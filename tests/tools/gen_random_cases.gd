extends SceneTree
## 重新生成冒烟用例里的随机对局（固定种子，正式卡），保留关卡的解。随机对局没有期望值，只检查能打完、左右对称、事件自洽。
## 卡牌增删后使用。每个角色、每件装备至少出现 MIN_APPEAR 次。
## 用法：just gen-random

const Harness := preload("res://tests/battle_harness.gd")
const COUNT := 100
const SEED := 20261102
const MIN_APPEAR := 3


func _initialize() -> void:
	var chars := CardDB.ids("character")
	var equips := CardDB.ids("equipment")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var cases := Harness.load_cases(Harness.SMOKE_PATH).filter(func(c): return not c.id.begins_with("random-"))
	var appear := {}
	for n in range(1, COUNT + 1):
		var teams := []
		for side in 2:
			var team := []
			for i in rng.randi_range(1, 7):
				var equip: String = equips[rng.randi() % equips.size()] if rng.randf() < 0.6 else ""
				team.append([chars[rng.randi() % chars.size()], equip])
			teams.append(team)
		for team in teams:
			for u in team:
				for name in u:
					appear[name] = appear.get(name, 0) + 1
		cases.append({"id": "random-%03d" % n, "p1": teams[0], "p2": teams[1]})
	for name in chars + equips:
		if appear.get(name, 0) < MIN_APPEAR:
			printerr("覆盖不足：%s 只出现 %d 次" % [name, appear.get(name, 0)])
	Harness.save_cases(Harness.SMOKE_PATH, cases)
	print("已生成 %d 条随机对局" % COUNT)
	quit()
