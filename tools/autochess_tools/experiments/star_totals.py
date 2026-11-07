"""同总星级：多个低星 vs 少量高星（裸卡）的随机摆位平均分。
方法同 docs/design/balance-report-2026-11-02-stars.md 第 1 节。

卡池是当前的非经济角色。按阵容组合计（与报告相同）：每方的阵容组合是一个多重集（同名卡可以重复）；
每对组合先在双方全部不同站位上取平均（相当于随机摆位），再在组合对之间等权平均。
算的是少而高星一方的平均分（胜 1、平 0.5、负 0）。
用法：just experiment star_totals
"""

from collections import defaultdict
from itertools import combinations_with_replacement, permutations, product

from autochess_tools import data
from autochess_tools.sim import simulate

type Team = list[list[str]]

# (说明, 少而高星方的星级, 多而低星方的星级)
MATCHUPS = [
    ("1×2★ vs 2×1★（2 星）", (2,), (1, 1)),
    ("1★+2★ vs 3×1★（3 星）", (1, 2), (1, 1, 1)),
    ("2×2★ vs 4×1★（4 星）", (2, 2), (1, 1, 1, 1)),
]


def combinations(stars: tuple[int, ...]) -> list[list[Team]]:
    """全部阵容组合，每个组合列出它的全部不同站位。"""
    pools = {s: data.balance_ids("character", s) for s in set(stars)}
    picks = [combinations_with_replacement(pools[s], stars.count(s)) for s in sorted(pools)]
    groups = []
    for parts in product(*picks):
        cards = [c for part in parts for c in part]
        groups.append([[[c, ""] for c in order] for order in sorted(set(permutations(cards)))])
    return groups


def average_score(high: tuple[int, ...], low: tuple[int, ...]) -> float:
    high_groups, low_groups = combinations(high), combinations(low)
    battles: list[tuple[Team, Team]] = []
    owners: list[tuple[int, int]] = []
    for i, high_orders in enumerate(high_groups):
        for j, low_orders in enumerate(low_groups):
            for h, lo in product(high_orders, low_orders):
                battles.append((h, lo))
                owners.append((i, j))
    by_pair: dict[tuple[int, int], list[float]] = defaultdict(list)
    for owner, result in zip(owners, simulate(battles), strict=True):
        by_pair[owner].append(result.score())
    return sum(sum(scores) / len(scores) for scores in by_pair.values()) / len(by_pair)


def main() -> None:
    print("| 对阵（总星相同） | 少而高星方平均分 |")
    print("|---|---|")
    for label, high, low in MATCHUPS:
        print(f"| {label} | {average_score(high, low):.3f} |")


if __name__ == "__main__":
    main()
