class_name CardDB
## 卡牌数据：读取 data/cards.json，按 id 查询；装备与角色的合并规则也在这里。
## 字段说明见 docs/plans/stage-1-reorg.md 第 2 节。

const PATH := "res://data/cards.json"
const TYPES := ["character", "equipment"]
const RACES := ["human", "beast", "nature", "divine", "elf"]
## 时机，也是合并后的排列顺序
const TIMINGS := ["pre_battle", "on_enter", "on_engage"]
## 普通技能，也是合并后的排列顺序
const NORMAL_SKILLS := ["rally", "rage", "corrode", "inspire"]
const SPECIAL_SKILLS := ["lethal", "shelter", "sturdy", "backlash"]
const FIELDS := ["id", "no", "type", "star", "races", "strength", "timing", "skills",
	"weapon_strength", "weapon_timing", "weapon_skills", "special_skills"]

static var _cards := {}


## 全部卡牌：id -> 卡牌数据，顺序与文件一致
static func all() -> Dictionary:
	if _cards.is_empty():
		_load()
	return _cards


static func card(id: String) -> Dictionary:
	return all()[id]


## 某一类型的全部 id，顺序与文件一致
static func ids(type: String) -> Array:
	return all().keys().filter(func(id): return _cards[id].type == type)


## 角色带上装备（可为空）之后的战斗属性：战力、时机、普通技能、特殊技能。
## 规则见 docs/design/battle-rules.md 第 6 节；基础技能目前按技能名逐个覆盖，尚未整体替换。
static func combine(card_id: String, equip_id: String) -> Dictionary:
	var c := card(card_id)
	var e: Dictionary = card(equip_id) if equip_id else {}
	var timing = e.get("timing", c.get("timing"))
	var weapon_timing = e.get("weapon_timing", c.get("weapon_timing"))
	var normal_skills := {}
	for skill in NORMAL_SKILLS:
		var power: int = _skill_power(skill, "skills", c, e) + _skill_power(skill, "weapon_skills", c, e)
		if power > 0:
			normal_skills[skill] = power
	var special: Dictionary = e.special_skills if e.get("special_skills") else c.get("special_skills", {})
	return {
		"strength": c.strength + e.get("weapon_strength", 0),
		"timings": TIMINGS.filter(func(t): return t == timing or t == weapon_timing),
		"normal_skills": normal_skills,
		"special_skills": special.duplicate(),
	}


## 装备有同名技能时覆盖角色的；装备该栏为空字典（空心）时清零
static func _skill_power(skill: String, field: String, c: Dictionary, e: Dictionary) -> int:
	var power: int = c.get(field, {}).get(skill, 0)
	if e.has(field):
		power = 0 if e[field].is_empty() else e[field].get(skill, power)
	return power


static func _load() -> void:
	for raw in JSON.parse_string(FileAccess.get_file_as_string(PATH)):
		var c := _normalize(raw)
		if _cards.has(c.id):
			push_error("cards.json：id 重复 %s" % c.id)
		_check(c)
		_cards[c.id] = c


## JSON 的数字都读成 float，这里转回 int
static func _normalize(raw: Dictionary) -> Dictionary:
	var c := raw.duplicate(true)
	for field in ["no", "star", "strength", "weapon_strength"]:
		if c.has(field):
			c[field] = int(c[field])
	for field in ["skills", "weapon_skills", "special_skills"]:
		if c.has(field):
			for skill in c[field]:
				if c[field][skill] != null:
					c[field][skill] = int(c[field][skill])
	return c


static func _check(c: Dictionary) -> void:
	var bad := []
	for field in c:
		if field not in FIELDS:
			bad.append("未知字段 " + field)
	if c.get("type") not in TYPES:
		bad.append("类型 %s" % c.get("type"))
	for race in c.get("races", []):
		if race not in RACES:
			bad.append("种族 " + race)
	for field in ["timing", "weapon_timing"]:
		if c.has(field) and c[field] not in TIMINGS:
			bad.append("时机 " + c[field])
	for field in ["skills", "weapon_skills"]:
		for skill in c.get(field, {}):
			if skill not in NORMAL_SKILLS:
				bad.append("普通技能 " + skill)
	for skill in c.get("special_skills", {}):
		if skill not in SPECIAL_SKILLS:
			bad.append("特殊技能 " + skill)
	if not bad.is_empty():
		push_error("cards.json：%s 有误：%s" % [c.get("id"), ", ".join(bad)])
