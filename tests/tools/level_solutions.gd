extends SceneTree
## 枚举每个关卡的全部解（用 cli/levels.gd），打印并写入冒烟用例（期望我方胜），保留随机对局。
## 用法：just levels

const Harness := preload("res://tests/battle_harness.gd")
const Levels := preload("res://cli/levels.gd")


func _initialize() -> void:
	var cases := []
	for level_id in LevelDB.all():
		var level := LevelDB.level(level_id)
		var report := Levels.solve(level)
		print(Levels.describe_report(level_id, report))
		for i in report.solutions.size():
			print("  ", Levels.describe_team(report.solutions[i]))
			cases.append({"id": "level-%s-%d" % [level_id, i + 1], "p1": level.enemy, "p2": report.solutions[i], "expect": {"winner": 2}})
	cases.append_array(Harness.load_cases(Harness.SMOKE_PATH).filter(func(c): return not c.id.begins_with("level-")))
	Harness.save_cases(Harness.SMOKE_PATH, cases)
	quit()
