# 路线图

> 活文档，随项目推进更新。当前进度见 [../PROCESS.md](../PROCESS.md)，已拍板事项见 [decisions.md](decisions.md)。
> 每个阶段开始前，在 `docs/plans/` 写计划给用户过目，确认后开 issue，在分支上开发，通过 PR 合并；小修改直接提交到 main。

## 已完成

| 阶段 | 内容 | 详情 |
|---|---|---|
| 0 仓库初始化 | 公开仓库、协议文件、README | `decisions.md`"仓库"一节 |
| 0.5 行为基线 | 基线测试（战斗用例、冒烟流程），已确认的规则 bug 修复，关卡全部解作为基线 | [tests/README.md](../tests/README.md)、[design/levels.md](design/levels.md) |
| 1 规范整理 | 英文 id、数据外置到 `data/`、翻译表 `i18n/`、目录按场景分组 | [plans/stage-1-reorg.md](plans/stage-1-reorg.md) |
| 2 战斗核心 | 纯逻辑 `BattleSim` + 事件日志，战斗场景按日志回放；无头模拟 `cli/sim.gd`；Python 平衡工具 `tools/` | [plans/stage-2-battle-core.md](plans/stage-2-battle-core.md)、[design/battle-rules.md](design/battle-rules.md) |
| UI 重做 | 玩法和结算不变，重做卡面、各界面、控件、背景、字体、图标；画布宽随屏幕（`expand`） | [plans/ui-redesign.md](plans/ui-redesign.md)、[design/art-direction.md](design/art-direction.md) |
| 战斗特效和回放节奏 | 四类飘字，发动者和作用对象的表现，每拍约 0.85 秒的节奏，交战撞击，阵亡烧散，庇护保护罩，战前光圈；随机对局平均从约 75 秒降到约 49 秒 | [plans/effects-pacing.md](plans/effects-pacing.md)、[design/art-direction.md](design/art-direction.md) |

## 阶段 3：卡牌补全

1. **第一轮：1★/2★ 打底**（已完成，[plans/stage-3-cards.md](plans/stage-3-cards.md)）：统一规范（术语、显示顺序、格子模型）→ 新机制（支援、唤醒、条件触发、财富只做特效）→ 新卡（卡图先用占位图）。
2. 3★/4★：用户设计新的角色和装备，按[有效战力目标均值](design/card-design.md#1-星级档位与有效战力)逐张定位，包括完整词条版圣水、覆盖型装备。规则里标"待实现"的多一次、多一轮、获得庇护优先，随第一张需要的卡实现。
3. 卡图：先讨论形象，再 codex 生图、抠图、导出（流程见 [takeover/06-assets.md](takeover/06-assets.md#6-后续-ai-生图建议codex-cli)）。没有卡图的卡、剧毒之牙待画。
4. 强度测试：分档环境、宿主适配、经济卡怎么评估，到时再规划。

## 下一步：设置和存档

规划讨论中：设置页面（默认速度、默认紧凑模式、显示存档位置），存档目录改成固定的 `niuma_autochess`，接上闯关的通关记录。构筑阶段的拖放反馈、音效之后再定。

## 阶段 4：闯关模式

- 只用裸卡和装备，不含羁绊、升星、经济。
- **教学关**：每个词条一关，循序渐进。
- **解谜关**：先定名字或敌方阵容，估算我方可用卡，用工具验证通过率，再微调；报告通过率和解的数量。
- 关卡描述、提示、评价，进度存档与解锁。

## 阶段 5：冒险模式

连续对战 AI，赢金币，买角色和装备构筑。需要商店、经济、对手生成（用模拟器调难度）、局内存档。

- 局外规则重新设计，桌游版（[takeover/05](takeover/05-design-materials.md#2-局外循环规则规则xlsx--docx)）只作参考。
- 羁绊、升星、经济系统（财富产生金币）可能在这一阶段引入；经济卡在阶段 3 录入，财富在那之前只有特效。

## 阶段 6：线下对战（局域网）

多人两两对战，期间构筑。用 Godot 高层多人 API（ENet），由主机做权威。战斗是确定性的，可以只同步阵容，各端本地模拟。

## 阶段 7：AI 与平衡工具

- AI 玩家：启发式 AI → 强化学习（需要高吞吐模拟器和 gym 风格接口）→ 接入大模型 API 模拟玩家。
- 平衡工具：卡牌胜率、出场率、阵容搜索。

## 功能待办（不排阶段）

- **阵容码**：
  - 两种格式可以互相转换：可读、可编辑的文本，以及压缩成一串、便于复制的文本；
  - 科研模式和其他模式的阵容编辑处加"导出"，科研模式加"导入"；
  - 用于复盘和交流，随时可以做。
- **重播**：
  - 闯关等单机模式可以重看战斗；
  - 存阵容并带版本号，版本不一致就不播放；需要时也可以存事件日志；
  - 阶段 2 的回放就是基础。

## 平台：移动端优先，兼顾 PC

- **已定**：
  - 卡面布局、看卡方式、屏幕比例适配已在 UI 重做里完成（[design/art-direction.md](design/art-direction.md)）；
  - 渲染器暂不换；
  - iOS 到联机阶段再说。
- **开发方式**：日常在 PC 上开发调试，定期真机测试；尽早建好 PC 导出预设，两端都保持可构建。
- **开发环境跨平台**（目前只在 macOS 开发，换平台时处理）：
  - `justfile` 里 Godot 的默认路径是 macOS 的 app 路径。其他系统要设环境变量 `GODOT`，或者改成按 `os()` 选默认值，比如在 PATH 里找 `godot`；
  - `timeout` 是 GNU 命令，Windows 没有（cmd 的 `timeout` 是"等待几秒"，含义完全不同）。战斗必然结束（B7 已修），这层外层超时可以去掉；
  - just 在 Windows 上默认用 sh 执行，需要 Git Bash，或者在 justfile 里设置 `windows-shell`；
  - Windows 要用 Godot 的 `_console.exe` 版本，终端里才能看到输出。
- **以后要处理**：
  - Android 加网络权限；
  - iOS 局域网广播可能要额外申请权限，备选方案是手动输入 IP 或扫码连接。
