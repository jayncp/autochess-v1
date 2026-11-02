extends Node2D

signal back_to_level_select
signal start_battle

var level_name

var level_database_reference
var level_info

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var background_path = "res://assets/backgrounds/setup.png"
	# 设置背景图片
	var background_texture = load_background.set_texture_for_node(
		$Background, 
		background_path, 
		0.5, 
		Vector2(1920, 1080)
	)
	level_database_reference = preload("res://scripts/database/level_database.gd")
	level_info = level_database_reference.LEVEL
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_back_button_pressed() -> void:
	emit_signal("back_to_level_select")

func _on_start_battle_pressed() -> void:
	if generate_battle_list()!= null:
		global_var.battle_card_list_1 = level_info[level_name][0]
		global_var.battle_card_list_2 = generate_battle_list()[0]
		global_var.battle_equip_list_1 = level_info[level_name][1]
		global_var.battle_equip_list_2 = generate_battle_list()[1]
		emit_signal("start_battle")
	else:
		$"output_text".text = "阵容有误，请调整！"

# 检索我方队伍
func generate_battle_list():
	var battle_card_list = []
	var battle_equip_list = []
	# 通过卡牌位置检索
	for j in range(0,7):
		var card_x = (j+1)*240
		var card_y = 540

		var this_card = null
		for t_card in $"advanced_card_manager".get_children():
			if t_card.position.x == card_x and t_card.position.y == card_y:
				this_card = t_card
		if this_card == null:
			continue
		if (this_card.get_node("character_name").text=="") and (this_card.get_node("equipment_name").text!=""):
			return null
		battle_card_list.append(this_card.get_node("character_name").text)
		battle_equip_list.append(this_card.get_node("equipment_name").text)
	return [battle_card_list,battle_equip_list]
