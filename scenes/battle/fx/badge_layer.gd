class_name BadgeLayer
extends Node2D
## 战斗中的飘字层：飘字压在卡图上、跟着卡移动。同一张卡上后弹出的在原位，先弹出的往上推一格。

## 飘字跟着战斗速度加快，但最多这么快：5× 时也至少停 0.45 秒，看得见
const MAX_SPEED := FloatBadge.LIFE / 0.45


func add(card: Node2D, badge: FloatBadge, speed: float) -> void:
	for other: FloatBadge in get_children():
		if other.card == card:
			other.push += FloatBadge.STACK
	badge.card = card
	badge.display_scale = card.face.display_scale
	badge.speed = minf(speed, MAX_SPEED)
	add_child(badge)


func clear() -> void:
	for badge in get_children():
		badge.queue_free()
