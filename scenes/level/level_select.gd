extends Control
## 关卡选择：标签页分教学关、解谜关（教学关还没有）；一行三个关卡，点一个展开详情（同时只展开一个），
## 详情横跨整行、插在这一行下面，内容是敌方阵容（放不下时左右拖动）和"进入关卡"。
## 布局按画布大小算（列表放在背景图的告示板上），画布宽度随屏幕变化时也适用。

signal back_to_menu
signal select_level(level_id)

## 背景图的尺寸和告示板的位置（左右各留 BOARD_SIDE，上边在 BOARD_TOP）；背景按宽度铺满、顶端对齐
const BACKGROUND_SIZE := Vector2(1664, 936)
const BOARD_SIDE := 150.0
const BOARD_TOP := 232.0
const COLUMNS := 3
const MAX_LIST_WIDTH := 1700.0
const HINT := Color(1, 0.94, 0.84, 0.75)

## 已通关的关卡 id（进度存档以后再做，现在一直是空的）
var cleared := {}
var _open := ""  # 展开详情的关卡

@onready var _rows: VBoxContainer = %Rows
@onready var _background: TextureRect = $Background


func _ready() -> void:
	_build_tabs()
	_rebuild()
	resized.connect(_layout)
	_layout()


func _on_back_button_pressed() -> void:
	back_to_menu.emit()


## 展开或收起一个关卡的详情
func toggle_level(level_id: String) -> void:
	_open = "" if _open == level_id else level_id
	_rebuild()


func enter_level(level_id: String) -> void:
	select_level.emit(level_id)


func _layout() -> void:
	var background_scale := maxf(size.x / BACKGROUND_SIZE.x, size.y / BACKGROUND_SIZE.y)
	_background.size = BACKGROUND_SIZE * background_scale
	_background.position = Vector2((size.x - _background.size.x) / 2, 0)
	var board_left := BOARD_SIDE * background_scale + _background.position.x
	var board_top := BOARD_TOP * background_scale
	var width := minf(MAX_LIST_WIDTH, size.x - 2 * board_left - 80)
	$Tabs.size = $Tabs.get_combined_minimum_size()
	$Tabs.position = Vector2((size.x - $Tabs.size.x) / 2, board_top - 4)
	# 列表右边留出对号伸出的部分和滚动条
	$List.position = Vector2((size.x - width) / 2, board_top + 62)
	$List.size = Vector2(width + 36, size.y - $List.position.y)
	$Fade.position = Vector2($List.position.x, size.y - 120)
	$Fade.size = Vector2(width, 120)


func _build_tabs() -> void:
	var tutorial := Tab.new(tr("ui.level_select.tutorial"), tr("ui.level_select.coming"))
	tutorial.disabled = true
	$Tabs.add_child(tutorial)
	var puzzle := Tab.new(tr("ui.level_select.puzzle"), str(LevelDB.all().size()))
	puzzle.button_pressed = true
	$Tabs.add_child(puzzle)


