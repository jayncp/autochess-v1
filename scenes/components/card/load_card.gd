class_name load_card
## 生成卡牌实例、刷新卡面显示。卡牌节点用 card_id / equip_id 记录自己是哪张角色和装备。

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
	card_1.get_node("card_image").adjust_size()
	card_1.get_node("equip_image").adjust_size()


## 按 card_id / equip_id 重新显示卡面
static func show_cards(card, card_id: String, equip_id: String):
	card.card_id = card_id
	card.equip_id = equip_id
	clear_UI_text(card)
	if card_id:
		_show_character(card, CardDB.card(card_id))
	if equip_id:
		_show_equipment(card, CardDB.card(equip_id))


static func _show_character(card, data: Dictionary):
	card.get_node("card_image").texture = load("res://assets/cards/%s.png" % data.id)
	card.get_node("card_image").modulate.a = 255
	card.get_node("character_name").text = _t("card." + data.id)
	card.get_node("character_star").text = "★".repeat(data.star)
	update_attribute_display(card, "race", ",".join(data.races.map(func(r): return _t("race." + r))))
	update_attribute_display(card, "strength_1", data.get("strength"))
	update_attribute_display(card, "strength_2", data.get("weapon_strength"))
	_show_timings_and_skills(card, data)


static func _show_equipment(card, data: Dictionary):
	card.get_node("addition_sign").visible = true
	card.get_node("equipment_name").text = _t("card." + data.id)
	card.get_node("equip_image").modulate.a = 255
	card.get_node("equip_image").texture = load("res://assets/cards/%s.png" % data.id)
	card.get_node("equipment_star").text = "★".repeat(data.star)
	# 装备没有种族
	update_attribute_display(card, "strength_2", data.get("weapon_strength"))
	# 装备没有基础战力，把武器战力加到角色战力上
	update_attribute_display(card, "strength_1", int(card.get_node("strength_1").text) + int(card.get_node("strength_2").text))
	# 装备的时机和技能显示在角色的上面
	_show_timings_and_skills(card, data)


static func _show_timings_and_skills(card, data: Dictionary):
	update_attribute_display(card, "time_1", timing_name(data.get("timing")))
	update_attribute_display(card, "time_2", timing_name(data.get("weapon_timing")))
	update_attribute_display(card, "skill_1", generate_skill_string(data.get("skills")))
	update_attribute_display(card, "skill_2", generate_skill_string(data.get("weapon_skills")))
	update_attribute_display(card, "skill_3", generate_skill_string(data.get("special_skills")))


# 清空卡牌UI文本，初始化
static func clear_UI_text(card):
	card.get_node("addition_sign").visible = false
	card.get_node("character_name").text = ""
	card.get_node("character_star").text = ""
	card.get_node("race").text = ""
	card.get_node("equipment_name").text = ""
	card.get_node("equipment_star").text = ""
	card.get_node("strength_1").text = ""
	card.get_node("strength_2").text = ""
	card.get_node("time_1").text = ""
	card.get_node("time_2").text = ""
	card.get_node("skill_1").text = ""
	card.get_node("skill_2").text = ""
	card.get_node("skill_3").text = ""
	card.get_node("all_time").text = ""
	card.get_node("all_normal_skill").text = ""
	card.get_node("card_image").modulate.a = 0
	card.get_node("equip_image").modulate.a = 0

# 更新卡牌属性显示
static func update_attribute_display(card, attri, target):
	# 若目标为null则不更新
	if target != null:
		card.get_node(attri).text = str(target)


## 时机列表的显示文字，如"战前,交战"；单个时机也可以直接传字符串，null 表示没有
static func timing_name(timings):
	if timings == null:
		return null
	if timings is String:
		return _t("timing." + timings)
	return ",".join(timings.map(func(t): return _t("timing." + t)))


## 技能的显示文字，如"狂暴3,腐蚀2"；null 表示没有该栏，空字典表示清空（显示"无"）
static func generate_skill_string(skills):
	if skills == null:
		return null
	if skills.is_empty():
		return _t("ui.common.none")
	var parts := []
	for skill in skills:
		var value = skills[skill]
		parts.append(_t("keyword." + skill) + (str(value) if value != null else ""))
	return ",".join(parts)


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
