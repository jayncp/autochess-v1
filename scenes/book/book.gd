extends Control
## 图鉴：左侧筛选栏，右侧卡牌网格（上下滚动），点卡放大并列出词条说明（CardZoom）。
## 筛选：组内满足任一、组间同时满足，没勾的组不限制；类型默认两种都勾上。
## 搜索匹配卡名、种族、时机、技能和效果文字。布局按画布宽度算，宽屏时侧栏加宽、网格多一列。

signal back_to_menu

const WIDE := 2200.0
const GAP := 26.0
const HEAD := 68.0
const SORTS := ["no", "star", "strength"]
const TYPES := ["character", "equipment"]
const STARS := [1, 2, 3, 4]

## 各组勾选的值：types、stars、races、timings、base（基础技能）、special（特殊技能，只有词条）
var filters := {}
var search := ""
var sort := "no"
## 当前显示的卡，按排序
var shown: Array = []

var _cells := {}  # id -> 网格里的格子
var _options := {}  # 组 -> {值: 勾选块}
var _press := Vector2.INF  # 点卡：按下的位置，松开时没怎么移动才算点击
var _special_menu: PopupPanel

@onready var _grid: GridContainer = %Grid


func _ready() -> void:
	_build_filters()
	_build_cards()
	for key in SORTS:
		%Sort.add_item("ui.book.sort_" + key)
	%Sort.item_selected.connect(func(i): set_sort(SORTS[i]))
	%Search.text_changed.connect(set_search)
	$Head/Reset.pressed.connect(reset_filters)
	var count := tr("ui.book.count").split("%s")
	%CountPrefix.text = count[0].strip_edges()
	%CountSuffix.text = count[1].strip_edges()
	reset_filters()
	resized.connect(_layout)
	_layout()


func _on_back_button_pressed() -> void:
	back_to_menu.emit()


func toggle_filter(group: String, value) -> void:
	var values: Array = filters[group]
	if value in values:
		values.erase(value)
	else:
		values.append(value)
	_sync_options()
	_refresh()


func set_search(text: String) -> void:
	search = text.strip_edges()
	if %Search.text != text:
		%Search.text = text
	_refresh()


func set_sort(key: String) -> void:
	sort = key
	%Sort.select(SORTS.find(key))
	_refresh()


func reset_filters() -> void:
	filters = {"types": TYPES.duplicate(), "stars": [], "races": [], "timings": [], "base": [], "special": []}
	search = ""
	%Search.text = ""
	set_sort("no")
	_sync_options()


func open_zoom(id: String) -> void:
	add_child(CardZoom.new(id))


# ---------- 筛选 ----------

func _build_filters() -> void:
	_add_group("ui.book.type", 3, "types", TYPES.map(func(t): return [t, {"text": tr("ui.book." + t)}]))
	_add_group("ui.book.star", 4, "stars", STARS.map(func(n): return [n, {"stars": n}]))
	_add_group("ui.book.race", 3, "races", CardDB.RACES.map(func(r): return [r, {"text": tr("race." + r), "icon": r, "tint": CardFace.RACE_COLORS[r]}]))
	_add_group("ui.book.timing", 3, "timings", CardDB.TIMINGS.map(func(t): return [t, {"text": tr("timing." + t), "icon": t, "tint": CardFace.TIMING_COLORS[t]}]))
	var used := _used_skills()
	var base := CardDB.BASE_SKILLS.filter(func(s): return s in used)
	_add_group("ui.book.base_skill", 4, "base", base.map(func(s): return [s, {"chip": [tr("keyword." + s), "", CardFace.CHIP_COLORS[s], false]}]))

	# 特殊技能：多选下拉，只列词条（描述型的大多是角色专属，靠搜索找）；列表弹在按钮上方，点外面关闭
	var title := HBoxContainer.new()
	title.add_child(_group_title("ui.book.special_skill"))
	var multi := Label.new()
	multi.theme_type_variation = &"HintLabel"
	multi.text = "ui.book.multi"
	multi.size_flags_horizontal = SIZE_EXPAND_FILL
	multi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	multi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_child(multi)
	%Filters.add_child(title)
	var select := Button.new()
	select.name = "Special"
	select.theme_type_variation = &"SelectButton"
	select.custom_minimum_size.y = 54
	select.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	select.pressed.connect(_open_special_menu)
	%Filters.add_child(select)
	select.icon = select.get_theme_icon("arrow", "OptionButton")
	_special_menu = PopupPanel.new()
	_special_menu.wrap_controls = true
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	_special_menu.add_child(list)
	_options["special"] = {}
	for skill in CardDB.SPECIAL_SKILLS.filter(func(s): return s in used and s not in CardDB.DESCRIPTIVE_SPECIALS):
		var check := Option.new({"text": tr("keyword." + skill)})
		check.pressed.connect(toggle_filter.bind("special", skill))
		list.add_child(check)
		_options["special"][skill] = check
	add_child(_special_menu)


