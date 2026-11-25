"""给一轮阵容搜索的均衡阵容算价格：每套阵容的期望花费、花费的分布、第几回合能凑齐。

用法（在 tools/ 下）：
  uv run --group balance python -m autochess_tools.economy.price [阵容目录] [--shops 5/1,4/2] [--round-xp 2,3]
      [--runs N] [--workers N] [--out 文件.json]

--shops：要比较的商店格子数（角色/装备）；--round-xp：要比较的每回合经验。默认都只算表格里的。

阵容目录是阵容搜索存下的阵容（默认 balance/pools），均衡分布按现在的正式数据重新求。
结果默认写到 balance/runs/economy.json。
"""

import argparse
import json
import os
import random
import statistics
import sys
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict, replace
from itertools import product
from pathlib import Path

import numpy as np

from autochess_tools import data
from autochess_tools.balance import DATA
from autochess_tools.balance.meta import STAGES, Cards, Meta, Space, load_pools
from autochess_tools.economy.model import MAX_LEVEL, Economy, Plan, load, simulate, target

RESERVES = (10, 20, 30)
"""存钱打法试的几档：手里留多少金币"""


def equilibrium(stage_name: str, directory: Path) -> list[tuple[list[list[str]], float]]:
    """这个阶段均衡分布里的阵容和权重。"""
    stage = next(s for s in STAGES if s.name == stage_name)
    cards = Cards()
    space = Space(cards, stage, random.Random(1))
    index = {card: k for k, card in enumerate(cards.ids)}
    known = [tuple((index[c], index[e] if e else -1) for c, e in x) for x in load_pools([directory], stage_name)]
    meta = Meta(space)
    meta.add([x for x in known if space.legal(x)])
    meta.solve()
    lineups, weights = meta.opponents(mass=0.999, cap=3000)
    return [
        ([[cards.ids[c], cards.ids[e] if e >= 0 else ""] for c, e in lineup], float(w))
        for lineup, w in zip(lineups, weights, strict=True)
    ]


def quantiles(values: list[int]) -> dict[str, float]:
    ordered = sorted(values)
    pick = lambda q: ordered[min(len(ordered) - 1, int(q * len(ordered)))]  # noqa: E731
    return {"mean": statistics.fmean(values), "p10": pick(0.1), "p50": pick(0.5), "p90": pick(0.9)}


def price(job: tuple[Economy, list[list[str]], int, int]) -> dict:
    eco, lineup, runs, seed = job
    goal = target(lineup)
    plan = Plan(eco, goal)
    rng = random.Random(seed)
    gold = [simulate(plan, rng, timed=False) for _ in range(runs)]
    rush = [simulate(plan, rng, timed=True) for _ in range(runs)]
    saved = {reserve: [simulate(plan, rng, timed=True, reserve=reserve) for _ in range(runs)] for reserve in RESERVES}
    reserve = min(saved, key=lambda k: statistics.fmean(r.round for r in saved[k]))
    timed = saved[reserve]
    if statistics.fmean(r.round for r in rush) <= statistics.fmean(r.round for r in timed):
        reserve, timed = 0, rush
    stars = lambda kind: sum(s * n for k, s, n in goal.cards if k == kind)  # noqa: E731
    return {
        "units": goal.units,
        "equips": sum(n for k, _, n in goal.cards if k == 1),
        "char_stars": stars(0),
        "equip_stars": stars(1),
        "cost": plan.cost,
        "gold": quantiles([r.gold for r in gold]),
        "xp": statistics.fmean(r.xp for r in gold),
        "rolls": statistics.fmean(r.rolls for r in gold),
        "level": statistics.fmean(r.level for r in gold),
        "round": quantiles([r.round for r in timed]),
        "rush_round": statistics.fmean(r.round for r in rush),
        "reserve": reserve,
        "interest": statistics.fmean(r.interest for r in timed),
        "timed_gold": statistics.fmean(r.gold for r in timed),
        "timed_level": statistics.fmean(r.level for r in timed),
    }


def show(lineup: list[list[str]]) -> str:
    return " / ".join(data.name(c) + (f"+{data.name(e)}" if e else "") for c, e in lineup)


def single_cards(eco: Economy) -> list[dict]:
    """只要一张指定的卡：各等级刷出来平均要几次。"""
    rows = []
    for kind in (0, 1):
        for star in range(1, 6):
            row = {"kind": kind, "star": star, "rolls": []}
            for level in range(1, MAX_LEVEL + 1):
                p = eco.odds[level - 1][star - 1] / eco.kinds[kind][star - 1]
                row["rolls"].append(1 / (1 - (1 - p) ** eco.shop[kind]) if p > 0 else None)
            rows.append(row)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="均衡阵容的价格")
    parser.add_argument("pools", type=Path, nargs="?", default=DATA / "pools")
    parser.add_argument("--shops", default="", help="商店格子数（角色/装备），逗号隔开，如 5/1,4/2")
    parser.add_argument("--round-xp", default="", help="每回合经验，逗号隔开，如 2,3")
    parser.add_argument("--runs", type=int, default=500, help="每套阵容每种打法模拟几次")
    parser.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 2) // 2), help="进程数，默认一半核心")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    base = load()
    shops = [tuple(int(x) for x in s.split("/")) for s in args.shops.split(",") if s] or [base.shop]
    round_xps = [int(x) for x in args.round_xp.split(",") if x] or [base.round_xp]
    mixes = {stage.name: equilibrium(stage.name, args.pools) for stage in STAGES}
    configs = {}
    with ProcessPoolExecutor(args.workers) as pool:
        for shop, round_xp in product(shops, round_xps):
            eco = replace(base, shop=shop, round_xp=round_xp)
            name = (
                "，".join(
                    [f"{shop[0]} 角色 + {shop[1]} 装备"] * (len(shops) > 1)
                    + [f"每回合 {round_xp} 经验"] * (len(round_xps) > 1)
                )
                or "表格里的数"
            )
            stages = {}
            for stage in STAGES:
                mix = mixes[stage.name]
                jobs = [(eco, lineup, args.runs, k) for k, (lineup, _) in enumerate(mix)]
                rows = list(pool.map(price, jobs, chunksize=4))
                for row, (lineup, weight) in zip(rows, mix, strict=True):
                    row |= {"lineup": show(lineup), "weight": weight}
                stages[stage.name] = {
                    "max_star": stage.max_star,
                    "options": stage.options,
                    "max_equips": stage.max_equips,
                    "lineups": rows,
                }
                w = np.array([r["weight"] for r in rows])
                print(
                    f"{name} {stage.name}：{len(rows)} 套，期望花费 {w @ [r['cost'] for r in rows]:.0f}，"
                    f"凑齐的回合 {w @ [r['round']['mean'] for r in rows]:.1f}"
                    f"（不存钱 {w @ [r['rush_round'] for r in rows]:.1f}）",
                    file=sys.stderr,
                )
            configs[name] = {"economy": asdict(eco), "single": single_cards(eco), "stages": stages}
    out = args.out or DATA / "runs" / "economy.json"
    out.write_text(json.dumps({"configs": configs}, ensure_ascii=False))
    print(f"写到 {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
