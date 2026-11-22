"""把一份阶段搜索报告里各阶段的出场率填进卡牌设计表（"角色""装备"两页的"出场率·<阶段>"六列）。

用法（在 tools/ 下，需要依赖组 balance）：
  uv run --group balance python -m autochess_tools.balance.usage <设计表.xlsx> <报告.md> <说明>

说明写在表头的批注里，写清是哪一次搜索（如"2026-11-22 收尾版 g1"）。出场率是那一次搜索的快照：
改了任何一张卡，占同一个位置的卡都会跟着变，所以只在定版时整列重填，不要手改。
报告里没有的卡（经济卡、那个阶段还不能用的卡）留空。
"""

import sys
from pathlib import Path

import openpyxl
from openpyxl.comments import Comment

from autochess_tools import data
from autochess_tools.balance.trend import STAGES, load

PREFIX = "出场率·"
SHEETS = ("角色", "装备")
ALIASES = {
    "念珠": "sludge_bolt",
    "白狼图腾": "legion_shield",
    "神庙核心": "poison_dagger",
    "精灵神杖": "yata_mirror",
    "虚无之心": "golden_chainmail",
}
"""2026-11-22 的报告里 5 件装备还是改名之前的名字"""


def fill(book_path: Path, report: Path, note: str) -> int:
    """整列重填，返回填了数的格子数。"""
    ids = {data.name(card_id): card_id for card_id in data.cards()} | ALIASES
    usage: dict[str, dict[str, float]] = {}
    for stage, cards in load(report).items():
        for name, card in cards.items():
            usage.setdefault(ids[name], {})[stage] = card["usage"]
    book = openpyxl.load_workbook(book_path)
    filled = 0
    for title in SHEETS:
        sheet = book[title]
        head = {cell.value: cell.column for cell in sheet[1]}
        id_column = head["id"]
        for stage in STAGES:
            column = head[PREFIX + stage]
            text = f"{note}。带这张卡的阵容在均衡分布里的占比（%），空着是这个阶段不能用或没有参与搜索。"
            sheet.cell(1, column).comment = Comment(text, "balance.usage")
            for row in range(2, sheet.max_row + 1):
                value = usage.get(sheet.cell(row, id_column).value, {}).get(stage)
                sheet.cell(row, column).value = value
                filled += value is not None
    book.save(book_path)
    return filled


if __name__ == "__main__":
    path, report, note = sys.argv[1:]
    print(f"{path}：填了 {fill(Path(path), Path(report), note)} 格")
