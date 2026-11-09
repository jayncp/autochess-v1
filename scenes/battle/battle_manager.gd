extends Node2D
## 战斗场景：开战时用 BattleSim 一次算完整场，再按事件日志播放动画。
## 动画和跳过用的是同一份结算，结果必然一致。事件格式见 scripts/core/battle_sim.gd 开头。

signal back_to_last_scene

# 出列、对撞时朝中间移动的距离，按两排卡之间的空隙算；和缩放一起给出。节奏和特效之后单独设计
const PREPARE := [0.08, 1.03]
const ACT := [0.11, 1.06]
const CLASH := [0.245, 1.03]
# 动画时长（秒，1 倍速）
const PREPARE_TIME := 0.5
const ACT_TIME := 0.5
const ACT_DOWN_TIME := 0.75
const TRIGGER_TEXT_TIME := 0.1
const BEAT_TIME := 0.3
const DEATH_TIME := 1.5
const REFILL_TIME := 0.6
## 连续多少次完全相同的交战算僵持，之后直接跳到结束
const STALEMATE_REPEATS := 3
## 双方当前在场的卡牌节点
var player_battle_fields = {1: [], 2: []}
## 0 = 未结束；1/2 = 该方胜；3 = 平局。播放结束或跳过后才设置
var winner = 0
var is_pre_battle = false

var battle_speed = 1.0
var have_been_skipped = false
## 战斗界面（布局和状态显示）
@onready var _ui = $".."

var _result: Dictionary
var _cards := {}  # uid -> 卡牌节点
var _specials := {}  # uid -> 当前特殊技能（庇护会被消耗）
var _special_sources := {}  # uid -> 特殊技能来自哪张卡（描述型效果的飘字用它的名字）
var _tweens: Array[Tween] = []


#==============================================
##### 初始化 #####
#==============================================
func _ready() -> void:
	show_battle_speed()
	load_player_deck()


## 按界面的布局摆卡（界面大小变化时也调用）：卡牌缩放、每个位置
func relayout() -> void:
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			var card = player_battle_fields[side][n]
			card.set_look(_ui.card_scale, false)
			card.position = _ui.slot_position(side, n)


func load_player_deck():
	var lineups := {1: [], 2: []}
	for side in [1, 2]:
		var cards: Array = global_var.battle_card_list_1 if side == 1 else global_var.battle_card_list_2
		var equips: Array = global_var.battle_equip_list_1 if side == 1 else global_var.battle_equip_list_2
		for n in cards.size():
			lineups[side].append([cards[n], equips[n]])
	_result = BattleSim.simulate(lineups[1], lineups[2])
	for side in [1, 2]:
		var units: Array = _result.events[0]["p%d" % side]
		for n in units.size():
			var u: Dictionary = units[n]
			var new_card = load_card.generate(u.card_id, u.equip_id)
			# 战斗中始终显示实时状态：合并后的时机和基础技能、当前战斗力
			new_card.face.start_live(u)
			$"../cards".add_child(new_card)
			player_battle_fields[side].append(new_card)
			_cards[u.uid] = new_card
			_specials[u.uid] = u.special_skills.duplicate()
			_special_sources[u.uid] = u.special_source


#==============================================
##### 按钮 #####
#==============================================

### "速度"按钮：循环调整动画速度，只影响之后的动画
func _on_speed_button_pressed() -> void:
	cycle_battle_speed()
	show_battle_speed()

func show_battle_speed():
	_ui.set_speed_text(battle_speed)

func cycle_battle_speed():
	if battle_speed == 1.0:
		battle_speed = 2.0
	elif battle_speed == 2.0:
		battle_speed = 5.0
	elif battle_speed == 5.0:
		battle_speed = 20.0
	else:
		battle_speed = 1.0
	return battle_speed

### "跳过战斗"按钮：停止播放，直接显示最终局面
func _on_skip_button_pressed() -> void:
	if is_pre_battle and winner == 0 and not have_been_skipped:
		have_been_skipped = true
		show_final_state()

### "开始战斗"按钮：开始播放；结束后变成"返回"
func _on_start_battle_pressed_battle() -> void:
	if not is_pre_battle:
		is_pre_battle = true
		_ui.show_phase("pre_battle", "")
		mark_front()
		await play_events()
		if not have_been_skipped:
			show_final_state()
	elif winner:
		emit_signal("back_to_last_scene")

