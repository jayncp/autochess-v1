extends Node2D
## 战斗场景：开战时用 BattleSim 一次算完整场，再按事件日志播放动画。
## 动画和跳过用的是同一份结算，结果必然一致。事件格式见 scripts/core/battle_sim.gd 开头。

signal back_to_last_scene

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
## 连续多少次交战无人阵亡后显示计数
const NO_DEATH_HINT_FROM := 10

var player_slots = {1: [], 2: []}
## 双方当前在场的卡牌节点（实时状态开关会遍历它们）
var player_battle_fields = {1: [], 2: []}
## 0 = 未结束；1/2 = 该方胜；3 = 平局。播放结束或跳过后才设置
var winner = 0
var is_pre_battle = false

var battle_speed = 1.0
var have_been_skipped = false
@onready var speed_button = $"../speed_button"

var _result: Dictionary
var _cards := {}  # uid -> 卡牌节点
var _specials := {}  # uid -> 当前特殊技能（庇护会被消耗）
var _tweens: Array[Tween] = []


#==============================================
##### 初始化 #####
#==============================================
func _ready() -> void:
	$"../skill_union".button_pressed = true
	show_battle_speed()
	for i in range(1, 8):
		player_slots[1].append(get_node("../card_slots/card_slot%d" % i))
		player_slots[2].append(get_node("../card_slots/card_slot%d" % (i + 7)))
	load_player_deck()


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
			new_card.position = player_slots[side][n].position
			# 整合技能UI：合并后的时机和基础技能
			load_card.update_attribute_display(new_card, "all_time", load_card.timing_name(u.timings))
			load_card.update_attribute_display(new_card, "all_base_skill", load_card.base_skill_text(u.base_skills))
			new_card.get_node("card_skill_UI").modulate.a = 255
			new_card.get_node("all_time").visible = true
			new_card.get_node("all_base_skill").visible = true
			# 实时状态只显示红色的当前战力，隐藏黑色的装备战力，避免误解
			new_card.get_node("strength_2").visible = false
			$"../card_manager".add_child(new_card)
			player_battle_fields[side].append(new_card)
			_cards[u.uid] = new_card
			_specials[u.uid] = u.special_skills.duplicate()


#==============================================
##### 按钮 #####
#==============================================

### "速度"按钮：循环调整动画速度，只影响之后的动画
func _on_speed_button_pressed() -> void:
	cycle_battle_speed()
	show_battle_speed()

func show_battle_speed():
	speed_button.text = tr("ui.battle.speed") % str(battle_speed)

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
		$"../start_battle".text = tr("ui.battle.pre_battle_running")
		await play_events()
		if not have_been_skipped:
			show_final_state()
	elif winner:
		emit_signal("back_to_last_scene")

func show_winner():
	$"../start_battle".text = tr("ui.common.back")
	match winner:
		1: $"../output_text".text = tr("ui.battle.p1_win")
		2: $"../output_text".text = tr("ui.battle.p2_win")
		3: $"../output_text".text = tr("ui.battle.draw")


#==============================================
##### 播放 #####
#==============================================

## 按事件逐步播放；每一步（战前一步、入场、交战）包含它后面的拍、对撞和反噬
func play_events() -> void:
	var events: Array = _result.events
	var no_death_engages := 0
	var last_engage := ""
	var repeats := 0
	var i := 1  # 第 0 个是 start
	while i < events.size() and not have_been_skipped:
		var e: Dictionary = events[i]
		var step := [e]
		i += 1
		while i < events.size() and events[i].type in ["beat", "clash", "backlash"]:
			step.append(events[i])
			i += 1
		match e.type:
			"pre_battle":
				$"../start_battle".text = tr("ui.battle.pre_battle_running")
				await play_step(e.units.filter(func(uid): return uid != ""), e.actors, "", step)
			"enter":
				$"../start_battle".text = tr("ui.battle.running")
				await play_step(e.units, e.units, "on_enter", step)
			"engage":
				$"../start_battle".text = tr("ui.battle.running")
				# 僵持：连续几次完全相同的交战，直接跳到结束
				var signature := JSON.stringify(step)
				repeats = repeats + 1 if signature == last_engage else 1
				last_engage = signature
				if repeats >= STALEMATE_REPEATS:
					$"../output_text".text = tr("ui.battle.stalemate")
					await wait(DEATH_TIME)
					break
				await play_step(e.units, e.actors, "on_engage", step)
				if have_been_skipped:
					return
				no_death_engages += 1
				if no_death_engages >= NO_DEATH_HINT_FROM:
					$"../output_text".text = tr("ui.battle.no_death") % [no_death_engages, BattleSim.NO_DEATH_ENGAGES]
			"death":
				no_death_engages = 0
				last_engage = ""
				$"../output_text".text = ""
				await play_death(e.units)
			"end":
				break


