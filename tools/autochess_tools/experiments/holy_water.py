"""圣水补偿校准：圣水改为"仅战前时机 + N 战力"后，N 取多少合适。

在 2★ 环境（10 个 2★ 角色组成的三人队，对手不带装备）里测装备的有效战力：
给被测位置的角色装上装备，相当于装上多大战力的白板武器。木剑、铁剑本身就是白板武器，应正好测出 5 和 8（自检）。
圣水的价值取决于宿主（战前时机让宿主的入场、交战技能多触发一次），所以再按宿主分别算。
用法：just experiment holy_water
"""

from dataclasses import replace

from autochess_tools import data
from autochess_tools.data import Card
from autochess_tools.effective import Sample, equipment_values, samples

SAMPLES = 8000
PER_HOST_SAMPLES = 1500
SEED = 20261103
MAX_SWORD = 40
BONUSES = range(5)


def holy_water(bonus: int) -> Card:
    card: Card = {"id": f"holy_water_{bonus}", "no": 0, "type": "equipment", "star": 2, "timing_2": "pre_battle"}
    if bonus:
        card["strength"] = bonus
    return card


# 改动之前的圣水：战前时机 + 振奋1，没有战力
OLD_HOLY_WATER: Card = {
    "id": "holy_water_old",
    "no": 0,
    "type": "equipment",
    "star": 2,
    "timing_2": "pre_battle",
    "skills_2": {"inspire": 1},
}
VARIANTS = [holy_water(b) for b in BONUSES] + [OLD_HOLY_WATER]
LABELS = {f"holy_water_{b}": f"圣水 +{b}" for b in BONUSES} | {"holy_water_old": "旧版圣水（振奋1）"}


def label(equip_id: str) -> str:
    return LABELS.get(equip_id, data.name(equip_id))


def main() -> None:
    hosts = data.ids("character", 2)
    battles = samples(hosts, SAMPLES, SEED)
    equipment = data.ids("equipment") + [v["id"] for v in VARIANTS]
    values = equipment_values(equipment, battles, MAX_SWORD, VARIANTS)
    print("## 装备有效战力（2★ 环境，宿主随机）\n")
    print("| 装备 | 星 | 有效战力 |")
    print("|---|---|---|")
    stars = {c["id"]: c["star"] for c in [*data.cards().values(), *VARIANTS]}
    for e in sorted(equipment, key=lambda e: (stars[e], values[e].value)):
        print(f"| {label(e)} | {stars[e]} | {values[e]} |")
    for star in (1, 2):
        real = [values[e].value for e in data.ids("equipment") if stars[e] == star]
        print(f"\n{star}★ 装备平均：{sum(real) / len(real):.1f}")

    print("\n## 圣水各版本按宿主（2★ 环境）\n")
    variant_ids = [v["id"] for v in VARIANTS]
    print("| 宿主 | " + " | ".join(label(v) for v in variant_ids) + " | 铁剑 |")
    print("|---" * (len(variant_ids) + 2) + "|")
    for host in hosts:
        host_battles: list[Sample] = [
            replace(s, team=tuple(host if i == s.position else c for i, c in enumerate(s.team)))
            for s in samples(hosts, PER_HOST_SAMPLES, SEED + 1)
        ]
        per_host = equipment_values([*variant_ids, "iron_sword"], host_battles, MAX_SWORD, VARIANTS)
        cells = [str(per_host[v]) for v in [*variant_ids, "iron_sword"]]
        print(f"| {data.name(host)} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