func show_winner():
	_ui.show_result(winner, _result_text())


## 结束的原因（我方是下面一排）：谁全部阵亡、另一方幸存几人；平局是同时全灭或连续无人阵亡
func _result_text() -> String:
	match winner:
		2: return tr("ui.battle.enemy_wiped") % player_battle_fields[2].size()
		1: return tr("ui.battle.ally_wiped") % player_battle_fields[1].size()
	if _result.events[-1].reason == "no_death":
		return tr("ui.battle.no_death_draw") % BattleSim.NO_DEATH_ENGAGES
	return tr("ui.battle.both_wiped")


## 中间一带的计数："第 3 次交战 · 无人阵亡 1 / 20"
func _engage_text(engages: int, no_death: int) -> String:
	if engages == 0:
		return ""
	return tr("ui.battle.engage_count") % [engages, no_death, BattleSim.NO_DEATH_ENGAGES]


#==============================================
##### 播放 #####
#==============================================

## 按事件逐步播放；每一步（战前一步、入场、交战）包含它后面的特殊技能、拍、对撞和反噬
func play_events() -> void:
	var events: Array = _result.events
	var no_death_engages := 0
	var engages := 0
	var pre_battle_steps := 0
	var last_engage := ""
	var repeats := 0
	var i := 1  # 第 0 个是 start
	while i < events.size() and not have_been_skipped:
		var e: Dictionary = events[i]
		var step := [e]
		i += 1
		while i < events.size() and events[i].type in ["special", "beat", "clash", "backlash"]:
			step.append(events[i])
			i += 1
		match e.type:
			"pre_battle":
				pre_battle_steps += 1
				_ui.show_phase("pre_battle", tr("ui.battle.step") % pre_battle_steps)
				await play_step(e.units.filter(func(uid): return uid != ""), e.actors, "pre_battle", step)
			"enter":
				_ui.show_phase("on_enter", _engage_text(engages, no_death_engages))
				await play_step(e.units, e.units, "on_enter", step)
			"engage":
				engages += 1
				_ui.show_phase("on_engage", _engage_text(engages, no_death_engages))
				# 僵持：连续几次完全相同的交战，直接跳到结束
				var signature := JSON.stringify(step)
				repeats = repeats + 1 if signature == last_engage else 1
				last_engage = signature
				if repeats >= STALEMATE_REPEATS:
					_ui.show_note(tr("ui.battle.stalemate"))
					await wait(DEATH_TIME)
					break
				await play_step(e.units, e.actors, "on_engage", step)
				if have_been_skipped:
					return
				no_death_engages += 1
				_ui.show_note(_engage_text(engages, no_death_engages))
			"death":
				no_death_engages = 0
				last_engage = ""
				await play_death(e.units)
			"end":
				break


## 一步：上前 → 出列（时机图标发亮；入场、交战还有时机蓝字）→ 特殊技能（被唤醒的出列、出手、收回）→ 原本的逐拍
## → 对撞 → 反噬 → 收回
func play_step(units: Array, actors: Array, timing: String, step: Array) -> void:
	var unit_cards := units.map(func(uid): return _cards[uid])
	var actor_cards := actors.map(func(uid): return _cards[uid])
	animate_cards(unit_cards, PREPARE[0], PREPARE[1])
	await wait(PREPARE_TIME)
	if have_been_skipped:
		return
	if not actor_cards.is_empty():
		animate_cards(actor_cards, ACT[0], ACT[1])
		light_timing(actor_cards, timing)
		await wait(ACT_TIME)
		if timing != "pre_battle":
			for card in actor_cards:
				buff_text_effect(card, load_card.timing_name(timing), "blue")
			await wait(TRIGGER_TEXT_TIME)
	var woken_cards := []
	for e in step:
		if have_been_skipped:
			return
		if not woken_cards.is_empty() and not e.get("woken", false):
			await retract(woken_cards)
			woken_cards = []
		match e.type:
			"special":
				woken_cards = await play_special(e)
			"beat":
				await play_effects(e.effects, e.skill)
				await wait(BEAT_TIME)
			"clash":
				if not actor_cards.is_empty():
					animate_cards(actor_cards, -ACT[0], PREPARE[1])
					light_timing(actor_cards, "")
					await wait(ACT_DOWN_TIME)
					actor_cards = []
				await play_clash(e, unit_cards)
			"backlash":
				await play_effects(e.effects, "backlash")
				await wait(TRIGGER_TEXT_TIME)
	if not woken_cards.is_empty():
		await retract(woken_cards)
	if not actor_cards.is_empty():
		animate_cards(actor_cards, -ACT[0], PREPARE[1])
		light_timing(actor_cards, "")
		await wait(ACT_DOWN_TIME)
	if step[-1].type in ["clash", "backlash"]:
		animate_cards(unit_cards, -CLASH[0], PREPARE[1], 0.2)
		await wait(0.25)
	animate_cards(unit_cards, -PREPARE[0], 1.0)
	await wait(PREPARE_TIME)


