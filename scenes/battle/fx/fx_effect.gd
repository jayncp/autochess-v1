class_name FxEffect
extends Node2D
## 一个战斗特效，规格见 docs/plans/effects-pacing.md 第 2 节。每帧按进度 p（0–1）重画，位置跟着卡算
## （卡在动时特效跟着），播完自己删掉。尺寸按缩放 1 写，乘以卡的显示缩放 k。由 FxLayer 生成。

enum Kind {
	ORB,           ## 光球：从 from 飞到 to（支援、振奋、湮灭）
	VENOM,         ## 毒液弹：抛物线飞到 to，拉长、冒泡、滴毒液（腐蚀）
	SPLASH,        ## 毒液溅开：一圈毒液、液滴落下、绿烟（腐蚀命中）
	SPARKS,        ## 光点：从 helpers 各飞一串汇到 to（集结）
	BURST,         ## 爆开的光（增益命中）
	CLAW,          ## 三道爪痕划过卡图（狂暴）
	COINS,         ## 金币弹起（财富）
	THREAD,        ## 白线：from 连到 to（角色专属效果）
	BEAM,          ## 光束：from 连到 to（唤醒）
	IMPACT,        ## 撞击：两张交战位中间的冲击光和光环
	FLASH,         ## 受击泛红
	SHIELD_HIT,    ## 庇护受击还有剩余层数：保护罩亮一圈
	SHIELD_BREAK,  ## 庇护用完：保护罩碎开
	STEEL,         ## 坚固：卡面上扫过一道金属光
	THORNS,        ## 反噬：卡上炸开一圈尖刺
	EMBERS,        ## 余烬：阵亡烧散时从卡上飘起
}

## 卡图中心相对卡牌中心（缩放 1 的完整卡）
const ART_Y := -60.0
const VENOM_COLORS: Array[Color] = [Color("24520f"), Color("5fae35"), Color("b9f08f"), Color("f4ffd8")]
const DROP := Color(0.56, 0.86, 0.36)
const GOLD_LIGHT := Color(1, 0.96, 0.8)

## 柔和的圆形光点（白色，用颜色调制）
static var _glow: GradientTexture2D

var kind := Kind.BURST
## 时长（1 倍速，秒）和播放速度
var duration := 0.4
var speed := 1.0
var from: Node2D
var to: Node2D
var helpers: Array = []
var color := Color.WHITE
var big := false

var _time := 0.0
var _k := 0.6
var _last := {}  # 卡被删掉后沿用最后的位置


static func _static_init() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.3, 1])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1, 0.5)
	_glow.width = 64
	_glow.height = 64


func _ready() -> void:
	var card := to if to else from
	_k = card.face.display_scale
	# 光类的特效叠加着画，更亮
	if kind in [Kind.ORB, Kind.SPARKS, Kind.BURST, Kind.IMPACT, Kind.BEAM, Kind.THREAD, Kind.EMBERS, Kind.SHIELD_HIT, Kind.SHIELD_BREAK, Kind.STEEL]:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive


func _process(delta: float) -> void:
	_time += delta * speed
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var p := _time / duration
	match kind:
		Kind.ORB:
			_draw_orb(p)
		Kind.VENOM:
			_draw_venom(p)
		Kind.SPLASH:
			_draw_splash(p)
		Kind.SPARKS:
			_draw_sparks(p)
		Kind.BURST:
			var radius := _size(to).x * 0.45 * (0.4 + _ease_out(p) * 0.9)
			_dot(_art(to), radius, Color(color, 1 - p))
		Kind.CLAW:
			_draw_claws(p)
		Kind.COINS:
			_draw_coins(p)
		Kind.THREAD:
			var a := _art(from)
			var end := a.lerp(_art(to), minf(1, p / 0.3))
			var alpha := 1.0 if p < 0.6 else (1 - p) / 0.4
			draw_line(a, end, Color(1, 1, 1, 0.3 * alpha), 10 * _k)
			draw_line(a, end, Color(1, 1, 1, 0.95 * alpha), 3)
		Kind.BEAM:
			var a := _art(from)
			var end := a.lerp(_art(to), minf(1, p / 0.4))
			var alpha := 1.0 if p < 0.6 else (1 - p) / 0.4
			draw_line(a, end, Color(color, 0.35 * alpha), 22 * _k)
			draw_line(a, end, Color(color, 0.8 * alpha), 9 * _k)
			draw_line(a, end, Color(1, 1, 1, alpha), 3 * _k)
		Kind.IMPACT:
			_draw_impact(p)
		Kind.FLASH:
			var size := _size(to)
			draw_texture_rect(_glow, Rect2(_center(to) + Vector2(-size.x * 0.7, -size.y * 0.75), Vector2(size.x * 1.4, size.y * 1.1)),
				false, Color(1, 0.24, 0.16, 0.55 * (1 - p)))
		Kind.SHIELD_HIT:
			_shield_box(_center(to), 1 + _ease_out(p) * 0.1, 1 - p, 3)
		Kind.SHIELD_BREAK:
			_draw_shield_break(p)
		Kind.STEEL:
			_draw_steel(p)
		Kind.THORNS:
			_draw_thorns(p)
		Kind.EMBERS:
			_draw_embers(p)


