from autochess_tools import data


def test_cards_and_names() -> None:
    assert len(data.ids("character")) == 15
    assert data.ids("character", 1) == ["soldier", "tiger", "sludge", "angel", "pixie"]
    assert data.name("soldier") == "士兵"
    assert data.name("vanilla_6") == "vanilla_6"
