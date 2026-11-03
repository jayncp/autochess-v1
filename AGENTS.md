# AGENTS.md

牛马自走棋（autochess-v1）：Godot 4.7.2 卡牌自走棋，单机为主，计划加局域网对战，移动端优先、兼顾 PC。
与用户用中文交流，卡牌用中文名沟通。

## 现状

- 阶段：阶段 2（战斗核心）已完成；阶段 3（卡牌补全）中，用户正在 `docs/design/card-workbook.xlsx` 里设计新卡，之后带设计来讨论。仓库 `main`，远程 `jayncp/autochess-v1`（公开）。进度见 `PROCESS.md`，路线图见 `docs/roadmap.md`。
- 可用：科研模式（自由摆阵对战）、闯关（2 个解谜关）、图鉴、战斗演出（速度/跳过）。冒险、线下对战未实现。
- 战斗结算在纯逻辑模块 `scripts/core/battle_sim.gd`（`BattleSim`），输出结果和事件日志；装备合并在 `CardDB.combine_data`。战斗场景 `scenes/battle/battle_manager.gd` 只按事件日志回放动画。
- 已知 bug 都已修复；规则的待实现项见 `docs/design/battle-rules.md`。

## 核心规则（详见 `docs/design/`，以 `docs/decisions.md` 为准）

- 卡牌数值以 `data/cards.json` 为准，中文名以 `i18n/data.csv` 为准；旧表格只作参考。
- 核心理念"大毒盾"：大克盾、盾克毒、毒克大。致命+庇护叠加是天花板级机制。
- 战斗是确定性的：只有交战位互相攻击。
- 每个时间节点按拍结算：先特殊技能，再按 狂暴 → 集结 → 振奋 → 腐蚀 → 湮灭（先加后减），双方同一拍同时生效。
- 平局：连续 20 次交战无人阵亡。
- 装备像一张卡盖在角色卡上：武器战力、武器时机、武器技能**叠加**；基础时机、基础技能、特殊技能**整体覆盖**角色的，数据里用 `"clear"` 表示清空。
- 规则的现行规范和待实现项见 `docs/design/battle-rules.md`。
- 平衡：角色和装备各自平衡；角色各档有效战力均值 6/13/21/30/40。
- 羁绊和升星暂不做。

## 目录

- `data/`：`cards.json`（一卡一行，字段见 `docs/plans/stage-1-reorg.md` 第 2 节）、`levels.json`
- `i18n/`：翻译表 `data.csv`（`card.<id>`、`race.<id>`、`keyword.<id>`、`timing.<id>`、`level.<id>`）、`ui.csv`（`ui.<场景>.<名称>`）
- `scenes/`：场景和脚本放在一起
  - `app/`：启动场景
  - `menu/`、`sandbox/`（科研模式）、`level/`（关卡选择和布阵）、`battle/`、`book/`（图鉴）
  - `components/`：卡牌、卡槽等共用组件；`components/card/load_card.gd` 按 id 生成卡牌、刷新卡面
- `scripts/`：`core/`（`CardDB`、`LevelDB`、`BattleSim`）、`global_var.gd`（场景之间传阵容）
- `cli/`：GDScript 无头命令，如 `sim.gd`（批量模拟）
- `assets/`：`cards/<id>.png`、`backgrounds/`、`ui/`、`fonts/`
- `tests/`：基线测试，说明见 `tests/README.md`
- `tools/`：Python 分析和平衡实验（uv 管理，带 `.gdignore`），通过 `cli/sim.gd` 调用战斗核心，说明见 `tools/README.md`

## 命令

- 运行：`just run`；测试：`just test`（约 2 秒，说明和维护方法见 `tests/README.md`）
- 批量模拟：`just sim <输入.jsonl> <输出.jsonl> [--log] [--cards <额外卡牌.json>]`，单线程约 7400 场/秒（带事件日志约 4700）
- 关卡检查：`just level-check [关卡文件.json]`；平衡实验：`just experiment <名字>`；Python 检查：`just tools-check`
- Godot：`/Applications/Godot.app/Contents/MacOS/Godot`（`justfile` 里可用环境变量 `GODOT` 覆盖）
- 无头脚本：`... --headless --path . --script <file.gd>`
  - 脚本 `extends SceneTree`；
  - 跑战斗直接用 `BattleSim.simulate(p1, p2)`，不需要场景（测试工具见 `tests/battle_harness.gd`）。

## 文档（索引见 `docs/README.md`）

- `docs/decisions.md`：决策记录，已拍板的事项以它为准
- `docs/roadmap.md`：路线图和功能待办
- `docs/design/`：设计总纲、战斗规则、卡牌数值（活文档）；`balance-report-*` 是带时效的快照
- `docs/takeover/`：接手调查快照，不再更新
- `docs/plans/`：各阶段计划

## 外部资料（只读，不要修改）

- `../自走棋20240211/`：桌游期策划（卡牌表、规则表、战斗流程）
- `../自走棋辅助/`：旧 Python 结算和关卡枚举脚本
- `../自走棋godot资源库/`：美术原图、PSD、旧版代码

## 约定

- 文档放 `docs/`，计划放 `docs/plans/`，复杂任务记在 `PROCESS.md`。
- 先做中文版，预留 i18n：
  - 内部一律用英文 id，显示文字一律走翻译表：场景里写 key，代码里用 `tr()`；
  - 给开发者看的报错信息可以直接写中文；
  - 改了 CSV 后要重新导入（`godot --import`），生成的 `*.translation` 一起提交。
- 新增卡牌：在 `data/cards.json` 加数据，`assets/cards/<id>.png` 放卡图，`i18n/data.csv` 加中文名；测试的数据检查会核对三者是否齐全。
- 协议暂定：代码 AGPL-3.0-or-later，美术/数据/文档 CC BY-SA 4.0。
- 开发流程：阶段性任务先在 `docs/plans/` 写计划，用户确认后开 issue，在分支上开发，通过 PR 合并；小修改直接提交到 main。
- 每次开 PR 之前检查文档：`AGENTS.md`、`PROCESS.md` 和 `docs/` 下的活文档，删掉过时内容，同步代码改动，更新进度。
- 小修改（文档、计划等）可以直接提交并推送到 main，不必逐次确认；阶段任务的 PR 合并、破坏性操作之前，先征得用户同意。
- commit 信息用中文简述，不加 AI 署名。
- 结构、约定或决策变化时，同步更新本文件。
