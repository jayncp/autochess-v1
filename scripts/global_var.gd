extends Node

class_name global_var

# 进入战斗时双方的阵容：角色 id 和对应的装备 id（空字符串表示不带）
static var battle_card_list_1 = []
static var battle_equip_list_1 = []
static var battle_card_list_2 = []
static var battle_equip_list_2 = []

## 紧凑模式（构筑阶段、科研模式的开关），这次运行里一直保持
static var compact_mode := false

# Called when the node enters the scene tree for the first time.
# func _ready() -> void:
# 	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta: float) -> void:
# 	pass
