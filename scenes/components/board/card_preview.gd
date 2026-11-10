class_name CardPreview
extends Control
## 放大查看一张卡（构筑阶段、科研模式）：PC 悬停、手机长按时显示在卡的上方，水平居中对着这张卡，不出屏幕；
## 上方放不下（队列里的卡）就从这张卡的下边往上展开（盖住它自己），顶到屏幕上边为止。
## 从不放在下方和左右：最下面一排（手牌、选卡区）和同一排的其他卡都不会被挡住。
## 大小是被查看的卡的 1.3 倍，在 1.15 到 1.3 之间。盖住整个界面，不接收输入。

const MIN_SCALE := 1.15
const MAX_SCALE := 1.3
const ENLARGE := 1.3
const GAP := 16.0
const MARGIN := 12.0
## PC 悬停查看，手机长按查看。项目开了"鼠标模拟触摸"，PC 上 is_touchscreen_available() 也是真，所以按平台判断
static var hover := not OS.has_feature("mobile")

var _face := CardFace.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	z_index = 2000
	visible = false
	_face.shadow = true
	add_child(_face)


## anchor 是被查看的卡在画布上的范围
func show_card(card_id: String, equip_id: String, anchor: Rect2) -> void:
	_face.show_cards(card_id, equip_id)
	var full := BoardLayout.card_height(1, false)
	_face.display_scale = clampf(anchor.size.x / CardFace.WIDTH * ENLARGE, MIN_SCALE, MAX_SCALE)
	var height := full * _face.display_scale
	var top := anchor.position.y - GAP - height
	if top < MARGIN:
		top = maxf(MARGIN, anchor.end.y - height)
	if top + height > size.y - MARGIN:
		height = size.y - MARGIN - top
		_face.display_scale = height / full
	var width := CardFace.WIDTH * _face.display_scale
	var x := clampf(anchor.get_center().x, width / 2 + MARGIN, size.x - width / 2 - MARGIN)
	_face.position = Vector2(x, top + height / 2)
	visible = true


func hide_card() -> void:
	visible = false
