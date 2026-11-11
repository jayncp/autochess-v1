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
- 设置和存档（issue #23，计划和执行记录 `docs/plans/settings-save.md`，存档格式 `docs/design/save-data.md`）：设置页面、存档目录 `niuma_autochess`、闯关通关记录、清除记录。

## 待办

- [ ] 阶段 3 后续：3★/4★ 角色和装备（用户设计）、卡图、强度测试规划
- 之后再定：构筑阶段的拖放反馈、音效；Android 的存档导入导出；正式发布前定 Android 包名（现在是占位的 `com.example.autochess`，改了存档会丢）
  - 备选工具（用户需要时再做）：设计表导入脚本（"设计中"的行 → `data/cards.json` + 中文名）；草稿评估实验（直接测"设计中"行的有效战力）
- 暂缓：测试、实验、报告、数值记录的存储约定，等卡牌形成较平衡稳定的完整版本后再单独讨论（建议草案见 2026-11-03 对话：回归测试精简、可复用实验进 git、原始输出不进 git、报告只在做决定时写）
- [ ] 阶段 4：闯关模式（教学关 + 解谜关 + 难度验证工具）
- [ ] 阶段 5：冒险模式
- [ ] 阶段 6：线下对战
- [ ] 阶段 7：AI 与平衡工具
