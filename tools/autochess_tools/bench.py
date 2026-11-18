"""测速：固定的一批随机对局（普通对局，固定种子），打印 Rust 版单线程、多线程的场/秒，
以及 Godot 版单进程的场/秒作为对比。

只算结算本身的时间，不含读写和启动（两边的命令行都这样打印）。用法：just bench
"""

import os
import re
import subprocess
import tempfile
from pathlib import Path

from autochess_tools.data import REPO
from autochess_tools.lineups import random_battles
from autochess_tools.sim import godot_path, run_engine, write_rows

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


def main() -> None:
    rows = [{"p1": p1, "p2": p2} for p1, p2 in random_battles(COUNT, SEED)]
    _, single = run_engine(rows, ["--threads", "1"])
    _, multi = run_engine(rows)
    godot = godot_speed(rows[:GODOT_COUNT])
    threads = int(re.findall(r"（(\d+) 线程）", multi)[-1])
    print(f"测速：{COUNT} 场随机对局（Godot 版只跑前 {GODOT_COUNT} 场），{os.cpu_count()} 个核心")
    print(f"  Godot 版（单进程）  {godot:>12,.0f} 场/秒")
    print(f"  Rust 版（单线程）   {speed(single):>12,.0f} 场/秒  {speed(single) / godot:6.0f} 倍")
    print(f"  Rust 版（{threads} 线程）  {speed(multi):>12,.0f} 场/秒  {speed(multi) / godot:6.0f} 倍")


if __name__ == "__main__":
    main()
