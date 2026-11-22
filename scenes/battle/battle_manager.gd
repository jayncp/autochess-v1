extends Node2D
## 战斗场景：开战时用 BattleSim 一次算完整场，再按事件日志播放动画。
## 动画和跳过用的是同一份结算，结果必然一致。事件格式见 scripts/core/battle_sim.gd 开头。
## 演出和节奏的规格见 docs/plans/effects-pacing.md：一步是 轮到 → 发动 → 一拍一拍（方块亮起 → 飞过去 → 生效 → 留时间看）
## → 交战（蓄力、冲撞、弹回）→ 反噬 → 收回；阵亡是变灰、烧散、补位。

signal back_to_last_scene

## 各段时长（1 倍速，秒），和样稿 design-workspace/mockups/fx_player.js 的 PACE 一致
const PACE := {
	"start": 0.4,
	"step_in": 0.2,      # 轮到：这一步的双方单位向中间靠一点
	"idle_hold": 0.15,   # 战前这一步没人发动：停一下就退回
	"act_in": 0.25,      # 发动：再往前、放大、金光、时机图标亮
	"act_hold": 0.1,
	"cast": 0.15,        # 每一拍：发动者的技能方块先亮
	"fly_self": 0.12,    # 作用于自己（狂暴、集结、财富）
	"fly": 0.25,         # 飞到别人身上（支援；集结有别人贡献时）
	"lob": 0.3,          # 腐蚀：毒液弹抛过去
	"wave": 0.3,         # 振奋、湮灭：飞到最近的对象
	"spread": 0.05,      # 振奋、湮灭：每远一个位置晚这么久到
	"read": 0.5,         # 生效后留给玩家看的时间，然后才开始下一拍
	"defend": 0.15,      # 坚固先弹词条，过这么久再弹实际扣的数值
	"extra": 0.15,       # 同一拍里多出来的飘字（队长）错开
	"awaken": 0.3,       # 唤醒、神佑：弹词条、一道光到下一位
	"again": 0.3,        # 多一次：多出来的每一下晚这么久
	"round_turn": 0.15,  # 多一轮：重走的单位收回、再发动各这么久
	"round": 0.2,        # 多一轮：来源弹卡名后停一下
	"quick_read": 0.25,  # 多一轮重走的那几拍：内容和第一轮一样，留给玩家看的时间减半
	"sword": 0.55,       # 协战：光剑现出、飞过去、斩击
	"assist_gap": 0.35,  # 协战：每往后一个位置晚这么久
	"woken_in": 0.2,
	"woken_out": 0.2,
	"act_out": 0.2,      # 发动的卡在交战前收回
	"clash_wind": 0.1,   # 交战：后撤蓄力
	"clash_lunge": 0.12, # 冲向中间（加速）
	"hit_stop": 0.08,    # 撞上后停顿
	"clash_back": 0.25,  # 弹回
	"clash_read": 0.4,
	"lethal": 0.15,
	"backlash": 0.6,
	"step_out": 0.2,
	"death_grey": 0.15,  # 阵亡：先变灰
	"dissolve": 0.5,     # 再烧散
	"refill": 0.35,      # 后面的卡补位（烧散到七成时开始）
	"settle": 0.1,
	"stalemate": 1.5,
}
## 位移：两排卡之间空隙的比例（轮到、发动、交战冲到的位置、蓄力后撤）
const OFF := {"step": 0.06, "act": 0.15, "clash": 0.3, "wind": 0.03}
const ACT_SCALE := 1.04
## 特殊技能栏亮起多久
const SPECIAL_LIT_TIME := 0.6
## 连续多少次完全相同的交战算僵持，之后直接跳到结束
const STALEMATE_REPEATS := 3
const DISSOLVE := preload("res://scenes/battle/fx/dissolve.gdshader")
const BEAM_CYAN := Color("29c4d6")
const RALLY_SPARK := Color("ffb66e")
## 挂在基础技能结算上、给角色加战斗力的被动（回放时跟在那一下后面）
const PASSIVE_GAINS := ["on_trigger_gain", "on_trigger_boost", "on_resolve_gain", "on_enemy_resolve_gain_all"]
const ANNIHILATE_ORB := Color("b48cff")
const BLESS_BEAM := Color("f2c94c")
## 八咫镜这类给己方全体加战斗力的被动：每个人身上爆开的光
const PASSIVE_BURST := Color("fff4cc")

## 烧散用的噪声
static var _noise: ImageTexture

## 双方当前在场的卡牌节点
var player_battle_fields = {1: [], 2: []}
## 0 = 未结束；1/2 = 该方胜；3 = 平局。播放结束或跳过后才设置
var winner = 0
var is_pre_battle = false

## 开战时是设置里的默认速度，战斗中可以临时切换
var battle_speed: float = GameSettings.speed
var have_been_skipped = false
## 测回放时长（cli/replay_time.gd）：不真的等，只把 1 倍速下主流程要等的时间加起来；
## measured 按段落分开记（战前、入场、交战的各部分、多一轮、阵亡）
var measuring := false
var measured := {}
## 测时长时每个时点的用时：[时点类型, 秒, 里面的事件类型]
var measured_steps := []
var _clock := 0.0
var _segment := ""
## 正在播多一轮重走的那几拍（留给玩家看的时间减半）
var _quick := false
## 战斗界面（布局和状态显示）
@onready var _ui = $".."
@onready var _badges: BadgeLayer = $"../badges"
@onready var _fx: FxLayer = $"../fx"

