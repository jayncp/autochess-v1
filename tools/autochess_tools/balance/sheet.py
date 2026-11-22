"""数值试验表：把一组卡牌数值写成 Excel 给设计者改，再从 Excel 读回"和正式数据不同的卡"。

用法（在 tools/ 下，需要依赖组 balance 里的 openpyxl）：
  uv run --group balance python -m autochess_tools.balance.sheet write <表.xlsx> [改动.json] [备注.json] [设计表.xlsx]
  uv run --group balance python -m autochess_tools.balance.sheet read <表.xlsx> <输出改动.json> [对照表.json]

读的时候和 data/cards.json 比较，输出有差别的卡（整张卡，供搜索的 --change 用），并列出红字的格子。
表里特殊技能有"文字"和"数据"两列，搜索只认数据列。设计者通常只改文字，所以可以给一份对照表
（{卡 id: {"text": 文字, "special": 数据}}）：文字和对照表一致的卡按对照表的数据算；文字变了的会提示，要人来补数据。
"""

import json
import sys
from pathlib import Path

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill

from autochess_tools import data

RACES = {"beast": "动物", "human": "人族", "elf": "精灵", "divine": "神族", "nature": "自然", "treasure": "财宝"}
TIMINGS = {"pre_battle": "战前", "on_enter": "入场", "on_engage": "交战"}
SKILLS = {
    "rage": "狂暴",
    "rally": "集结",
    "support": "支援",
    "inspire": "振奋",
    "corrode": "腐蚀",
    "annihilate": "湮灭",
    "wealth": "财富",
}
CLEAR = "空"
COLUMNS = [
    "id",
    "名称",
    "星级",
    "种族",
    "战斗力",
    "时机-1",
    "时机-2",
    "基础技能-1",
    "基础技能-2",
    "特殊技能（文字）",
    "特殊技能（数据）",
    "备注",
]
WIDTHS = [20, 12, 6, 16, 8, 10, 10, 26, 26, 48, 60, 30]
SHEETS = {"character": "角色", "equipment": "装备"}


def show_timing(value) -> str | None:
    if value is None:
        return None
    return CLEAR if value == "clear" else "、".join(TIMINGS[t] for t in value)


def show_skills(value) -> str | None:
    if value is None:
        return None
    return CLEAR if value == "clear" else "、".join(f"{SKILLS[k]}{v}" for k, v in value.items())


def show_special(value) -> str | None:
    if value is None:
        return None
    return CLEAR if value == "clear" else json.dumps(value, ensure_ascii=False)


def parse_timing(text):
    if text is None or not str(text).strip():
        return None
    text = str(text).strip()
    if text == CLEAR:
        return "clear"
    back = {v: k for k, v in TIMINGS.items()}
    return [back[t.strip()] for t in text.replace("，", "、").replace(",", "、").split("、")]


def parse_skills(text):
    if text is None or not str(text).strip():
        return None
    text = str(text).strip()
    if text == CLEAR:
        return "clear"
    result = {}
    for part in text.replace("，", "、").replace(",", "、").replace("；", "、").split("、"):
        part = part.strip().replace(" ", "")
        name = next(n for n in SKILLS.values() if part.startswith(n))
        result[next(k for k, v in SKILLS.items() if v == name)] = int(part[len(name) :])
    return result


def parse_special(text):
    if text is None or not str(text).strip():
        return None
    text = str(text).strip()
    return "clear" if text == CLEAR else json.loads(text)


def design_texts(path: Path) -> dict[str, str]:
    """设计表里的特殊技能文字（按 id）"""
    texts = {}
    book = openpyxl.load_workbook(path, read_only=True)
    for sheet in SHEETS.values():
        rows = book[sheet].iter_rows(values_only=True)
        header = list(next(rows))
        for row in rows:
            card_id, text = row[header.index("id")], row[header.index("特殊技能")]
            if card_id and text:
                texts[card_id] = text
    return texts


