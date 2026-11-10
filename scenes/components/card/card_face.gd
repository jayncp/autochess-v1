class_name CardFace
extends Node2D
## 卡面：完整卡 300×420 或紧凑卡 300×300，原点在卡牌中心。规范见 docs/design/art-direction.md 第 3 节。
## - 构筑阶段：时机和基础技能是 2×2 表格；紧凑卡是"时机图标 + 合并后的基础技能"；
## - 战斗中（start_live 之后）：同样是"时机图标 + 基础技能"，发动的时机发亮，战斗中改变的数值显示紫色，战斗力是当前值；
##   正在结算的技能方块、正在起作用的特殊技能栏亮起，战斗力变化时跳动，有庇护时罩着保护罩。
## 全部在 _draw 里画：布局按缩放 1 写，乘以 display_scale；文字按显示字号栅格化，缩小显示时也清楚。
## 卡图背景的渐变是子节点上的着色器（card_background.gdshader）。

const WIDTH := 300.0
const RADIUS := 16.0
## 自动缩字的下限（缩放 1 时的字号）
const MIN_FONT_SIZE := 8.0

## 完整卡、紧凑卡的布局（缩放 1）。卡图按比例放进框里、靠底居中；法阵给中心和边长
const LAYOUTS := {
	false: {
		"height": 420.0,
		"art": Rect2(10, 50, 280, 212), "equip_art": Rect2(10, 62, 280, 186),
		"pattern": Vector2(150, 158), "equip_pattern": Vector2(150, 152), "pattern_size": 300.0,
		"placeholder": Vector2(150, 150), "placeholder_size": 130.0, "fade": 190.0,
		"equip_box": Rect2(14, 146, 86, 106), "equip_image": Vector2(62, 58), "equip_name": 18.0, "equip_stars": 14.0,
		"special": Rect2(14, 260, 272, 58), "special_font": 21.0,
		"slots": Rect2(14, 325, 214, 81), "strength": Rect2(226, 325, 60, 81),
		"timing_box": Vector2(28, 24), "timing_icon": 23.0,
	},
	true: {
		"height": 300.0,
		"art": Rect2(50, 46, 200, 132), "equip_art": Rect2(50, 50, 200, 120),
		"pattern": Vector2(150, 112), "equip_pattern": Vector2(150, 112), "pattern_size": 230.0,
		"placeholder": Vector2(150, 112), "placeholder_size": 96.0, "fade": 150.0,
		"equip_box": Rect2(14, 92, 70, 86), "equip_image": Vector2(46, 42), "equip_name": 16.0, "equip_stars": 12.0,
		"special": Rect2(14, 184, 272, 44), "special_font": 20.0,
		"slots": Rect2(14, 234, 214, 54), "strength": Rect2(226, 234, 60, 54),
		"timing_box": Vector2(28, 20), "timing_icon": 19.0,
	},
}

const RACE_COLORS := {
	"human": Color("f28c28"), "beast": Color("e5483b"), "divine": Color("f2c94c"),
	"nature": Color("5dbb46"), "elf": Color("29c4d6"), "treasure": Color("f07cc0"),
}
const TIMING_COLORS := {"pre_battle": Color("33d0e2"), "on_enter": Color("66cc4c"), "on_engage": Color("f0503f")}
## 基础技能方块：所属种族色的浅色版（湮灭不属于任何种族，用灰紫）
const CHIP_COLORS := {
	"rage": Color("ff9d92"), "rally": Color("ffb66e"), "support": Color("8be8f2"), "inspire": Color("ffe07a"),
	"corrode": Color("a8e68c"), "annihilate": Color("d3cede"), "wealth": Color("fab5dd"),
}
## 按星级（下标是星级）：法阵和面板的线色、星星颜色、装备底色
const TIER_LINE: Array[Color] = [Color(), Color("b4bcc6"), Color("dcab6a"), Color("eef4ff"), Color("ffd866"), Color("e6d4ff")]
const TIER_STAR: Array[Color] = [Color(), Color("d9dee5"), Color("e8b878"), Color("ffffff"), Color("ffd84a"), Color("ffffff")]
const EQUIP_BG: Array[Color] = [Color(), Color("4b525e"), Color("7c5a32"), Color("4d6a90"), Color("8c6a12"), Color("5a3d93")]
## 棱彩：星星逐颗换色，装备背景是彩虹
const PRISM_STARS: Array[Color] = [Color("ff9ad8"), Color("ffd56e"), Color("8af5c6"), Color("7ab8ff"), Color("c58aff")]
const PRISM_BACKGROUND: Array[Color] = [Color("6a3fb0"), Color("2f6fb8"), Color("2aa58a"), Color("b8962e"), Color("b04a8a")]
const DARK := Color("070a14")
## 还没有卡图时的种族图标、虚线六边形
const PLACEHOLDER := Color(1, 1, 1, 0.35)
const CHIP_TEXT := Color("141414")
## 战斗中改变的数值：方块里的紫字和紫框，特殊技能的浅紫字
const CHANGED_TEXT := Color("7a12b0")
const CHANGED_RING := Color("c58aff")
const CHANGED_SPECIAL := Color("dcb0ff")

