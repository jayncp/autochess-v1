"""把按金币搜索的报告做成一页趋势图：每张卡各回合档的出场率和带卡得分，角色分普通、觉醒、合计。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.balance.gold_trend <输出.html> <说明文字> <报告目录> <觉醒方案.json>

报告目录里是 gold report --forced 写出的 <回合>.md；网页模板和阶段搜索的趋势图共用（trend.html）。
"""

import json
import sys
from pathlib import Path

from autochess_tools import data
from autochess_tools.awaken import awakened, characters, describe, label
from autochess_tools.balance.gold import BUDGETS

KINDS = ["角色·合计", "角色·普通", "角色·觉醒", "装备"]


def number(text: str) -> float | None:
    """表格里的一格：百分数、得分；空的和"买不起"没有值。"""
    text = text.strip().rstrip("%")
    return float(text) if text and text[0].isdigit() else None


def load(path: Path) -> list[dict]:
    """一份报告里的每一行：{name, kind, star, usage, score, lineup}，角色一张卡出三行。"""
    rows, section = [], None
    for line in path.read_text().splitlines():
        if line.startswith("**"):
            section = line[2:4] if line[2:4] in ("角色", "装备") else None
            continue
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if section is None or len(cells) < 3 or not cells[1].isdigit():
            continue
        name, star = cells[0], int(cells[1])
        if section == "装备":
            rows.append((name, "装备", star, number(cells[2]), number(cells[3]), cells[4]))
            continue
        plain, awake = (number(cells[5]), cells[7]), (number(cells[6]), cells[8])
        both = max(plain, awake, key=lambda pair: -1 if pair[0] is None else pair[0])
        rows.append((name, "角色·合计", star, number(cells[4]), *both))
        rows.append((name, "角色·普通", star, number(cells[2]), *plain))
        rows.append((name + "*", "角色·觉醒", star, number(cells[3]), *awake))
    return [dict(zip(("name", "kind", "star", "usage", "score", "lineup"), row, strict=True)) for row in rows]


def text(card: data.Card) -> str:
    strength, skills, special = describe(card)
    return "，".join(part for part in (f"{strength} 战斗力", skills, special) if part)


def infos(templates: Path) -> dict[str, str]:
    """每张角色的说明：觉醒方案，原版和觉醒后的数值。"""
    chosen = json.loads(templates.read_text())
    result = {}
    for card in characters():
        rule = chosen[card["id"]]
        after = awakened(card, *rule)
        result[data.name(card["id"])] = f"觉醒：{label(rule)}。原版 {text(card)} → 觉醒 {text(after)}"
    return result


def main() -> None:
    output, note, folder, templates = sys.argv[1:]
    turns = list(BUDGETS)
    info = infos(Path(templates))
    cards: dict[tuple[str, str], dict] = {}
    for at, turn in enumerate(turns):
        for row in load(Path(folder) / f"{turn}.md"):
            card = cards.setdefault(
                (row["kind"], row["name"]),
                {
                    "name": row["name"],
                    "kind": row["kind"],
                    "star": row["star"],
                    "usage": [None] * len(turns),
                    "score": [None] * len(turns),
                    "lineup": [None] * len(turns),
                    "info": info.get(row["name"].rstrip("*")),
                },
            )
            card["usage"][at], card["score"][at], card["lineup"][at] = row["usage"], row["score"], row["lineup"]
    page = {
        "title": "按金币搜索：各回合的出场率和带卡得分（带觉醒）",
        "stages": [f"第 {turn} 回合" for turn in turns],
        "kinds": KINDS,
        "cards": list(cards.values()),
        "note": note,
    }
    template = (Path(__file__).parent / "trend.html").read_text()
    Path(output).write_text(template.replace("__DATA__", json.dumps(page, ensure_ascii=False)))
    print(f"{output}：{len(cards)} 行")


if __name__ == "__main__":
    main()
