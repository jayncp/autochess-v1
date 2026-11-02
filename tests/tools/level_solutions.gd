extends SceneTree
## 枚举每个关卡里玩家的全部摆法（可只上部分角色、装备可不用，相同卡互换算一种），
## 打印通过率和全部解，并把解写入 level 组用例（之后运行 just record 录制期望值）。
## 用法：just levels

const Harness := preload("res://tests/battle_harness.gd")
const LEVELS := preload("res://scripts/database/level_database.gd").LEVEL
const CASES_PATH := "res://tests/golden/battles.jsonl"


func _initialize() -> void:
	await process_frame
	var harness := Harness.new(self)
	var cases := Harness.load_cases(CASES_PATH).filter(func(c): return c.group != "level")
	for level_name in LEVELS:
		var data: Array = LEVELS[level_name]
		var enemy := []
		for i in data[0].size():
			enemy.append([data[0][i], data[1][i]])
		var arrangements := _arrangements(data[2], data[3])
		var solutions := []
		for team in arrangements:
			var got: Dictionary = await harness.run(enemy, team)
			if got.winner == 2:
				solutions.append(team)
		print("%s：%d 种摆法，%d 个解，通过率 %.2f%%" % [level_name, arrangements.size(), solutions.size(), 100.0 * solutions.size() / arrangements.size()])
		for i in solutions.size():
			print("  ", _describe(solutions[i]))
			cases.append({"id": "level-%s-%d" % [level_name, i + 1], "group": "level", "p1": enemy, "p2": solutions[i]})
	Harness.save_cases(CASES_PATH, cases)
	quit()


## 全部不同的摆法：角色有序选取 k 个（k ≥ 1），每件装备不用或装给一个没装备的角色
func _arrangements(chars: Array, equips: Array) -> Array:
	var seen := {}
	var result := []
	for order in _orders(chars):
		for team in _equip(order.map(func(c): return [c, ""]), equips, 0):
			var key := JSON.stringify(team)
			if not seen.has(key):
				seen[key] = true
				result.append(team)
	return result


func _orders(pool: Array) -> Array:
	var result := []
	for i in pool.size():
		var rest := pool.duplicate()
		rest.remove_at(i)
		result.append([pool[i]])
		for tail in _orders(rest):
			result.append([pool[i]] + tail)
	return result


func _equip(team: Array, equips: Array, index: int) -> Array:
	if index == equips.size():
		return [team]
	var result := _equip(team, equips, index + 1)  # 这件装备不用
	for i in team.size():
		if team[i][1] == "":
			var next := team.duplicate(true)
			next[i][1] = equips[index]
			result += _equip(next, equips, index + 1)
	return result


func _describe(team: Array) -> String:
	return " / ".join(team.map(func(u): return u[0] + ("+" + u[1] if u[1] != "" else "")))
