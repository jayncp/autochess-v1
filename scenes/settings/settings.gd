extends Control
## 设置：默认速度、默认紧凑模式、存档位置、清除闯关记录。改了立刻生效、立刻保存，没有"保存"按钮。
## 默认值在进入构筑阶段、科研模式和开战时读（见 GameSettings）。
## 背景用主菜单的，压暗；内容是居中的一列：分组标题，下面一个面板，面板里一项一行（名称和说明在左，控件在右）。

signal back_to_menu

const WIDTH := 1160.0
const TOP := 110.0
const GOLD := Color("ffd98a")
const SERIF := preload("res://assets/fonts/serif.tres")
const BOLD := preload("res://assets/fonts/sans_bold.tres")

## PC 上可以复制路径、打开存档文件夹；手机上存档在应用内部，改成一行说明
var desktop := not OS.has_feature("mobile")

var _speed_buttons := {}  # 速度 -> 按钮
var _compact: CheckButton
var _copy: UiButton
var _clear: UiButton
var _cleared_hint: Label

@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	_build()
	resized.connect(_layout)
	_content.minimum_size_changed.connect(_layout)
	_layout()


func _on_back_button_pressed() -> void:
	back_to_menu.emit()


func set_speed(speed: float) -> void:
	GameSettings.speed = speed
	GameSettings.save()
	_speed_buttons[speed].button_pressed = true


func set_compact(on: bool) -> void:
	GameSettings.compact = on
	GameSettings.save()
	_compact.set_pressed_no_signal(on)


func copy_path() -> void:
	DisplayServer.clipboard_set(save_dir())
	_copy.text = "ui.settings.copied"
	create_tween().tween_callback(func(): _copy.text = "ui.settings.copy").set_delay(1.5)


func open_folder() -> void:
	OS.shell_show_in_file_manager(OS.get_user_data_dir())


## "清除闯关记录"：确认后清除
func clear_records() -> void:
	var dialog := Dialog.confirm(self, tr("ui.settings.clear"), tr("ui.settings.clear_text"))
	if await dialog.closed:
		SaveData.clear_levels()
		_refresh_records()


## 存档目录，按平台的写法（Windows 用反斜杠）
static func save_dir() -> String:
	var dir := OS.get_user_data_dir()
	return dir.replace("/", "\\") if OS.get_name() == "Windows" else dir


func _layout() -> void:
	var width := minf(WIDTH, size.x - 160)
	var height := _content.get_combined_minimum_size().y
	_content.size = Vector2(width, height)
	_content.position = Vector2((size.x - width) / 2, maxf(TOP, TOP + (size.y - TOP - height - 40) / 2))


# ---------- 内容 ----------

func _build() -> void:
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for speed in GameSettings.SPEEDS:
		var button := Button.new()
		button.theme_type_variation = &"FilterCheck"
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = FOCUS_NONE
		button.text = tr("ui.battle.speed") % str(int(speed))
		button.custom_minimum_size = Vector2(104, 60)
		button.add_theme_font_override("font", BOLD)
		button.add_theme_font_size_override("font_size", 26)
		button.button_pressed = speed == GameSettings.speed
		button.pressed.connect(set_speed.bind(speed))
		speeds.add_child(button)
		_speed_buttons[speed] = button
	_group("ui.settings.battle", [_row("ui.settings.speed", _hint("ui.settings.speed_hint"), speeds)])

	_compact = CheckButton.new()
	_compact.focus_mode = FOCUS_NONE
	_compact.button_pressed = GameSettings.compact
	_compact.toggled.connect(set_compact)
	_group("ui.settings.board", [_row("ui.board.compact", _hint("ui.settings.compact_hint"), _compact)])

	# 存档位置：路径框可以选中复制；PC 上还有"复制路径""打开文件夹"
	var location := VBoxContainer.new()
	location.add_theme_constant_override("separation", 16)
	location.add_child(_row("ui.settings.location", _hint("ui.settings.location_hint" if desktop else "ui.settings.mobile_note"), null))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 26)
	var path := LineEdit.new()
	path.text = save_dir()
	path.editable = false
	path.size_flags_horizontal = SIZE_EXPAND_FILL
	path.custom_minimum_size.y = 58
	path.add_theme_font_size_override("font_size", 22)
	path.add_theme_color_override("font_uneditable_color", Color(1, 1, 1, 0.85))
	line.add_child(path)
	if desktop:
		_copy = _button("ui.settings.copy", copy_path)
		line.add_child(_copy)
		line.add_child(_button("ui.settings.open", open_folder))
	location.add_child(line)

	_clear = _button("ui.settings.clear", clear_records)
	_cleared_hint = _hint("")
	_group("ui.settings.save", [location, _row("ui.settings.records", _cleared_hint, _clear)])
	_refresh_records()


## 闯关记录：已通关几关；没有记录时（或存档只读时）不能清除
func _refresh_records() -> void:
	var ids := LevelDB.all().keys()
	var cleared := ids.filter(func(id): return SaveData.is_cleared(id)).size()
	_cleared_hint.text = tr("ui.settings.cleared_count") % [cleared, ids.size()]
	_clear.disabled = cleared == 0 or SaveData.read_only


## 一组：分组标题（后面一条渐隐的金线），下面一个面板，面板里的行之间用细线隔开
func _group(title_key: String, rows: Array) -> void:
	if _content.get_child_count() > 0:
		_content.add_child(_gap(22))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var title := Label.new()
	title.theme_type_variation = &"GroupLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.text = title_key
	head.add_child(title)
	var rule := TextureRect.new()
	rule.texture = _rule_texture()
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.custom_minimum_size.y = 2
	rule.size_flags_horizontal = SIZE_EXPAND_FILL
	rule.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(rule)
	_content.add_child(head)
	_content.add_child(_gap(10))

	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	margin.add_child(column)
	for i in rows.size():
		if i > 0:
			var divider := ColorRect.new()
			divider.color = Color(GOLD, 0.16)
			divider.custom_minimum_size.y = 1
			column.add_child(divider)
		column.add_child(rows[i])
	_content.add_child(panel)


## 一行：左边名称和说明，右边控件（可以没有）
func _row(title_key: String, hint: Label, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = title_key
	title.add_theme_font_override("font", SERIF)
	title.add_theme_font_size_override("font_size", 30)
	text.add_child(title)
	text.add_child(hint)
	row.add_child(text)
	if control:
		control.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(control)
	return row


func _hint(key: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HintLabel"
	label.text = key
	return label


func _button(key: String, action: Callable) -> UiButton:
	var button := UiButton.new()
	button.theme_type_variation = &"SmallButton"
	button.text = key
	button.custom_minimum_size.y = 58
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	return button


func _gap(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap


func _rule_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(GOLD, 0.6), Color(GOLD, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 2
	texture.fill_to = Vector2(1, 0)
	return texture
