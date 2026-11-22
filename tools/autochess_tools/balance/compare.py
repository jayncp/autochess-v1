"""汇总一份阶段搜索的报告，可以和上一份比较：各阶段的概况，每张卡各阶段的出场率和带卡得分。

用法（在 tools/ 下）：uv run python -m autochess_tools.balance.compare <新报告.md> [旧报告.md] [--changed N]

--changed N：只列出场率变化不小于 N 个点的卡（要给旧报告）。
"""

import argparse
from pathlib import Path

from autochess_tools.balance.trend import STAGES, load


def overview(path: Path) -> dict[str, list[str]]:
    """每个阶段开头的几行概况：阵容库和均衡的大小、各档卡位、种族占比。"""
    result: dict[str, list[str]] = {}
    stage = None
    for line in path.read_text().splitlines():
        if line.startswith("## "):
            stage = line[3:].split("（")[0]
            result[stage] = []
        elif stage and (line.startswith(("阵容库", "**种族占比**")) or (line.startswith("- ") and "卡位（" in line)):
            result[stage].append(line)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="汇总和比较阶段搜索的报告")
    parser.add_argument("new", type=Path)
    parser.add_argument("old", type=Path, nargs="?")
    parser.add_argument("--changed", type=float, default=0.0)
    args = parser.parse_args()

    new, old = load(args.new), load(args.old) if args.old else {}
    stages = [s for s in STAGES if s in new]
    for stage, lines in overview(args.new).items():
        print(f"== {stage}")
        print("\n".join(f"  {line}" for line in lines))
        for kind in ("角色", "装备"):
            rows = [r for r in new[stage].values() if r["kind"] == kind]
            print(
                f"  {kind} {len(rows)} 张：出场率不低于 5% 的 {sum(r['usage'] >= 5 for r in rows)} 张，"
                f"不低于 1% 的 {sum(r['usage'] >= 1 for r in rows)} 张，"
                f"带卡得分低于 0.47 的 {sum(r['score'] < 0.47 for r in rows)} 张"
            )

    names = dict.fromkeys(name for stage in stages for name in new[stage])
    cards = {name: {s: new[s][name] for s in stages if name in new[s]} for name in names}
    for kind in ("角色", "装备"):
        print(f"\n# {kind}：各阶段的出场率（带卡得分）" + ("｜上一份的出场率" if old else ""))
        rows = [(name, by) for name, by in cards.items() if next(iter(by.values()))["kind"] == kind]
        for name, by in sorted(
            rows, key=lambda x: (next(iter(x[1].values()))["star"], -max(r["usage"] for r in x[1].values()))
        ):
            before = [old.get(s, {}).get(name, {}).get("usage") for s in by]
            if (
                old
                and args.changed
                and all(
                    b is None or abs(r["usage"] - b) < args.changed for r, b in zip(by.values(), before, strict=True)
                )
            ):
                continue
            line = f"{next(iter(by.values()))['star']}★ {name} " + " ".join(
                f"{r['usage']:.0f}({r['score']:.2f})" for r in by.values()
            )
            if old:
                line += "｜" + " ".join("-" if b is None else f"{b:.0f}" for b in before)
            print(line)


if __name__ == "__main__":
    main()
