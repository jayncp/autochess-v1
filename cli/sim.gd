extends SceneTree
## 无头批量模拟：读 JSONL，每行一场 {"p1": [[角色 id, 装备 id], ...], "p2": [...]}，可带 "id"；
## 写 JSONL，每行一个结果 {"id", "winner", "reason", "p1", "p2"}，加 --log 时带上事件日志 "events"。
## winner：1/2 = 该方胜，3 = 平局；reason：wipe（全灭）/ no_death（连续无人阵亡）；p1/p2 是双方幸存单位的战力。
## --cards <文件>：额外的卡牌定义（JSON 数组，字段同 data/cards.json），只在本次模拟有效，供平衡实验使用。
## --trace：带上简要轨迹 "trace"（每步判死之后双方的战力，格式同 Rust 版 engine-cli），只用于对拍时定位差异。
## 用法：just sim-godot <输入> <输出> [--log] [--trace] [--cards <文件>]（just sim 是 Rust 版，格式相同）


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法：godot --headless --path . --script res://cli/sim.gd -- <输入.jsonl> <输出.jsonl> [--log] [--trace] [--cards <文件>]")
		quit(2)
		return
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	if out == null:
		printerr("无法写入 %s" % args[1])
		quit(1)
		return
	var with_log := "--log" in args
	var with_trace := "--trace" in args
	var cards_at := args.find("--cards")
	if cards_at != -1:
		CardDB.add_cards(JSON.parse_string(FileAccess.get_file_as_string(args[cards_at + 1])))
	var start := Time.get_ticks_usec()
	for line in lines:
		var battle: Dictionary = JSON.parse_string(line)
		var result := BattleSim.simulate(battle.p1, battle.p2)
		var row := {"winner": result.winner, "reason": result.events[-1].reason, "p1": result.p1, "p2": result.p2}
		if battle.has("id"):
			row.id = battle.id
		if with_log:
			row.events = result.events
		if with_trace:
			row.trace = trace(result.events)
		out.store_line(JSON.stringify(row, "", false))
	out.close()
	var seconds := (Time.get_ticks_usec() - start) / 1e6
	print("模拟 %d 场，用时 %.2f 秒，%.0f 场/秒" % [lines.size(), seconds, lines.size() / maxf(seconds, 1e-6)])
	quit(0)


## 简要轨迹：由事件日志算出每一步（战前、入场、交战）判死之后双方队列里每个角色的战力，[[步骤, [P1...], [P2...]], ...]。
## 和 Rust 版的 --trace 相同，对拍时用来找第一处不同；不改 BattleSim
static func trace(events: Array) -> Array:
	var strength := {}
	var alive := {1: [], 2: []}
	for side in [1, 2]:
		for u in events[0]["p%d" % side]:
			strength[u.uid] = u.strength
			alive[side].append(u.uid)
	var steps := []
	var step := ""
	for e in events:
		if e.type in ["pre_battle", "enter", "engage", "end"]:
			if step:
				steps.append([step, alive[1].map(func(uid): return strength[uid]), alive[2].map(func(uid): return strength[uid])])
			step = e.type
		elif e.type == "death":
			for side in [1, 2]:
				alive[side] = alive[side].filter(func(uid): return uid not in e.units)
		for f in e.get("effects", []):
			if f.has("strength"):
				strength[f.unit] = f.strength
	return steps
