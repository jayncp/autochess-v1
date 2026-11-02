# 01 Godot 项目现状

> 调查日期：2026-11-01。本文描述 `autochess-v1/` 在接手时的真实状态，以代码为准。
> 代码引用格式 `路径:行号`，路径相对于项目根目录。

## 1. 基本信息

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2** stable（`project.godot` features = `"4.7","Mobile"`；本机 `/Applications/Godot.app`） |
| 渲染 | `mobile` 渲染器，1920×1080，`stretch/mode = canvas_items`，鼠标模拟触控 |
| 主场景 | `res://scenes/scene_manager.tscn` |
| Autoload | `GlobalVar` → `scripts/global_var.gd`（实际代码通过 `class_name global_var` 的 `static var` 访问，autoload 本身没被用到） |
| 全局主题 | `assets/fonts/hei_font.tres` → `NotoSansSC-Regular.ttf`（10 MB） |
| 导出预设 | Android arm64，输出 `../../../export_godot/auto_chess_v1_0510.apk`，包名 `com.example.autochess` |
| 签名凭据 | `.godot/export_credentials.cfg`（keystore 路径/密码），**被 .gitignore 忽略，不会进仓库**，换机器需另行备份 |
| 规模 | 28 个 `.gd` 共约 2300 行；13 个 `.tscn`；`assets/` 24 MB；`.godot/` 缓存 47 MB |
| 运行检查 | `Godot --headless --path . --quit-after 120` 无报错 |
| 版本控制 | 尚未初始化 git；已有 `.gitignore`（`.godot/`、`/android/`）与 `.gitattributes`（LF） |

## 2. 目录结构

```
autochess-v1/
├── project.godot / export_presets.cfg / icon.svg
├── assets/
│   ├── 纯色背景-蓝.png          # 各场景 Background 的占位贴图（运行时被脚本替换）
│   ├── 石板卡槽.png             # 卡槽贴图（card_slot.tscn 使用）
│   ├── 新卡面UI.png / 新卡面UI-下.png   # 卡面底板 / "整合技能"模式下半部底板
│   ├── 卡槽.png、自走棋测试UI.png、自走棋测试UI_下.png   # 未被引用（旧版 UI）
│   ├── background/              # 6 张场景背景（英文名，已规范）
│   ├── fonts/                   # 主题 + 思源黑体
│   └── 自走棋卡图/               # 37 张 256×256 透明 PNG，中文文件名，按卡名动态加载
├── scenes/
│   ├── scene_manager.tscn       # 根场景，负责切换
│   ├── menu_scene.tscn          # 主菜单
│   ├── test_scene.tscn          # 科研模式
│   ├── level_select_scene.tscn  # 闯关-关卡选择
│   ├── pre_battle.tscn          # 闯关-布阵
│   ├── main.tscn                # 战斗场景
│   ├── book_scene.tscn          # 图鉴
│   └── material/                # card / card_slot / buff_text / 两种下拉选择按钮
└── scripts/
    ├── global_var.gd            # 跨场景传递双方阵容
    ├── scene_manager.gd / menu_scene.gd / test_scene.gd / level_select_scene.gd
    ├── pre_battle_scene.gd / main_scene.gd / book_scene.gd
    ├── database/card_database.gd、level_database.gd
    ├── battle/battle_animation_manager.gd、battle_skill_manager.gd   # 空文件（预留拆分）
    └── material/
        ├── card/card.gd、card_image.gd、equip_image.gd
        ├── card_slot.gd、player_hand.gd
        ├── button/card_select_button.gd、equip_select_button.gd、filter_star_button.gd
        ├── function_tools/load_card.gd、load_background.gd    # 静态工具类
        └── manager/battle_manager.gd(746行)、advanced_card_manager.gd、card_manager.gd、
                    select_manager.gd、book_manager.gd、input_manager.gd
```

命名现状：脚本/场景已是英文 snake_case；**资源名、卡牌 key、关卡 key、部分节点名（如 `实时状态`）是中文**。

## 3. 场景流转

`scene_manager.gd` 用信号驱动切换，`current_scene` 保存当前场景：

```
SceneManager._ready → MenuScene
  ├─ 科研模式  → TestScene ──开始──▶ main(战斗) ──返回──▶ TestScene
  ├─ 闯关模式  → LevelSelectScene ──选关──▶ PreBattleScene ──开始──▶ main ──返回──▶ PreBattleScene
  │                                         └─返回─▶ LevelSelectScene
  ├─ 冒险模式  → (空，_on_adventure_mode_pressed 只有 pass)
  ├─ 线下对战  → (空)
  └─ 图鉴模式  → BookScene
```

