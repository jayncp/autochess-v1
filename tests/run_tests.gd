extends SceneTree
## 测试入口：战斗用例（含镜像检查）+ 冒烟流程。
## 运行中出现任何错误都算失败；协程因错误中断而卡住时，由看门狗判失败。
## 用法：just test

const Harness := preload("res://tests/battle_harness.gd")
const CASES_PATH := "res://tests/golden/battles.jsonl"
const TIMEOUT_SEC := 300.0
## 测试专用卡：正式卡覆盖不到的规则才用，单元测试和回放检查之后移除，不影响数据检查和冒烟流程
const TEST_CARDS := [
	{"id": "test_general", "no": 0, "type": "character", "star": 3, "races": ["human"], "strength": 15, "skills_1": {"rally": 5}},
	{"id": "test_shelter_sturdy", "no": 0, "type": "character", "star": 3, "races": ["divine"], "strength": 6, "timing_1": "on_enter", "special_skills": {"shelter": 1, "sturdy": 4}},
	{"id": "test_shelter_2", "no": 0, "type": "character", "star": 3, "races": ["divine"], "strength": 8, "timing_1": "on_enter", "special_skills": {"shelter": 2}},
	{"id": "test_shelter_3", "no": 0, "type": "character", "star": 3, "races": ["divine"], "strength": 8, "timing_1": "on_enter", "special_skills": {"shelter": 3}},
]


class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			errors.append("%s:%d %s %s" % [file, line, code, rationale])


var _catcher := ErrorCatcher.new()
var _failures: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_catcher)
	create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	await process_frame
	_check_data()
	await _run_battle_cases()
	await _run_unit_tests()
	await _run_replay_checks()
	for c in TEST_CARDS:
		CardDB.all().erase(c.id)
	await _run_smoke()
	await _frames(3)  # 让 queue_free 的节点真正释放，避免退出时报泄漏
	_finish()


## 数据检查：卡牌、种族、时机、词条、关卡都有中文名，词条都有说明；列出还在用占位图的卡。
## 字段和 id 的合法性由 CardDB、LevelDB 加载时校验，出错会被 ErrorCatcher 捕获。
## 临时切到英文环境，确认系统语言不是中文时也能回退到中文。
func _check_data() -> void:
	var keys := []
	var placeholders := []
	for id in CardDB.all():
		keys.append("card." + id)
		if not ResourceLoader.exists("res://assets/cards/%s.png" % id):
			placeholders.append(id)
	for race in CardDB.RACES:
		keys.append("race." + race)
	for timing in CardDB.TIMINGS:
		keys.append("timing." + timing)
	for skill in CardDB.BASE_SKILLS + CardDB.SPECIAL_SKILLS:
		if skill in CardDB.DESCRIPTIVE_SPECIALS:
			keys.append("effect." + skill)
		else:
			keys.append("keyword." + skill)
			keys.append("keyword_desc." + skill)
	for level_id in LevelDB.all():
		keys.append("level." + level_id)
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for key in keys:
		if tr(key) == key:
			_failures.append("[data] 缺少中文名：%s" % key)
	TranslationServer.set_locale(locale)
	print("数据检查：%d 张卡，%d 个关卡" % [CardDB.all().size(), LevelDB.all().size()])
	if not placeholders.is_empty():
		print("  用占位图的卡：%s" % ", ".join(placeholders))


## 每条用例：结果符合期望、交换左右后对称、事件日志自洽
func _run_battle_cases() -> void:
	var cases := Harness.load_cases(CASES_PATH)
	for c in cases:
		var result := BattleSim.simulate(c.p1, c.p2)
		if not Harness.same(result, c.expect):
			_failures.append("[%s] 期望 %s，实际 %s" % [c.id, c.expect, Harness.run(c.p1, c.p2)])
		var inconsistency := Harness.check_events(result)
		if inconsistency != "":
			_failures.append("[%s] 事件日志不自洽：%s" % [c.id, inconsistency])
		if not c.get("asymmetric", false):
			var mirrored := Harness.run(c.p2, c.p1)
			if not Harness.same(mirrored, Harness.mirror(result)):
				_failures.append("[%s] 交换左右后结果不对称：%s" % [c.id, mirrored])
	print("战斗用例：%d 条" % cases.size())


