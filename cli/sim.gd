extends SceneTree
## 无头批量模拟：读 JSONL，每行一场 {"p1": [[角色 id, 装备 id], ...], "p2": [...]}，可带 "id"；
## 写 JSONL，每行一个结果 {"id", "winner", "p1", "p2"}，加 --log 时带上事件日志 "events"。
## winner：1/2 = 该方胜，3 = 平局；p1/p2 是双方幸存单位的战力。
## 用法：just sim <输入> <输出> [--log]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("用法：godot --headless --path . --script res://cli/sim.gd -- <输入.jsonl> <输出.jsonl> [--log]")
		quit(2)
		return
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	if out == null:
		printerr("无法写入 %s" % args[1])
		quit(1)
		return
	var with_log := "--log" in args
	var start := Time.get_ticks_usec()
	for line in lines:
		var battle: Dictionary = JSON.parse_string(line)
		var result := BattleSim.simulate(battle.p1, battle.p2)
		var row := {"winner": result.winner, "p1": result.p1, "p2": result.p2}
		if battle.has("id"):
			row.id = battle.id
		if with_log:
			row.events = result.events
		out.store_line(JSON.stringify(row, "", false))
	out.close()
	var seconds := (Time.get_ticks_usec() - start) / 1e6
	print("模拟 %d 场，用时 %.2f 秒，%.0f 场/秒" % [lines.size(), seconds, lines.size() / maxf(seconds, 1e-6)])
	quit(0)