var _result: Dictionary
var _cards := {}  # uid -> 卡牌节点
var _base := {}  # uid -> 当前基础技能（集结的光点从带集结值的队友飞来；战斗中会获得、清除、改数值）
var _specials := {}  # uid -> 当前特殊技能（庇护会被消耗，也会获得）
var _special_sources := {}  # uid -> 特殊技能来自哪张卡（描述型效果的飘字用它的名字）
var _tweens: Array[Tween] = []


#==============================================
##### 初始化 #####
#==============================================
func _ready() -> void:
	_fx.shake_targets = [$"../cards", _badges, _fx]
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
			new_card.set_meta("uid", u.uid)
			$"../cards".add_child(new_card)
			player_battle_fields[side].append(new_card)
			_cards[u.uid] = new_card
			_base[u.uid] = u.base_skills.duplicate()
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
	_fx.speed = battle_speed

func cycle_battle_speed():
	var speeds := GameSettings.SPEEDS
	battle_speed = speeds[(speeds.find(battle_speed) + 1) % speeds.size()]
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
		_fx.speed = battle_speed
		_ui.show_phase("pre_battle", "")
		mark_front()
		await play_events()
		if not have_been_skipped:
			show_final_state()
	elif winner:
		back_to_last_scene.emit()

## 显示胜负；闯关打赢了（我方是 2）记通关
func show_winner():
	if winner == 2 and global_var.battle_level:
		SaveData.mark_cleared(global_var.battle_level)
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
	_segment = "start"
	await wait(PACE.start)
	while i < events.size() and not have_been_skipped:
		var e: Dictionary = events[i]
		_segment = e.type
		var step := []
		i += 1
		while i < events.size() and events[i].type in ["round", "special", "beat", "clash", "assist", "backlash"]:
			step.append(events[i])
			i += 1
		var started := _clock
		var done := false
		match e.type:
			"pre_battle":
				pre_battle_steps += 1
				_ui.show_phase("pre_battle", tr("ui.battle.step") % pre_battle_steps)
				await play_step(_cards_of(e.units.filter(func(uid): return uid != "")), _cards_of(e.actors), "pre_battle", step)
			"enter":
				_ui.show_phase("on_enter", _engage_text(engages, no_death_engages))
				await play_step(_cards_of(e.units), _cards_of(e.units), "on_enter", step)
			"engage":
				engages += 1
				_ui.show_phase("on_engage", _engage_text(engages, no_death_engages))
				# 僵持：连续几次完全相同的交战，直接跳到结束
				var signature := JSON.stringify([e, step])
				repeats = repeats + 1 if signature == last_engage else 1
				last_engage = signature
				if repeats >= STALEMATE_REPEATS:
					_ui.show_note(tr("ui.battle.stalemate"))
					await wait(PACE.stalemate)
					done = true
				else:
					await play_step(_cards_of(e.units), _cards_of(e.actors), "on_engage", step)
					if have_been_skipped:
						return
					no_death_engages += 1
					_ui.show_note(_engage_text(engages, no_death_engages))
			"death":
				no_death_engages = 0
				last_engage = ""
				await play_death(e.units)
			"end":
				done = true
		if measuring and e.type != "end":
			measured_steps.append([e.type, _clock - started, step.map(func(x): return x.type)])
		if done:
			break


## 一步：轮到（向中间靠一点；战前的还亮青色光圈）→ 发动（再往前、放大、金光、时机图标亮）
## → 特殊技能、各拍（多一轮时再来一遍）、交战、协战、反噬 → 收回
func play_step(units: Array, actors: Array, timing: String, step: Array) -> void:
	var segment := _segment
	var marked: Array = units if timing == "pre_battle" else []
	_mark_turn(marked, 1.0)
	_pose(units, OFF.step, 1.0, PACE.step_in)
	await wait(PACE.step_in)
	if actors.is_empty() and timing == "pre_battle":
		await wait(PACE.idle_hold)
		_pose(units, 0.0, 1.0, PACE.step_out)
		_mark_turn(marked, 0.0)
		await wait(PACE.step_out)
		return
	if not actors.is_empty():
		_pose(actors, OFF.act, ACT_SCALE, PACE.act_in)
		light_timing(actors, timing)
		await wait(PACE.act_in + PACE.act_hold)
	var woken := []
	var out := not actors.is_empty()
	var extra_round := false
	var assisted := false
	for e in step:
		if have_been_skipped:
			_quick = false
			return
		extra_round = extra_round or e.type == "round"
		_quick = extra_round and e.type in ["special", "beat"]
		_segment = segment + "/" + ("extra_round" if extra_round and e.type in ["round", "special", "beat"] else e.type)
		if not woken.is_empty() and not e.get("woken", false):
			await _retract(woken)
			woken = []
		match e.type:
			"round":
				await play_round(e, actors, timing)
			"special":
				woken = await play_special(e)
			"beat":
				await play_beat(e)
			"clash":
				if out:
					_pose(actors, OFF.step, 1.0, PACE.act_out)
					light_timing(actors, "")
					await wait(PACE.act_out)
					out = false
				await play_clash(e, units)
			"assist":
				# 一个交战里的协战（按位置一个事件）一起播，后面的位置依次晚一点
				if not assisted:
					assisted = true
					await play_assist(step.filter(func(x): return x.type == "assist"))
			"backlash":
				await play_backlash(e)
	_quick = false
	if not woken.is_empty():
		await _retract(woken)
	_segment = segment
	var all := units.duplicate()
	for card in actors:
		if card not in all:
			all.append(card)
	_pose(all, 0.0, 1.0, PACE.step_out)
	light_timing(all, "")
	_mark_turn(marked, 0.0)
	await wait(PACE.step_out)


