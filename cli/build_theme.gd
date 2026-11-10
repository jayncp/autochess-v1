extends SceneTree
## 生成全局主题 assets/ui/theme.tres 和字体变体 assets/fonts/*.tres。
## 颜色、字号、九宫格边距都在这里定，场景里不再单独覆盖样式。贴图由 tools/autochess_tools/art/ui.py 生成。
## 用法：just theme（改了贴图先 just art）

const GOLD := Color("ffd98a")
const GOLD_TEXT := Color("f3e6c4")
const GOLD_BRIGHT := Color("fff3d0")
const TEXT := Color(1, 1, 1, 0.92)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const THEME_DIR := "res://assets/ui/theme/"

## 字体变体：[字体文件, 字重, 加粗, 字间距]。黑体按字重，宋体是静态粗体，更重的用加粗；标题加字间距
const FONTS := {
	"sans": ["NotoSansSC.ttf", 400, 0.0, 0],
	"sans_medium": ["NotoSansSC.ttf", 500, 0.0, 0],
	"sans_bold": ["NotoSansSC.ttf", 700, 0.0, 0],
	"serif": ["NotoSerifSC-Bold.ttf", 0, 0.0, 0],
	"serif_heavy": ["NotoSerifSC-Bold.ttf", 0, 0.6, 0],
	"serif_title": ["NotoSerifSC-Bold.ttf", 0, 0.6, 6],
}

var fonts := {}


func _initialize() -> void:
	for name in FONTS:
		var spec: Array = FONTS[name]
		var font := FontVariation.new()
		font.base_font = load("res://assets/fonts/" + spec[0])
		if spec[1] > 0:
			font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): spec[1]}
		font.variation_embolden = spec[2]
		font.spacing_glyph = spec[3]
		_save(font, "res://assets/fonts/%s.tres" % name)
		fonts[name] = load("res://assets/fonts/%s.tres" % name)
	var theme := build()
	_stable_ids(theme)
	_save(theme, "res://assets/ui/theme.tres")
	quit()


## 子资源按"类型/条目"命名，重新生成时 ID 不变，diff 只反映真正的改动
func _stable_ids(theme: Theme) -> void:
	for type in theme.get_type_list():
		for name in theme.get_stylebox_list(type):
			theme.get_stylebox(name, type).resource_scene_unique_id = ("%s_%s" % [type, name]).validate_node_name()
		for name in theme.get_icon_list(type):
			var icon := theme.get_icon(name, type)
			if icon.resource_path.is_empty():  # 图标贴图都是 assets/ui/theme/ 下的文件；只有内嵌的才需要命名
				icon.resource_scene_unique_id = ("icon_%s_%s" % [type, name]).validate_node_name()


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("保存 %s 失败：%s" % [path, error_string(err)])
	else:
		print("写入 ", path)


