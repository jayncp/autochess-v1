# 阶段 1 计划：规范整理（不改功能）

> **状态**：已完成，PR #4 已合并（2026-11-02）。issue #3「阶段 1：规范整理」，分支 `stage-1-reorg`。执行中和计划不同的地方见文末「执行记录」。

## 目标

1. 程序内部一律用英文 id；中文名只用于显示、文档和沟通。
2. 卡牌和关卡数据从代码里拿出来，放进 `data/*.json`。
3. 所有显示文字走翻译表，目前只有中文一列。
4. 目录按功能分组，删掉没用的文件。
5. 修 UI 小 bug B3/B4/B5/B8。

**不改功能**：战斗结果和界面表现都不变。基线用例的期望值不重录，`just test` 全部通过。

**不在本阶段做**：

- 抽战斗核心、湮灭、基础技能整体替换（阶段 2）；
- 新卡、3★/4★ 拆分（阶段 3）；
- 代码风格统一（类名、节点名的大小写、类型标注）：只改中文节点名，其余等阶段 2 重写时再说；
- PC 导出预设。

## 已确认

1. **英文 id 对照表**（第 1 节）按候选采用。定下后尽量不再改（以后存档、阵容码都会引用）。
2. **8 张生图过程图**（队长、蟾蜍、竖笛、森灵头带、穿云弓、藤鞭、腐蚀之爪、双节棍）从项目里删除。资源库里有 md5 一致的副本，git 历史里也有。以后做成装备时再按新 id 导入。
3. **注释掉的卡**（7 张 3★ 角色、9 件 3★ 装备、空心）不迁移到 `cards.json`。它们的数值记录在 [takeover/03-cards.md](../takeover/03-cards.md)，阶段 3 拆分 3★/4★ 时重新定。

## 1. 英文 id

规则：小写 snake_case，全项目唯一。原来的数字序号保留为 `no` 字段。

### 1.1 角色

| 序号 | 中文 | id |
|---|---|---|
| 101 | 士兵 | `soldier` |
| 102 | 老虎 | `tiger` |
| 103 | 淤泥怪 | `sludge` |
| 104 | 天使 | `angel` |
| 105 | 小精灵 | `pixie` |
| 106 | 精灵虎 | `fey_tiger` |
| 107 | 半精灵人 | `half_elf` |
| 108 | 树精 | `dryad` |
| 109 | 仙女 | `fairy` |
| 110 | 秃鹫 | `vulture` |
| 111 | 虎人 | `tiger_man` |
| 112 | 食人花 | `maneater` |
| 113 | 圣骑士 | `paladin` |
| 114 | 盾卫 | `shield_guard` |
| 115 | 豪猪 | `porcupine` |

### 1.2 装备

| 序号 | 中文 | id |
|---|---|---|
| 201 | 号角 | `war_horn` |
| 202 | 狮心 | `lionheart` |
| 203 | 荆棘 | `thorns` |
| 204 | 光环 | `halo` |
| 207 | 木剑 | `wooden_sword` |
| 209 | 剧毒匕首 | `venom_dagger` |
| 210 | 防爆头盔 | `riot_helmet` |
| 211 | 圣水 | `holy_water` |
| 212 | 战旗 | `war_banner` |
| 213 | 毒囊 | `venom_sac` |
| 214 | 铁剑 | `iron_sword` |
| 216 | 尖刺拳套 | `spiked_gauntlet` |
| 218 | 圣盾 | `holy_shield` |

`cards.json` 里卡的顺序和现在一致，图鉴和下拉菜单的排列顺序不变。

### 1.3 词条、时机、种族、类型

