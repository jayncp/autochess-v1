"""按金币约束搜索阵容（带卡牌觉醒）：第 N 回合，期望花费不超过预算的阵容里，互相克制后的均衡。
方法和结论见 docs/plans/gold-search.md。

用法（在 tools/ 下）：
  uv run --group balance python -m autochess_tools.balance.gold run <回合> [--minutes N] [--threads N] [--fresh]
  uv run --group balance python -m autochess_tools.balance.gold report <回合> [--forced] [--threads N]

run：每一轮（求均衡 → 找最强回应 → 加进阵容库）结束都存盘（balance/runs/gold/<回合>.json），再跑会接着上次的；
     到时间、收到中断信号（Ctrl-C）时跑完当前这一轮就停；收敛后做带卡搜索，找不到更强的就算完成。--fresh 从头来。
report：从存盘出报告（Markdown，标准输出），搜索还在跑也可以出；--forced 加上每张卡的带卡得分（慢）。

阵容的规则（`GoldSpace`，和 engine/py/src/search.rs 的 `Gold` 一一对应）：
- 最多 7 个角色；同名的普通角色最多 2 张，觉醒的角色按 3 张原卡算，用的张数不超过牌库；
- 凑齐的期望花费（含升到能上这么多人的等级）不超过预算。
觉醒的卡由 autochess_tools.awaken 生成，是另一张卡（id 加 _awakened），报告里写成"卡名*"。
"""

import argparse
import json
import os
import random
import signal
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from autochess_tools import data
from autochess_tools.awaken import SUFFIX, TEMPLATES, awakened
from autochess_tools.balance import DATA
from autochess_tools.balance.meta import MAX_UNITS, STAGES, Cards, Lineup, Meta, Space, Stage, load_pools, to_array
from autochess_tools.economy.model import KINDS, Economy, load, prices
from autochess_tools.sim import engine

BUDGETS = {5: 55, 8: 115, 11: 165, 14: 220, 17: 265, 20: 310}
"""第几回合 -> 预算：期望花费这么多的阵容平均在这个回合凑齐（按回合发钱的模拟标定）"""
OUT = DATA / "runs" / "gold"
INF = float("inf")


class GoldCards(Cards):
    """正式数据的卡加上全部角色的觉醒版。"""

    def __init__(self, rule: tuple[float, float, float] | Path = (2, 2, 2)) -> None:
        """rule：觉醒后战力、基础技能、特殊技能的倍数（见 awaken.awakened）；
        或者一个文件 {角色 id: 三个倍数}，各卡用各自的觉醒方案。"""
        cards = data.cards()
        chosen = json.loads(rule.read_text()) if isinstance(rule, Path) else {}
        extra = [
            awakened(card, *(chosen[i] if isinstance(rule, Path) else rule))
            for i, card in cards.items()
            if card["type"] == "character"
        ]
        self.engine = engine(extra)
        self.ids = self.engine.ids()
        index = {card: k for k, card in enumerate(self.ids)}
        self.base = [index[i.removesuffix(SUFFIX)] for i in self.ids]
        """各卡的原卡编号（普通卡是它自己）"""
        self.twin = [-1] * len(self.ids)
        """角色的另一个形态（普通 ↔ 觉醒），没有是 -1"""
        for k, b in enumerate(self.base):
            if b != k:
                self.twin[k], self.twin[b] = b, k
        self.star = [cards[self.ids[b]]["star"] for b in self.base]
        self.kind = [cards[self.ids[b]]["type"] for b in self.base]
        self.usable = [not data.economy(self.ids[b]) for b in self.base]

    def awake(self, k: int) -> bool:
        return self.base[k] != k

    def name(self, k: int) -> str:
        return data.name(self.ids[self.base[k]]) + ("*" if self.awake(k) else "")


