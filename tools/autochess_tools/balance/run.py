"""六个阶段各开一个进程同时搜索，合成一份报告。本机和集群都这样跑，线程数按机器的核心数分。

用法（在 tools/ 下）：
  uv run python -m autochess_tools.balance.run <名字> [--change 改动.json] [--warm 目录 ...]
      [--stages 阶段 ...] [--threads 每个进程的线程数] [--seed N] [--rounds N] [--out 目录]

结果在 <out>/<名字>/：report.md（六个阶段合在一起）、<阶段>.md、<阶段>.log（进度）、pools/（这次的阵容，下次的起点）。
--warm 不写时用 balance/pools；建议把最近三四轮的 pools 目录都写上。
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from autochess_tools.balance import DATA
from autochess_tools.balance.meta import STAGES


def main() -> None:
    names = [s.name for s in STAGES]
    parser = argparse.ArgumentParser(description="六个阶段同时搜索")
    parser.add_argument("name", help="这一轮的名字，也是结果目录的名字")
    parser.add_argument("--change", type=Path, default=DATA / "trial.json", help="改过的卡，默认 balance/trial.json")
    parser.add_argument("--warm", type=Path, nargs="*", default=[DATA / "pools"], help="起点阵容的目录，可以写几个")
    parser.add_argument("--stages", nargs="*", default=names, choices=names)
    parser.add_argument("--threads", type=int, help="每个进程的线程数，默认是核心数除以阶段数")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--rounds", type=int, default=80)
    parser.add_argument("--out", type=Path, default=DATA / "runs")
    args = parser.parse_args()

    out = args.out / args.name
    out.mkdir(parents=True, exist_ok=True)
    threads = args.threads or max(1, (os.cpu_count() or 1) // len(args.stages))
    # 求均衡用 numpy，线程给多了反而和模拟抢核心
    env = os.environ | {"RAYON_NUM_THREADS": str(threads), "OMP_NUM_THREADS": "2", "OPENBLAS_NUM_THREADS": "2"}
    start = time.time()
    running = {}
    for stage in args.stages:
        command = [sys.executable, "-m", "autochess_tools.balance.stage", stage, "--change", str(args.change)]
        command += ["--warm", *map(str, args.warm), "--save", str(out / "pools")]
        command += ["--seed", str(args.seed), "--rounds", str(args.rounds)]
        with (out / f"{stage}.md").open("w") as report, (out / f"{stage}.log").open("w") as log:
            running[stage] = subprocess.Popen(command, stdout=report, stderr=log, env=env)
    print(f"{len(running)} 个阶段在跑，每个 {threads} 线程，进度看 {out}/<阶段>.log")
    failed = [stage for stage, process in running.items() if process.wait() != 0]
    for stage in running:
        print(f"  {stage}：{'失败，见日志' if stage in failed else '完成'}")
    if failed:
        raise SystemExit(1)
    (out / "report.md").write_text("".join((out / f"{stage}.md").read_text() for stage in args.stages))
    print(f"用时 {time.time() - start:.0f} 秒，报告在 {out / 'report.md'}")


if __name__ == "__main__":
    main()