func _open_special_menu() -> void:
	var select: Control = %Filters.get_node("Special")
	var height := _special_menu.get_contents_minimum_size().y
	_special_menu.popup(Rect2i(Vector2i(select.global_position - Vector2(0, height + 8)), Vector2i(int(select.size.x), int(height))))


## 一组勾选块：标题加网格；options 是 [值, 外观]，外观见 Option
func _add_group(title_key: String, columns: int, group: String, options: Array) -> void:
	%Filters.add_child(_group_title(title_key))
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_options[group] = {}
	for option in options:
		var check := Option.new(option[1])
		check.size_flags_horizontal = SIZE_EXPAND_FILL
		check.pressed.connect(toggle_filter.bind(group, option[0]))
		grid.add_child(check)
		_options[group][option[0]] = check
	%Filters.add_child(grid)


func _group_title(key: String) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 9)
	var label := Label.new()
	label.theme_type_variation = &"GroupLabel"
	label.text = key
	margin.add_child(label)
	return margin


## 数据里出现过的技能（没有卡用到的不列）
func _used_skills() -> Array:
	var used := {}
	for data in CardDB.all().values():
		for term in CardZoom.terms(data):
			used[term[1]] = true
		if data.get("special_skills") is Dictionary:
			for skill in data.special_skills:
				used[skill] = true
	return used.keys()


## 勾选块、下拉、标签跟着 filters 走
func _sync_options() -> void:
	for group in _options:
		for value in _options[group]:
			_options[group][value].set_pressed_no_signal(value in filters[group])
			_options[group][value].queue_redraw()
	var names := CardDB.SPECIAL_SKILLS.filter(func(s): return s in filters.special).map(func(s): return tr("keyword." + s))
	%Filters.get_node("Special").text = tr("ui.card.separator").join(names) if names else tr("ui.book.all")


func _matches(id: String) -> bool:
	var data := CardDB.card(id)
	var terms := CardZoom.terms(data)
	var of_kind := func(kind: String): return terms.filter(func(t): return t[0] == kind).map(func(t): return t[1])
	return data.type in filters.types \
		and _any(filters.stars, [data.star]) \
		and _any(filters.races, data.get("races", [])) \
		and _any(filters.timings, of_kind.call("timing")) \
		and _any(filters.base, of_kind.call("base")) \
		and _any(filters.special, of_kind.call("special")) \
		and (search == "" or _matches_search(data))


## 组内满足任一；没勾的组不限制
func _any(selected: Array, values: Array) -> bool:
	return selected.is_empty() or selected.any(func(v): return v in values)


## 搜索：卡名、种族、时机、技能和效果文字（显示出来的文字）
func _matches_search(data: Dictionary) -> bool:
	var names := [tr("card." + data.id)]
	for race in data.get("races", []):
		names.append(tr("race." + race))
	for slot in CardDB.TIMING_SLOTS:
		if data.get(slot, CardDB.CLEAR) != CardDB.CLEAR:
			names.append(tr("timing." + data[slot]))
	var texts := CardDB.SKILL_SLOTS.map(func(slot): return load_card.base_skill_text(data.get(slot)))
	texts.append(load_card.special_skill_text(data.get("special_skills")))
	names.append_array(texts.filter(func(t): return t != null))
	return names.any(func(n): return search in n)


## 排序：序号；星级从低到高；战斗力从高到低。相同时按序号
func _before(a: String, b: String) -> bool:
	var x := CardDB.card(a)
	var y := CardDB.card(b)
	match sort:
		"star":
			if x.star != y.star:
				return x.star < y.star
		"strength":
			if x.get("strength", 0) != y.get("strength", 0):
				return x.get("strength", 0) > y.get("strength", 0)
	return x.no < y.no


func _refresh() -> void:
	shown = CardDB.all().keys().filter(_matches)
	shown.sort_custom(_before)
	for id in _cells:
		_cells[id].visible = id in shown
	for i in shown.size():
		_grid.move_child(_cells[shown[i]], i)
	%Count.text = str(shown.size())
	_rebuild_tags()


