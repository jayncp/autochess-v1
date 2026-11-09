class_name CardZoom
extends Control
## 点卡放大（图鉴）：左边是放大的卡，右边列出这张卡用到的时机和词条说明，最后一行是种族、星级、序号。点任意处关闭。

const CARD_SCALE := 1.7
const GLOSS_WIDTH := 600.0
const KEY_WIDTH := 120.0
const GOLD := Color("ffd98a")
const GOLD_TEXT := Color("f3e6c4")
const SANS_BOLD := preload("res://assets/fonts/sans_bold.tres")
const SANS_MEDIUM := preload("res://assets/fonts/sans_medium.tres")
const SERIF := preload("res://assets/fonts/serif_title.tres")
const DIAMOND := preload("res://assets/ui/theme/diamond.png")


func _init(id: String) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.027, 0.063, 0.85)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(row)

	var data := CardDB.card(id)
	var face := CardFace.new()
	face.display_scale = CARD_SCALE
	if data.type == "character":
		face.show_cards(id, "")
	else:
		face.show_cards("", id)
	var holder := Control.new()
	holder.custom_minimum_size = face.get_size()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	face.position = holder.custom_minimum_size / 2
	holder.add_child(face)
	row.add_child(holder)
	row.add_child(_gloss(data))

	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "ui.book.close_hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	hint.offset_top = -70
	hint.offset_bottom = -34
	add_child(hint)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		accept_event()
		queue_free()


## 这张卡用到的时机、基础技能、特殊技能，按显示顺序：[类型, id, 数值]。
## 时机包括带时机的特殊技能的时机；基础技能把两格同名的相加；描述型特殊技能卡面上已经是整句，不列
static func terms(data: Dictionary) -> Array:
	var timings := []
	for slot in CardDB.TIMING_SLOTS:
		if data.get(slot) is String and data[slot] != CardDB.CLEAR:
			timings.append(data[slot])
	var specials: Dictionary = data.special_skills if data.get("special_skills") is Dictionary else {}
	for value in specials.values():
		if value is Dictionary:
			timings.append(value.timing)
	var base := {}
	for slot in CardDB.SKILL_SLOTS:
		if data.get(slot) is Dictionary:
			for skill in data[slot]:
				base[skill] = base.get(skill, 0) + data[slot][skill]
	var result := []
	for timing in CardDB.TIMINGS.filter(func(t): return t in timings):
		result.append(["timing", timing, null])
	for skill in CardDB.sorted_skills(base):
		result.append(["base", skill, base[skill]])
	for skill in CardDB.sorted_skills(specials):
		if skill not in CardDB.DESCRIPTIVE_SPECIALS:
			result.append(["special", skill, specials[skill]])
	return result


func _gloss(data: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = GLOSS_WIDTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var diamond := TextureRect.new()
	diamond.texture = DIAMOND
	diamond.modulate = GOLD
	diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	diamond.custom_minimum_size = Vector2(12, 12)
	diamond.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(diamond)
	head.add_child(_label(tr("ui.book.glossary"), SERIF, 24, GOLD_TEXT))
	column.add_child(head)
	for term in terms(data):
		column.add_child(_term(term))
	var meta := ""
	if data.type == "character":
		var races := CardDB.sorted_races(data.races).map(func(r): return tr("race." + r))
		meta = tr("ui.book.meta_character") % [tr("ui.card.separator").join(races), data.star, data.no]
	else:
		meta = tr("ui.book.meta_equipment") % [data.star, data.no]
	var meta_label := _label(meta, SANS_MEDIUM, 22, Color(1, 0.94, 0.84, 0.7))
	meta_label.custom_minimum_size.y = 56
	meta_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	column.add_child(meta_label)
	return column


## 一条说明：左边是时机（图标加名称）、基础技能方块或特殊技能，右边是说明，下面一条细线
func _term(term: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(_gap(16))
	box.add_child(row)
	box.add_child(_gap(16))
	var line := ColorRect.new()
	line.color = Color(GOLD, 0.18)
	line.custom_minimum_size.y = 1
	box.add_child(line)

	var key := HBoxContainer.new()
	key.custom_minimum_size.x = KEY_WIDTH
	key.add_theme_constant_override("separation", 6)
	var description := ""
	match term[0]:
		"timing":
			var color: Color = CardFace.TIMING_COLORS[term[1]]
			var icon := TextureRect.new()
			icon.texture = load("res://assets/ui/icons/%s.png" % term[1])
			icon.modulate = color
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.custom_minimum_size = Vector2(28, 28)
			icon.size_flags_vertical = SIZE_SHRINK_CENTER
			key.add_child(icon)
			key.add_child(_label(tr("timing." + term[1]), SANS_BOLD, 26, color))
			description = tr("timing_desc." + term[1])
		"base":
			key.add_child(Chip.new([tr("keyword." + term[1]), str(term[2]), CardFace.CHIP_COLORS[term[1]], false], 24))
			description = tr("keyword_desc." + term[1]).replace("N", str(term[2]))
		"special":
			key.add_child(_label(load_card.one_skill_text(term[1], term[2]), SANS_BOLD, 26, Color.WHITE))
			description = tr("keyword_desc." + term[1]).replace("N", str(term[2]))
	row.add_child(key)
	var text := _label(description, preload("res://assets/fonts/sans.tres"), 28, Color(1, 1, 1, 0.92))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text)
	return box


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap


## 一个基础技能方块（和卡面上的一样）
class Chip extends Control:
	var chip: Array
	var px: int

	func _init(chip_: Array, px_: int) -> void:
		chip = chip_
		px = px_
		custom_minimum_size = Vector2(CardFace.chip_width(chip, px), roundf(px * 1.5))
		size_flags_vertical = SIZE_SHRINK_CENTER

	func _draw() -> void:
		CardFace.draw_chip(self, chip, Rect2(Vector2.ZERO, size), px)
