from autochess_tools import data
from autochess_tools.lineups import has_mechanics, mixed_battles, random_battles


def test_fixed_seed() -> None:
    assert random_battles(50, 1) == random_battles(50, 1)
    assert random_battles(50, 1) != random_battles(50, 2)


def test_lineups_are_valid() -> None:
    cards = data.cards()
    for p1, p2 in mixed_battles(200, 3):
        for lineup in (p1, p2):
            assert 1 <= len(lineup) <= 7
            for character, equipment in lineup:
                assert cards[character]["type"] == "character"
                assert equipment == "" or cards[equipment]["type"] == "equipment"


def test_dense_battles_favor_mechanics() -> None:
    cards = data.cards()

    def share(battles: list) -> float:
        units = [c for p1, p2 in battles for c, _ in p1 + p2]
        return sum(has_mechanics(cards[c]) for c in units) / len(units)

    assert share(random_battles(300, 5, dense=True)) > share(random_battles(300, 5)) + 0.3


def test_has_mechanics() -> None:
    cards = data.cards()
    assert has_mechanics(cards["toad"])  # 带参数的被动
    assert has_mechanics(cards["clockwork_box"])  # 千机之匣：写 null 的效果
    assert not has_mechanics(cards["paladin"])  # 只有庇护
    assert not has_mechanics(cards["tiger_man"])