## 一步：上前 → 放技能（时机蓝字）→ 逐拍 → 对撞 → 反噬 → 收回
func play_step(units: Array, actors: Array, timing: String, step: Array) -> void:
	var unit_cards := units.map(func(uid): return _cards[uid])
	var actor_cards := actors.map(func(uid): return _cards[uid])
	animate_cards(unit_cards, 30, 1.1)
	await wait(PREPARE_TIME)
	if have_been_skipped:
		return
	if not actor_cards.is_empty():
		animate_cards(actor_cards, 40, 1.2)
		await wait(ACT_TIME)
		if timing != "":
			for card in actor_cards:
				buff_text_effect(card, load_card.timing_name(timing), "blue")
			await wait(TRIGGER_TEXT_TIME)
	for e in step:
		if have_been_skipped:
			return
		match e.type:
			"beat":
				await play_effects(e.effects, e.skill)
				await wait(BEAT_TIME)
			"clash":
				if not actor_cards.is_empty():
					animate_cards(actor_cards, -40, 1.1)
					await wait(ACT_DOWN_TIME)
					actor_cards = []
				await play_clash(e, unit_cards)
			"backlash":
				await play_effects(e.effects, "backlash")
				await wait(TRIGGER_TEXT_TIME)
	if not actor_cards.is_empty():
		animate_cards(actor_cards, -40, 1.1)
		await wait(ACT_DOWN_TIME)
	if step[-1].type in ["clash", "backlash"]:
		animate_cards(unit_cards, -90, 1.1, 0.2)
		await wait(0.25)
	animate_cards(unit_cards, -30, 1.0)
	await wait(PREPARE_TIME)


## 对撞：双方向前，致命显示绿字，结算伤害
func play_clash(e: Dictionary, unit_cards: Array) -> void:
	animate_cards(unit_cards, 90, 1.1, 0.2)
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


## 同时显示一组效果：增益绿字、伤害红字（交战伤害不显示数字），坚固、庇护随后显示绿字
func play_effects(effects: Array, skill: String) -> void:
	var defenses := []
	for f in effects:
		var card = _cards[f.unit]
		if f.kind == "buff":
			buff_text_effect(card, tr("keyword." + skill) + " + " + str(f.amount), "green")
		else:
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
	card.strength = f.strength
	card.get_node("strength_1").text = str(f.strength)
	if f.kind == "damage" and f.shelter:
		_specials[f.unit].erase("shelter")
		load_card.update_attribute_display(card, "skill_3", load_card.special_skill_text(_specials[f.unit]))


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
	await wait(DEATH_TIME)
	if have_been_skipped:
		return
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			var card = player_battle_fields[side][n]
			if card.position != player_slots[side][n].position:
				create_battle_tween().tween_property(card, "position", player_slots[side][n].position, REFILL_TIME / battle_speed)
	await wait(DEATH_TIME)


## 最终局面：停止所有动画，按结算结果摆好幸存单位，显示胜负
func show_final_state() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	for text in $"../buff_text_container".get_children():
		text.queue_free()
	var alive := {1: [], 2: []}
	for side in [1, 2]:
		for u in _result.events[0]["p%d" % side]:
			alive[side].append(u.uid)
	var sheltered := {}  # 庇护被消耗过的单位
	for e in _result.events:
		if e.type == "death":
			for side in [1, 2]:
				alive[side] = alive[side].filter(func(uid): return uid not in e.units)
		for f in e.get("effects", []):
			if f.kind == "damage" and f.shelter:
				_specials[f.unit].erase("shelter")
				sheltered[f.unit] = true
	for uid in _cards:
		var card = _cards[uid]
		var side := int(uid.split("-")[0])
		var n: int = alive[side].find(uid)
		if n == -1:
			card.queue_free()
			continue
		card.strength = _result["p%d" % side][n]
		card.get_node("strength_1").text = str(card.strength)
		if sheltered.has(uid):
			load_card.update_attribute_display(card, "skill_3", load_card.special_skill_text(_specials[uid]))
		card.position = player_slots[side][n].position
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


## 双方卡牌朝对方移动 offset（P1 向下、P2 向上），并缩放到 card_scale
func animate_cards(cards: Array, offset: float, card_scale: float, duration := 0.3) -> void:
	if cards.is_empty() or have_been_skipped:
		return
	var tween := create_battle_tween()
	for card in cards:
		var side := 1 if card in player_battle_fields[1] else 2
		var direction := 1 if side == 1 else -1
		tween.tween_property(card, "position", card.position + Vector2(0, offset * direction), duration / battle_speed)
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