# ---------- 各种特效 ----------

## 光球：沿弧线飞过去（同一排拱得高些），拖着几颗渐小的光点
func _draw_orb(p: float) -> void:
	var a := _art(from)
	var b := _art(to)
	var lift := (90 if absf(a.y - b.y) < 50 else 40) * _k
	var fade := 1.0 if p < 0.95 else (1 - p) * 20
	for i in range(5, -1, -1):
		var point := _arc(a, b, _ease_in_out(clampf(p - i * 0.05, 0, 1)), lift)
		var radius := (1.3 if big else 1.0) * 15 * _k * (1 - i * 0.14)
		var alpha := (1 - i * 0.15) * fade
		_dot(point, radius * 2.2, Color(color, 0.7 * alpha))
		draw_circle(point, radius * 0.45, Color(1, 1, 1, alpha))


## 毒液弹：抛物线飞过去，沿飞行方向拉长，周围冒泡，身后滴下毒液
func _draw_venom(p: float) -> void:
	var a := _art(from)
	var b := _art(to)
	var lift := 80 * _k
	for i in 8:
		var emitted := (i + 1) * 0.11
		var age := (p - emitted) * duration
		if age > 0:
			var drop := _arc(a, b, emitted, lift) + Vector2(0, 900 * _k * age * age)
			draw_circle(drop, 6 * _k, Color(DROP, maxf(0, 1 - age / 0.4)))
	var point := _arc(a, b, p, lift)
	var angle := (_arc(a, b, minf(1, p + 0.02), lift) - point).angle()
	draw_set_transform(point, angle, Vector2(1.25, 0.88))
	_dot(Vector2.ZERO, 46 * _k, Color(0.47, 0.86, 0.31, 0.6))
	var radius := 21 * _k
	draw_circle(Vector2.ZERO, radius + 1.5, Color(0.08, 0.2, 0.03, 0.9))
	draw_circle(Vector2.ZERO, radius, VENOM_COLORS[0])
	draw_circle(Vector2(-2, -2) * _k, radius * 0.8, VENOM_COLORS[1])
	draw_circle(Vector2(-6, -6) * _k, radius * 0.45, VENOM_COLORS[2])
	draw_circle(Vector2(-9, -9) * _k, radius * 0.18, VENOM_COLORS[3])
	draw_set_transform(Vector2.ZERO)
	for i in 3:
		var turn := _time * 9 + i * 2.1
		draw_arc(point + Vector2(cos(turn) * 22, sin(turn) * 16) * _k, 5 * _k, 0, TAU, 12, Color(0.86, 1, 0.75, 0.9), 1.5)


## 毒液溅开：一圈毒液向外扩，液滴飞溅落下，冒出绿烟
func _draw_splash(p: float) -> void:
	var center := _art(to)
	var age := p * duration
	for i in 3:
		_dot(center + Vector2((i - 1) * 30, -age * 120) * _k, (0.6 + p * 1.2) * 50 * _k, Color(0.55, 0.82, 0.35, 0.7 * (1 - p)))
	draw_arc(center, (0.3 + _ease_out(minf(1, p * 2)) * 1.2) * 80 * _k, 0, TAU, 48, Color(0.55, 0.88, 0.35, 0.9 * (1 - p)), 14 * _k * (1 - p) + 2)
	for n in 10:
		var angle := n / 10.0 * TAU + 0.3
		var velocity := (180 + (n % 3) * 60) * _k
		var drop := center + Vector2(cos(angle), sin(angle)) * velocity * age + Vector2(0, 700 * _k * age * age)
		draw_circle(drop, 6 * _k, Color(DROP, 1 - p))


## 集结：每个贡献集结值的队友飞一串光点汇过来
func _draw_sparks(p: float) -> void:
	var b := _art(to)
	for helper in helpers:
		var a := _art(helper)
		for j in 6:
			var q := _ease_in(clampf(p * 1.1 - j * 0.04, 0, 1))
			if q >= 1:
				continue
			var point := _arc(a + Vector2((j - 2.5) * 10 * _k, 0), b, q, 60 * _k)
			_dot(point, 18 * _k, Color(color, 0.9))
			draw_circle(point, 3 * _k, Color.WHITE)