const SANS := preload("res://assets/fonts/sans.tres")
const SANS_MEDIUM := preload("res://assets/fonts/sans_medium.tres")
const SANS_BOLD := preload("res://assets/fonts/sans_bold.tres")
const SERIF := preload("res://assets/fonts/serif_heavy.tres")
const BACKGROUND_SHADER := preload("res://scenes/components/card/card_background.gdshader")
const CHIP := preload("res://assets/ui/card/chip.png")
const DIAMOND := preload("res://assets/ui/theme/diamond.png")
## 描边版图标（*_outline.png）四周各留了 4 格给描边：48 格的图标画成 56 格
const OUTLINE_ICON_SCALE := 56.0 / 48.0

## 卡图底部压暗（卡图融进下面的面板）、发动时机的光晕
static var _fade: GradientTexture2D
static var _glow: GradientTexture2D
## 画过的纹理：绘制命令只记纹理的 RID，要一直持有引用，否则 _draw 结束后纹理被释放，画出来是白块
static var _textures := {}

## 紧凑卡（300×300）
var compact := false:
	set(value):
		compact = value
		_refresh()
## 显示缩放：0.6 时和旧卡一样大（180×252）
var display_scale := 0.6:
	set(value):
		display_scale = value
		_refresh()
## 战斗实时状态：strength、timings、base_skills、special_skills、firing（正在发动的时机）；空表示构筑阶段
var live := {}
## 拖动中：金色外框加光晕、投影
var glow := false:
	set(value):
		glow = value
		_halo.queue_redraw()
## 叠压的手牌：一圈柔和的投影，把前后两张分开
var shadow := false:
	set(value):
		shadow = value
		_halo.queue_redraw()
## 战斗中在交战位：红色外框加红光
var engaged := false:
	set(value):
		engaged = value
		_halo.queue_redraw()
## 战斗中正在结算的基础技能：这个方块亮起（白框、外发光、放大）；空字符串表示没有
var firing_skill := "":
	set(value):
		firing_skill = value
		queue_redraw()
## 战斗中特殊技能正在起作用（发动，或受击时庇护、坚固挡伤害）：特殊技能栏亮起
var firing_special := false:
	set(value):
		firing_special = value
		queue_redraw()

var _character := {}
var _equipment := {}
var _origin := {}  # 开战时的实时状态，用来标出战斗中改变的数值
var _offset := Vector2.ZERO  # 左上角（像素）
var _background := ColorRect.new()
var _halo := Node2D.new()  # 光晕和投影：画在卡面背后
## 战斗力跳动的进度（1 → 0，由 pulse_strength 的补间推进）和方向
var _pulse := 0.0:
	set(value):
		_pulse = value
		queue_redraw()
var _pulse_up := true
var _pulse_tween: Tween


static func _static_init() -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, 0.5, 0.88, 1])
	fade.colors = PackedColorArray([Color(DARK, 0), Color(DARK, 0.8), DARK, DARK])
	_fade = GradientTexture2D.new()
	_fade.gradient = fade
	_fade.width = 4
	_fade.height = 64
	_fade.fill_to = Vector2(0, 1)
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0, 0.75])
	glow.colors = PackedColorArray([Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = glow
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1, 0.5)


## 卡图的纹理；还没有卡图时返回 null（卡面上画淡显的种族图标或虚线六边形）
static func art(id: String) -> Texture2D:
	var path := "res://assets/cards/%s.png" % id
	return cached_texture(path) if ResourceLoader.exists(path) else null


## 带缓存地加载纹理：在 _draw 里画的纹理都要用它取（见 _textures）
static func cached_texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


func _init() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_halo.show_behind_parent = true
	_halo.draw.connect(_draw_halo)
	add_child(_halo)
	_background.show_behind_parent = true
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.material = ShaderMaterial.new()
	add_child(_background)


## 显示角色（可带装备）或单独的装备，回到构筑阶段的样子
func show_cards(card_id: String, equip_id: String) -> void:
	_character = CardDB.card(card_id) if card_id else {}
	_equipment = CardDB.card(equip_id) if equip_id else {}
	live = {}
	_refresh()


## 进入战斗实时状态；unit 是 BattleSim 开战时的单位属性
func start_live(unit: Dictionary) -> void:
	live = {
		"strength": unit.strength,
		"timings": unit.timings.duplicate(),
		"base_skills": unit.base_skills.duplicate(),
		"special_skills": unit.special_skills.duplicate(),
		"firing": "",
	}
	_origin = live.duplicate(true)
	queue_redraw()
	_halo.queue_redraw()


func set_strength(value: int) -> void:
	live.strength = value
	queue_redraw()


## 战斗力变化时数字放大回弹，带绿光（增）或红光（减），duration 秒内恢复
func pulse_strength(up: bool, duration: float) -> void:
	_pulse_up = up
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "_pulse", 0.0, duration).from(1.0)