- 进入战斗时不销毁上一场景，而是 `visible=false` 并整体下移 1500px 防止射线检测（`scripts/scene_manager.gd:95-111`）。
- 双方阵容通过 `global_var` 的 4 个 static 数组传给战斗场景（`scripts/global_var.gd:5-8`）。

## 4. 各模式现状

| 模式 | 状态 | 说明 |
|---|---|---|
| 主菜单 | 可用 | 随机两张背景之一（`menu_scene.gd:10-22`），标题"牛马自走棋" |
| 科研模式 | 可用 | 上下各 7 个位置，每位一个角色下拉 + 一个装备下拉，实时显示合成后的卡；"开始"进入战斗（`select_manager.gd`）。装备无角色时报"阵容有误" |
| 闯关模式 | 可用（2 关） | 关卡列表自动从 `level_database.gd` 生成按钮；布阵界面：对手阵容固定在上方，玩家手牌（角色+装备）在底部，拖到中间 7 个槽；装备拖到槽中角色上即合成，合成卡拖出槽外即拆分回手（`advanced_card_manager.gd:170-265`）。**无胜负记录、无解锁/进度、无关卡描述** |
| 图鉴模式 | 可用 | 每页 18 张（3×6），筛选：角色/装备开关、星级、关键词（匹配名称/种族/时机/技能名）（`book_manager.gd`） |
| 冒险模式 | 未实现 | 仅按钮 |
| 线下对战 | 未实现 | 仅按钮 |
| 战斗 | 可用 | 见第 6 节；按钮：开始战斗/返回、速度（1→2→5→20x 循环）、跳过战斗、"实时状态"开关（整合技能 UI ↔ 原始卡面） |

## 5. 数据层

### 5.1 `scripts/database/card_database.gd`

一个 `const CARDS` 字典，**key 为中文卡名**，value 为 11 列数组：

| 下标 | 含义 | 说明 |
|---|---|---|
| 0 | 序号 | 字符串，角色 1xx，装备 2xx |
| 1 | 类型 | `"角色"` / `"装备"` |
| 2 | 星级 | 1–3 |
| 3 | 种族 | 数组，如 `["动物","精灵"]`；装备为 null |
| 4 | 战力1 | 角色基础战力 |
| 5 | 战力2 | 装备附加战力 |
| 6 | 时机1 | 角色技能时机：`战前`/`入场`/`交战` |
| 7 | 技能1 | 角色普通技能 `[{"集结":2}]` |
| 8 | 时机2 | 装备附加时机（目前只有圣水=战前） |
| 9 | 技能2 | 装备普通技能 |
| 10 | 技能3 | 特殊技能（被动）`[{"致命":-1}]`，-1 表示无数值 |

当前**已启用 15 个角色 + 13 个装备**（共 28 张，均有卡图），均为 1–2 星：

- 角色：士兵、老虎、淤泥怪、天使、小精灵（1★）；精灵虎、半精灵人、树精、仙女、秃鹫、虎人、食人花、圣骑士、盾卫、豪猪（2★）
- 装备：号角、狮心、荆棘、光环、木剑（1★）；圣盾、剧毒匕首、防爆头盔、圣水、战旗、毒囊、铁剑、尖刺拳套（2★）

**已注释（数据已写，未启用）**：7 个三星角色（猛犸、大天使长、眼镜蛇王、炼金术师、大将军、狼王、丛林神庙）、二星装备空心、9 个三星装备（仙女翅膀、虎符、神庙核心、噬心药剂、无双战铠、诅咒之爪、圣剑、玉玺、全知法袍）。其中猛犸、大将军、虎符、空心等的特殊效果在数据里无法表达（如猛犸只有战力 25，虎符时机"入场"但无技能），说明当时卡在"复杂机制"上。

### 5.2 `scripts/database/level_database.gd`

`const LEVEL`，key 为关卡名，value = `[对手角色[], 对手装备[], 玩家角色[], 玩家装备[]]`：

| 关卡 | 对手 | 玩家可用 |
|---|---|---|
| 猪突猛进 | 豪猪×4，装备 毒囊/剧毒匕首/防爆头盔/铁剑 | 秃鹫、食人花、半精灵人、虎人 + 战旗、尖刺拳套 |
| 虎虎生风 | 虎人×4，装备 荆棘/光环/木剑/号角 | 盾卫、半精灵人、虎人×2 + 剧毒匕首、狮心 |

### 5.3 卡图加载