## 出列的卡：时机图标发亮、卡牌发光（timing 为空表示熄灭）
func light_timing(cards: Array, timing: String) -> void:
	if have_been_skipped:
		return
	for card in cards:
		card.face.set_firing(timing)
		card.face.glow = timing != ""


## 发动者的技能方块亮起（skill 为空表示熄灭）
func light_skill(cards: Array, skill: String) -> void:
	if have_been_skipped:
		return
	for card in cards:
		card.face.firing_skill = skill


## 双方交战位的卡加红框
func mark_front() -> void:
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			player_battle_fields[side][n].face.engaged = n == 0


## 多一轮：来源的特殊技能栏亮起、弹卡名（连线到重走的单位）；重走的单位收回一点再发动，这一轮没有的单位收回等着
func play_round(e: Dictionary, actors: Array, timing: String) -> void:
	var cards := _cards_of(e.units)
	for k in e.units.size():
		_character_effect("extra_round", e.sources[k], e.units[k], 0)
	var waiting := actors.filter(func(card): return card not in cards)
	_pose(actors, OFF.step, 1.0, PACE.round_turn)
	light_timing(waiting, "")
	await wait(PACE.round_turn)
	_pose(cards, OFF.act, ACT_SCALE, PACE.round_turn)
	light_timing(cards, timing)
	await wait(PACE.round_turn + PACE.round)


## 特殊技能的一步：
## - 唤醒：发动者弹"唤醒"、特殊技能栏亮起，一道光连到下一位，下一位出列；返回出列的卡，它们的拍播完后收回；
## - 神佑：发动者弹"神佑"、特殊技能栏亮起，一道金光连到下一位，下一位弹"庇护"、罩上保护罩；
## - 描述型（获得、复制、清除、改数值、加战斗力、造成伤害）：见 _play_effect
func play_special(e: Dictionary) -> Array:
	if e.skill in CardDB.DESCRIPTIVE_SPECIALS:
		await _play_effect(e)
		return []
	if e.skill == "bless":
		for f in e.effects:
			var source = _cards[f.source]
			_badge(source, FloatBadge.keyword(e.skill))
			_light_special(source)
			if _detail() == 2:
				_spawn_later(PACE.awaken * 0.15, FxEffect.Kind.BEAM, PACE.awaken + 0.2, {from = source, to = _cards[f.unit], color = BLESS_BEAM})
			_grant_later(f, PACE.awaken)
		await wait(PACE.awaken + _read())
		return []
	var woken := []
	for f in e.effects:
		var source = _cards[f.source]
		_badge(source, FloatBadge.keyword(e.skill))
		_light_special(source)
		if _detail() == 2:
			_spawn_later(PACE.awaken * 0.15, FxEffect.Kind.BEAM, PACE.awaken + 0.2, {from = source, to = _cards[f.unit], color = BEAM_CYAN})
		woken.append(_cards[f.unit])
	await wait(PACE.awaken)
	_pose(woken, OFF.act, ACT_SCALE, PACE.woken_in)
	for card in woken:
		card.face.glow = not have_been_skipped
	await wait(PACE.woken_in + PACE.act_hold)
	return woken


## 描述型特殊技能：来源卡的特殊技能栏亮起、弹卡名（一张卡弹一次），白线连到作用对象（复制是从被复制的卡连过来）；
## 作用对象上：获得弹词条或技能，技能方块和特殊技能栏更新（和开战时不同的标紫）；加战斗力弹卡名和数值；伤害弹卡名和扣的数值
func _play_effect(e: Dictionary) -> void:
	var named := {}
	for f in e.effects:
		var source: String = f.by if f.kind == "damage" else f.source
		var target: String = f.from if f.kind == "copy" else f.unit
		if f.kind == "buff":
			# 一个来源给几个角色加战斗力（神裁者）：卡名只弹一次，其余的直接更新战斗力
			if named.has(source):
				apply_effect(f)
			else:
				_land(f, 0.0)
			named[source] = true
			continue
		if not named.has(source):
			_character_effect(e.skill, source, target, 0)
			named[source] = true
		elif _detail() == 2 and target != source:
			_spawn(FxEffect.Kind.THREAD, 0.5, {from = _cards[source], to = _cards[target]})
		if f.kind == "damage":
			_land(f, PACE.awaken)
		else:
			_grant_later(f, PACE.awaken)
	await wait(PACE.awaken + _read())


## 技能的变化（获得、复制、清除、改数值）写进 _base、_specials；回放和最终局面共用
func _apply_change(f: Dictionary) -> void:
	match f.kind:
		"grant":
			var skills: Dictionary = _base[f.unit] if f.skill in CardDB.BASE_SKILLS else _specials[f.unit]
			skills[f.skill] = f.value
		"copy":
			_base[f.unit] = f.skills.duplicate()
		"clear":
			_base[f.unit] = {}
		"raise":
			_base[f.unit][f.skill] = f.value