@dataclass
class GoldSpace(Space):
    """一个回合档里的合法阵容。"""

    cards: GoldCards  # ty: ignore[invalid-mutable-override]
    eco: Economy = field(default_factory=load)
    budget: float = 0.0

    def __post_init__(self) -> None:
        super().__post_init__()
        self.prices = prices(self.eco)
        self._cost: dict[tuple, float] = {}
        self._normal = {
            kind: {s: [c for c in pool if self.cards.star[c] == s and not self.cards.awake(c)] for s in range(1, 6)}
            for kind, pool in (("character", self.chars), ("equipment", self.equips))
        }

    def wants(self, lineup: Lineup) -> tuple[tuple[int, int, int], ...] | None:
        """要凑的卡（类型, 星级, 张数）；同名的规则不满足时没有。"""
        cards = self.cards
        need: Counter[int] = Counter()
        normal: Counter[int] = Counter()
        for c, e in lineup:
            base = cards.base[c]
            need[base] += 3 if cards.awake(c) else 1
            normal[base] += not cards.awake(c)
            if e >= 0:
                need[e] += 1
        if any(n > 2 for n in normal.values()):
            return None
        rows = [(KINDS.index(cards.kind[k]), cards.star[k], n) for k, n in need.items()]
        if any(n > self.eco.copies[kind][star - 1] for kind, star, n in rows):
            return None
        return tuple(sorted(rows))

    def cost(self, lineup: Lineup) -> float:
        """凑齐的期望花费；不合规则是无穷大。"""
        wants = self.wants(lineup)
        if wants is None or not 0 < len(lineup) <= MAX_UNITS:
            return INF
        key = (wants, len(lineup))
        if key not in self._cost:
            self._cost[key] = self.prices.costs([key])[0]
        return self._cost[key]

    def legal(self, lineup: Lineup) -> bool:
        return self.cost(lineup) <= self.budget

    def repair(self, lineup: Lineup, keep: int = -1) -> Lineup | None:
        """超预算时随机取消觉醒、降低或去掉装备、降星、去掉角色，直到合法；keep 是不能动的卡。"""
        units = list(lineup)
        cards, rng = self.cards, self.rng
        for _ in range(200):
            current = tuple(units)
            if self.legal(current):
                return current
            if not units:
                return None
            i = rng.randrange(len(units))
            c, e = units[i]
            move = rng.random()
            if len(units) <= MAX_UNITS and self.wants(current) is None:
                if c != keep:
                    units[i] = (rng.choice(self._normal["character"][cards.star[c]]), e)
                continue
            fixed = keep in (c, e)
            if len(units) > MAX_UNITS or (move < 0.15 and len(units) > 1):
                if not fixed:
                    del units[i]
            elif cards.awake(c) and c != keep and move < 0.5:
                units[i] = (cards.twin[c], e)
            elif e >= 0 and e != keep and move < 0.75:
                lower = [x for s in range(1, cards.star[e]) for x in self._normal["equipment"][s]]
                units[i] = (c, rng.choice(lower) if lower and rng.random() < 0.7 else -1)
            elif c != keep and cards.star[c] > 1:
                units[i] = (rng.choice([x for s in range(1, cards.star[c]) for x in self._normal["character"][s]]), e)
            elif not fixed and len(units) > 1:
                del units[i]
        return None

    def random_lineup(self, keep: int = -1) -> Lineup:
        rng = self.rng
        for _ in range(50):
            units = [(rng.choice(self.chars), -1) for _ in range(rng.randint(1, MAX_UNITS))]
            for i in rng.sample(range(len(units)), rng.randint(0, len(units))):
                units[i] = (units[i][0], rng.choice(self.equips))
            if keep >= 0:
                i = rng.randrange(len(units))
                units[i] = (keep, units[i][1]) if self.cards.kind[keep] == "character" else (units[i][0], keep)
            lineup = self.repair(tuple(units), keep)
            if lineup is not None and (keep < 0 or any(keep in unit for unit in lineup)):
                return lineup
        return self.alone(keep)

    def alone(self, card: int) -> Lineup:
        """只带这一张卡的最便宜的阵容（装备配一个 1★ 角色）。"""
        cheapest = self._normal["character"][1][0]
        if card < 0:
            return ((cheapest, -1),)
        return ((card, -1),) if self.cards.kind[card] == "character" else ((cheapest, card),)

    def targets(self) -> list[int]:
        """这个预算下单独拿得出来的卡。"""
        return [card for card in self.chars + self.equips if self.legal(self.alone(card))]


