extends Node2D
## 卡牌：拖放、悬停、动画用这个根节点；卡面由子节点 face（CardFace）画。用 load_card.generate 生成。

## 鼠标进入、离开卡牌（布阵界面用来悬停看卡）
signal hovered(card)
signal hovered_off(card)

## 卡牌身份：角色和装备的 id，空字符串表示没有
var card_id := ""
var equip_id := ""
## 在手牌里的位置（放回手牌时回到这里）
var starting_position
## 所在的卡位，不在卡位上为 null
var card_slot_card_is_in
## 平时的图层（拖动时临时提到最上面，放下后恢复）
var old_z_index
## 敌方的卡，不能拖动
var is_enemy_card = false

## 卡面
var face: CardFace:
	get:
		return $face


func _ready() -> void:
	# 点击区域和卡面一样大
	$Area2D/CollisionShape2D.shape.size = face.get_size()
	# 布阵界面接收悬停信号（战斗界面不用）
	if get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)


## 移动到 target（动画）；新的移动会取代还没走完的
func move_to(target: Vector2, duration: float) -> void:
	stop_moving()
	if duration <= 0:
		position = target
		return
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration)
	set_meta("tween", tween)


## 停下正在进行的移动（比如被拿起来拖动时）
func stop_moving() -> void:
	if has_meta("tween"):
		get_meta("tween").kill()
		remove_meta("tween")


## 外观：显示缩放、是否紧凑卡；点击区域跟着卡面大小变
func set_look(display_scale: float, compact: bool) -> void:
	if face.display_scale == display_scale and face.compact == compact:
		return
	face.display_scale = display_scale
	face.compact = compact
	$Area2D/CollisionShape2D.shape.size = face.get_size()


func _on_area_2d_mouse_entered() -> void:
	hovered.emit(self)


func _on_area_2d_mouse_exited() -> void:
	hovered_off.emit(self)