## 特殊技能（庇护被消耗、用完时移除）；保护罩跟着庇护有没有
func set_specials(specials: Dictionary) -> void:
	live.special_skills = specials.duplicate()
	queue_redraw()
	_halo.queue_redraw()


## 复制另一张卡的实时状态（点卡查看时，放大的卡和场上的一样，改变的数值也标紫）
func copy_live(other: CardFace) -> void:
	live = other.live.duplicate(true)
	_origin = other._origin.duplicate(true)
	queue_redraw()
	_halo.queue_redraw()


## 正在发动的时机（这张卡有这个时机时图标发亮）；空字符串表示没有
func set_firing(timing: String) -> void:
	live.firing = timing
	queue_redraw()


## 显示尺寸（像素）
func get_size() -> Vector2:
	return Vector2(WIDTH, _layout().height) * display_scale


func _layout() -> Dictionary:
	return LAYOUTS[compact]


func _refresh() -> void:
	var size := get_size()
	_offset = -size / 2
	_background.position = _offset
	_background.size = size
	_update_background()
	_halo.queue_redraw()
	queue_redraw()


## 背景：角色按种族色（多种族按扇区融合），装备按星级色；外圈压暗、圆角在着色器里
func _update_background() -> void:
	_background.visible = not (_character.is_empty() and _equipment.is_empty())
	if _background.visible:
		apply_background(_background.material, _character, _equipment, _background.size, RADIUS * display_scale)


## 设置背景着色器（card_background.gdshader）的参数；装备框、关卡里的头像也用。radius 等于边长一半时是圆
static func apply_background(shader: ShaderMaterial, character: Dictionary, equipment: Dictionary, size: Vector2, radius: float) -> void:
	shader.shader = BACKGROUND_SHADER
	shader.set_shader_parameter("size", size)
	shader.set_shader_parameter("radius", radius)
	var colors: Array[Color] = []
	var mode := 0
	if character:
		colors.assign(CardDB.sorted_races(character.races).map(func(r): return RACE_COLORS[r].lerp(Color.WHITE, 0.12)))
		if colors.size() == 1:
			colors = _radial(colors[0], 0.4, 0.1)
			shader.set_shader_parameter("mid_stop", 0.4)
		else:
			mode = 1
			shader.set_shader_parameter("solid", 1 - 1 / 2.2)
			shader.set_shader_parameter("start_angle", -180.0 / colors.size())
	elif equipment.star == 5:
		mode = 1
		colors = PRISM_BACKGROUND.duplicate()
		shader.set_shader_parameter("solid", 0.0)
		shader.set_shader_parameter("start_angle", 0.0)
	else:
		colors = _radial(EQUIP_BG[equipment.star], 0.45, 0.15)
		shader.set_shader_parameter("mid_stop", 0.45)
	shader.set_shader_parameter("mode", mode)
	shader.set_shader_parameter("count", colors.size())
	colors.resize(5)
	shader.set_shader_parameter("colors", PackedColorArray(colors))


## 径向渐变的三个颜色：中心、中段（各混一些白）、边缘（混一些暗色）
static func _radial(base: Color, center_white: float, mid_white: float) -> Array[Color]:
	return [base.lerp(Color.WHITE, center_white), base.lerp(Color.WHITE, mid_white), base.lerp(DARK, 0.25)]


