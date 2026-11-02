extends SceneTree
## 测试入口：战斗用例（含镜像检查）+ 冒烟流程。
## 运行中出现任何错误都算失败；协程因错误中断而卡住时，由看门狗判失败。
## 用法：just test

const Harness := preload("res://tests/battle_harness.gd")
const CASES_PATH := "res://tests/golden/battles.jsonl"
const TIMEOUT_SEC := 300.0


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
	await _run_smoke()
	await _frames(3)  # 让 queue_free 的节点真正释放，避免退出时报泄漏
	_finish()


## 数据检查：每张卡都有卡图；卡牌、种族、时机、词条、关卡都有中文名。
## 字段和 id 的合法性由 CardDB、LevelDB 加载时校验，出错会被 ErrorCatcher 捕获。
## 临时切到英文环境，确认系统语言不是中文时也能回退到中文。
func _check_data() -> void:
	var keys := []
	for id in CardDB.all():
		keys.append("card." + id)
		if not ResourceLoader.exists("res://assets/cards/%s.png" % id):
			_failures.append("[data] %s 没有卡图" % id)
	for race in CardDB.RACES:
		keys.append("race." + race)
	for timing in CardDB.TIMINGS:
		keys.append("timing." + timing)
	for skill in CardDB.NORMAL_SKILLS + CardDB.SPECIAL_SKILLS:
		keys.append("keyword." + skill)
	for level_id in LevelDB.all():
		keys.append("level." + level_id)
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for key in keys:
		if tr(key) == key:
			_failures.append("[data] 缺少中文名：%s" % key)
	TranslationServer.set_locale(locale)
	print("数据检查：%d 张卡，%d 个关卡" % [CardDB.all().size(), LevelDB.all().size()])


func _run_battle_cases() -> void:
	var harness := Harness.new(self)
	var cases := Harness.load_cases(CASES_PATH)
	for c in cases:
		var got: Dictionary = await harness.run(c.p1, c.p2)
		if not Harness.same(got, c.expect):
			_failures.append("[%s] 期望 %s，实际 %s" % [c.id, c.expect, got])
		if not c.get("asymmetric", false):
			var mirrored: Dictionary = await harness.run(c.p2, c.p1)
			if not Harness.same(mirrored, Harness.mirror(got)):
				_failures.append("[%s] 交换左右后结果不对称：%s" % [c.id, mirrored])
	print("战斗用例：%d 条" % cases.size())


## 只测对战用例触发不到的情况
func _run_unit_tests() -> void:
	# 相邻两个单位同时阵亡时都要移除（B6；现有卡牌只有交战位会阵亡，对战中触发不到，湮灭会触发）
	global_var.battle_card_list_1 = ["soldier", "soldier", "soldier"]
	global_var.battle_equip_list_1 = ["", "", ""]
	global_var.battle_card_list_2 = ["pixie"]
	global_var.battle_equip_list_2 = [""]
	var scene: Node = Harness.BATTLE_SCENE.instantiate()
	root.add_child(scene)
	var manager: Node = scene.get_node("battle_manager")
	manager.play_animation = false
	var field: Array = manager.player_battle_fields[1]
	field[0].strength = 0
	field[1].strength = -1
	var survivor: Node = field[2]
	manager.settlement_death()
	if manager.player_battle_fields[1] != [survivor]:
		_failures.append("[unit-death-adjacent] 相邻两个阵亡单位应一起移除，实际剩余 %d 个" % manager.player_battle_fields[1].size())
	scene.free()
	print("单元测试：1 条")


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
	book._on_filter_character_button_pressed()
	book._on_filter_equipment_button_pressed()
	book._on_filter_star_button_item_selected(2)
	if book.total_pages() != 1:  # 2★ 正好 18 张，一页放下（B4）
		_failures.append("[smoke-book] 2★ 共 %d 张，应为 1 页，实际 %d 页" % [book.display_list.size(), book.total_pages()])
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
	await create_timer(1.0).timeout  # 等跳过后的补位动画
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
