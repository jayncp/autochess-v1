class_name BattleSim
extends RefCounted
## 纯逻辑战斗核心：给定双方阵容，一次算完整场战斗，返回结果和事件日志。不依赖场景节点。
## 规则见 docs/design/battle-rules.md。
## 用法：BattleSim.simulate([[角色 id, 装备 id], ...], [...])
##
## 事件日志（单位用"座位-初始序号"标识，如 "1-0"）：
## - start：version，p1/p2 为双方单位的初始属性（uid、card_id、equip_id、strength、timings、base_skills、special_skills、
##   special_source（特殊技能来自哪张卡））
## - pre_battle：units 为战前这一步的双方单位（没有则为 ""），actors 为其中在战前触发的单位
## - enter：units 为执行入场的交战位
## - engage：units 为双方交战位，actors 为其中在交战时触发的单位
##   （"触发"指时机是它，或者带这个时机的特殊技能）
## - special：特殊技能的一步里的一个技能（如唤醒）。skill 为技能，effects 为效果
## - beat：一拍。skill 为技能，effects 为这一拍的全部效果（含被动的效果）；woken 为真表示是被唤醒那一组的拍
## - clash：attacks 为双方攻击值（致命为 LETHAL_ATTACK），effects 为双方受到的伤害
## - backlash：effects 为反噬伤害
## - death：units 为阵亡单位
## - end：winner（1/2 = 该方胜，3 = 平局），reason（wipe = 全灭，no_death = 连续无人阵亡）
## 效果：buff {source, unit, skill（基础技能，或被动的 id，如 on_trigger_gain）, amount, strength}；
##       damage {unit, by（造成伤害的单位：腐蚀、湮灭是发动者，交战是对方交战位，反噬是自己）,
##              source（clash/corrode/annihilate/backlash）, amount, sturdy, shelter（是否被庇护挡下）, dealt, strength,
##              有结算加成（on_resolve_bonus）时还有 boosts（加成来自哪些单位）}；
##       wealth {source, unit, amount}（只做特效，不改战力）；awaken {source, unit}（unit 是被唤醒的单位）。
##       strength 是结算后的战力。

## 事件日志的版本，规则或事件格式变化时加一，供以后的重播判断版本是否一致
const VERSION := 5
## 致命的攻击值
const LETHAL_ATTACK := 10000
## 平局：连续多少次交战无人阵亡
const NO_DEATH_ENGAGES := 20
## 一个时点里特殊技能的步骤（battle-rules.md 4.1）：记 → 增 → 删 → 改 → 加 → 减 → 醒，之后才是基础技能。
## 每一步列出属于它的带时机的特殊技能，双方同时结算；被动不占步骤，挂在事件上（_on_trigger、_hit）
const STEPS := {
	"record": [],
	"grant": [],
	"clear": [],
	"raise": [],
	"gain": [],
	"damage": [],
	"awaken": ["awaken"],
}
## 被动：不带时机的描述型特殊技能，挂在事件上
const PASSIVES := ["on_trigger_gain", "on_resolve_bonus"]


class Unit:
	var uid: String  ## 座位-初始序号，如 "1-0"
	var side: int
	var card_id: String
	var equip_id: String
	var strength: int
	var timings: Array
	var base_skills: Dictionary
	var special_skills: Dictionary
	var special_source: String
	## 在哪些时机触发：自己的时机，加上带时机的特殊技能的时机
	var acting_timings: Array
	## 有没有带时机的特殊技能（没有的跳过特殊技能的各步）
	var has_timed_specials := false
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
		base_skills = stats.base_skills
		special_skills = stats.special_skills
		special_source = stats.special_source
		acting_timings = timings.duplicate()
		for params in special_skills.values():
			if params is Dictionary and params.has("timings"):
				acting_timings.append_array(params.timings)
				has_timed_specials = true

	func acts_at(timing: String) -> bool:
		return timing in acting_timings

	func describe() -> Dictionary:
		return {"uid": uid, "card_id": card_id, "equip_id": equip_id, "strength": strength, "timings": timings,
			"base_skills": base_skills.duplicate(), "special_skills": special_skills.duplicate(), "special_source": special_source}


## 双方队列：side -> [Unit]，第 0 个是交战位
var fields := {1: [], 2: []}
var events: Array = []
## 0 = 未结束，1/2 = 该方胜，3 = 平局
var winner := 0
var _no_death_engages := 0
## 双方被动的持有者：side -> {被动 id: [Unit]}，按队列顺序；判死后更新
var _holders := {1: {}, 2: {}}