## 只测对战用例触发不到的情况
func _run_unit_tests() -> void:
	# 相邻两个单位同时阵亡时都要移除（B6；现有卡牌只有交战位会阵亡，对战中触发不到，湮灭会触发）
	var sim := BattleSim.new([["soldier", ""], ["soldier", ""], ["soldier", ""]], [["pixie", ""]])
	sim.fields[1][0].strength = 0
	sim.fields[1][1].strength = -1
	sim.settle_death()
	if sim.fields[1].map(func(u): return u.uid) != ["1-2"]:
		_failures.append("[unit-death-adjacent] 相邻两个阵亡单位应一起移除，实际剩余 %s" % [sim.fields[1].map(func(u): return u.uid)])
	_test_annihilate()
	_test_overlay()
	CardDB.add_cards(TEST_CARDS)
	_test_rules_without_cards()
	_test_skill_text()
	print("单元测试：5 组")


## 湮灭（目前没有卡带湮灭）：打对方全体、走伤害流程；同一时间节点先腐蚀后湮灭，所以庇护挡的是腐蚀
func _test_annihilate() -> void:
	var sim := BattleSim.new([["soldier", ""]], [["paladin", ""], ["soldier", ""], ["shield_guard", ""], ["soldier", ""]])
	var actor = sim.fields[1][0]
	actor.base_skills = {"corrode": 2, "annihilate": 3}
	sim.resolve_timing([actor], "on_enter")
	sim.settle_death()
	var got := {
		"strengths": sim.fields[2].map(func(u): return u.strength),
		"paladin_shelter": sim.fields[2][0].special_skills.has("shelter"),
		"beats": sim.events.filter(func(e): return e.type == "beat").map(func(e): return e.skill),
	}
	# 圣骑士 8：腐蚀 2 被庇护挡下，湮灭 3 打中 → 5；士兵 3 → 0 阵亡；盾卫 6 坚固 4 → 不掉血
	var expected := {"strengths": [5, 6], "paladin_shelter": false, "beats": ["corrode", "annihilate"]}
	if got != expected:
		_failures.append("[unit-annihilate] 期望 %s，实际 %s" % [expected, got])


## 格子模型：逐格覆盖（有就覆盖，"clear" 清空，{} 和省略等价都沿用），再把两格合并
func _test_overlay() -> void:
	var vulture := CardDB.card("vulture")  # 秃鹫：交战，狂暴3、腐蚀2
	var paladin := CardDB.card("paladin")  # 圣骑士：入场，庇护
	var guard := CardDB.card("shield_guard")  # 盾卫：坚固4
	var cases := [
		[guard, CardDB.card("holy_shield"), "special_source", "holy_shield", "特殊技能来自装备"],
		[guard, CardDB.card("lionheart"), "special_source", "shield_guard", "装备没有特殊技能，来源是角色"],
		[vulture, {"skills_1": {"corrode": 15}}, "base_skills", {"corrode": 15}, "基础技能-1 覆盖"],
		[vulture, {"strength": 12, "skills_1": "clear"}, "base_skills", {}, "基础技能-1 清空（空心）"],
		[vulture, {"strength": 12, "skills_1": "clear"}, "strength", 19, "战斗力相加"],
		[vulture, {"skills_2": {"rage": 2}}, "base_skills", {"rage": 5, "corrode": 2}, "两格同名相加"],
		[vulture, {"timing_1": "clear", "timing_2": "pre_battle"}, "timings", ["pre_battle"], "时机-1 清空，时机-2 保留"],
		[{"strength": 1, "timing_2": "on_enter", "skills_2": {"rage": 1}}, {"skills_2": {"rally": 1}}, "base_skills", {"rally": 1}, "装备填 2 也是覆盖角色的 2"],
		[{"strength": 1, "timing_2": "on_enter"}, {"timing_1": "pre_battle"}, "timings", ["pre_battle", "on_enter"], "时机两格取并集"],
		[paladin, {"special_skills": "clear"}, "special_skills", {}, "特殊技能清空"],
		[paladin, {"special_skills": {"lethal": null}}, "special_skills", {"lethal": null}, "特殊技能整体覆盖"],
	]
	for c in cases:
		var got = CardDB.combine_data(c[0], c[1])[c[2]]
		if got != c[3]:
			_failures.append("[unit-overlay] %s：期望 %s，实际 %s" % [c[4], c[3], got])


