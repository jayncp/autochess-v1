extends Node2D

# 卡牌尺寸变化常数
const DEFAULT_CARD_SCALE = 1
const CARD_BIGGER_SCALE = 1.7
# 碰撞掩码
const COLLISION_MASK_CARD = 1


# 卡牌悬停高亮
var is_hovering_on_card

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

# 接收悬停信号
func connect_card_signals(card):
	card.connect("hovered",on_hovered_over_card)
	card.connect("hovered_off",on_hovered_off_card)

func on_hovered_over_card(card):
	if card.is_playing_animation:
		return
	# 鼠标指针选停在卡牌上时对卡牌进行高亮显示
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card,true)

# 放大突出显示卡牌		
func highlight_card(card, hovered):
	if hovered:
		card.scale = Vector2(CARD_BIGGER_SCALE,CARD_BIGGER_SCALE)
		card.z_index = 2
	else:
		card.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)
		card.z_index = 1

func on_hovered_off_card(card):
	# 鼠标指针离开卡牌时取消高亮显示
	if card.is_playing_animation == false:
		highlight_card(card,false)
	var new_card_hovered = raycast_check_for_card()
	if (new_card_hovered) and new_card_hovered.is_playing_animation == false:
		highlight_card(new_card_hovered, true)
	else:
		is_hovering_on_card = false

# 卡牌射线投射
func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size()>0:
		return get_card_with_highest_z_index(result)
	else:
		return null

# 获取z_index最上面卡牌
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	
	for i in range(1,cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card

var is_union_UI = true
func _on_check_button_pressed():
	# 切换卡牌技能部分UI
	if is_union_UI == false:
		is_union_UI = true
		for i in range(1,3):
			for j in $"../battle_manager".player_battle_fields[i]:
				j.get_node("card_skill_UI").modulate.a = 255
				j.get_node("all_time").visible = true
				j.get_node("all_normal_skill").visible = true
	else:
		is_union_UI = false
		for i in range(1,3):
			for j in $"../battle_manager".player_battle_fields[i]:
				j.get_node("card_skill_UI").modulate.a = 0
				j.get_node("all_time").visible = false
				j.get_node("all_normal_skill").visible = false
