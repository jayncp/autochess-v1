class_name load_card
## 生成卡牌实例、卡面文字。卡牌节点用 card_id / equip_id 记录自己是哪张角色和装备，卡面由 CardFace 画。

const CARD_SCENE := preload("res://scenes/components/card/card.tscn")


## 生成卡牌实例（位置在初始位置，屏幕外右下角）：只有角色、只有装备，或角色带装备
static func generate(card_id: String, equip_id: String = ""):
	var new_card = CARD_SCENE.instantiate()
	show_cards(new_card, card_id, equip_id)
	return new_card


## 给定 id 生成单张卡牌，按类型决定是角色卡还是装备卡
static func generate_single_card(id: String):
	if CardDB.card(id).type == "character":
		return generate(id)
	return generate("", id)


## 合并两张卡牌：把卡牌 2 合并到卡牌 1 上，只改卡面，不删除卡牌 2，不更新战斗属性
## 需保证一张为角色、另一张为装备，未做异常处理
static func union_two_cards(card_1, card_2):
	var card_id: String = card_1.card_id if card_1.card_id else card_2.card_id
	var equip_id: String = card_1.equip_id if card_1.equip_id else card_2.equip_id
	show_cards(card_1, card_id, equip_id)


## 按 card_id / equip_id 重新显示卡面
static func show_cards(card, card_id: String, equip_id: String):
	card.card_id = card_id
	card.equip_id = equip_id
	card.face.show_cards(card_id, equip_id)


## 时机的显示文字，如"战前、交战"；单个时机也可以直接传字符串，null 表示没有，"clear" 显示"空"
static func timing_name(timings):
	if timings == null:
		return null
	if timings is String:
		return _t("ui.card.clear") if timings == CardDB.CLEAR else _t("timing." + timings)
	return _t("ui.card.separator").join(timings.map(func(t): return _t("timing." + t)))


## 基础技能的显示文字，如"狂暴3、腐蚀2"
static func base_skill_text(skills):
	return _skill_text(skills, _t("ui.card.separator"))


## 特殊技能的显示文字，如"坚固4；致命"；带时机的写成"战前：唤醒"，描述型的写整句
static func special_skill_text(skills):
	return _skill_text(skills, _t("ui.card.special_separator"))


## 按 CardDB 的顺序排列；null 表示没有该栏，"clear" 显示"空"，战斗中技能被清空显示"无"
static func _skill_text(skills, separator: String):
	if skills == null:
		return null
	if skills is String:
		return _t("ui.card.clear")
	if skills.is_empty():
		return _t("ui.common.none")
	var parts := []
	for skill in CardDB.sorted_skills(skills):
		parts.append(one_skill_text(skill, skills[skill]))
	return separator.join(parts)


## 一个技能的显示文字，如"狂暴3"、"战前：唤醒"；描述型的写整句
static func one_skill_text(skill: String, value) -> String:
	if skill in CardDB.DESCRIPTIVE_SPECIALS:
		return _t("effect." + skill) % value
	if value is Dictionary:
		return _t("ui.card.timed_special") % [_t("timing." + value.timing), _t("keyword." + skill)]
	return _t("keyword." + skill) + (str(value) if value != null else "")


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