## 技能的变化在 delay 之后显示到卡面上：获得弹词条或技能（有庇护就罩上保护罩），改数值弹技能，清除时卡面闪一下
func _grant_later(f: Dictionary, delay: float) -> void:
	await _after(delay)
	if have_been_skipped:
		return
	_apply_change(f)
	var card = _cards[f.unit]
	card.face.set_base_skills(_base[f.unit])
	card.face.set_specials(_specials[f.unit])
	# 层数、技能值的变化是白字（"庇护 +2""集结 +1""腐蚀 +3"），没有数值的词条只弹名字
	match f.kind:
		"grant":
			if f.skill in CardDB.BASE_SKILLS:
				_badge(card, FloatBadge.skill(f.skill, f.amount, true))
			else:
				_badge(card, FloatBadge.keyword(f.skill, f.amount, true))
				_light_special(card)
		"raise":
			_badge(card, FloatBadge.skill(f.skill, f.amount, true))
		"clear":
			_spawn(FxEffect.Kind.FLASH, 0.3, {to = card})


## 被唤醒的卡收回原位
func _retract(cards: Array) -> void:
	_pose(cards, 0.0, 1.0, PACE.woken_out)
	for card in cards:
		card.face.glow = false
	await wait(PACE.woken_out)


## 一拍：发动者的方块亮起 → 飞向作用对象（或在自己身上爆开）→ 生效（飘字、战斗力）→ 留时间看。双方同时
func play_beat(e: Dictionary) -> void:
	var skill: String = e.skill
	var casters := _casters(e)
	var fly := _fly_time(skill, casters)
	light_skill(casters, skill)
	await wait(PACE.cast * (0.6 if _quick else 1.0))
	if have_been_skipped:
		return
	var color: Color = FloatBadge.SKILL_COLORS[skill]
	for caster in casters:
		match skill:
			"rage":
				_spawn(FxEffect.Kind.CLAW, 0.4, {to = caster})
			"rally":
				var helpers := _rally_helpers(caster)
				if not helpers.is_empty() and _detail() == 2:
					_spawn(FxEffect.Kind.SPARKS, fly, {to = caster, helpers = helpers, color = RALLY_SPARK})
				_spawn_later(fly, FxEffect.Kind.BURST, 0.4, {to = caster, color = color})
			"wealth":
				_spawn(FxEffect.Kind.COINS, 0.7, {to = caster})
	var last := fly
	var defended := 0.0
	var raised := {}
	var raises := {}  # 改数值按"角色、技能、第几次"合成一条：[效果, 最晚的时间]
	var mirrors := {}  # 八咫镜：持有者 -> 这一拍的效果
	for f in e.effects:
		var target = _cards[f.unit]
		# 多一次：多出来的每一下依次晚一点，第一个效果出现时来源弹卡名
		var start: float = f.get("again", 0) * PACE.again
		var delay := fly + start
		if start > 0 and f == e.effects.filter(func(g): return g.get("again") == f.again and g.get("again_by") == f.again_by)[0]:
			_character_effect_later(start, "extra_resolve", f.again_by, f.by if f.kind == "damage" else f.source)
		# 萨满这类：触发后改数值，来源弹一次卡名；同一个角色同时被几个来源改（两个萨满），白字合成一条
		if f.kind == "raise":
			var key := "%s/%d" % [f.source, f.get("again", 0)]
			if not raised.has(key):
				raised[key] = true
				_character_effect_later(delay + PACE.extra, "on_trigger_raise", f.source, f.unit)
			var group := "%s/%s/%d" % [f.unit, f.skill, f.get("again", 0)]
			if not raises.has(group):
				raises[group] = [[], 0.0]
			raises[group][0].append(f)
			raises[group][1] = maxf(raises[group][1], delay + PACE.extra)
			last = maxf(last, delay + PACE.extra)
			continue
		# 八咫镜：等对方这一拍全部结算完，合起来显示一次
		if f.kind == "buff" and f.skill == "on_enemy_resolve_gain_all":
			if not mirrors.has(f.source):
				mirrors[f.source] = []
			mirrors[f.source].append(f)
			continue
		if skill in ["inspire", "annihilate"] and _detail() == 2:
			var side_cards: Array = player_battle_fields[_side(target)]
			# 振奋从发动者向两边扩，湮灭从对方交战位往后
			var origin: int = side_cards.find(_cards[f.source]) if skill == "inspire" else 0
			delay += PACE.spread * absi(side_cards.find(target) - origin)
		if f.kind == "buff" and f.skill in PASSIVE_GAINS:
			delay += PACE.extra
			last = maxf(last, delay)
			# 队长这类：触发技能的是别的卡时，从那张卡连一道白线过来
			var holder = _cards[f.source]
			var trigger = casters.filter(func(c): return _side(c) == _side(holder) and c != holder)
			_land(f, delay, trigger[0] if not trigger.is_empty() else null)
			continue
		if _detail() == 2:
			var caster = _cards[f.by] if f.kind == "damage" else _cards[f.source]
			match skill:
				"support", "inspire":
					if target != caster:
						_spawn_later(start, FxEffect.Kind.ORB, delay - start, {from = caster, to = target, color = color})
				"corrode":
					_spawn_later(start, FxEffect.Kind.VENOM, delay - start, {from = caster, to = target})
				"annihilate":
					_spawn_later(start, FxEffect.Kind.ORB, delay - start, {from = caster, to = target, color = ANNIHILATE_ORB, big = true})
		# 蟾蜍这类：出手时特殊技能栏亮起、弹卡名，白线连到被加成的那一下
		for uid in f.get("boosts", []):
			_character_effect("on_resolve_bonus", uid, f.unit, 0, "", delay + 0.45)
		if f.kind == "damage":
			# 庇护、坚固、减半先弹名字，过一会儿才弹扣的数值（坚固和减半都有时等两次）
			var steps := 1 if f.shelter else int(f.sturdy > 0) + int(f.has("halved"))
			defended = maxf(defended, PACE.defend * steps)
		_land(f, delay)
		last = maxf(last, delay)
	for group in raises.values():
		_raise_later(group[0], group[1])
	if not mirrors.is_empty():
		last += PACE.extra
		for holder in mirrors:
			_mirror_later(holder, mirrors[holder], last)
	await wait(last + _read() + defended)
	light_skill(casters, "")


