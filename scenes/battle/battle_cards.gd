extends Node2D
## 战斗界面的卡牌都放在这里；点卡（按下又松开、几乎没动）打开查看（CardDetail）。
## 卡牌用物理拾取（Area2D 在层 1），界面上的按钮先拿到输入，所以用 _unhandled_input。

const COLLISION_MASK_CARD := 1
const TAP_DISTANCE := 16.0

var _press := Vector2.INF


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_press = event.position
	elif event.position.distance_to(_press) < TAP_DISTANCE:
		var card = card_at(get_global_mouse_position())
		if card:
			get_viewport().set_input_as_handled()
			open_detail(card)


func open_detail(card) -> CardDetail:
	var detail := CardDetail.new(card.face, card.card_id, card.equip_id)
	get_parent().add_child(detail)
	return detail


func card_at(at: Vector2):
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = at
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result := get_world_2d().direct_space_state.intersect_point(parameters)
	return result[0].collider.get_parent() if not result.is_empty() else null