class GoldMeta(Meta):
    space: GoldSpace  # ty: ignore[invalid-mutable-override]

    def climb(self, starts, keeps, steps, mutations):
        cards, space = self.space.cards, self.space
        opponents, weights = self.opponents()
        cells, value = cards.engine.climb(
            to_array(starts),
            list(keeps),
            to_array(opponents),
            [float(w) for w in weights],
            steps,
            mutations,
            space.rng.getrandbits(63),
            space.chars,
            space.equips,
            cards.star,
            [],
            [],
            0,
            (space.prices, space.budget, cards.base, cards.twin),
        )
        units = np.asarray(cells).reshape(len(starts), MAX_UNITS, 2).tolist()
        found = [tuple((c, e) for c, e in lineup if c >= 0) for lineup in units]
        assert all(space.legal(x) for x in found), "Rust 和 Python 的阵容规则不一致"
        return found, np.array(value)


def space_for(turn: int, seed: int, rule: tuple[float, float, float] | Path = (2, 2, 2)) -> GoldSpace:
    stage = Stage(f"第 {turn} 回合", 5, (), MAX_UNITS)
    return GoldSpace(GoldCards(rule), stage, random.Random(seed), budget=BUDGETS[turn])


def first_pool(space: GoldSpace) -> list[Lineup]:
    """起点：原来六个阶段的阵容压到预算内，把其中一个角色换成觉醒的版本，再加随机阵容。"""
    cards, rng = space.cards, space.rng
    index = {card: k for k, card in enumerate(cards.ids)}
    old = [x for stage in STAGES for x in load_pools([DATA / "pools"], stage.name)]
    known = [tuple((index[c], index[e] if e else -1) for c, e in x) for x in rng.sample(old, min(len(old), 800))]
    fitted = [x for x in (space.repair(lineup) for lineup in known) if x is not None]
    awake = []
    for lineup in rng.sample(fitted, min(len(fitted), 400)):
        i = rng.randrange(len(lineup))
        twin = cards.twin[lineup[i][0]]
        changed = space.repair((*lineup[:i], (twin, lineup[i][1]), *lineup[i + 1 :]), twin)
        if changed is not None:
            awake.append(changed)
    return list(dict.fromkeys(fitted + awake + [space.random_lineup() for _ in range(200)]))


def read(path: Path) -> dict:
    return json.loads(path.read_text()) if path.exists() else {"pool": [], "tops": [], "seconds": 0.0, "done": False}


def restore(space: GoldSpace, state: dict) -> GoldMeta:
    index = {card: k for k, card in enumerate(space.cards.ids)}
    meta = GoldMeta(space)
    meta.add([tuple((index[c], index[e] if e else -1) for c, e in x) for x in state["pool"]])
    return meta


def write(path: Path, meta: GoldMeta, state: dict) -> None:
    ids = meta.space.cards.ids
    state["pool"] = [[[ids[c], ids[e] if e >= 0 else ""] for c, e in x] for x in meta.pool]
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False))
    temporary.replace(path)


def run(turn: int, minutes: float, seed: int, fresh: bool, out: Path, rule: tuple[float, float, float] | Path) -> None:
    path = out / f"{turn}.json"
    state = read(Path("/nonexistent") if fresh else path)
    space = space_for(turn, seed + len(state["tops"]), rule)
    stop = False

    def halt(*_) -> None:
        nonlocal stop
        stop = True
        log("  收到中断，跑完这一轮就停")

    def log(text: str) -> None:
        print(text, file=sys.stderr, flush=True)

    signal.signal(signal.SIGINT, halt)
    signal.signal(signal.SIGTERM, halt)
    start = time.time()
    if state["pool"]:
        meta = restore(space, state)
        log(f"第 {turn} 回合（预算 {space.budget:.0f}）：接着上次的 {len(meta.pool)} 套、{len(state['tops'])} 轮")
    else:
        meta = GoldMeta(space)
        meta.add(first_pool(space))
        log(f"第 {turn} 回合（预算 {space.budget:.0f}）：从 {len(meta.pool)} 套起点开始")
    previous = None
    while not stop and time.time() - start < minutes * 60 and not state["done"]:
        began = time.time()
        top = meta.grow(1, log=lambda _: None)
        state["tops"].append(round(top, 4))
        state["seconds"] += time.time() - began
        write(path, meta, state)
        log(f"  第 {len(state['tops'])} 轮：最强回应 {top:.3f}，库 {len(meta.pool)}，{time.time() - began:.0f} 秒")
        if top >= 0.52 or len(state["tops"]) < 4:
            continue
        # 整体搜索找不到明显占优的了：带卡搜索再找一遍，找到就并回库里接着搜
        began = time.time()
        forced = meta.forced(previous=previous, targets=space.targets())
        previous = {card: value for card, (value, _) in forced.items()}
        strong = [lineup for value, lineup in forced.values() if value >= 0.52]
        added = meta.add(strong)
        state["seconds"] += time.time() - began
        state["done"] = not added
        write(path, meta, state)
        log(f"  带卡搜索：{len(strong)} 套得分不低于 0.52，加入 {added} 套，{time.time() - began:.0f} 秒")
    log("搜索完成" if state["done"] else f"停在第 {len(state['tops'])} 轮，再跑会接着来")


