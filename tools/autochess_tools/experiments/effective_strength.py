"""当前卡池的有效战力：角色在 1★、2★ 环境，装备在 2★ 环境（宿主随机），再按宿主看几件装备。

环境：1★ 环境是全部非经济 1★ 角色组成的三人队，2★ 环境是全部非经济 2★ 角色组成的三人队，都不带装备。
经济卡（带财富的卡）照样测，但不进环境、不计入均值。抽样误差约 ±0.3。
方法见 autochess_tools/effective.py。
用法：just experiment effective_strength
"""

from dataclasses import replace

from autochess_tools import data
from autochess_tools.effective import Estimate, Sample, effective_strengths, equipment_values, samples

SAMPLES = 6000
EQUIPMENT_SAMPLES = 8000
PER_HOST_SAMPLES = 1500
SEED = 20261107
# 按宿主细看的装备：适配性强、上下限差距大的
PER_HOST = ["butterfly_wings", "hollow", "flash_orb"]


def mark(card_id: str) -> str:
    return data.name(card_id) + ("（经济）" if data.economy(card_id) else "")


def mean(values: dict[str, Estimate], card_ids: list[str]) -> float:
    return sum(values[i].value for i in card_ids) / len(card_ids)


def characters() -> None:
    all_ids = data.ids("character")
    measured = {}
    for star, cap in ((1, 25), (2, 50)):
        environment = samples(data.balance_ids("character", star), SAMPLES, SEED + star)
        measured[star] = effective_strengths(all_ids, environment, cap)
    print("## 角色\n")
    print("| 卡 | 星 | 战斗力 | 1★环境 | 2★环境 |")
    print("|---|---|---|---|---|")
    for c in sorted(all_ids, key=lambda c: (data.cards()[c]["star"], data.economy(c), measured[2][c].value)):
        card = data.cards()[c]
        print(f"| {mark(c)} | {card['star']} | {card.get('strength')} | {measured[1][c]} | {measured[2][c]} |")
    for star in (1, 2):
        ids = data.balance_ids("character", star)
        print(f"\n{star}★ 非经济角色（{len(ids)} 张）在 {star}★ 环境的平均有效战力：{mean(measured[star], ids):.1f}")


def equipment() -> None:
    hosts = data.balance_ids("character", 2)
    all_ids = data.ids("equipment")
    values = equipment_values(all_ids, samples(hosts, EQUIPMENT_SAMPLES, SEED), 40)
    print("\n## 装备（2★ 环境，宿主随机）\n")
    print("| 装备 | 星 | 有效战力 |")
    print("|---|---|---|")
    for e in sorted(all_ids, key=lambda e: (data.cards()[e]["star"], data.economy(e), values[e].value)):
        print(f"| {mark(e)} | {data.cards()[e]['star']} | {values[e]} |")
    for star in (1, 2):
        ids = data.balance_ids("equipment", star)
        print(f"\n{star}★ 非经济装备（{len(ids)} 件）平均：{mean(values, ids):.1f}")

    print("\n## 按宿主（2★ 环境）\n")
    print("| 宿主 | " + " | ".join(data.name(e) for e in PER_HOST) + " |")
    print("|---" * (len(PER_HOST) + 1) + "|")
    for host in hosts:
        battles: list[Sample] = [
            replace(s, team=tuple(host if i == s.position else c for i, c in enumerate(s.team)))
            for s in samples(hosts, PER_HOST_SAMPLES, SEED + 3)
        ]
        per_host = equipment_values(PER_HOST, battles, 40)
        print(f"| {data.name(host)} | " + " | ".join(str(per_host[e]) for e in PER_HOST) + " |")


def main() -> None:
    characters()
    equipment()


if __name__ == "__main__":
    main()
