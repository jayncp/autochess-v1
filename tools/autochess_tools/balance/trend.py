"""把阶段搜索的报告做成一页趋势图：每张卡各阶段的出场率和带卡得分。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.balance.trend <输出.html> <说明文字> <报告.md>[,<报告.md>...] [更多组 ...]

每个参数是一组报告：同一组里的几份（不同种子）取平均；后面的组覆盖前面组里相同的阶段。
"""

import json
import re
import sys
from pathlib import Path

STAGES = ["开局", "前期", "前中期", "中期", "中后期", "后期"]
ROW = re.compile(r"\| (\S+) \| (\d) \| ([\d.]+)% \| ([\d.]+) \| (.*) \|")


def load(path: Path) -> dict[str, dict[str, dict]]:
    """报告里每个阶段每张卡的一行：{阶段: {卡名: {kind, star, usage, score, lineup}}}"""
    result: dict[str, dict[str, dict]] = {}
    stage = kind = None
    for line in path.read_text().splitlines():
        if match := re.match(r"## (\S+?)[·（]", line):
            stage, kind = match.group(1), None
            result[stage] = {}
        elif line.startswith("**角色**"):
            kind = "角色"
        elif line.startswith("**装备**"):
            kind = "装备"
        elif stage and kind and (match := ROW.match(line)):
            name, star, usage, score, lineup = match.groups()
            result[stage][name] = {
                "kind": kind,
                "star": int(star),
                "usage": float(usage),
                "score": float(score),
                "lineup": lineup,
            }
    return result


def merge(groups: list[list[Path]]) -> list[dict]:
    stages: dict[str, dict[str, dict]] = {}
    for group in groups:
        reports = [load(path) for path in group]
        for stage in reports[0]:
            cards = {}
            for name, first in reports[0][stage].items():
                rows = [r[stage][name] for r in reports if name in r.get(stage, {})]
                cards[name] = {
                    **first,
                    "usage": sum(r["usage"] for r in rows) / len(rows),
                    "score": sum(r["score"] for r in rows) / len(rows),
                }
            stages[stage] = cards
    names = dict.fromkeys(name for stage in STAGES for name in stages.get(stage, {}))
    cards = []
    for name in names:
        rows = {stage: stages[stage][name] for stage in STAGES if name in stages.get(stage, {})}
        last = list(rows.values())[-1]
        cards.append(
            {
                "name": name,
                "kind": last["kind"],
                "star": last["star"],
                "usage": [round(rows[s]["usage"], 1) if s in rows else None for s in STAGES],
                "score": [round(rows[s]["score"], 3) if s in rows else None for s in STAGES],
                "lineup": [rows[s]["lineup"] if s in rows else None for s in STAGES],
            }
        )
    return cards


def main() -> None:
    output, note, *groups = sys.argv[1:]
    cards = merge([[Path(p) for p in group.split(",")] for group in groups])
    template = (Path(__file__).parent / "trend.html").read_text()
    page = template.replace(
        "__DATA__", json.dumps({"stages": STAGES, "cards": cards, "note": note}, ensure_ascii=False)
    )
    Path(output).write_text(page)
    print(f"{output}：{len(cards)} 张卡")


if __name__ == "__main__":
    main()