def write(path: Path, changed: list[dict], notes: dict[str, str], texts: dict[str, str]) -> None:
    cards = {**data.cards(), **{c["id"]: c for c in changed}}
    book = openpyxl.Workbook()
    book.remove(book.active)
    for kind, title in SHEETS.items():
        sheet = book.create_sheet(title)
        sheet.append(COLUMNS)
        for cell in sheet[1]:
            cell.font = Font(bold=True)
            cell.fill = PatternFill("solid", fgColor="DDDDDD")
        for card in sorted((c for c in cards.values() if c["type"] == kind), key=lambda c: c["no"]):
            sheet.append(
                [
                    card["id"],
                    data.name(card["id"]),
                    card["star"],
                    "、".join(RACES[r] for r in card.get("races", [])) or None,
                    card.get("strength"),
                    show_timing(card.get("timing_1")),
                    show_timing(card.get("timing_2")),
                    show_skills(card.get("skills_1")),
                    show_skills(card.get("skills_2")),
                    notes.get("text." + card["id"], texts.get(card["id"])),
                    show_special(card.get("special_skills")),
                    notes.get(card["id"]),
                ]
            )
        for letter, width in zip("ABCDEFGHIJKL", WIDTHS, strict=True):
            sheet.column_dimensions[letter].width = width
        for row in sheet.iter_rows(min_row=2):
            for cell in row:
                cell.alignment = Alignment(vertical="center", wrap_text=cell.column >= 10)
        sheet.freeze_panes = "C2"
    book.save(path)


def is_red(cell) -> bool:
    color = cell.font.color if cell.font else None
    rgb = color.rgb if color is not None and color.type == "rgb" else None
    if not isinstance(rgb, str) or len(rgb) != 8:
        return False
    r, g, b = int(rgb[2:4], 16), int(rgb[4:6], 16), int(rgb[6:8], 16)
    return r >= 160 and g <= 90 and b <= 90


def read(path: Path, overrides: dict[str, dict] | None = None) -> tuple[list[dict], list[str], list[str]]:
    """返回（和 data/cards.json 不同的卡，红字格子的说明，对照表的提示）"""
    original = data.cards()
    overrides = overrides or {}
    changed, red, notes = [], [], []
    book = openpyxl.load_workbook(path)
    for kind, title in SHEETS.items():
        sheet = book[title]
        header = [c.value for c in sheet[1]]
        for row in sheet.iter_rows(min_row=2):
            cells = dict(zip(header, row, strict=False))
            card_id = cells["id"].value
            if not card_id:
                continue
            card = {k: v for k, v in original[card_id].items() if k in ("id", "no", "type", "races")}
            fields = {
                "star": int(cells["星级"].value),
                "strength": int(cells["战斗力"].value) if cells["战斗力"].value not in (None, "") else None,
                "timing_1": parse_timing(cells["时机-1"].value),
                "timing_2": parse_timing(cells["时机-2"].value),
                "skills_1": parse_skills(cells["基础技能-1"].value),
                "skills_2": parse_skills(cells["基础技能-2"].value),
                "special_skills": parse_special(cells["特殊技能（数据）"].value),
            }
            card.update({k: v for k, v in fields.items() if v is not None})
            assert card["type"] == kind, card_id
            text = cells["特殊技能（文字）"].value
            if (item := overrides.get(card_id)) and item["text"] != text:
                notes.append(f"{cells['名称'].value}（{card_id}）的文字变成了「{text}」，对照表里的数据不再套用")
            elif item and item["special"] is None:
                card.pop("special_skills", None)
            elif item:
                card["special_skills"] = item["special"]
            elif not item and not text and card.get("special_skills"):
                notes.append(f"{cells['名称'].value}（{card_id}）的文字是空的，数据列还有 {card['special_skills']}")
            if card != original[card_id]:
                changed.append(card)
            for name, cell in cells.items():
                if name and cell.value is not None and is_red(cell):
                    red.append(f"{title} {cells['名称'].value}（{card_id}）{name}：{cell.value}")
    return changed, red, notes


def main() -> None:
    command, path, *rest = sys.argv[1:]
    if command == "write":
        changed = json.loads(Path(rest[0]).read_text()) if rest else []
        notes = json.loads(Path(rest[1]).read_text()) if len(rest) > 1 else {}
        texts = design_texts(Path(rest[2])) if len(rest) > 2 else {}
        write(Path(path), changed, notes, texts)
    elif command == "read":
        overrides = json.loads(Path(rest[1]).read_text()) if len(rest) > 1 else {}
        changed, red, notes = read(Path(path), overrides)
        Path(rest[0]).write_text(json.dumps(changed, ensure_ascii=False, indent=1))
        original = data.cards()
        print(f"和正式数据不同的卡 {len(changed)} 张：")
        for card in changed:
            diff = {
                k: (original[card["id"]].get(k), card.get(k))
                for k in card.keys() | original[card["id"]].keys()
                if card.get(k) != original[card["id"]].get(k)
            }
            print(f"- {data.name(card['id'])}：" + "；".join(f"{k} {a} → {b}" for k, (a, b) in diff.items()))
        print(f"\n要留意的 {len(notes)} 处：")
        for line in notes:
            print(f"- {line}")
        print(f"\n红字格子 {len(red)} 个：")
        for line in red:
            print(f"- {line}")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
