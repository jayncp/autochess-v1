extends RefCounted
## 测试用的战斗工具：跑一场战斗（BattleSim），检查事件日志，读写用例文件。
## 阵容格式：[[角色 id, 装备 id], ...]，装备为空字符串表示不带。


## 返回胜负和双方幸存单位的战力
static func run(p1: Array, p2: Array) -> Dictionary:
	var r := BattleSim.simulate(p1, p2)
	return {"winner": r.winner, "p1": r.p1, "p2": r.p2}


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
		if alive[side].map(func(uid): return strength[uid]) != result["p%d" % side]:
			return "P%d 幸存单位推演为 %s，结果为 %s" % [side, alive[side].map(func(uid): return strength[uid]), result["p%d" % side]]
	return ""


## 伤害的 by（回放据此找发动者）：反噬是自己，交战、腐蚀、湮灭是对方的单位
static func _check_by(f: Dictionary) -> String:
	var own: bool = f.by == f.unit
	var opposite: bool = f.by.get_slice("-", 0) != f.unit.get_slice("-", 0)
	if (f.source == "backlash" and not own) or (f.source != "backlash" and not opposite):
		return "%s 的伤害（%s）记录的来源 %s 不对" % [f.unit, f.source, f.by]
	return ""


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
