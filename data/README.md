# 数据格式

游戏数据都是 JSON。数值以这里为准；中文名在 `i18n/data.csv`，旧表格只作参考。
`CardDB`、`LevelDB` 加载时会校验字段和 id，出错时报错，测试也会因此失败。Rust 版结算（`engine/`）读同一份卡牌数据，校验相同；哪些写法合法、哪些报错，见 `tests/cases/card_checks.json`（两边的测试共用）。

**每个技能该不该带数值是固定的**，写错就在加载时报错：

| 写在哪 | 写法 |
|---|---|
| 基础技能（狂暴、集结……） | 正整数 |
| 带数值的词条：庇护（层数）、坚固、反噬 | 正整数 |
| 不带数值的词条：致命、协战、免疫致命，以及千机之匣、千机魔女这类没有参数的效果 | `null`（写了数值不报错，只看有没有） |
| 参数 `amount` | 正整数；获得不带数值的词条时必须写 `null` |

战斗力、序号、星级是整数。

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
| `timing_1`、`timing_2` | 时机-1、时机-2：时机的列表（一格可以写多个），见 `CardDB.TIMINGS`，如 `["on_enter", "on_engage"]` |
| `skills_1`、`skills_2` | 基础技能-1、基础技能-2：`{技能 id: 数值}`，数值是正整数 |
| `special_skills` | 特殊技能：`{技能 id: 值}`，写法见下 |

**特殊技能的值**：

- 词条：带数值的写正整数（如庇护的层数 `{"shelter": 2}`），不带数值的（如致命）写 `null`。
- 带参数的写成字典，参数见 `CardDB.SPECIAL_PARAMS`：
  - `timings`：带时机的特殊技能在哪些时机生效，如 `{"awaken": {"timings": ["pre_battle"]}}`；
  - `skill`、`amount`：作用于哪个基础技能、数值，如队长 `{"on_trigger_boost": {"skill": "rally", "amount": 2}}`；神佑的层数也是 `amount`：`{"bless": {"timings": ["on_enter"], "amount": 2}}`；
  - `scope`：范围，`self`（自身）、`allies`（己方全体）、`first`（开战时位于己方第 1 位的角色）、`self_and_second`（自身和开战时位于己方第 2 位的角色）、`self_and_front`（自身和前一位）；`timing`：作用于哪个时机。如精灵公主 `{"extra_round": {"scope": "first", "timing": "pre_battle"}}`；
  - `target`：对象，`self`（自身）、`next`（下一位）、`next_two`（下两位）、`allies`（己方全体）、`enemies`（对方全体）、`enemy_first_two`（对方前两位）。获得的 `skill` 可以是基础技能或词条，没有数值的词条 `amount` 写 `null`，如彼岸花妖 `{"grant": {"timings": ["pre_battle"], "target": "next_two", "skill": "lethal", "amount": null}}`；
  - `skill` 写 `"any"` 表示任意 / 所有基础技能（星辰法师、尤姆卡克斯）；
  - 只有一个数值的效果也写成字典，如千机魔女的倍数 `{"equipment_times": {"amount": 3}}`。
- 没有参数的描述型效果写 `null`，如千机之匣 `{"double_skills": null}`。
- 描述型特殊技能一种效果一个 id，卡牌之间只是参数不同；卡面文字在翻译表 `effect.<id>`，模板里的 `{参数名}` 换成参数（`{skill}` 显示技能名，`{skill_value}` 显示"腐蚀值"这样的技能值，任意基础技能时是"基础技能数值"）。有哪些效果、各属于时点里的哪一步，见 [battle-rules.md 6.3](../docs/design/battle-rules.md#63-特殊技能描述型)。

**格子**：时机、基础技能各两格，特殊技能一格。角色和装备都可以填任意格，通常角色填 1、装备填 2。
合并时装备那一格有内容就覆盖角色的，写 `"clear"` 表示清空，规则见 [battle-rules.md 第 2 节](../docs/design/battle-rules.md#2-卡牌和装备)。

```json
{"id": "tiger_man", "no": 1201, "type": "character", "star": 2, "races": ["beast", "human"], "strength": 8, "timing_1": ["on_engage"], "skills_1": {"rage": 2, "rally": 1}},
{"id": "holy_water", "no": 2210, "type": "equipment", "star": 2, "strength": 2, "skills_2": {"inspire": 2}},
{"id": "toad", "no": 1220, "type": "character", "star": 2, "races": ["nature"], "strength": 8, "timing_1": ["on_enter"], "skills_1": {"corrode": 6}, "special_skills": {"on_resolve_bonus": {"skill": "corrode", "amount": 1}}},
```

## levels.json

```json
{"id": "boar_rush", "enemy": [["porcupine", "venom_sac"], ...], "hand": ["vulture", "maneater", ...]}
```

- `enemy`：敌方阵容，`[角色 id, 装备 id]`，没有装备写 `""`；
- `hand`：玩家可用的卡（角色和装备混在一起）；
- `slots`（可选）：我方能用的卡位数，默认 7；其余卡位显示"未解锁"；
- 关卡名的翻译 key 是 `level.<id>`。