## 狂暴：三道爪痕从上往下划过卡图，红边白芯
func _draw_claws(p: float) -> void:
	var size := 150 * _k
	var origin := _art(to) - Vector2(size, size) / 2
	var alpha := 1.0 if p < 0.7 else (1 - p) / 0.3
	draw_set_transform(origin, 0, Vector2(size / 64, size / 64 * minf(1, p * 4)))
	for claw in [[52, 2, 20, 62], [42, 2, 10, 62], [32, 4, 2, 58]]:
		var a := Vector2(claw[0], claw[1])
		var b := Vector2(claw[2], claw[3])
		draw_colored_polygon(_crescent(a, b, 5.2, 0.0), Color(0.9, 0.28, 0.23, 0.45 * alpha))
		draw_colored_polygon(_crescent(a, b, 3.6, 0.15), Color(1, 0.62, 0.57, alpha))
		draw_colored_polygon(_crescent(a, b, 1.8, 0.35), Color(1, 1, 1, 0.8 * alpha))
	draw_set_transform(Vector2.ZERO)


## 财富：几枚金币从卡上弹起再落下
func _draw_coins(p: float) -> void:
	var center := _art(to)
	var t := p * duration
	var alpha := 1 - maxf(0, (p - 0.6) / 0.4)
	for i in 6:
		var velocity := Vector2((i - 2.5) * 34, -(160 + (i % 3) * 40)) * _k
		var coin := center + velocity * t + Vector2(0, 520 * _k * t * t)
		draw_circle(coin, 13 * _k, Color(0.42, 0.26, 0.05, alpha))
		draw_circle(coin, 11 * _k, Color(0.95, 0.76, 0.31, alpha))
		draw_circle(coin - Vector2(3, 3) * _k, 4 * _k, Color(1, 0.96, 0.76, alpha))


## 撞击：两张交战位中间一颗八角星（放大、旋转、淡出）和向外扩的光环
func _draw_impact(p: float) -> void:
	var center := (_center(from) + _center(to)) / 2
	var alpha := 1.0 if p < 0.1 else 1 - (p - 0.1) / 0.9
	var radius := 120 * _k * (0.35 + _ease_out(minf(1, p * 3)) * 0.9)
	_dot(center, radius * 1.3, Color(1, 0.55, 0.2, 0.8 * alpha))
	draw_set_transform(center, deg_to_rad(p * 40), Vector2.ONE)
	draw_colored_polygon(_star(8, radius, radius * 0.2), Color(1, 0.96, 0.84, alpha))
	draw_set_transform(Vector2.ZERO)
	draw_arc(center, (0.2 + _ease_out(p) * 0.8) * 110 * _k, 0, TAU, 48, Color(1, 0.9, 0.7, alpha), 5 * _k)


## 庇护用完：保护罩先亮起，再胀开、淡出，八块碎片向外飞
func _draw_shield_break(p: float) -> void:
	var center := _center(to)
	var alpha := p / 0.35 if p < 0.35 else maxf(0, 1 - (p - 0.35) / 0.25)
	_shield_box(center, 1 + maxf(0, p - 0.35) * 0.15, alpha, 3)
	var q := maxf(0, (p - 0.35) / 0.65)
	if q <= 0:
		return
	var size := _size(to)
	for i in 8:
		var angle := i / 8.0 * TAU
		var at := center + Vector2(cos(angle) * (size.x * 0.55 + q * 90 * _k), sin(angle) * (size.y * 0.55 + q * 90 * _k))
		draw_set_transform(at, angle + q * 4, Vector2.ONE * _k)
		draw_colored_polygon(PackedVector2Array([Vector2(-11, -7), Vector2(11, -1), Vector2(-4, 7)]), Color(1, 0.97, 0.84, 1 - q))
	draw_set_transform(Vector2.ZERO)


## 坚固：一道斜的金属光从左扫到右（裁在卡面里）
func _draw_steel(p: float) -> void:
	var size := _size(to)
	var rect := Rect2(_center(to) - size / 2, size)
	var card := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var x := rect.get_center().x + lerpf(-1.2, 1.2, _ease_in_out(p)) * size.x / 2
	var slant := size.y * tan(deg_to_rad(20))
	var alpha := 1.0 if p < 0.8 else (1 - p) / 0.2
	for band in [[size.x * 0.3, 0.25], [size.x * 0.1, 0.6]]:
		var half: float = band[0] / 2
		var shape := PackedVector2Array([Vector2(x - half + slant / 2, rect.position.y), Vector2(x + half + slant / 2, rect.position.y),
			Vector2(x + half - slant / 2, rect.end.y), Vector2(x - half - slant / 2, rect.end.y)])
		for piece in Geometry2D.intersect_polygons(shape, card):
			draw_colored_polygon(piece, Color(0.92, 0.95, 1, band[1] * alpha))