func _init(p1: Array, p2: Array) -> void:
	for side in [1, 2]:
		var lineup: Array = p1 if side == 1 else p2
		for i in lineup.size():
			fields[side].append(Unit.new(side, i, lineup[i][0], lineup[i][1]))
		_index_passives(side)


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


## 战前阶段：第 k 步取双方各自第 k 个未执行过的单位，在战前触发的按 resolve_timing 结算，之后判死
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
		var actors := pair.filter(func(u): return u != null and u.acts_at("pre_battle"))
		events.append({"type": "pre_battle", "units": pair.map(func(u): return u.uid if u else ""),
			"actors": actors.map(func(u): return u.uid)})
		resolve_timing(actors, "pre_battle")
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


## 双方交战位里在入场时触发、还没入场的单位执行入场；都没有则返回 false
func entering_step() -> bool:
	var actors := []
	for side in [1, 2]:
		var front: Unit = fields[side][0]
		if front.acts_at("on_enter") and not front.done_entering:
			front.done_entering = true
			actors.append(front)
	if actors.is_empty():
		return false
	events.append({"type": "enter", "units": actors.map(func(u): return u.uid)})
	resolve_timing(actors, "on_enter")
	return true


## 交战：在交战时触发的交战位按 resolve_timing 结算；双方都活着则对撞，再结算反噬
func engage_step() -> void:
	var fronts: Array = [fields[1][0], fields[2][0]]
	var actors := fronts.filter(func(u): return u.acts_at("on_engage"))
	events.append({"type": "engage", "units": fronts.map(func(u): return u.uid), "actors": actors.map(func(u): return u.uid)})
	resolve_timing(actors, "on_engage")
	if fronts[0].strength <= 0 or fronts[1].strength <= 0:
		return
	var attacks := fronts.map(func(u): return LETHAL_ATTACK if u.special_skills.has("lethal") else u.strength)
	events.append({"type": "clash", "attacks": attacks,
		"effects": [damage(fronts[0], attacks[1], "clash", fronts[1]), damage(fronts[1], attacks[0], "clash", fronts[0])]})
	var backlash := []
	for u in fronts:
		if u.special_skills.has("backlash"):
			backlash.append(damage(u, u.special_skills.backlash, "backlash", u))
	if not backlash.is_empty():
		events.append({"type": "backlash", "effects": backlash})


## 一个时间节点的一轮（docs/design/battle-rules.md 4.1），从上到下：
## 特殊技能的各步 → 被唤醒的单位结算基础技能 → 原本在这个时机触发的单位结算基础技能。
## 每组都按拍结算，每拍双方同时，拍的顺序就是 CardDB.BASE_SKILLS。中途不判死
func resolve_timing(actors: Array, timing: String) -> void:
	resolve_beats(special_steps(actors, timing), true)
	resolve_beats(actors.filter(func(u): return timing in u.timings), false)


## 一组单位按拍结算基础技能；woken 标记被唤醒的那一组，回放据此让它们出列。
## 每个单位结算完一个技能，就是"触发了这个技能"，接着结算挂在触发上的被动
func resolve_beats(units: Array, woken: bool) -> void:
	for skill in CardDB.BASE_SKILLS:
		var effects := []
		for u in units:
			if u.base_skills.has(skill):
				effects.append_array(apply_skill(u, skill, u.base_skills[skill]))
				if _holders[u.side].has("on_trigger_gain"):
					effects.append_array(_on_trigger(u, skill))
		if effects.is_empty():
			continue
		var beat := {"type": "beat", "skill": skill, "effects": effects}
		if woken:
			beat.woken = true
		events.append(beat)


## 特殊技能的各步：双方带这个时机的特殊技能按 STEPS 的顺序结算，每一步里的每个技能记一个 special 事件。
## 返回被唤醒的单位
func special_steps(actors: Array, timing: String) -> Array:
	var woken := []
	var any := false
	for u in actors:
		any = any or u.has_timed_specials
	if not any:
		return woken
	for step in STEPS:
		for skill in STEPS[step]:
			var effects := []
			for u in actors:
				var params = u.special_skills.get(skill)
				if params is Dictionary and timing in params.timings:
					effects.append_array(apply_special(u, skill, woken))
			if not effects.is_empty():
				events.append({"type": "special", "skill": skill, "effects": effects})
	return woken


## 结算一个带时机的特殊技能，返回产生的效果；被唤醒的单位加进 woken
func apply_special(u: Unit, skill: String, woken: Array) -> Array:
	match skill:
		"awaken":
			var next := next_unit(u)
			if next == null:
				return []
			woken.append(next)
			return [{"kind": "awaken", "source": u.uid, "unit": next.uid}]
	push_error("BattleSim：未知的带时机的特殊技能 %s" % skill)
	return []


