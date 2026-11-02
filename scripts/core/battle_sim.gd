class_name BattleSim
extends RefCounted
## 纯逻辑战斗核心：给定双方阵容，一次算完整场战斗，返回结果和事件日志。不依赖场景节点。
## 规则见 docs/design/battle-rules.md；事件格式见 docs/plans/stage-2-battle-core.md 1.4 节。
## 用法：BattleSim.simulate([[角色 id, 装备 id], ...], [...])

## 事件日志的版本，规则或事件格式变化时加一，供以后的重播判断版本是否一致
const VERSION := 1
## 致命的攻击值
const LETHAL_ATTACK := 10000
## 平局：连续多少次交战无人阵亡
const NO_DEATH_ENGAGES := 20
## 普通技能的结算拍，先加后减
const BEATS := ["rage", "rally", "inspire", "corrode", "annihilate"]


class Unit:
	var uid: String  ## 座位-初始序号，如 "1-0"
	var side: int
	var card_id: String
	var equip_id: String
	var strength: int
	var timings: Array
	var normal_skills: Dictionary
	var special_skills: Dictionary
	var done_pre_battle := false
	var done_entering := false

	func _init(side_: int, index: int, card_id_: String, equip_id_: String) -> void:
		uid = "%d-%d" % [side_, index]
		side = side_
		card_id = card_id_
		equip_id = equip_id_
		var stats := CardDB.combine(card_id, equip_id)
		strength = stats.strength
		timings = stats.timings
		normal_skills = stats.normal_skills
		special_skills = stats.special_skills

	func describe() -> Dictionary:
		return {"uid": uid, "card_id": card_id, "equip_id": equip_id, "strength": strength, "timings": timings,
			"normal_skills": normal_skills.duplicate(), "special_skills": special_skills.duplicate()}


## 双方队列：side -> [Unit]，第 0 个是交战位
var fields := {1: [], 2: []}
var events: Array = []
## 0 = 未结束，1/2 = 该方胜，3 = 平局
var winner := 0
var _no_death_engages := 0


func _init(p1: Array, p2: Array) -> void:
	for side in [1, 2]:
		var lineup: Array = p1 if side == 1 else p2
		for i in lineup.size():
			fields[side].append(Unit.new(side, i, lineup[i][0], lineup[i][1]))


## 算完整场战斗，返回 {winner, p1, p2, events}；p1/p2 是双方幸存单位的战力
static func simulate(p1: Array, p2: Array) -> Dictionary:
	var sim := BattleSim.new(p1, p2)
	sim.run()
	return {
		"winner": sim.winner,
		"p1": sim.fields[1].map(func(u): return u.strength),
		"p2": sim.fields[2].map(func(u): return u.strength),
		"events": sim.events,
	}


func run() -> void:
	events.append({"type": "start", "version": VERSION,
		"p1": fields[1].map(func(u): return u.describe()), "p2": fields[2].map(func(u): return u.describe())})
	pre_battle_phase()
	if winner == 0:
		main_phase()


## 战前阶段：第 k 步取双方各自第 k 个未执行过的单位，有战前时机的执行普通技能，之后判死
func pre_battle_phase() -> void:
	while not check_winner():
		var pair := []
		for side in [1, 2]:
			var unit = null
			for u in fields[side]:
				if not u.done_pre_battle:
					unit = u
					u.done_pre_battle = true
					break
			pair.append(unit)
		if pair[0] == null and pair[1] == null:
			return
		var actors := pair.filter(func(u): return u != null and "pre_battle" in u.timings)
		events.append({"type": "pre_battle", "units": pair.map(func(u): return u.uid if u else ""),
			"actors": actors.map(func(u): return u.uid)})
		resolve_timing(actors)
		settle_death()


## 主循环：有未触发的入场就先入场，否则交战；每步之后判死。
## 有人阵亡则"无人阵亡"计数清零，否则每次交战加一（入场不算）
func main_phase() -> void:
	while not check_winner():
		var engaged := false
		if not entering_step():
			engage_step()
			engaged = true
		if settle_death():
			_no_death_engages = 0
		elif engaged:
			_no_death_engages += 1


## 双方交战位里有入场时机、还没入场的单位执行入场；都没有则返回 false
func entering_step() -> bool:
	var actors := []
	for side in [1, 2]:
		var front: Unit = fields[side][0]
		if "on_enter" in front.timings and not front.done_entering:
			front.done_entering = true
			actors.append(front)
	if actors.is_empty():
		return false
	events.append({"type": "enter", "units": actors.map(func(u): return u.uid)})
	resolve_timing(actors)
	return true


