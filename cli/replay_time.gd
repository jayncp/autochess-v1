extends SceneTree
## 估算回放时长（1 倍速，秒）：随机对局在战斗场景里按事件播放，只把主流程要等的时间加起来（battle_manager.measuring），不真的等。
## 打印平均、中位、P90、最长，以及各段落平均占多少秒。
## 用法：just replay-time [场数] [--stars 1,2]（--stars 只用这些星级的卡）

const COUNT := 600
const SEED := 20261118
const SIZES := [5, 7]
const EQUIP_RATE := 0.6


func _initialize() -> void:
	await process_frame  # 场景树就绪后再生成战斗场景，@onready 才会生效
	var args := OS.get_cmdline_user_args()
	var count := COUNT
	if not args.is_empty() and args[0].is_valid_int():
		count = int(args[0])
	var stars := []
	var at := args.find("--stars")
	if at != -1:
		stars = Array(args[at + 1].split(",")).map(func(x): return int(x))
	var pool := func(type: String) -> Array:
		return CardDB.ids(type).filter(func(id): return stars.is_empty() or CardDB.card(id).star in stars)
	var chars: Array = pool.call("character")
	var equips: Array = pool.call("equipment")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var times: Array[float] = []
	var segments := {}
	var steps := []  # [秒, 时点类型, 事件类型, 第几场]
	var battles := []  # 每场的阵容
	for n in count:
		var lineups := []
		for side in 2:
			var team := []
			for i in rng.randi_range(SIZES[0], SIZES[1]):
				team.append([chars[rng.randi() % chars.size()], equips[rng.randi() % equips.size()] if rng.randf() < EQUIP_RATE else ""])
			lineups.append(team)
		battles.append(lineups)
		global_var.battle_card_list_1 = lineups[0].map(func(u): return u[0])
		global_var.battle_equip_list_1 = lineups[0].map(func(u): return u[1])
		global_var.battle_card_list_2 = lineups[1].map(func(u): return u[0])
		global_var.battle_equip_list_2 = lineups[1].map(func(u): return u[1])
		var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
		root.add_child(scene)
		var manager: Node = scene.get_node("battle_manager")
		manager.battle_speed = 1.0
		manager.measuring = true
		manager._on_start_battle_pressed_battle()
		var total := 0.0
		for key in manager.measured:
			total += manager.measured[key]
			segments[key] = segments.get(key, 0.0) + manager.measured[key]
		times.append(total)
		for step in manager.measured_steps:
			steps.append([step[1], step[0], step[2], n])
		scene.free()
	times.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= times.size()
	print("回放时长（1 倍速，%d 场，每方 %d–%d 人%s）：平均 %.1f 秒，中位 %.1f，P90 %.1f，最长 %.1f" % [count, SIZES[0], SIZES[1],
		"" if stars.is_empty() else "，只用 %s★" % ",".join(stars.map(func(x): return str(x))),
		mean, times[times.size() / 2], times[int(times.size() * 0.9)], times[-1]])
	var keys := segments.keys()
	keys.sort_custom(func(a, b): return segments[a] > segments[b])
	for key in keys:
		print("  %-22s %5.1f 秒（%2.0f%%）" % [key, segments[key] / count, 100.0 * segments[key] / count / mean])
	steps.sort_custom(func(a, b): return a[0] > b[0])
	print("最长的时点：")
	var shown := {}
	for step in steps:
		if shown.size() >= 5:
			break
		if shown.has(step[3]):
			continue  # 每场只列最长的那个
		shown[step[3]] = true
		var kinds := {}
		for t in step[2]:
			kinds[t] = kinds.get(t, 0) + 1
		print("  %4.1f 秒  %s  %s" % [step[0], step[1], kinds])
		print("         %s\n      对 %s" % [battles[step[3]][0], battles[step[3]][1]])
	quit()
