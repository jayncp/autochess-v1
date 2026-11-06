class_name load_card
## 生成卡牌实例、刷新卡面显示。卡牌节点用 card_id / equip_id 记录自己是哪张角色和装备。

const CARD_SCENE := preload("res://scenes/components/card/card.tscn")
## 还没有卡图的卡用这张占位图
const PLACEHOLDER_ART := "res://assets/cards/placeholder.png"
## 文字放不下时最小缩到多大的字号
const MIN_FONT_SIZE := 8


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


## 卡图；还没有卡图的卡用占位图
static func art(id: String) -> Texture2D:
	var path := "res://assets/cards/%s.png" % id
	return load(path if ResourceLoader.exists(path) else PLACEHOLDER_ART)


static func _show_character(card, data: Dictionary):
	card.get_node("card_image").texture = art(data.id)
	card.get_node("card_image").modulate.a = 255
	card.get_node("character_name").text = _t("card." + data.id)
	card.get_node("character_star").text = "★".repeat(data.star)
	var races := CardDB.sorted_races(data.races).map(func(r): return _t("race." + r))
	update_attribute_display(card, "race", _t("ui.card.separator").join(races))
	update_attribute_display(card, "strength_1", data.strength)
	_show_slots(card, data)


static func _show_equipment(card, data: Dictionary):
	card.get_node("addition_sign").visible = true
	card.get_node("equipment_name").text = _t("card." + data.id)
	card.get_node("equip_image").modulate.a = 255
	card.get_node("equip_image").texture = art(data.id)
	card.get_node("equipment_star").text = "★".repeat(data.star)
	# 装备没有种族；装备的战斗力显示在第二行，第一行显示合计
	update_attribute_display(card, "strength_2", data.get("strength"))
	update_attribute_display(card, "strength_1", int(card.get_node("strength_1").text) + int(card.get_node("strength_2").text))
	# 装备的格子盖在角色的上面：有内容才覆盖
	_show_slots(card, data)


static func _show_slots(card, data: Dictionary):
	update_attribute_display(card, "time_1", timing_name(data.get("timing_1")))
	update_attribute_display(card, "time_2", timing_name(data.get("timing_2")))
	update_attribute_display(card, "skill_1", base_skill_text(data.get("skills_1")))
	update_attribute_display(card, "skill_2", base_skill_text(data.get("skills_2")))
	update_attribute_display(card, "skill_3", special_skill_text(data.get("special_skills")))


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
	card.get_node("all_base_skill").text = ""
	card.get_node("card_image").modulate.a = 0
	card.get_node("equip_image").modulate.a = 0

## 更新卡牌属性显示：目标为 null 则不更新；文字放不下时缩小字号
static func update_attribute_display(card, attri, target):
	if target == null:
		return
	var label: Label = card.get_node(attri)
	label.text = str(target)
	fit_text(label)


## 文字放不下时逐级缩小字号（最小 MIN_FONT_SIZE），放得下时恢复场景里设的字号。
## 不在场景树里时字体还没加载、量不出排版，等进入场景树再调
static func fit_text(label: Label) -> void:
	if not label.is_inside_tree():
		if not label.has_meta("fit_pending"):
			label.set_meta("fit_pending", true)
			label.tree_entered.connect(func():
				label.remove_meta("fit_pending")
				fit_text(label), CONNECT_ONE_SHOT)
		return
	if not label.has_meta("base_font_size"):
		label.set_meta("base_font_size", label.get_theme_font_size("font_size"))
	var size: int = label.get_meta("base_font_size")
	label.add_theme_font_size_override("font_size", size)
	while size > MIN_FONT_SIZE and not _fits(label):
		size -= 1
		label.add_theme_font_size_override("font_size", size)


## 自动换行的看行数是否都显示得下，不换行的看宽度
static func _fits(label: Label) -> bool:
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		var size := label.get_theme_font_size("font_size")
		return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x
	return label.get_line_count() <= label.get_visible_line_count()


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
		parts.append(_one_skill_text(skill, skills[skill]))
	return separator.join(parts)


static func _one_skill_text(skill: String, value) -> String:
	if skill in CardDB.DESCRIPTIVE_SPECIALS:
		return _t("effect." + skill) % value
	if value is Dictionary:
		return _t("ui.card.timed_special") % [_t("timing." + value.timing), _t("keyword." + skill)]
	return _t("keyword." + skill) + (str(value) if value != null else "")


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
