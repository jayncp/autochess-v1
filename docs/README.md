# 文档索引

| 文档 | 内容 | 类型 |
|---|---|---|
| [decisions.md](decisions.md) | 已拍板的决定 | 活文档 |
| [roadmap.md](roadmap.md) | 各阶段计划与功能待办 | 活文档 |
| [design/game-design.md](design/game-design.md) | 游戏设计总纲：大毒盾、种族定位、平衡原则、模式 | 活文档 |
| [design/battle-rules.md](design/battle-rules.md) | 战斗规则规范：术语、卡牌和装备、流程、时点内的结算、伤害、技能一览、卡面文字（含待实现标记） | 活文档 |
| [design/card-design.md](design/card-design.md) | 卡牌数值：平衡的验收标准、建模方法、装备衍生 | 活文档 |
| [design/levels.md](design/levels.md) | 现有关卡的数据与解（两关都待重做） | 活文档 |
| [design/art-direction.md](design/art-direction.md) | 美术与界面规范：画风、卡面、各界面布局、控件、素材生成 | 活文档 |
| [design/save-data.md](design/save-data.md) | 存档：位置、文件、字段、版本和升级规则 | 活文档 |
| [design/lineup-code.md](design/lineup-code.md) | 阵容码：一方阵容的文字写法、导入的规则、面板 | 活文档 |
| [design/economy.md](design/economy.md) | 经济系统：等级、商店、利息、天赋、拍卖的规则，估算的方法和现在的结论 | 活文档 |
| [design/economic-system.xlsx](design/economic-system.xlsx) | 经济表：经济规则的全部数字，估算工具直接读它 | 设计表，经济规则以它为准 |
| [design/economy-report-2026-11-25.html](design/economy-report-2026-11-25.html) | 均衡阵容的价格和成型回合（一页图表） | 快照，带时效 |
| [design/awakening.md](design/awakening.md) | 卡牌觉醒：合成的规则、觉醒后怎么变强（战力、基础技能、特殊技能各 ×1.5 / ×2）、定方案的原则、实现的现状 | 活文档 |
| [design/gold-report-2026-11-26.html](design/gold-report-2026-11-26.html) | 按金币约束搜索的结果：各回合档每张卡普通、觉醒的出场率和带卡得分（一页趋势图） | 快照，带时效 |
| [design/card-workbook.xlsx](design/card-workbook.xlsx) | 卡牌设计表：全部角色和装备（和正式数据一致，带各阶段的出场率）、各角色觉醒后的数值（"觉醒"页，脚本生成）、旧设计（参考） | 设计草稿，正式数据以 `data/cards.json` 为准 |
| [design/balance-notes.md](design/balance-notes.md) | 调数值的经验：怎么读数据、时机、体系和辅助卡、强卡和克制、调整的方法 | 活文档 |
| [design/balance-trial.xlsx](design/balance-trial.xlsx) | 数值试验表：校正后的数值，已写进正式数据；下一轮试验在这张表上改（流程见 [tools/README.md](../tools/README.md)） | 设计草稿，正式数据以 `data/cards.json` 为准 |
| [design/balance-report-*](design/) | 模拟实验报告；`2026-11-22` 是数值校正收尾版的全阶段结果（`.html` 是趋势图） | 快照，带时效 |
| [takeover/](takeover/README.md) | 接手调查：Godot 现状、旧 Python 脚本、桌游资料、素材库 | 快照，不再更新 |
| `plans/` | 各阶段的执行计划，按需创建 | — |

项目根目录还有 [AGENTS.md](../AGENTS.md)（给 AI 代理的项目概览）和 [PROCESS.md](../PROCESS.md)（进度）；数据格式见 [data/README.md](../data/README.md)；Rust 版结算见 [engine/README.md](../engine/README.md)。
