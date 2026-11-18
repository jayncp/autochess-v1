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
## 特殊技能按所属种族排，同族里词条在前；不属于某个种族的描述型效果在最后，按时点里的步骤排（被动在前）
const SPECIAL_SKILLS := ["backlash", "sturdy", "assist", "immune_lethal", "on_trigger_gain", "awaken", "shelter", "bless",
	"lethal", "on_resolve_bonus", "on_resolve_raise", "extra_resolve", "extra_round", "double_skills", "double_equipment",
	"copy_skills", "grant", "clear_skills", "raise_skills", "gain_half_skill_sum", "gain_if_outnumbered", "damage_half_strength"]
## 描述型特殊技能：一种效果一个 id 加参数，不起词条名，卡面写整句（翻译 key 是 effect.<id>，{参数名} 换成参数）
const DESCRIPTIVE_SPECIALS := ["on_trigger_gain", "on_resolve_bonus", "on_resolve_raise", "extra_resolve", "extra_round",
	"double_skills", "double_equipment", "copy_skills", "grant", "clear_skills", "raise_skills", "gain_half_skill_sum",
	"gain_if_outnumbered", "damage_half_strength"]
## 写成参数字典的特殊技能和它们的参数；不在这里的写数值（如庇护的层数）或 null（如致命、千机之匣）。
## timings：带时机的特殊技能在哪些时机生效（属于特殊技能本身，和卡牌的时机无关）；
## skill：基础技能（"any" 是任意 / 所有基础技能；获得的可以是词条）；amount：数值（获得没有数值的词条时是 null）；
## scope：被动的范围（SCOPES）；timing：作用于哪个时机（多一轮）；target：对象（TARGETS）
const SPECIAL_PARAMS := {
	"awaken": ["timings"],
	"bless": ["timings", "amount"],
	"on_trigger_gain": ["skill", "amount"],
	"on_resolve_bonus": ["skill", "amount"],
	"on_resolve_raise": ["skill", "amount"],
	"extra_resolve": ["scope", "skill"],
	"extra_round": ["scope", "timing"],
	"copy_skills": ["timings"],
	"grant": ["timings", "target", "skill", "amount"],
	"clear_skills": ["timings", "target"],
	"raise_skills": ["timings", "skill", "amount"],
	"gain_half_skill_sum": ["timings"],
	"gain_if_outnumbered": ["timings", "amount"],
	"damage_half_strength": ["timings"],
}
## 被动的范围：自身、己方全体、开战时位于己方第 1 位的角色（翻译 key 是 scope.<id>）
const SCOPES := ["self", "allies", "first"]
## 对象：下一位、己方全体、对方全体、对方前两位（翻译 key 是 target.<id>）
const TARGETS := ["next", "allies", "enemies", "enemy_first_two"]
## "任意 / 所有基础技能"（翻译 key 是 keyword.any）
const ANY := "any"
## 格子：时机、基础技能各两格（通常角色填 1、装备填 2），特殊技能一格。时机格写时机的列表
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


## 角色带上装备（可为空）之后的战斗属性：战斗力、时机、基础技能、特殊技能，以及特殊技能来自哪张卡。
static func combine(card_id: String, equip_id: String) -> Dictionary:
	return combine_data(card(card_id), card(equip_id) if equip_id else {})


## 装备像一张卡盖在角色卡上（docs/design/battle-rules.md 第 2 节）：
## 逐格处理，装备那一格有内容就覆盖，没有就沿用角色的，写"空"就清空；
## 然后两格合并：时机取并集，基础技能同名相加。战斗力不分格，角色的加上装备的。
static func combine_data(c: Dictionary, e: Dictionary) -> Dictionary:
	var timings := []
	for slot in TIMING_SLOTS:
		timings.append_array(_overlay(c, e, slot, []))
	var special: Dictionary = _overlay(c, e, "special_skills", {})
	# 千机魔女：从装备获得的战斗力和基础技能数值翻倍（装备那一格覆盖了角色的才算从装备获得；特殊技能被装备覆盖掉就没有这个效果）
	var times := 2 if special.has("double_equipment") else 1
	var base_skills := {}
	for slot in SKILL_SLOTS:
		var skills: Dictionary = _overlay(c, e, slot, {})
		var k := times if times > 1 and e.get(slot) is Dictionary else 1
		for skill in skills:
			base_skills[skill] = base_skills.get(skill, 0) + skills[skill] * k
	# 按结算顺序排，数值不大于 0 的去掉
	var sorted := {}
	for skill in BASE_SKILLS:
		if base_skills.get(skill, 0) > 0:
			sorted[skill] = base_skills[skill]
	base_skills = sorted
	return {
		"strength": c.strength + e.get("strength", 0) * times,
		"timings": TIMINGS.filter(func(t): return t in timings),
		"base_skills": base_skills,
		"special_skills": special.duplicate(),
		# 描述型特殊技能触发时，飘字显示这张卡的名字
		"special_source": e.get("id", "") if e.has("special_skills") else c.get("id", ""),
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


## JSON 的数字都读成 float，这里转回 int（含特殊技能的参数）
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
				var value = c[field][skill]
				if value is float:
					c[field][skill] = int(value)
				elif value is Dictionary:
					for key in value:
						if value[key] is float:
							value[key] = int(value[key])
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
		if c.has(slot) and not (c[slot] is String and c[slot] == CLEAR or _valid_timings(c[slot])):
			bad.append("%s 应为时机的列表或 \"clear\"：%s" % [slot, c[slot]])
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
			elif skill in SPECIAL_PARAMS:
				var error := _check_params(value[skill], SPECIAL_PARAMS[skill])
				if error:
					bad.append("%s 的参数%s" % [skill, error])
			elif not (value[skill] == null or value[skill] is int):
				bad.append("%s 应为数值或 null" % skill)
	if not bad.is_empty():
		push_error("cards.json：%s 有误：%s" % [c.get("id"), ", ".join(bad)])


## 时机的列表：不空、不重复，都是已知的时机
static func _valid_timings(value) -> bool:
	if not value is Array or value.is_empty():
		return false
	for i in value.size():
		if value[i] not in TIMINGS or value.find(value[i]) != i:
			return false
	return true


## 特殊技能的参数字典：正好是这几个参数，取值合法；没问题返回空字符串
static func _check_params(params, keys: Array) -> String:
	if not params is Dictionary or params.keys().size() != keys.size() or not keys.all(func(k): return params.has(k)):
		return "应为 %s" % [keys]
	for key in keys:
		var ok: bool
		match key:
			"timings":
				ok = _valid_timings(params[key])
			"skill":
				ok = params[key] in BASE_SKILLS or params[key] == ANY or params[key] in SPECIAL_SKILLS and params[key] not in SPECIAL_PARAMS
			"amount":
				ok = params[key] is int or params[key] == null and params.get("skill") in SPECIAL_SKILLS
			"target":
				ok = params[key] in TARGETS
			"scope":
				ok = params[key] in SCOPES
			"timing":
				ok = params[key] in TIMINGS
		if not ok:
			return " %s 不对：%s" % [key, params[key]]
	return ""
