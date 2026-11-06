"""读取游戏数据：data/cards.json、data/levels.json，以及 i18n/data.csv 里的中文名。"""

import csv
import json
from functools import cache
from pathlib import Path
from typing import NotRequired, TypedDict

REPO = Path(__file__).resolve().parents[2]


class Card(TypedDict):
    """卡牌数据，字段说明见 data/README.md。"""

    id: str
    no: int
    type: str
    star: int
    races: NotRequired[list[str]]
    strength: NotRequired[int]
    timing_1: NotRequired[str]
    timing_2: NotRequired[str]
    skills_1: NotRequired[dict[str, int | None] | str]
    skills_2: NotRequired[dict[str, int | None] | str]
    special_skills: NotRequired[dict[str, int | None] | str]


@cache
def cards() -> dict[str, Card]:
    """全部卡牌：id -> 卡牌，顺序与文件一致。"""
    with (REPO / "data" / "cards.json").open(encoding="utf-8") as f:
        return {c["id"]: c for c in json.load(f)}


def ids(card_type: str, star: int | None = None) -> list[str]:
    """某一类型（character / equipment）的全部 id，可按星级筛选。"""
    return [c["id"] for c in cards().values() if c["type"] == card_type and (star is None or c["star"] == star)]


@cache
def texts() -> dict[str, str]:
    """翻译表 i18n/data.csv：key -> 中文。"""
    with (REPO / "i18n" / "data.csv").open(encoding="utf-8", newline="") as f:
        return {row["keys"]: row["zh_CN"] for row in csv.DictReader(f)}


def name(card_id: str) -> str:
    """卡牌的中文名；不在翻译表里的（如实验用的白板）返回 id。"""
    return texts().get(f"card.{card_id}", card_id)
