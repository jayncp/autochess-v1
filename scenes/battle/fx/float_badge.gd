class_name FloatBadge
extends Node2D
## 飘字，规格见 docs/plans/effects-pacing.md 第 3 节。四类：
## - 基础技能：技能色的名称加带纹样的饰板，后面是数值；
## - 词条：银边饰板，左边圆章里是词条图标，白字，改了战斗力的带数值；
## - 角色专属效果：白色宋体卡名，改了战斗力的带数值；
## - 交战伤害：只有数字，比其他飘字大一号。
## 按缩放 1 排版（高 64，原点在中心，饰板在 y -20–20），乘以 display_scale；文字按显示字号栅格化。
## 饰板贴图由 tools/autochess_tools/art/fx.py 生成，四周各留 PAD 给纹样和外发光。
## 压在一张卡的卡图中间、跟着卡移动；自己播放弹出、上浮、淡出，播完自己删掉（叠放由 BadgeLayer 管）。

enum Kind { SKILL, KEYWORD, NAME, CLASH }

## 停留时间（1 倍速，秒）：弹出 0.12，最后 0.3 上浮淡出
const LIFE := 1.1
const POP := 0.06
const FADE := 0.3
## 同一张卡上后弹出的飘字在原位，先弹出的往上推这么多（缩放 1）
const STACK := 58.0
## 卡图中心相对卡牌中心（缩放 1 的完整卡）
const ART_Y := -60.0
const PAD := 16.0
const CAP := 48.0
const MEDAL := 60.0
const TIP := 28.0
const GAP := 8.0
## 基础技能的名称颜色（技能方块的颜色）
const SKILL_COLORS := {
	"rage": Color("ff9d92"), "rally": Color("ffb66e"), "support": Color("8be8f2"), "inspire": Color("ffe07a"),
	"corrode": Color("a8e68c"), "annihilate": Color("d3cede"), "wealth": Color("fab5dd"),
}
## 数值：战斗力加绿减红；财富金色；层数这类不是战斗力的白色
const UP := Color("6dff8a")
const DOWN := Color("ff5f52")
const COIN := Color("ffd56e")
const ZERO := Color("cfcfcf")
const SERIF := preload("res://assets/fonts/serif_heavy.tres")
const SANS_BOLD := preload("res://assets/fonts/sans_bold.tres")

var kind := Kind.SKILL
## 基础技能或词条的 id（决定饰板）
var id := ""
var text := ""
## 数值文字和颜色；空字符串表示不显示
var number := ""
var number_color := Color.WHITE
var display_scale := 0.6
## 跟着的卡（卡牌根节点，原点在卡牌中心）
var card: Node2D
## 被后来的飘字往上推的量（缩放 1），BadgeLayer 设置，这里平滑地跟过去
var push := 0.0
## 播放速度
var speed := 1.0

var _time := 0.0
var _push_shown := 0.0
var _anchor := Vector2.ZERO


## 基础技能：n 是战斗力变化（财富是金币数）；null 表示只显示名称
static func skill(skill_id: String, n: Variant = null) -> FloatBadge:
	var badge := FloatBadge.new()
	badge.id = skill_id
	badge.text = TranslationServer.translate("keyword." + skill_id)
	badge._set_number(n, COIN if skill_id == "wealth" else Color())
	return badge


## 词条：n 是战斗力变化；count 为真时 n 是层数（白字，如"庇护 +2"）
static func keyword(keyword_id: String, n: Variant = null, count := false) -> FloatBadge:
	var badge := FloatBadge.new()
	badge.kind = Kind.KEYWORD
	badge.id = keyword_id
	badge.text = TranslationServer.translate("keyword." + keyword_id)
	badge._set_number(n, Color.WHITE if count else Color())
	return badge


## 角色专属效果：卡名，n 是持有者自己的战斗力变化
static func card_name(card_id: String, n: Variant = null) -> FloatBadge:
	var badge := FloatBadge.new()
	badge.kind = Kind.NAME
	badge.text = TranslationServer.translate("card." + card_id)
	badge._set_number(n, Color())
	return badge


## 交战伤害：n 是战斗力变化，致命命中传 -INF（显示 −∞）
static func clash(n: float) -> FloatBadge:
	var badge := FloatBadge.new()
	badge.kind = Kind.CLASH
	badge._set_number(n, Color())
	return badge


## 带符号的数值：+3、−6（减号用 U+2212）、−∞
static func signed(n: float) -> String:
	if is_inf(n):
		return "−∞"
	if n > 0:
		return "+%d" % n
	return "−%d" % -n if n < 0 else "0"


## color 为空时按正负取绿、红
func _set_number(n: Variant, color: Color) -> void:
	if n == null:
		return
	number = signed(n)
	number_color = color if color != Color() else (UP if n > 0 else DOWN if n < 0 else ZERO)


func _init() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	z_index = 100