## 对撞：后撤蓄力 → 冲向中间（发动致命的一方弹"致命"）→ 撞上：冲击光、画面震动、伤害 → 停顿 → 弹回
func play_clash(e: Dictionary, unit_cards: Array) -> void:
	_pose(unit_cards, OFF.step - OFF.wind, 1.0, PACE.clash_wind)
	await wait(PACE.clash_wind)
	if have_been_skipped:
		return
	var lethal := false
	for k in 2:
		if e.attacks[k] == BattleSim.LETHAL_ATTACK:
			_badge(unit_cards[k], FloatBadge.keyword("lethal"))
			_light_special(unit_cards[k])
			lethal = true
		elif _specials[_uid(unit_cards[k])].has("lethal") and _specials[_uid(unit_cards[1 - k])].has("immune_lethal"):
			# 对方免疫致命：致命无效，对方弹"免疫致命"
			_badge(unit_cards[1 - k], FloatBadge.keyword("immune_lethal"))
			_light_special(unit_cards[1 - k])
	_pose(unit_cards, OFF.clash, 1.0, PACE.clash_lunge, Tween.TRANS_QUAD, Tween.EASE_IN)
	await wait(PACE.clash_lunge)
	if have_been_skipped:
		return
	if _detail() > 0:
		_spawn(FxEffect.Kind.IMPACT, 0.45, {from = unit_cards[0], to = unit_cards[1]})
		_fx.shake((14.0 if lethal else 8.0) * _ui.card_scale, 0.22)
	var defended := false
	for f in e.effects:
		defended = defended or f.shelter or f.sturdy > 0
		_damage(f)
	await wait(PACE.hit_stop)
	_pose(unit_cards, OFF.step, 1.0, PACE.clash_back)
	await wait(PACE.clash_back + PACE.clash_read + (PACE.lethal if lethal else 0.0) + (PACE.defend if defended else 0.0))


## 协战（规格见 docs/plans/effects-pacing.md 2.2）：持有者特殊技能栏亮起、向前一顿，身前现出一把光剑，
## 加速飞向对方交战位、一道斩击，弹"协战"和扣的数值。按位置从前往后，每个位置晚 0.35 秒，同一位置双方同时
func play_assist(events: Array) -> void:
	var sword := PACE.sword if _detail() == 2 else 0.0
	for k in events.size():
		for f in events[k].effects:
			_assist_later(f, k * PACE.assist_gap, sword)
	await wait((events.size() - 1) * PACE.assist_gap + sword + PACE.read)


func _assist_later(f: Dictionary, delay: float, sword: float) -> void:
	await _after(delay)
	if have_been_skipped:
		return
	var holder = _cards[f.by]
	_light_special(holder)
	_pose([holder], OFF.step, 1.0, 0.12)
	_spawn(FxEffect.Kind.SWORD, sword, {from = holder, to = _cards[f.unit]})
	await _after(0.12)
	_pose([holder], 0.0, 1.0, 0.2)
	_land(f, sword * 0.85 - 0.12)


## 反噬：持有者特殊技能栏亮起、炸开一圈尖刺，随后受到伤害
func play_backlash(e: Dictionary) -> void:
	for f in e.effects:
		var card = _cards[f.unit]
		_light_special(card)
		_spawn(FxEffect.Kind.THORNS, 0.45, {to = card})
		_land(f, 0.12)
	await wait(PACE.backlash)


## 阵亡：变灰 → 烧散（带余烬）；烧散到七成时后面的卡补位（略带回弹），新的交战位亮红框
func play_death(uids: Array) -> void:
	if have_been_skipped:
		return
	for uid in uids:
		var card = _cards[uid]
		player_battle_fields[_side(card)].erase(card)
		card.face.engaged = false
		card.face.glow = false
		_dissolve(card)
	await wait(PACE.death_grey + PACE.dissolve * 0.7)
	if have_been_skipped:
		return
	var moving := []
	for side in [1, 2]:
		for n in player_battle_fields[side].size():
			var card = player_battle_fields[side][n]
			if card.position != _ui.slot_position(side, n):
				moving.append(card)
	_pose(moving, 0.0, 1.0, PACE.refill, Tween.TRANS_BACK, Tween.EASE_OUT)
	await wait(PACE.refill * 0.6)
	mark_front()
	await wait(PACE.refill * 0.4 + PACE.settle)


