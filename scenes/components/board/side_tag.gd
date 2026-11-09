class_name SideTag
extends Control
## 阵营旗帜：竖排的"对方"（红）、"我方"（蓝），字在旗子里居中，下端是燕尾。

const WIDTH := 58.0
const FONT := preload("res://assets/fonts/serif.tres")
const FONT_SIZE := 26
const LINE := 28.6
const COLORS := {true: [Color("8a2430"), Color("4a0f19"), Color("e7a0a6")], false: [Color("264f9a"), Color("12264f"), Color("a9c6ff")]}

var text := ""
var enemy := true


func _init(text_: String, enemy_: bool) -> void:
	text = text_
	enemy = enemy_
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 16 + text.length() * LINE + 28)
	size = custom_minimum_size


func _draw() -> void:
	var colors: Array = COLORS[enemy]
	var w := size.x
	var h := size.y
	var shape := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(w / 2, h - 14), Vector2(0, h)])
	draw_polygon(shape, PackedColorArray([colors[0], colors[0], colors[1], colors[1], colors[1]]))
	draw_polyline(shape + PackedVector2Array([shape[0]]), colors[2], 1.5, true)
	for i in text.length():
		var ch := text[i]
		var width := FONT.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var center := Vector2(w / 2, 16 + LINE * (i + 0.5))
		var baseline := center.y + (FONT.get_ascent(FONT_SIZE) - FONT.get_descent(FONT_SIZE)) / 2
		draw_string(FONT, Vector2(center.x - width / 2, baseline + 2), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.7))
		draw_string(FONT, Vector2(center.x - width / 2, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)
