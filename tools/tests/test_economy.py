"""经济系统的估算：读表格，动态规划和照规则抽卡的模拟对得上。"""

import random
import statistics

import pytest

pytest.importorskip("openpyxl")

from autochess_tools.economy.model import MAX_LEVEL, Plan, Target, load, prices, simulate, target  # noqa: E402

LINEUP = [["soldier", ""], ["soldier", ""], ["tiger", "lionheart"], ["parrot", ""]]


def test_load() -> None:
    eco = load()
    assert len(eco.odds) == MAX_LEVEL and len(eco.slots) == MAX_LEVEL and len(eco.xp) == MAX_LEVEL - 1
    assert all(abs(sum(odds) - 1) < 1e-9 for odds in eco.odds)
    assert list(eco.slots) == sorted(eco.slots)
    assert eco.interest_on(0) == 0 and eco.interest_on(10**6) == max(amount for _, amount in eco.interest)
    assert abs(sum(chance for chance, _ in eco.talent_sets) - 1) < 1e-9


def test_single_card() -> None:
    """只要一张 1★ 角色：1 级就能刷到，期望次数有公式。"""
    eco = load()
    plan = Plan(eco, target([["tiger", ""]]))
    chance = eco.odds[0][0] / eco.kinds[0][0]
    rolls = 1 / (1 - (1 - chance) ** eco.shop[0])
    assert plan.cost == pytest.approx(rolls * eco.refresh + 1)


def test_rust_cost_matches_plan() -> None:
    """Rust 版的期望花费和 Plan 一样：几张不同星级的卡，同名两张、三张（觉醒），够不上的等级和张数是无穷大。"""
    eco = load()
    goals = [
        target(LINEUP),
        Target(((0, 1, 3), (0, 2, 1), (1, 2, 2), (0, 4, 1)), 5),
        Target(((0, 5, 6), (1, 3, 1), (0, 3, 3)), 7),
    ]
    costs = prices(eco).costs([(goal.cards, goal.units) for goal in goals])
    assert costs == pytest.approx([Plan(eco, goal).cost for goal in goals])
    too_many = eco.copies[0][4] + 1
    assert prices(eco).costs([(((0, 5, too_many),), 1), (((0, 1, 1),), max(eco.slots) + 1)]) == [float("inf")] * 2


def test_plan_matches_simulation() -> None:
    eco = load()
    plan = Plan(eco, target(LINEUP))
    rng = random.Random(1)
    runs = [simulate(plan, rng, timed=False) for _ in range(3000)]
    assert all(run.level >= plan.need_level for run in runs)
    assert statistics.fmean(run.gold for run in runs) == pytest.approx(plan.cost, rel=0.03)


def test_timed() -> None:
    """按回合发钱：花的钱不超过到手的钱；存钱的打法能拿到利息。"""
    eco = load()
    plan = Plan(eco, target(LINEUP))
    rng = random.Random(2)
    for reserve in (0, 30):
        for _ in range(200):
            run = simulate(plan, rng, timed=True, reserve=reserve)
            income = eco.start_gold + eco.round_gold * (run.round - 1) + run.interest
            income += max(sum(combo) for _, combo in eco.talent_sets)
            assert 1 <= run.round < 400 and run.gold <= income
            assert reserve or run.interest <= eco.interest_on(eco.round_gold) * run.round
