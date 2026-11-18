"""调用真实的 Godot（cli/sim.gd）和 Rust 版（engine-cli）；找不到时跳过。"""

import json
import shutil
from pathlib import Path

import pytest

from autochess_tools import data
from autochess_tools.diff_sim import first_difference
from autochess_tools.effective import vanilla_character
from autochess_tools.sim import ENGINE, godot_path, run_engine, run_godot, simulate

needs_godot = pytest.mark.skipif(
    not Path(godot_path()).exists() and shutil.which(godot_path()) is None, reason="找不到 Godot"
)
needs_engine = pytest.mark.skipif(not ENGINE.exists(), reason="没有 engine-cli，先运行 just rs-build")
FOLDER = data.REPO / "tests" / "cases"


def rule_cases() -> tuple[list[dict], list]:
    cases = json.loads((FOLDER / "battles.json").read_text(encoding="utf-8"))
    test_cards = json.loads((FOLDER / "cards.json").read_text(encoding="utf-8"))
    return cases, test_cards


@needs_godot
def test_matches_rule_cases() -> None:
    """规则用例（tests/cases/battles.json）用测试卡，作为额外卡牌传给 cli/sim.gd。"""
    cases, test_cards = rule_cases()
    results = simulate([(c["p1"], c["p2"]) for c in cases], test_cards)
    for case, result in zip(cases, results, strict=True):
        expect = case["expect"]
        assert (result.winner, result.p1, result.p2) == (
            expect["winner"],
            [strength for _, strength in expect["p1"]],
            [strength for _, strength in expect["p2"]],
        ), case["id"]


@needs_godot
def test_extra_cards() -> None:
    [result] = simulate([([["vanilla_10", ""]], [["pixie", ""]])], [vanilla_character(10)])
    assert (result.winner, result.p1, result.p2) == (1, [4], [])
    assert result.score() == 1.0 and result.score(2) == 0.0


@needs_godot
def test_bad_extra_card_raises() -> None:
    bad = vanilla_character(3)
    bad["timing_1"] = "nope"
    with pytest.raises(RuntimeError, match="有误"):
        simulate([([["vanilla_3", ""]], [["pixie", ""]])], [bad])


@needs_engine
def test_engine_matches_rule_cases() -> None:
    """Rust 版的命令行：规则用例的胜负、原因、幸存者的战斗力都符合期望。"""
    cases, test_cards = rule_cases()
    rows, stats = run_engine([{"p1": c["p1"], "p2": c["p2"]} for c in cases], extra_cards=test_cards)
    assert "场/秒" in stats
    for case, row in zip(cases, rows, strict=True):
        expect = case["expect"]
        assert (row["winner"], row["reason"], row["p1"], row["p2"]) == (
            expect["winner"],
            expect["reason"],
            [strength for _, strength in expect["p1"]],
            [strength for _, strength in expect["p2"]],
        ), case["id"]


@needs_godot
@needs_engine
def test_traces_match() -> None:
    """两边的简要轨迹相同（Godot 版由事件日志算出）。"""
    cases, test_cards = rule_cases()
    battles = [{"p1": c["p1"], "p2": c["p2"]} for c in cases]
    godot = run_godot(battles, ["--trace"], extra_cards=test_cards)
    rust, _ = run_engine(battles, ["--trace"], extra_cards=test_cards)
    for case, g, r in zip(cases, godot, rust, strict=True):
        assert first_difference(g["trace"], r["trace"]) is None, case["id"]
        assert g["reason"] == r["reason"], case["id"]


def test_first_difference() -> None:
    a = [["pre_battle", [3], [4]], ["engage", [1], [2.0]]]
    assert first_difference(a, [["pre_battle", [3], [4]], ["engage", [1], [2]]]) is None
    assert first_difference(a, [["pre_battle", [3], [4]], ["engage", [1], [3]]]) == 1
    assert first_difference(a, a[:1]) == 1
