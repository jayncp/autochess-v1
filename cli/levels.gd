extends SceneTree
## 关卡检查：枚举玩家的全部摆法（可以只上部分角色、装备可以不用，相同的卡互换算一种），
## 打印摆法数、解数、通过率和全部解。只有获胜算通过。
## 用法：just level-check [关卡文件.json]（格式同 data/levels.json，默认就是它）


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var levels: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() > 0 else LevelDB.all().values()
	for level in levels:
		var report := solve(level)
		print(describe_report(level.id, report))
		for team in report.solutions:
			print("  ", describe_team(team))
	quit()


## 枚举一个关卡：返回 {arrangements: 全部摆法, solutions: 其中获胜的摆法}
static func solve(level: Dictionary) -> Dictionary:
	var chars: Array = level.hand.filter(func(id): return CardDB.card(id).type == "character")
	var equips: Array = level.hand.filter(func(id): return CardDB.card(id).type == "equipment")
	var arrangements := _arrangements(chars, equips)
	var solutions := arrangements.filter(func(team): return BattleSim.simulate(level.enemy, team).winner == 2)
	return {"arrangements": arrangements, "solutions": solutions}


static func describe_report(level_id: String, report: Dictionary) -> String:
	var name := TranslationServer.translate("level." + level_id)
	var total: int = report.arrangements.size()
	return "%s：%d 种摆法，%d 个解，通过率 %.2f%%" % [name, total, report.solutions.size(), 100.0 * report.solutions.size() / maxi(total, 1)]


static func describe_team(team: Array) -> String:
	var t := func(id): return String(TranslationServer.translate("card." + id))
	return " / ".join(team.map(func(u): return t.call(u[0]) + ("+" + t.call(u[1]) if u[1] != "" else "")))


## 全部不同的摆法：角色有序选取 k 个（k ≥ 1），每件装备不用或装给一个没装备的角色
static func _arrangements(chars: Array, equips: Array) -> Array:
	var seen := {}
	var result := []
	for order in _orders(chars):
		for team in _equip(order.map(func(c): return [c, ""]), equips, 0):
			var key := JSON.stringify(team)
			if not seen.has(key):
				seen[key] = true
				result.append(team)
	return result


static func _orders(pool: Array) -> Array:
	var result := []
	for i in pool.size():
		var rest := pool.duplicate()
		rest.remove_at(i)
		result.append([pool[i]])
		for tail in _orders(rest):
			result.append([pool[i]] + tail)
	return result


static func _equip(team: Array, equips: Array, index: int) -> Array:
	if index == equips.size():
		return [team]
	var result := _equip(team, equips, index + 1)  # 这件装备不用
	for i in team.size():
		if team[i][1] == "":
			var next := team.duplicate(true)
			next[i][1] = equips[index]
			result += _equip(next, equips, index + 1)
	return result
