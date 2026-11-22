# Python 工具

分析和平衡实验。这里不实现战斗规则：批量模拟默认用 Rust 版结算（`engine/`，通过 Python 绑定 `autochess_engine`）；规则的基准实现是 GDScript 版（`scripts/core/battle_sim.gd`），两边逐场一致，Godot 后端留给对拍用。

## 使用

- 环境：用 uv 管理。第一次运行 `just` 命令时会自动创建 `tools/.venv`，并编译 Rust 版的 Python 绑定（要先装 Rust，见 `engine/README.md`；Rust 源码变了会自动重新编译）。
  要手动同步环境时用 `uv sync --all-groups`（只写 `uv sync` 会删掉美术素材用的依赖组）。
- Godot 路径默认是 `/Applications/Godot.app/Contents/MacOS/Godot`，可用环境变量 `GODOT` 覆盖。
- 想用 Godot 版跑某个实验（比如核对结果），设环境变量 `AUTOCHESS_BACKEND=godot`：`AUTOCHESS_BACKEND=godot just experiment effective_strength`。
- `just experiment <名字>`：运行 `autochess_tools/experiments/<名字>.py`，结果打印到终端。
- `just tools-check`：ruff 检查和格式、ty 类型检查、pytest。提交前在本地运行（CI 目前停用）。

## 模块

| 模块 | 内容 |
|---|---|
| `data.py` | 读 `data/cards.json` 和 `i18n/data.csv` |
| `sim.py` | `simulate(对局列表, extra_cards, workers, backend)`：默认用 Rust 版（Python 绑定，多核），`backend="godot"` 时调 `cli/sim.gd`（拆给多个 Godot 进程）。`extra_cards` 是只在本次模拟有效的额外卡牌，比如白板单位、某张卡的不同数值版本。`engine(extra_cards)` 返回 Rust 版的引擎，大批量时用它的 `simulate_ids`（编号数组，见 `engine/README.md`）。`run_godot`、`run_engine` 分别用 Godot 版、Rust 版的命令行跑一批对局，返回原样的结果行（可带 `--trace` 等参数） |
| `lineups.py` | 随机对局（固定种子）：每方 1–7 人、各星级的正式卡、允许同名卡；机制密集的对局多从带特殊机制的卡里抽 |
| `diff_sim.py` | 对拍（`just diff-sim`）：同一批随机对局分别用两个版本跑，逐场比较，不一致时用简要轨迹找出第一处不同 |
| `bench.py` | 测速（`just bench`）：Rust 版单线程、多线程和 Godot 版单进程的场/秒 |
| `effective.py` | 有效战力：与被测卡（或装备）表现相同的白板战力 |
| `balance/` | 数值试验：分阶段的阵容搜索（见下面"数值试验"） |
| `art/` | 美术素材生成（依赖组 `art`：fonttools、resvg-py）：`fonts.py` 字体子集，`icons.py` 图标，`ornaments.py` 卡牌边框和法阵，`ui.py` 控件和卡面面板贴图，`fx.py` 战斗飘字的饰板。用 `just fonts`、`just art` 运行，规范见 `docs/design/art-direction.md` |

## 实验

| 名字 | 内容 |
|---|---|
| `matrix_1star` | 1★ 基准对局矩阵，与 `docs/design/card-design.md` 第 3 节逐格对比 |
| `effective_strength` | 当前卡池的有效战力：角色（1★、2★ 环境）、装备（2★ 环境），以及几件装备按宿主的价值。经济卡照测，但不进环境、不计入均值 |
| `star_totals` | 同总星级的多个低星对少量高星的随机摆位平均分（方法同星级报告第 1 节） |
| `holy_water` | 装备有效战力，以及圣水 +0 到 +4 各版本按宿主的价值 |

实验结果写成 `docs/design/balance-report-<日期>.md`（带时效的快照）。

## 数值试验

