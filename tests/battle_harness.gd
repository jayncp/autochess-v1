extends RefCounted
## 用现有战斗场景跑一场战斗（关闭动画），返回胜负和双方幸存单位的战力。
## 阵容格式：[[角色, 装备], ...]，装备为空字符串表示不带。

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree


func run(p1: Array, p2: Array) -> Dictionary:
	global_var.battle_card_list_1 = p1.map(func(u): return u[0])
	global_var.battle_equip_list_1 = p1.map(func(u): return u[1])
	global_var.battle_card_list_2 = p2.map(func(u): return u[0])
	global_var.battle_equip_list_2 = p2.map(func(u): return u[1])
	var scene := BATTLE_SCENE.instantiate()
	_tree.root.add_child(scene)
	var manager = scene.get_node("battle_manager")
	manager.play_animation = false
	manager.battle_speed = 1e9
	await manager._on_start_battle_pressed_battle()
	var result := {
		"winner": manager.winner,
		"p1": manager.player_battle_fields[1].map(func(c): return c.strength),
		"p2": manager.player_battle_fields[2].map(func(c): return c.strength),
	}
	scene.free()
	return result


## 交换左右后的期望结果
static func mirror(result: Dictionary) -> Dictionary:
	return {
		"winner": {1: 2, 2: 1, 3: 3}[int(result.winner)],
		"p1": result.p2,
		"p2": result.p1,
	}


## 只比较数值，忽略 JSON 读出的 float 与 int 之差
static func same(a: Dictionary, b: Dictionary) -> bool:
	return int(a.winner) == int(b.winner) and _ints(a.p1) == _ints(b.p1) and _ints(a.p2) == _ints(b.p2)


static func _ints(xs: Array) -> Array:
	return xs.map(func(x): return int(x))


static func load_cases(path: String) -> Array:
	var cases := []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		cases.append(JSON.parse_string(line))
	return cases


static func save_cases(path: String, cases: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for c in cases:
		f.store_line(JSON.stringify(c, "", false))
	f.close()
