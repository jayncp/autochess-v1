# 数据格式

游戏数据都是 JSON。数值以这里为准；中文名在 `i18n/data.csv`，旧表格只作参考。
`CardDB`、`LevelDB` 加载时会校验字段和 id，出错时报错，测试也会因此失败。

## cards.json

一卡一行，按序号排列。没有的字段直接省略；技能字典写 `{}` 和省略等价。

| 字段 | 含义 |
|---|---|
| `id` | 英文 id，代码、卡图（`assets/cards/<id>.png`）、翻译 key（`card.<id>`）都用它 |
| `no` | 序号，4 位：类型（1 角色、2 装备）、星级、两位流水号。同星级按设计分组和种族顺序排，决定图鉴顺序 |
| `type` | `character` / `equipment` |
| `star` | 星级 |
| `races` | 种族列表（只有角色有），见 `CardDB.RACES` |
| `strength` | 战斗力。角色必填；装备的战斗力加到角色上 |
| `timing_1`、`timing_2` | 时机-1、时机-2，见 `CardDB.TIMINGS` |
| `skills_1`、`skills_2` | 基础技能-1、基础技能-2：`{技能 id: 数值}` |
| `special_skills` | 特殊技能：`{技能 id: 数值或 null}`，没有数值的（如致命）写 `null`；带时机的写 `{"timing": 时机}`，如 `{"awaken": {"timing": "pre_battle"}}`。描述型的（如队长的 `rally_gain`）卡面文字在翻译表 `effect.<id>` |

**格子**：时机、基础技能各两格，特殊技能一格。角色和装备都可以填任意格，通常角色填 1、装备填 2。
合并时装备那一格有内容就覆盖角色的，写 `"clear"` 表示清空，规则见 [battle-rules.md 第 6 节](../docs/design/battle-rules.md#6-装备叠加格子模型)。

```json
{"id": "tiger_man", "no": 1201, "type": "character", "star": 2, "races": ["beast", "human"], "strength": 9, "timing_1": "on_engage", "skills_1": {"rage": 2, "rally": 1}},
{"id": "holy_water", "no": 2210, "type": "equipment", "star": 2, "strength": 3, "timing_2": "pre_battle"},
```

## levels.json

```json
{"id": "boar_rush", "enemy": [["porcupine", "venom_sac"], ...], "hand": ["vulture", "maneater", ...]}
```

- `enemy`：敌方阵容，`[角色 id, 装备 id]`，没有装备写 `""`；
- `hand`：玩家可用的卡（角色和装备混在一起）；
- 关卡名的翻译 key 是 `level.<id>`。
