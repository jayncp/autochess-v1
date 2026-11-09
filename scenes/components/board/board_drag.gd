class_name BoardDrag
extends Node2D
## 布阵界面的拖放（构筑阶段、科研模式共用），卡牌是这个节点的子节点：
## - 按下卡牌开始拖动：卡牌抬起、发光，原位置留下半透明的影子；动了之后跟着指针走，经过的卡位高亮；
## - 松开时交给子类按规则处理（drop_card）；按下后几乎没动就松开算"点一下"（tap_card），不改变布阵；
## - PC 悬停、手机长按（按住不动）时显示放大的卡（preview）。
## 卡牌和卡位用物理拾取：卡牌的 Area2D 在层 1，卡位在层 2。界面上的按钮先拿到输入，所以按下用 _unhandled_input。

signal lineup_changed

const COLLISION_MASK_CARD := 1
const COLLISION_MASK_CARD_SLOT := 2
const TAP_DISTANCE := 12.0
const LONG_PRESS := 0.45
const LIFT_SCALE := 1.06
const LIFT_ROTATION := -4.0
const DRAG_Z := 1001
const MOVE_TIME := 0.12

var card_being_dragged = null
## 被拖动的卡原来所在的卡位（不是从卡位拖出来的为 null）
var drag_origin_slot = null
## 放大查看，由场景设置
var preview: CardPreview

var _press_position := Vector2.ZERO
var _press_time := 0
var _grab_offset := Vector2.ZERO
var _moved := false
var _ghost: CardFace = null
var _hover_slot = null


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or card_being_dragged:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var card = raycast_check_for_card()
		if card and can_pick(card):
			get_viewport().set_input_as_handled()
			start_drag(card)
		elif card == null:
			var slot = raycast_check_for_card_slot()
			if slot:
				tap_slot(slot)


func _input(event: InputEvent) -> void:
	if card_being_dragged and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_drag()


func _process(_delta: float) -> void:
	if card_being_dragged == null:
		return
	var mouse := get_global_mouse_position()
	if not _moved:
		if mouse.distance_to(_press_position) <= TAP_DISTANCE:
			if preview and not preview.visible and Time.get_ticks_msec() - _press_time > LONG_PRESS * 1000:
				_show_preview(card_being_dragged)
			return
		_moved = true
		if preview:
			preview.hide_card()
	var viewport := get_viewport_rect().size
	card_being_dragged.position = (mouse + _grab_offset).clamp(Vector2.ZERO, viewport)
	var look := drag_look(mouse)
	card_being_dragged.set_look(look[0], look[1])
	var slot = raycast_check_for_card_slot()
	if slot and not slot.interactable:
		slot = null
	if slot != _hover_slot:
		if _hover_slot:
			_hover_slot.hover = false
		_hover_slot = slot
		if slot:
			slot.hover = true


# ---------- 子类按规则实现 ----------

## 这张卡能不能拿起来（敌方的卡不能）
func can_pick(card) -> bool:
	return not card.is_enemy_card


## 把正在拖动的卡放到 slot 上（null 表示格子以外）；开头要调用 end_drag()
func drop_card(_slot) -> void:
	pass


## 按下又松开、几乎没动：默认放回原处
func tap_card(card) -> void:
	return_card(card)


## 点了空卡位（没有卡的地方）
func tap_slot(_slot) -> void:
	pass


## 拖到 at 时卡牌的样子：[缩放, 是否紧凑卡]，比如拖到队列上方时变成队列的样式
func drag_look(_at: Vector2) -> Array:
	return [card_being_dragged.face.display_scale, card_being_dragged.face.compact]


## 放回原来的位置（"点一下"或者放不下时）
func return_card(_card) -> void:
	pass


# ---------- 拖动过程 ----------

func start_drag(card) -> void:
	card_being_dragged = card
	card.stop_moving()
	_moved = false
	_press_position = get_global_mouse_position()
	_press_time = Time.get_ticks_msec()
	_grab_offset = card.position - _press_position
	card.z_index = DRAG_Z
	card.scale = Vector2.ONE * LIFT_SCALE
	card.rotation_degrees = LIFT_ROTATION
	card.face.glow = true
	if preview:
		preview.hide_card()
	# 原位置的影子
	_ghost = CardFace.new()
	_ghost.show_cards(card.card_id, card.equip_id)
	_ghost.display_scale = card.face.display_scale
	_ghost.compact = card.face.compact
	_ghost.position = card.position
	_ghost.modulate.a = 0.25
	_ghost.z_index = card.old_z_index if card.old_z_index != null else 0
	add_child(_ghost)
	# 从卡位拿起：记下来源卡位（互换时要把对方移过去），并清空卡位
	drag_origin_slot = card.card_slot_card_is_in
	if drag_origin_slot != null:
		drag_origin_slot.card_in_slot = null
		card.card_slot_card_is_in = null


## 松开：动过就按规则放下，没动就算"点一下"
func finish_drag() -> void:
	if _moved:
		drop_card(raycast_check_for_card_slot())
		return
	var card = card_being_dragged
	var origin = drag_origin_slot
	end_drag()
	# 放回原来的卡位（"点一下"不改变布阵）
	if origin != null:
		origin.card_in_slot = card
		card.card_slot_card_is_in = origin
	tap_card(card)


## 结束拖动：恢复卡牌的样子，去掉影子和高亮
func end_drag() -> void:
	var card = card_being_dragged
	card_being_dragged = null
	drag_origin_slot = null
	_moved = false
	if card:
		card.scale = Vector2.ONE
		card.rotation_degrees = 0
		card.face.glow = false
		card.z_index = card.old_z_index if card.old_z_index != null else 0
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _hover_slot:
		_hover_slot.hover = false
		_hover_slot = null
	if preview:
		preview.hide_card()


func animate_card_to_position(card, new_position: Vector2, speed := MOVE_TIME) -> void:
	card.move_to(new_position, speed)


# ---------- 悬停查看 ----------

## card.gd 进入场景树时调用
func connect_card_signals(card) -> void:
	card.hovered.connect(on_hovered_over_card)
	card.hovered_off.connect(on_hovered_off_card)


## PC 悬停显示放大的卡；手机靠长按，不用悬停（触摸会模拟鼠标经过）
func on_hovered_over_card(card) -> void:
	if card_being_dragged or preview == null or not CardPreview.hover:
		return
	_show_preview(card)


func on_hovered_off_card(card) -> void:
	if card == card_being_dragged or preview == null:
		return
	var other = raycast_check_for_card()
	if other and other != card and card_being_dragged == null and CardPreview.hover:
		_show_preview(other)
	else:
		preview.hide_card()


func _show_preview(card) -> void:
	if preview == null:
		return
	var size: Vector2 = card.face.get_size()
	preview.show_card(card.card_id, card.equip_id, Rect2(card.global_position - size / 2, size))


# ---------- 拾取 ----------

func raycast_check_for_card():
	var result := _raycast(COLLISION_MASK_CARD)
	if result.is_empty():
		return null
	var top = result[0].collider.get_parent()
	for hit in result:
		var card = hit.collider.get_parent()
		if card.z_index > top.z_index:
			top = card
	return top


func raycast_check_for_card_slot():
	var result := _raycast(COLLISION_MASK_CARD_SLOT)
	return result[0].collider.get_parent() if not result.is_empty() else null


func _raycast(mask: int) -> Array:
	var parameters := PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = mask
	return get_world_2d().direct_space_state.intersect_point(parameters)