func build() -> Theme:
	var t := Theme.new()
	t.default_font = fonts.sans
	t.default_font_size = 26

	# 标签：正文白色；标题是宋体（金色渐变用 gold_text 着色器）
	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", fonts.serif_title)
	t.set_font_size("font_size", "TitleLabel", 46)
	t.set_color("font_color", "TitleLabel", Color.WHITE)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 22)
	t.set_color("font_color", "HintLabel", Color(1, 0.94, 0.84, 0.7))

	t.set_type_variation("GroupLabel", "Label")
	t.set_font("font", "GroupLabel", fonts.serif)
	t.set_font_size("font_size", "GroupLabel", 22)
	t.set_color("font_color", "GroupLabel", GOLD_TEXT)

	# 面板；侧栏是贴边的深色栏，右边一条金线；展开的详情是金框
	for type in ["Panel", "PanelContainer"]:
		t.set_stylebox("panel", type, _box("plate", 10, 18))
	t.set_type_variation("DialogPanel", "PanelContainer")
	t.set_stylebox("panel", "DialogPanel", _box("dialog", 26, 0, 16))
	t.set_type_variation("RailPanel", "PanelContainer")
	var rail := _flat(Color(0.024, 0.031, 0.086, 0.85), 0)
	rail.border_width_right = 1
	rail.border_color = Color(GOLD, 0.45)
	rail.shadow_color = Color(0, 0, 0, 0.45)
	rail.shadow_size = 24
	rail.shadow_offset = Vector2(6, 0)
	t.set_stylebox("panel", "RailPanel", rail)
	t.set_type_variation("DetailPanel", "PanelContainer")
	var detail := _outlined(Color(0.04, 0.05, 0.15, 0.96), GOLD, 2, 6, 0)
	detail.shadow_color = Color(0, 0, 0, 0.55)
	detail.shadow_size = 22
	detail.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "DetailPanel", detail)

	# 按钮：深蓝底板、细金线，两端菱形由 UiButton 画
	t.set_font("font", "Button", fonts.serif)
	t.set_font_size("font_size", "Button", 27)
	_button_colors(t, "Button", GOLD_TEXT, Color.WHITE, GOLD_TEXT.darkened(0.15), Color(GOLD_TEXT, 0.4))
	t.set_stylebox("normal", "Button", _box("button", 10, 30))
	t.set_stylebox("hover", "Button", _box("button_hover", 10, 30))
	t.set_stylebox("pressed", "Button", _box("button_pressed", 10, 30))
	t.set_stylebox("hover_pressed", "Button", _box("button_pressed", 10, 30))
	t.set_stylebox("disabled", "Button", _box("button_disabled", 10, 30))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 34)

	t.set_type_variation("PrimaryButton", "Button")
	t.set_font("font", "PrimaryButton", fonts.serif_heavy)
	t.set_font_size("font_size", "PrimaryButton", 32)
	_button_colors(t, "PrimaryButton", GOLD_BRIGHT, Color.WHITE, GOLD_BRIGHT.darkened(0.15), Color(GOLD_BRIGHT, 0.4))
	t.set_stylebox("normal", "PrimaryButton", _box("button_primary", 18, 44, 8))
	t.set_stylebox("hover", "PrimaryButton", _box("button_primary_hover", 18, 44, 8))
	t.set_stylebox("pressed", "PrimaryButton", _box("button_primary_pressed", 18, 44, 8))
	t.set_stylebox("hover_pressed", "PrimaryButton", _box("button_primary_pressed", 18, 44, 8))
	t.set_stylebox("disabled", "PrimaryButton", _box("button_primary_disabled", 18, 44, 8))

	# 自己画外观的按钮（关卡格、标签页）：没有底板
	t.set_type_variation("PlainButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "PlainButton", StyleBoxEmpty.new())

	# 小号按钮（重置筛选这类次要操作）
	t.set_type_variation("SmallButton", "Button")
	t.set_font_size("font_size", "SmallButton", 22)

	# 已选条件的标签：圆角、淡金底，点一下去掉
	t.set_type_variation("TagButton", "Button")
	t.set_font("font", "TagButton", fonts.sans_medium)
	t.set_font_size("font_size", "TagButton", 20)
	_button_colors(t, "TagButton", Color.WHITE, Color.WHITE, GOLD_TEXT, TEXT_DIM)
	t.set_stylebox("normal", "TagButton", _outlined(Color(GOLD, 0.16), Color(GOLD, 0.6), 1, 20, 14))
	t.set_stylebox("hover", "TagButton", _outlined(Color(GOLD, 0.26), GOLD, 1, 20, 14))
	t.set_stylebox("pressed", "TagButton", _outlined(Color(GOLD, 0.1), GOLD, 1, 20, 14))
	t.set_stylebox("focus", "TagButton", StyleBoxEmpty.new())

	# 只有图标的方形按钮（返回、速度、跳过）
	t.set_type_variation("IconButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var source: String = "button" if state == "normal" else "button_" + ("pressed" if state == "hover_pressed" else state)
		t.set_stylebox(state, "IconButton", _box(source, 10, 14))
	_button_colors(t, "IconButton", GOLD_TEXT, Color.WHITE, GOLD_TEXT.darkened(0.15), Color(GOLD_TEXT, 0.4))

	# 主菜单的文字按钮：没有底板，选中时由 MenuItem 画菱形和下划线
	t.set_type_variation("MenuItem", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "MenuItem", _empty(40, 8, 20, 8))
	t.set_font("font", "MenuItem", fonts.serif)
	t.set_font_size("font_size", "MenuItem", 46)
	_button_colors(t, "MenuItem", Color(1, 1, 1, 0.88), Color("ffe3a3"), Color("ffd98a"), Color(1, 1, 1, 0.38))
	t.set_color("font_outline_color", "MenuItem", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "MenuItem", 6)

	# 勾选块、开关
	for type in ["CheckBox", "CheckButton"]:
		t.set_font("font", type, fonts.sans)
		t.set_font_size("font_size", type, 24)
		_button_colors(t, type, TEXT, Color.WHITE, Color.WHITE, TEXT_DIM)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(state, type, _empty(4, 4, 4, 4))
		t.set_constant("h_separation", type, 12)
		t.set_constant("icon_max_width", type, 0)  # 不继承 Button 的图标限宽，开关按贴图原尺寸画
	# 筛选用的勾选块：带框，选中时金框淡金底
	t.set_type_variation("FilterCheck", "CheckBox")
	t.set_font("font", "FilterCheck", fonts.sans_medium)
	t.set_font_size("font_size", "FilterCheck", 22)
	_button_colors(t, "FilterCheck", Color(1, 1, 1, 0.8), Color.WHITE, Color.WHITE, TEXT_DIM)
	t.set_color("font_hover_pressed_color", "FilterCheck", Color.WHITE)
	t.set_stylebox("normal", "FilterCheck", _outlined(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 2, 4, 10))
	t.set_stylebox("hover", "FilterCheck", _outlined(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.3), 2, 4, 10))
	t.set_stylebox("pressed", "FilterCheck", _outlined(Color(GOLD, 0.14), GOLD, 2, 4, 10))
	t.set_stylebox("hover_pressed", "FilterCheck", _outlined(Color(GOLD, 0.2), GOLD, 2, 4, 10))
	t.set_stylebox("focus", "FilterCheck", StyleBoxEmpty.new())
	t.set_constant("h_separation", "FilterCheck", 8)
	t.set_constant("icon_max_width", "FilterCheck", 26)
	var on := _tex("check_on")
	var off := _tex("check_off")
	for icon in ["checked", "checked_disabled"]:
		t.set_icon(icon, "CheckBox", on)
	for icon in ["unchecked", "unchecked_disabled"]:
		t.set_icon(icon, "CheckBox", off)
	for icon in ["checked", "checked_disabled", "checked_mirrored", "checked_disabled_mirrored"]:
		t.set_icon(icon, "CheckButton", _tex("toggle_on"))
	for icon in ["unchecked", "unchecked_disabled", "unchecked_mirrored", "unchecked_disabled_mirrored"]:
		t.set_icon(icon, "CheckButton", _tex("toggle_off"))

	# 输入框、下拉
	t.set_stylebox("normal", "LineEdit", _box("input", 10, 18))
	t.set_stylebox("focus", "LineEdit", _box("input_focus", 10, 18))
	t.set_stylebox("read_only", "LineEdit", _box("input", 10, 18))
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.42))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	t.set_font("font", "OptionButton", fonts.sans)
	t.set_font_size("font_size", "OptionButton", 24)
	_button_colors(t, "OptionButton", Color.WHITE, Color.WHITE, Color.WHITE, TEXT_DIM)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "OptionButton", _box("input_focus" if state in ["hover", "pressed", "hover_pressed"] else "input", 10, 18))
	t.set_icon("arrow", "OptionButton", _tex("arrow_down"))
	# 搜索框：左边留出放大镜的位置；多选下拉：按钮样式同输入框
	t.set_type_variation("SearchEdit", "LineEdit")
	var search := _box("input", 10, 18)
	search.content_margin_left = 54
	t.set_stylebox("normal", "SearchEdit", search)
	var search_focus := _box("input_focus", 10, 18)
	search_focus.content_margin_left = 54
	t.set_stylebox("focus", "SearchEdit", search_focus)
	t.set_type_variation("SelectButton", "Button")
	t.set_font("font", "SelectButton", fonts.sans)
	t.set_font_size("font_size", "SelectButton", 22)
	_button_colors(t, "SelectButton", Color.WHITE, Color.WHITE, Color.WHITE, TEXT_DIM)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "SelectButton", _box("input_focus" if state in ["hover", "pressed", "hover_pressed"] else "input", 10, 18))
	t.set_constant("icon_max_width", "SelectButton", 22)
	t.set_stylebox("panel", "PopupMenu", _box("plate", 10, 8))
	t.set_stylebox("hover", "PopupMenu", _flat(Color(GOLD, 0.14), 4))
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 14)
	var popup := _outlined(Color("0b0f26"), GOLD, 2, 6, 8)
	popup.content_margin_top = 8
	popup.content_margin_bottom = 8
	popup.shadow_color = Color(0, 0, 0, 0.7)
	popup.shadow_size = 24
	popup.shadow_offset = Vector2(0, 12)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_icon("checked", "PopupMenu", on)
	t.set_icon("unchecked", "PopupMenu", off)

	# 滚动条：细金条，没有箭头
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, _flat(Color(1, 1, 1, 0.12), 3, 6))
		t.set_stylebox("scroll_focus", type, _flat(Color(1, 1, 1, 0.12), 3, 6))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			t.set_stylebox(state, type, _flat(Color(GOLD, 0.8 if state == "grabber" else 1.0), 3, 6))
		for icon in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, type, _tex("empty"))
	return t


