class_name CardDB
## 卡牌数据：读取 data/cards.json，按 id 查询；装备与角色的合并规则也在这里。
## 字段说明见 data/README.md。

const PATH := "res://data/cards.json"
const TYPES := ["character", "equipment"]
## 下面几个列表的顺序就是显示顺序（docs/design/battle-rules.md 第 1 节），卡面、实时状态、图鉴都按它排
const RACES := ["beast", "human", "elf", "divine", "nature", "treasure"]
const TIMINGS := ["pre_battle", "on_enter", "on_engage"]
## 基础技能，也是结算顺序：作用对象由近及远，先加后减，财富最后。BattleSim 按它分拍
const BASE_SKILLS := ["rage", "rally", "support", "inspire", "corrode", "annihilate", "wealth"]
## 特殊技能按所属种族排，同族里基础特殊技能在前
const SPECIAL_SKILLS := ["backlash", "sturdy", "rally_gain", "awaken", "shelter", "lethal", "corrode_boost"]
## 带时机的特殊技能，数据里写 {"timing": 时机}；时机属于特殊技能本身，和卡牌的时机无关
const TIMED_SPECIALS := ["awaken"]
## 描述型特殊技能：不起词条名，卡面写整句（翻译 key 是 effect.<id>，%d 是数值）
const DESCRIPTIVE_SPECIALS := ["rally_gain", "corrode_boost"]
## 格子：时机、基础技能各两格（通常角色填 1、装备填 2），特殊技能一格
const TIMING_SLOTS := ["timing_1", "timing_2"]
const SKILL_SLOTS := ["skills_1", "skills_2"]
const SLOTS := ["timing_1", "timing_2", "skills_1", "skills_2", "special_skills"]
const FIELDS := ["id", "no", "type", "star", "races", "strength",
	"timing_1", "timing_2", "skills_1", "skills_2", "special_skills"]
## 装备的格子里写"空"表示清空角色的那一格
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


## 角色带上装备（可为空）之后的战斗属性：战斗力、时机、基础技能、特殊技能。
static func combine(card_id: String, equip_id: String) -> Dictionary:
	return combine_data(card(card_id), card(equip_id) if equip_id else {})


## 装备像一张卡盖在角色卡上（docs/design/battle-rules.md 第 6 节）：
## 逐格处理，装备那一格有内容就覆盖，没有就沿用角色的，写"空"就清空；
## 然后两格合并：时机取并集，基础技能同名相加。战斗力不分格，角色的加上装备的。
static func combine_data(c: Dictionary, e: Dictionary) -> Dictionary:
	var timings := TIMING_SLOTS.map(func(slot): return _overlay(c, e, slot))
	var skills := SKILL_SLOTS.map(func(slot): return _overlay(c, e, slot, {}))
	var base_skills := {}
	for skill in BASE_SKILLS:
		var power: int = skills[0].get(skill, 0) + skills[1].get(skill, 0)
		if power > 0:
			base_skills[skill] = power
	var special: Dictionary = _overlay(c, e, "special_skills", {})
	return {
		"strength": c.strength + e.get("strength", 0),
		"timings": TIMINGS.filter(func(t): return t in timings),
		"base_skills": base_skills,
		"special_skills": special.duplicate(),
	}


## 一格的叠放结果：装备有这格就用装备的（"空"表示清空），否则沿用角色的
static func _overlay(c: Dictionary, e: Dictionary, slot: String, empty: Variant = null) -> Variant:
	var value = e[slot] if e.has(slot) else c.get(slot)
	return empty if value == null or value is String and value == CLEAR else value


## 按显示顺序排列：races 按 RACES，技能字典按 BASE_SKILLS 或 SPECIAL_SKILLS
static func sorted_races(races: Array) -> Array:
	return RACES.filter(func(r): return r in races)


static func sorted_skills(skills: Dictionary) -> Array:
	return (BASE_SKILLS + SPECIAL_SKILLS).filter(func(s): return skills.has(s))


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
	for field in ["no", "star", "strength"]:
		if c.has(field):
			c[field] = int(c[field])
	for field in SKILL_SLOTS + ["special_skills"]:
		if c.get(field) is Dictionary:
			# {} 和省略等价：都表示沿用角色的
			if c[field].is_empty():
				c.erase(field)
				continue
			for skill in c[field]:
				if c[field][skill] is float:
					c[field][skill] = int(c[field][skill])
	return c


static func _check(c: Dictionary) -> void:
	var bad := []
	for field in c:
		if field not in FIELDS:
			bad.append("未知字段 " + field)
	if c.get("type") not in TYPES:
		bad.append("类型 %s" % c.get("type"))
	if c.get("type") == "character" and not c.has("strength"):
		bad.append("角色缺少战斗力")
	for race in c.get("races", []):
		if race not in RACES:
			bad.append("种族 " + race)
	for slot in SLOTS:
		if c.get(slot) is String and c[slot] == CLEAR and c.get("type") != "equipment":
			bad.append("只有装备能写\"空\"：" + slot)
	for slot in TIMING_SLOTS:
		if c.has(slot) and c[slot] not in TIMINGS and c[slot] != CLEAR:
			bad.append("时机 " + c[slot])
	for slot in SKILL_SLOTS + ["special_skills"]:
		var value = c.get(slot, {})
		if value is String:
			if value != CLEAR:
				bad.append("%s 应为技能字典或 \"clear\"" % slot)
			continue
		var known: Array = SPECIAL_SKILLS if slot == "special_skills" else BASE_SKILLS
		for skill in value:
			if skill not in known:
				bad.append("技能 " + skill)
			elif skill in TIMED_SPECIALS:
				if not (value[skill] is Dictionary and value[skill].get("timing") in TIMINGS):
					bad.append("%s 要写成 {\"timing\": 时机}" % skill)
			elif value[skill] is Dictionary:
				bad.append("%s 不带时机" % skill)
	if not bad.is_empty():
		push_error("cards.json：%s 有误：%s" % [c.get("id"), ", ".join(bad)])
