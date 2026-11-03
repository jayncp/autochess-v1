class_name CardDB
## 卡牌数据：读取 data/cards.json，按 id 查询；装备与角色的合并规则也在这里。
## 字段说明见 docs/plans/stage-1-reorg.md 第 2 节。

const PATH := "res://data/cards.json"
const TYPES := ["character", "equipment"]
const RACES := ["human", "beast", "nature", "divine", "elf"]
## 时机，也是合并后的排列顺序
const TIMINGS := ["pre_battle", "on_enter", "on_engage"]
## 普通技能，也是合并后的排列顺序（结算顺序见 BattleSim.BEATS）
const NORMAL_SKILLS := ["rally", "rage", "corrode", "inspire", "annihilate"]
const SPECIAL_SKILLS := ["lethal", "shelter", "sturdy", "backlash"]
const FIELDS := ["id", "no", "type", "star", "races", "strength", "timing", "skills",
	"weapon_strength", "weapon_timing", "weapon_skills", "special_skills"]
## 装备上可以写"空"（清空角色对应格子）的字段
const CLEARABLE := ["timing", "skills", "special_skills"]
const CLEAR := "clear"

static var _cards := {}


## 全部卡牌：id -> 卡牌数据，顺序与文件一致
static func all() -> Dictionary:
	if _cards.is_empty():
		_load()
	return _cards


static func card(id: String) -> Dictionary:
	return all()[id]


## 临时加入额外的卡牌（只在本次运行有效），供平衡实验使用，比如白板单位、某张卡的不同数值版本。
## 与已有 id 相同时覆盖原卡
static func add_cards(raw_cards: Array) -> void:
	all()
	for raw in raw_cards:
		var c := _normalize(raw)
		_check(c)
		_cards[c.id] = c


## 某一类型的全部 id，顺序与文件一致
static func ids(type: String) -> Array:
	return all().keys().filter(func(id): return _cards[id].type == type)


## 角色带上装备（可为空）之后的战斗属性：战力、时机、普通技能、特殊技能。
static func combine(card_id: String, equip_id: String) -> Dictionary:
	return combine_data(card(card_id), card(equip_id) if equip_id else {})


## 装备像一张卡盖在角色卡上（docs/design/battle-rules.md 第 6 节）：
## 装备那一格没有就沿用角色的，有就覆盖，写"空"就清空；武器战力加到角色战力上，
## 基础技能和武器技能同名相加。
static func combine_data(c: Dictionary, e: Dictionary) -> Dictionary:
	var timing = _overlay(c, e, "timing")
	var weapon_timing = _overlay(c, e, "weapon_timing")
	var skills: Dictionary = _overlay(c, e, "skills", {})
	var weapon_skills: Dictionary = _overlay(c, e, "weapon_skills", {})
	var normal_skills := {}
	for skill in NORMAL_SKILLS:
		var power: int = skills.get(skill, 0) + weapon_skills.get(skill, 0)
		if power > 0:
			normal_skills[skill] = power
	var special: Dictionary = _overlay(c, e, "special_skills", {})
	return {
		"strength": c.strength + e.get("weapon_strength", 0),
		"timings": TIMINGS.filter(func(t): return t == timing or t == weapon_timing),
		"normal_skills": normal_skills,
		"special_skills": special.duplicate(),
	}


## 一格的叠放结果：装备有这格就用装备的（"空"表示清空），否则沿用角色的
static func _overlay(c: Dictionary, e: Dictionary, field: String, empty: Variant = null) -> Variant:
	var value = e[field] if e.has(field) else c.get(field)
	return empty if value == null or value is String and value == CLEAR else value


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
		if c.get(field) is Dictionary:
			# {} 和省略等价：都表示沿用角色的
			if c[field].is_empty():
				c.erase(field)
				continue
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
	for field in CLEARABLE:
		if c.get(field) is String and c[field] == CLEAR and c.get("type") != "equipment":
			bad.append("只有装备能写\"空\"：" + field)
	for field in ["timing", "weapon_timing"]:
		if c.has(field) and c[field] not in TIMINGS and not (field in CLEARABLE and c[field] == CLEAR):
			bad.append("时机 " + c[field])
	for field in ["skills", "weapon_skills", "special_skills"]:
		var value = c.get(field, {})
		if value is String:
			if not (field in CLEARABLE and value == CLEAR):
				bad.append("%s 应为技能字典或 \"clear\"" % field)
			continue
		var known: Array = SPECIAL_SKILLS if field == "special_skills" else NORMAL_SKILLS
		for skill in value:
			if skill not in known:
				bad.append("技能 " + skill)
	if not bad.is_empty():
		push_error("cards.json：%s 有误：%s" % [c.get("id"), ", ".join(bad)])
