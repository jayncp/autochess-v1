class_name LevelTile
extends Button
## 关卡列表的一格：编号菱形、关卡名（太长时省略号截断）、展开箭头。
## 点这一格进入关卡；点右边的箭头（圆形按钮）展开或收起详情。
## 展开时金框加光；已通关时绿框加光、右上角一个绿色对号，不写文字。

signal enter_requested
signal detail_requested

const HEIGHT := 88.0
## 右边箭头按钮的点击范围（宽）和圆的半径
const ARROW_ZONE := 84.0
const ARROW_RADIUS := 24.0
const GOLD := Color("ffd98a")
const GREEN := Color("8fd14f")
const NUMBER_FONT := preload("res://assets/fonts/sans_bold.tres")
const NAME_FONT := preload("res://assets/fonts/serif_title.tres")
const CHECK := preload("res://assets/ui/icons/check.png")

var number := 1
var title := ""
var open := false:
	set(value):
		open = value
		queue_redraw()
var cleared := false:
	set(value):
		cleared = value
		queue_redraw()


func _init() -> void:
	theme_type_variation = &"PlainButton"
	custom_minimum_size.y = HEIGHT
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _pressed() -> void:
	if _on_arrow():
		detail_requested.emit()
	else:
		enter_requested.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		queue_redraw()


func _on_arrow() -> bool:
	return get_local_mouse_position().x >= size.x - ARROW_ZONE


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(get_theme_stylebox("panel", "PanelContainer"), rect)
	if cleared:
		_glow(rect, GREEN)
	elif open or is_hovered():
		_glow(rect, Color(GOLD, 1.0 if open else 0.5))

	# 编号：金边菱形，深棕渐变
	var center := Vector2(57, size.y / 2)
	var r := 38.0
	var diamond := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
	var outer := PackedVector2Array(Array(diamond).map(func(p): return center + (p - center) * (r + 3) / r))
	draw_colored_polygon(outer, Color.BLACK)
	draw_polygon(diamond, PackedColorArray([Color("5c4012"), Color("432e0b"), Color("2a1b04"), Color("432e0b")]))
	draw_polyline(diamond + PackedVector2Array([diamond[0]]), GOLD, 1.5, true)
	_centered(NUMBER_FONT, "%02d" % number, center, 24, Color("fff3d0"))

	# 关卡名：放不下时省略号
	var left := center.x + r + 22
	var right := size.x - ARROW_ZONE - 4
	var line := TextLine.new()
	line.add_string(title, NAME_FONT, 32)
	line.width = right - left
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var top := size.y / 2 - line.get_size().y / 2
	line.draw(get_canvas_item(), Vector2(left, top + 2), Color(0, 0, 0, 0.8))
	line.draw(get_canvas_item(), Vector2(left, top), Color.WHITE)

	# 展开箭头：圆形按钮，收起时朝下，展开时朝上；指针在上面时加亮
	var arrow := Vector2(size.x - ARROW_ZONE / 2, size.y / 2)
	var lit := open or (is_hovered() and _on_arrow())
	draw_circle(arrow, ARROW_RADIUS, Color(GOLD, 0.16 if lit else 0.06), true, -1, true)
	draw_arc(arrow, ARROW_RADIUS, 0, TAU, 48, Color(GOLD, 0.8 if lit else 0.4), 1.5, true)
	var d := -1.0 if open else 1.0
	draw_polyline(PackedVector2Array([arrow + Vector2(-9, -4.5 * d), arrow + Vector2(0, 4.5 * d), arrow + Vector2(9, -4.5 * d)]), GOLD, 3, true)

	if cleared:
		var tick := Vector2(size.x - 9, 7)
		draw_circle(tick, 21, Color.BLACK, true, -1, true)
		draw_circle(tick, 19, Color("6aa832"), true, -1, true)
		draw_circle(tick + Vector2(-3, -4), 12, Color("a8d96a"), true, -1, true)
		draw_texture_rect(CHECK, Rect2(tick - Vector2(12, 12), Vector2(24, 24)), false, Color("173004"))


## 边框加一圈渐弱的光
func _glow(rect: Rect2, color: Color) -> void:
	for i in 4:
		draw_rect(rect.grow(1 + i * 2), Color(color, color.a * (0.3 - i * 0.07)), false, 2)
	draw_rect(rect.grow(-1), color, false, 2)


func _centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	draw_string(font, Vector2(center.x - width / 2, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