## 出列的卡：时机图标发亮、卡牌发光（timing 为空表示熄灭）
func light_timing(cards: Array, timing: String) -> void:
	if have_been_skipped:
		return
	for card in cards:
		card.face.set_firing(timing)
		card.face.glow = timing != ""


## 双方交战位的卡加红框
func mark_front() -> void:
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			player_battle_fields[side][n].face.engaged = n == 0


## 对撞：双方向前，致命显示绿字，结算伤害
func play_clash(e: Dictionary, unit_cards: Array) -> void:
	animate_cards(unit_cards, CLASH[0], PREPARE[1], 0.2)
	await wait(0.25)
	var lethal := false
	for k in 2:
		if e.attacks[k] == BattleSim.LETHAL_ATTACK:
			buff_text_effect(unit_cards[k], tr("keyword.lethal"), "green")
			lethal = true
	if lethal:
		await wait(TRIGGER_TEXT_TIME)
	await play_effects(e.effects, "")
	await wait(0.2)


## 特殊技能阶段：发动者显示唤醒蓝字，被唤醒的出列；返回出列的卡，它们的拍播完后收回
func play_special(e: Dictionary) -> Array:
	for f in e.effects:
		buff_text_effect(_cards[f.source], tr("keyword." + e.skill), "blue")
	await wait(TRIGGER_TEXT_TIME)
	var woken: Array = e.effects.map(func(f): return _cards[f.unit])
	animate_cards(woken, ACT[0], ACT[1])
	for card in woken:
		card.face.glow = not have_been_skipped
	await wait(ACT_TIME)
	return woken


## 被唤醒的卡收回原位
func retract(cards: Array) -> void:
	animate_cards(cards, -ACT[0], 1.0)
	for card in cards:
		card.face.glow = false
	await wait(ACT_DOWN_TIME)


## 同时显示一组效果：增益绿字、财富黄字、伤害红字（交战伤害不显示数字），坚固、庇护随后显示绿字。
## 描述型特殊技能用来源卡的名字：改了战斗力的带数字（"队长 + 2"），没改的只弹名字（腐蚀被蟾蜍加成时）
func play_effects(effects: Array, skill: String) -> void:
	var defenses := []
	for f in effects:
		var card = _cards[f.unit]
		if f.kind == "buff":
			var label := _source_name(f.source) if f.skill in CardDB.DESCRIPTIVE_SPECIALS else tr("keyword." + f.skill)
			buff_text_effect(card, label + " + " + str(f.amount), "green")
		elif f.kind == "wealth":
			buff_text_effect(card, tr("keyword.wealth") + " + " + str(f.amount), "yellow")
			continue
		else:
			for uid in f.get("boosts", []):
				buff_text_effect(_cards[uid], _source_name(uid), "blue")
			if f.source != "clash":
				buff_text_effect(card, tr("keyword." + f.source) + " - " + str(f.amount), "red")
			if f.sturdy > 0 or f.shelter:
				defenses.append(f)
		apply_effect(f)
	if defenses.is_empty():
		return
	await wait(TRIGGER_TEXT_TIME)
	for f in defenses:
		if f.sturdy > 0:
			buff_text_effect(_cards[f.unit], tr("keyword.sturdy") + str(f.sturdy), "green")
		if f.shelter:
			buff_text_effect(_cards[f.unit], tr("keyword.shelter"), "green")


## 把一个效果写到卡面上：战力；庇护被消耗时更新特殊技能栏
func apply_effect(f: Dictionary) -> void:
	if have_been_skipped:
		return  # 跳过后最终局面已经摆好
	var card = _cards[f.unit]
	card.face.set_strength(f.strength)
	if f.kind == "damage" and f.shelter:
		_consume_shelter(f.unit)
		card.face.set_specials(_specials[f.unit])


