extends SceneTree
## 重新生成 random 组用例（固定种子），保留其他分组；生成后需运行 just record 录制期望值。
## 卡牌增删后使用。每个角色、每件装备至少出现 MIN_APPEAR 次。
## 用法：just gen-random

const Harness := preload("res://tests/battle_harness.gd")
const CASES_PATH := "res://tests/golden/battles.jsonl"
const COUNT := 100
const SEED := 20261102
const MIN_APPEAR := 3
## 在当前引擎里不会结束的对局（修复平局规则前会卡死），生成时跳过
const SKIP_IDS: Array[String] = []


func _initialize() -> void:
	var chars := CardDB.ids("character")
	var equips := CardDB.ids("equipment")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var cases := Harness.load_cases(CASES_PATH).filter(func(c): return c.group != "random")
	var appear := {}
	var made := 0
	var n := 0
	while made < COUNT:
		n += 1
		var teams := []
		for side in 2:
			var team := []
			for i in rng.randi_range(1, 7):
				var equip: String = equips[rng.randi() % equips.size()] if rng.randf() < 0.6 else ""
				team.append([chars[rng.randi() % chars.size()], equip])
			teams.append(team)
		var id := "random-%03d" % n
		if id in SKIP_IDS:
			continue
		for team in teams:
			for u in team:
				for name in u:
					appear[name] = appear.get(name, 0) + 1
		cases.append({"id": id, "group": "random", "p1": teams[0], "p2": teams[1]})
		made += 1
	for name in chars + equips:
		if appear.get(name, 0) < MIN_APPEAR:
			printerr("覆盖不足：%s 只出现 %d 次" % [name, appear.get(name, 0)])
	Harness.save_cases(CASES_PATH, cases)
	print("已生成 %d 条随机用例，请运行 just record" % made)
	quit()
