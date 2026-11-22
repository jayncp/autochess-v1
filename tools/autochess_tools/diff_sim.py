"""对拍：同一批随机对局分别用 Godot 版（cli/sim.gd）和 Rust 版（engine-cli）跑，逐场比较胜负、原因、幸存者的战斗力。

对局一半普通、一半机制密集（见 lineups.py），固定种子。不一致时打印阵容，并用简要轨迹（--trace）找出第一处不同。
用法：just diff-sim [场数] [--seed N] [--cards 额外卡牌.json]（先 just rs-build，just diff-sim 会自动做）
--cards：额外的卡（JSON 数组，同 id 覆盖正式卡，路径相对 tools/），用来对拍还没写进正式数据的数值和机制。
"""

import json
import sys
import time
from collections import Counter
from collections.abc import Sequence
from pathlib import Path

from autochess_tools.data import Card
from autochess_tools.lineups import mixed_battles
from autochess_tools.sim import run_engine, run_godot

COUNT = 1_000_000
SEED = 20261119
SHOW = 5
"""最多详细列出几场不一致的"""


def outcome(row: dict) -> tuple:
    """胜负、原因、双方幸存者的战斗力（Godot 写出的数可能是小数，统一成整数）"""
    return int(row["winner"]), row["reason"], [int(x) for x in row["p1"]], [int(x) for x in row["p2"]]


def normalize(trace: Sequence) -> list:
    return [[step, [int(x) for x in p1], [int(x) for x in p2]] for step, p1, p2 in trace]


def first_difference(a: Sequence, b: Sequence) -> int | None:
    """两份简要轨迹第一处不同的步数；一份是另一份的开头时，是短的那份的长度；完全相同时为 None。"""
    a, b = normalize(a), normalize(b)
    for i, (x, y) in enumerate(zip(a, b, strict=False)):
        if x != y:
            return i
    return None if len(a) == len(b) else min(len(a), len(b))


def explain(battle: dict, extra_cards: Sequence[Card]) -> str:
    """一场不一致的对局：阵容、两边的结果，以及简要轨迹里第一处不同"""
    [godot] = run_godot([battle], ["--trace"], extra_cards)
    [rust], _ = run_engine([battle], ["--trace"], extra_cards)
    lines = [f"  P1 {battle['p1']}", f"  P2 {battle['p2']}", f"  Godot {outcome(godot)}", f"  Rust  {outcome(rust)}"]
    k = first_difference(godot["trace"], rust["trace"])
    if k is not None:
        lines.append(f"  第一处不同在第 {k + 1} 步（之前的步骤都一样）：")
        for name, row in (("Godot", godot), ("Rust ", rust)):
            steps = normalize(row["trace"])
            lines.append(f"    {name} {steps[k] if k < len(steps) else '（已经结束）'}")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    count = int(argv[0]) if argv and argv[0].isdigit() else COUNT
    seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else SEED
    extra_cards: list[Card] = json.loads(Path(argv[argv.index("--cards") + 1]).read_text()) if "--cards" in argv else []
    battles = [{"p1": p1, "p2": p2} for p1, p2 in mixed_battles(count, seed, extra_cards=extra_cards)]
    start = time.perf_counter()
    godot = run_godot(battles, extra_cards=extra_cards)
    godot_seconds = time.perf_counter() - start
    start = time.perf_counter()
    rust, _ = run_engine(battles, extra_cards=extra_cards)
    rust_seconds = time.perf_counter() - start
    mismatches = [i for i, (g, r) in enumerate(zip(godot, rust, strict=True)) if outcome(g) != outcome(r)]
    normal = count - count // 2
    results = Counter((int(r["winner"]), r["reason"]) for r in rust)
    print(f"对拍 {count} 场（普通 {normal}、机制密集 {count // 2}，种子 {seed}）")
    print(f"  用时：Godot {godot_seconds:.1f} 秒（多进程），Rust {rust_seconds:.1f} 秒（含读写）")
    print(
        f"  结果：P1 胜 {results[1, 'wipe']}，P2 胜 {results[2, 'wipe']}，"
        f"同时全灭 {results[3, 'wipe']}，连续无人阵亡 {results[3, 'no_death']}"
    )
    dense = sum(i >= normal for i in mismatches)
    print(f"  不一致：{len(mismatches)} 场（普通 {len(mismatches) - dense}，机制密集 {dense}）")
    for i in mismatches[:SHOW]:
        print(f"第 {i + 1} 场：\n{explain(battles[i], extra_cards)}")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