## 反噬：卡上炸开一圈尖刺（放大、旋转、淡出）
func _draw_thorns(p: float) -> void:
	var center := _center(to) + Vector2(0, ART_Y * _k * 0.5)
	var scale_now := 200 * _k / 48 * (0.5 + _ease_out(p) * 0.8)
	_dot(center, 23 * scale_now * 1.2, Color(0.9, 0.28, 0.23, 0.5 * (1 - p)))
	draw_set_transform(center, deg_to_rad(p * 30), Vector2.ONE)
	draw_colored_polygon(_star(12, 23 * scale_now, 13 * scale_now), Color(1, 0.42, 0.31, 1 - p))
	draw_set_transform(Vector2.ZERO)


## 余烬：卡面各处飘起的火星，闪烁着上升
func _draw_embers(p: float) -> void:
	var size := _size(to)
	var center := _center(to)
	for i in 18:
		var x0 := (_random(i, 1) - 0.5) * size.x
		var y0 := (_random(i, 2) - 0.3) * size.y * 0.8
		var q := maxf(0, p - _random(i, 3) * 0.3)
		if q <= 0:
			continue
		var at := center + Vector2(x0 + sin(q * 6 + i) * 12 * _k, y0 - q * 160 * _k)
		var alpha := minf(1, q * 5) * (1 - q)
		_dot(at, 14 * _k * (1 - q * 0.6), Color(color, alpha))
		draw_circle(at, 2.5 * _k, Color(1, 0.85, 0.55, alpha))


# ---------- 工具 ----------

## 保护罩的样子：圆角框、亮金边、外发光；scale 以卡为中心
func _shield_box(center: Vector2, scale_now: float, alpha: float, border: int) -> void:
	if alpha <= 0:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 0.9, 0.6, 0.05 * alpha)
	box.set_corner_radius_all(roundi(26 * _k))
	box.set_expand_margin_all(14 * _k)
	box.border_color = Color(GOLD_LIGHT, alpha)
	box.set_border_width_all(border)
	box.shadow_color = Color(1, 0.84, 0.47, 0.6 * alpha)
	box.shadow_size = roundi(22 * _k)
	var size := _size(to)
	draw_set_transform(center, 0, Vector2.ONE * scale_now)
	draw_style_box(box, Rect2(-size / 2, size))
	draw_set_transform(Vector2.ZERO)


func _dot(at: Vector2, radius: float, tint: Color) -> void:
	draw_texture_rect(_glow, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, tint)


## 月牙：从 a 到 b，最宽 w，offset 是内侧那条弧往外偏的比例（0 时是实心的月牙）
func _crescent(a: Vector2, b: Vector2, w: float, offset: float) -> PackedVector2Array:
	var mid := (a + b) / 2
	var normal := (b - a).orthogonal().normalized()
	var outer := mid + normal * w * 1.3
	var inner := mid + normal * w * offset
	var points := PackedVector2Array()
	for i in 13:
		points.append(_quad(a, outer, b, i / 12.0))
	for i in range(11, 0, -1):
		points.append(_quad(a, inner, b, i / 12.0))
	return points


func _quad(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(control, t).lerp(control.lerp(b, t), t)


func _star(points: int, outer: float, inner: float) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for i in points * 2:
		var angle := -PI / 2 + i * PI / points
		shape.append(Vector2(cos(angle), sin(angle)) * (inner if i % 2 else outer))
	return shape


func _arc(a: Vector2, b: Vector2, q: float, lift: float) -> Vector2:
	return a.lerp(b, q) - Vector2(0, sin(q * PI) * lift)


## 卡的位置（卡被删掉后沿用最后的位置）
func _center(card: Node2D) -> Vector2:
	if is_instance_valid(card):
		_last[card.get_instance_id()] = card.position
	return _last.get(card.get_instance_id(), Vector2.ZERO)


func _art(card: Node2D) -> Vector2:
	var scale_y: float = card.scale.y if is_instance_valid(card) else 1.0
	return _center(card) + Vector2(0, ART_Y * _k * scale_y)


func _size(card: Node2D) -> Vector2:
	return card.face.get_size() * card.scale if is_instance_valid(card) else Vector2(300, 420) * _k


## 0–1 的伪随机数（按编号固定）
func _random(i: int, n: int) -> float:
	return fposmod(sin(i * 12.9898 + n * 78.233) * 43758.5453, 1.0)


func _ease_out(p: float) -> float:
	return 1 - pow(1 - p, 3)


func _ease_in(p: float) -> float:
	return pow(p, 2.4)


func _ease_in_out(p: float) -> float:
	return 4 * p * p * p if p < 0.5 else 1 - pow(-2 * p + 2, 3) / 2
