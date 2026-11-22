"""分阶段的阵容搜索：在一个阶段的限制下反复找"对当前阵容库最强"的阵容，
在阵容库上求互相克制后的均衡分布，再对着这个分布量每张卡。

战斗是确定性的，两套阵容只打一场。阵容是一串 (角色编号, 装备编号)，从交战位往后排，装备 -1 表示不带。
"""

import json
import random
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from autochess_tools import data
from autochess_tools.sim import engine

type Unit = tuple[int, int]
type Lineup = tuple[Unit, ...]

MAX_UNITS = 7


@dataclass(frozen=True)
class Stage:
    """对局的一个阶段：角色和装备的最高星、几种卡位选择（卡位数, 角色加装备的总星上限）、装备件数上限。"""

    name: str
    max_star: int
    options: tuple[tuple[int, int], ...]
    max_equips: int
    copies: tuple[int, int] = (3, 2)
    """同名角色的张数上限：（5★ 以下, 5★），0 是不限；装备不限"""


STAGES = [
    Stage("开局", 2, ((4, 7), (5, 6)), 2),
    Stage("前期", 2, ((4, 9), (5, 8)), 3),
    Stage("前中期", 3, ((4, 16), (5, 15), (6, 14)), 4),
    Stage("中期", 4, ((5, 23), (6, 21), (7, 18)), 4),
    Stage("中后期", 5, ((5, 29), (6, 27), (7, 24)), 5),
    Stage("后期", 5, ((6, 35), (7, 32)), 5),
]


class Cards:
    """引擎里的卡牌编号，以及某个阶段能用的角色、装备（不含经济卡）。"""

    def __init__(self, changed: Sequence[data.Card] = (), banned: Sequence[str] = ()) -> None:
        """changed：临时改过的卡（同 id 覆盖原卡）；banned：这次不让用的卡。都不动正式数据。"""
        self.engine = engine(list(changed) or None)
        self.ids: list[str] = self.engine.ids()
        cards = data.cards() | {c["id"]: c for c in changed}
        self.star = [cards[i]["star"] for i in self.ids]
        self.kind = [cards[i]["type"] for i in self.ids]
        self.usable = [not data.economy(i) and i not in banned for i in self.ids]

    def pool(self, kind: str, max_star: int) -> list[int]:
        return [k for k in range(len(self.ids)) if self.kind[k] == kind and self.usable[k] and self.star[k] <= max_star]

    def name(self, k: int) -> str:
        return data.name(self.ids[k])

    def show(self, lineup: Lineup) -> str:
        return " / ".join(self.name(c) + (f"+{self.name(e)}" if e >= 0 else "") for c, e in lineup)


