# 04 旧版 Python 结算脚本（`../自走棋辅助/`）

> 2024-02 写的战斗结算与测试工具，纯标准库，约 765 行引擎。规则细节已并入 [02-battle-rules.md](02-battle-rules.md)，本文讲结构、工具和可复用的东西。
> 下文行号指 `script/main_script.py`。

## 1. 目录与运行

```
自走棋辅助/
├── script/main_script.py          ★ 唯一的引擎 + 硬编码数据（角色 33 + 三合一"大X" 18 + 装备 32）
├── single_test_launcher.py        单局，打印详细过程（改文件里的 4 个 list）
├── match_launcher.py              终端交互，两人各自输入阵容
├── loop_test_launcher.py          双方只打乱站位，随机抽样统计胜率
├── single_loop_test_launcher.py   ★ 关卡通过率：固定队 1，枚举队 2 的站位 × 装备分配
├── optimal_team/                  ★ 最优阵容随机演化搜索 + 出现次数统计图
│   ├── main_script.py             引擎副本（与 script/ 逐字节相同）
│   ├── basic_functions.py         搜索主程序（导入即运行，覆盖 team_savings.txt）
│   ├── statistics.py              统计并画柱状图（matplotlib）
│   └── team_savings*.txt          阵容池；_top_XXXXXX 是按星级预算存档
├── webUI/                         Flask 网页版（引擎副本 + /api），templates/index.html
└── file/                          自走棋.xlsx、预制阵容.txt、规则/流程 PDF
```

- 需要 Python ≥ 3.9（注解里直接写 `list[character]`）；核心零依赖，`statistics.py` 要 matplotlib，webUI 要 flask。
- 运行：`python single_test_launcher.py` 等，脚本会把自身目录加入 `sys.path`。
- 性能：7v7 约 2300 局/秒，4v4 约 4400 局/秒（大量时间花在 deepcopy）。
- **数据不读 xlsx**，全部硬编码在 `init_character()` / `init_equipment()`（`:40-145`）。

## 2. 引擎特点

- **完全确定性**：引擎内没有随机；p1/p2 镜像 3000 局 0 处不一致；能逐步复现 docx 例子。
- 状态：`character` / `equipment` 两个 dataclass，技能用 `[{name: value}]`，内部名为英文（raging、assembling、corrosion、encouraging、annihilating、wealth、toxic、solid、self_hurt、sheltering 等）——**可以直接作为 Godot 改英文 id 时的词条命名参考**。
- 调用顺序：羁绊 → 地狱之主 → 装备 → 战前（必须用返回值）→ `fighting()`。
- 返回：`(winner, damage, p1存活, p2存活, p1_money, p2_money)`；金钱放在模块全局变量。

## 3. 关卡难度验证脚本（你提到的"枚举通过率"）

就是 `single_loop_test_launcher.py`：

- 队 1 固定（关卡敌方），队 2 是玩家可用的卡；对队 2 做**角色排列 × 装备排列全枚举**，装备会在角色间重新分配。
- 每当队 2 获胜就打印该配置，最后输出胜率 = 关卡通过率。
- 当前样例就是 Godot 的"虎虎生风"：虎人×4 对 盾卫/半精灵人/虎人×2，通过率 **3.47%**。
- 注意：**羁绊结算被注释掉了**（`:74-76`）；打印时战前有人阵亡会导致角色与装备错位；没有随机种子。

`loop_test_launcher.py` 名为"全排列"，实际是有放回随机抽样，同样关掉了羁绊。

## 4. 最优阵容搜索（`optimal_team/`）

- 池 `team_savings.txt`（一行一个 tuple，用 `eval` 读）。
- 每次取一支队连续变异 10 次（同星级换角色或装备，保持星级预算），和池中每支队各打 10 局随机站位，总分 > 0 就入池；池超过 10 支时打循环赛保留前 5。共 500 次迭代，约 21 秒。
- `team_savings_top_XXXXXX.txt` 的 6 位数字 = 1★/2★/3★ 角色数 + 1★/2★/3★ 装备数（如 `007043` = 7 个 3★ 角色、4 件 2★ 装备、3 件 3★ 装备），推测对应规则表不同回合的人口与商店星级。
- `statistics.py` 统计池中各卡出现次数画柱状图，用作强度参考（当时：精灵虎、半精灵人、仙女；圣盾、圣水、剧毒匕首 最常出现）。

## 5. 已知 bug

| # | 位置 | 问题 |
|---|---|---|
| P1 | `optimal_team/basic_functions.py:80`、`webUI/main_script_web.py:819` | 丢弃战前阶段返回值，战前已死的单位进入主战斗。随机 7v7 中约 1.9% 胜负与 launcher 不同 → **最优阵容搜索的结论与正式规则不一致** |
| P2 | 两个循环测试 launcher | 羁绊被注释掉 |
| P3 | `:417-429` | 自然7/神族4 给首位装备追加致命/庇护，导致首位角色原特殊技能被覆盖 |
| P4 | `:369` | 两件基因密码时只有第一个槽位生效 |
| P5 | webUI | 出错时前端显示 undefined；`debug=True` + `0.0.0.0` 暴露调试器 |
| P6 | 全部 | 三份引擎副本手工同步；测试无随机种子；`basic_functions.py` 末尾淘汰结果未赋值 |

## 6. 对后续的价值

1. **规则参考实现**：Godot 没做的机制（湮灭、财富、羁绊、精灵女王、战神、大王花、地狱之主、勇者、神圣精灵、污染源、基因密码、雷神）都有可读的参考代码。
2. **工具思路**：关卡通过率枚举、随机演化找强势阵容、出现次数统计——后续在新的无头模拟器上重做。
3. **对拍**：修好 P1/P3/P4 后，可以用它批量生成"阵容 → 结果"黄金用例，与新引擎交叉校验（注意数值差异要先对齐到 Godot 数据）。
4. **不建议继续维护**它的数据表和代码；新的模拟器应读取与 Godot 同一份卡牌数据。
