class_name TabButton
extends Button
## 标签页（关卡选择、科研模式的选卡区）：标题加一行小字（数量或"即将开放"），选中时金色下划线。
## 同一组的标签用 ButtonGroup 互斥。

const TITLE_FONT := preload("res://assets/fonts/serif_title.tres")
const NOTE_FONT := preload("res://assets/fonts/sans_bold.tres")
const GOLD := Color("ffd98a")

var title := ""
var note := "":
	set(value):
		note = value
		_fit()
		queue_redraw()


func _init(title_: String, note_: String) -> void:
	title = title_
	theme_type_variation = &"PlainButton"
	toggle_mode = true
	focus_mode = FOCUS_NONE
	note = note_
	toggled.connect(func(_on): queue_redraw())


func _fit() -> void:
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
