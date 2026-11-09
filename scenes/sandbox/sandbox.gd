extends Control
## 科研模式：双方都可以自由摆阵（上面一排是对方，下面一排是我方），然后开战。
## 点卡位选中，下面的选卡区就为它选卡；也可以把卡从选卡区拖到任意卡位，或把场上的卡拖出去（拖放见 sandbox_board）。
## 右列：标题、开始战斗、交换双方、清空全部、紧凑模式。布局按画布大小算；紧凑模式下双方队列换成紧凑卡，选卡区放大。

signal back_to_menu
signal start_battle

const MARGIN := 14.0
const GAP_ROWS := 22.0
const BACK_BOTTOM := 92.0

## 双方阵容：1 是对方（上面一排），2 是我方；每个卡位是 [角色 id, 装备 id] 或 []
var lineups := {1: [], 2: []}
## 选中的卡位 [阵营, 序号]
var selected := [2, 0]

@onready var _board = $board
@onready var _picker: CardPicker = $Picker
var _slots := {1: [], 2: []}
var _enemy_tag := SideTag.new(tr("ui.board.enemy"), true)
var _ally_tag := SideTag.new(tr("ui.board.ally"), false)
var _preview := CardPreview.new()


func _ready() -> void:
	for side in [1, 2]:
		lineups[side] = []
		for i in BoardLayout.SLOTS:
			lineups[side].append([])
			var slot: CardSlot = preload("res://scenes/components/card_slot.tscn").instantiate()
			slot.number = i + 1
			slot.set_meta("side", side)
			slot.set_meta("index", i)
			get_node("slots_%d" % side).add_child(slot)
			_slots[side].append(slot)
	add_child(_enemy_tag)
	add_child(_ally_tag)
	add_child(_preview)
	_board.preview = _preview
	_picker.picked.connect(pick)
	_picker.drag_started.connect(_board.start_drag_new)
	_picker.action_pressed.connect(_on_picker_action)
	_picker.tab_changed.connect(refresh)
	_picker.preview_requested.connect(func(id, rect):
		var data := CardDB.card(id)
		_preview.show_card(id if data.type == "character" else "", "" if data.type == "character" else id, rect))
	_picker.preview_ended.connect(_preview.hide_card)
	%Compact.button_pressed = global_var.compact_mode
	%Compact.toggled.connect(_on_compact_toggled)
	resized.connect(_layout)
	_layout()


func _on_back_button_pressed() -> void:
	emit_signal("back_to_menu")


# ---------- 阵容 ----------

## 设置一个卡位：card_id 为空表示清空
func set_unit(side: int, index: int, card_id: String, equip_id := "") -> void:
	lineups[side][index] = [card_id, equip_id] if card_id else []
	refresh()


func select_slot(side: int, index: int) -> void:
	selected = [side, index]
	refresh()


## 为选中的卡位选一张卡：角色替换角色（装备保留），装备装到角色身上（没有角色时不能装）
func pick(id: String) -> void:
	var unit: Array = lineups[selected[0]][selected[1]]
	if CardDB.card(id).type == "character":
		lineups[selected[0]][selected[1]] = [id, unit[1] if unit else ""]
	elif unit:
		lineups[selected[0]][selected[1]] = [unit[0], id]
	refresh()


## 两个卡位互换（空的就是移过去）
func move_unit(from_side: int, from_index: int, to_side: int, to_index: int) -> void:
	var moving: Array = lineups[from_side][from_index]
	lineups[from_side][from_index] = lineups[to_side][to_index]
	lineups[to_side][to_index] = moving
	refresh()


func swap_sides() -> void:
	var top: Array = lineups[1]
	lineups[1] = lineups[2]
	lineups[2] = top
	refresh()


func clear_all() -> void:
	for side in [1, 2]:
		for i in BoardLayout.SLOTS:
			lineups[side][i] = []
	refresh()


func _on_clear_pressed() -> void:
	if await Dialog.confirm(self, tr("ui.sandbox.clear"), tr("ui.sandbox.clear_confirm")).closed:
		clear_all()


## 选卡区的按钮：角色页是"移除"，装备页是"卸下装备"
func _on_picker_action() -> void:
	var unit: Array = lineups[selected[0]][selected[1]]
	if _picker.tab == "character":
		lineups[selected[0]][selected[1]] = []
	elif unit:
		lineups[selected[0]][selected[1]] = [unit[0], ""]
	refresh()


## 战斗阵容：按卡位从左到右，跳过空的
func battle_lineup(side: int) -> Array:
	return lineups[side].filter(func(u): return not u.is_empty())


