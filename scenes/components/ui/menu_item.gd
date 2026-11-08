@tool
class_name MenuItem
extends Button
## 主菜单的文字按钮：左边一枚菱形，悬停或聚焦时菱形填满并加下划线；不可用时灰显并标注 note。

const GOLD := Color("ffd98a")

## 不可用时文字后面的小标签，如"未开放"
@export var note := "":
	set(value):
		note = value
		queue_redraw()


func _ready() -> void:
	theme_type_variation = &"MenuItem"
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var active := not disabled and (is_hovered() or has_focus())
	var c := Vector2(14, size.y / 2)
	var points := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
	if active:
		draw_colored_polygon(points, GOLD)
		var line := Rect2(Vector2(34, size.y - 14), Vector2(420, 2))
		draw_texture_rect(_fade(), line, false)
	else:
		points.append(points[0])
		draw_polyline(points, Color(1, 1, 1, 0.35), 2.0)
	if disabled and note != "":
		var font := get_theme_font("font", "Label")
		var font_size := 20
		var label := tr(note)
		var text_width := get_theme_font("font").get_string_size(tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
		var pos := Vector2(get_theme_stylebox("normal").content_margin_left + text_width + 18, size.y / 2)
		var note_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var box := Rect2(pos - Vector2(0, note_size.y / 2 + 4), note_size + Vector2(20, 8))
		draw_rect(box, Color(1, 1, 1, 0.3), false, 1.0)
		draw_string(font, pos + Vector2(10, note_size.y / 2 - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.55))


var _fade_texture: GradientTexture1D

## 下划线：从金色渐隐到透明
func _fade() -> GradientTexture1D:
	if _fade_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(GOLD, 0.9))
		gradient.set_color(1, Color(GOLD, 0))
		_fade_texture = GradientTexture1D.new()
		_fade_texture.gradient = gradient
	return _fade_texture
