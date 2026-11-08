@tool
class_name UiButton
extends Button
## 按钮：底板来自主题（Button / PrimaryButton），两端各画一枚金色菱形。

const GOLD := Color("ffd98a")
const SIZE := 10.0

@export var diamonds := true:
	set(value):
		diamonds = value
		queue_redraw()


func _draw() -> void:
	if not diamonds:
		return
	var color := Color(GOLD, 0.35) if disabled else GOLD
	var y := size.y / 2
	for x in [0.0, size.x]:
		_diamond(Vector2(x, y), SIZE + 2, Color.BLACK)
		_diamond(Vector2(x, y), SIZE, color)


func _diamond(center: Vector2, d: float, color: Color) -> void:
	var r := d / 2
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]), color)
