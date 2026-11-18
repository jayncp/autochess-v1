"""测速：固定的一批随机对局（普通对局，固定种子），打印 Godot 版单进程、Rust 版命令行单线程和多线程的场/秒，
以及从 Python 调用 Rust 版的场/秒（字符串 id 的 simulate、编号数组的 simulate_ids）。

命令行只算结算本身，不含读写和启动；从 Python 调用的算整个调用（含转换参数和结果）。用法：just bench
"""

import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np

from autochess_tools.data import REPO
from autochess_tools.lineups import random_battles
from autochess_tools.sim import engine, godot_path, run_engine, write_rows

COUNT = 300_000
GODOT_COUNT = 20_000
"""Godot 版只跑前这么多场（单进程约 4300 场/秒）"""
SEED = 20261119


def speed(stats: str) -> float:
    """命令行打印的"N 场/秒"（取最后一个）"""
    return float(re.findall(r"([\d.]+) 场/秒", stats)[-1])


def godot_speed(rows: list[dict]) -> float:
    with tempfile.TemporaryDirectory() as tmp:
        in_file, out_file = Path(tmp) / "in.jsonl", Path(tmp) / "out.jsonl"
        write_rows(in_file, rows)
        command = [godot_path(), "--headless", "--path", str(REPO), "--script", "res://cli/sim.gd", "--"]
        process = subprocess.run([*command, str(in_file), str(out_file)], capture_output=True, text=True, check=True)
        return speed(process.stdout)


def python_speeds(battles: list) -> dict[str, float]:
    """从 Python 调用：simulate（字符串 id）和 simulate_ids（编号数组，不含建数组的时间），单线程和全部核心"""
    rust = engine()
    arrays = []
    for side in range(2):
        cells = np.full((len(battles), 7, 2), -1, dtype=np.int32)
        for i, battle in enumerate(battles):
            for k, (character, equipment) in enumerate(battle[side]):
                cells[i, k] = [rust.index(character), rust.index(equipment) if equipment else -1]
        arrays.append(cells)
    speeds = {}
    for threads in (1, 0):
        start = time.perf_counter()
        rust.simulate(battles, threads)
        speeds[f"simulate/{threads}"] = len(battles) / (time.perf_counter() - start)
        start = time.perf_counter()
        rust.simulate_ids(*arrays, threads=threads)
        speeds[f"simulate_ids/{threads}"] = len(battles) / (time.perf_counter() - start)
    return speeds


def main() -> None:
    battles = random_battles(COUNT, SEED)
    rows = [{"p1": p1, "p2": p2} for p1, p2 in battles]
    _, single = run_engine(rows, ["--threads", "1"])
    _, multi = run_engine(rows)
    godot = godot_speed(rows[:GODOT_COUNT])
    threads = int(re.findall(r"（(\d+) 线程）", multi)[-1])
    python = python_speeds(battles)
    lines = [
        ("Godot 版（cli/sim.gd，单进程）", godot),
        ("Rust 命令行（单线程）", speed(single)),
        (f"Rust 命令行（{threads} 线程）", speed(multi)),
        ("Python 调 simulate（单线程）", python["simulate/1"]),
        (f"Python 调 simulate（{threads} 线程）", python["simulate/0"]),
        ("Python 调 simulate_ids（单线程）", python["simulate_ids/1"]),
        (f"Python 调 simulate_ids（{threads} 线程）", python["simulate_ids/0"]),
    ]
    print(f"测速：{COUNT} 场随机对局（Godot 版只跑前 {GODOT_COUNT} 场），{os.cpu_count()} 个核心")
    for name, value in lines:
        print(f"  {value:>12,.0f} 场/秒  {value / godot:5.0f} 倍  {name}")


if __name__ == "__main__":
    main()
