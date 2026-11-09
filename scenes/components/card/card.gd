extends Node2D
## 卡牌：拖放、悬停、动画用这个根节点；卡面由子节点 face（CardFace）画。用 load_card.generate 生成。

# 鼠标悬停信号
signal hovered
signal hovered_off

var starting_position
# 所在卡槽，判断是否在卡槽内
var card_slot_card_is_in
# 记录旧的z_index
var old_z_index
# 标记为敌人卡牌，无法互动
var is_enemy_card = false

# 卡牌身份：角色和装备的 id，空字符串表示没有
var card_id := ""
var equip_id := ""

var is_playing_animation = false

## 卡面
var face: CardFace:
	get:
		return $face


func _ready() -> void:
	# 点击区域和卡面一样大
	$Area2D/CollisionShape2D.shape.size = face.get_size()
	# 连结发送信号
	get_parent().connect_card_signals(self)

# 卡牌悬停信号发送
func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered",self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off",self)
