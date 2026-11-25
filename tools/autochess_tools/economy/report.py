"""把 price 的结果做成一页图表。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.economy.report <输出.html> [结果.json]
"""

import json
import sys
from pathlib import Path

from autochess_tools.balance import DATA


def by_equips(lineups: list[dict]) -> list[dict]:
    """按装备件数分组：占比、平均花费、平均凑齐的回合。"""
    rows = []
    for count in sorted({r["equips"] for r in lineups}):
        group = [r for r in lineups if r["equips"] == count]
        weight = sum(r["weight"] for r in group)
        rows.append(
            {
                "equips": count,
                "share": weight,
                "cost": sum(r["weight"] * r["cost"] for r in group) / weight,
                "round": sum(r["weight"] * r["round"]["mean"] for r in group) / weight,
            }
        )
    return rows


def main() -> None:
    output = Path(sys.argv[1])
    result = json.loads(Path(sys.argv[2] if len(sys.argv) > 2 else DATA / "runs" / "economy.json").read_text())
    for config in result["configs"].values():
        for stage in config["stages"].values():
            stage["by_equips"] = by_equips(stage["lineups"])
    template = (Path(__file__).parent / "report.html").read_text()
    output.write_text(template.replace("__DATA__", json.dumps(result, ensure_ascii=False)))
    print(output)


if __name__ == "__main__":
    main()
