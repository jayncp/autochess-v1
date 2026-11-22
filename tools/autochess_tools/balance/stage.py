"""一个阶段的阵容搜索：均衡阵容、各档卡位的占比、每张卡的出场率和带卡得分。
报告（Markdown）打印到标准输出，进度打印到标准错误。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.balance.stage <阶段> [--change 改动.json] [--warm 目录 ...] [--save 目录]
      [--seed N] [--rounds N] [--ban id,id]

--change：改过的卡（JSON 数组，同 id 覆盖正式数据）；--warm：从这些目录里存的阵容出发；
--save：把这次的阵容存到这个目录。
六个阶段一起跑用 autochess_tools.balance.run。
"""

import argparse
import json
import sys
import time
from collections import defaultdict
from pathlib import Path

import numpy as np

from autochess_tools import data
from autochess_tools.balance.meta import STAGES, Cards, Meta, build, contains, load_pools, save_pool, scores

RACES = {"beast": "动物", "human": "人族", "elf": "精灵", "divine": "神族", "nature": "自然"}


def report(meta: Meta) -> None:
    space, cards = meta.space, meta.space.cards
    stage = space.stage
    opponents, weights = meta.opponents(mass=0.999, cap=3000)
    print(f"\n## {stage.name}（最高 {stage.max_star}★，卡位：总星 {stage.options}，装备 ≤{stage.max_equips} 件）\n")
    print(
        f"阵容库 {len(meta.pool)} 套，均衡分布里 {len(opponents)} 套（按权重折算 {1 / (weights**2).sum():.0f} 套），"
        f"权重最大的一套占 {weights.max():.1%}。\n"
    )

    print("**各档卡位在均衡里的占比**（角色数 / 平均角色星 / 平均装备星 / 装备件数）\n")
    by_option: dict[int, list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0, 0.0])
    for lineup, w in zip(opponents, weights, strict=True):
        row = by_option[space.option(lineup)]
        row[0] += w
        row[1] += w * len(lineup)
        row[2] += w * sum(cards.star[c] for c, _ in lineup)
        row[3] += w * sum(cards.star[e] for _, e in lineup if e >= 0)
        row[4] += w * sum(e >= 0 for _, e in lineup)
    for slots, budget in stage.options:
        w, n, cs, es, ne = by_option[slots]
        if w > 0:
            print(
                f"- {slots} 卡位（{budget} 星）：{w:.1%}，{n / w:.1f} 人，"
                f"角色 {cs / w:.1f} 星，装备 {es / w:.1f} 星、{ne / w:.1f} 件"
            )
        else:
            print(f"- {slots} 卡位（{budget} 星）：0%")

    print("\n**均衡里权重最大的阵容**\n")
    for i in np.argsort(-weights)[:12]:
        print(f"- {weights[i]:.1%}　{cards.show(opponents[i])}")

    usage: dict[int, float] = defaultdict(float)
    race: dict[str, float] = defaultdict(float)
    units = 0.0
    for lineup, w in zip(opponents, weights, strict=True):
        for card in {x for unit in lineup for x in unit if x >= 0}:
            usage[card] += w
        for c, _ in lineup:
            for r in data.cards()[cards.ids[c]].get("races", []):
                race[r] += w
            units += w
    print(
        "\n**种族占比**（按角色计，双种族各算一次）："
        + "、".join(f"{RACES.get(r, r)} {race[r] / units:.0%}" for r in RACES)
    )

    forced = meta.forced()
    for kind, pool in (("角色", space.chars), ("装备", space.equips)):
        print(
            f"\n**{kind}**：出场率是均衡分布里带这张卡的阵容占比；"
            "带卡最优是必须带它时最强阵容对均衡分布的得分（0.5 为持平）\n"
        )
        print("| 卡 | 星 | 出场率 | 带卡最优 | 带卡最优的阵容 |")
        print("|---|---|---|---|---|")
        for card in sorted(pool, key=lambda c: (cards.star[c], -forced[c][0])):
            value, lineup = forced[card]
            print(
                f"| {cards.name(card)} | {cards.star[card]} | {usage[card]:.1%} | {value:.3f} | {cards.show(lineup)} |"
            )

    print("\n**站位的影响**：均衡里权重最大的 10 套，随机打乱站位（装备跟着角色）后对均衡分布的得分\n")
    rng = space.rng
    top = [opponents[i] for i in np.argsort(-weights)[:10]]
    for lineup in top:
        shuffled = [tuple(rng.sample(lineup, len(lineup))) for _ in range(40)]
        values = scores(cards, [lineup, *shuffled], opponents) @ weights
        print(
            f"- 原站位 {values[0]:.3f}，打乱后平均 {values[1:].mean():.3f}"
            f"（{values[1:].min():.3f}–{values[1:].max():.3f}）　{cards.show(lineup)}"
        )

    assert all(contains(forced[c][1], c) for c in forced)


def main() -> None:
    parser = argparse.ArgumentParser(description="一个阶段的阵容搜索")
    parser.add_argument("stage", choices=[s.name for s in STAGES])
    parser.add_argument("--change", type=Path, help="改过的卡（JSON 数组）")
    parser.add_argument("--warm", type=Path, nargs="*", default=[], help="从这些目录里存的阵容出发")
    parser.add_argument("--save", type=Path, help="把这次的阵容存到这个目录")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--rounds", type=int, default=80, help="每次扩充阵容库最多几轮")
    parser.add_argument("--ban", default="", help="这次不让用的卡，id 用逗号隔开")
    args = parser.parse_args()

    start = time.time()
    changed = json.loads(args.change.read_text()) if args.change else []
    cards = Cards(changed, [x for x in args.ban.split(",") if x])
    stage = next(s for s in STAGES if s.name == args.stage)

    def log(text: str) -> None:
        print(text, file=sys.stderr, flush=True)

    meta = build(
        stage, seed=args.seed, rounds=args.rounds, log=log, cards=cards, warm=load_pools(args.warm, stage.name)
    )
    if args.save:
        save_pool(meta, args.save)
    report(meta)
    log(f"\n用时 {time.time() - start:.0f} 秒")


if __name__ == "__main__":
    main()
