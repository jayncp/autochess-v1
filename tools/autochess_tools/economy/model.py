"""凑齐一套阵容的花费。

规则（单人，表格 docs/design/economic-system.xlsx）：
- 商店每次刷新出若干个角色格、装备格；每格先按等级的概率定星级，再从牌库里这个星级剩下的牌中均匀抽一张。
  自己手里的、商店里摆着的都不在牌库里。
- 刷新一次 1 金币，1 金币买 1 点经验，卡的价格等于星级；上阵人数上限随等级变。
- 每回合自动得金币、经验，商店免费刷新一次。

两种算法：
- `plan`：动态规划，算"只看金币"的最小期望花费（不算每回合白送的经验和刷新），并给出每个状态该升级还是该刷新。
  状态是（等级，每种要的卡还缺几张）；一次刷新按格子一个一个结算。商店里同时摆出来的牌互相挤占牌库这一点忽略不计
  （模拟里是照实抽的，用来对答案）。
- `simulate`：照规则真的抽卡，按 `plan` 的决定花钱。`timed=False` 只数花了多少金币；
  `timed=True` 按回合发金币、经验和利息，得到第几回合凑齐。`reserve` 是存钱的打法：手里留这么多金币吃利息，
  多出来的才拿去升级、刷新（想要的卡出现了照买）；等手里的钱够把剩下的一次凑齐（按 `plan` 的期望）就全部花掉。
  拿天赋的回合直接多给金币（一局按表格的概率抽一种天赋组合）；拍卖的回合，阵容里还缺这个类型、这个星级的卡就按卡价买到一张（不算和别人竞价）。
"""

import random
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass
from itertools import product
from pathlib import Path

import openpyxl
from autochess_engine import Prices

from autochess_tools import data

WORKBOOK = data.REPO / "docs" / "design" / "economic-system.xlsx"
MAX_LEVEL = 7
KINDS = ("character", "equipment")
INF = float("inf")


@dataclass(frozen=True)
class Economy:
    odds: tuple[tuple[float, ...], ...]
    """odds[等级-1][星级-1]"""
    slots: tuple[int, ...]
    """各等级的上阵人数上限"""
    xp: tuple[int, ...]
    """xp[等级-1]：升到下一级要的经验"""
    kinds: tuple[tuple[int, ...], tuple[int, ...]]
    """各星级的种类数：(角色, 装备)"""
    copies: tuple[tuple[int, ...], tuple[int, ...]]
    """各星级每种牌的张数：(角色, 装备)"""
    shop: tuple[int, int]
    """商店里的格子数：(角色, 装备)"""
    round_xp: int
    round_gold: int
    start_gold: int
    refresh: int
    interest: tuple[tuple[int, int], ...]
    """利息：(手里的金币达到多少, 回合结束多给几个)，从低到高"""
    auctions: tuple[tuple[int, int, int], ...]
    """拍卖：(第几回合, 类型 0 角色 / 1 装备, 星级)"""
    talents: tuple[int, ...]
    """拿天赋的回合"""
    talent_sets: tuple[tuple[float, tuple[int, ...]], ...]
    """天赋组合：(概率, 各次天赋折合的金币)，一局抽一种"""

    def interest_on(self, gold: int) -> int:
        return max((amount for least, amount in self.interest if gold >= least), default=0)

    def level_for(self, units: int) -> int:
        """能上 units 个角色的最低等级。"""
        return next(level for level in range(1, MAX_LEVEL + 1) if self.slots[level - 1] >= units)

    def xp_between(self, low: int, high: int) -> int:
        return sum(self.xp[low - 1 : high - 1])


