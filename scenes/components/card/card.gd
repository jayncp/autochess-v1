extends Node2D

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

# 战斗中当前显示的战力（结算在 BattleSim 里，这里只做显示）
var strength
var is_playing_animation = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 连结发送信号
	get_parent().connect_card_signals(self)

# 卡牌悬停信号发送
func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered",self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off",self)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