`load_card.gd:14,50,85,118` 直接拼路径 `res://assets/自走棋卡图/<中文卡名>.png`。卡图目录里还有 8 张 **database 中不存在**的图：藤鞭、蟾蜍、队长、竖笛、双节棍、穿云弓、腐蚀之爪、森灵头带（推测是"待录入"表中的新卡/改名卡，已提前出图）。

## 6. 战斗系统（`scripts/material/manager/battle_manager.gd`）

战斗规则的完整描述见 [02-battle-rules.md](02-battle-rules.md)，这里只讲架构。

### 6.1 初始化

1. 从 `global_var` 读取双方阵容（`:24-31`）。
2. 对每个位置：`load_card.generate_single_card(角色)`，若有装备再 `load_card.union_two_cards(角色卡, 装备卡)` —— **这一步只改 UI Label**（`load_card.gd:72`注释原文："仅改变卡牌UI，不更新内在属性"）。
3. 然后**从 Label 文本反解析战斗属性**（`battle_manager.gd:70-90`）：
   - `strength = int(strength_1.text)`（合成时已把装备战力加到 strength_1 上）
   - `skill_time` = `time_1`/`time_2` 文本里出现的 `战前/入场/交战`
   - `normal_skill` = 对 `集结/狂暴/腐蚀/振奋` 四个技能，分别取 "角色技能1(可被装备技能1覆盖) + 装备技能2" 的数值（`union_normal_skill_power`，`:110-138`）
   - `special_skill` = 角色技能3，**若装备有技能3则整体替换**（`:86-90`）
4. 卡牌节点加入 `card_manager`，并 append 到 `player_battle_fields[1|2]`。

### 6.2 流程

`_on_start_battle_pressed_battle`（`:235`）→ `pre_battle_part()` → `main_battle_part()` → `show_winner()`。
所有结算函数都混合了 tween 动画与 `await create_timer()`；"跳过"通过 `play_animation=false` 关闭大部分等待。

### 6.3 架构问题（对后续开发影响最大）

1. **逻辑与 UI 强耦合**：战斗状态挂在卡牌节点上（`card.gd:15-24`），属性从 Label 文本解析，结算函数里直接改 Label、播 tween。没有纯数据层，也就**无法在不实例化场景的情况下跑战斗**。
2. **无头可跑但不适合批量**（实测约 32 场/秒）：实测用 `--headless --script` 实例化 `main.tscn` 可以跑完一场战斗（一次性探针脚本，已清理），但 `pre_battle_part` 中 `await create_timer(0.5/battle_speed)`（`:306-307`）**不受 `play_animation` 控制**，每场至少等待真实时间；且每场都要建整套 UI 节点。批量模拟（关卡枚举、RL）必须先抽出纯逻辑层。
3. **协程未被 await**：`settlement_normal_skill`、`settlement_damage` 内部有 `await`，但调用处没有 `await`（如 `:303-305`、`:460-461`、`:713`）。导致**动画模式与跳过模式的结算顺序不同**：动画模式下双方技能按"P1狂暴→P2狂暴→P1集结→P2集结…"交错执行；跳过模式下是"P1全部→P2全部"。对现有 4 个加减类技能结果一致，但一旦加入"受伤触发""死亡触发"等机制就会出现两种模式结果不一致。
4. 卡牌位置靠坐标匹配找卡（`pre_battle_scene.gd:49-57`、`select_manager.gd:76-82`、`move_character` 用 `x/240` 推算），脆弱。
5. 两个空文件 `scripts/battle/battle_animation_manager.gd`、`battle_skill_manager.gd` 说明当时已有"拆分动画与技能"的打算，未完成。

## 7. 已知问题清单

### 7.1 Bug（已复现或可确定）