def load(path: Path = WORKBOOK) -> Economy:
    book = openpyxl.load_workbook(path, data_only=False)
    ws, pvp = book["等级和卡池"], book["PVP"]
    interest_row = next(r for r in range(1, pvp.max_row + 1) if pvp.cell(r, 1).value == "利息") + 1
    interest = []
    for c in range(1, pvp.max_column + 1):
        if pvp.cell(interest_row, c).value is not None:
            interest.append((pvp.cell(interest_row, c).value, pvp.cell(interest_row + 1, c).value))

    def block(title: str, rows: int) -> list[tuple]:
        """PVP 页里标题下面的几行，按列读成一组一组。"""
        top = next(r for r in range(1, pvp.max_row + 1) if pvp.cell(r, 1).value == title)
        top += pvp.cell(top, 2).value is None  # 标题单独占一行时，内容从下一行开始
        columns = [c for c in range(2, pvp.max_column + 1) if pvp.cell(top, c).value is not None]
        return [tuple(pvp.cell(top + k, c).value for k in range(rows)) for c in columns]

    auctions = tuple((turn, ("角色", "装备").index(kind), star) for turn, kind, star in block("拍卖", 3))
    talent_rows = block("天赋", 3)
    talents = tuple(turn for turn, _, _ in talent_rows)
    worth = {quality: gold for _, quality, gold in talent_rows}
    talent_sets = tuple(
        (float(chance), tuple(worth[q] for q in combo))
        for combo, chance in block("天赋组合", 2)
        if all(q in worth for q in combo)
    )
    assert abs(sum(chance for chance, _ in talent_sets) - 1) < 1e-9, "天赋组合的概率加起来要是 1"
    assert all(len(combo) == len(talents) for _, combo in talent_sets), "天赋组合的个数要和拿天赋的回合数一样"
    labels = {ws.cell(r, 1).value: r for r in range(1, ws.max_row + 1) if ws.cell(r, 1).value}

    def row(label: str, first: int, last: int) -> tuple:
        return tuple(ws.cell(labels[label], c).value for c in range(first, last + 1))

    stars = [f"{s}星" for s in range(1, 6)]
    by_level = [row(s, 2, 8) for s in stars]
    odds = tuple(tuple(float(by_level[s][level]) for s in range(5)) for level in range(MAX_LEVEL))
    assert all(abs(sum(o) - 1) < 1e-9 for o in odds), "每个等级的概率加起来要是 1"
    pools = [row(s, 10, 13) for s in stars]
    return Economy(
        odds=odds,
        slots=row("位置数量", 2, 8),
        xp=row("升至下一级经验", 2, 7),
        kinds=(tuple(p[0] for p in pools), tuple(p[2] for p in pools)),
        copies=(tuple(p[1] for p in pools), tuple(p[3] for p in pools)),
        shop=(ws.cell(labels["商店中角色数量"], 2).value, ws.cell(labels["商店中装备数量"], 2).value),
        round_xp=ws.cell(labels["每回合经验"], 2).value,
        round_gold=ws.cell(labels["每回合金币"], 2).value,
        start_gold=ws.cell(labels["初始金币"], 2).value,
        refresh=ws.cell(labels["刷新价格"], 2).value,
        interest=tuple(interest),
        auctions=auctions,
        talents=talents,
        talent_sets=talent_sets,
    )


def prices(eco: Economy) -> Prices:
    """Rust 版的期望花费（和 `Plan.cost` 相同，快得多，给搜索用）：
    `prices(eco).costs([(goal.cards, goal.units), ...])`。"""
    kinds, copies = ([[float(x) for x in stars] for stars in table] for table in (eco.kinds, eco.copies))
    xp = [float(x) for x in eco.xp]
    return Prices([list(o) for o in eco.odds], list(eco.slots), xp, kinds, copies, list(eco.shop), eco.refresh)


@dataclass(frozen=True)
class Target:
    """要凑的一套阵容：每种卡 (类型 0 角色 / 1 装备, 星级, 张数)，以及上阵的角色数。"""

    cards: tuple[tuple[int, int, int], ...]
    units: int

    @property
    def price(self) -> int:
        return sum(star * need for _, star, need in self.cards)


def target(lineup: Sequence[Sequence[str]]) -> Target:
    """lineup：[[角色 id, 装备 id 或 ""], ...]"""
    cards = data.cards()
    count = Counter(x for unit in lineup for x in unit if x)
    return Target(
        tuple((KINDS.index(cards[i]["type"]), cards[i]["star"], n) for i, n in sorted(count.items())),
        len(lineup),
    )


