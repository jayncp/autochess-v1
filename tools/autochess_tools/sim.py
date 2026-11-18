"""批量模拟：调用 Godot 的 cli/sim.gd（大批量时拆成几份，用多个 Godot 进程并行跑），
或 Rust 版的 engine-cli（对拍、测速用）。
"""

import json
import os
import subprocess
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from autochess_tools.data import REPO, Card

DEFAULT_GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
# Rust 版的命令行，just rs-build 生成
ENGINE = REPO / "engine" / "target" / "release" / "engine-cli"
# 每个进程至少分到这么多场，太少时并行不划算（Godot 启动要零点几秒）
MIN_CHUNK = 2000

type Lineup = Sequence[Sequence[str]]
"""阵容：[[角色 id, 装备 id], ...]，装备为空字符串表示不带。"""


@dataclass(frozen=True)
class Result:
    winner: int
    """1/2 = 该方胜，3 = 平局"""
    p1: list[int]
    """P1 幸存单位的战力"""
    p2: list[int]

    def score(self, side: int = 1) -> float:
        """某一方的得分：胜 1、平 0.5、负 0。"""
        if self.winner == 3:
            return 0.5
        return 1.0 if self.winner == side else 0.0


def godot_path() -> str:
    return os.environ.get("GODOT", DEFAULT_GODOT)


def simulate(
    battles: Sequence[tuple[Lineup, Lineup]],
    extra_cards: Sequence[Card] | None = None,
    workers: int | None = None,
) -> list[Result]:
    """模拟一批对局，结果顺序与输入一致。extra_cards 是只在本次模拟有效的额外卡牌（如白板单位）。"""
    rows = run_godot([{"p1": p1, "p2": p2} for p1, p2 in battles], extra_cards=extra_cards, workers=workers)
    return [Result(r["winner"], r["p1"], r["p2"]) for r in rows]


def run_godot(
    rows: Sequence[dict],
    flags: Sequence[str] = (),
    extra_cards: Sequence[Card] | None = None,
    workers: int | None = None,
) -> list[dict]:
    """用 cli/sim.gd 跑一批对局（每行 {"p1", "p2"}），返回原样的结果行，顺序与输入一致。flags 如 ["--trace"]。"""
    if not rows:
        return []
    workers = workers or os.cpu_count() or 1
    chunk_count = max(1, min(workers, len(rows) // MIN_CHUNK))
    size = -(-len(rows) // chunk_count)
    chunks = [rows[i : i + size] for i in range(0, len(rows), size)]
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        args = [*flags, *_cards_args(tmp_dir, extra_cards)]
        processes = []
        for k, chunk in enumerate(chunks):
            in_file, out_file = tmp_dir / f"in{k}.jsonl", tmp_dir / f"out{k}.jsonl"
            write_rows(in_file, chunk)
            command = [godot_path(), "--headless", "--path", str(REPO), "--script", "res://cli/sim.gd", "--"]
            command += [str(in_file), str(out_file), *args]
            processes.append((subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE), out_file))
        results: list[dict] = []
        for process, out_file in processes:
            _, stderr = process.communicate()
            log = stderr.decode(errors="replace")
            # 数据或脚本出错时 Godot 照样以 0 退出，只在标准错误里打印 ERROR 行
            if process.returncode != 0 or any(
                line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in log.splitlines()
            ):
                raise RuntimeError(f"cli/sim.gd 运行失败：\n{log}")
            results += read_rows(out_file)
    if len(results) != len(rows):
        raise RuntimeError(f"cli/sim.gd 只返回了 {len(results)} / {len(rows)} 场结果")
    return results


def run_engine(
    rows: Sequence[dict],
    flags: Sequence[str] = (),
    extra_cards: Sequence[Card] | None = None,
) -> tuple[list[dict], str]:
    """用 Rust 版 engine-cli 跑一批对局，返回结果行（顺序与输入一致）和它打印的统计。要先 just rs-build。"""
    if not ENGINE.exists():
        raise RuntimeError(f"没有 {ENGINE}，先运行 just rs-build")
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        in_file, out_file = tmp_dir / "in.jsonl", tmp_dir / "out.jsonl"
        write_rows(in_file, rows)
        command = [str(ENGINE), str(in_file), str(out_file), *flags, *_cards_args(tmp_dir, extra_cards)]
        process = subprocess.run(command, capture_output=True, text=True)
        if process.returncode != 0:
            raise RuntimeError(f"engine-cli 运行失败：\n{process.stderr}")
        return read_rows(out_file), process.stdout.strip()


def _cards_args(tmp_dir: Path, extra_cards: Sequence[Card] | None) -> list[str]:
    if not extra_cards:
        return []
    cards_file = tmp_dir / "cards.json"
    cards_file.write_text(json.dumps(list(extra_cards)), encoding="utf-8")
    return ["--cards", str(cards_file)]


def write_rows(path: Path, rows: Sequence[dict]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")


def read_rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f]
