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
| `art/` | 美术素材生成（依赖组 `art`：fonttools、resvg-py）：`fonts.py` 字体子集，`icons.py` 图标，`ornaments.py` 卡牌边框和法阵，`ui.py` 控件和卡面面板贴图，`fx.py` 战斗飘字的饰板。用 `just fonts`、`just art` 运行，规范见 `docs/design/art-direction.md` |

## 实验

| 名字 | 内容 |
|---|---|
| `matrix_1star` | 1★ 基准对局矩阵，与 `docs/design/card-design.md` 第 3 节逐格对比 |
| `effective_strength` | 当前卡池的有效战力：角色（1★、2★ 环境）、装备（2★ 环境），以及几件装备按宿主的价值。经济卡照测，但不进环境、不计入均值 |
| `star_totals` | 同总星级的多个低星对少量高星的随机摆位平均分（方法同星级报告第 1 节） |
| `holy_water` | 装备有效战力，以及圣水 +0 到 +4 各版本按宿主的价值 |

实验结果写成 `docs/design/balance-report-<日期>.md`（带时效的快照）。