func _draw() -> void:
	var main := _character if _character else _equipment
	if main.is_empty():
		return
	var layout := _layout()
	var tier: int = main.star
	_unit_space()
	_draw_pattern(layout, tier)
	_draw_art(layout, main)
	draw_texture_rect(_fade, Rect2(6, layout.height - layout.fade, WIDTH - 12, layout.fade - 6), false)
	var frame := cached_texture("res://assets/ui/card/%s_%d.png" % ["frame_compact" if compact else "frame", tier])
	draw_texture_rect(frame, Rect2(-32, -32, WIDTH + 64, layout.height + 64), false)
	_draw_header(main, tier)
	if _character and _equipment:
		_draw_equip_box(layout)
	_draw_panels(layout, tier)


## 光晕和投影（StyleBoxFlat 的阴影画成柔和的边）：庇护的保护罩、交战位的红框、拖动和出列的金光、叠压的投影
func _draw_halo() -> void:
	if _character.is_empty() and _equipment.is_empty():
		return
	var rect := Rect2(_offset, get_size())
	if live and live.special_skills.get("shelter", 0) > 0:
		_draw_shelter(rect)
	if engaged and not glow:
		var red := StyleBoxFlat.new()
		red.draw_center = false
		red.set_corner_radius_all(roundi((RADIUS + 3) * display_scale))
		red.border_color = Color(1, 0.43, 0.35, 0.85)
		red.set_border_width_all(2)
		red.set_expand_margin_all(7 * display_scale)
		red.shadow_color = Color(1, 0.35, 0.27, 0.55)
		red.shadow_size = roundi(18 * display_scale)
		_halo.draw_style_box(red, rect)
	if not (glow or shadow):
		return
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(roundi(RADIUS * display_scale))
	if glow:
		box.shadow_color = Color(0, 0, 0, 0.6)
		box.shadow_size = roundi(28 * display_scale)
		box.shadow_offset = Vector2(0, 24) * display_scale
		_halo.draw_style_box(box, rect)
		box.shadow_color = Color(1, 0.84, 0.47, 0.5)
		box.shadow_size = roundi(26 * display_scale)
		box.shadow_offset = Vector2.ZERO
		box.border_color = Color(1, 0.925, 0.667, 0.9)
		box.set_border_width_all(3)
		box.set_expand_margin_all(3)
	else:
		box.shadow_color = Color(0, 0, 0, 0.5)
		box.shadow_size = roundi(16 * display_scale)
		box.shadow_offset = Vector2(-4, 8) * display_scale
	_halo.draw_style_box(box, rect)


## 庇护的保护罩：有庇护（层数大于 0）时一直罩着，多层和单层一样。卡外一圈淡金的光带、细金边、外发光
func _draw_shelter(rect: Rect2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 0.9, 0.6, 0.16)
	box.set_corner_radius_all(roundi(26 * display_scale))
	box.set_expand_margin_all(14 * display_scale)
	box.border_color = Color(1, 0.97, 0.82)
	box.set_border_width_all(2)
	box.shadow_color = Color(1, 0.84, 0.47, 0.5)
	box.shadow_size = roundi(16 * display_scale)
	_halo.draw_style_box(box, rect)


# ---------- 卡图区 ----------

## 法阵：角色是圆形法阵，装备是六边形附魔阵，颜色和复杂度随星级
func _draw_pattern(layout: Dictionary, tier: int) -> void:
	var texture := cached_texture("res://assets/ui/card/%s_%d.png" % ["circle" if _character else "array", tier])
	var center: Vector2 = layout.pattern if _character else layout.equip_pattern
	var size: Vector2 = Vector2.ONE * layout.pattern_size
	draw_texture_rect(texture, Rect2(center - size / 2, size), false, Color(1, 1, 1, 0.85))


## 卡图；还没有卡图时画占位
func _draw_art(layout: Dictionary, main: Dictionary) -> void:
	var texture := art(main.id)
	if texture:
		_draw_contained(texture, layout.art if _character else layout.equip_art)
	else:
		draw_placeholder(self, main, layout.placeholder, layout.placeholder_size)


## 还没有卡图：角色画第一种族的大图标，装备画虚线六边形（按 48 格的图标画），都淡显；size 是边长
static func draw_placeholder(canvas: CanvasItem, data: Dictionary, center: Vector2, size: float) -> void:
	if data.type == "character":
		var icon := cached_texture("res://assets/ui/icons/%s.png" % CardDB.sorted_races(data.races)[0])
		canvas.draw_texture_rect(icon, Rect2(center - Vector2.ONE * size / 2, Vector2.ONE * size), false, PLACEHOLDER)
		return
	var points := [Vector2(24, 3), Vector2(42, 13.5), Vector2(42, 34.5), Vector2(24, 45), Vector2(6, 34.5), Vector2(6, 13.5)]
	points = points.map(func(p): return center + (p - Vector2(24, 24)) * size / 48)
	for i in points.size():
		canvas.draw_dashed_line(points[i], points[(i + 1) % points.size()], PLACEHOLDER, 2.5 * size / 48, 5 * size / 48)