## 正式卡覆盖不到的规则（用测试专用卡）；能用正式卡表达的都在基线用例的 rule 组。
## 每条：[说明, P1, P2, 跑到哪一步（pre_battle / all）, 期望]。
## pre_battle 比较战前阶段之后双方的战斗力；all 比较整场结果，并做镜像和事件自洽检查
func _test_rules_without_cards() -> void:
	var cases := [
		["唤醒：没有时机的也能被唤醒（集结5）", [["wisp", ""], ["test_general", ""]], [["pixie", ""]], "pre_battle", [[8, 20], [6]]],
		["庇护先于坚固：坚固能挡掉的腐蚀3 也消耗庇护，之后虎人的 12 只被坚固减 4", [["sludge", ""], ["tiger_man", ""]], [["test_shelter_sturdy", ""]], "all",
			{"winner": 1, "p1": [6], "p2": []}],
		["庇护2：腐蚀和交战各消耗一层", [["sludge", ""]], [["test_shelter_2", ""]], "all", {"winner": 2, "p1": [], "p2": [8]}],
	]
	for c in cases:
		if c[3] == "all":
			var result := BattleSim.simulate(c[1], c[2])
			var got := {"winner": result.winner, "p1": result.p1, "p2": result.p2}
			var inconsistency := Harness.check_events(result)
			if inconsistency != "":
				_failures.append("[unit-rules] %s：事件日志不自洽：%s" % [c[0], inconsistency])
			if not Harness.same(Harness.run(c[2], c[1]), Harness.mirror(got)):
				_failures.append("[unit-rules] %s：交换左右后结果不对称" % c[0])
			if not Harness.same(got, c[4]):
				_failures.append("[unit-rules] %s：期望 %s，实际 %s" % [c[0], c[4], got])
			continue
		var sim := BattleSim.new(c[1], c[2])
		sim.pre_battle_phase()
		var strengths := [sim.fields[1].map(func(u): return u.strength), sim.fields[2].map(func(u): return u.strength)]
		if strengths != c[4]:
			_failures.append("[unit-rules] %s：期望 %s，实际 %s" % [c[0], c[4], strengths])
	# 蟾蜍的加成记在腐蚀伤害上，回放据此在蟾蜍身上弹名字
	var hits: Array = BattleSim.simulate([["toad", ""]], [["pixie", ""]]).events.filter(func(e): return e.type == "beat" and e.skill == "corrode")
	if hits.is_empty() or hits[0].effects[0].get("boosts") != ["1-0"]:
		_failures.append("[unit-rules] 蟾蜍的腐蚀应记下加成来源 1-0")


## 卡面文字：带时机的特殊技能、描述型特殊技能、按结算顺序排列
func _test_skill_text() -> void:
	var cases := [
		[load_card.special_skill_text({"lethal": null, "awaken": {"timing": "pre_battle"}}), "战前：唤醒；致命"],
		[load_card.special_skill_text({"rally_gain": 2}), "己方角色触发集结时，自身战斗力 +2"],
		[load_card.special_skill_text({"corrode_boost": 2, "sturdy": 4}), "坚固4；己方角色结算腐蚀时，伤害 +2"],
		[load_card.base_skill_text({"wealth": 1, "support": 3, "rage": 2}), "狂暴2、支援3、财富1"],
		[load_card.special_skill_text({"shelter": 1, "sturdy": 4}), "坚固4；庇护1"],
	]
	for c in cases:
		if c[0] != c[1]:
			_failures.append("[unit-skill-text] 期望 %s，实际 %s" % [c[1], c[0]])


