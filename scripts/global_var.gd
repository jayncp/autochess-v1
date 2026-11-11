class_name global_var
extends RefCounted
## 场景之间共享的状态（静态变量，不需要实例）。

## 进入战斗时双方的阵容：角色 id 和对应的装备 id（空字符串表示不带）
static var battle_card_list_1 = []
static var battle_equip_list_1 = []
static var battle_card_list_2 = []
static var battle_equip_list_2 = []

## 这场战斗来自哪个关卡（打赢了记通关）；科研模式为空
static var battle_level := ""

## 紧凑模式（构筑阶段、科研模式的开关）：进入时设成默认值（GameSettings.compact），当次可以临时切换
static var compact_mode := true
