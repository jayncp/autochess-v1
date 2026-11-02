class_name load_card

const CARD_THENE_PATH = "res://scenes/components/card/card.tscn"
const CARD_DATABASE_PATH = "res://scripts/database/card_database.gd"


# 给定名字生成单张卡牌实例(位置在初始位置，屏幕外右下角)
static func generate_single_card(card_name):
	var card_scene = preload(CARD_THENE_PATH)
	var card_database_reference = preload(CARD_DATABASE_PATH)
	var new_card = card_scene.instantiate()
	clear_UI_text(new_card)
	if card_database_reference.CARDS[card_name][1] == "角色":
		var card_image_path = str("res://assets/cards/"+card_name+".png")
		new_card.get_node("card_image").texture = load(card_image_path)
		new_card.get_node("card_image").modulate.a = 255
		# 载入卡牌属性-图像显示
		# 角色名称
		var card_data_list = card_database_reference.CARDS[card_name]
		new_card.get_node("character_name").text = card_name
		# 角色星级
		var star_string = ""
		for j in range(0,card_data_list[2]):
			star_string += "★"
		new_card.get_node("character_star").text = star_string
		# 角色种族
		var race_string = ""
		for j in card_data_list[3]:
			if race_string != "":
				race_string += ","
			race_string += j
		update_attribute_display(new_card,"race",race_string)
		# 角色战力
		update_attribute_display(new_card,"strength_1",card_data_list[4])
		update_attribute_display(new_card,"strength_2",card_data_list[5])
		# 角色技能时机
		update_attribute_display(new_card,"time_1",card_data_list[6])
		update_attribute_display(new_card,"time_2",card_data_list[8])
		# 角色技能
		update_attribute_display(new_card,"skill_1",generate_skill_string(card_data_list[7]))
		update_attribute_display(new_card,"skill_2",generate_skill_string(card_data_list[9]))
		update_attribute_display(new_card,"skill_3",generate_skill_string(card_data_list[10]))
	elif card_database_reference.CARDS[card_name][1] == "装备":
		var equip_name = card_name
		new_card.get_node("addition_sign").visible = true
		var equip_data_list = card_database_reference.CARDS[equip_name]
		new_card.get_node("equipment_name").text = equip_name
		# 装备图像
		new_card.get_node("equip_image").modulate.a = 255
		var equip_image_path = str("res://assets/cards/"+equip_name+".png")
		new_card.get_node("equip_image").texture = load(equip_image_path)
		# 装备星级
		var star_string = ""
		for j in range(0,equip_data_list[2]):
			star_string += "★"
		new_card.get_node("equipment_star").text = star_string
		# 装备种族
		# 暂不考虑装备种族
		# 装备战力
		update_attribute_display(new_card,"strength_2",equip_data_list[5])
		# 整备没有基础战力,更新角色战力
		update_attribute_display(new_card,"strength_1",int(new_card.get_node("strength_1").text) + int(new_card.get_node("strength_2").text))
		# 装备技能时机, 覆盖角色技能时机
		update_attribute_display(new_card,"time_1",equip_data_list[6])
		update_attribute_display(new_card,"time_2",equip_data_list[8])
		# 装备技能, 覆盖角色技能
		update_attribute_display(new_card,"skill_1",generate_skill_string(equip_data_list[7]))
		update_attribute_display(new_card,"skill_2",generate_skill_string(equip_data_list[9]))
		update_attribute_display(new_card,"skill_3",generate_skill_string(equip_data_list[10]))
	return new_card

# 合并两张卡牌，将卡牌2的信息合并到卡牌1中，并不删除卡牌2，仅改变卡牌UI，不更新内在属性
# 需保证两张卡牌一张为角色，另一张为装备，未做异常处理
static func union_two_cards(card_1, card_2):
	var card_database_reference = preload(CARD_DATABASE_PATH)
	var card_name = card_1.get_node("character_name").text+card_2.get_node("character_name").text
	var equipment_name = card_1.get_node("equipment_name").text+card_2.get_node("equipment_name").text
	# 载入卡牌属性-图像显示
	# 清空UI文本
	clear_UI_text(card_1)
	# 角色名称
	var card_data_list = card_database_reference.CARDS[card_name]
	card_1.get_node("character_name").text = card_name
	# 角色图像
	var card_image_path = str("res://assets/cards/"+card_name+".png")
	card_1.get_node("card_image").texture = load(card_image_path)
	card_1.get_node("card_image").modulate.a = 255
	card_1.get_node("card_image").adjust_size()
	# 角色星级
	var star_string = ""
	for j in range(0,card_data_list[2]):
		star_string += "★"
	card_1.get_node("character_star").text = star_string
	# 角色种族
	var race_string = ""
	for j in card_data_list[3]:
		if race_string != "":
			race_string += ","
		race_string += j
	update_attribute_display(card_1,"race",race_string)
	# 角色战力
	update_attribute_display(card_1,"strength_1",card_data_list[4])
	update_attribute_display(card_1,"strength_2",card_data_list[5])
	# 角色技能时机
	update_attribute_display(card_1,"time_1",card_data_list[6])
	update_attribute_display(card_1,"time_2",card_data_list[8])
	# 角色技能
	update_attribute_display(card_1,"skill_1",generate_skill_string(card_data_list[7]))
	update_attribute_display(card_1,"skill_2",generate_skill_string(card_data_list[9]))
	update_attribute_display(card_1,"skill_3",generate_skill_string(card_data_list[10]))

	# 载入装备属性-图像显示
	card_1.get_node("addition_sign").visible = true
	var equip_data_list = card_database_reference.CARDS[equipment_name]
	card_1.get_node("equipment_name").text = equipment_name
	# 装备图像
	card_1.get_node("equip_image").modulate.a = 255
	var equip_image_path = str("res://assets/cards/"+equipment_name+".png")
	card_1.get_node("equip_image").texture = load(equip_image_path)
	card_1.get_node("equip_image").modulate.a = 255
	card_1.get_node("equip_image").adjust_size()
	# 装备星级
	star_string = ""
	for j in range(0,equip_data_list[2]):
		star_string += "★"
	card_1.get_node("equipment_star").text = star_string
	# 装备种族
	# 暂不考虑装备种族
	# 装备战力
	update_attribute_display(card_1,"strength_2",equip_data_list[5])
	# 整备没有基础战力,更新角色战力
	update_attribute_display(card_1,"strength_1",int(card_1.get_node("strength_1").text) + int(card_1.get_node("strength_2").text))
	# 装备技能时机, 覆盖角色技能时机
	update_attribute_display(card_1,"time_1",equip_data_list[6])
	update_attribute_display(card_1,"time_2",equip_data_list[8])
	# 装备技能, 覆盖角色技能
	update_attribute_display(card_1,"skill_1",generate_skill_string(equip_data_list[7]))
	update_attribute_display(card_1,"skill_2",generate_skill_string(equip_data_list[9]))
	update_attribute_display(card_1,"skill_3",generate_skill_string(equip_data_list[10]))

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

# 生成技能列表
static func generate_skill_string(skill_list):
	# 注意[]!=null
	if skill_list == null:
		return null
	# 空心的空技能
	if skill_list == []:
		return "无"
	var skill_string = ""
	for j in skill_list:
		if skill_string != "":
			skill_string += ","
		skill_string += j.keys()[0]
		if j.values()[0] > -1:
			skill_string += str(j.values()[0])
	return skill_string