## 阵亡的卡套一个 CanvasGroup，整张卡（含光晕）先变灰再按噪声烧掉，烧完隐藏；余烬从卡上飘起
func _dissolve(card) -> void:
	if _detail() == 0:
		card.visible = false
		return
	if not _noise:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		noise.fractal_octaves = 3
		_noise = ImageTexture.create_from_image(noise.get_seamless_image(256, 256))
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE
	material.set_shader_parameter("noise", _noise)
	var group := CanvasGroup.new()
	group.fit_margin = 60.0
	group.clear_margin = 60.0
	group.material = material
	card.add_child(group)
	card.face.reparent(group, false)
	var tween := create_battle_tween().set_parallel(false)
	tween.tween_method(func(v: float): material.set_shader_parameter("grey", v), 0.0, 1.0, PACE.death_grey / battle_speed)
	tween.tween_method(func(v: float): material.set_shader_parameter("progress", v), 0.0, 1.0, PACE.dissolve / battle_speed) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func(): card.visible = false)
	var race: String = CardDB.sorted_races(CardDB.card(card.card_id).races)[0]
	_spawn_later(PACE.death_grey, FxEffect.Kind.EMBERS, PACE.dissolve + 0.35, {to = card, color = CardFace.RACE_COLORS[race]})


#==============================================
##### 效果：飘字、战斗力、受击 #####
#==============================================

## 一个效果在 delay 之后生效：增益、财富、伤害（规格见 docs/plans/effects-pacing.md 第 2、3 节）。
## trigger 是触发队长这类效果的卡（从它连白线过来）
func _land(f: Dictionary, delay: float, trigger = null) -> void:
	if delay > 0:
		await _after(delay)
	if have_been_skipped:
		return
	var card = _cards[f.unit]
	match f.kind:
		"buff":
			if f.skill in CardDB.DESCRIPTIVE_SPECIALS:
				_character_effect(f.skill, f.source, f.unit, f.amount, trigger.get_meta("uid") if trigger else "", 0.5)
				apply_effect(f)
				return
			if f.skill != "rally":  # 集结的光在 play_beat 里已经在发动者身上爆开
				_spawn(FxEffect.Kind.BURST, 0.35, {to = card, color = FloatBadge.SKILL_COLORS[f.skill]})
			_badge(card, FloatBadge.skill(f.skill, f.amount))
			apply_effect(f)
		"wealth":
			_badge(card, FloatBadge.skill("wealth", f.amount))
		"damage":
			match f.source:
				"corrode":
					_spawn(FxEffect.Kind.SPLASH, 0.6, {to = card})
				"annihilate":
					_spawn(FxEffect.Kind.BURST, 0.4, {to = card, color = ANNIHILATE_ORB})
			_damage(f)


## 受到伤害：庇护挡下 → 保护罩亮一圈（还有层数）或碎开（用完），只弹庇护；
## 坚固 → 金属光、弹坚固，减完还有伤害再弹实际扣的数值；战前减半同样先弹卡名再弹数值；否则直接弹数值，卡泛红抖动
func _damage(f: Dictionary) -> void:
	var card = _cards[f.unit]
	if f.has("immune"):
		# 致命伤害打在免疫致命的单位上：只弹"免疫致命"
		_badge(card, FloatBadge.keyword("immune_lethal"))
		_light_special(card)
		apply_effect(f)
		return
	if f.shelter:
		var left: int = _specials[f.unit].get("shelter", 1) - 1
		_spawn(FxEffect.Kind.SHIELD_HIT if left > 0 else FxEffect.Kind.SHIELD_BREAK, 0.55, {to = card})
		_badge(card, FloatBadge.keyword("shelter"))
		_light_special(card)
		apply_effect(f)
		return
	if f.sturdy > 0:
		_spawn(FxEffect.Kind.STEEL, 0.45, {to = card})
		_badge(card, FloatBadge.keyword("sturdy"))
		_light_special(card)
		if f.dealt == 0:
			apply_effect(f)
			return
		await _after(PACE.defend)
		if have_been_skipped:
			return
	if f.has("halved"):
		# 战前伤害减半（雪域神牛）：和坚固一样，先弹来源的卡名，过一会儿再弹减半后扣的数值
		_light_special(card)
		_badge(card, FloatBadge.card_name(_special_sources[f.unit]))
		await _after(PACE.defend)
		if have_been_skipped:
			return
	_badge(card, _damage_badge(f))
	apply_effect(f)
	if f.dealt > 0:
		_hurt(card)
		# 致命伤害命中：和致命对撞一样重震一下
		if f.source == "execute" and _detail() > 0:
			_fx.shake(14.0 * _ui.card_scale, 0.22)


## 伤害的飘字：交战是大号数字（致命命中是 −∞），反噬、协战是词条，腐蚀、湮灭是基础技能；没有造成伤害就不带数值
func _damage_badge(f: Dictionary) -> FloatBadge:
	var change = -f.dealt if f.dealt > 0 else null
	match f.source:
		"clash":
			return FloatBadge.clash(-INF if f.amount >= BattleSim.LETHAL_ATTACK else -f.dealt)
		"backlash", "assist":
			return FloatBadge.keyword(f.source, change)
	if f.source == "execute":
		return FloatBadge.clash(-INF) if f.dealt > 0 else FloatBadge.card_name(_special_sources[f.by], null)
	if f.source in CardDB.DESCRIPTIVE_SPECIALS:
		return FloatBadge.card_name(_special_sources[f.by], change)
	return FloatBadge.skill(f.source, change)


## 受击：卡面泛红、左右抖一下
func _hurt(card) -> void:
	if _detail() == 0:
		return
	_spawn(FxEffect.Kind.FLASH, 0.3, {to = card})
	var k: float = card.face.display_scale
	var tween := create_battle_tween().set_parallel(false)
	for x in [7.0, -6.0, 4.0, -2.0, 0.0]:
		tween.tween_property(card.face, "position:x", x * k, 0.05 / battle_speed)


