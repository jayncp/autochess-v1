class_name CardPreview
extends Control
## 放大查看一张卡（构筑阶段、科研模式）：PC 悬停、手机长按时显示在卡的旁边，优先放右边，放不下放左边，不出屏幕。
## 盖住整个界面，不接收输入。

const SCALE := 1.15
const MARGIN := 12.0
## PC 悬停查看，手机长按查看。项目开了"鼠标模拟触摸"，PC 上 is_touchscreen_available() 也是真，所以按平台判断
static var hover := not OS.has_feature("mobile")

var _face := CardFace.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	z_index = 2000
	visible = false
	_face.display_scale = SCALE
	_face.shadow = true
	add_child(_face)


## anchor 是被查看的卡在画布上的范围
func show_card(card_id: String, equip_id: String, anchor: Rect2) -> void:
	_face.show_cards(card_id, equip_id)
	var card := _face.get_size()
	var x := anchor.end.x + 24 + card.x / 2
	if x + card.x / 2 > size.x - MARGIN:
		x = anchor.position.x - 24 - card.x / 2
	x = clampf(x, card.x / 2 + MARGIN, size.x - card.x / 2 - MARGIN)
	var y := clampf(anchor.get_center().y, card.y / 2 + MARGIN, size.y - card.y / 2 - MARGIN)
	_face.position = Vector2(x, y)
	visible = true


func hide_card() -> void:
	visible = false
