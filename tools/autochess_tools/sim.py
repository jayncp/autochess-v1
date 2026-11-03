"""批量模拟：调用 Godot 的 cli/sim.gd。大批量时拆成几份，用多个 Godot 进程并行跑。"""

import json
import os
import subprocess
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from autochess_tools.data import REPO, Card

DEFAULT_GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
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
    if not battles:
        return []
    workers = workers or os.cpu_count() or 1
    chunk_count = max(1, min(workers, len(battles) // MIN_CHUNK))
    size = -(-len(battles) // chunk_count)
    chunks = [battles[i : i + size] for i in range(0, len(battles), size)]
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        cards_args: list[str] = []
        if extra_cards:
            cards_file = tmp_dir / "cards.json"
            cards_file.write_text(json.dumps(list(extra_cards)), encoding="utf-8")
            cards_args = ["--cards", str(cards_file)]
        processes = []
        for k, chunk in enumerate(chunks):
            in_file, out_file = tmp_dir / f"in{k}.jsonl", tmp_dir / f"out{k}.jsonl"
            with in_file.open("w", encoding="utf-8") as f:
                for p1, p2 in chunk:
                    f.write(json.dumps({"p1": p1, "p2": p2}) + "\n")
            command = [godot_path(), "--headless", "--path", str(REPO), "--script", "res://cli/sim.gd", "--"]
            command += [str(in_file), str(out_file), *cards_args]
            processes.append((subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE), out_file))
        results: list[Result] = []
        for process, out_file in processes:
            _, stderr = process.communicate()
            log = stderr.decode(errors="replace")
            # 数据或脚本出错时 Godot 照样以 0 退出，只在标准错误里打印 ERROR 行
            if process.returncode != 0 or any(
                line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in log.splitlines()
            ):
                raise RuntimeError(f"cli/sim.gd 运行失败：\n{log}")
            with out_file.open(encoding="utf-8") as f:
                results += [Result(r["winner"], r["p1"], r["p2"]) for r in map(json.loads, f)]
    if len(results) != len(battles):
        raise RuntimeError(f"cli/sim.gd 只返回了 {len(results)} / {len(battles)} 场结果")
    return results