按对局阶段搜索互相克制后的均衡阵容，看每张卡的出场率和带卡得分。方法、指标的读法和踩过的坑见 [`docs/plans/balance-tuning.md`](../docs/plans/balance-tuning.md)，调数值的经验见 [`docs/design/balance-notes.md`](../docs/design/balance-notes.md)。

都用 `just balance <模块> [参数]` 运行（等于在 `tools/` 下 `uv run --group balance python -m autochess_tools.balance.<模块>`）：

| 模块 | 内容 |
|---|---|
| `run <名字>` | 六个阶段各开一个进程同时搜索。结果在 `tools/balance/runs/<名字>/`：`report.md`、各阶段的报告和进度日志、`pools/`（这次的阵容） |
| `stage <阶段>` | 只搜一个阶段，报告打印到终端 |
| `check --cards id,id` | 复核一张卡是不是真的弱：把它挂到均衡里每套阵容的每个位置上再搜 |
| `compare <新报告> [旧报告]` | 汇总一份报告，或者列出两份报告之间每张卡的变化 |
| `trend <输出.html> <说明> <报告>` | 把报告做成一页趋势图：每张卡各阶段的出场率和带卡得分 |
| `sheet read/write` | 试验表（Excel）和"改过的卡"之间互转 |

数据在 `tools/balance/`：

- `trial.json`：试验数值里和正式数据不同的卡（整张卡的数组）。搜索默认用它；想测别的改动，另写一份用 `--change` 指定。
- `overrides.json`：试验表里特殊技能的文字对应的数据。设计者通常只改文字，读表时按这份对照表补数据。
- `pools/`：上一轮留下的阵容，作为搜索的起点。
- `runs/`：每一轮的结果，不进 git。

**一轮的流程**

1. 设计者改 `docs/design/balance-trial.xlsx`。
2. `just balance sheet read ../docs/design/balance-trial.xlsx balance/trial.json balance/overrides.json`：读回改动。先核对它列出的差别和"要留意的"几处；文字改了的特殊技能要在对照表里补上数据（新效果要先按改规则的流程实现，见 `engine/README.md`）。
3. `just balance run <名字> --warm balance/pools balance/runs/<上一轮>/pools ...`：起点写上最近三四轮的阵容目录。
4. `just balance compare balance/runs/<名字>/report.md balance/runs/<上一轮>/report.md --changed 5`：看哪些卡变了。
5. 出场率很低、带卡得分又明显低于 0.5 的卡，下结论之前用 `check` 复核；带 `--save` 存下找到的阵容，把那个目录加进下一次的 `--warm` 重跑，才是这些卡真实的出场率。
6. 一轮定下来后，把 `runs/<名字>/pools/` 复制成 `balance/pools/`。

**在哪里跑**

- 时间几乎都花在模拟上，只吃 CPU，核心越多越快。12 核的笔记本上开局、前期各十几秒，后三个阶段要几分钟到十几分钟；192 核的服务器上六个阶段一共 2–5 分钟。
- `run` 默认把核心平分给各个阶段（`--threads` 可以改）。只想跑几个阶段用 `--stages`。
- 在别的机器上跑：把仓库拷过去（`engine/`、`tools/`、`data/`、`i18n/`），装好 Rust 和 uv，在 `tools/` 下 `uv sync --all-groups`，之后命令相同。没有 `just` 就直接用上面那条 `uv run` 命令。
- 用 rsync 同步代码时不要保留修改时间（`rsync -rlzc`）：Rust 源码的时间比上次编译早的话，Python 绑定不会重新编译。
- 远程连接不稳定时，用 `nohup` 在后台跑，再隔一会儿看 `runs/<名字>/` 下的日志；`report.md` 出现就是跑完了。

**按正式数据搜索**：`stage` 加 `--official`（`run`、`check` 用 `--change` 指向一个内容是 `[]` 的文件）。规则只有一套，候选数值和正式数据只是卡不同。

**对拍候选数值**：`just diff-sim 1000000 --cards balance/trial.json`，随机对局从套用候选数值之后的卡里抽，Godot 版和 Rust 版逐场比较。
