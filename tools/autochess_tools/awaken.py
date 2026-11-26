"""卡牌觉醒：三张相同的角色合成一张更强的。这里是"怎么变强"的规则（规则的说明见 docs/design/awakening.md）。

用法（在 tools/ 下）：
  uv run --group balance python -m autochess_tools.awaken [设计表.xlsx] [觉醒方案.json]
把各角色的觉醒方案、原版和觉醒后的数值写进设计表的"觉醒"页（整页重写），默认是
docs/design/card-workbook.xlsx 和 balance/awaken-templates.json。

觉醒方案：每张角色三个倍数 [战力, 基础技能, 特殊技能]，各是 1（不变）、1.5、2。
- 战力、基础技能的数值乘倍数，四舍五入。
- 特殊技能：带数值的（词条的数值、参数 amount）乘倍数，四舍五入；
  "多结算一次""多触发一轮""额外获得一份"变成两次、两轮、两份（数据里写 times 2）；
  范围"下两位""对方前两位"变成"下四位""对方前四位"。后两种没有 1.5 倍，只要不是 1 就加强。
- 不带数值的词条（致命、协战、免疫致命）和没有数值的效果（唤醒、清除、一半、减半、之和）不变。
- 个别数值不按倍数算，写在 OVERRIDES 里。
times 和两个新范围现在只有 Rust 版认。
"""

import copy
import json
import sys
from pathlib import Path

from autochess_tools import data

SUFFIX = "_awakened"
SKILLS = {
    "rage": "狂暴",
    "rally": "集结",
    "support": "支援",
    "inspire": "振奋",
    "corrode": "腐蚀",
    "annihilate": "湮灭",
    "wealth": "财富",
}
NUMBERS = {1: "一", 2: "两"}
UNITS = {"extra_resolve": "次", "extra_round": "轮", "copy_skills": "份"}
"""按次数算的效果：觉醒后是两次，数据里写 times（原版不写，等于 1）"""
OVERRIDES = {("clockwork_witch", "equipment_times"): 4}
"""不按倍数算的数值：(角色 id, 效果) -> 觉醒后的 amount（千机魔女 3 倍 → 4 倍，记作特殊技能 ×1.5）"""
WIDER = {"next_two": "next_four", "enemy_first_two": "enemy_first_four"}
WIDER_NAMES = {"next_four": "下四位", "enemy_first_four": "对方前四位"}
DIMENSIONS = ("战力", "基础技能", "特殊技能")
TEMPLATES = Path(__file__).parents[1] / "balance" / "awaken-templates.json"
WORKBOOK = Path(__file__).parents[2] / "docs" / "design" / "card-workbook.xlsx"
SHEET = "觉醒"


def scaled(value: int, factor: float) -> int:
    """乘上倍数，四舍五入。"""
    return int(value * factor + 0.5)


def label(rule: list[float]) -> str:
    """觉醒方案的写法：战力 ×2 + 基础技能 ×1.5。"""
    return " + ".join(f"{name} ×{factor:g}" for name, factor in zip(DIMENSIONS, rule, strict=True) if factor != 1)


def awakened(card: data.Card, strength: float = 2, skills: float = 2, special: float = 2) -> data.Card:
    """一张角色的觉醒版（新 id：原 id 加 _awakened）。三个参数是战力、基础技能、特殊技能的倍数。"""
    new = copy.deepcopy(card)
    new["id"] = card["id"] + SUFFIX
    new["strength"] = scaled(card.get("strength", 0), strength)
    for slot in ("skills_1", "skills_2"):
        values = new.get(slot)
        if isinstance(values, dict):
            new[slot] = {skill: scaled(value, skills) for skill, value in values.items()}
    special_skills = new.get("special_skills")
    if special != 1 and isinstance(special_skills, dict):
        for effect, value in special_skills.items():
            if isinstance(value, int):
                special_skills[effect] = scaled(value, special)
            elif effect in UNITS:
                special_skills[effect] = {**(value or {}), "times": 2}
            elif isinstance(value, dict):
                amount = value.get("amount")
                if isinstance(amount, int):
                    value["amount"] = OVERRIDES.get((card["id"], effect), scaled(amount, special))
                wider = WIDER.get(str(value.get("target")))
                if wider:
                    value["target"] = wider
    return new


def skill_text(skills) -> str:
    return "、".join(f"{SKILLS[k]}{v}" for k, v in skills.items()) if isinstance(skills, dict) else ""