## 按比例放进 box，靠底居中
func _draw_contained(texture: Texture2D, box: Rect2) -> void:
	var size := texture.get_size() * minf(box.size.x / texture.get_width(), box.size.y / texture.get_height())
	draw_texture_rect(texture, Rect2(box.position.x + (box.size.x - size.x) / 2, box.end.y - size.y, size.x, size.y), false)


## 直接压在卡图上的：左上星级（竖排）、上中卡名、右上种族图标（竖排），都带黑色描边
func _draw_header(main: Dictionary, tier: int) -> void:
	for i in tier:
		_text("★", SANS, Vector2(31.5, 31.5 + i * 23), 23, PRISM_STARS[i] if tier == 5 else TIER_STAR[tier], 3)
	_text(tr("card." + main.id), SERIF, Vector2(150, 36), 30, Color.WHITE, 4, 208, true)
	if _character:
		var races := CardDB.sorted_races(_character.races)
		for i in races.size():
			_outline_icon(races[i], Vector2(266.5, 34.5 + i * 33), 29, RACE_COLORS[races[i]])


## 角色身上的装备：左侧中部的小框，星级、图标、名称；底色随装备的星级
func _draw_equip_box(layout: Dictionary) -> void:
	var box: Rect2 = layout.equip_box
	var tier: int = _equipment.star
	draw_texture_rect(cached_texture("res://assets/ui/card/equip_box_%d.png" % tier), box, false)
	var x := box.get_center().x
	var y := box.position.y + 2
	var stars_height: float = layout.equip_stars * 1.2
	_text("★".repeat(tier), SANS, Vector2(x, y + stars_height / 2), layout.equip_stars, TIER_STAR[tier], 2)
	y += stars_height
	var image: Vector2 = layout.equip_image
	var texture := art(_equipment.id)
	if texture:
		_draw_contained(texture, Rect2(x - image.x / 2, y, image.x, image.y))
	else:
		draw_placeholder(self, _equipment, Vector2(x, y + image.y / 2), image.y)
	y += image.y
	_text(tr("card." + _equipment.id), SANS_BOLD, Vector2(x, y + layout.equip_name * 0.6), layout.equip_name, Color.WHITE, 3, box.size.x - 6)


# ---------- 面板 ----------

func _draw_panels(layout: Dictionary, tier: int) -> void:
	var special := _special_parts()
	var rect: Rect2 = layout.special
	var mid := rect.get_center()
	_panel(rect, tier, [Vector2(rect.position.x, mid.y), Vector2(rect.end.x, mid.y)], 1.0 if special else 0.6)
	if live and firing_special:
		_draw_lit(rect, Color.WHITE, 4, 14)
	_draw_special(special, rect.grow_individual(-12, -3, -12, -3), layout.special_font)

	rect = layout.slots
	_panel(rect, tier, [Vector2(rect.get_center().x, rect.position.y)])
	if live or compact:
		_draw_merged(rect.grow(-3), tier)
	else:
		_draw_table(rect.grow(-3), tier)

	rect = layout.strength
	mid = rect.get_center()
	_panel(rect, tier, [Vector2(mid.x, rect.position.y), Vector2(mid.x, rect.end.y)])
	var strength := ""
	if live:
		strength = str(live.strength)
	elif _character:
		strength = str(_character.strength + _equipment.get("strength", 0))
	elif _equipment.has("strength"):
		strength = "+%d" % _equipment.strength
	# 战斗力跳动：先放大、带绿光或红光，再回到原样
	var grow := 1 + 0.28 * _pulse * _pulse
	var tint := Color("b9ffc6") if _pulse_up else Color("ffc0b8")
	var glow_color := Color(Color("3dff6a") if _pulse_up else Color("ff4a3a"), 0.7 * _pulse)
	_text(strength, SANS_BOLD, mid, (46 if _character else 36) * grow, Color.WHITE.lerp(tint, _pulse), 4, (rect.size.x - 4) * grow, false, glow_color)


## 亮起的框（像素坐标画，细线不随缩放变粗）：白框加外发光；rect 是缩放 1 的坐标
func _draw_lit(rect: Rect2, glow_color: Color, radius: float, glow_size: float) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_corner_radius_all(roundi(radius * display_scale))
	box.border_color = Color.WHITE
	box.set_border_width_all(2)
	box.shadow_color = Color(glow_color, 0.6)
	box.shadow_size = roundi(glow_size * display_scale)
	_pixel_space()
	draw_style_box(box, Rect2(rect.position * display_scale, rect.size * display_scale))
	_unit_space()