| # | 位置 | 问题 | 证据 |
|---|---|---|---|
| B1 | `battle_manager.gd:466` | `settlement_self_hurt(P1) or settlement_self_hurt(P2)` **短路求值**：P1 触发反噬时 P2 的反噬被跳过 | 实测：P1 豪猪 vs P2 小精灵+尖刺拳套 → P2 以 1 战力获胜；交换左右 → 平局。同一对局结果随座位变化 |
| B2 | `battle_manager.gd:738-746` | 反噬只结算第一个反噬词条（循环内 `return true`） | 代码阅读；目前没有同时带两个反噬的卡，暂不触发 |
| B3 | `advanced_card_manager.gd:203-208` | 拖到敌方卡上：`move_dragged_card_to_hand()` 后未 return，继续访问已置空的 `card_being_dragged` | 代码阅读；敌方槽 `interactable=false`，正常操作很难触发 |
| B4 | `book_manager.gd:32,45` | 卡数恰为 18 的倍数时多出一个空页 | 代码阅读 |
| B5 | `battle_manager.gd:604-610` | `buff_text` 实例播放完从不释放 | 代码阅读，长战斗会累积节点 |
| B6 | `battle_manager.gd:533-554` | `settlement_death` 边遍历边 `erase`，相邻两个同时死亡时漏删第二个，该"死人"下一轮会被当作交战位触发入场 | 最小脚本验证了 GDScript 行为。目前每方每次只有首位会死，**潜伏**；实现湮灭（群体伤害）后会触发 |
| B7 | `battle_manager.gd:146-184、326-337` | **战斗可能无限进行**：没有回合上限；"连续 7 次战力不变"判平局，会被振奋这类持续加战力的效果绕过。开着"跳过"时游戏卡死 | 实测：P1 老虎+圣水 vs P2 盾卫+狮心 永不结束（见 [../design/balance-report-2026-11-01.md](../design/balance-report-2026-11-01.md#4-附带发现战斗可能无限循环新-bugb7)） |

### 7.2 需要确认是"设计"还是"bug"的行为

"Python"列是旧结算脚本的做法（详见 [02-battle-rules.md](02-battle-rules.md)）。"结论"列已按 2026-11-01 的决定更新（[../decisions.md](../decisions.md)）。

| # | 现行行为 | Python | 结论 |
|---|---|---|---|
| Q1 | 装备有技能3（特殊技能）时**整体替换**角色的技能3：盾卫(坚固4)+圣盾 → 只剩庇护（实测确认） | 同样整体替换 | 与旧规则一致；是否改为叠加**仍待讨论**（R2） |
| Q2 | 角色+带时机的装备（圣水：战前振奋1）→ 卡牌获得多个时机，**每个时机都执行全部普通技能** | 同样（时机取并集） | 与旧规则一致 |
| Q3 | 装备的技能1按技能名覆盖角色同名技能（为空心预留，空心的 `[]` 清空） | 整体替换 | **决定：整体替换** |
| Q4 | 特殊平局：双方战力列表**连续 7 次检查**不变即平局（`:163-184`，注释写"三回合"） | 100 轮上限 | **决定：不变检测 + 回合上限** |
| Q5 | 致命 = 攻击值 10000，**会被庇护抵挡** | 对方战力+100，同样被庇护挡 | 与旧规则一致 |
| Q6 | 反噬直接扣战力，**不经过坚固/庇护** | 走伤害流程，坚固/庇护生效 | **决定：按 Python** |
| Q7 | 腐蚀走伤害流程，受坚固减免、会消耗庇护 | 同样 | 与旧规则一致 |
| Q8 | 集结 = 本方场上所有集结数值之和（含自己） | 同样 | 与 docx 例子一致 |
| Q9 | 无最大回合数保护 | 有（100 轮） | **决定：加** |

### 7.3 代码卫生

- `battle_manager.gd:5-8` 默认值 `player_cards`/`player_equips` 内容放反（cards 里是装备名）；`global_var.gd` 默认值含未启用的"空心""仙女翅膀"（运行时会被覆盖，无影响）。
- `global_var` 既注册为 autoload 又作为 `class_name` 静态类使用，二选一即可。
- 大量空的 `_process`、模板注释。
- `main.tscn`/`test_scene.tscn`/`book_scene.tscn` 中的 `input_manager` 节点未挂脚本（这些场景卡牌只能悬停放大，不能拖拽——符合需求，但节点多余）。
- 各场景 `Background` 默认贴 `纯色背景-蓝.png`，运行时由 `load_background.set_texture_for_node` 换成真实背景。
- 未被引用的资源：`assets/卡槽.png`、`assets/自走棋测试UI.png`、`assets/自走棋测试UI_下.png`。
- 卡面布局全部是 `card.tscn` 中手摆的 Label 坐标，卡面尺寸约 180×252（碰撞框），卡槽 194×272，场上间距 240px，7 个位置 x=240…1680。

## 8. 对后续开发的直接影响

- **新增卡牌**：现有 11 列数组 schema 只能表达"时机 + 四种数值技能 + 若干被动词条"，三星卡和复杂装备（猛犸、大将军、虎符、全知法袍等）需要新的效果表达方式和结算钩子。
- **无头模拟 / 平衡测试 / RL**：必须把战斗逻辑抽成不依赖节点的纯数据模块（GDScript `RefCounted` 类即可），表现层订阅其事件日志回放动画。这也顺便解决 6.3 第 3 条的结果不一致问题。
- **改英文 id**：卡名同时充当数据 key、显示名、图片文件名、关卡数据引用，需要一次性统一迁移（见 [../roadmap.md](../roadmap.md)）。
