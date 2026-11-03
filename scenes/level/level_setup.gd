extends Node2D

signal back_to_level_select
signal start_battle

var level_id

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


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_back_button_pressed() -> void:
	emit_signal("back_to_level_select")

func _on_start_battle_pressed() -> void:
	var lineup = generate_battle_list()
	# 至少上场一个角色（装备不能单独上场，所以场上的卡都有角色）
	if lineup[0].is_empty():
		$"output_text".text = tr("ui.level_setup.need_character")
		return
	var enemy: Array = LevelDB.level(level_id).enemy
	global_var.battle_card_list_1 = enemy.map(func(u): return u[0])
	global_var.battle_card_list_2 = lineup[0]
	global_var.battle_equip_list_1 = enemy.map(func(u): return u[1])
	global_var.battle_equip_list_2 = lineup[1]
	emit_signal("start_battle")

# 检索我方队伍：按卡槽从左到右
func generate_battle_list():
	var battle_card_list = []
	var battle_equip_list = []
	for slot in $"player_card_slots".get_children():
		var card = slot.card_in_slot
		if card == null:
			continue
		battle_card_list.append(card.card_id)
		battle_equip_list.append(card.equip_id)
	return [battle_card_list,battle_equip_list]
