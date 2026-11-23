class_name LineupCodePanel
extends Control
## 阵容码面板（规范见 docs/design/lineup-code.md）：顶部切换对方、我方，一个文本框加"复制、粘贴、导入"。
## 外框同对话框（Dialog.frame），右上角的叉或点框外关闭。打开时文本框里是这一方现在的阵容，可以直接复制，也可以改了或贴上别的再导入。
## importable 为假时只能导出：文本框只读，只有"复制"。
## 导入：一个角色都认不出就不导入；这一方已有角色时先确认；导入后文本框换成标准写法，有问题就列在文本框下面，没有就关掉。
## 用法：LineupCodePanel.open(self, 双方阵容, 打开哪一方, 能不能导入).imported.connect(...)

## 导入：side 这一方换成 slots（7 个卡位），由调用方放上去
signal imported(side: int, slots: Array)

const WIDTH := 1000.0
const COPIED_TIME := 1.5
const CLOSE_ICON := preload("res://assets/ui/icons/close.png")
## 右上角的叉：边长、离框的上边和右边
const CLOSE_SIZE := 54.0
const CLOSE_INSET := 22.0

## 现在是哪一方：1 对方，2 我方
var side := 2
var importable := true
## 双方阵容 {1: [...], 2: [...]}，只读（调用方的字典，导入后由调用方更新）
var _lineups: Dictionary
var _sides := {}
var _text: TextEdit
var _notes: Label
var _copy: UiButton
var _close: Button

## 文本框里的文字
var code: String:
	get:
		return _text.text
	set(value):
		_text.text = value


static func open(parent: Node, lineups: Dictionary, side_: int, importable_: bool) -> LineupCodePanel:
	var panel := LineupCodePanel.new()
	panel._lineups = lineups
	panel.importable = importable_
	panel._build()
	parent.add_child(panel)
	panel.set_side(side_)
	return panel


func _build() -> void:
	var column := Dialog.frame(self, tr("ui.lineup_code.title"), WIDTH)
	_add_close_button(column.get_parent().get_parent())  # 框：column 在框的边距容器里
	var sides := HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 16)
	var group := ButtonGroup.new()
	for s in [1, 2]:
		var button := SideButton.new(tr("ui.board.enemy" if s == 1 else "ui.board.ally"), s == 1)
		button.button_group = group
		button.pressed.connect(func():
			if side != s:  # 点已选的一方不重置文本框
				set_side(s))
		sides.add_child(button)
		_sides[s] = button
	column.add_child(sides)
	column.add_child(Dialog.gap(20))

	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 176)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.editable = importable
	_text.placeholder_text = tr("ui.lineup_code.placeholder") if importable else ""
	column.add_child(_text)
	_notes = Label.new()
	_notes.add_theme_font_size_override("font_size", 24)
	_notes.add_theme_color_override("font_color", Dialog.GOLD)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacing := StyleBoxEmpty.new()
	spacing.content_margin_top = 12  # 和文本框隔开；没有说明时整个隐藏
	_notes.add_theme_stylebox_override("normal", spacing)
	column.add_child(_notes)
	column.add_child(Dialog.gap(28))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	column.add_child(buttons)
	_copy = _button("ui.lineup_code.copy", copy_code)
	buttons.add_child(_copy)
	if importable:
		buttons.add_child(_button("ui.lineup_code.paste", paste_code))
		var import_button := _button("ui.lineup_code.import", import_code)
		import_button.theme_type_variation = &"PrimaryButton"
		buttons.add_child(import_button)


## 切换一方：文本框换成这一方现在的阵容
func set_side(s: int) -> void:
	side = s
	_sides[s].button_pressed = true
	code = LineupCode.write(_lineups[s])
	_show_notes([])


func copy_code() -> void:
	DisplayServer.clipboard_set(code)
	_copy.text = "ui.lineup_code.copied"
	create_tween().tween_callback(func(): _copy.text = "ui.lineup_code.copy").set_delay(COPIED_TIME)


