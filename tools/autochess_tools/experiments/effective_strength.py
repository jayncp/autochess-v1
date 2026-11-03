"""复现 docs/design/balance-report-2026-11-01.md 2.2 节的角色有效战力表（1★ 环境和 2★ 环境）。

环境：1★ 环境是 5 个 1★ 角色组成的三人队，2★ 环境是 10 个 2★ 角色组成的三人队，都不带装备。
每个环境抽 SAMPLES 场对局（固定种子），数值有约 ±0.3 的抽样误差。
用法：just experiment effective_strength
"""

from autochess_tools import data
from autochess_tools.effective import effective_strengths, samples

SAMPLES = 6000
SEED = 20261103
# 2026-11-01 报告的数值（当时规则：坚固求和、平局 = 7 次不变或 20 轮无人阵亡；裸卡下坚固求和不起作用）
REPORT = {
    "angel": (5.1, 5.5),
    "soldier": (5.8, 6.7),
    "pixie": (6.0, 6.0),
    "sludge": (6.7, 7.6),
    "tiger": (7.0, 6.6),
    "maneater": (5.1, 10.0),
    "fairy": (10.6, 11.0),
    "porcupine": (9.1, 12.2),
    "shield_guard": (12.1, 12.4),
    "half_elf": (11.8, 12.6),
    "paladin": (11.2, 14.1),
    "dryad": (11.2, 15.1),
    "tiger_man": ("≥16", 15.1),
    "vulture": ("≥16", 15.8),
    "fey_tiger": ("≥16", 16.0),
}


def main() -> None:
    characters = data.ids("character")
    envs = {1: (data.ids("character", 1), 25), 2: (data.ids("character", 2), 50)}
    measured = {}
    for star, (env, cap) in envs.items():
        measured[star] = effective_strengths(characters, samples(env, SAMPLES, SEED + star), cap)
    print("| 卡 | 星 | 基础战力 | 1★环境 | 2★环境 | 报告 1★ / 2★ |")
    print("|---|---|---|---|---|---|")
    for c in sorted(characters, key=lambda c: (data.cards()[c]["star"], measured[2][c].value)):
        card = data.cards()[c]
        cells = [data.name(c), card["star"], card.get("strength"), measured[1][c], measured[2][c]]
        cells.append(" / ".join(str(v) for v in REPORT[c]))
        print("| " + " | ".join(str(x) for x in cells) + " |")
    for star in (1, 2):
        values = [measured[2][c].value for c in data.ids("character", star)]
        print(f"\n{star}★ 角色在 2★ 环境的平均有效战力：{sum(values) / len(values):.1f}")


if __name__ == "__main__":
    main()
