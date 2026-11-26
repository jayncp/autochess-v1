"""按金币约束的阵容规则和爬山：觉醒按 3 张原卡算，Rust 和 Python 的规则一致。"""

import pytest

pytest.importorskip("openpyxl")

from autochess_tools.balance.gold import GoldMeta, space_for  # noqa: E402


def test_rules() -> None:
    space = space_for(8, 1)
    cards = space.cards
    tiger = cards.ids.index("tiger")
    awake = cards.twin[tiger]
    assert cards.name(awake) == cards.name(tiger) + "*" and cards.star[awake] == cards.star[tiger]
    assert space.legal(((tiger, -1), (tiger, -1)))
    # 三张普通的会合成觉醒，不能留着；觉醒的按 3 张算，比一张普通的贵
    assert not space.legal(((tiger, -1),) * 3)
    assert space.cost(((awake, -1),)) > space.cost(((tiger, -1),)) + 2
    assert space.cost(((awake, -1), (tiger, -1))) > space.cost(((awake, -1),))
    # 5★ 只有 6 张：两张觉醒是上限
    five = next(c for c in space.chars if cards.star[c] == 5 and cards.awake(c))
    assert space.wants(((five, -1), (five, -1))) is not None
    assert space.wants(((five, -1), (five, -1), (cards.twin[five], -1))) is None
    assert five not in space.targets() and tiger in space.targets()


def test_climb_stays_legal() -> None:
    space = space_for(5, 2)
    meta = GoldMeta(space)
    meta.add([space.random_lineup() for _ in range(40)])
    top = meta.grow(2, climbers=12, steps=5, mutations=6, log=lambda _: None)
    assert 0.0 <= top <= 1.0
    assert all(space.legal(x) for x in meta.pool)