## 角色专属效果（描述型特殊技能）的表现。要单独设计的效果，写一个 _fx_<效果 id>(持有者, 作用对象, 数值, 触发者) 方法就会用它；
## 没有就用通用方案：持有者的特殊技能栏亮起，弹白色卡名（特殊技能来自哪张卡就用哪张卡的名字），改了自己的战斗力就带数值；
## 作用在别人身上时从持有者连一道白线过去，由别人触发时从触发者连一道白线过来（线持续 thread_time 秒）
func _character_effect(effect_id: String, holder: String, target: String, amount: int, trigger := "", thread_time := 0.5) -> void:
	if has_method("_fx_" + effect_id):
		call("_fx_" + effect_id, holder, target, amount, trigger)
		return
	var card = _cards[holder]
	_light_special(card)
	_badge(card, FloatBadge.card_name(_special_sources[holder], amount if target == holder and amount != 0 else null))
	if _detail() < 2:
		return
	if target != holder:
		_spawn(FxEffect.Kind.THREAD, thread_time, {from = card, to = _cards[target]})
	if trigger and trigger != holder:
		_spawn(FxEffect.Kind.THREAD, thread_time, {from = _cards[trigger], to = card})


## 萨满这类：同一个角色同时被几个来源改同一个技能（两个萨满），写进卡面后只弹一条白字，数值相加
func _raise_later(fs: Array, delay: float) -> void:
	await _after(delay)
	if have_been_skipped:
		return
	var total := 0
	for f in fs:
		_apply_change(f)
		total += f.amount
	var card = _cards[fs[0].unit]
	card.face.set_base_skills(_base[fs[0].unit])
	_badge(card, FloatBadge.skill(fs[0].skill, total, true))


## 八咫镜：对方这一拍结算完之后合起来显示一次。持有者的特殊技能栏亮起，弹一次卡名和这一拍加的总数；
## 己方每个角色同时爆开一次光，战斗力更新到这一拍结束时的数
func _mirror_later(holder: String, fs: Array, delay: float) -> void:
	await _after(delay)
	if have_been_skipped:
		return
	var latest := {}
	var total := 0
	for f in fs:
		latest[f.unit] = f
		if f.unit == holder:
			total += f.amount
	_light_special(_cards[holder])
	_badge(_cards[holder], FloatBadge.card_name(_special_sources[holder], total if total != 0 else null))
	for uid in latest:
		_spawn(FxEffect.Kind.BURST, 0.35, {to = _cards[uid], color = PASSIVE_BURST})
		apply_effect(latest[uid])


func _character_effect_later(delay: float, effect_id: String, holder: String, target: String) -> void:
	await _after(delay)
	if not have_been_skipped:
		_character_effect(effect_id, holder, target, 0)


## 把一个效果写到卡面上：战力（变化时跳动）；庇护被消耗时更新特殊技能栏，用完就移除（保护罩跟着消失）
func apply_effect(f: Dictionary) -> void:
	if have_been_skipped:
		return  # 跳过后最终局面已经摆好
	var card = _cards[f.unit]
	var before: int = card.face.live.strength
	card.face.set_strength(_shown_strength(f.strength))
	if card.face.live.strength != before and _detail() > 0:
		card.face.pulse_strength(card.face.live.strength > before, 0.45 / battle_speed)
	if f.kind == "damage" and f.shelter:
		_consume_shelter(f.unit)
		card.face.set_specials(_specials[f.unit])


## 卡面上显示的战斗力：致命命中后是一个很大的负数（攻击按 LETHAL_ATTACK 算），显示成 0
func _shown_strength(value: int) -> int:
	return 0 if value <= -BattleSim.LETHAL_ATTACK / 4 else value


## 庇护消耗一层，用完就去掉（和 BattleSim.damage 一致）
func _consume_shelter(uid: String) -> void:
	_specials[uid].shelter -= 1
	if _specials[uid].shelter <= 0:
		_specials[uid].erase("shelter")


## 弹一个飘字；跳过后、20× 时不弹（建好的飘字直接释放）
func _badge(card, badge: FloatBadge) -> void:
	if have_been_skipped or _detail() == 0:
		badge.free()
		return
	_badges.add(card, badge, battle_speed)


## 特殊技能栏亮起一会儿；连着亮时以最后一次为准
func _light_special(card) -> void:
	if have_been_skipped:
		return
	card.face.firing_special = true
	var seconds: float = SPECIAL_LIT_TIME / battle_speed
	card.set_meta("special_lit_until", Time.get_ticks_msec() + seconds * 1000)
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(card) and card.get_meta("special_lit_until") <= Time.get_ticks_msec():
		card.face.firing_special = false


## 一拍里发动技能的卡：增益、财富的 source，伤害的 by（队长这类描述型效果不算，它们亮特殊技能栏）
func _casters(e: Dictionary) -> Array:
	var cards := []
	for f in e.effects:
		var uid: String = f.by if f.kind == "damage" else f.source
		if f.kind != "raise" and f.get("skill", "") not in CardDB.DESCRIPTIVE_SPECIALS and _cards[uid] not in cards:
			cards.append(_cards[uid])
	return cards


## 集结：己方带集结值的其他角色（含没有时机的），光点从它们飞来
func _rally_helpers(caster) -> Array:
	return player_battle_fields[_side(caster)].filter(func(card): return card != caster and _base[card.get_meta("uid")].has("rally"))