class Plan:
    """动态规划的结果。状态编号是"每种卡还缺几张"的混合进制数。"""

    def __init__(self, eco: Economy, goal: Target) -> None:
        self.eco, self.goal = eco, goal
        cards = goal.cards
        n = len(cards)
        self.strides = []
        size = 1
        for _, _, need in cards:
            self.strides.append(size)
            size *= need + 1
        self.size = size
        self.need_level = eco.level_for(goal.units)
        states = sorted(product(*(range(need + 1) for _, _, need in cards)), key=sum)
        groups = sorted({(kind, star) for kind, star, _ in cards})
        group_of = [groups.index((kind, star)) for kind, star, _ in cards]
        group_total = [eco.kinds[kind][star - 1] * eco.copies[kind][star - 1] for kind, star in groups]
        slot_kinds = [0] * eco.shop[0] + [1] * eco.shop[1]
        n_slots = len(slot_kinds)

        self.value = [[0.0] * size for _ in range(MAX_LEVEL + 2)]
        """value[等级][状态]：从这里到凑齐的最小期望花费（不含买卡）"""
        self.roll = [[INF] * size for _ in range(MAX_LEVEL + 2)]
        """roll[等级][状态]：在这一级先刷新一次、之后照最优做的期望花费"""
        for level in range(MAX_LEVEL, 0, -1):
            odds = eco.odds[level - 1]
            value, roll, above = self.value[level], self.roll[level], self.value[level + 1]
            after = [[0.0] * size for _ in range(n_slots + 1)]  # after[j][状态]：第 j 格之前的期望
            for state in states:
                index = sum(r * s for r, s in zip(state, self.strides, strict=True))
                level_up = eco.xp[level - 1] + above[index] if level < MAX_LEVEL else INF
                if not any(state):
                    best = eco.xp_between(level, self.need_level) if level < self.need_level else 0.0
                    value[index] = best
                    for j in range(n_slots + 1):
                        after[j][index] = best
                    continue
                held = [0] * len(groups)
                for i in range(n):
                    held[group_of[i]] += cards[i][2] - state[i]
                chance = [0.0, 0.0]  # 这一格出想要的卡的概率：角色格、装备格
                hits: tuple[list, list] = ([], [])
                for i in range(n):
                    if state[i]:
                        kind, star, need = cards[i]
                        left = eco.copies[kind][star - 1] - (need - state[i])
                        p = odds[star - 1] * left / (group_total[group_of[i]] - held[group_of[i]])
                        if p > 0:
                            chance[kind] += p
                            hits[kind].append((p, index - self.strides[i]))
                miss, base = 1.0, 0.0  # after[j] = base + miss * value
                tail = [(0.0, 1.0)] * (n_slots + 1)
                for j in range(n_slots - 1, -1, -1):
                    kind = slot_kinds[j]
                    nxt = after[j + 1]
                    base = sum(p * nxt[k] for p, k in hits[kind]) + (1 - chance[kind]) * base
                    miss *= 1 - chance[kind]
                    tail[j] = (base, miss)
                stay = eco.refresh + base
                rolled = stay / (1 - miss) if miss < 1 else INF
                best = min(rolled, level_up)
                roll[index], value[index] = rolled, best
                for j in range(n_slots + 1):
                    after[j][index] = tail[j][0] + tail[j][1] * best
        self.start = size - 1

    @property
    def cost(self) -> float:
        """从 1 级、一张都没有开始的最小期望花费，含买卡。"""
        return self.value[1][self.start] + self.goal.price


@dataclass
class Run:
    gold: int
    """一共花的金币（含买卡）"""
    xp: int
    """其中买经验"""
    rolls: int
    """其中刷新"""
    level: int
    round: int
    """第几回合凑齐（只在 timed 时有意义）"""
    interest: int = 0
    """一共拿到的利息"""