def report(turn: int, forced: bool, out: Path, rule: tuple[float, float, float] | Path) -> None:
    state = read(out / f"{turn}.json")
    if not state["pool"]:
        raise SystemExit(f"还没有第 {turn} 回合的存盘")
    space = space_for(turn, 1, rule)
    cards, eco = space.cards, space.eco
    meta = restore(space, state)
    meta.solve()
    lineups, weights = meta.opponents(mass=0.999, cap=3000)
    tops = state["tops"]
    print(f"\n## 第 {turn} 回合（预算 {space.budget:.0f} 金币）\n")
    if isinstance(rule, Path):
        print(f"觉醒：各卡按各自的方案（{rule.name}）。\n")
    else:
        print(f"觉醒：战力 ×{rule[0]:g}，基础技能 ×{rule[1]:g}，特殊技能 ×{rule[2]:g}。\n")
    print(
        f"搜索了 {len(tops)} 轮、{state['seconds'] / 60:.0f} 分钟，{'已完成' if state['done'] else '未完成'}；"
        f"最近几轮最强回应的得分 {'、'.join(f'{t:.3f}' for t in tops[-5:])}（越接近 0.5 越收敛）。"
    )
    print(
        f"阵容库 {len(meta.pool)} 套，均衡分布里 {len(lineups)} 套（按权重折算 {1 / (weights**2).sum():.0f} 套），"
        f"权重最大的一套占 {weights.max():.1%}。\n"
    )

    print("**均衡里权重最大的阵容**（花费 / 人数）\n")
    for i in np.argsort(-weights)[:15]:
        x = lineups[i]
        print(f"- {weights[i]:.1%}　{space.cost(x):.0f} 金币，{len(x)} 人　{cards.show(x)}")

    def mean(value) -> float:
        return float(sum(w * value(x) for x, w in zip(lineups, weights, strict=True)))

    def awakened_in(x: Lineup) -> int:
        return sum(cards.awake(c) for c, _ in x)

    def price(x: Lineup) -> int:
        return sum(star * n for _, star, n in space.wants(x) or ())

    print("\n**平均一套**：", end="")
    print(
        f"{mean(len):.1f} 人，角色平均 {mean(lambda x: sum(cards.star[c] for c, _ in x) / len(x)):.1f} 星，"
        f"装备 {mean(lambda x: sum(e >= 0 for _, e in x)):.1f} 件，觉醒 {mean(awakened_in):.2f} 张"
        f"（不带觉醒的阵容占 {mean(lambda x: awakened_in(x) == 0):.0%}）；"
        f"花费 {mean(space.cost):.0f} 金币，其中买卡 {mean(price):.0f}，"
        f"升级和刷新 {mean(space.cost) - mean(price):.0f}。"
    )
    print("\n**人数**（要的等级）：", end="")
    by_size = Counter()
    for x, w in zip(lineups, weights, strict=True):
        by_size[len(x)] += w
    print("、".join(f"{n} 人（{eco.level_for(n)} 级）{by_size[n]:.0%}" for n in sorted(by_size)))

    print("\n**觉醒和最高星**：行是一套里觉醒的张数，列是这一套里角色的最高星，格子是在均衡里的占比\n")
    table: dict[tuple[int, int], float] = defaultdict(float)
    for x, w in zip(lineups, weights, strict=True):
        table[min(awakened_in(x), 3), max(cards.star[c] for c, _ in x)] += w
    print("| 觉醒 | 最高 1★ | 2★ | 3★ | 4★ | 5★ | 合计 |\n|---|---|---|---|---|---|---|")
    for count, label in enumerate(("没有", "1 张", "2 张", "3 张以上")):
        row = [table[count, star] for star in range(1, 6)]
        print(f"| {label} | " + " | ".join(f"{v:.0%}" if v >= 0.005 else "" for v in row) + f" | {sum(row):.0%} |")
    by_star = [mean(lambda x, s=s: sum(cards.awake(c) and cards.star[c] == s for c, _ in x)) for s in range(1, 6)]
    print("\n各星级觉醒的平均张数：" + "、".join(f"{s}★ {v:.2f}" for s, v in enumerate(by_star, 1)))

    usage: dict[int, float] = defaultdict(float)
    for x, w in zip(lineups, weights, strict=True):
        for card in {k for unit in x for k in unit if k >= 0}:
            usage[card] += w
    score = meta.forced(targets=space.targets()) if forced else {}

    def best(card: int) -> str:
        return f"{score[card][0]:.3f}" if card in score else "买不起" if forced else ""

    def lineup(card: int) -> str:
        return cards.show(score[card][1]) if card in score else ""

    either: dict[int, float] = defaultdict(float)
    for x, w in zip(lineups, weights, strict=True):
        for card in {cards.base[c] for c, _ in x}:
            either[card] += w
    print("\n**角色**：出场率是均衡分布里带这张卡的阵容占比，普通和觉醒分开，合计是带任一形态的", end="")
    print("；带卡最优是必须带它时最强阵容对均衡分布的得分（0.5 为持平）\n" if forced else "\n")
    extra = (" 带卡最优 | 觉醒带卡最优 | 带卡最强阵容 | 觉醒带卡最强阵容 |", "---|---|---|---|") if forced else ("", "")
    print("| 卡 | 星 | 普通 | 觉醒 | 合计 |" + extra[0])
    print("|---|---|---|---|---|" + extra[1])
    normal = [c for c in space.chars if not cards.awake(c)]
    for card in sorted(normal, key=lambda c: (cards.star[c], -either[c])):
        twin = cards.twin[card]
        row = (
            f"| {cards.name(card)} | {cards.star[card]} | {usage[card]:.1%} | {usage[twin]:.1%} | {either[card]:.1%} |"
        )
        print(row + (f" {best(card)} | {best(twin)} | {lineup(card)} | {lineup(twin)} |" if forced else ""))
    print("\n**装备**\n\n| 卡 | 星 | 出场率 |" + (" 带卡最优 | 带卡最强阵容 |" if forced else ""))
    print("|---|---|---|" + ("---|---|" if forced else ""))
    for card in sorted(space.equips, key=lambda c: (cards.star[c], -usage[c])):
        row = f"| {cards.name(card)} | {cards.star[card]} | {usage[card]:.1%} |"
        print(row + (f" {best(card)} | {lineup(card)} |" if forced else ""))


