# PROCESS

项目重启的进度跟踪。阶段定义见 [docs/roadmap.md](docs/roadmap.md)，已拍板事项见 [docs/decisions.md](docs/decisions.md)。

## 已完成

- 接手调查（2026-11-01）：结论在 `docs/takeover/`（快照）和早期的 balance-report。
- 阶段 0：仓库初始化、协议、首次提交原样快照。
- 阶段 0.5：行为基线测试与规则修复（PR #2）；关卡复核见 `docs/design/levels.md`。
- 阶段 1：英文 id、数据外置、多语言预留、目录整理（PR #4，计划 `docs/plans/stage-1-reorg.md`）。
- 布阵互换（PR #6），规则见 `docs/design/game-design.md` 第 7 节。
- 阶段 2：战斗核心纯逻辑化、回放、无头模拟、Python 工具（PR #8、#9，计划 `docs/plans/stage-2-battle-core.md`）。
- 阶段 3 第一轮：1★/2★ 打底（PR #11 规范、#12 机制、#13 新卡，计划和执行记录 `docs/plans/stage-3-cards.md`）。
- UI 重做（issue #14，PR #15–#19，计划和执行记录 `docs/plans/ui-redesign.md`，规范 `docs/design/art-direction.md`）：字体、图标、主题、背景，卡面，图鉴，关卡选择，构筑阶段，科研模式，战斗界面，`expand` 适配。
- 战斗特效和回放节奏（issue #20，PR #21 飘字和卡面反馈、#22 动作和节奏，计划和执行记录 `docs/plans/effects-pacing.md`）。协战、神佑的规则和表现已定，等有卡用到时实现。
- 设置和存档（issue #23，PR #24，计划和执行记录 `docs/plans/settings-save.md`，存档格式 `docs/design/save-data.md`）：设置页面、存档目录 `niuma_autochess`、闯关通关记录、清除记录。
- 阶段 3 第二轮的设计（2026-11-18 定版）：3★/4★/5★ 共 60 张角色、38 件装备，结算顺序和卡面写法的规范，记录在 `docs/plans/stage-3-high-stars.md`。
- 阶段 3 第二轮开发（issue #25，PR #26–#29，计划和执行记录 `docs/plans/stage-3-high-stars-dev.md`）：结算结构改造（时点内七步、被动挂在事件上、用例迁到 `tests/cases/`），神佑、协战、免疫致命、多一次、多一轮，全部描述型特殊技能，98 张新卡（现在共 87 张角色、57 件装备），回放表现和节奏，回放时长工具 `just replay-time`。
- Rust 版结算（issue #30，PR #31–#33，计划和执行记录 `docs/plans/rust-engine.md`）：`engine/` 的核心库（和 GDScript 版逐函数对应）、命令行 `engine-cli`、Python 绑定 `autochess_engine`（`tools/` 的批量模拟默认用它）；对拍 `just diff-sim` 100 万场零差异，单线程约为 Godot 版的 130 倍；顺带收紧了卡牌数据的校验（`tests/cases/card_checks.json`）。

- 数值校正（记录 `docs/plans/balance-tuning.md`，经验 `docs/design/balance-notes.md`）：按对局阶段搜索均衡阵容，校正到"没有废卡、没有一家独大"；试验数值在 `docs/design/balance-trial.xlsx`，测试工具在 `tools/autochess_tools/balance/`（`just balance`）。
- 数值校正写进正式版（issue #36，三个 PR，计划和执行记录 `docs/plans/balance-port.md`）：新机制在 GDScript 版实现、Rust 版去掉试验开关；118 张卡的数值写进 `data/cards.json`，5 件装备改名改 id；回放的合并显示（八咫镜、两个萨满）、战前减半和致命伤害的表现；规则、决策、设计文档同步。两个关卡因此待重做。
- 平衡指标（issue #39）：只用阶段搜索，警戒线写进 `card-design.md` 第 1 节；去掉各星级有效战力的目标均值、有效战力和 1★ 基准矩阵的工具；设计表的有效战力列换成六个阶段的出场率（`just balance usage`）。
- 阵容码（issue #44，计划和执行记录 `docs/plans/lineup-code.md`，规范 `docs/design/lineup-code.md`）：一方阵容写成一段文字（`鹦鹉+狮心 / 士兵`），读写在 `LineupCode`；共用的阵容码面板，科研模式里导出、导入；用例 `tests/cases/lineup_codes.json`。
- 经济系统的初步建立和摸底（issue #46，记录 `docs/plans/economy-survey.md`，规则和结论 `docs/design/economy.md`）：经济表 `docs/design/economic-system.xlsx`（等级、商店、利息、天赋、拍卖），估算工具 `just economy`（一套阵容的期望花费、第几回合凑齐）；用均衡阵容摸底后定了商店 4 角色 + 2 装备、升级经验 5/10/25/30/45/60。

## 待办
- [ ] 按金币约束搜索阵容，带上卡牌觉醒（三张相同的角色合成一张，数值翻倍；规则待定）

- [ ] 冒险模式（设计中）
- [ ] 卡图
- 之后再定：构筑阶段的拖放反馈、音效；Android 的存档导入导出；正式发布前定 Android 包名（现在是占位的 `com.example.autochess`，改了存档会丢）
  - 备选工具（用户需要时再做）：设计表导入脚本（"设计中"的行 → `data/cards.json` + 中文名）
- 暂缓：测试、实验、报告、数值记录的存储约定，等卡牌形成较平衡稳定的完整版本后再单独讨论（建议草案见 2026-11-03 对话：回归测试精简、可复用实验进 git、原始输出不进 git、报告只在做决定时写）
- [ ] 阶段 4：闯关模式（教学关 + 解谜关 + 难度验证工具）；现有两关按新数值重做（猪突猛进现在无解，虎虎生风太容易）
- [ ] 阶段 5：冒险模式
- [ ] 阶段 6：线下对战
- [ ] 阶段 7：AI 与平衡工具
