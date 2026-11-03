extends SceneTree
## 枚举每个关卡的全部解（用 cli/levels.gd），打印并写入 level 组用例，之后运行 just record 录制期望值。
## 用法：just levels

const Harness := preload("res://tests/battle_harness.gd")
const Levels := preload("res://cli/levels.gd")
const CASES_PATH := "res://tests/golden/battles.jsonl"


func _initialize() -> void:
	var cases := Harness.load_cases(CASES_PATH).filter(func(c): return c.group != "level")
	for level_id in LevelDB.all():
		var level := LevelDB.level(level_id)
		var report := Levels.solve(level)
		print(Levels.describe_report(level_id, report))
		for i in report.solutions.size():
			print("  ", Levels.describe_team(report.solutions[i]))
			cases.append({"id": "level-%s-%d" % [level_id, i + 1], "group": "level", "p1": level.enemy, "p2": report.solutions[i]})
	Harness.save_cases(CASES_PATH, cases)
	quit()