## 面板：深蓝底、细线（颜色随星级），边上的菱形点缀
func _panel(rect: Rect2, tier: int, diamonds: Array, alpha := 1.0) -> void:
	var texture := cached_texture("res://assets/ui/card/panel_%d.png" % tier)
	nine_patch(self, texture, rect, 7, Color(1, 1, 1, alpha))
	for point in diamonds:
		draw_texture_rect(DIAMOND, Rect2(point - Vector2(5, 5), Vector2(10, 10)), false, Color(TIER_LINE[tier], alpha))


## 构筑阶段：时机、基础技能各两格；装备卡直接显示它填在哪一格（"空"表示清空）
func _draw_table(area: Rect2, tier: int) -> void:
	var line := Color(TIER_LINE[tier], 0.4)
	var column := area.position.x + 52
	var middle := area.get_center().y
	draw_line(Vector2(column, area.position.y), Vector2(column, area.end.y), line, 1)
	draw_line(Vector2(area.position.x, middle), Vector2(area.end.x, middle), line, 1)
	draw_texture_rect(DIAMOND, Rect2(column - 4, middle - 4, 8, 8), false, TIER_LINE[tier])
	for row in 2:
		var top := area.position.y + row * area.size.y / 2
		var timing = _slot(CardDB.TIMING_SLOTS[row])
		var center := Vector2(area.position.x + 26, top + area.size.y / 4)
		if timing == CardDB.CLEAR:
			_text(tr("ui.card.clear"), SANS_BOLD, center, 19, Color(1, 1, 1, 0.6))
		elif timing:
			_text(tr("timing." + timing), SANS_BOLD, center, 19, TIMING_COLORS[timing], 2)
		var skills = _slot(CardDB.SKILL_SLOTS[row])
		var cell := Rect2(column + 4, top, area.end.x - column - 8, area.size.y / 2)
		if skills is String:
			_text(tr("ui.card.clear"), SANS_BOLD, cell.get_center(), 19, Color(1, 1, 1, 0.6))
		elif skills:
			_draw_chips(_chips(skills, skills), cell, false)


## 紧凑卡、战斗中：左边竖排这张卡有的时机图标，右边是合并后的基础技能，都按数量居中
func _draw_merged(area: Rect2, tier: int) -> void:
	var timings: Array
	var skills: Dictionary
	var origin: Dictionary
	if live:
		timings = live.timings
		skills = live.base_skills
		origin = _origin.base_skills
	else:
		var merged := CardDB.combine_data(_character if _character else {"strength": 0}, _equipment)
		timings = merged.timings
		skills = merged.base_skills
		origin = skills
	var column := Rect2(area.position, Vector2(36, area.size.y))
	draw_line(Vector2(column.end.x, area.position.y), Vector2(column.end.x, area.end.y), Color(TIER_LINE[tier], 0.4), 1)
	_draw_timing_icons(timings, column)
	_draw_chips(_chips(skills, origin), Rect2(column.end.x + 4, area.position.y, area.end.x - column.end.x - 8, area.size.y), true)


## 时机图标：发动时放大、加亮、带光晕
func _draw_timing_icons(timings: Array, column: Rect2) -> void:
	var layout := _layout()
	var box: Vector2 = layout.timing_box
	var y := column.get_center().y - (timings.size() * box.y + (timings.size() - 1) * 2) / 2
	for timing in timings:
		var center := Vector2(column.get_center().x, y + box.y / 2)
		var color: Color = TIMING_COLORS[timing]
		var size: float = layout.timing_icon
		if live and live.firing == timing:
			draw_texture_rect(_glow, Rect2(center - Vector2(22, 22), Vector2(44, 44)), false, color)
			color = Color(color.r * 1.35, color.g * 1.35, color.b * 1.35)
			size *= 1.12
		_outline_icon(timing, center, size, color)
		y += box.y + 2


## 卡面上某一格的内容：装备有这格就显示装备的，否则显示角色的
func _slot(slot: String) -> Variant:
	return _equipment[slot] if _equipment.has(slot) else _character.get(slot)


# ---------- 基础技能方块 ----------

## 方块：[名称, 数值, 底色, 是否在战斗中改变, 技能 id]，按显示顺序
func _chips(skills: Dictionary, origin: Dictionary) -> Array:
	return CardDB.sorted_skills(skills).map(func(skill): return [
		tr("keyword." + skill), str(skills[skill]), CHIP_COLORS[skill], origin.get(skill) != skills[skill], skill])