## 从发动者到作用对象的飞行时间；5× 以上不飞（直接生效）
func _fly_time(skill: String, casters: Array) -> float:
	if _detail() < 2:
		return 0.0
	match skill:
		"rage", "wealth":
			return PACE.fly_self
		"rally":
			return PACE.fly if casters.any(func(card): return not _rally_helpers(card).is_empty()) else PACE.fly_self
		"inspire", "annihilate":
			return PACE.wave
		"corrode":
			return PACE.lob
	return PACE.fly


## 演出的详细程度：0.5×、1×、2× 完整；5× 不飞光球、不连线（直接在目标上生效）；20× 也不弹飘字、不加特效
func _detail() -> int:
	if battle_speed <= 2:
		return 2
	return 1 if battle_speed <= 5 else 0


#==============================================
##### 最终局面 #####
#==============================================

## 最终局面：停止所有动画，按结算结果摆好幸存单位，显示胜负
func show_final_state() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	_badges.clear()
	_fx.clear()
	# 从初始状态重新推演：播放途中跳过时，前面已经消耗过的庇护不能重复扣
	var alive := {1: [], 2: []}
	for side in [1, 2]:
		for u in _result.events[0]["p%d" % side]:
			alive[side].append(u.uid)
			_specials[u.uid] = u.special_skills.duplicate()
			_base[u.uid] = u.base_skills.duplicate()
	for e in _result.events:
		if e.type == "death":
			for side in [1, 2]:
				alive[side] = alive[side].filter(func(uid): return uid not in e.units)
		for f in e.get("effects", []):
			if f.kind == "damage" and f.shelter:
				_consume_shelter(f.unit)
			else:
				_apply_change(f)
	for uid in _cards:
		var card = _cards[uid]
		var side := int(uid.split("-")[0])
		var n: int = alive[side].find(uid)
		if n == -1:
			card.queue_free()
			continue
		card.face.set_strength(_result["p%d" % side][n])
		card.face.set_specials(_specials[uid])
		card.face.set_base_skills(_base[uid])
		card.face.set_firing("")
		card.face.firing_skill = ""
		card.face.firing_special = false
		card.face.glow = false
		card.face.engaged = false
		card.face.turn = 0.0
		card.face.position = Vector2.ZERO
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

## 生效后留给玩家看的时间；多一轮重走的那几拍减半
func _read() -> float:
	return PACE.quick_read if _quick else PACE.read


## 主流程等一会儿（按当前速度）；测时长时只记下
func wait(seconds: float) -> void:
	if measuring:
		measured[_segment] = measured.get(_segment, 0.0) + seconds
		_clock += seconds
		return
	await get_tree().create_timer(seconds / battle_speed).timeout


## 和 wait 一样，用在不挡住主流程的效果里（飘字、晚一点生效的伤害）；测时长时不计
func _after(seconds: float) -> void:
	if measuring:
		return
	await get_tree().create_timer(seconds / battle_speed).timeout


func create_battle_tween() -> Tween:
	_tweens = _tweens.filter(func(tween): return tween.is_valid())
	var tween := create_tween().set_parallel(true)
	_tweens.append(tween)
	return tween


## 卡牌摆到自己位置朝中间偏 offset（两排空隙的比例；对方向下、我方向上）、缩放到 card_scale；
## 会打断这张卡正在进行的摆位。已经阵亡移出队列的卡不动
func _pose(cards: Array, offset: float, card_scale: float, duration: float, trans := Tween.TRANS_CUBIC, ease := Tween.EASE_OUT) -> void:
	if cards.is_empty() or have_been_skipped:
		return
	for card in cards:
		var side := _side(card)
		var n: int = player_battle_fields[side].find(card) if side else -1
		if n == -1:
			continue
		if card.has_meta("pose"):
			card.get_meta("pose").kill()
		var target: Vector2 = _ui.slot_position(side, n) + Vector2(0, (1 if side == 1 else -1) * offset * _ui.row_gap)
		var tween := create_battle_tween()
		tween.tween_property(card, "position", target, duration / battle_speed).set_trans(trans).set_ease(ease)
		tween.tween_property(card, "scale", Vector2.ONE * card_scale, duration / battle_speed).set_trans(trans).set_ease(ease)
		card.set_meta("pose", tween)


## 战前进行到的位置：青色光圈淡入（value 1）或淡出（0）
func _mark_turn(cards: Array, value: float) -> void:
	if cards.is_empty() or have_been_skipped or _detail() == 0:
		return
	var tween := create_battle_tween()
	for card in cards:
		tween.tween_property(card.face, "turn", value, 0.15 / battle_speed)


## 卡牌属于哪一方（已经阵亡移出队列的返回 0）
func _side(card) -> int:
	if card in player_battle_fields[1]:
		return 1
	return 2 if card in player_battle_fields[2] else 0


func _cards_of(uids: Array) -> Array:
	return uids.map(func(uid): return _cards[uid])


func _spawn(kind: FxEffect.Kind, duration: float, props: Dictionary) -> void:
	if have_been_skipped or _detail() == 0:
		return
	_fx.spawn(kind, duration, props)


func _spawn_later(delay: float, kind: FxEffect.Kind, duration: float, props: Dictionary) -> void:
	if delay > 0:
		await _after(delay)
	_spawn(kind, duration, props)


func _uid(card) -> String:
	return card.get_meta("uid")
