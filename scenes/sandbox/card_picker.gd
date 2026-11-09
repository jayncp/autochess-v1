class_name CardPicker
extends PanelContainer
## 科研模式的选卡区：标签页分角色、装备，可以按星级、种族（只有角色）筛选，也可以搜索；下面一排卡横向滚动。
## 点卡发出 picked；按住往上拖发出 drag_started（科研模式在指针处生成一张卡接着拖）；
## 右上角是"为 我方 第 3 位 选择角色"和"移除"/"卸下装备"。PC 悬停、手机长按发出 preview_requested。

signal picked(id: String)
signal drag_started(id: String)
signal action_pressed
signal tab_changed
signal preview_requested(id: String, rect: Rect2)
signal preview_ended

const HEAD_HEIGHT := 76.0
const GAP := 18.0
const DRAG_DISTANCE := 16.0
const LONG_PRESS := 0.45

var tab := "character"
var stars := []
var races := []
var search := ""
## 选卡区里卡牌的样子
var card_scale := 0.6
var compact := true
## 装备能不能点（选中的卡位还没有角色时不能装备）
var equipment_enabled := true

var _cells := {}  # id -> 格子
var _tabs := {}
var _stars := {}  # 星级 -> 勾选块；0 是"全部星级"
var _races := {}
var _target := RichTextLabel.new()
var _action := UiButton.new()
var _row := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _fade := TextureRect.new()
var _press := {}  # 按住的卡：id、位置、时间、是否已经拖出


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = HEAD_HEIGHT - 16
	head.add_theme_constant_override("separation", 14)
	column.add_child(head)

	var group := ButtonGroup.new()
	for type in ["character", "equipment"]:
		var button := TabButton.new(tr("ui.book." + type), str(CardDB.ids(type).size()))
		button.button_group = group
		button.button_pressed = type == tab
		button.pressed.connect(set_tab.bind(type))
		head.add_child(button)
		_tabs[type] = button
	var all := FilterOption.new({"text": tr("ui.sandbox.all_stars")}, 44)
	all.pressed.connect(_set_stars.bind([]))
	head.add_child(all)
	_stars[0] = all
	var star_values := {}
	for data in CardDB.all().values():
		star_values[data.star] = true
	for star in range(1, 6):
		if star_values.has(star):
			var option := FilterOption.new({"stars": star}, 44)
			option.pressed.connect(_toggle_star.bind(star))
			head.add_child(option)
			_stars[star] = option
	for race in CardDB.RACES:
		var option := FilterOption.new({"icon": race, "tint": CardFace.RACE_COLORS[race]}, 44)
		option.pressed.connect(_toggle_race.bind(race))
		head.add_child(option)
		_races[race] = option
	var search_box := LineEdit.new()
	search_box.theme_type_variation = &"SearchEdit"
	search_box.placeholder_text = "ui.sandbox.search_hint"
	search_box.custom_minimum_size = Vector2(260, 48)
	search_box.size_flags_vertical = SIZE_SHRINK_CENTER
	search_box.clear_button_enabled = true
	search_box.text_changed.connect(_on_search_changed)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/ui/icons/search.png")
	icon.modulate = Color(1, 0.851, 0.541, 0.7)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = Vector2(18, 11)
	icon.size = Vector2(26, 26)
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	search_box.add_child(icon)
	head.add_child(search_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_target.bbcode_enabled = true
	_target.fit_content = true
	_target.autowrap_mode = TextServer.AUTOWRAP_OFF
	_target.scroll_active = false
	_target.size_flags_vertical = SIZE_SHRINK_CENTER
	_target.mouse_filter = MOUSE_FILTER_IGNORE
	_target.add_theme_font_size_override("normal_font_size", 22)
	_target.add_theme_font_size_override("bold_font_size", 22)
	_target.add_theme_font_override("bold_font", preload("res://assets/fonts/sans_bold.tres"))
	_target.add_theme_color_override("default_color", Color(1, 0.94, 0.84, 0.85))
	head.add_child(_target)
	_action.theme_type_variation = &"SmallButton"
	_action.custom_minimum_size.y = 54
	_action.size_flags_vertical = SIZE_SHRINK_CENTER
	_action.pressed.connect(func(): action_pressed.emit())
	head.add_child(_action)

	# 卡牌一排：放不下时左右拖动，右边渐隐
	var strip := Control.new()
	strip.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(strip)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	strip.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 60)
	_scroll.add_child(margin)
	_row.add_theme_constant_override("separation", GAP)
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(_row)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.03, 0.035, 0.094, 0), Color(0.03, 0.035, 0.094, 0.95)])
	_fade.texture = GradientTexture2D.new()
	_fade.texture.gradient = gradient
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.mouse_filter = MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(PRESET_RIGHT_WIDE)
	_fade.offset_left = -70
	_fade.offset_bottom = -12
	strip.add_child(_fade)
	var bar := _scroll.get_h_scroll_bar()
	bar.changed.connect(func(): _fade.visible = bar.max_value > bar.page)

	for id in CardDB.all():
		var cell := Control.new()
		cell.size_flags_vertical = SIZE_SHRINK_CENTER
		cell.mouse_filter = MOUSE_FILTER_PASS
		var face := CardFace.new()
		if CardDB.card(id).type == "character":
			face.show_cards(id, "")
		else:
			face.show_cards("", id)
		cell.add_child(face)
		cell.gui_input.connect(_on_cell_input.bind(id, cell))
		cell.mouse_entered.connect(func():
			if CardPreview.hover:
				preview_requested.emit(id, cell.get_global_rect()))
		cell.mouse_exited.connect(func(): preview_ended.emit())
		_row.add_child(cell)
		_cells[id] = cell
	_sync_filters()
	layout(card_scale, compact)