## 回放检查：战斗场景最后显示的局面和 BattleSim 的结果一致。
## 覆盖动画播完、僵持压缩、动画中途跳过三种情况（高速播放）
func _run_replay_checks() -> void:
	var cases := [
		["animated", [["tiger_man", "lionheart"], ["fairy", ""]], [["porcupine", "holy_shield"], ["paladin", ""]], -1],
		["stalemate", [["angel", "riot_helmet"]], [["angel", "riot_helmet"]], -1],
		["skip-midway", [["soldier", ""], ["soldier", ""], ["tiger", "holy_water"]], [["sludge", "thorns"], ["shield_guard", ""]], 30],
		["mechanics", [["wisp", ""], ["fey_tiger", ""], ["mimic", ""], ["butterfly", ""], ["pixie", "hollow"]],
			[["captain", ""], ["toad", ""], ["soldier", ""], ["tiger", "flash_orb"], ["paladin", ""]], -1],
	]
	for c in cases:
		global_var.battle_card_list_1 = c[1].map(func(u): return u[0])
		global_var.battle_equip_list_1 = c[1].map(func(u): return u[1])
		global_var.battle_card_list_2 = c[2].map(func(u): return u[0])
		global_var.battle_equip_list_2 = c[2].map(func(u): return u[1])
		var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
		root.add_child(scene)
		var battle_manager: Node = scene.get_node("battle_manager")
		battle_manager.battle_speed = 1000.0
		battle_manager._on_start_battle_pressed_battle()
		if c[3] >= 0:
			await _frames(c[3])
			battle_manager._on_skip_button_pressed()
		while battle_manager.winner == 0:
			await process_frame
		if c[3] >= 0 and not battle_manager.have_been_skipped:
			_failures.append("[replay-%s] 战斗在跳过之前就播完了，没测到中途跳过" % c[0])
		_check_replay(battle_manager, "replay-" + c[0])
		scene.free()
	await _check_skip_keeps_shelter()
	print("回放检查：%d 条" % (cases.size() + 1))


## 播放途中跳过：已经播放过的庇护消耗不能在最终局面里重复扣。
## 淤泥怪的腐蚀和交战各消耗一层，庇护3 最后剩 1
func _check_skip_keeps_shelter() -> void:
	global_var.battle_card_list_1 = ["sludge"]
	global_var.battle_equip_list_1 = [""]
	global_var.battle_card_list_2 = ["test_shelter_3"]
	global_var.battle_equip_list_2 = [""]
	var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	root.add_child(scene)
	var battle_manager: Node = scene.get_node("battle_manager")
	for e in battle_manager._result.events:
		var played: Array = e.get("effects", []).filter(func(f): return f.kind == "damage" and f.shelter)
		if not played.is_empty():
			battle_manager.apply_effect(played[0])  # 相当于播放到第一次庇护消耗
			break
	battle_manager.have_been_skipped = true
	battle_manager.show_final_state()
	var shown: String = battle_manager.player_battle_fields[2][0].get_node("skill_3").text
	if shown != "庇护1":
		_failures.append("[replay-skip-shelter] 跳过后应显示庇护1，实际 %s" % shown)
	scene.free()


## 场景里显示的胜负和双方幸存单位的战力，应与 BattleSim 的结果一致
func _check_replay(battle_manager: Node, label: String) -> void:
	var lineups := {1: [], 2: []}
	for side in [1, 2]:
		var cards: Array = global_var.battle_card_list_1 if side == 1 else global_var.battle_card_list_2
		var equips: Array = global_var.battle_equip_list_1 if side == 1 else global_var.battle_equip_list_2
		for n in cards.size():
			lineups[side].append([cards[n], equips[n]])
	var expected := Harness.run(lineups[1], lineups[2])
	var shown := {"winner": battle_manager.winner}
	for side in [1, 2]:
		shown["p%d" % side] = battle_manager.player_battle_fields[side].map(func(card): return int(card.get_node("strength_1").text))
	if not Harness.same(shown, expected):
		_failures.append("[%s] 场景显示 %s，BattleSim 结果 %s" % [label, shown, expected])