func _process(delta: float) -> void:
	_time += delta * speed
	if _time >= LIFE:
		queue_free()
		return
	var pop := 1.0
	if _time < POP:
		pop = lerpf(0.5, 1.15, _time / POP)
	elif _time < 2 * POP:
		pop = lerpf(1.15, 1.0, (_time - POP) / POP)
	var fade := maxf(0.0, (_time - (LIFE - FADE)) / FADE)
	_push_shown = move_toward(_push_shown, push, STACK * delta * speed / 0.1)
	if is_instance_valid(card):
		_anchor = card.position + Vector2(0, ART_Y * display_scale * card.scale.y)
	position = _anchor - Vector2(0, (_time * 12 + fade * 34 + _push_shown) * display_scale)
	scale = Vector2.ONE * pop
	modulate.a = 1 - fade


# ---------- 画 ----------

func _draw() -> void:
	match kind:
		Kind.SKILL:
			_draw_skill()
		Kind.KEYWORD:
			_draw_keyword()
		Kind.NAME:
			var name_width := _width(text, SERIF, 31)
			var total := name_width + (GAP + _width(number, SANS_BOLD, 35) if number else 0.0)
			var glow := Color(1, 1, 1, 0.3)
			_text(text, SERIF, -total / 2, 31, Color.WHITE, 6, glow)
			if number:
				_text(number, SANS_BOLD, -total / 2 + name_width + GAP, 35, number_color, 6, glow)
		Kind.CLASH:
			_text(number, SANS_BOLD, -_width(number, SANS_BOLD, 62) / 2, 62, number_color, 8, Color(1, 0.31, 0.24, 0.35))


## 基础技能：左端饰、拉伸的中段、右端饰（镜像，狂暴旋转 180°）；振奋加顶部光芒，腐蚀加底边水滴
func _draw_skill() -> void:
	var middle := _middle(27)
	var left := -(2 * CAP + middle) / 2
	var cap := _texture("cap_" + id)
	var cap_rect := Rect2(left - PAD, -32 - PAD, CAP + PAD, 64 + 2 * PAD)
	_unit_space()
	draw_texture_rect(cap, cap_rect, false)
	draw_texture_rect(_texture("mid_" + id), Rect2(left + CAP, -32 - PAD, middle, 64 + 2 * PAD), false)
	if id == "inspire":
		draw_texture_rect(_texture("crest"), Rect2(left + CAP + middle / 2 - 38, -48, 76, 36), false)
	if id == "corrode":
		draw_texture_rect(_texture("drip"), Rect2(left + CAP + middle * 0.62 - 4, 16, 20, 22), false)
	# 右端饰：以中心为轴镜像（或旋转 180°），和左端饰对称
	var flip := Transform2D(PI, Vector2.ONE, 0, Vector2.ZERO) if id == "rage" else Transform2D(0, Vector2(-1, 1), 0, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D(0, Vector2.ONE * display_scale, 0, Vector2.ZERO) * flip)
	draw_texture_rect(cap, cap_rect, false)
	var x := left + CAP + 2
	_text(text, SERIF, x, 27, SKILL_COLORS[id], 5)
	if number:
		_text(number, SANS_BOLD, x + _width(text, SERIF, 27) + GAP, 35, number_color, 5)


## 词条：左边圆章、拉伸的中段、右边尖头
func _draw_keyword() -> void:
	var middle := _middle(26)
	var left := -(MEDAL + middle + TIP) / 2
	_unit_space()
	draw_texture_rect(_texture("medal_" + id), Rect2(left - PAD, -32 - PAD, MEDAL + PAD, 64 + 2 * PAD), false)
	draw_texture_rect(_texture("kmid_" + id), Rect2(left + MEDAL, -32 - PAD, middle, 64 + 2 * PAD), false)
	draw_texture_rect(_texture("ktip_" + id), Rect2(left + MEDAL + middle, -32 - PAD, TIP + PAD, 64 + 2 * PAD), false)
	var x := left + MEDAL + 2
	_text(text, SERIF, x, 26, Color.WHITE, 5)
	if number:
		_text(number, SANS_BOLD, x + _width(text, SERIF, 26) + GAP, 35, number_color, 5)


## 中段的宽度：名称、数值和两边的留白
func _middle(name_size: float) -> float:
	var width := 2 + _width(text, SERIF, name_size) + 2
	if number:
		width += GAP + _width(number, SANS_BOLD, 35)
	return width


func _texture(name: String) -> Texture2D:
	return CardFace.cached_texture("res://assets/ui/fx/%s.png" % name)


func _unit_space() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * display_scale)


## 文字宽度（缩放 1）
func _width(value: String, font: Font, size: float) -> float:
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(size)).x / display_scale


func _px(size: float) -> int:
	return maxi(1, roundi(size * display_scale))


## 一行字，左边在 x（缩放 1）、垂直居中；黑描边，glow 不透明时外面再加一圈光
func _text(value: String, font: Font, x: float, size: float, color: Color, outline: float, glow := Color(0, 0, 0, 0)) -> void:
	var px := _px(size)
	var at := Vector2(x * display_scale, (font.get_ascent(px) - font.get_descent(px)) / 2)
	draw_set_transform(Vector2.ZERO)
	if glow.a > 0:
		draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline + 12), glow)
	draw_string_outline(font, at + Vector2(0, 3 * display_scale), value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline + 2), Color(0, 0, 0, 0.6))
	draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _px(outline), Color.BLACK)
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
