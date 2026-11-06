"""有效战力：与被测卡发挥同样作用的白板（只有战力、没有技能）的战力。

做法与 docs/design/balance-report-2026-11-01.md 第 1 节相同：
1. 从环境里抽三人队，把被测位置换成被测卡（或给该位置的角色装上被测装备），与环境里抽到的对手队伍对战，算平均分；
2. 把被测卡换成不同战力的白板（装备则换成不同战力的"白板武器"），在同一批对局上得到"战力 → 平均分"曲线；
3. 在曲线上找到与被测卡平均分相同的点，就是有效战力。

所有被测对象用同一批抽样对局，这样比较时随机误差相互抵消一部分。
"""

import random
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from autochess_tools.data import Card
from autochess_tools.sim import Lineup, simulate


@dataclass(frozen=True)
class Sample:
    """一场抽样对局：我方三人队、被测位置、对手三人队（都是角色 id，不带装备）。"""

    team: tuple[str, ...]
    position: int
    opponent: tuple[str, ...]


def samples(environment: Sequence[str], count: int, seed: int, team_size: int = 3) -> list[Sample]:
    """从环境（一组角色 id）里抽 count 场对局，固定种子。"""
    rng = random.Random(seed)

    def pick() -> tuple[str, ...]:
        return tuple(rng.choice(environment) for _ in range(team_size))

    return [Sample(pick(), rng.randrange(team_size), pick()) for _ in range(count)]


def vanilla_character(strength: int) -> Card:
    return {"id": f"vanilla_{strength}", "no": 0, "type": "character", "star": 0, "races": [], "strength": strength}


def vanilla_sword(strength: int) -> Card:
    return {"id": f"sword_{strength}", "no": 0, "type": "equipment", "star": 0, "strength": strength}


def with_character(card_id: str) -> Callable[[Sample], Lineup]:
    """被测位置换成这张角色卡。"""
    return lambda s: [[card_id if i == s.position else c, ""] for i, c in enumerate(s.team)]


def with_equipment(equip_id: str) -> Callable[[Sample], Lineup]:
    """给被测位置的角色装上这件装备（空字符串表示不装）。"""
    return lambda s: [[c, equip_id if i == s.position else ""] for i, c in enumerate(s.team)]


def average_scores(
    subjects: dict[str, Callable[[Sample], Lineup]],
    battles: Sequence[Sample],
    extra_cards: Sequence[Card] = (),
) -> dict[str, float]:
    """每个被测对象在同一批对局上的平均分（胜 1、平 0.5、负 0）。"""
    games = [(make(s), [[c, ""] for c in s.opponent]) for make in subjects.values() for s in battles]
    results = simulate(games, extra_cards)
    n = len(battles)
    return {name: sum(r.score() for r in results[k * n : (k + 1) * n]) / n for k, name in enumerate(subjects)}


@dataclass(frozen=True)
class Estimate:
    """有效战力的估计值。at_least 为真表示白板曲线已经到顶，真实值不低于 value。"""

    value: float
    at_least: bool = False

    def __str__(self) -> str:
        return f"≥{self.value:g}" if self.at_least else f"{self.value:.1f}"


def interpolate(curve: Sequence[tuple[float, float]], target: float) -> Estimate:
    """在"战力 → 平均分"曲线上找平均分等于 target 的战力（线性插值）。
    达到或超过曲线最高分时，返回最先达到最高分的战力并标为"至少"。"""
    top = max(y for _, y in curve)
    if target >= top:
        return Estimate(next(x for x, y in curve if y == top), at_least=True)
    if target <= curve[0][1]:
        return Estimate(curve[0][0])
    for (x0, y0), (x1, y1) in zip(curve, curve[1:], strict=False):
        if y0 <= target < y1:
            return Estimate(x0 + (x1 - x0) * (target - y0) / (y1 - y0))
    raise ValueError("曲线不单调，无法插值")


def effective_strengths(characters: Sequence[str], battles: Sequence[Sample], max_strength: int) -> dict[str, Estimate]:
    """角色的有效战力。"""
    vanillas = [vanilla_character(v) for v in range(1, max_strength + 1)]
    subjects = {c: with_character(c) for c in characters}
    subjects |= {v["id"]: with_character(v["id"]) for v in vanillas}
    scores = average_scores(subjects, battles, vanillas)
    curve = [(v["strength"], scores[v["id"]]) for v in vanillas]
    return {c: interpolate(curve, scores[c]) for c in characters}


def equipment_values(
    equipment: Sequence[str], battles: Sequence[Sample], max_strength: int, extra_cards: Sequence[Card] = ()
) -> dict[str, Estimate]:
    """装备的有效战力：给同一个角色装上它，相当于装上多大战力的白板武器。"""
    swords = [vanilla_sword(k) for k in range(1, max_strength + 1)]
    subjects = {e: with_equipment(e) for e in equipment}
    subjects |= {"": with_equipment("")} | {s["id"]: with_equipment(s["id"]) for s in swords}
    scores = average_scores(subjects, battles, [*swords, *extra_cards])
    curve = [(0, scores[""])] + [(s["strength"], scores[s["id"]]) for s in swords]
    return {e: interpolate(curve, scores[e]) for e in equipment}