@dataclass
class Space:
    """一个阶段里的合法阵容，以及随机生成、变异。"""

    cards: Cards
    stage: Stage
    rng: random.Random
    chars: list[int] = field(init=False)
    equips: list[int] = field(init=False)

    def __post_init__(self) -> None:
        self.chars = self.cards.pool("character", self.stage.max_star)
        self.equips = self.cards.pool("equipment", self.stage.max_star)
        self._chars_by_star = {s: [c for c in self.chars if self.cards.star[c] == s] for s in range(1, 6)}
        self._equips_by_star = {s: [e for e in self.equips if self.cards.star[e] == s] for s in range(1, 6)}
        self._allowed = set(self.chars) | set(self.equips) | {-1}

    def stars(self, lineup: Lineup) -> int:
        star = self.cards.star
        return sum(star[c] + (star[e] if e >= 0 else 0) for c, e in lineup)

    def legal(self, lineup: Lineup) -> bool:
        if not lineup or sum(e >= 0 for _, e in lineup) > self.stage.max_equips:
            return False
        if any(c not in self._allowed or e not in self._allowed for c, e in lineup):
            return False
        used = [c for c, _ in lineup]
        if any(used.count(c) > self.limit(c) for c in set(used)):
            return False
        total = self.stars(lineup)
        return any(len(lineup) <= slots and total <= budget for slots, budget in self.stage.options)

    def limit(self, char: int) -> int:
        """同一个角色最多上几张。"""
        low, top = self.stage.copies
        return (top if self.cards.star[char] == 5 else low) or MAX_UNITS

    def option(self, lineup: Lineup) -> int:
        """这套阵容属于哪一档卡位：能容下它的最小卡位数。"""
        total = self.stars(lineup)
        return min(slots for slots, budget in self.stage.options if len(lineup) <= slots and total <= budget)

    def repair(self, lineup: Lineup, keep: int = -1) -> Lineup | None:
        """超出限制时随机降星、去掉装备、去掉角色，直到合法；keep 是不能动的卡。"""
        units = list(lineup)
        star = self.cards.star
        max_slots = max(slots for slots, _ in self.stage.options)
        for _ in range(60):
            current = tuple(units)
            if self.legal(current):
                return current
            i = self.rng.randrange(len(units))
            c, e = units[i]
            move = self.rng.random()
            if [x for x, _ in units].count(c) > self.limit(c):
                units[i] = (self.rng.choice(self._chars_by_star[star[c]]), e)
                continue
            if len(units) > max_slots or (move < 0.15 and len(units) > 1):
                if keep not in (c, e):
                    del units[i]
            elif e >= 0 and e != keep and move < 0.55:
                lower = [x for s in range(1, star[e]) for x in self._equips_by_star[s]]
                units[i] = (c, self.rng.choice(lower) if lower and self.rng.random() < 0.7 else -1)
            elif c != keep and star[c] > 1:
                lower = [x for s in range(1, star[c]) for x in self._chars_by_star[s]]
                units[i] = (self.rng.choice(lower), e)
        return None

    def random_lineup(self, keep: int = -1) -> Lineup:
        while True:
            slots, _ = self.rng.choice(self.stage.options)
            units: list[Unit] = [(self.rng.choice(self.chars), -1) for _ in range(slots)]
            for i in self.rng.sample(range(slots), min(slots, self.rng.randint(0, self.stage.max_equips))):
                units[i] = (units[i][0], self.rng.choice(self.equips))
            if keep >= 0:
                i = self.rng.randrange(slots)
                units[i] = (keep, units[i][1]) if self.cards.kind[keep] == "character" else (units[i][0], keep)
            lineup = self.repair(tuple(units), keep)
            if lineup is not None and (keep < 0 or contains(lineup, keep)):
                return lineup


def contains(lineup: Lineup, card: int) -> bool:
    return any(card in unit for unit in lineup)


def to_array(lineups: Sequence[Lineup]) -> np.ndarray:
    out = np.full((len(lineups), MAX_UNITS, 2), -1, dtype=np.int32)
    for k, lineup in enumerate(lineups):
        out[k, : len(lineup)] = lineup
    return out


def scores(cards: Cards, mine: Sequence[Lineup], theirs: Sequence[Lineup]) -> np.ndarray:
    """mine 里每套对 theirs 里每套的得分矩阵：胜 1、平 0.5、负 0。"""
    return np.asarray(cards.engine.cross(to_array(mine), to_array(theirs)))


def equilibrium(payoff: np.ndarray, iterations: int = 4000) -> np.ndarray:
    """对称零和博弈的均衡分布（regret matching+，线性加权平均）。payoff[i][j] 是 i 对 j 的得分。"""
    m = payoff - 0.5
    n = len(m)
    regret = np.zeros(n)
    x = np.full(n, 1.0 / n)
    total = np.zeros(n)
    for t in range(1, iterations + 1):
        u = m @ x
        regret = np.maximum(regret + u - x @ u, 0.0)
        s = regret.sum()
        x = regret / s if s > 0 else np.full(n, 1.0 / n)
        total += t * x
    return total / total.sum()


