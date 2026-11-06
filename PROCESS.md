# PROCESS

项目重启的进度跟踪。阶段定义见 [docs/roadmap.md](docs/roadmap.md)，已拍板事项见 [docs/decisions.md](docs/decisions.md)。

## 接手调查（2026-11-01）

- [x] 阅读 Godot 项目全部脚本与场景，无头运行验证
- [x] 分析旧 Python 结算脚本、桌游设计资料、素材库
- [x] 用探针脚本验证：docx 例子复现、反噬短路 bug、特殊技能替换、GDScript 遍历删除行为、1★ 对局矩阵
- [x] 编写 `docs/takeover/`（README + 01–07 + source 转录）
- [x] 用户答复问题 → `docs/decisions.md`、`docs/design/card-design.md`
- [x] 数值模型验证实验 → `docs/design/balance-report-2026-11-01.md`（发现 B7 无限战斗 bug）
- [x] 原三星、圣水变体、战斗长度实验 → `docs/design/balance-report-2026-11-01-part2.md`；临时脚本已清理
- [x] R2 定为替换；平局规则核实；`AGENTS.md` + `CLAUDE.md`；路线图移到 `docs/roadmap.md`
- [x] 平局规则（7 次不变 + 20 轮无人阵亡）、圣水（仅战前 +2）、协议暂定、i18n 预留 → `docs/decisions.md`
- [x] 星级平衡原则验证 → `docs/design/balance-report-2026-11-02-stars.md`；临时脚本已清理
- [x] 讨论结论：接受 2★ 略强、角色与装备各自平衡、种族差异来自定位；核心理念"大毒盾"
- [x] 文档整理：新增 `docs/README.md`、`design/game-design.md`、`design/battle-rules.md`；精简 `card-design.md`；重写 `decisions.md`、`roadmap.md`（含阵容码、Python 工具位置）
- [x] 用户确认开始阶段 0；约定开发流程（阶段任务走 issue + PR，小修改直接提交 main）

## 待办

- [x] 阶段 0：git 初始化 + 协议 + 首次提交原样快照 + 推送
- [x] 阶段 0.5：行为基线测试与规则修复（PR #2 已合并，issue #1 已关闭；关卡复核见 `docs/design/levels.md`）
- [x] 阶段 1：英文 id、数据外置、多语言预留、目录整理（PR #4 已合并，issue #3 已关闭；计划见 `docs/plans/stage-1-reorg.md`）
- [x] 布阵互换：规则见 `docs/design/game-design.md` 第 7 节（PR #6 已合并，issue #5 已关闭）
- [x] 阶段 2：战斗核心纯逻辑化 + 回放 + 无头模拟 CLI + 测试（含湮灭）+ 工具（PR #8、#9 已合并，issue #7 已关闭）
  - [x] 计划 `docs/plans/stage-2-battle-core.md`（实测：现有 134 条用例动画模式与跳过模式结果全部一致）
  - [x] 讨论定稿：分拍、先加后减、特殊技能模型、装备叠放模型、平局只留 20 次交战、B9；写入 `battle-rules.md`、`decisions.md`
  - [x] PR A：战斗核心（计划第 6 节第 1–6 步，PR #8）
    - BattleSim 与旧引擎逐场对比 2268 场一致；平局规则实验 20000 场无误判；回放截图对比一致（旧版跳过误判平局除外）
  - [x] PR B：工具（第 7–9 步）：关卡检查、Python 工具、复现旧报告、圣水校准 → `docs/design/balance-report-2026-11-03.md`
  - [x] PR B 已合并（PR #9），issue #7 已关闭；圣水补偿定为 +3
- [ ] 阶段 3：卡牌补全（3★/4★ 拆分 → 卡图 → 实现 → 表现）
  - [x] 卡牌设计表 `docs/design/card-workbook.xlsx`：已实现、旧三星、旧设计的参考 + 新设计填写区
  - [x] 用户的 1★/2★ 设计稿入库（`f3e5851`）；讨论定稿：术语、顺序、分隔符、格子模型、支援、唤醒、条件触发、财富只做特效 → `docs/decisions.md` 11-06
  - [ ] **第一轮（1★/2★ 打底）**：计划 `docs/plans/stage-3-cards.md`（待确认）
    - [ ] PR 3a 规范（改名、顺序、格子字段、序号、术语文档、设计表整理）
    - [ ] PR 3b 机制（支援、财富、唤醒、队长和蟾蜍的效果）
    - [ ] PR 3c 新卡（12 张角色 + 6 件装备，占位图，新环境下测有效战力）
    - [ ] 之后先停：一起规划卡图、UI、强度测试
  - [ ] 之后：3★ 角色和装备（用户设计）
  - 备选工具（用户需要时再做）：设计表导入脚本（"设计中"的行 → `data/cards.json` + 中文名）；草稿评估实验（直接测"设计中"行的有效战力）
- 暂缓：测试、实验、报告、数值记录的存储约定，等卡牌形成较平衡稳定的完整版本后再单独讨论（建议草案见 2026-11-03 对话：回归测试精简、可复用实验进 git、原始输出不进 git、报告只在做决定时写）
- [ ] 阶段 4：闯关模式（教学关 + 解谜关 + 难度验证工具）
- [ ] 阶段 5：冒险模式
- [ ] 阶段 6：线下对战
- [ ] 阶段 7：AI 与平衡工具
- [ ] 持续：UI 美化（装备图尺寸、卡面底色/星级边框/种族背景、按钮），见 roadmap"美术与体验"