def main() -> None:
    parser = argparse.ArgumentParser(description="按金币约束搜索阵容")
    parser.add_argument("command", choices=["run", "report"])
    parser.add_argument("turn", type=int, choices=sorted(BUDGETS), help="第几回合")
    parser.add_argument("--minutes", type=float, default=30, help="run：最多跑多久")
    parser.add_argument("--threads", type=int, default=max(1, (os.cpu_count() or 2) // 2), help="默认一半核心")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--fresh", action="store_true", help="run：不接着上次的，从头来")
    parser.add_argument("--forced", action="store_true", help="report：加上每张卡的带卡得分")
    parser.add_argument("--out", type=Path, default=OUT, help="存盘的目录；换觉醒方案时要换一个目录")
    parser.add_argument("--templates", type=Path, default=TEMPLATES, help="各卡的觉醒方案 {角色 id: 三个倍数}")
    parser.add_argument("--uniform", type=float, nargs=3, metavar="倍数", help="不用方案文件，全部角色用同样的三个倍数")
    args = parser.parse_args()
    # 模拟用 rayon 的全局线程池，第一次用之前定下线程数；求均衡用 numpy，线程给多了反而抢核心
    os.environ["RAYON_NUM_THREADS"] = str(args.threads)
    rule = tuple(args.uniform) if args.uniform else args.templates
    if args.command == "run":
        run(args.turn, args.minutes, args.seed, args.fresh, args.out, rule)
    else:
        report(args.turn, args.forced, args.out, rule)


if __name__ == "__main__":
    main()