func set_tab(type: String) -> void:
	tab = type
	_tabs[type].button_pressed = true
	_sync_filters()
	tab_changed.emit()


## 右上角：选卡的对象（BBCode）、按钮文字和能不能按
func set_target(text: String, action: String, action_enabled: bool) -> void:
	_target.text = text
	_action.text = action
	_action.disabled = not action_enabled


## 选卡区里卡牌的缩放和是否紧凑卡
func layout(scale_: float, compact_: bool) -> void:
	card_scale = scale_
	compact = compact_
	for cell in _cells.values():
		var face: CardFace = cell.get_child(0)
		face.display_scale = card_scale
		face.compact = compact
		cell.custom_minimum_size = face.get_size()
		face.position = face.get_size() / 2


func _on_search_changed(text: String) -> void:
	search = text.strip_edges()
	refresh_cards()


func _toggle_star(star: int) -> void:
	if star in stars:
		stars.erase(star)
	else:
		stars.append(star)
	_sync_filters()


func _set_stars(values: Array) -> void:
	stars = values
	_sync_filters()


func _toggle_race(race: String) -> void:
	if race in races:
		races.erase(race)
	else:
		races.append(race)
	_sync_filters()


## 勾选状态跟着筛选条件走，然后刷新卡牌
func _sync_filters() -> void:
	_stars[0].set_pressed_no_signal(stars.is_empty())
	for star in _stars:
		if star > 0:
			_stars[star].set_pressed_no_signal(star in stars)
	for race in _races:
		_races[race].set_pressed_no_signal(race in races)
		_races[race].visible = tab == "character"
	for option in _stars.values() + _races.values():
		option.queue_redraw()
	refresh_cards()


func refresh_cards() -> void:
	for id in _cells:
		var data := CardDB.card(id)
		var shown: bool = data.type == tab \
			and (stars.is_empty() or data.star in stars) \
			and (races.is_empty() or races.any(func(r): return r in data.get("races", []))) \
			and load_card.matches_search(data, search)
		_cells[id].visible = shown
		_cells[id].modulate.a = 0.4 if data.type == "equipment" and not equipment_enabled else 1.0
	_scroll.scroll_horizontal = 0


## 点卡、按住往上拖、长按查看
func _on_cell_input(event: InputEvent, id: String, cell: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = {"id": id, "position": event.global_position, "time": Time.get_ticks_msec(), "dragged": false, "cell": cell}
			set_process(true)
		elif _press.get("id") == id:
			var moved: bool = event.global_position.distance_to(_press.position) > DRAG_DISTANCE
			if not _press.dragged and not moved and Time.get_ticks_msec() - _press.time < LONG_PRESS * 1000:
				if CardDB.card(id).type == "character" or equipment_enabled:
					picked.emit(id)
			if not CardPreview.hover:
				preview_ended.emit()
			_press = {}
	elif event is InputEventMouseMotion and _press.get("id") == id:
		# 拿起来以后不再滚动选卡区（移动事件不传给 ScrollContainer；松开还要传，它才会结束拖动）
		if _press.dragged:
			accept_event()
			return
		var delta: Vector2 = event.global_position - _press.position
		# 往上拖（和水平方向夹角大于约 22°）才算拿卡；横着拖是在滚动
		if delta.y < -DRAG_DISTANCE and -delta.y > absf(delta.x) * 0.4:
			_press.dragged = true
			accept_event()
			preview_ended.emit()
			drag_started.emit(id)


func _process(_delta: float) -> void:
	if _press.is_empty():
		set_process(false)
		return
	# 手机长按：按住不动显示放大的卡
	if not _press.dragged and Time.get_ticks_msec() - _press.time >= LONG_PRESS * 1000:
		preview_requested.emit(_press.id, _press.cell.get_global_rect())
		set_process(false)