| 类别 | 中文 → id |
|---|---|
| 普通技能 | 集结 `rally`、狂暴 `rage`、腐蚀 `corrode`、振奋 `inspire`；湮灭 `annihilate`、财富 `wealth`（未实现） |
| 特殊技能 | 致命 `lethal`、庇护 `shelter`、坚固 `sturdy`、反噬 `backlash` |
| 时机 | 战前 `pre_battle`、入场 `on_enter`、交战 `on_engage`；出售 `on_sell`（未实现） |
| 种族 | 人族 `human`、动物 `beast`、自然 `nature`、神族 `divine`、精灵 `elf`；财宝 `treasure`、恶魔 `demon`（暂无卡） |
| 类型 | 角色 `character`、装备 `equipment` |

集结在路线图草案里写的是 `assemble`，这里改用更常见的游戏术语 `rally`。未实现的 id 先只登记在这里，用到时再加进数据和翻译表。

### 1.4 关卡

| 中文 | id |
|---|---|
| 猪突猛进 | `boar_rush` |
| 虎虎生风 | `tiger_gale` |

### 1.5 资源文件

| 现在 | 之后 |
|---|---|
| `assets/自走棋卡图/<中文名>.png` | `assets/cards/<id>.png` |
| `assets/新卡面UI.png` | `assets/ui/card_frame.png` |
| `assets/新卡面UI-下.png` | `assets/ui/card_skill_overlay.png`（实时状态下盖住底部的那块） |
| `assets/石板卡槽.png` | `assets/ui/card_slot.png` |
| `assets/纯色背景-蓝.png` | `assets/backgrounds/solid_blue.png`（场景里的占位底图，运行时被替换） |
| `assets/background/battle_background.png` | `assets/backgrounds/battle.png` |
| `assets/background/book_background.png` | `assets/backgrounds/book.png` |
| `assets/background/level_select_background.png` | `assets/backgrounds/level_select.png` |
| `assets/background/main_menu_1.png`、`main_menu_2.png` | `assets/backgrounds/menu_1.png`、`menu_2.png` |
| `assets/background/pre_scene_1.png` | `assets/backgrounds/setup.png`（科研模式和关卡布阵共用） |
| `assets/fonts/` | 不变 |
| `assets/卡槽.png`、`自走棋测试UI.png`、`自走棋测试UI_下.png` | 删除（未被引用） |

### 1.6 场景与脚本

| 现在 | 之后 |
|---|---|
| `scenes/scene_manager.tscn`、`scripts/scene_manager.gd` | `scenes/app/scene_manager.*`（启动场景） |
| `scenes/menu_scene.tscn`、`scripts/menu_scene.gd` | `scenes/menu/menu.*` |
| `scenes/test_scene.tscn`、`scripts/test_scene.gd` | `scenes/sandbox/sandbox.*` |
| `select_manager.gd`、`card_select_button.*`、`equip_select_button.*` | `scenes/sandbox/` |
| `scenes/level_select_scene.tscn`、`scripts/level_select_scene.gd` | `scenes/level/level_select.*` |
| `scenes/pre_battle.tscn`、`scripts/pre_battle_scene.gd` | `scenes/level/level_setup.*`（原名和"战前"时机重名，容易混） |
| `advanced_card_manager.gd`、`player_hand.gd`、`input_manager.gd` | `scenes/level/` |
| `scenes/main.tscn`、`scripts/main_scene.gd` | `scenes/battle/battle.*` |
| `battle_manager.gd`、`scenes/material/buff_text.tscn` | `scenes/battle/` |
| `scenes/book_scene.tscn`、`scripts/book_scene.gd`、`book_manager.gd`、`filter_star_button.gd` | `scenes/book/` |
| `scenes/material/card.tscn`、`scripts/material/card/*.gd`、`load_card.gd` | `scenes/components/card/` |
| `scenes/material/card_slot.tscn`、`card_slot.gd`、`card_manager.gd`（悬停放大，三个场景共用） | `scenes/components/` |
| `scripts/database/*.gd` | `data/*.json` + `scripts/core/card_db.gd`、`level_db.gd` |
| `scripts/global_var.gd`、`load_background.gd` | `scripts/`（位置不变或从子目录上移） |
| `scripts/battle/*.gd`（两个空文件，未被引用） | 删除 |
| 节点 `实时状态`（`battle.tscn`） | `skill_union_label` |

