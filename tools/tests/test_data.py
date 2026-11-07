from autochess_tools import data


def test_cards_and_names() -> None:
    assert data.ids("character", 1) == ["tiger", "soldier", "pixie", "butterfly", "angel", "sludge", "mimic"]
    assert data.name("soldier") == "士兵"
    assert data.name("vanilla_6") == "vanilla_6"


def test_economy() -> None:
    assert data.economy("mimic") and data.economy("necklace") and data.economy("clover")
    assert not data.economy("tiger") and not data.economy("hollow")
    assert "mimic" not in data.balance_ids("character", 1)
