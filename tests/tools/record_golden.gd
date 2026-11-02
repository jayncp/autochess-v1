extends SceneTree
## 用当前引擎重录战斗用例的期望值，并列出结果变化的用例；同时报告交换左右后不对称的用例。
## 用法：just record（改规则或数据后运行，核对变化后再提交）

const Harness := preload("res://tests/battle_harness.gd")
const CASES_PATH := "res://tests/golden/battles.jsonl"


func _initialize() -> void:
	await process_frame
	var harness := Harness.new(self)
	var cases := Harness.load_cases(CASES_PATH)
	var changed := 0
	for c in cases:
		print("运行 ", c.id)  # 引擎卡死时，最后一行就是出问题的用例
		var got: Dictionary = await harness.run(c.p1, c.p2)
		if not c.has("expect") or not Harness.same(got, c.expect):
			print("  变化：%s -> %s" % [c.get("expect"), got])
			changed += 1
		c.expect = got
		var mirrored: Dictionary = await harness.run(c.p2, c.p1)
		var symmetric := Harness.same(mirrored, Harness.mirror(got))
		if symmetric == c.get("asymmetric", false):
			print("  对称性与标记不符：交换左右%s" % ["对称" if symmetric else "不对称"])
	Harness.save_cases(CASES_PATH, cases)
	print("共 %d 条，结果变化 %d 条" % [cases.size(), changed])
	quit()