## 2. 数据文件

### 2.1 `data/cards.json`

数组，一张卡一行，便于对照和看 diff。字段名对应 [battle-rules.md 第 6 节](../design/battle-rules.md#6-装备叠加) 的术语：

| 字段 | 含义 |
|---|---|
| `id`、`no`、`type`、`star` | id、原序号、类型、星级 |
| `races` | 种族（角色） |
| `strength` | 基础战力（角色） |
| `timing`、`skills` | 基础时机、基础技能。角色的就是自身的；装备上表示替换角色的（目前没有装备使用） |
| `weapon_strength`、`weapon_timing`、`weapon_skills` | 武器战力、武器时机、武器技能（装备，与角色叠加） |
| `special_skills` | 特殊技能（整体替换） |

- 技能写成 `{"词条 id": 数值}`，有多个时按书写顺序显示；致命、庇护没有数值，写 `null`。
- 没有的字段直接省略。`"skills": {}` 表示清空，留给空心这类卡。

```json
[
{"id": "soldier", "no": 101, "type": "character", "star": 1, "races": ["human"], "strength": 3, "timing": "on_enter", "skills": {"rally": 2}},
{"id": "vulture", "no": 110, "type": "character", "star": 2, "races": ["beast", "nature"], "strength": 7, "timing": "on_engage", "skills": {"rage": 3, "corrode": 2}},
{"id": "porcupine", "no": 115, "type": "character", "star": 2, "races": ["beast"], "strength": 15, "timing": "on_engage", "special_skills": {"backlash": 4}},
{"id": "holy_water", "no": 211, "type": "equipment", "star": 2, "weapon_strength": 2, "weapon_timing": "pre_battle"},
{"id": "holy_shield", "no": 218, "type": "equipment", "star": 2, "special_skills": {"shelter": null}}
]
```

### 2.2 `data/levels.json`

阵容格式和测试用例相同：`[[角色, 装备], ...]`，装备为空字符串表示不带。`hand` 是玩家手牌，顺序就是发牌顺序。

```json
[
{"id": "boar_rush", "enemy": [["porcupine", "venom_sac"], ["porcupine", "venom_dagger"], ["porcupine", "riot_helmet"], ["porcupine", "iron_sword"]], "hand": ["vulture", "maneater", "half_elf", "tiger_man", "war_banner", "spiked_gauntlet"]}
]
```

### 2.3 加载与使用

- `scripts/core/card_db.gd`（`CardDB`）、`level_db.gd`（`LevelDB`）：静态类，第一次用时读 JSON 并缓存。
  - 加载时校验：字段、类型、词条、时机、种族的 id 都要认识，否则报错。
  - 运行中的报错会被测试捕获，所以数据写错时测试会失败。
- **装备合并**搬进 `CardDB`：
  - 现在这段逻辑在 `battle_manager.gd` 的 `load_player_deck` 和 `union_normal_skill_power` 里；
  - 改为由 `CardDB.combine(card_id, equip_id)` 返回战力、时机、普通技能、特殊技能；
  - 战斗加载和卡面显示都调它，不再从 Label 文本反解析时机；
  - 逻辑原样搬，包括"基础技能按技能名逐个覆盖"的现状（阶段 2 再改）。
- **卡牌节点记录 `card_id`、`equip_id`**。下面这些地方现在都从 Label 文本反查卡名，一律改为读这两个字段：
  - 布阵时合并、拆分卡牌；
  - 科研模式和闯关生成阵容；
  - 战斗加载。
- 科研模式的下拉菜单显示中文名，选项里存 id。
- `global_var.gd`、`battle_manager.gd` 里引用了不存在的卡（空心、仙女翅膀）的默认阵容，改为空。
- 以后的 Python 工具直接读 `data/` 和 `i18n/`。

## 3. 翻译表

- `i18n/data.csv`（卡牌、种族、词条、时机、关卡）和 `i18n/ui.csv`（界面文字），列为 `keys,zh_CN`。
- Godot 导入 CSV 后，在项目设置里注册。回退语言设为中文，所以系统语言不是中文时也显示中文。

| 类别 | key | 例 |
|---|---|---|
| 卡牌名 | `card.<id>` | `card.soldier` = 士兵 |
| 种族、词条、时机 | `race.<id>`、`keyword.<id>`、`timing.<id>` | `keyword.rally` = 集结 |
| 关卡名 | `level.<id>` | `level.boar_rush` = 猪突猛进 |
| 界面 | `ui.<场景>.<名称>`，共用的写 `ui.common.*` | `ui.common.back` = 返回；`ui.book.page` = 第%d页/共%d页 |

- **场景里的文字**：
  - 控件文本写 key，Godot 运行时自动翻译；
  - 编辑器里打开 2D 视图的 View → Preview Translation，选中文就能看到中文；
  - 改了 CSV 要重新导入才会刷新预览。
- **代码里拼的文字**（飘字"狂暴 + 2"、胜负提示、页码等）用 `tr()`，格式和现在一致。
- **图鉴搜索**：按显示的中文名匹配卡名、种族、时机和技能，行为不变。
- 文档和沟通里继续用中文卡名。

## 4. 目录结构

```
autochess-v1/
├── assets/
│   ├── cards/          卡图，<card_id>.png
│   ├── backgrounds/    场景背景
│   ├── ui/             卡面、卡槽
│   └── fonts/          字体和主题（不变）
├── data/               cards.json、levels.json
├── i18n/               data.csv、ui.csv
├── scenes/
│   ├── app/            启动场景，负责切换各模式
│   ├── menu/
│   ├── sandbox/        科研模式
│   ├── level/          关卡选择、关卡布阵
│   ├── battle/
│   ├── book/           图鉴
│   └── components/     卡牌、卡槽等共用组件
├── scripts/
│   ├── core/           card_db.gd、level_db.gd（阶段 2 的战斗核心也放这里）
│   ├── global_var.gd   场景之间传递阵容
│   └── load_background.gd
├── tests/
├── docs/               加 .gdignore，Godot 不扫描
└── justfile
```

- **场景和脚本放在一起**；只被一个场景用的组件放在该场景目录下，多个场景共用的放 `components/`。
- **`cli/`、`tools/`**：等有第一个工具时再建（阶段 2 的模拟命令）。现在建只会是空目录。
- **移动方法**：
  - 用脚本批量处理：`git mv` 文件，`.import`、`.uid` 一起移；
  - 改写 `.tscn`、`.gd`、`.tres`、`project.godot` 里的 `res://` 路径；
  - 运行 `godot --import` 重建缓存；
  - 检查：导入没有报错，资源的 uid 不变，git 能识别为重命名。
- **导出**：导出预设排除 `tests/`；确认 `data/*.json` 会被打包，不会的话加进包含列表。

## 5. UI 小 bug

| # | 位置 | 问题 | 修法 |
|---|---|---|---|
| B3 | 布阵拖拽 | 拖到敌方卡上，退回手牌后没有返回，接着访问已置空的拖拽对象 | 退回后直接返回 |
| B4 | 图鉴 | 卡数正好是 18 的倍数时多出一页空页 | 页数改为向上取整，至少 1 页 |
| B5 | 战斗飘字 | 飘字节点播完不释放，长战斗会越积越多 | 动画播完后释放 |
| B8 | 关卡布阵 | 敌方装备卡合并后没有释放，测试退出时报泄漏 | 卡牌直接按 `card_id` + `equip_id` 生成，不再创建临时装备卡 |

## 6. 测试

- **基线用例迁移**：
  - `tests/golden/battles.jsonl` 里的卡名换成 id，用例编号里的关卡名也换成 id，期望值不动；
  - 迁移后反向换回中文，必须和原文件一致。
- **测试工具**：harness、`gen_random_cases.gd`、`level_solutions.gd`、冒烟流程改用 `CardDB`、`LevelDB` 和新路径。
- **新增一项数据检查**：
  - 每张卡都有卡图和中文名；
  - 数据里用到的种族、词条、时机都有中文名；
  - 关卡引用的卡都存在。
- `just levels`：两关的解数应和现在一样，猪突猛进 10 个、虎虎生风 5 个。

## 7. 步骤（每步一个提交，每步 `just test` 都通过）

| # | 内容 | 额外验证 |
|---|---|---|
| 1 | 清理：删除未引用的 UI 图、8 张过程图、空脚本 | — |
| 2 | 目录整理：移动场景、脚本、资源（卡图先移到 `assets/cards/`，暂时保留中文文件名）；改路径；中文节点改名；`docs/.gdignore` | 导入无报错；uid 不变 |
| 3 | 数据外置 + 英文 id：`data/*.json`、`CardDB`、`LevelDB`、装备合并、卡牌节点存 id、卡图改名、`i18n/data.csv`、基线用例迁移、数据检查 | 期望值未重录；`just levels` 解数不变 |
| 4 | 界面文字进翻译表：场景和代码里的显示文字都换成 key | 代码和场景里除注释外没有中文字面量 |
| 5 | 修 B3/B4/B5/B8 | 测试退出时不再报泄漏 |
| 6 | 导出过滤；文档同步 | — |

## 8. 文档同步

- `AGENTS.md`：
  - 卡牌数据的来源改成 `data/cards.json`，显示名在 `i18n/`；
  - 更新目录一节；
  - 补充约定：新增卡牌要同时加数据、卡图和翻译。
- `tests/README.md`：用例格式里的卡名改为 id。
- `docs/roadmap.md`：
  - 阶段 1 标记完成；
  - `cli/`、`tools/` 挪到阶段 2。
- `PROCESS.md`：更新进度。
- `docs/takeover/` 是快照，不改。

## 9. 验收

- `just test` 在本地和 CI 都通过；`just levels` 解数不变。
- 你用编辑器打开项目：没有缺失资源的报错，开启预览翻译后场景显示中文。
- 你把各模式玩一遍（科研、两个关卡、图鉴），文字和卡面显示正常。
- 可选：导出一次 APK 真机试一下。

## 执行记录

和计划不同、或计划里没写到的地方：

- **B8 提前消失**：第 3 步改成按 `card_id` + `equip_id` 直接生成卡牌后，就不再创建临时装备卡，泄漏随之消失。第 5 步只修 B3/B4/B5。
- **翻译文件提交进仓库**：项目设置在导入之前就要加载 `*.translation`，新克隆的仓库缺这些文件，导入时会报错。生成结果是确定的，只在 CSV 改动时才变。
- **中文字面量**：显示给玩家的文字都走翻译表；`CardDB`、`LevelDB` 给开发者看的报错信息保留中文。
- **用例编号**：`rule-assemble` 改为 `rule-rally`，和词条 id 一致。
- **`.import` 文件**：Godot 4.7 重新导入时补上了新的默认参数（`channel_remap` 等），对显示无影响。
- **额外验证**：
  - 截图对比：在 main 和本分支上，各截 12 张图鉴、关卡布阵、战斗开始和结束、科研模式的画面，逐像素一致；
  - 导出：`--export-pack` 导出成功，包里有 `data/*.json` 和翻译文件，没有 `tests/`。
- **B3 需要手动验证**：拖拽依赖真实鼠标，测试里触发不到。请把手牌拖到敌方卡上试一下。