## 重新排列表：每行三个，展开的关卡所在的行下面插入详情
func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var ids := LevelDB.all().keys()
	for start in range(0, ids.size(), COLUMNS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		var open_tile: LevelTile = null
		for i in range(start, start + COLUMNS):
			if i >= ids.size():
				var filler := Control.new()
				filler.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(filler)
				continue
			var tile := LevelTile.new()
			tile.number = i + 1
			tile.title = tr("level." + ids[i])
			tile.open = ids[i] == _open
			tile.cleared = cleared.has(ids[i])
			tile.pressed.connect(toggle_level.bind(ids[i]))
			row.add_child(tile)
			if tile.open:
				open_tile = tile
		_rows.add_child(row)
		if open_tile:
			_rows.add_child(_detail(_open, open_tile))


## 详情：敌方阵容和"进入关卡"，顶上一个小箭头指向展开的关卡
func _detail(level_id: String, tile: LevelTile) -> Control:
	var level := LevelDB.level(level_id)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DetailPanel"
	panel.draw.connect(_draw_pointer.bind(panel, tile))
	tile.resized.connect(panel.queue_redraw)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, {"left": 34, "top": 10, "right": 30, "bottom": 22}[side])
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	margin.add_child(row)

	var label := VBoxContainer.new()
	label.alignment = BoxContainer.ALIGNMENT_CENTER
	label.add_theme_constant_override("separation", 8)
	label.add_child(_text(tr("ui.level_select.enemy"), 22, HINT))
	label.add_child(_count(level.enemy.size()))
	row.add_child(label)

	# 阵容：放不下时可以左右拖动，右边渐隐
	var strip := Control.new()
	strip.size_flags_horizontal = SIZE_EXPAND_FILL
	strip.custom_minimum_size.y = 200
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	strip.add_child(scroll)
	var units_margin := MarginContainer.new()
	units_margin.add_theme_constant_override("margin_left", 26)
	units_margin.add_theme_constant_override("margin_top", 20)
	units_margin.add_theme_constant_override("margin_right", 40)
	units_margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(units_margin)
	var units := HBoxContainer.new()
	units.add_theme_constant_override("separation", 40)
	units_margin.add_child(units)
	for i in level.enemy.size():
		units.add_child(UnitPortrait.new(level.enemy[i][0], level.enemy[i][1], i + 1))
	var fade := TextureRect.new()
	fade.texture = _fade_texture()
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
	fade.offset_left = -120
	strip.add_child(fade)
	var bar := scroll.get_h_scroll_bar()
	bar.changed.connect(func(): fade.visible = bar.max_value > bar.page)
	row.add_child(strip)

	var enter := UiButton.new()
	enter.theme_type_variation = &"PrimaryButton"
	enter.text = "ui.level_select.enter"
	enter.custom_minimum_size = Vector2(250, 80)
	enter.add_theme_font_size_override("font_size", 30)
	enter.size_flags_vertical = SIZE_SHRINK_CENTER
	enter.pressed.connect(enter_level.bind(level_id))
	row.add_child(enter)
	return panel


## 详情顶上的小箭头，指向展开的关卡
func _draw_pointer(panel: PanelContainer, tile: LevelTile) -> void:
	var x := tile.position.x + tile.size.x / 2
	var r := 15.0
	var fill := (panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	panel.draw_colored_polygon(PackedVector2Array([Vector2(x - r, 1), Vector2(x, 1 - r), Vector2(x + r, 1)]), fill)
	panel.draw_polyline(PackedVector2Array([Vector2(x - r, 0), Vector2(x, -r), Vector2(x + r, 0)]), LevelTile.GOLD, 2, true)


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## "共 4 人"：数字大一号
func _count(n: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var parts := tr("ui.level_select.enemy_count").split("%s")
	box.add_child(_text(parts[0].strip_edges(), 22, HINT))
	var number := _text(str(n), 26, Color.WHITE)
	number.add_theme_font_override("font", preload("res://assets/fonts/sans_bold.tres"))
	box.add_child(number)
	box.add_child(_text(parts[1].strip_edges(), 22, HINT))
	return box


func _fade_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.03, 0.04, 0.1, 0), Color(0.03, 0.04, 0.1, 0.97)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	return texture


## 标签页：标题加一行小字（数量或"即将开放"），选中时金色下划线
class Tab extends Button:
	const TITLE_FONT := preload("res://assets/fonts/serif_title.tres")
	const NOTE_FONT := preload("res://assets/fonts/sans_bold.tres")
	const GOLD := Color("ffd98a")

	var title := ""
	var note := ""

	func _init(title_: String, note_: String) -> void:
		title = title_
		note = note_
		theme_type_variation = &"PlainButton"
		toggle_mode = true
		var width := TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 8 + NOTE_FONT.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		custom_minimum_size = Vector2(width + 52, 56)

	func _draw() -> void:
		var color := Color("fff3d0") if button_pressed else Color(Color("f3e6c4"), 0.35 if disabled else 0.6)
		var middle := size.y / 2
		var x := 26.0
		draw_string(TITLE_FONT, Vector2(x, middle + (TITLE_FONT.get_ascent(24) - TITLE_FONT.get_descent(24)) / 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)
		x += TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 8
		draw_string(NOTE_FONT, Vector2(x, middle + (NOTE_FONT.get_ascent(18) - NOTE_FONT.get_descent(18)) / 2), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(color, color.a * 0.7))
		if button_pressed:
			draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), GOLD, 2)