## 方块按行排开，每行居中、整体垂直居中；放不下就缩字。wrap 为假时只排一行
func _draw_chips(chips: Array, area: Rect2, wrap: bool) -> void:
	if chips.is_empty():
		return
	var k := display_scale
	var gap := 4 * k
	var px := _px(20)
	var rows := _chip_rows(chips, px, area.size.x * k, gap, wrap)
	while px > _px(MIN_FONT_SIZE) and (rows.is_empty() or rows.size() * roundf(px * 1.5) + (rows.size() - 1) * gap > area.size.y * k):
		px -= 1
		rows = _chip_rows(chips, px, area.size.x * k, gap, wrap)
	if rows.is_empty():
		rows = [chips.map(func(chip): return [chip, chip_width(chip, px)])]
	var height := roundf(px * 1.5)
	var y := area.get_center().y * k - (rows.size() * height + (rows.size() - 1) * gap) / 2
	_pixel_space()
	var firing := []  # 正在结算的方块放大了，最后画，压在旁边的方块上面
	for row in rows:
		var width: float = row.reduce(func(sum, item): return sum + item[1], 0.0) + (row.size() - 1) * gap
		var x := area.get_center().x * k - width / 2
		for item in row:
			var rect := Rect2(x, y, item[1], height)
			if live and item[0][4] == firing_skill:
				firing = [item[0], rect]
			else:
				draw_chip(self, item[0], rect, px)
			x += item[1] + gap
		y += height + gap
	if firing:
		# 放大 1.16，白框，外发光用方块的颜色
		var rect: Rect2 = firing[1]
		var big := Rect2(rect.get_center() - rect.size * 0.58, rect.size * 1.16)
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_corner_radius_all(roundi(4 * k))
		box.border_color = Color.WHITE
		box.set_border_width_all(2)
		box.set_expand_margin_all(2)
		box.shadow_color = Color(firing[0][2], 0.9)
		box.shadow_size = roundi(12 * k)
		draw_style_box(box, big)
		draw_chip(self, firing[0], big, roundi(px * 1.16))
	_unit_space()


## 贪心分行；有方块比整行还宽，或不换行却排不下时返回空
func _chip_rows(chips: Array, px: int, width: float, gap: float, wrap: bool) -> Array:
	var rows := [[]]
	var used := 0.0
	for chip in chips:
		var w := chip_width(chip, px)
		if w > width:
			return []
		if rows[-1] and used + gap + w > width:
			if not wrap:
				return []
			rows.append([])
			used = 0.0
		used += (gap if rows[-1] else 0.0) + w
		rows[-1].append([chip, w])
	return rows


