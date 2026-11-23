class_name Dialog
extends Control
## 对话框：通知（一个"知道了"）或确认（"取消" + "确定"）。盖住整个屏幕，点按钮关闭。
## 通知：Dialog.notice(self, 标题, 正文)
## 确认：var ok: bool = await Dialog.confirm(self, 标题, 正文).closed
## 外框和标题由 frame() 搭，别的面板（阵容码）也可以用它

signal closed(confirmed: bool)

const WIDTH := 760.0
const GOLD := Color("ffd98a")
const GOLD_TEXT_SHADER := preload("res://scenes/components/ui/gold_text.gdshader")


static func notice(parent: Node, title: String, text: String) -> Dialog:
	return _open(parent, title, text, false)


static func confirm(parent: Node, title: String, text: String) -> Dialog:
	return _open(parent, title, text, true)


static func _open(parent: Node, title: String, text: String, ask: bool) -> Dialog:
	var dialog := Dialog.new()
	dialog._build(title, text, ask)
	parent.add_child(dialog)
	return dialog


func _build(title: String, text: String, ask: bool) -> void:
	var column := frame(self, title, WIDTH)
	var body := Label.new()
	body.text = text
	body.add_theme_font_size_override("font_size", 30)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	column.add_child(gap(36))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	column.add_child(buttons)
	if ask:
		buttons.add_child(_button("ui.dialog.cancel", false, false))
		buttons.add_child(_button("ui.dialog.confirm", true, true))
	else:
		buttons.add_child(_button("ui.dialog.ok", true, true))


## 盖住整个屏幕的压暗底和居中的框（标题、分隔线），返回放内容的一列。阵容码面板也用。
## 框外的点击交给 overlay 自己（_gui_input）；框里的空白处挡住点击
static func frame(overlay: Control, title: String, width: float) -> VBoxContainer:
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.027, 0.063, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := Box.new()
	box.theme_type_variation = &"DialogPanel"
	box.custom_minimum_size.x = width
	box.mouse_filter = MOUSE_FILTER_STOP
	center.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_bottom", 44)
	box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	var heading := Label.new()
	heading.theme_type_variation = &"TitleLabel"
	heading.add_theme_font_size_override("font_size", 40)
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gold := ShaderMaterial.new()
	gold.shader = GOLD_TEXT_SHADER
	gold.set_shader_parameter("height", 56.0)
	heading.material = gold
	column.add_child(heading)
	var rule := TextureRect.new()
	rule.texture = _rule_texture()
	rule.custom_minimum_size = Vector2(320, 2)
	rule.size_flags_horizontal = SIZE_SHRINK_CENTER
	column.add_child(rule)
	column.add_child(gap(26))
	return column


func _button(key: String, primary: bool, confirmed: bool) -> UiButton:
	var button := UiButton.new()
	button.text = key
	button.custom_minimum_size = Vector2(200, 74)
	button.add_theme_font_size_override("font_size", 30)
	if primary:
		button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(_close.bind(confirmed))
	return button


func _close(confirmed: bool) -> void:
	closed.emit(confirmed)
	queue_free()


## 一段竖直的空白
static func gap(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


static func _rule_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.5, 1])
	gradient.colors = PackedColorArray([Color(GOLD, 0), GOLD, Color(GOLD, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 320
	texture.height = 2
	texture.fill_to = Vector2(1, 0)
	return texture


## 对话框的框：两侧中间各一枚菱形，顶部中间一枚徽记
class Box extends PanelContainer:
	const GOLD := Color("ffd98a")

	func _draw() -> void:
		var y := size.y / 2
		for x in [0.0, size.x]:
			_diamond(Vector2(x, y), 16, Color.BLACK)
			_diamond(Vector2(x, y), 14, GOLD)
		var top := Vector2(size.x / 2, 0)
		_diamond(top, 46, Color.BLACK)
		_diamond(top, 42, GOLD)
		_diamond(top, 38, Color("3d2a0b"))
		_diamond(top, 12, Color("ffe7a8"))

	func _diamond(center: Vector2, d: float, color: Color) -> void:
		var r := d / 2
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), color)
