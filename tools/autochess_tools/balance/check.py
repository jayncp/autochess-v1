"""复核一张卡是不是真的弱：把它挂到均衡里每套阵容的每个位置上当起点，再爬山。

常规搜索里没人用的卡，带卡得分可能被低估很多（每张卡只有几个起点）。对一张卡下"太弱"的结论之前先用这个量一次：
最好的阵容接近 0.50 是"有位置但没被选中"，明显低于 0.47 才是带上就亏。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.balance.check --cards id,id [--stages 阶段 ...] [--change 改动.json]
      [--pools 目录 ...] [--save 目录]

--save：把找到的阵容存成 <目录>/<阶段>-check.json，下一轮搜索时把这个目录加进 --warm，才能看到这些卡真实的出场率。
"""

import argparse
import json
import random
from pathlib import Path

import numpy as np

from autochess_tools import data
from autochess_tools.balance.meta import STAGES, Cards, Meta, Space, contains, load_pools
from autochess_tools.balance.run import ROOT


def main() -> None:
    names = [s.name for s in STAGES]
    parser = argparse.ArgumentParser(description="加大力度的带卡搜索")
    parser.add_argument("--cards", required=True, help="要复核的卡，id 用逗号隔开")
    parser.add_argument("--stages", nargs="*", default=names, choices=names)
    parser.add_argument("--change", type=Path, default=ROOT / "trial.json")
    parser.add_argument("--pools", type=Path, nargs="*", default=[ROOT / "pools"])
    parser.add_argument("--save", type=Path)
    args = parser.parse_args()

    cards = Cards(json.loads(args.change.read_text()))
    index = {card: k for k, card in enumerate(cards.ids)}
    for stage in STAGES:
        if stage.name not in args.stages:
            continue
        space = Space(cards, stage, random.Random(7))
        meta = Meta(space)
        known = [tuple((index[c], index[e] if e else -1) for c, e in x) for x in load_pools(args.pools, stage.name)]
        meta.add([x for x in known if space.legal(x)])
        meta.solve()
        opponents, _ = meta.opponents()
        found = []
        for card_id in args.cards.split(","):
            card = index[card_id]
            if card not in space.chars + space.equips:
                continue  # 这个阶段还用不了
            starts = []
            for base in opponents:
                for i in range(len(base)):
                    units = list(base)
                    units[i] = (card, units[i][1]) if cards.kind[card] == "character" else (units[i][0], card)
                    fixed = space.repair(tuple(units), card)
                    if fixed is not None and contains(fixed, card):
                        starts.append(fixed)
            starts = list(dict.fromkeys(starts))
            lineups, value = meta.climb(starts, [card] * len(starts), 40, 16)
            best = list(dict.fromkeys(lineups[i] for i in np.argsort(-value)))[:40]
            found += best
            print(
                f"{stage.name} {data.name(card_id)}：{len(starts)} 个起点，最好 {value.max():.3f}，"
                f"得分不低于 0.50 的 {int((value >= 0.5).sum())} 个"
            )
            for lineup in best[:3]:
                print(f"    {value[lineups.index(lineup)]:.3f}  {cards.show(lineup)}", flush=True)
        if args.save and found:
            args.save.mkdir(parents=True, exist_ok=True)
            ids = [[[cards.ids[c], cards.ids[e] if e >= 0 else ""] for c, e in lineup] for lineup in found]
            (args.save / f"{stage.name}-check.json").write_text(json.dumps(ids, ensure_ascii=False))


if __name__ == "__main__":
    main()
