class_name FilterOption
extends CheckBox
## 筛选的勾选块（图鉴的筛选栏、科研模式的选卡区）：勾选框后面画内容，spec 给出：
## text 文字；icon 图标 id（assets/ui/icons/）和 tint 颜色；chip 技能方块（见 CardFace.draw_chip）；stars 星星个数。
## size 是高度，48 是常规，44 是小号（字和图标也小一号）。

const FONT := preload("res://assets/fonts/sans_medium.tres")
const STAR_COLOR := Color("ffd866")
## 勾选框左边的边距、勾选框、间距（和主题的 FilterCheck 一致），右边距
const CONTENT_LEFT := 40.0
const CONTENT_RIGHT := 14.0

var spec: Dictionary
var _font_size: int
var _icon_size: float


func _init(spec_: Dictionary, height := 48.0) -> void:
	spec = spec_
	theme_type_variation = &"FilterCheck"
	focus_mode = FOCUS_NONE
	_font_size = 22 if height >= 48 else 20
	_icon_size = 26.0 if height >= 48 else 24.0
	# 星星挤一点：图鉴筛选栏里一行放得下四个"★★★★"
	var right := 8.0 if spec.has("stars") else CONTENT_RIGHT
	custom_minimum_size = Vector2(CONTENT_LEFT + _content_width() + right, height)


func _content_width() -> float:
	var width := 0.0
	if spec.has("icon"):
		width += _icon_size + (6 if spec.has("text") else 0)
	if spec.has("stars"):
		width += 11 * (spec.stars - 1) + 17
	if spec.has("chip"):
		width += CardFace.chip_width(spec.chip, 19)
	if spec.has("text"):
		width += FONT.get_string_size(spec.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	return width


func _draw() -> void:
	var x := get_theme_stylebox("normal").get_margin(SIDE_LEFT) + get_theme_icon("unchecked").get_width() + get_theme_constant("h_separation")
	var middle := size.y / 2
	if spec.has("icon"):
		var icon := CardFace.cached_texture("res://assets/ui/icons/%s.png" % spec.icon)
		draw_texture_rect(icon, Rect2(x, middle - _icon_size / 2, _icon_size, _icon_size), false, spec.tint)
		x += _icon_size + 6
	if spec.has("stars"):
		for i in spec.stars:
			_string("★", Vector2(x + i * 11, middle), 17, STAR_COLOR)
	if spec.has("chip"):
		var height := roundf(19 * 1.5)
		CardFace.draw_chip(self, spec.chip, Rect2(x, middle - height / 2, CardFace.chip_width(spec.chip, 19), height), 19)
	if spec.has("text"):
		_string(spec.text, Vector2(x, middle), _font_size, Color.WHITE if button_pressed else Color(1, 1, 1, 0.8))


func _string(text: String, left_middle: Vector2, font_size: int, color: Color) -> void:
	var baseline := left_middle.y + (FONT.get_ascent(font_size) - FONT.get_descent(font_size)) / 2
	draw_string(FONT, Vector2(left_middle.x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