## 记下一方被动的持有者。被动在持有者还在队列中时生效，同名的各自生效
func _index_passives(side: int) -> void:
	var holders := {}
	for u in fields[side]:
		for id in u.special_skills:
			if id in PASSIVES:
				if not holders.has(id):
					holders[id] = []
				holders[id].append(u)
	_holders[side] = holders


## 被动：己方角色触发〈技能〉时，自身战斗力 +N（on_trigger_gain，如队长）
func _on_trigger(u: Unit, skill: String) -> Array:
	var effects := []
	for holder in _holders[u.side].get("on_trigger_gain", []):
		var params: Dictionary = holder.special_skills.on_trigger_gain
		if params.skill == skill:
			effects.append(buff(holder, holder, params.amount, "on_trigger_gain"))
	return effects


## 队列里紧挨在后面的己方单位，没有则返回 null
func next_unit(u: Unit) -> Unit:
	var line: Array = fields[u.side]
	var i := line.find(u)
	return line[i + 1] if i + 1 < line.size() else null


## 结算一条基础技能，返回产生的效果
func apply_skill(u: Unit, skill: String, value: int) -> Array:
	var enemies: Array = fields[3 - u.side]
	match skill:
		"rage":
			return [buff(u, u, value, skill)]
		"rally":
			var total := 0
			for partner in fields[u.side]:
				total += partner.base_skills.get("rally", 0)
			return [buff(u, u, total, skill)]
		"support":
			var next := next_unit(u)
			return [buff(u, next, value, skill)] if next else []
		"inspire":
			return fields[u.side].map(func(target): return buff(u, target, value, skill))
		"corrode":
			return [_hit(u, enemies[0], value, skill)] if not enemies.is_empty() else []
		"annihilate":
			return enemies.map(func(target): return _hit(u, target, value, skill))
		"wealth":
			return [{"kind": "wealth", "source": u.uid, "unit": u.uid, "amount": value}]
	push_error("BattleSim：未知的基础技能 %s" % skill)
	return []


## 腐蚀、湮灭的一下。被动：己方角色结算〈技能〉时，伤害 +N（on_resolve_bonus，如蟾蜍），
## 加在这一下上再进伤害流程，卡面数值不变；伤害记下加成来自哪些单位（boosts）
func _hit(u: Unit, target: Unit, value: int, skill: String) -> Dictionary:
	var holders = _holders[u.side].get("on_resolve_bonus")
	if holders == null:
		return damage(target, value, skill, u)
	var bonus := 0
	var boosts := []
	for holder in holders:
		var params: Dictionary = holder.special_skills.on_resolve_bonus
		if params.skill == skill:
			bonus += params.amount
			boosts.append(holder.uid)
	var hit := damage(target, value + bonus, skill, u)
	if not boosts.is_empty():
		hit.boosts = boosts
	return hit


func buff(source: Unit, target: Unit, amount: int, skill: String) -> Dictionary:
	target.strength += amount
	return {"kind": "buff", "source": source.uid, "unit": target.uid, "skill": skill, "amount": amount, "strength": target.strength}


## 伤害流程：有庇护就挡下这次伤害、消耗一层（先于坚固）→ 否则减去坚固（最低 0）→ 扣战力。by 是造成伤害的单位
func damage(target: Unit, amount: int, source: String, by: Unit) -> Dictionary:
	var sheltered := amount > 0 and target.special_skills.has("shelter")
	var sturdy := 0
	var dealt := 0
	if sheltered:
		target.special_skills.shelter -= 1
		if target.special_skills.shelter <= 0:
			target.special_skills.erase("shelter")
	else:
		sturdy = target.special_skills.get("sturdy", 0)
		dealt = maxi(0, amount - sturdy)
	target.strength -= dealt
	return {"kind": "damage", "unit": target.uid, "by": by.uid, "source": source, "amount": amount,
		"sturdy": sturdy, "shelter": sheltered, "dealt": dealt, "strength": target.strength}


## 判死：一次性移除双方所有战力 ≤0 的单位，返回是否有人阵亡
func settle_death() -> bool:
	var dead := []
	for side in [1, 2]:
		var count := dead.size()
		for u in fields[side]:
			if u.strength <= 0:
				dead.append(u.uid)
		if dead.size() > count:
			fields[side] = fields[side].filter(func(u): return u.strength > 0)
			_index_passives(side)
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
