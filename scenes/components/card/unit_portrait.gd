class_name UnitPortrait
extends Control
## 阵容里的一个单位（关卡详情的敌方阵容用）：角色是圆形头像，装备是完整压在左下角的小圆（和卡面上装备框的位置一致），
## 右上角标位置号，下面写角色名。底色、圈的颜色和卡面一致（种族色背景，圈随星级）。

const SIZE := 120.0  ## 头像直径
const EQUIP_SIZE := 62.0
const WIDTH := 128.0
const BADGE := 32.0  ## 位置号的圆
const SANS_BOLD := preload("res://assets/fonts/sans_bold.tres")
const GOLD := Color("ffd98a")


func _init(card_id: String, equip_id: String, number: int) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, SIZE + 44)
	var character := CardDB.card(card_id)
	add_child(_circle(character, {}, Vector2((WIDTH - SIZE) / 2, 0), SIZE, 3))
	if equip_id:
		add_child(_circle({}, CardDB.card(equip_id), Vector2(-14, 70), EQUIP_SIZE, 2.5))
	var badge := Control.new()
	badge.position = Vector2(WIDTH - BADGE + 8, -10)
	badge.size = Vector2(BADGE, BADGE)
	badge.draw.connect(_draw_badge.bind(badge, number))
	add_child(badge)
	var label := Label.new()
	label.text = tr("card." + card_id)
	label.add_theme_font_override("font", SANS_BOLD)
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-20, SIZE + 6)
	label.size = Vector2(WIDTH + 40, 30)
	add_child(label)


## 一个圆：外圈（星级色加黑边），里面是卡面同款背景和卡图（裁成圆形）；还没有卡图时淡显种族图标或虚线六边形
func _circle(character: Dictionary, equipment: Dictionary, at: Vector2, size: float, ring: float) -> Control:
	var main := character if character else equipment
	var holder := Control.new()
	holder.position = at
	holder.size = Vector2(size, size)
	holder.draw.connect(func():
		holder.draw_circle(holder.size / 2, size / 2 + ring + 2, Color.BLACK, true, -1, true)
		holder.draw_circle(holder.size / 2, size / 2 + ring, CardFace.TIER_LINE[main.star], true, -1, true))
	var background := ColorRect.new()
	background.size = holder.size
	background.material = ShaderMaterial.new()
	CardFace.apply_background(background.material, character, equipment, background.size, size / 2)
	background.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(background)
	var texture := CardFace.art(main.id)
	if texture:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 角色：靠上留一点空，脚可以被圆裁掉；装备：整件放进圆里
		image.position = Vector2(0, size * 0.08) if character else Vector2.ONE * size * 0.1
		image.size = Vector2(size, size * 0.92) if character else Vector2.ONE * size * 0.8
		background.add_child(image)
	else:
		var placeholder := Control.new()
		placeholder.size = holder.size
		placeholder.draw.connect(func(): CardFace.draw_placeholder(placeholder, main, placeholder.size / 2, size * 0.6))
		background.add_child(placeholder)
	return holder


## 位置号：深色圆、金边加黑边、白字
func _draw_badge(canvas: Control, number: int) -> void:
	var center := canvas.size / 2
	var r := BADGE / 2
	canvas.draw_circle(center, r + 3, Color.BLACK, true, -1, true)
	canvas.draw_circle(center, r + 1.5, GOLD, true, -1, true)
	canvas.draw_circle(center, r, Color("2a1d10"), true, -1, true)
	var text := str(number)
	var width := SANS_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var baseline := center.y + (SANS_BOLD.get_ascent(18) - SANS_BOLD.get_descent(18)) / 2
	canvas.draw_string(SANS_BOLD, Vector2(center.x - width / 2, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
