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
	print("单元测试：3 条")


## 湮灭（目前没有卡带湮灭）：打对方全体、走伤害流程；同一时间节点先腐蚀后湮灭，所以庇护挡的是腐蚀
func _test_annihilate() -> void:
	var sim := BattleSim.new([["soldier", ""]], [["paladin", ""], ["soldier", ""], ["shield_guard", ""], ["soldier", ""]])
	var actor = sim.fields[1][0]
	actor.normal_skills = {"corrode": 2, "annihilate": 3}
	sim.resolve_timing([actor])
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


## 装备叠放模型：有就覆盖，"clear" 清空，{} 和省略等价都沿用；武器格叠加
func _test_overlay() -> void:
	var vulture := CardDB.card("vulture")  # 秃鹫：交战，狂暴3、腐蚀2
	var paladin := CardDB.card("paladin")  # 圣骑士：入场，庇护
	var cases := [
		[vulture, {"skills": {"corrode": 15}}, "normal_skills", {"corrode": 15}, "基础技能整体覆盖"],
		[vulture, {"weapon_strength": 12, "skills": "clear"}, "normal_skills", {}, "基础技能清空（空心）"],
		[vulture, {"weapon_skills": {"rage": 2}}, "normal_skills", {"rage": 5, "corrode": 2}, "武器技能同名相加"],
		[vulture, {"timing": "clear", "weapon_timing": "pre_battle"}, "timings", ["pre_battle"], "基础时机清空，武器时机保留"],
		[paladin, {"special_skills": "clear"}, "special_skills", {}, "特殊技能清空"],
		[paladin, {"special_skills": {"lethal": null}}, "special_skills", {"lethal": null}, "特殊技能整体覆盖"],
	]
	for c in cases:
		var got = CardDB.combine_data(c[0], c[1])[c[2]]
		if got != c[3]:
			_failures.append("[unit-overlay] %s：期望 %s，实际 %s" % [c[4], c[3], got])


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

	# 闯关：两关各布阵一次 → 开始战斗 → 返回
	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(2)
	for level_id in LevelDB.all():
		manager.current_scene._on_level_select_button_pressed(level_id)
		await create_timer(0.3).timeout  # 等手牌入场动画
		var pre_battle: Node = manager.current_scene
		var chars: Array = pre_battle.get_node("advanced_card_manager").get_children().filter(
			func(card): return card.card_id != "")
		for i in chars.size():
			chars[i].position = Vector2((i + 1) * 240, 540)
		pre_battle._on_start_battle_pressed()
		await _play_battle_and_return(manager)
		pre_battle._on_back_button_pressed()
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