func _on_start_battle_pressed() -> void:
	if battle_lineup(1).is_empty() or battle_lineup(2).is_empty():
		Dialog.notice(self, tr("ui.dialog.hint"), tr("ui.sandbox.need_both"))
		return
	global_var.battle_card_list_1 = battle_lineup(1).map(func(u): return u[0])
	global_var.battle_equip_list_1 = battle_lineup(1).map(func(u): return u[1])
	global_var.battle_card_list_2 = battle_lineup(2).map(func(u): return u[0])
	global_var.battle_equip_list_2 = battle_lineup(2).map(func(u): return u[1])
	emit_signal("start_battle")


## 按阵容重摆卡牌，更新选中的卡位和选卡区的提示
func refresh() -> void:
	_board.render(_slots)
	for side in [1, 2]:
		for i in BoardLayout.SLOTS:
			_slots[side][i].selected = selected == [side, i]
	var unit: Array = lineups[selected[0]][selected[1]]
	var side_name := tr("ui.board.enemy" if selected[0] == 1 else "ui.board.ally")
	var slot_name := "[color=#ffd98a][b]%s[/b][/color]" % (tr("ui.sandbox.slot") % [side_name, selected[1] + 1])
	_picker.equipment_enabled = not unit.is_empty()
	if _picker.tab == "character":
		_picker.set_target(tr("ui.sandbox.for_character") % slot_name, tr("ui.sandbox.remove"), not unit.is_empty())
	elif unit.is_empty():
		_picker.set_target(tr("ui.sandbox.no_character") % slot_name, tr("ui.sandbox.unequip"), false)
	else:
		_picker.set_target(tr("ui.sandbox.for_equipment") % slot_name, tr("ui.sandbox.unequip"), unit[1] != "")
	_picker.refresh_cards()


func _on_compact_toggled(on: bool) -> void:
	global_var.compact_mode = on
	_layout()


## 两排卡位和选卡区上下排开，共享高度：卡位的缩放受宽度和高度限制；
## 选卡区的卡填满剩下的高度（最大缩放 1），放得下和队列一样大的完整卡就用完整卡，否则用紧凑卡；
## 卡已经最大还有空余时，选卡区收紧，整体上下居中
func _layout() -> void:
	var compact: bool = global_var.compact_mode
	var row_unit := BoardLayout.card_height(1, compact)
	var picker_head: float = CardPicker.HEAD_HEIGHT
	var fit := (size.y - 2 * MARGIN - 2 * GAP_ROWS - picker_head - 30) / (2 * row_unit + BoardLayout.card_height(1, true))
	var columns := BoardLayout.columns(BoardLayout.TAG_COLUMN, size.x - BoardLayout.RIGHT_COLUMN, fit)
	var card_scale: float = columns.scale
	var row_height := row_unit * card_scale

	var picker_height := size.y - 2 * MARGIN - 2 * (row_height + GAP_ROWS)
	var room := picker_height - picker_head - 22
	var picker_scale := minf(1.0, room / BoardLayout.card_height(1, false))
	var full := picker_scale >= card_scale
	if not full:
		picker_scale = minf(1.0, room / BoardLayout.card_height(1, true))
	var spare := maxf(0, room - BoardLayout.card_height(picker_scale, not full))
	picker_height -= spare
	var top := MARGIN + spare / 2
	var tops := {1: top, 2: top + row_height + GAP_ROWS}
	var picker_top: float = tops[2] + row_height + GAP_ROWS

	for side in [1, 2]:
		for i in BoardLayout.SLOTS:
			var slot: CardSlot = _slots[side][i]
			slot.size = Vector2(columns.width, row_height)
			slot.position = Vector2(columns.center.call(i), tops[side] + row_height / 2)
	_board.lineup_look = [card_scale, compact]
	_board.lineup_band = Vector2(0, picker_top - GAP_ROWS / 2)
	_picker.position = Vector2(30, picker_top)
	_picker.size = Vector2(size.x - 60, picker_height)
	_picker.layout(picker_scale, not full)
	_board.picker_look = [picker_scale, not full]

	var tag_x := (BoardLayout.TAG_COLUMN - SideTag.WIDTH) / 2 + 8
	var enemy_top := maxf(tops[1], BACK_BOTTOM)
	_enemy_tag.position = Vector2(tag_x, enemy_top + (tops[1] + row_height - enemy_top - _enemy_tag.size.y) / 2)
	_ally_tag.position = Vector2(tag_x, tops[2] + (row_height - _ally_tag.size.y) / 2)
	var column: Control = $RightColumn
	column.size = column.get_combined_minimum_size()
	column.position = Vector2((columns.right + size.x) / 2, tops[1] + row_height + GAP_ROWS / 2) - column.size / 2
	refresh()