func _run_smoke() -> void:
	var manager: Node = load("res://scenes/app/scene_manager.tscn").instantiate()
	root.add_child(manager)
	await _frames(2)

	# 科研模式：设置阵容 → 开始战斗 → 跳过 → 返回 → 主菜单
	manager.get_node("MenuScene")._on_test_mode_pressed()
	await _frames(2)
	var sandbox: Node = manager.current_scene
	var select: Node = sandbox.get_node("select_manager")
	for slot in [[1, 0, "tiger_man", "lionheart"], [2, 0, "porcupine", "holy_shield"], [2, 1, "fairy", ""]]:
		select.init_card_list[slot[0]][slot[1]] = slot[2]
		select.init_equip_list[slot[0]][slot[1]] = slot[3]
		select.update_display(slot[0], slot[1], slot[2], slot[3])
	select._on_start_battle_pressed()
	await _play_battle_and_return(manager)
	sandbox._on_back_button_pressed()
	await _frames(2)

	# 闯关：第一关检查布阵交互规则；两关各布阵一次 → 开始战斗 → 返回
	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(2)
	manager.current_scene._on_level_select_button_pressed(LevelDB.all().keys()[0])
	await create_timer(0.3).timeout  # 等手牌入场动画
	await _check_lineup_rules(manager)
	manager.current_scene._on_back_button_pressed()
	await _frames(2)
	for level_id in LevelDB.all():
		manager.current_scene._on_level_select_button_pressed(level_id)
		await create_timer(0.3).timeout
		var setup: Node = manager.current_scene
		var slots: Array = setup.get_node("player_card_slots").get_children()
		var hand: Array = setup.get_node("player_hand").player_hand.duplicate()
		var chars := hand.filter(func(card): return card.card_id != "")
		for i in chars.size():
			_drag(setup, chars[i], slots[i])
		setup._on_start_battle_pressed()
		await _play_battle_and_return(manager)
		setup._on_back_button_pressed()
		await _frames(2)
	manager.current_scene._on_back_button_pressed()
	await _frames(2)

	# 图鉴：翻页、筛选
	manager.get_node("MenuScene")._on_book_mode_pressed()
	await _frames(2)
	var book: Node = manager.current_scene.get_node("book_manager")
	book._on_next_page_button_pressed()
	book._on_last_page_button_pressed()
	var equipment_count := CardDB.ids("equipment").size()
	book._on_filter_character_button_pressed()  # 关掉角色，只剩装备
	if book.display_list.size() != equipment_count:
		_failures.append("[smoke-book] 只看装备应有 %d 张，实际 %d 张" % [equipment_count, book.display_list.size()])
	book._on_filter_character_button_pressed()  # 恢复
	book._on_filter_star_button_item_selected(2)
	var two_stars := CardDB.all().values().filter(func(c): return c.star == 2).size()
	if book.display_list.size() != two_stars:
		_failures.append("[smoke-book] 2★ 应有 %d 张，实际 %d 张" % [two_stars, book.display_list.size()])
	# 分页（B4）：每页 18 张，正好 18 张是 1 页，19 张是 2 页
	for n in [18, 19]:
		book.display_list = range(n)
		if book.total_pages() != ceili(n / 18.0):
			_failures.append("[smoke-book] %d 张应为 %d 页，实际 %d 页" % [n, ceili(n / 18.0), book.total_pages()])
	book._on_filter_star_button_item_selected(2)
	book.get_node("../filter_string_input").text = "集结"
	book._on_filter_string_button_pressed()
	await _frames(2)
	manager.current_scene._on_back_button_pressed()
	await _frames(2)

	manager.free()
	print("冒烟流程：完成")