## 交战：有交战时机的交战位执行普通技能；双方都活着则对撞，再结算反噬
func engage_step() -> void:
	var fronts: Array = [fields[1][0], fields[2][0]]
	var actors := fronts.filter(func(u): return "on_engage" in u.timings)
	events.append({"type": "engage", "units": fronts.map(func(u): return u.uid), "actors": actors.map(func(u): return u.uid)})
	resolve_timing(actors)
	if fronts[0].strength <= 0 or fronts[1].strength <= 0:
		return
	var attacks := fronts.map(func(u): return LETHAL_ATTACK if u.special_skills.has("lethal") else u.strength)
	events.append({"type": "clash", "attacks": attacks,
		"effects": [damage(fronts[0], attacks[1], "clash"), damage(fronts[1], attacks[0], "clash")]})
	var backlash := []
	for u in fronts:
		if u.special_skills.has("backlash"):
			backlash.append(damage(u, u.special_skills.backlash, "backlash"))
	if not backlash.is_empty():
		events.append({"type": "backlash", "effects": backlash})


## 一个时间节点：按拍结算这些单位的普通技能，每拍双方同时
func resolve_timing(actors: Array) -> void:
	for skill in BEATS:
		var effects := []
		for u in actors:
			if u.normal_skills.has(skill):
				effects.append_array(apply_skill(u, skill, u.normal_skills[skill]))
		if not effects.is_empty():
			events.append({"type": "beat", "skill": skill, "effects": effects})


## 结算一条普通技能，返回产生的效果
func apply_skill(u: Unit, skill: String, value: int) -> Array:
	var enemies: Array = fields[3 - u.side]
	match skill:
		"rage":
			return [buff(u, u, value, skill)]
		"rally":
			var total := 0
			for partner in fields[u.side]:
				total += partner.normal_skills.get("rally", 0)
			return [buff(u, u, total, skill)]
		"inspire":
			return fields[u.side].map(func(target): return buff(u, target, value, skill))
		"corrode":
			if enemies.is_empty():
				return []
			return [damage(enemies[0], value, skill)]
		"annihilate":
			return enemies.map(func(target): return damage(target, value, skill))
	push_error("BattleSim：未知的普通技能 %s" % skill)
	return []


func buff(source: Unit, target: Unit, amount: int, skill: String) -> Dictionary:
	target.strength += amount
	return {"kind": "buff", "source": source.uid, "unit": target.uid, "skill": skill, "amount": amount, "strength": target.strength}


## 伤害流程：减去坚固（最低 0）→ 仍大于 0 且有庇护则挡下并消耗庇护 → 扣战力
func damage(target: Unit, amount: int, source: String) -> Dictionary:
	var sturdy: int = target.special_skills.get("sturdy", 0)
	var dealt := maxi(0, amount - sturdy)
	var sheltered := false
	if dealt > 0 and target.special_skills.has("shelter"):
		target.special_skills.erase("shelter")
		sheltered = true
		dealt = 0
	target.strength -= dealt
	return {"kind": "damage", "unit": target.uid, "source": source, "amount": amount,
		"sturdy": sturdy, "shelter": sheltered, "dealt": dealt, "strength": target.strength}


## 判死：一次性移除双方所有战力 ≤0 的单位，返回是否有人阵亡
func settle_death() -> bool:
	var dead := []
	for side in [1, 2]:
		for u in fields[side]:
			if u.strength <= 0:
				dead.append(u.uid)
		fields[side] = fields[side].filter(func(u): return u.strength > 0)
	if dead.is_empty():
		return false
	events.append({"type": "death", "units": dead})
	return true


## 判胜负和平局，结束时记下 end 事件，返回是否结束。
## 平局：双方同时全灭，或连续 NO_DEATH_ENGAGES 次交战无人阵亡（只在主循环里计数）
func check_winner() -> bool:
	var reason := "wipe"
	if fields[1].is_empty() and fields[2].is_empty():
		winner = 3
	elif fields[2].is_empty():
		winner = 1
	elif fields[1].is_empty():
		winner = 2
	elif _no_death_engages >= NO_DEATH_ENGAGES:
		winner = 3
		reason = "no_death"
	else:
		return false
	events.append({"type": "end", "winner": winner, "reason": reason})
	return true
