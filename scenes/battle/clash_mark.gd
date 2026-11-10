extends VBoxContainer
## 交战位标记：红色光圈里的交叉双剑，下面写"交战位"。放在中间一带的最左边，对着两排的交战位。

const SIZE := 92.0
const RED := Color("ff7a62")
const ICON := preload("res://assets/ui/icons/on_engage.png")
const SERIF := preload("res://assets/fonts/serif_title.tres")


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	alignment = ALIGNMENT_CENTER
	add_theme_constant_override("separation", 4)
	var emblem := Control.new()
	emblem.custom_minimum_size = Vector2(SIZE, SIZE)
	emblem.size_flags_horizontal = SIZE_SHRINK_CENTER
	emblem.mouse_filter = MOUSE_FILTER_IGNORE
	emblem.draw.connect(_draw_emblem.bind(emblem))
	add_child(emblem)
	var label := Label.new()
	label.text = "ui.board.front"
	label.add_theme_font_override("font", SERIF)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("ffb3a6"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


func _draw_emblem(canvas: Control) -> void:
	var center := canvas.size / 2
	var r := SIZE / 2
	# 外发光
	for i in 6:
		canvas.draw_circle(center, r + 4 + i * 3, Color(1, 0.35, 0.27, 0.1 - i * 0.015), true, -1, true)
	canvas.draw_circle(center, r + 4, Color(0, 0, 0, 0.5), true, -1, true)
	canvas.draw_circle(center, r, Color("1e0808"), true, -1, true)
	canvas.draw_circle(center, r * 0.7, Color(1, 0.47, 0.35, 0.3), true, -1, true)
	canvas.draw_arc(center, r - 0.75, 0, TAU, 64, Color(1, 0.55, 0.43, 0.9), 1.5, true)
	var icon := 56.0
	canvas.draw_texture_rect(ICON, Rect2(center - Vector2.ONE * icon / 2, Vector2.ONE * icon), false, RED)