func _source_name(uid: String) -> String:
	return tr("card." + _special_sources[uid])


## 庇护消耗一层，用完就去掉（和 BattleSim.damage 一致）
func _consume_shelter(uid: String) -> void:
	_specials[uid].shelter -= 1
	if _specials[uid].shelter <= 0:
		_specials[uid].erase("shelter")


## 阵亡：淡出并移出（P1 向上、P2 向下），之后后排补位
func play_death(uids: Array) -> void:
	if have_been_skipped:
		return
	for uid in uids:
		var card = _cards[uid]
		var side := int(uid.split("-")[0])
		player_battle_fields[side].erase(card)
		var tween := create_battle_tween()
		tween.tween_property(card, "modulate:a", 0, 1.0 / battle_speed)
		tween.tween_property(card, "position", card.position + Vector2(0, -500 if side == 1 else 500), 1.2 / battle_speed)
		card.face.engaged = false
	await wait(DEATH_TIME)
	if have_been_skipped:
		return
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			var card = player_battle_fields[side][n]
			var target: Vector2 = _ui.slot_position(side, n)
			if card.position != target:
				create_battle_tween().tween_property(card, "position", target, REFILL_TIME / battle_speed)
	mark_front()
	await wait(DEATH_TIME)


## 最终局面：停止所有动画，按结算结果摆好幸存单位，显示胜负
func show_final_state() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	for text in $"../buff_text_container".get_children():
		text.queue_free()
	# 从初始状态重新推演：播放途中跳过时，前面已经消耗过的庇护不能重复扣
	var alive := {1: [], 2: []}
	for side in [1, 2]:
		for u in _result.events[0]["p%d" % side]:
			alive[side].append(u.uid)
			_specials[u.uid] = u.special_skills.duplicate()
	for e in _result.events:
		if e.type == "death":
			for side in [1, 2]:
				alive[side] = alive[side].filter(func(uid): return uid not in e.units)
		for f in e.get("effects", []):
			if f.kind == "damage" and f.shelter:
				_consume_shelter(f.unit)
	for uid in _cards:
		var card = _cards[uid]
		var side := int(uid.split("-")[0])
		var n: int = alive[side].find(uid)
		if n == -1:
			card.queue_free()
			continue
		card.face.set_strength(_result["p%d" % side][n])
		card.face.set_specials(_specials[uid])
		card.face.set_firing("")
		card.face.glow = false
		card.face.engaged = false
		card.position = _ui.slot_position(side, n)
		card.scale = Vector2.ONE
		card.modulate.a = 1
	for side in [1, 2]:
		player_battle_fields[side] = alive[side].map(func(uid): return _cards[uid])
	winner = _result.winner
	show_winner()


#==============================================
##### 动画工具 #####
#==============================================

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds / battle_speed).timeout


func create_battle_tween() -> Tween:
	var tween := create_tween().set_parallel(true)
	_tweens.append(tween)
	return tween


## 双方卡牌朝对方移动 offset（两排卡之间空隙的比例；P1 向下、P2 向上），并缩放到 card_scale
func animate_cards(cards: Array, offset: float, card_scale: float, duration := 0.3) -> void:
	if cards.is_empty() or have_been_skipped:
		return
	var tween := create_battle_tween()
	for card in cards:
		var side := 1 if card in player_battle_fields[1] else 2
		var direction := 1 if side == 1 else -1
		tween.tween_property(card, "position", card.position + Vector2(0, offset * _ui.row_gap * direction), duration / battle_speed)
		tween.tween_property(card, "scale", Vector2(card_scale, card_scale), duration / battle_speed)


# 显示buff数字特效
func buff_text_effect(card, text, color):
	if have_been_skipped:
		return
	var buff_text_prefab = preload("res://scenes/battle/buff_text.tscn")
	var buff_text = buff_text_prefab.instantiate()
	$"../buff_text_container".add_child(buff_text)
	buff_text.position = card.position
	buff_text.get_node("buff_text_label").text = text
	var player: AnimationPlayer = buff_text.get_node("AnimationPlayer")
	player.animation_finished.connect(func(_name): buff_text.queue_free())
	player.play(color+"_text")
