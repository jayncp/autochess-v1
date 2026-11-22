"""批量模拟：Rust 版的 Python 绑定（默认后端）、命令行 engine-cli，以及 Godot 版（cli/sim.gd）。

找不到 Godot 或 engine-cli 时跳过。
"""

import json
import shutil
from pathlib import Path

import numpy as np
import pytest

from autochess_tools import data
from autochess_tools.diff_sim import first_difference
from autochess_tools.effective import vanilla_character
from autochess_tools.lineups import mixed_battles
from autochess_tools.sim import ENGINE, engine, godot_path, run_engine, run_godot, simulate

needs_godot = pytest.mark.skipif(
    not Path(godot_path()).exists() and shutil.which(godot_path()) is None, reason="找不到 Godot"
)
needs_engine = pytest.mark.skipif(not ENGINE.exists(), reason="没有 engine-cli，先运行 just rs-build")
# 两个后端：Rust 版（Python 绑定）总是有；Godot 版要装了 Godot
BACKENDS = ["rust", pytest.param("godot", marks=needs_godot)]
FOLDER = data.REPO / "tests" / "cases"


def rule_cases() -> tuple[list[dict], list]:
    cases = json.loads((FOLDER / "battles.json").read_text(encoding="utf-8"))
    test_cards = json.loads((FOLDER / "cards.json").read_text(encoding="utf-8"))
    return cases, test_cards


@pytest.mark.parametrize("backend", BACKENDS)
def test_matches_rule_cases(backend: str) -> None:
    """规则用例（tests/cases/battles.json）用测试卡，作为额外卡牌传进去。"""
    cases, test_cards = rule_cases()
    results = simulate([(c["p1"], c["p2"]) for c in cases], test_cards, backend=backend)
    for case, result in zip(cases, results, strict=True):
        expect = case["expect"]
        assert (result.winner, result.p1, result.p2) == (
            expect["winner"],
            [strength for _, strength in expect["p1"]],
            [strength for _, strength in expect["p2"]],
        ), case["id"]


@pytest.mark.parametrize("backend", BACKENDS)
def test_extra_cards(backend: str) -> None:
    [result] = simulate([([["vanilla_10", ""]], [["pixie", ""]])], [vanilla_character(10)], backend=backend)
    assert (result.winner, result.p1, result.p2) == (1, [2], [])
    assert result.score() == 1.0 and result.score(2) == 0.0


@pytest.mark.parametrize(
    ("backend", "error"), [("rust", ValueError), pytest.param("godot", RuntimeError, marks=needs_godot)]
)
def test_bad_extra_card_raises(backend: str, error: type[Exception]) -> None:
    bad = vanilla_character(3)
    bad["timing_1"] = "nope"
    with pytest.raises(error, match="有误"):
        simulate([([["vanilla_3", ""]], [["pixie", ""]])], [bad], backend=backend)


def test_simulate_ids_matches_simulate() -> None:
    """按编号传 numpy 数组和按字符串 id 传，结果一样；-1 是空位、不带装备。"""
    battles = mixed_battles(400, 11)
    rust = engine()
    expected = rust.simulate(battles)
    arrays = []
    for side in range(2):
        cells = np.full((len(battles), 7, 2), -1, dtype=np.int32)
        for i, battle in enumerate(battles):
            for k, (character, equipment) in enumerate(battle[side]):
                cells[i, k] = [rust.index(character), rust.index(equipment) if equipment else -1]
        arrays.append(cells)
    winner, reason, p1, p2 = rust.simulate_ids(*arrays, threads=2)
    for i, (w, r, s1, s2) in enumerate(expected):
        assert (winner[i], reason[i]) == (w, int(r == "no_death"))
        assert list(p1[i][p1[i] > 0]) == s1 and list(p2[i][p2[i] > 0]) == s2


def test_simulate_ids_rejects_bad_input() -> None:
    rust = engine()
    cells = np.full((1, 7, 2), -1, dtype=np.int32)
    cells[0, 0] = [rust.index("iron_sword"), -1]
    with pytest.raises(ValueError, match="不是角色"):
        rust.simulate_ids(cells, cells)
    with pytest.raises(ValueError, match="形状"):
        rust.simulate_ids(np.zeros((1, 8, 2), dtype=np.int32), np.zeros((1, 8, 2), dtype=np.int32))


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
