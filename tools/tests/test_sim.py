"""调用真实的 Godot（cli/sim.gd）；找不到 Godot 时跳过。"""

import json
import shutil
from pathlib import Path

import pytest

from autochess_tools import data
from autochess_tools.effective import vanilla_character
from autochess_tools.sim import godot_path, simulate

pytestmark = pytest.mark.skipif(
    not Path(godot_path()).exists() and shutil.which(godot_path()) is None, reason="找不到 Godot"
)


def test_matches_golden_cases() -> None:
    lines = (data.REPO / "tests" / "golden" / "battles.jsonl").read_text(encoding="utf-8").splitlines()
    cases = [json.loads(line) for line in lines[:20]]
    results = simulate([(c["p1"], c["p2"]) for c in cases])
    for case, result in zip(cases, results, strict=True):
        assert (result.winner, result.p1, result.p2) == (
            case["expect"]["winner"],
            case["expect"]["p1"],
            case["expect"]["p2"],
        )


def test_extra_cards() -> None:
    [result] = simulate([([["vanilla_10", ""]], [["pixie", ""]])], [vanilla_character(10)])
    assert (result.winner, result.p1, result.p2) == (1, [4], [])
    assert result.score() == 1.0 and result.score(2) == 0.0


def test_bad_extra_card_raises() -> None:
    bad = vanilla_character(3)
    bad["timing_1"] = "nope"
    with pytest.raises(RuntimeError, match="有误"):
        simulate([([["vanilla_3", ""]], [["pixie", ""]])], [bad])