## 已选的条件：类型（只勾了一种时）、各组勾选的值、搜索词；点一下去掉
func _rebuild_tags() -> void:
	for child in %Tags.get_children():
		%Tags.remove_child(child)
		child.queue_free()
	var tags := []
	if filters.types.size() == 1:
		tags.append([tr("ui.book." + filters.types[0]), toggle_filter.bind("types", TYPES[1 - TYPES.find(filters.types[0])])])
	for star in filters.stars:
		tags.append(["★".repeat(star), toggle_filter.bind("stars", star)])
	for race in filters.races:
		tags.append([tr("race." + race), toggle_filter.bind("races", race)])
	for timing in filters.timings:
		tags.append([tr("timing." + timing), toggle_filter.bind("timings", timing)])
	for group in ["base", "special"]:
		for skill in filters[group]:
			tags.append([tr("keyword." + skill), toggle_filter.bind(group, skill)])
	if search:
		tags.append(["“%s”" % search, set_search.bind("")])
	for tag in tags:
		var button := Button.new()
		button.theme_type_variation = &"TagButton"
		button.text = tag[0] + "  ×"
		button.custom_minimum_size.y = 40
		button.size_flags_vertical = SIZE_SHRINK_CENTER
		button.pressed.connect(tag[1])
		%Tags.add_child(button)


# ---------- 卡牌网格 ----------

func _build_cards() -> void:
	for id in CardDB.all():
		var face := CardFace.new()
		if CardDB.card(id).type == "character":
			face.show_cards(id, "")
		else:
			face.show_cards("", id)
		var cell := Control.new()
		cell.mouse_filter = MOUSE_FILTER_PASS
		cell.add_child(face)
		cell.gui_input.connect(_on_card_input.bind(id))
		_grid.add_child(cell)
		_cells[id] = cell


## 点卡放大：按下和松开的位置差不多才算点击（拖动是在滚动网格）
func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.global_position
		elif event.global_position.distance_to(_press) < 16:
			open_zoom(id)


## 侧栏宽度、网格列数和卡牌缩放按画布宽度算
func _layout() -> void:
	var wide := size.x >= WIDE
	var rail := 520.0 if wide else 470.0
	var columns := 6 if wide else 5
	var left := rail + 40
	var right := size.x - 50
	var card_scale := (right - left - (columns - 1) * GAP) / columns / CardFace.WIDTH
	$Rail.position = Vector2.ZERO
	$Rail.size = Vector2(rail, size.y)
	$Head.position = Vector2(left, 8)
	$Head.size = Vector2(right - left, 70)
	$Scroll.position = Vector2(left, HEAD)
	$Scroll.size = Vector2(size.x - 20 - left, size.y - HEAD)
	$Fade.position = Vector2(rail, size.y - 120)
	$Fade.size = Vector2(size.x - rail, 120)
	_grid.columns = columns
	for cell in _cells.values():
		var face: CardFace = cell.get_child(0)
		face.display_scale = card_scale
		cell.custom_minimum_size = face.get_size()
		face.position = face.get_size() / 2


## 筛选的一个勾选块：勾选框后面画图标加文字、技能方块或星星（外观由 spec 给出：text、icon、tint、chip、stars）
class Option extends CheckBox:
	const FONT := preload("res://assets/fonts/sans_medium.tres")
	const STAR_COLOR := Color("ffd866")

	var spec: Dictionary

	func _init(spec_: Dictionary) -> void:
		spec = spec_
		theme_type_variation = &"FilterCheck"
		custom_minimum_size.y = 48
		focus_mode = FOCUS_NONE

	func _draw() -> void:
		var x := get_theme_stylebox("normal").get_margin(SIDE_LEFT) + get_theme_icon("unchecked").get_width() + get_theme_constant("h_separation")
		var middle := size.y / 2
		if spec.has("icon"):
			var icon := CardFace.cached_texture("res://assets/ui/icons/%s.png" % spec.icon)
			draw_texture_rect(icon, Rect2(x, middle - 13, 26, 26), false, spec.tint)
			x += 32
		if spec.has("stars"):
			for i in spec.stars:
				_string("★", Vector2(x + i * 12, middle), 18, STAR_COLOR)
		if spec.has("chip"):
			var height := roundf(19 * 1.5)
			CardFace.draw_chip(self, spec.chip, Rect2(x, middle - height / 2, CardFace.chip_width(spec.chip, 19), height), 19)
		if spec.has("text"):
			_string(spec.text, Vector2(x, middle), 22, Color.WHITE if button_pressed else Color(1, 1, 1, 0.8))

	func _string(text: String, left_middle: Vector2, font_size: int, color: Color) -> void:
		var baseline := left_middle.y + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) / 2
		draw_string(FONT, Vector2(left_middle.x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
