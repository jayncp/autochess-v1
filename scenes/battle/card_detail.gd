class_name CardDetail
extends Control
## 战斗中点卡查看：左边是合成后的大卡（实时状态、当前战斗力），右边是拆开的角色卡、装备卡（原始状态）。
## 没带装备时右边只有角色的原始卡面。点任意处关闭；战斗照常进行，大卡是点开那一刻的样子。

const BIG_SCALE := 1.6
const SMALL_SCALE := 0.75
const GOLD := Color("ffd98a")
const SERIF := preload("res://assets/fonts/serif_title.tres")
const DIAMOND := preload("res://assets/ui/theme/diamond.png")


func _init(source: CardFace, card_id: String, equip_id: String) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	z_index = 2000
	var dim := ColorRect.new()
	dim.color = Color(0.024, 0.031, 0.07, 0.82)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(row)

	var big := CardFace.new()
	big.display_scale = BIG_SCALE
	big.show_cards(card_id, equip_id)
	big.copy_live(source)
	row.add_child(_holder(big))
	var equal := Label.new()
	equal.text = "="
	equal.add_theme_font_override("font", SERIF)
	equal.add_theme_font_size_override("font_size", 64)
	equal.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	equal.visible = equip_id != ""
	row.add_child(equal)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 26)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(side)
	side.add_child(_original(tr("ui.book.character") if equip_id else tr("ui.battle.original"), card_id, ""))
	if equip_id:
		side.add_child(_original(tr("ui.book.equipment"), "", equip_id))

	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "ui.common.close_hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	hint.offset_top = -66
	hint.offset_bottom = -30
	add_child(hint)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		accept_event()
		queue_free()


## 一张原始卡：上面一行标题（菱形加文字）
func _original(caption: String, card_id: String, equip_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var diamond := TextureRect.new()
	diamond.texture = DIAMOND
	diamond.modulate = GOLD
	diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	diamond.custom_minimum_size = Vector2(11, 11)
	diamond.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(diamond)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_override("font", SERIF)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	head.add_child(label)
	box.add_child(head)
	var face := CardFace.new()
	face.display_scale = SMALL_SCALE
	face.show_cards(card_id, equip_id)
	box.add_child(_holder(face))
	return box


func _holder(face: CardFace) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = face.get_size()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	face.position = face.get_size() / 2
	holder.add_child(face)
	return holder