@dataclass
class Meta:
    """一个阶段的阵容库、得分矩阵和均衡分布。"""

    space: Space
    pool: list[Lineup] = field(default_factory=list)
    payoff: np.ndarray = field(default_factory=lambda: np.zeros((0, 0)))
    mix: np.ndarray = field(default_factory=lambda: np.zeros(0))

    def add(self, lineups: Sequence[Lineup]) -> int:
        known = set(self.pool)
        new = [x for x in dict.fromkeys(lineups) if x not in known]
        if not new:
            return 0
        cards = self.space.cards
        old = len(self.pool)
        self.pool += new
        payoff = np.zeros((len(self.pool), len(self.pool)))
        payoff[:old, :old] = self.payoff
        payoff[old:, :] = scores(cards, new, self.pool)
        payoff[:old, old:] = 1.0 - payoff[old:, :old].T
        self.payoff = payoff
        return len(new)

    def solve(self) -> None:
        self.mix = equilibrium(self.payoff)

    def opponents(self, mass: float = 0.995, cap: int = 600) -> tuple[list[Lineup], np.ndarray]:
        """均衡分布里权重最大的那些阵容（占到 mass 为止，最多 cap 套），权重重新归一。
        cap 要盖住均衡里实际在用的阵容：取得不全时，库里已有的阵容对这部分对手能打出虚高的得分，
        搜索会一直停不下来（后期均衡分散到 800 套时，cap=200 只占八成权重，出过这个问题）。"""
        order = np.argsort(-self.mix)
        cut = int(np.searchsorted(np.cumsum(self.mix[order]), mass)) + 1
        chosen = order[: min(cut, cap)]
        weights = self.mix[chosen]
        return [self.pool[i] for i in chosen], weights / weights.sum()

    def climb(
        self, starts: Sequence[Lineup], keeps: Sequence[int], steps: int, mutations: int
    ) -> tuple[list[Lineup], np.ndarray]:
        """每个起点做爬山：每步试 mutations 个变异，对均衡分布的得分不降就换过去。keeps 是各起点必须带的卡（-1 不限）。
        在 Rust 里并行做（engine/py/src/search.rs，阵容规则和 Space 相同）。"""
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
            [space.limit(c) if cards.kind[c] == "character" else MAX_UNITS for c in range(len(cards.ids))],
            list(space.stage.options),
            space.stage.max_equips,
        )
        units = np.asarray(cells).reshape(len(starts), MAX_UNITS, 2).tolist()
        found = [tuple((c, e) for c, e in lineup if c >= 0) for lineup in units]
        assert all(space.legal(x) for x in found)
        return found, np.array(value)

    def grow(self, rounds: int, climbers: int = 96, steps: int = 25, mutations: int = 24, log=print) -> None:
        """反复：求均衡 → 找对均衡分布最强的阵容 → 加进库。"""
        rng = self.space.rng
        for r in range(rounds):
            self.solve()
            opponents, weights = self.opponents()
            # 起点三种：均衡里的阵容、库里对均衡分布得分最高的阵容、随机阵容
            starts = rng.choices(opponents, weights=list(weights), k=climbers // 3)
            starts += [self.pool[i] for i in np.argsort(-(self.payoff @ self.mix))[: climbers // 3]]
            starts += [self.space.random_lineup() for _ in range(climbers - len(starts))]
            found, value = self.climb(starts, [-1] * len(starts), steps, mutations)
            order = np.argsort(-value)
            good = [found[i] for i in order if value[i] > 0.5 + 1e-9][:40]
            added = self.add(good)
            log(
                f"  第 {r + 1} 轮：均衡里 {len(opponents)} 套，最强回应 {value[order[0]]:.3f}，"
                f"加入 {added} 套，库 {len(self.pool)}"
            )
            if value[order[0]] < 0.52 and r >= 3:
                break
        self.solve()

    def forced(
        self, per_card: int = 8, steps: int = 30, mutations: int = 12, previous: dict[int, float] | None = None
    ) -> dict[int, tuple[float, Lineup]]:
        """每张卡：必须带它的最强阵容对均衡分布的得分。
        均衡里已经出场的卡（得分按定义在 0.5 附近）只用 2 个起点复查；
        previous 是上一次的得分，给了的话，上次明显偏低（< 0.47）的卡也只用 2 个起点。"""
        space = self.space
        targets = space.chars + space.equips
        opponents, weights = self.opponents()
        starts, keeps = [], []
        ranked = np.argsort(-(self.payoff @ self.mix))
        for card in targets:
            in_mix = sum(w for x, w in zip(opponents, weights, strict=True) if contains(x, card)) >= 0.01
            count = 2 if in_mix or (previous is not None and previous.get(card, 1.0) < 0.47) else per_card
            # 起点一半是库里带这张卡、对均衡分布得分最高的阵容（保证结果不低于库里已有的）
            known = [self.pool[i] for i in ranked if contains(self.pool[i], card)][: count // 2]
            starts += known
            keeps += [card] * len(known)
            # 其余：把这张卡塞进均衡里的阵容（随机阵容对着强环境得分全是 0，爬不动）
            for base in space.rng.choices(opponents, weights=list(weights), k=count - len(known)):
                units = list(base)
                i = space.rng.randrange(len(units))
                units[i] = (card, units[i][1]) if space.cards.kind[card] == "character" else (units[i][0], card)
                start = space.repair(tuple(units), card)
                starts.append(start if start is not None and contains(start, card) else space.random_lineup(card))
                keeps.append(card)
        found, value = self.climb(starts, keeps, steps, mutations)
        result: dict[int, tuple[float, Lineup]] = {}
        for card, score, lineup in zip(keeps, value, found, strict=True):
            if card not in result or score > result[card][0]:
                result[card] = (float(score), lineup)
        return result


def build(
    stage: Stage,
    seed: int = 1,
    initial: int = 300,
    rounds: int = 40,
    log=print,
    cards: Cards | None = None,
    warm: Sequence[Sequence[Sequence[str]]] = (),
) -> Meta:
    """warm：上一次结果里的阵容（卡牌 id），作为起点；数值变了也能用，得分会重新算。"""
    space = Space(cards or Cards(), stage, random.Random(seed))
    meta = Meta(space)
    index = {card: k for k, card in enumerate(space.cards.ids)}
    known = [tuple((index[c], index[e] if e else -1) for c, e in lineup) for lineup in warm]
    known = [x for x in known if space.legal(x)]
    if known:
        log(f"  从上一次的 {len(known)} 套阵容出发")
    meta.add(known + [space.random_lineup() for _ in range(initial)])
    meta.grow(rounds, log=log)
    # 带卡搜索能找到整体搜索漏掉的强阵容：并回库里再搜，直到带卡搜索也找不到明显占优的
    previous = None
    for _ in range(20):
        forced = meta.forced(previous=previous)
        previous = {card: value for card, (value, _) in forced.items()}
        strong = [lineup for value, lineup in forced.values() if value >= 0.52]
        if not strong or not meta.add(strong):
            break
        log(f"  带卡搜索找到 {len(strong)} 套得分不低于 0.52 的阵容，并回库里再搜")
        meta.grow(rounds, log=log)
    return meta


def keep(meta: Meta, limit: int = 600) -> list[list[list[str]]]:
    """留给下一次当起点的阵容：均衡里的，加上库里对均衡分布得分最高的，共 limit 套（卡牌 id）。"""
    ids = meta.space.cards.ids
    order = list(np.argsort(-meta.mix)[: int((meta.mix > 1e-4).sum())]) + list(np.argsort(-(meta.payoff @ meta.mix)))
    chosen = list(dict.fromkeys(int(i) for i in order))[:limit]
    return [[[ids[c], ids[e] if e >= 0 else ""] for c, e in meta.pool[i]] for i in chosen]


def save_pool(meta: Meta, directory: Path) -> Path:
    """把这次留下的阵容存成 <目录>/<阶段>.json，给以后当起点。"""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{meta.space.stage.name}.json"
    path.write_text(json.dumps(keep(meta), ensure_ascii=False))
    return path


def load_pools(directories: Iterable[Path], stage: str) -> list[list[list[str]]]:
    """几个目录里这个阶段存下的阵容（<阶段>.json 和 <阶段>-*.json），合在一起。
    起点要并上前几轮的阵容库：搜索依赖起点，从库里消失的组合不容易再找回来。"""
    lineups: list[list[list[str]]] = []
    for directory in directories:
        for path in sorted([*directory.glob(f"{stage}.json"), *directory.glob(f"{stage}-*.json")]):
            lineups += json.loads(path.read_text())
    return lineups
