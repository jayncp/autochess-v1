extends SceneTree
## 用当前引擎重录规则用例（tests/cases/battles.json）的期望值，并列出结果变化的用例；同时报告交换左右后不对称的用例。
## 用法：just record（改规则后运行，逐条核对变化后再提交）

const Harness := preload("res://tests/battle_harness.gd")


func _initialize() -> void:
	Harness.add_test_cards()
	var cases := Harness.load_cases(Harness.CASES_PATH)
	var changed := 0
	for c in cases:
		var got := Harness.outcome(Harness.run(c.p1, c.p2))
		if not c.has("expect") or not Harness.same(got, c.expect):
			print("%s 变化：%s -> %s" % [c.id, c.get("expect"), got])
			changed += 1
		c.expect = got
		if not Harness.same(Harness.run(c.p2, c.p1), Harness.mirror(got)):
			print("%s 交换左右后不对称" % c.id)
	Harness.save_cases(Harness.CASES_PATH, cases)
	print("共 %d 条，结果变化 %d 条" % [cases.size(), changed])
	quit()