def special_text(special) -> str:
    """特殊技能的卡面文字（和游戏里的写法一致，用来对照）。"""
    if not isinstance(special, dict):
        return ""
    texts = data.texts()
    parts = []
    for effect, value in special.items():
        params = value if isinstance(value, dict) else {}
        if f"keyword.{effect}" in texts:
            amount = value if isinstance(value, int) else params.get("amount")
            body = texts[f"keyword.{effect}"] + (str(amount) if amount else "")
        else:
            skill = params.get("skill")
            name = "任意基础技能" if skill == "any" else texts.get(f"keyword.{skill}", SKILLS.get(str(skill), ""))
            body = texts[f"effect.{effect}"].format(
                scope=texts.get(f"scope.{params.get('scope')}", ""),
                target=texts.get(f"target.{params.get('target')}", WIDER_NAMES.get(str(params.get("target")), "")),
                timing=texts.get(f"timing.{params.get('timing')}", ""),
                skill=name,
                skill_value="基础技能数值" if skill == "any" else f"{name}值",
                amount=params.get("amount") or "",
            )
            if effect in UNITS and params.get("times", 1) != 1:
                unit = UNITS[effect]
                body = body.replace(f"一{unit}", f"{NUMBERS[params['times']]}{unit}")
        timings = "、".join(texts[f"timing.{t}"] for t in params.get("timings", []))
        parts.append(f"{timings}：{body}" if timings else body)
    return "；".join(parts)


def characters() -> list[data.Card]:
    return [card for card in data.cards().values() if card["type"] == "character"]


def describe(card: data.Card) -> tuple[int, str, str]:
    """一张卡的战力、基础技能、特殊技能（卡面的写法）。"""
    skills = "、".join(text for text in (skill_text(card.get("skills_1")), skill_text(card.get("skills_2"))) if text)
    return card.get("strength", 0), skills, special_text(card.get("special_skills"))


def write_sheet(book_path: Path, templates: Path) -> None:
    import openpyxl
    from openpyxl.comments import Comment
    from openpyxl.styles import Alignment, Font, PatternFill

    texts = data.texts()
    chosen = json.loads(templates.read_text())
    book = openpyxl.load_workbook(book_path)
    if SHEET in book.sheetnames:
        del book[SHEET]
    sheet = book.create_sheet(SHEET, book.sheetnames.index("装备") + 1)
    columns = [
        ("序号", 7),
        ("id", 18),
        ("名称", 12),
        ("星级", 6),
        ("种族", 12),
        ("觉醒方案", 30),
        *((f"{name}倍数", 9) for name in DIMENSIONS),
        ("战斗力", 8),
        ("基础技能", 18),
        ("特殊技能", 44),
        ("觉醒·战斗力", 12),
        ("觉醒·基础技能", 18),
        ("觉醒·特殊技能", 44),
    ]
    sheet.append([name for name, _ in columns])
    wrap = Alignment(wrap_text=True, vertical="top")
    for k, (_, width) in enumerate(columns, 1):
        cell = sheet.cell(1, k)
        cell.font = Font(bold=True)
        cell.fill = PatternFill("solid", fgColor="DDEBF7" if k >= 13 else "F2F2F2")
        sheet.column_dimensions[cell.column_letter].width = width
    for card in characters():
        rule = chosen[card["id"]]
        races = "、".join(texts[f"race.{r}"] for r in card.get("races", []))
        row = [card["no"], card["id"], data.name(card["id"]), card["star"], races, label(rule), *rule]
        sheet.append([*row, *describe(card), *describe(awakened(card, *rule))])
        for cell in sheet[sheet.max_row]:
            cell.alignment = wrap
    note = (
        f"由脚本从 {templates.name} 生成（just awaken），整页重写，不要手改；规则见 docs/design/awakening.md。"
        "三个倍数各是 1（不变）、1.5、2，蓝色表头的三列是觉醒后的数值。"
    )
    sheet.cell(1, 6).comment = Comment(note, "awaken")
    sheet.freeze_panes = "D2"
    book.save(book_path)
    print(f"{book_path}：“{SHEET}”页 {sheet.max_row - 1} 张角色")


if __name__ == "__main__":
    paths = [Path(arg) for arg in sys.argv[1:]]
    write_sheet(*(paths + [WORKBOOK, TEMPLATES][len(paths) :]))
