# AGENTS.md

牛马自走棋（autochess-v1）：Godot 4.7.2 卡牌自走棋，单机为主，计划加局域网对战，移动端优先、兼顾 PC。
与用户用中文交流，卡牌用中文名沟通。

## 现状

- 阶段：阶段 0.5（行为基线测试与规则修复）已完成，下一步是阶段 1（规范整理）。仓库 `main`，远程 `jayncp/autochess-v1`（公开）。进度见 `PROCESS.md`，路线图见 `docs/roadmap.md`。
- 可用：科研模式（自由摆阵对战）、闯关（2 个解谜关）、图鉴、战斗演出（速度/跳过）。冒险、线下对战未实现。
- 战斗逻辑在 `scripts/material/manager/battle_manager.gd`，与 UI 强耦合（战力从 Label 文本解析），计划抽成纯逻辑模块。
- 已修复 B1（反噬短路）、B6（死亡漏删）、B7（无限战斗）。剩下的是 UI 小 bug B3/B4/B5/B8，阶段 1 修（见 `docs/roadmap.md` 阶段 1）。规则的待实现项见 `docs/design/battle-rules.md`。

## 核心规则（详见 `docs/design/`，以 `docs/decisions.md` 为准）

- 卡牌名称和数值以 `scripts/database/card_database.gd` 为准；旧表格只作参考。
- 核心理念"大毒盾"：大克盾、盾克毒、毒克大。致命+庇护叠加是天花板级机制。
- 战斗是确定性的：只有交战位互相攻击；普通技能按 狂暴 → 集结 → 腐蚀 → 振奋 → 湮灭 的顺序结算。
- 装备：武器战力、武器时机、武器技能**叠加**；基础技能、特殊技能**整体替换**角色的。
- 规则的现行规范和待实现项见 `docs/design/battle-rules.md`。
- 平衡：角色和装备各自平衡；角色各档有效战力均值 6/13/21/30/40。
- 羁绊和升星暂不做。

## 目录（整理前）

- `scenes/`：各模式场景；`scenes/material/` 是卡牌、卡槽等组件
- `scripts/`：场景脚本；`database/` 放卡牌和关卡数据，`material/manager/` 放各管理器
- `assets/`：`自走棋卡图/`（按中文卡名动态加载）、`background/`、`fonts/`、卡面 UI 图
- 计划改为英文 id、按功能分组的目录；Python 工具放 `tools/`（带 `.gdignore`），GDScript 无头命令放 `cli/`（`docs/roadmap.md` 阶段 1）

## 命令

- 运行：`just run`；测试：`just test`（说明和维护方法见 `tests/README.md`）
- Godot：`/Applications/Godot.app/Contents/MacOS/Godot`（`justfile` 里可用环境变量 `GODOT` 覆盖）
- 无头脚本：`... --headless --path . --script <file.gd>`
  - 脚本 `extends SceneTree`；
  - 跑战斗时设 `battle_manager.play_animation = false`，约 100 场/秒（测试工具见 `tests/battle_harness.gd`）。

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
- 先做中文版，预留 i18n：界面文字和卡牌显示名不要和内部英文 id 混用。
- 协议暂定：代码 AGPL-3.0-or-later，美术/数据/文档 CC BY-SA 4.0。
- 开发流程：阶段性任务先在 `docs/plans/` 写计划，用户确认后开 issue，在分支上开发，通过 PR 合并；小修改直接提交到 main。
- 小修改（文档、计划等）可以直接提交并推送到 main，不必逐次确认；阶段任务的 PR 合并、破坏性操作之前，先征得用户同意。
- commit 信息用中文简述，不加 AI 署名。
- 结构、约定或决策变化时，同步更新本文件。