## 剪贴板的内容放进文本框；读不到（有的手机和网页版）时提示用系统的粘贴
func paste_code() -> void:
	var text := DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		_show_notes([tr("ui.lineup_code.clipboard_empty")])
		return
	code = text
	_show_notes([])


func import_code() -> void:
	var result := LineupCode.read(code)
	var notes: Array = result.problems.map(_problem_text)
	if result.slots.all(func(u): return u.is_empty()):
		_show_notes([tr("ui.lineup_code.nothing")] + notes)
		return
	if _lineups[side].any(func(u): return not u.is_empty()):
		var side_name := tr("ui.board.enemy" if side == 1 else "ui.board.ally")
		if not await Dialog.confirm(self, tr("ui.lineup_code.import"), tr("ui.lineup_code.replace") % side_name).closed:
			return
	imported.emit(side, result.slots)
	code = LineupCode.write(result.slots)
	if notes.is_empty():
		close()
	else:
		_show_notes(notes)


func close() -> void:
	queue_free()


## 点框外关闭
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## 右上角的叉：盖在框上的一层（不挡点击），叉贴右上角
func _add_close_button(box: Control) -> void:
	var corner := Control.new()
	corner.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(corner)
	var button := Button.new()
	button.theme_type_variation = &"IconButton"
	button.icon = CLOSE_ICON
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = FOCUS_NONE
	button.set_anchors_preset(PRESET_TOP_RIGHT)
	button.offset_left = -CLOSE_INSET - CLOSE_SIZE
	button.offset_right = -CLOSE_INSET
	button.offset_top = CLOSE_INSET
	button.offset_bottom = CLOSE_INSET + CLOSE_SIZE
	button.pressed.connect(close)
	corner.add_child(button)
	_close = button


func _problem_text(problem: Dictionary) -> String:
	match problem.kind:
		"too_many":
			return tr("ui.lineup_code.too_many") % [LineupCode.SLOTS, problem.count]
		"no_character":
			return tr("ui.lineup_code.no_character") % problem.slot
	return tr("ui.lineup_code." + problem.kind) % [problem.slot, problem.name]


func _show_notes(lines: Array) -> void:
	_notes.text = "\n".join(lines)
	_notes.visible = not lines.is_empty()


func _button(key: String, action: Callable) -> UiButton:
	var button := UiButton.new()
	button.text = key
	button.custom_minimum_size = Vector2(200, 74)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(action)
	return button


## 选一方的按钮：单选块，文字前面一面小旗（对方红、我方蓝，和阵营旗帜同色）
class SideButton extends Button:
	const FONT := preload("res://assets/fonts/sans_bold.tres")
	const FONT_SIZE := 26
	const FLAG := Vector2(22, 30)

	var label := ""
	var enemy := true

	func _init(label_: String, enemy_: bool) -> void:
		label = label_
		enemy = enemy_
		theme_type_variation = &"FilterCheck"
		toggle_mode = true
		focus_mode = FOCUS_NONE
		custom_minimum_size = Vector2(22 + FLAG.x + 12 + FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 26, 60)
		toggled.connect(func(_on): queue_redraw())

	func _draw() -> void:
		var colors: Array = SideTag.COLORS[enemy]
		var top := (size.y - FLAG.y) / 2
		var x := 22.0
		var shape := PackedVector2Array([Vector2(x, top), Vector2(x + FLAG.x, top), Vector2(x + FLAG.x, top + FLAG.y),
			Vector2(x + FLAG.x / 2, top + FLAG.y - 7), Vector2(x, top + FLAG.y)])
		draw_polygon(shape, PackedColorArray([colors[0], colors[0], colors[1], colors[1], colors[1]]))
		draw_polyline(shape + PackedVector2Array([shape[0]]), colors[2], 1.5, true)
		var color := Color.WHITE if button_pressed else Color(1, 1, 1, 0.7)
		var baseline := size.y / 2 + (FONT.get_ascent(FONT_SIZE) - FONT.get_descent(FONT_SIZE)) / 2
		draw_string(FONT, Vector2(x + FLAG.x + 12, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
