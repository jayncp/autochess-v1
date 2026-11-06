from autochess_tools import data


def test_cards_and_names() -> None:
    assert len(data.ids("character")) == 15
    assert data.ids("character", 1) == ["tiger", "soldier", "pixie", "angel", "sludge"]
    assert data.name("soldier") == "士兵"
    assert data.name("vanilla_6") == "vanilla_6"
