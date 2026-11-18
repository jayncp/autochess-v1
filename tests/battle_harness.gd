extends RefCounted
## 测试用的战斗工具：读写用例、加载测试卡、跑一场战斗（BattleSim）、检查事件日志。格式见 tests/README.md。
## 阵容格式：[[角色 id, 装备 id], ...]，装备为空字符串表示不带。

## 规则用例：只用测试卡，期望值是完整的结果。以后 Rust 版读同一份
const CASES_PATH := "res://tests/cases/battles.json"
## 测试卡：数值固定，不随正式卡调整
const TEST_CARDS_PATH := "res://tests/cases/cards.json"
## 冒烟用例：用正式卡，只检查能打完、左右对称、事件自洽（关卡的解还检查胜负）
const SMOKE_PATH := "res://tests/cases/smoke.json"


static func test_cards() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(TEST_CARDS_PATH))


## 测试卡临时加进 CardDB（只在本次运行有效）
static func add_test_cards() -> void:
	CardDB.add_cards(test_cards())


static func remove_test_cards() -> void:
	for c in test_cards():
		CardDB.all().erase(c.id)


## 跑一场：胜负、原因、双方幸存的角色和战斗力（[[角色 id, 战斗力], ...]，按队列顺序），以及事件日志
static func run(p1: Array, p2: Array) -> Dictionary:
	var sim := BattleSim.new(p1, p2)
	sim.run()
	var result := {"winner": sim.winner, "reason": sim.events[-1].reason, "events": sim.events}
	for side in [1, 2]:
		result["p%d" % side] = sim.fields[side].map(func(u): return [u.card_id, u.strength])
	return result


## 交换左右后的期望结果
static func mirror(result: Dictionary) -> Dictionary:
	return {"winner": {1: 2, 2: 1, 3: 3}[int(result.winner)], "reason": result.reason, "p1": result.p2, "p2": result.p1}


## 只比较结果（胜负、原因、幸存的角色和战斗力），忽略 JSON 读出的 float 与 int 之差。
## 有一方没有原因时（如场景里显示的结果）不比原因
static func same(a: Dictionary, b: Dictionary) -> bool:
	if int(a.winner) != int(b.winner) or a.has("reason") and b.has("reason") and a.reason != b.reason:
		return false
	return _pairs(a.p1) == _pairs(b.p1) and _pairs(a.p2) == _pairs(b.p2)


static func _pairs(units: Array) -> Array:
	return units.map(func(u): return [u[0], int(u[1])])


## 只有结果，没有事件日志（用来写期望值、打印）
static func outcome(result: Dictionary) -> Dictionary:
	return {"winner": result.winner, "reason": result.reason, "p1": result.p1, "p2": result.p2}


## 事件自洽：从 start 的初始战力出发，按每个效果的增减推演，
## 中途记录的战力、判死和最终结果都要对得上。返回第一处不一致，没有则返回空字符串
static func check_events(result: Dictionary) -> String:
	var events: Array = result.events
	var strength := {}
	var alive := {1: [], 2: []}
	for side in [1, 2]:
		for u in events[0]["p%d" % side]:
			strength[u.uid] = u.strength
			alive[side].append(u.uid)
	for e in events:
		for f in e.get("effects", []):
			if f.kind == "damage":
				var by_error := _check_by(f)
				if by_error:
					return by_error
			if f.kind not in ["buff", "damage"]:
				continue  # 唤醒、财富不改战力
			strength[f.unit] += f.amount if f.kind == "buff" else -f.dealt
			if strength[f.unit] != f.strength:
				return "%s 的战力推演为 %d，事件记录为 %d" % [f.unit, strength[f.unit], f.strength]
		if e.type == "death":
			for side in [1, 2]:
				var dead: Array = alive[side].filter(func(uid): return strength[uid] <= 0)
				alive[side] = alive[side].filter(func(uid): return strength[uid] > 0)
				for uid in dead:
					if uid not in e.units:
						return "%s 战力 ≤0 但没有阵亡" % uid
	if events[-1].type != "end" or events[-1].winner != result.winner:
		return "最后一个事件不是 end，或胜负不一致"
	for side in [1, 2]:
		var expected: Array = result["p%d" % side].map(func(u): return u[1])
		if alive[side].map(func(uid): return strength[uid]) != expected:
			return "P%d 幸存单位推演为 %s，结果为 %s" % [side, alive[side].map(func(uid): return strength[uid]), expected]
	return ""


## 伤害的 by（回放据此找发动者）：反噬是自己，交战、腐蚀、湮灭是对方的单位
static func _check_by(f: Dictionary) -> String:
	var own: bool = f.by == f.unit
	var opposite: bool = f.by.get_slice("-", 0) != f.unit.get_slice("-", 0)
	if (f.source == "backlash" and not own) or (f.source != "backlash" and not opposite):
		return "%s 的伤害（%s）记录的来源 %s 不对" % [f.unit, f.source, f.by]
	return ""


static func load_cases(path: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## 用例文件是 JSON 数组，一行一条（和 data/cards.json 一样，方便看改动）
static func save_cases(path: String, cases: Array) -> void:
	var lines := cases.map(func(c): return JSON.stringify(c, "", false))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[\n" + ",\n".join(lines) + "\n]\n")
	f.close()
