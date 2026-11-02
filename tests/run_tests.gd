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
	await _run_battle_cases()
	await _run_unit_tests()
	await _run_smoke()
	await _frames(3)  # 让 queue_free 的节点真正释放，避免退出时报泄漏
	_finish()


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
	global_var.battle_card_list_1 = ["士兵", "士兵", "士兵"]
	global_var.battle_equip_list_1 = ["", "", ""]
	global_var.battle_card_list_2 = ["小精灵"]
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
	for slot in [[1, 0, "虎人", "狮心"], [2, 0, "豪猪", "圣盾"], [2, 1, "仙女", ""]]:
		select.init_card_list[slot[0]][slot[1]] = slot[2]
		select.init_equip_list[slot[0]][slot[1]] = slot[3]
		select.update_display(slot[0], slot[1], slot[2], slot[3])
	select._on_start_battle_pressed()
	await _play_battle_and_return(manager)
	sandbox._on_back_button_pressed()
	await _frames(2)

	# 闯关：两关各布阵一次 → 开始战斗 → 返回
	var level_names: Array = preload("res://scripts/database/level_database.gd").LEVEL.keys()
	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(2)
	for level_name in level_names:
		manager.current_scene._on_level_select_button_pressed(level_name)
		await create_timer(0.3).timeout  # 等手牌入场动画
		var pre_battle: Node = manager.current_scene
		var chars: Array = pre_battle.get_node("advanced_card_manager").get_children().filter(
			func(card): return card.get_node("character_name").text != "")
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
