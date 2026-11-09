class_name CardSlot
extends Node2D
## 卡位，原点在中心：可用的是金色虚线框加位置号；没解锁的是暗色斜纹加锁和"未解锁"；
## 拖卡经过时金框高亮；科研模式里选中时外面一圈金色光。大小由界面的布局设置（size），点击区域跟着变。

const GOLD := Color("ffd98a")
const RADIUS := 12.0
const SERIF := preload("res://assets/fonts/serif_title.tres")
const SANS := preload("res://assets/fonts/sans_medium.tres")
const LOCK := preload("res://assets/ui/icons/lock.png")

static var _stripes: ImageTexture

var card_in_slot = null
## 不能放卡（敌方的卡位、没解锁的卡位）：拖到这里算放到格子以外
@export var interactable := true
## 位置号，0 表示不显示
var number := 0:
	set(value):
		number = value
		queue_redraw()
var locked := false:
	set(value):
		locked = value
		interactable = not value
		queue_redraw()
var hover := false:
	set(value):
		hover = value
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var size := Vector2(180, 252):
	set(value):
		size = value
		$Area2D/CollisionShape2D.shape.size = value
		queue_redraw()


static func _static_init() -> void:
	# 斜纹：20 像素一格，一半深一半浅，平铺
	var image := Image.create_empty(20, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 20:
			image.set_pixel(x, y, Color(0, 0, 0, 0.45 if (x + y) % 20 < 10 else 0.3))
	_stripes = ImageTexture.create_from_image(image)


func _ready() -> void:
	texture_repeat = TEXTURE_REPEAT_ENABLED
	$Area2D/CollisionShape2D.shape.size = size


func _draw() -> void:
	var rect := Rect2(-size / 2, size)
	if selected:
		_glow(rect, 26, 0.6)
		draw_style_box(_box(Color.TRANSPARENT, GOLD, 3), rect.grow(3))
	if locked:
		draw_style_box(_box(Color(0.03, 0.04, 0.09, 0.35), Color(1, 1, 1, 0.12), 2), rect)
		draw_texture_rect(_stripes, rect.grow(-2), true)
		var icon := size.x * 0.18
		draw_texture_rect(LOCK, Rect2(-icon / 2, -icon / 2 - size.y * 0.04, icon, icon), false, Color(1, 1, 1, 0.3))
		_centered(SANS, tr("ui.board.locked"), Vector2(0, size.y / 2 - size.y * 0.1), maxi(12, roundi(size.x * 0.085)), Color(1, 1, 1, 0.35))
		return
	draw_style_box(_box(Color(0.04, 0.055, 0.13, 0.35), Color.TRANSPARENT, 0), rect)
	if hover:
		_glow(rect, 22, 0.6)
		draw_style_box(_box(Color(GOLD, 0.12), GOLD, 2), rect)
	else:
		_dashed(rect.grow(-1), Color(GOLD, 0.5))
	if number > 0:
		_centered(SERIF, str(number), Vector2.ZERO, roundi(size.x * 0.2), Color(GOLD, 0.45))


func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(roundi(RADIUS))
	box.draw_center = fill.a > 0
	return box


func _glow(rect: Rect2, glow_size: int, alpha: float) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(roundi(RADIUS))
	box.shadow_color = Color(1, 0.84, 0.47, alpha)
	box.shadow_size = glow_size
	draw_style_box(box, rect)


## 虚线圆角框：四条边画虚线，四个角画实线圆弧
func _dashed(rect: Rect2, color: Color) -> void:
	var r := RADIUS
	var a := rect.position
	var b := rect.end
	for edge in [[Vector2(a.x + r, a.y), Vector2(b.x - r, a.y)], [Vector2(b.x, a.y + r), Vector2(b.x, b.y - r)],
			[Vector2(b.x - r, b.y), Vector2(a.x + r, b.y)], [Vector2(a.x, b.y - r), Vector2(a.x, a.y + r)]]:
		draw_dashed_line(edge[0], edge[1], color, 1.5, 7)
	for corner in [[Vector2(a.x + r, a.y + r), PI], [Vector2(b.x - r, a.y + r), -PI / 2], [Vector2(b.x - r, b.y - r), 0.0], [Vector2(a.x + r, b.y - r), PI / 2]]:
		draw_arc(corner[0], r, corner[1], corner[1] + PI / 2, 8, color, 1.5, true)


func _centered(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	draw_string(font, Vector2(center.x - width / 2, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
