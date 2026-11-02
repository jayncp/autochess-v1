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
- [ ] 阶段 0.5：行为基线测试与规则修复（计划：`docs/plans/stage-0.5-baseline.md`，待确认）
- [ ] 阶段 1：英文 id、数据外置、目录整理（不改功能）
- [ ] 阶段 2：战斗核心纯逻辑化 + 无头模拟 CLI + 测试（含湮灭）
- [ ] 阶段 3：卡牌补全（3★/4★ 拆分 → 卡图 → 实现 → 表现）
- [ ] 阶段 4：闯关模式（教学关 + 解谜关 + 难度验证工具）
- [ ] 阶段 5：冒险模式
- [ ] 阶段 6：线下对战
- [ ] 阶段 7：AI 与平衡工具
- [ ] 持续：UI 美化（装备图尺寸、卡面底色/星级边框/种族背景、按钮），见 roadmap"美术与体验"
