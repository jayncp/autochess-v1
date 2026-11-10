class_name FxLayer
extends Node2D
## 战斗特效层：生成特效（FxEffect），以及交战撞击时的画面震动（只震卡牌、飘字和特效，不震按钮）。
## 特效的时长按 1 倍速给，跟着战斗速度加快。

## 震动的节点：整体上下晃，晃完回到原位
var shake_targets: Array[Node2D] = []
var speed := 1.0

var _shake_time := 0.0
var _shake_duration := 0.0
var _shake_amp := 0.0


## 生成一个特效；props 是 FxEffect 的属性（from、to、helpers、color、big）
func spawn(kind: FxEffect.Kind, duration: float, props: Dictionary) -> void:
	var effect := FxEffect.new()
	effect.kind = kind
	effect.duration = duration
	effect.speed = speed
	for key in props:
		effect.set(key, props[key])
	add_child(effect)


## 画面震动：amp 像素，duration 秒（1 倍速）内衰减
func shake(amp: float, duration: float) -> void:
	_shake_amp = amp
	_shake_duration = duration
	_shake_time = 0.0


func clear() -> void:
	for effect in get_children():
		effect.queue_free()
	_shake_duration = 0.0
	_apply_shake(0.0)


func _process(delta: float) -> void:
	if _shake_duration <= 0:
		return
	_shake_time += delta * speed
	var p := _shake_time / _shake_duration
	if p >= 1:
		_shake_duration = 0.0
		_apply_shake(0.0)
		return
	_apply_shake(_shake_amp * sin(p * PI * 7) * (1 - p))


func _apply_shake(offset: float) -> void:
	for node in shake_targets:
		node.position = Vector2(0, offset)
