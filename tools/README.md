# Python 工具

分析和平衡实验。战斗规则只有 GDScript 一份实现（`scripts/core/battle_sim.gd`），这里通过 `cli/sim.gd` 批量调用它，自己不重写规则。

## 使用

- 环境：用 uv 管理。第一次运行 `just` 命令时会自动创建 `tools/.venv`。
- Godot 路径默认是 `/Applications/Godot.app/Contents/MacOS/Godot`，可用环境变量 `GODOT` 覆盖。
- `just experiment <名字>`：运行 `autochess_tools/experiments/<名字>.py`，结果打印到终端。
- `just tools-check`：ruff 检查和格式、ty 类型检查、pytest。提交前在本地运行（CI 目前停用）。

## 模块

| 模块 | 内容 |
|---|---|
| `data.py` | 读 `data/cards.json` 和 `i18n/data.csv` |
| `sim.py` | `simulate(对局列表, extra_cards)`：调用 `cli/sim.gd`，大批量时拆给多个 Godot 进程并行。`extra_cards` 是只在本次模拟有效的额外卡牌，比如白板单位、某张卡的不同数值版本 |
| `effective.py` | 有效战力：与被测卡（或装备）表现相同的白板战力 |

## 实验

| 名字 | 内容 |
|---|---|
| `matrix_1star` | 1★ 基准对局矩阵，与 `docs/design/card-design.md` 第 3 节逐格对比 |
| `effective_strength` | 当前卡池的有效战力：角色（1★、2★ 环境）、装备（2★ 环境），以及几件装备按宿主的价值。经济卡照测，但不进环境、不计入均值 |
| `star_totals` | 同总星级的多个低星对少量高星的随机摆位平均分（方法同星级报告第 1 节） |
| `holy_water` | 装备有效战力，以及圣水 +0 到 +4 各版本按宿主的价值 |

实验结果写成 `docs/design/balance-report-<日期>.md`（带时效的快照）。
