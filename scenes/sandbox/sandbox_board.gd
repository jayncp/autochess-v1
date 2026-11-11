extends BoardDrag
## 科研模式的拖放：阵容在 sandbox.gd 里（lineups），这里按阵容摆卡，拖放后改阵容再重摆。
## - 从选卡区拖出的卡：放到卡位上就为那个卡位选这张卡（和在选卡区点卡一样），放到别处作废；
## - 场上的卡：拖到另一个卡位互换（空的就移过去），拖到卡位以外移除；
## - 点卡或空卡位：选中这个卡位。

@onready var sandbox = $".."
## 队列里卡牌的样子：[缩放, 是否紧凑卡]；队列所在的竖直范围，拖到这里时卡牌变成队列的样式
var lineup_look := [0.6, false]
var lineup_band := Vector2(0, 0)
## 选卡区里卡牌的样子
var picker_look := [0.6, true]


## 按阵容摆卡：先清掉，再按每个卡位的内容生成
func render(slots: Dictionary) -> void:
	for child in get_children():
		if child != card_being_dragged and child.has_method("set_look"):
			remove_child(child)
			child.queue_free()
	for side in slots:
		for slot in slots[side]:
			var unit: Array = sandbox.lineups[side][slot.get_meta("index")]
			slot.card_in_slot = null
			if unit.is_empty():
				continue
			var card = load_card.generate(unit[0], unit[1])
			card.set_look(lineup_look[0], lineup_look[1])
			card.position = slot.position
			card.card_slot_card_is_in = slot
			card.old_z_index = 0
			slot.card_in_slot = card
			add_child(card)


## 从选卡区拖出一张卡：在指针处生成，接着拖（原卡还在选卡区，不留影子）
func start_drag_new(id: String) -> void:
	var card = load_card.generate_single_card(id)
	card.set_meta("picked", id)
	card.set_look(picker_look[0], picker_look[1])
	card.position = get_global_mouse_position()
	add_child(card)
	start_drag(card, false)
	_moved = true


func drag_look(at: Vector2) -> Array:
	if at.y >= lineup_band.x and at.y <= lineup_band.y:
		return lineup_look
	return picker_look


func drop_card(slot) -> void:
	var card = card_being_dragged
	var origin = drag_origin_slot
	end_drag()
	if slot != null and not slot.interactable:
		slot = null
	if card.has_meta("picked"):
		card.queue_free()
		if slot:
			sandbox.select_slot(slot.get_meta("side"), slot.get_meta("index"))
			sandbox.pick(card.get_meta("picked"))
	elif slot == null:
		sandbox.set_unit(origin.get_meta("side"), origin.get_meta("index"), "", "")
	elif slot != origin:
		sandbox.move_unit(origin.get_meta("side"), origin.get_meta("index"), slot.get_meta("side"), slot.get_meta("index"))
		sandbox.select_slot(slot.get_meta("side"), slot.get_meta("index"))
	sandbox.refresh()
	lineup_changed.emit()


func tap_card(card) -> void:
	var slot = card.card_slot_card_is_in
	if slot:
		sandbox.select_slot(slot.get_meta("side"), slot.get_meta("index"))
	sandbox.refresh()


func tap_slot(slot) -> void:
	sandbox.select_slot(slot.get_meta("side"), slot.get_meta("index"))
	sandbox.refresh()


func return_card(_card) -> void:
	sandbox.refresh()
