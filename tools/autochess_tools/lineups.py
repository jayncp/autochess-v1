"""随机对局（固定种子），供对拍和测速：每方 1–7 人，从全部正式卡里抽（各星级，含经济卡），允许同名卡。

机制密集的对局多从带特殊机制的卡里抽：带参数的特殊技能（描述型效果、唤醒、神佑），以及协战、免疫致命、
千机之匣这类，让少见的组合多出现。
"""

import random
from collections.abc import Sequence

from autochess_tools import data

type Battle = tuple[list[list[str]], list[list[str]]]
"""一场对局：双方阵容 [[角色 id, 装备 id], ...]，装备为空字符串表示不带。"""

SIZES = (1, 7)
EQUIP_RATE = 0.6
"""每个角色带装备的概率"""
DENSE_RATE = 0.75
"""机制密集的对局里，每个角色、每件装备从带特殊机制的卡里抽的概率"""
MECHANICS = frozenset({"assist", "immune_lethal", "double_skills", "halve_pre_battle_damage"})
"""不写参数、但也算特殊机制的特殊技能（写参数的都算）"""


def has_mechanics(card: data.Card) -> bool:
    special = card.get("special_skills")
    return isinstance(special, dict) and any(isinstance(v, dict) or k in MECHANICS for k, v in special.items())


def random_battles(
    count: int,
    seed: int,
    *,
    dense: bool = False,
    equip_rate: float = EQUIP_RATE,
    extra_cards: Sequence[data.Card] = (),
) -> list[Battle]:
    """count 场随机对局。dense 为真时是机制密集的对局。extra_cards：额外的卡（同 id 覆盖正式卡），也参与抽样。"""
    rng = random.Random(seed)
    cards = list((data.cards() | {c["id"]: c for c in extra_cards}).values())
    pools = {}
    for kind in ("character", "equipment"):
        pool = [c for c in cards if c["type"] == kind]
        pools[kind] = ([c["id"] for c in pool], [c["id"] for c in pool if has_mechanics(c)])

    def pick(kind: str) -> str:
        common, special = pools[kind]
        return rng.choice(special if dense and rng.random() < DENSE_RATE else common)

    def lineup() -> list[list[str]]:
        size = rng.randint(*SIZES)
        return [[pick("character"), pick("equipment") if rng.random() < equip_rate else ""] for _ in range(size)]

    return [(lineup(), lineup()) for _ in range(count)]


def mixed_battles(
    count: int, seed: int, equip_rate: float = EQUIP_RATE, extra_cards: Sequence[data.Card] = ()
) -> list[Battle]:
    """前一半是普通对局，后一半是机制密集的对局。"""
    normal = count - count // 2
    return random_battles(normal, seed, equip_rate=equip_rate, extra_cards=extra_cards) + random_battles(
        count // 2, seed + 1, dense=True, equip_rate=equip_rate, extra_cards=extra_cards
    )