## 方块的宽度（像素）：左右留 0.32 个字，名称和数值之间 0.1 个字
static func chip_width(chip: Array, px: int) -> float:
	return SANS_MEDIUM.get_string_size(chip[0] + chip[1], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + px * 0.74


## 一个基础技能方块（像素坐标）：种族色底、黑字；战斗中改变的是紫字加紫框。图鉴的筛选和词条说明也用
static func draw_chip(canvas: CanvasItem, chip: Array, rect: Rect2, px: int) -> void:
	if chip[3]:
		canvas.draw_rect(rect.grow(3), Color(CHANGED_RING, 0.35), false, 2)
		canvas.draw_rect(rect.grow(1.5), CHANGED_RING, false, 2)
	nine_patch(canvas, CHIP, rect, 4, chip[2])
	var color := CHANGED_TEXT if chip[3] else CHIP_TEXT
	var baseline := rect.get_center().y + (SANS_MEDIUM.get_ascent(px) - SANS_MEDIUM.get_descent(px)) / 2
	var x := rect.position.x + px * 0.32
	canvas.draw_string(SANS_MEDIUM, Vector2(x, baseline), chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	x += SANS_MEDIUM.get_string_size(chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + px * 0.1
	canvas.draw_string(SANS_MEDIUM, Vector2(x, baseline), chip[1], HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


# ---------- 特殊技能 ----------

## 特殊技能分段：[文字, 字体, 颜色]。词条加粗；描述型写整句；战斗中改变的显示浅紫。
## 数值降到 0 的词条（如庇护用完）已经移除，不显示
func _special_parts() -> Array:
	var skills = live.special_skills if live else _slot("special_skills")
	if skills == null:
		return []
	if skills is String:
		return [[tr("ui.card.clear"), SANS_BOLD, Color(1, 1, 1, 0.6)]]
	var parts := []
	for skill in CardDB.sorted_skills(skills):
		if parts:
			parts.append([tr("ui.card.special_separator"), SANS, Color(1, 1, 1, 0.7)])
		var changed: bool = live and skills[skill] != _origin.special_skills.get(skill)
		var font := SANS if skill in CardDB.DESCRIPTIVE_SPECIALS else SANS_BOLD
		parts.append([load_card.one_skill_text(skill, skills[skill]), font, CHANGED_SPECIAL if changed else Color.WHITE])
	return parts


## 分段排成居中的多行文字（行高 1.2 倍），放不下就缩字
func _draw_special(parts: Array, area: Rect2, max_size: float) -> void:
	if parts.is_empty():
		return
	var k := display_scale
	var px := _px(max_size)
	var paragraph := _paragraph(parts, px, area.size.x * k)
	while px > _px(MIN_FONT_SIZE) and paragraph.get_line_count() * roundf(px * 1.2) > area.size.y * k:
		px -= 1
		paragraph = _paragraph(parts, px, area.size.x * k)
	# 逐字画，按字所在的分段取颜色
	var ends := []
	var length := 0
	for part in parts:
		length += part[0].length()
		ends.append(length)
	var server := TextServerManager.get_primary_interface()
	var line_height := roundf(px * 1.2)
	var top := area.get_center().y * k - paragraph.get_line_count() * line_height / 2
	_pixel_space()
	for i in paragraph.get_line_count():
		var x := area.get_center().x * k - paragraph.get_line_width(i) / 2
		var baseline := top + i * line_height + (line_height + paragraph.get_line_ascent(i) - paragraph.get_line_descent(i)) / 2
		for glyph in server.shaped_text_get_glyphs(paragraph.get_line_rid(i)):
			var color: Color = parts[mini(ends.bsearch(glyph.start, false), parts.size() - 1)][2]
			for _r in glyph.repeat:
				if glyph.font_rid.is_valid():
					server.font_draw_glyph(glyph.font_rid, get_canvas_item(), glyph.font_size, Vector2(x, baseline) + glyph.offset, glyph.index, color)
				x += glyph.advance
	_unit_space()


func _paragraph(parts: Array, px: int, width: float) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	for part in parts:
		paragraph.add_string(part[0], part[1], px)
	return paragraph


# ---------- 绘制工具 ----------

## 默认在缩放 1 的坐标里画（纹理、线条按 display_scale 缩放）；文字临时切到像素坐标，按显示字号栅格化
func _unit_space() -> void:
	draw_set_transform(_offset, 0, Vector2.ONE * display_scale)


func _pixel_space() -> void:
	draw_set_transform(_offset)


## 缩放 1 的字号换成显示字号
func _px(size: float) -> int:
	return maxi(1, roundi(size * display_scale))


## 一行字，以 center 为中心；size、outline、max_width 都是缩放 1 的值。放不下 max_width 就逐级缩小；glow 不透明时描边外再加一圈光
func _text(text: String, font: Font, center: Vector2, size: float, color: Color, outline := 0.0, max_width := 0.0, shadow := false,
		glow := Color(0, 0, 0, 0)) -> void:
	if text.is_empty():
		return
	var k := display_scale
	var px := _px(size)
	while max_width > 0 and px > _px(MIN_FONT_SIZE) and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_width * k:
		px -= 1
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var at := center * k + Vector2(-width / 2, (font.get_ascent(px) - font.get_descent(px)) / 2)
	_pixel_space()
	if glow.a > 0:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline + 12), glow)
	if shadow:
		draw_string_outline(font, at + Vector2(0, 3 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline + 2), Color(0, 0, 0, 0.6))
	if outline > 0:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline), Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	_unit_space()


## 带黑色描边的图标，以 center 为中心，size 是图标本身的边长
func _outline_icon(id: String, center: Vector2, size: float, color: Color) -> void:
	var box := Vector2.ONE * size * OUTLINE_ICON_SCALE
	draw_texture_rect(cached_texture("res://assets/ui/icons/%s_outline.png" % id), Rect2(center - box / 2, box), false, color)


## 九宫格贴图（四边按 margin 不拉伸），modulate 上色
static func nine_patch(canvas: CanvasItem, texture: Texture2D, rect: Rect2, margin: float, modulate_color: Color) -> void:
	RenderingServer.canvas_item_add_nine_patch(canvas.get_canvas_item(), rect, Rect2(Vector2.ZERO, texture.get_size()), texture.get_rid(),
		Vector2(margin, margin), Vector2(margin, margin), RenderingServer.NINE_PATCH_STRETCH, RenderingServer.NINE_PATCH_STRETCH, true, modulate_color)