## 布阵交互规则（docs/design/game-design.md 第 7 节），用第一关的手牌：
## 秃鹫、食人花、半精灵人、虎人、战旗、尖刺拳套
func _check_lineup_rules(manager: Node) -> void:
	var setup: Node = manager.current_scene
	var s: Array = setup.get_node("player_card_slots").get_children()
	setup._on_start_battle_pressed()
	await _frames(1)
	if manager.has_node("main"):
		_failures.append("[smoke-lineup] 一个角色都没上场也开始了战斗")
	# 拖动中鼠标移出卡牌区域（移动太快时会发生），卡牌仍要在最上层
	var cards: Node = setup.get_node("advanced_card_manager")
	var dragged := _hand_card(setup, "vulture")
	cards.start_drag(dragged)
	cards.on_hovered_off_card(dragged)
	if dragged.z_index != 1001:
		_failures.append("[smoke-lineup] 拖动中触发鼠标离开后，卡牌图层降到了 %d" % dragged.z_index)
	cards.drop_card(null)
	var steps := [
		["war_banner", 0, [[]], "装备不能单独上场"],
		["vulture", 0, [["vulture", ""]], "角色放入空格"],
		["maneater", 1, [["vulture", ""], ["maneater", ""]], "角色放入空格"],
		["war_banner", 0, [["vulture", "war_banner"], ["maneater", ""]], "装备拖到角色上：合并"],
		["spiked_gauntlet", 0, [["vulture", "spiked_gauntlet"], ["maneater", ""]], "装备拖到已合并的卡上：换装备"],
		[1, 0, [["maneater", ""], ["vulture", "spiked_gauntlet"]], "场上互换"],
		["half_elf", 0, [["half_elf", ""], ["vulture", "spiked_gauntlet"]], "手牌占位"],
		[1, -1, [["half_elf", ""], []], "拖到格子以外：拆开回手"],
		[0, 0, [["half_elf", ""], []], "拖回原来的格子：不变"],
	]
	for step in steps:
		var card = s[step[0]].card_in_slot if step[0] is int else _hand_card(setup, step[0])
		_drag(setup, card, s[step[1]] if step[1] >= 0 else null)
		await _frames(1)
		var got := []
		for i in step[2].size():
			var c = s[i].card_in_slot
			got.append([c.card_id, c.equip_id] if c else [])
		if got != step[2]:
			_failures.append("[smoke-lineup] %s：期望 %s，实际 %s" % [step[3], step[2], got])
	for id in ["war_banner", "maneater", "vulture", "spiked_gauntlet"]:
		if _hand_card(setup, id) == null:
			_failures.append("[smoke-lineup] %s 应该回到手牌" % id)


## 模拟玩家把卡拖到某个格子（null 表示格子以外）
func _drag(setup: Node, card: Node, slot: Node) -> void:
	var cards: Node = setup.get_node("advanced_card_manager")
	cards.start_drag(card)
	cards.drop_card(slot)


func _hand_card(setup: Node, id: String) -> Node:
	for card in setup.get_node("player_hand").player_hand:
		if (card.card_id if card.card_id else card.equip_id) == id:
			return card
	return null


## 模拟玩家点击：开始战斗 → 跳过 → 等结束 → 返回
func _play_battle_and_return(manager: Node) -> void:
	await _frames(2)
	var battle_manager: Node = manager.get_node("main/battle_manager")
	battle_manager._on_start_battle_pressed_battle()
	await _frames(2)
	battle_manager._on_skip_button_pressed()
	while battle_manager.winner == 0:
		await process_frame
	_check_replay(battle_manager, "smoke-battle")
	battle_manager._on_start_battle_pressed_battle()
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish() -> void:
	for e in _catcher.errors:
		_failures.append("运行错误：" + e)
	if _failures.is_empty():
		print("全部通过")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		printerr("失败 %d 项" % _failures.size())
		quit(1)


func _on_timeout() -> void:
	printerr("超时（%d 秒）：可能有协程因错误中断" % TIMEOUT_SEC)
	for e in _catcher.errors:
		printerr("运行错误：" + e)
	quit(1)
