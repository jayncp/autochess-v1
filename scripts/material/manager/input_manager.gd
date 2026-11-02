# 输入管理器，用于接受鼠标点击事件，并进行射线投射检查

extends Node2D

const COLLISION_MASK_CARD = 1

var card_manager_reference

signal left_mouse_button_clicked
signal left_mouse_button_released

func _ready() -> void:
	card_manager_reference = $"../advanced_card_manager"

func _input(event: InputEvent) -> void:
	# 如果当前场景被隐藏则不执行
	if get_parent().visible == false:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			# raycast_at_cursor()
			raycast_check_for_card()
		else:
			emit_signal("left_mouse_button_released")


func raycast_at_cursor():
	# 射线投射检查，根据collision_mask判断光标位置对象类型
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	var result = space_state.intersect_point(parameters)
	if result.size()>0:
		var result_collision_mask = result[0].collider.collision_mask
		if result_collision_mask == COLLISION_MASK_CARD:
			var card_found = result[0].collider.get_parent()
			if card_found:
				card_manager_reference.card_clicked(card_found)

# 卡牌射线投射
func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size()>0:
		card_manager_reference.card_clicked(get_card_with_highest_z_index(result))

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