func _button_colors(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	t.set_color("font_color", type, normal)
	t.set_color("font_focus_color", type, normal)
	t.set_color("font_hover_color", type, hover)
	t.set_color("font_pressed_color", type, pressed)
	t.set_color("font_hover_pressed_color", type, pressed)
	t.set_color("font_disabled_color", type, disabled)
	t.set_color("icon_normal_color", type, normal)
	t.set_color("icon_hover_color", type, hover)
	t.set_color("icon_pressed_color", type, pressed)
	t.set_color("icon_disabled_color", type, disabled)


## 九宫格底板：margin 是贴图四边不拉伸的宽度，content 是左右内边距，glow 是贴图四周留给外发光的空
func _box(name: String, margin: int, content: int, glow := 0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _tex(name)
	box.set_texture_margin_all(margin + glow)
	box.set_expand_margin_all(glow)
	box.content_margin_left = content
	box.content_margin_right = content
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _empty(left: int, top: int, right: int, bottom: int) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = left
	box.content_margin_top = top
	box.content_margin_right = right
	box.content_margin_bottom = bottom
	return box


func _flat(color: Color, radius: int, min_size := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = min_size / 2.0
	box.content_margin_right = min_size / 2.0
	box.content_margin_top = min_size / 2.0
	box.content_margin_bottom = min_size / 2.0
	return box


## 带边框的纯色底板：border 线宽，margin 左右内边距
func _outlined(color: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var box := _flat(color, radius)
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


func _tex(name: String) -> Texture2D:
	return load(THEME_DIR + name + ".png")