def simulate(plan: Plan, rng: random.Random, timed: bool, reserve: int = 0, max_rounds: int = 400) -> Run:
    eco, goal = plan.eco, plan.goal
    cards = goal.cards
    missing = [need for _, _, need in cards]
    index = plan.start
    level, xp, spent, spent_xp, rolls, interest = 1, 0, 0, 0, 0, 0
    left_price = goal.price
    gold = eco.start_gold if timed else 10**9
    by_group: dict[tuple[int, int], list[int]] = {}
    for i, (kind, star, _) in enumerate(cards):
        by_group.setdefault((kind, star), []).append(i)
    shop: list[int] = []  # 商店里摆着的、想要的卡

    def refresh() -> None:
        shop.clear()
        odds = eco.odds[level - 1]
        shown: Counter[tuple[int, int]] = Counter()
        for kind in (0, 1):
            for _ in range(eco.shop[kind]):
                star = rng.choices(range(1, 6), odds)[0]
                mine = by_group.get((kind, star), ())
                total = eco.kinds[kind][star - 1] * eco.copies[kind][star - 1]
                total -= sum(cards[i][2] - missing[i] for i in mine) + shown[kind, star]
                shown[kind, star] += 1
                pick = rng.random() * total
                for i in mine:
                    pick -= eco.copies[kind][star - 1] - (cards[i][2] - missing[i]) - shop.count(i)
                    if pick < 0:
                        shop.append(i)
                        break

    def buy() -> bool:
        """买下商店里想要的卡；有想要但买不起的返回 False。"""
        nonlocal gold, spent, index, left_price
        for i in sorted(shop, key=lambda i: cards[i][1]):
            if not missing[i]:
                continue
            if gold < cards[i][1]:
                return False
            gold -= cards[i][1]
            spent += cards[i][1]
            left_price -= cards[i][1]
            missing[i] -= 1
            index -= plan.strides[i]
            shop.remove(i)
        return True

    def pay_xp(amount: int) -> None:
        nonlocal gold, spent, spent_xp, xp, level
        gold -= amount
        spent += amount
        spent_xp += amount
        gain(amount)

    def gain(amount: int) -> None:
        nonlocal xp, level
        xp += amount
        while level < MAX_LEVEL and xp >= eco.xp[level - 1]:
            xp -= eco.xp[level - 1]
            level += 1

    refresh()
    if not timed:  # 只数金币时每次刷新都算钱，和 Plan 的口径一致
        spent, rolls = eco.refresh, 1
    talent_gold = rng.choices([combo for _, combo in eco.talent_sets], [chance for chance, _ in eco.talent_sets])[0]
    for turn in range(1, max_rounds + 1):
        if timed:
            if turn in eco.talents:
                gold += talent_gold[eco.talents.index(turn)]
            for when, kind, star in eco.auctions:
                wanted = [i for i in by_group.get((kind, star), ()) if missing[i]]
                if when == turn and wanted and gold >= star:
                    gold -= star
                    spent += star
                    left_price -= star
                    missing[wanted[0]] -= 1
                    index -= plan.strides[wanted[0]]
        while True:
            if not buy():
                break
            if index == 0 and level >= plan.need_level:
                return Run(spent, spent_xp, rolls, level, turn, interest)
            free = gold if gold >= plan.value[level][index] + left_price else gold - reserve
            wait = eco.xp[level - 1] - xp if level < MAX_LEVEL else 0
            if level < MAX_LEVEL and (index == 0 or wait + plan.value[level + 1][index] < plan.roll[level][index]):
                if free <= 0:
                    break
                pay_xp(min(free, wait))
                if free < wait:
                    break
            elif free >= eco.refresh:
                gold -= eco.refresh
                spent += eco.refresh
                rolls += 1
                refresh()
            else:
                break
        bonus = eco.interest_on(gold) if timed else 0
        interest += bonus
        gold += eco.round_gold + bonus
        gain(eco.round_xp)
        if not any(missing[i] for i in shop):  # 没有等着买的卡才换一批，否则相当于锁住商店
            refresh()
    return Run(spent, spent_xp, rolls, level, max_rounds, interest)
