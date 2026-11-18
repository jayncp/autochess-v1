extends SceneTree
## 测试入口：战斗用例（含镜像检查）+ 存档 + 冒烟流程。
## 设置和存档用测试专用的文件（test_*），不读写玩家的存档。
## 运行中出现任何错误都算失败；协程因错误中断而卡住时，由看门狗判失败。
## 用法：just test

const Harness := preload("res://tests/battle_harness.gd")
const TIMEOUT_SEC := 300.0
## 能打赢的摆法（冒烟用例里关卡的解），冒烟流程用它记通关
const WINNING := {"boar_rush": [["vulture", "war_banner"], ["maneater", ""], ["tiger_man", "spiked_gauntlet"], ["half_elf", ""]]}
const TEST_FILES := ["test_settings.cfg", "test_save.json", "test_save.json.bak", "test_save.json.tmp", "test_save.json.broken"]


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
	GameSettings.path = "user://test_settings.cfg"
	SaveData.path = "user://test_save.json"
	_remove_test_files()
	await process_frame
	_check_data()
	# 测试卡（tests/cases/cards.json）只在规则用例、单元测试、回放检查里用，之后移除，不影响数据检查和冒烟流程
	Harness.add_test_cards()
	_run_battle_cases()
	_run_unit_tests()
	_run_save_tests()
	await _run_replay_checks()
	Harness.remove_test_cards()
	await _run_smoke()
	await _frames(3)  # 让 queue_free 的节点真正释放，避免退出时报泄漏
	_remove_test_files()
	_finish()


## 数据检查：卡牌、种族、时机、词条、关卡都有中文名，词条都有说明，基础技能和词条都有飘字的饰板；列出还没有卡图的卡。
## 字段和 id 的合法性由 CardDB、LevelDB 加载时校验，出错会被 ErrorCatcher 捕获。
## 临时切到英文环境，确认系统语言不是中文时也能回退到中文。
func _check_data() -> void:
	var keys := []
	var no_art := []
	for id in CardDB.all():
		keys.append("card." + id)
		if not ResourceLoader.exists("res://assets/cards/%s.png" % id):
			no_art.append(id)
	for race in CardDB.RACES:
		keys.append("race." + race)
	for timing in CardDB.TIMINGS:
		keys.append("timing." + timing)
		keys.append("timing_desc." + timing)
	for skill in CardDB.BASE_SKILLS + CardDB.SPECIAL_SKILLS:
		if skill in CardDB.DESCRIPTIVE_SPECIALS:
			keys.append("effect." + skill)
		else:
			keys.append("keyword." + skill)
			keys.append("keyword_desc." + skill)
			# 飘字的饰板（just art 生成）：基础技能是端饰和中段，词条是圆章、中段和尖头
			var parts := ["cap_", "mid_"] if skill in CardDB.BASE_SKILLS else ["medal_", "kmid_", "ktip_"]
			for part in parts:
				if not ResourceLoader.exists("res://assets/ui/fx/%s%s.png" % [part, skill]):
					_failures.append("[data] 缺少飘字贴图：%s%s.png" % [part, skill])
	for scope in CardDB.SCOPES:
		keys.append("scope." + scope)
	for target in CardDB.TARGETS:
		keys.append("target." + target)
	keys.append("keyword." + CardDB.ANY)
	for level_id in LevelDB.all():
		keys.append("level." + level_id)
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for key in keys:
		if tr(key) == key:
			_failures.append("[data] 缺少中文名：%s" % key)
	TranslationServer.set_locale(locale)
	_check_font_coverage()
	print("数据检查：%d 张卡，%d 个关卡" % [CardDB.all().size(), LevelDB.all().size()])
	if not no_art.is_empty():
		print("  还没有卡图的卡：%s" % ", ".join(no_art))


## 字体是子集化的（just fonts）：翻译表里的每个字都要在两种字体里，缺了就重新子集化
func _check_font_coverage() -> void:
	var fonts := ["res://assets/fonts/NotoSansSC.ttf", "res://assets/fonts/NotoSerifSC-Bold.ttf"].map(func(path): return load(path))
	var missing := {}
	for table in DirAccess.get_files_at("res://i18n"):
		if not table.ends_with(".csv"):
			continue
		for line in FileAccess.get_file_as_string("res://i18n/" + table).split("\n"):
			for i in line.length():
				var code := line.unicode_at(i)
				if code >= 0x20 and fonts.any(func(font): return not font.has_char(code)):
					missing[line[i]] = true
	if not missing.is_empty():
		_failures.append("[data] 字体缺字（运行 just fonts 重新子集化）：%s" % "".join(missing.keys()))


## 规则用例（只用测试卡）：结果符合期望；冒烟用例（正式卡）：关卡的解要赢。都检查交换左右后对称、事件日志自洽
func _run_battle_cases() -> void:
	var test_ids := Harness.test_cards().map(func(c): return c.id)
	var cases := Harness.load_cases(Harness.CASES_PATH)
	for c in cases:
		for unit in c.p1 + c.p2:
			for id in unit:
				if id and id not in test_ids:
					_failures.append("[%s] 规则用例只用测试卡，%s 是正式卡" % [c.id, id])
		_check_case(c, Harness.run(c.p1, c.p2), c.expect)
	var smoke := Harness.load_cases(Harness.SMOKE_PATH)
	for c in smoke:
		var result := Harness.run(c.p1, c.p2)
		_check_case(c, result, null)
		if c.has("expect") and result.winner != int(c.expect.winner):
			_failures.append("[%s] 应该是 P%d 胜，实际 %s" % [c.id, c.expect.winner, Harness.outcome(result)])
	print("战斗用例：规则 %d 条，冒烟 %d 条" % [cases.size(), smoke.size()])


func _check_case(c: Dictionary, result: Dictionary, expect) -> void:
	if expect != null and not Harness.same(result, expect):
		_failures.append("[%s] 期望 %s，实际 %s" % [c.id, expect, Harness.outcome(result)])
	var inconsistency := Harness.check_events(result)
	if inconsistency != "":
		_failures.append("[%s] 事件日志不自洽：%s" % [c.id, inconsistency])
	var mirrored := Harness.run(c.p2, c.p1)
	if not Harness.same(mirrored, Harness.mirror(result)):
		_failures.append("[%s] 交换左右后结果不对称：%s" % [c.id, Harness.outcome(mirrored)])


## 只测对战用例触发不到的情况；都用测试卡
func _run_unit_tests() -> void:
	# 相邻两个单位同时阵亡时都要移除（B6；现有卡牌只有交战位会阵亡，对战中触发不到，湮灭会触发）
	var sim := BattleSim.new([["t_soldier", ""], ["t_soldier", ""], ["t_soldier", ""]], [["t_pixie", ""]])
	sim.fields[1][0].strength = 0
	sim.fields[1][1].strength = -1
	sim.settle_death()
	if sim.fields[1].map(func(u): return u.uid) != ["1-2"]:
		_failures.append("[unit-death-adjacent] 相邻两个阵亡单位应一起移除，实际剩余 %s" % [sim.fields[1].map(func(u): return u.uid)])
	_test_annihilate()
	_test_overlay()
	_test_bonus_sources()
	_test_event_details()
	_test_skill_text()
	_test_live_specials()
	print("单元测试：7 组")


## 湮灭（目前没有卡带湮灭）：打对方全体、走伤害流程；同一时间节点先腐蚀后湮灭，所以庇护挡的是腐蚀
func _test_annihilate() -> void:
	var sim := BattleSim.new([["t_soldier", ""]], [["t_paladin", ""], ["t_soldier", ""], ["t_shield_guard", ""], ["t_soldier", ""]])
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
	var vulture := CardDB.card("t_vulture")  # 秃鹫：7，交战，狂暴3、腐蚀2
	var paladin := CardDB.card("t_paladin")  # 圣骑士：入场，庇护
	var guard := CardDB.card("t_shield_guard")  # 盾卫：坚固4
	var cases := [
		[guard, CardDB.card("t_holy_shield"), "special_source", "t_holy_shield", "特殊技能来自装备"],
		[guard, CardDB.card("t_lionheart"), "special_source", "t_shield_guard", "装备没有特殊技能，来源是角色"],
		[vulture, {"skills_1": {"corrode": 15}}, "base_skills", {"corrode": 15}, "基础技能-1 覆盖"],
		[vulture, {"strength": 12, "skills_1": "clear"}, "base_skills", {}, "基础技能-1 清空（空心）"],
		[vulture, {"strength": 12, "skills_1": "clear"}, "strength", 19, "战斗力相加"],
		[vulture, {"skills_2": {"rage": 2}}, "base_skills", {"rage": 5, "corrode": 2}, "两格同名相加"],
		[vulture, {"timing_1": "clear", "timing_2": ["pre_battle"]}, "timings", ["pre_battle"], "时机-1 清空，时机-2 保留"],
		[{"strength": 1, "timing_2": ["on_enter"], "skills_2": {"rage": 1}}, {"skills_2": {"rally": 1}}, "base_skills", {"rally": 1}, "装备填 2 也是覆盖角色的 2"],
		[{"strength": 1, "timing_2": ["on_enter"]}, {"timing_1": ["pre_battle"]}, "timings", ["pre_battle", "on_enter"], "时机两格取并集"],
		[{"strength": 1, "timing_1": ["on_engage", "pre_battle"]}, {"timing_2": ["on_enter", "on_engage"]}, "timings", ["pre_battle", "on_enter", "on_engage"],
			"一格多个时机；同一个时机出现两次只算一次，按显示顺序"],
		[paladin, {"special_skills": "clear"}, "special_skills", {}, "特殊技能清空"],
		[paladin, {"special_skills": {"lethal": null}}, "special_skills", {"lethal": null}, "特殊技能整体覆盖"],
		[CardDB.card("t_clockwork_witch"), CardDB.card("t_ruyi_staff"), "base_skills", {"rage": 10, "rally": 2}, "千机魔女：从装备获得的基础技能翻倍"],
		[CardDB.card("t_clockwork_witch"), CardDB.card("t_ruyi_staff"), "strength", 35, "千机魔女：从装备获得的战斗力翻倍"],
		[CardDB.card("t_clockwork_witch"), CardDB.card("t_void_heart"), "strength", 45, "千机魔女带虚无之心：特殊技能被清空，不翻倍"],
		[CardDB.card("t_tiger_man"), CardDB.card("t_clockwork_box"), "base_skills", {"rage": 4, "rally": 2}, "千机之匣：自身的基础技能在合并时翻倍"],
	]
	for c in cases:
		var got = CardDB.combine_data(c[0], c[1])[c[2]]
		if got != c[3]:
			_failures.append("[unit-overlay] %s：期望 %s，实际 %s" % [c[4], c[3], got])
	# 卡面印的数（不翻倍）：卡面据此把翻倍的标紫
	var printed := CardDB.combine_data(CardDB.card("t_clockwork_witch"), CardDB.card("t_ruyi_staff"), true)
	if [printed.strength, printed.base_skills] != [25, {"rage": 5, "rally": 2}]:
		_failures.append("[unit-overlay] 千机魔女带如意金箍棒印的是 25、狂暴5、集结2，实际 %s %s" % [printed.strength, printed.base_skills])


## 结算加成（蟾蜍）记在腐蚀伤害上，回放据此在持有者身上弹名字
func _test_bonus_sources() -> void:
	# 伤害记下发动者（后面那只蟾蜍在第 2 位，腐蚀是第 1 位发动的）
	var hits: Array = BattleSim.simulate([["t_toad", ""], ["t_toad", ""]], [["t_pixie", ""]]).events.filter(func(e): return e.type == "beat" and e.skill == "corrode")
	if hits.is_empty() or hits[0].effects[0].get("boosts") != ["1-0", "1-1"]:
		_failures.append("[unit-bonus] 蟾蜍的腐蚀应记下加成来源 1-0、1-1")
	elif hits[0].effects[0].by != "1-0":
		_failures.append("[unit-bonus] 腐蚀伤害的 by 应是发动者 1-0，实际 %s" % hits[0].effects[0].by)


## 事件日志里出现了哪些新机制（回放检查用来确认阵容覆盖到）
func _event_marks(events: Array) -> Array:
	var marks := {}
	for e in events:
		marks[e.type] = true
		for f in e.get("effects", []):
			if f.kind in ["grant", "copy", "clear", "raise"]:
				marks[f.kind if e.type == "special" else f.kind + "@" + e.type] = true
			if f.has("again"):
				marks["again"] = true
			if f.kind == "damage" and f.source == "damage_half_strength":
				marks["half"] = true
			if f.kind == "buff" and f.skill in ["gain_half_skill_sum", "gain_if_outnumbered"]:
				marks[f.skill] = true
		if e.type == "clash":
			for k in 2:
				var attacker: Dictionary = _unit_info(events, e.effects[1 - k].by)
				if attacker.special_skills.has("lethal") and e.attacks[k] != BattleSim.LETHAL_ATTACK:
					marks["immune"] = true
	return marks.keys()


func _unit_info(events: Array, uid: String) -> Dictionary:
	for u in events[0].p1 + events[0].p2:
		if u.uid == uid:
			return u
	return {}


## 回放依赖的事件细节（结果由规则用例检查）：多一次的标记、多一轮的来源、协战按位置分开、神佑给的层数
func _test_event_details() -> void:
	var cases := Harness.load_cases(Harness.CASES_PATH)
	var events := func(id: String) -> Array:
		var c: Dictionary = cases.filter(func(x): return x.id == id)[0]
		return BattleSim.simulate(c.p1, c.p2).events
	var corrode: Array = events.call("rule-extra-resolve").filter(func(e): return e.type == "beat" and e.skill == "corrode")[0].effects
	var again := corrode.filter(func(f): return f.has("again")).map(func(f): return [f.kind, f.again, f.again_by])
	if again != [["damage", 1, "1-0"]]:
		_failures.append("[unit-events] 多一次的那一下应标 again 1、来自 1-0，实际 %s" % [again])
	var rounds: Array = events.call("rule-extra-round-stack").filter(func(e): return e.type == "round").map(func(e): return [e.round, e.units, e.sources])
	if rounds != [[2, ["1-0"], ["1-0"]], [3, ["1-0"], ["1-1"]]]:
		_failures.append("[unit-events] 熊猫大侠的两次多一轮应来自自己和金甲虎王，实际 %s" % [rounds])
	var assists: Array = events.call("rule-assist-order").filter(func(e): return e.type == "assist").map(func(e): return e.effects.map(func(f): return f.by))
	if assists != [["1-1"], ["1-2"]]:
		_failures.append("[unit-events] 协战应按位置分成两个事件（1-1、1-2），实际 %s" % [assists])
	var grants: Array = events.call("rule-extra-round-special").filter(func(e): return e.type == "special" and e.skill == "bless").map(
		func(e): return e.effects.map(func(f): return [f.unit, f.skill, f.amount, f.value]))
	if grants != [[["1-1", "shelter", 2, 2]], [["1-1", "shelter", 2, 4]]]:
		_failures.append("[unit-events] 神佑两轮应给骑士王 2、4 层庇护，实际 %s" % [grants])
	# 千机之匣：获得的基础技能数值也 ×2（圣咏者给的集结1，带千机之匣的士兵 +2）
	var gained: Array = events.call("rule-double-skills-gained").filter(func(e): return e.type == "special" and e.skill == "grant")[0].effects
	if gained.map(func(f): return [f.unit, f.amount, f.value]) != [["1-0", 1, 1], ["1-1", 2, 6]]:
		_failures.append("[unit-events] 带千机之匣的士兵应获得集结 2（4 → 6），实际 %s" % [gained])
	# 美杜莎只清前两位，第 3 位的集结值还在
	var cleared: Array = events.call("rule-clear").filter(func(e): return e.type == "special" and e.skill == "clear_skills")[0].effects
	if cleared.map(func(f): return [f.unit, f.skills]) != [["2-0", ["rally"]], ["2-1", ["rage"]]]:
		_failures.append("[unit-events] 美杜莎入场应清除 2-0 的集结、2-1 的狂暴，实际 %s" % [cleared])
	# 尤姆卡克斯：财富也加，没有技能的不加
	var raised: Array = events.call("rule-raise-all").filter(func(e): return e.type == "special").map(
		func(e): return e.effects.map(func(f): return [f.unit, f.skill, f.value]))
	if raised != [[["1-0", "rally", 3], ["1-0", "inspire", 4], ["1-1", "wealth", 3]]]:
		_failures.append("[unit-events] 尤姆卡克斯应加集结、振奋、财富，实际 %s" % [raised])
	# 萨满：每一下腐蚀之后马上加，第二下用新数值；士兵没有腐蚀，不加
	var beat: Array = events.call("rule-raise-after-resolve").filter(func(e): return e.type == "beat" and e.skill == "corrode")[0].effects
	var order := beat.map(func(f): return [f.kind, f.unit, f.get("value", f.get("amount"))])
	if order != [["damage", "2-0", 7], ["raise", "1-0", 8], ["raise", "1-1", 7], ["damage", "2-0", 8], ["raise", "1-0", 9], ["raise", "1-1", 8]]:
		_failures.append("[unit-events] 萨满的腐蚀加成顺序不对：%s" % [order])


## 卡面文字：带时机的特殊技能、描述型特殊技能、按结算顺序排列
func _test_skill_text() -> void:
	var cases := [
		[load_card.special_skill_text({"lethal": null, "awaken": {"timings": ["pre_battle"]}}), "战前：唤醒；致命"],
		[load_card.special_skill_text({"awaken": {"timings": ["pre_battle", "on_enter"]}}), "战前、入场：唤醒"],
		[load_card.special_skill_text({"on_trigger_gain": {"skill": "rally", "amount": 2}}), "己方角色触发集结时，自身战斗力 +2"],
		[load_card.special_skill_text({"on_resolve_bonus": {"skill": "corrode", "amount": 2}, "sturdy": 4}), "坚固4；己方角色结算腐蚀时，伤害 +2"],
		[load_card.special_skill_text({"bless": {"timings": ["on_enter"], "amount": 2}}), "入场：神佑2"],
		[load_card.special_skill_text({"immune_lethal": null, "sturdy": 2}), "坚固2；免疫致命"],
		[load_card.special_skill_text({"extra_resolve": {"scope": "self", "skill": "corrode"}}), "自身腐蚀多结算一次"],
		[load_card.special_skill_text({"extra_round": {"scope": "allies", "timing": "on_enter"}}), "己方入场多触发一轮"],
		[load_card.special_skill_text({"extra_round": {"scope": "first", "timing": "pre_battle"}}), "开战时位于己方第 1 位的角色，战前多触发一轮"],
		[load_card.special_skill_text({"grant": {"timings": ["pre_battle"], "target": "next", "skill": "lethal", "amount": null}}), "战前：下一位角色获得致命"],
		[load_card.special_skill_text({"grant": {"timings": ["on_enter"], "target": "allies", "skill": "rally", "amount": 1}}), "入场：己方全体获得集结1"],
		[load_card.special_skill_text({"clear_skills": {"timings": ["on_enter", "on_engage"], "target": "enemy_first_two"}}), "入场、交战：清除对方前两位的基础技能"],
		[load_card.special_skill_text({"raise_skills": {"timings": ["on_enter"], "skill": "any", "amount": 2}}), "入场：己方全体的基础技能值 +2"],
		[load_card.special_skill_text({"on_trigger_gain": {"skill": "any", "amount": 2}}), "己方角色触发基础技能时，自身战斗力 +2"],
		[load_card.special_skill_text({"double_skills": null}), "自身的基础技能数值翻倍"],
		[load_card.base_skill_text({"wealth": 1, "support": 3, "rage": 2}), "狂暴2、支援3、财富1"],
		[load_card.special_skill_text({"shelter": 1, "sturdy": 4}), "坚固4；庇护1"],
	]
	for c in cases:
		if c[0] != c[1]:
			_failures.append("[unit-skill-text] 期望 %s，实际 %s" % [c[1], c[0]])


## 战斗中的特殊技能栏：庇护被消耗还有剩余时显示新的层数（标紫），用完就移除，不显示"庇护0"
func _test_live_specials() -> void:
	var face := CardFace.new()
	face.show_cards("t_shelter_3", "")
	face.start_live(BattleSim.new([["t_shelter_3", ""]], [["t_pixie", ""]]).fields[1][0].describe())
	face.set_specials({"shelter": 1})
	var parts := face._special_parts()
	if parts.size() != 1 or parts[0][0] != "庇护1" or parts[0][2] != CardFace.CHANGED_SPECIAL:
		_failures.append("[unit-live-specials] 庇护剩 1 层应显示紫色的庇护1，实际 %s" % [parts])
	face.set_specials({})
	if not face._special_parts().is_empty():
		_failures.append("[unit-live-specials] 庇护用完应移除，实际 %s" % [face._special_parts()])
	face.free()
	# 基础技能和卡面印的比：带千机之匣的开局就标紫
	face = CardFace.new()
	face.show_cards("t_tiger_man", "t_clockwork_box")
	face.start_live(BattleSim.new([["t_tiger_man", "t_clockwork_box"]], [["t_pixie", ""]]).fields[1][0].describe())
	var chips := face._chips(face.live.base_skills, face._origin.base_skills)
	if chips.map(func(chip): return [chip[1], chip[3]]) != [["4", true], ["2", true]]:
		_failures.append("[unit-live-specials] 带千机之匣的虎人开局应显示紫色的狂暴4、集结2，实际 %s" % [chips])
	face.free()


## 回放检查：战斗场景最后显示的局面和 BattleSim 的结果一致。
## 覆盖动画播完、僵持压缩、动画中途跳过三种情况（高速播放）
func _run_replay_checks() -> void:
	var cases := [
		["animated", [["tiger_man", "lionheart"], ["fairy", ""]], [["porcupine", "holy_shield"], ["paladin", ""]], -1],
		["stalemate", [["angel", "riot_helmet"]], [["angel", "riot_helmet"]], -1],
		["skip-midway", [["soldier", ""], ["soldier", ""], ["tiger", "holy_water"]], [["sludge", "thorns"], ["shield_guard", ""]], 30],
		["mechanics", [["wisp", ""], ["fey_tiger", ""], ["mimic", ""], ["butterfly", ""], ["pixie", "hollow"]],
			[["captain", ""], ["toad", ""], ["soldier", ""], ["tiger", "flash_orb"], ["paladin", ""]], -1],
		# 下面两条要出现列出的机制（正式卡调数值后可能不再出现，届时换阵容）
		["mechanics-2", [["pure_sage", ""], ["high_priest", ""], ["knight_king", ""], ["ninja", ""], ["forest_archer", ""]],
			[["king_cobra", "golden_sword"], ["panda_hero", ""], ["envoy", ""], ["dream_mushroom", ""]], -1,
			["round", "assist", "grant", "again", "immune"]],
		["mechanics-3", [["shaman", ""], ["chanter", ""], ["alchemist", ""], ["arbiter", ""]],
			[["vulture", ""], ["parrot", ""], ["medusa", ""], ["swamp_king", ""], ["tumbleweed", ""], ["soldier", ""]], -1,
			["copy", "clear", "raise", "raise@beat", "grant", "half", "gain_half_skill_sum", "gain_if_outnumbered"]],
	]
	for c in cases:
		if c.size() > 4:
			var seen := _event_marks(BattleSim.simulate(c[1], c[2]).events)
			for mark in c[4]:
				if mark not in seen:
					_failures.append("[replay-%s] 阵容里没有出现 %s，换一个阵容" % [c[0], mark])
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
		# 结束（含跳过）后不留下飘字和亮起的技能方块、特殊技能栏
		await process_frame
		var lit: Array = (battle_manager.player_battle_fields[1] + battle_manager.player_battle_fields[2]).filter(
			func(card): return card.face.firing_skill != "" or card.face.firing_special)
		if scene.get_node("badges").get_child_count() > 0 or not lit.is_empty():
			_failures.append("[replay-%s] 结束后还有飘字或亮起的卡" % c[0])
		scene.free()
	await _check_skip_keeps_shelter()
	print("回放检查：%d 条" % (cases.size() + 1))


## 设置和进度存档：读写往返、不合法的值、备份恢复、新版本只读
func _run_save_tests() -> void:
	var fail := func(label: String, message: String) -> void: _failures.append("[save-%s] %s" % [label, message])
	GameSettings.speed = 0.5
	GameSettings.compact = true
	GameSettings.save()
	GameSettings.load()
	if GameSettings.speed != 0.5 or not GameSettings.compact:
		fail.call("settings", "读写往返应是 0.5× 和打开，实际 %s×、%s" % [GameSettings.speed, GameSettings.compact])
	_write(GameSettings.path, "[battle]\nspeed=3\n[board]\ncompact=\"yes\"\n")
	GameSettings.load()
	if GameSettings.speed != 1.0 or GameSettings.compact:
		fail.call("settings", "不合法的值应该用默认值，实际 %s×、%s" % [GameSettings.speed, GameSettings.compact])

	var path := SaveData.path
	SaveData.load()
	if SaveData.notice or SaveData.is_cleared("boar_rush"):
		fail.call("empty", "没有存档时应是空进度、没有通知")
	SaveData.mark_cleared("boar_rush")
	var first: String = _read_json(path).levels.boar_rush.first_cleared
	SaveData.load()
	SaveData.mark_cleared("boar_rush")
	if not SaveData.is_cleared("boar_rush") or SaveData.is_cleared("tiger_gale") or _read_json(path).levels.boar_rush.first_cleared != first:
		fail.call("round-trip", "读写往返后应只有 boar_rush 通关，第一次通关的时间不变")
	SaveData.mark_cleared("tiger_gale")  # 备份是写入前的：只有 boar_rush

	# 正式文件坏了：用备份恢复，坏文件改名为 .broken；之后再写入，备份不被坏文件覆盖
	_write(path, "{\"version\": 1, \"levels\": ")
	SaveData.load()
	if SaveData.notice != "ui.save.restored" or not SaveData.is_cleared("boar_rush") or SaveData.is_cleared("tiger_gale"):
		fail.call("restore", "应该用备份恢复（只有 boar_rush），通知 %s" % SaveData.notice)
	if FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".broken"):
		fail.call("restore", "坏的存档应改名为 .broken")
	SaveData.mark_cleared("tiger_gale")
	if _read_json(path + ".bak").levels.keys() != ["boar_rush"] or _read_json(path).levels.size() != 2:
		fail.call("restore", "恢复后再写入，备份应保持原样")

	# 备份也坏了：从空进度开始
	_write(path, "not json")
	_write(path + ".bak", "[]")
	SaveData.load()
	if SaveData.notice != "ui.save.reset" or SaveData.is_cleared("boar_rush"):
		fail.call("reset", "备份也坏了应从空进度开始，通知 %s" % SaveData.notice)

	# 比游戏新的版本：能读，但只读不写
	var newer := "{\"version\": 2, \"levels\": {\"boar_rush\": {\"cleared\": true}}, \"coins\": 5}"
	_write(path, newer)
	SaveData.load()
	if SaveData.notice != "ui.save.newer" or not SaveData.read_only or not SaveData.is_cleared("boar_rush"):
		fail.call("newer", "新版本的存档应该能读、只读，通知 %s" % SaveData.notice)
	SaveData.mark_cleared("tiger_gale")
	SaveData.clear_levels()
	if FileAccess.get_file_as_string(path) != newer:
		fail.call("newer", "新版本的存档不应被改写")

	_remove_test_files()
	GameSettings.load()
	SaveData.load()
	print("存档测试：6 组")


func _write(path: String, text: String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(text)


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _remove_test_files() -> void:
	for file in TEST_FILES:
		if FileAccess.file_exists("user://" + file):
			DirAccess.remove_absolute("user://" + file)


## 播放途中跳过：已经播放过的庇护消耗不能在最终局面里重复扣。
## 淤泥怪的腐蚀和交战各消耗一层，庇护3 最后剩 1
func _check_skip_keeps_shelter() -> void:
	global_var.battle_card_list_1 = ["t_sludge"]
	global_var.battle_equip_list_1 = [""]
	global_var.battle_card_list_2 = ["t_shelter_3"]
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
	var shown: String = load_card.special_skill_text(battle_manager.player_battle_fields[2][0].face.live.special_skills)
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
		shown["p%d" % side] = battle_manager.player_battle_fields[side].map(func(card): return [card.card_id, card.face.live.strength])
	if not Harness.same(shown, expected):
		_failures.append("[%s] 场景显示 %s，BattleSim 结果 %s" % [label, shown, Harness.outcome(expected)])
	# 技能在战斗中会变（获得、清除、改数值、复制、庇护消耗）：幸存的卡显示的技能和 BattleSim 结束时一样
	var sim := BattleSim.new(lineups[1], lineups[2])
	sim.run()
	for side in [1, 2]:
		var cards: Array = battle_manager.player_battle_fields[side]
		for n in mini(cards.size(), sim.fields[side].size()):
			var live: Dictionary = cards[n].face.live
			var unit = sim.fields[side][n]
			if live.base_skills != unit.base_skills or live.special_skills != unit.special_skills:
				_failures.append("[%s] %s 显示的技能 %s %s，BattleSim 是 %s %s" % [label, unit.uid, live.base_skills, live.special_skills,
					unit.base_skills, unit.special_skills])
	# 中间一带显示胜负（我方是下面一排，即 p2）
	var result: String = battle_manager.get_parent().get_node("%Result").text
	var word: String = tr({1: "ui.battle.lose", 2: "ui.battle.win", 3: "ui.battle.draw"}[expected.winner])
	if result != word:
		_failures.append("[%s] 应显示%s，实际 %s" % [label, word, result])
	# 点卡查看：大卡和场上的一样（当前战斗力）
	var survivors: Array = battle_manager.player_battle_fields[1] + battle_manager.player_battle_fields[2]
	if not survivors.is_empty():
		var detail: CardDetail = battle_manager.get_node("../cards").open_detail(survivors[0])
		var big: CardFace = detail.find_children("*", "CardFace", true, false)[0]
		if big.live.strength != survivors[0].face.live.strength:
			_failures.append("[%s] 点卡查看的战斗力 %s，场上 %s" % [label, big.live.strength, survivors[0].face.live.strength])
		detail.free()


func _run_smoke() -> void:
	# 启动时存档坏了：用备份恢复，主菜单弹一次通知
	_write(SaveData.path, "{")
	_write(SaveData.path + ".bak", JSON.stringify({"version": 1, "levels": {}}))
	var manager: Node = load("res://scenes/app/scene_manager.tscn").instantiate()
	root.add_child(manager)
	await _frames(2)
	var notices := manager.get_node("MenuScene").find_children("*", "Dialog", true, false)
	if notices.size() != 1:
		_failures.append("[smoke-save] 存档用备份恢复时主菜单应弹通知，实际 %d 个" % notices.size())
	for dialog in notices:
		dialog._close(true)

	# 设置：改默认速度和紧凑模式，立刻保存
	manager.get_node("MenuScene")._on_settings_pressed()
	await _frames(2)
	var settings: Node = manager.current_scene
	settings.set_speed(0.5)
	settings.set_compact(true)
	GameSettings.load()
	if GameSettings.speed != 0.5 or not GameSettings.compact or not settings._speed_buttons[0.5].button_pressed:
		_failures.append("[smoke-settings] 改了设置应立刻保存，实际 %s×、%s" % [GameSettings.speed, GameSettings.compact])
	settings._on_back_button_pressed()
	await _frames(2)

	# 科研模式：选卡、拖放规则；设置阵容 → 开始战斗 → 跳过 → 返回 → 主菜单
	# 紧凑模式进入时是默认值（上面改成了打开）；临时关掉，打完一场回来还关着
	manager.get_node("MenuScene")._on_test_mode_pressed()
	await _frames(2)
	var sandbox: Node = manager.current_scene
	_expect_compact(sandbox, true, "进入科研模式")
	await _check_sandbox(sandbox)
	for slot in [[1, 0, "tiger_man", "lionheart"], [2, 0, "porcupine", "holy_shield"], [2, 1, "fairy", ""]]:
		sandbox.set_unit(slot[0], slot[1], slot[2], slot[3])
	sandbox.get_node("%Compact").button_pressed = false
	sandbox._on_start_battle_pressed()
	await _play_battle_and_return(manager)
	_expect_compact(sandbox, false, "从战斗回到科研模式")
	sandbox._on_back_button_pressed()
	await _frames(2)

	# 闯关：展开关卡详情；第一关检查布阵交互规则；两关各布阵一次 → 开始战斗 → 返回
	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(2)
	_check_level_select(manager.current_scene)
	manager.current_scene.enter_level(LevelDB.all().keys()[0])
	await create_timer(0.3).timeout  # 等手牌入场动画
	await _check_lineup_rules(manager)
	manager.current_scene._on_back_button_pressed()
	await _frames(2)
	# 进入时紧凑模式是默认值，临时切换后打完回来保持；赢了才记通关（第一关用能赢的摆法）
	for level_id in LevelDB.all():
		manager.current_scene.enter_level(level_id)
		await create_timer(0.3).timeout
		var setup: Node = manager.current_scene
		_expect_compact(setup, GameSettings.compact, "进入构筑阶段")
		var column: Rect2 = setup.get_node("RightColumn").get_rect()
		if setup.get_node("player_hand")._top < column.end.y:
			_failures.append("[smoke-layout] 紧凑模式下手牌（顶边 %d）压住了右列（底边 %d）" % [setup.get_node("player_hand")._top, column.end.y])
		var slots: Array = setup.get_node("player_card_slots").get_children()
		if WINNING.has(level_id):
			for i in WINNING[level_id].size():
				for id in WINNING[level_id][i]:
					if id:
						_drag(setup, _hand_card(setup, id), slots[i])
		else:
			var hand: Array = setup.get_node("player_hand").player_hand.duplicate()
			var chars := hand.filter(func(card): return card.card_id != "")
			for i in chars.size():
				_drag(setup, chars[i], slots[i])
		setup.get_node("%Compact").button_pressed = not GameSettings.compact
		setup._on_start_battle_pressed()
		var winner: int = await _play_battle_and_return(manager)
		_expect_compact(setup, not GameSettings.compact, "从战斗回到构筑阶段")
		if SaveData.is_cleared(level_id) != (winner == 2):
			_failures.append("[smoke-records] %s：胜负 %d，通关记录 %s" % [level_id, winner, SaveData.is_cleared(level_id)])
		setup._on_back_button_pressed()
		await _frames(2)
	if not SaveData.is_cleared(WINNING.keys()[0]):
		_failures.append("[smoke-records] 打赢了应记通关")
	_check_cleared_tiles(manager.current_scene, "打完之后")
	manager.current_scene._on_back_button_pressed()
	await _frames(2)

	# 设置：清除闯关记录（确认框点"确定"），关卡选择不再显示已通关
	manager.get_node("MenuScene")._on_settings_pressed()
	await _frames(2)
	settings = manager.current_scene
	settings.clear_records()
	await _frames(1)
	var dialogs := settings.find_children("*", "Dialog", true, false)
	if dialogs.size() == 1:
		dialogs[0]._close(true)
	else:
		_failures.append("[smoke-settings] 清除闯关记录应弹确认框")
	await _frames(1)
	if LevelDB.all().keys().any(func(id): return SaveData.is_cleared(id)) or not settings._clear.disabled:
		_failures.append("[smoke-settings] 清除后不应还有通关记录")
	settings._on_back_button_pressed()
	await _frames(2)
	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(2)
	_check_cleared_tiles(manager.current_scene, "清除之后")
	manager.current_scene._on_back_button_pressed()
	await _frames(2)

	# 图鉴：筛选、排序、点卡放大
	manager.get_node("MenuScene")._on_book_mode_pressed()
	await _frames(2)
	_check_book(manager.current_scene)
	await _frames(2)
	manager.current_scene._on_back_button_pressed()
	await _frames(2)

	manager.free()
	print("冒烟流程：完成")


## 科研模式：为选中的卡位选卡（角色替换角色、装备装到角色身上），拖动互换、拖出移除，交换双方、清空
func _check_sandbox(sandbox: Node) -> void:
	var expect := func(label: String, side: int, index: int, unit: Array) -> void:
		if sandbox.lineups[side][index] != unit:
			_failures.append("[smoke-sandbox] %s：%s 第 %d 位应是 %s，实际 %s" % [label, side, index + 1, unit, sandbox.lineups[side][index]])
	sandbox.select_slot(2, 0)
	sandbox.pick("tiger")
	expect.call("选角色", 2, 0, ["tiger", ""])
	sandbox.pick("iron_sword")
	expect.call("选装备", 2, 0, ["tiger", "iron_sword"])
	sandbox.pick("soldier")
	expect.call("换角色，装备保留", 2, 0, ["soldier", "iron_sword"])
	sandbox.select_slot(2, 1)
	sandbox.pick("holy_shield")
	expect.call("空卡位不能选装备", 2, 1, [])
	var board: Node = sandbox.get_node("board")
	# 从选卡区拖出的卡不留影子（原卡还在选卡区）
	board.start_drag_new("soldier")
	if board._ghost != null:
		_failures.append("[smoke-sandbox] 从选卡区拖出的卡不应留下影子")
	board.drop_card(null)
	var slots: Dictionary = sandbox._slots
	board.start_drag(slots[2][0].card_in_slot)
	board.drop_card(slots[1][3])
	expect.call("拖到对方空卡位", 1, 3, ["soldier", "iron_sword"])
	expect.call("原来的卡位空了", 2, 0, [])
	sandbox.set_unit(2, 0, "paladin")
	board.start_drag(slots[2][0].card_in_slot)
	board.drop_card(slots[1][3])
	expect.call("互换", 2, 0, ["soldier", "iron_sword"])
	expect.call("互换", 1, 3, ["paladin", ""])
	board.start_drag(slots[1][3].card_in_slot)
	board.drop_card(null)
	expect.call("拖出去移除", 1, 3, [])
	sandbox.swap_sides()
	expect.call("交换双方", 1, 0, ["soldier", "iron_sword"])
	sandbox._on_start_battle_pressed()
	await _frames(2)
	if not sandbox.find_children("*", "Dialog", true, false).is_empty():
		for dialog in sandbox.find_children("*", "Dialog", true, false):
			dialog.queue_free()
	else:
		_failures.append("[smoke-sandbox] 我方没有角色时应该提示")
	sandbox.clear_all()
	expect.call("清空全部", 1, 0, [])


## 关卡选择：同时只展开一个关卡，详情里是它的敌方阵容
func _check_level_select(select: Node) -> void:
	var ids: Array = LevelDB.all().keys()
	for id in [ids[0], ids[-1]]:
		select.toggle_level(id)
		var portraits := select.find_children("*", "UnitPortrait", true, false)
		if portraits.size() != LevelDB.level(id).enemy.size():
			_failures.append("[smoke-levels] 展开 %s 应显示 %d 个敌方单位，实际 %d 个" % [id, LevelDB.level(id).enemy.size(), portraits.size()])
	select.toggle_level(ids[-1])
	if not select.find_children("*", "UnitPortrait", true, false).is_empty():
		_failures.append("[smoke-levels] 再点一次应该收起详情")


## 图鉴的筛选：组内满足任一，组间同时满足；排序；点卡放大
func _check_book(book: Node) -> void:
	# 布局：侧栏不被内容撑宽、不压住顶栏和网格；排序、重置筛选在网格的截断线以上
	var rail: Control = book.get_node("Rail")
	var scroll: Control = book.get_node("Scroll")
	if rail.get_rect().end.x > book.get_node("Head").position.x or rail.get_rect().end.x > scroll.position.x:
		_failures.append("[smoke-book] 侧栏宽 %d，压住了顶栏或网格" % rail.size.x)
	for button in [book.get_node("%Sort"), book.get_node("Head/Reset")]:
		if button.get_global_rect().end.y > scroll.global_position.y:
			_failures.append("[smoke-book] %s 的下边 %d 低于网格的截断线 %d" % [button.name, button.get_global_rect().end.y, scroll.global_position.y])
	var cards: Array = CardDB.all().values()
	var expect := func(label: String, filter: Callable) -> void:
		var count := cards.filter(filter).size()
		if book.shown.size() != count:
			_failures.append("[smoke-book] %s 应有 %d 张，实际 %d 张" % [label, count, book.shown.size()])
	book.toggle_filter("types", "character")
	expect.call("只看装备", func(c): return c.type == "equipment")
	book.toggle_filter("types", "character")
	book.toggle_filter("stars", 2)
	expect.call("2★", func(c): return c.star == 2)
	book.toggle_filter("stars", 1)
	expect.call("1★ 或 2★", func(c): return c.star in [1, 2])
	book.toggle_filter("races", "elf")
	expect.call("1★ 或 2★，且是精灵", func(c): return c.star in [1, 2] and "elf" in c.get("races", []))
	book.reset_filters()
	book.toggle_filter("special", "shelter")
	expect.call("庇护", func(c): return c.get("special_skills") is Dictionary and c.special_skills.has("shelter"))
	book.reset_filters()
	book.set_search("集结")
	if book.shown.is_empty():
		_failures.append("[smoke-book] 搜索“集结”应有结果")
	book.reset_filters()
	book.set_sort("strength")
	var strengths: Array = book.shown.map(func(id): return CardDB.card(id).get("strength", 0))
	if strengths[0] != strengths.max():
		_failures.append("[smoke-book] 按战斗力排序，第一张应是最高的")
	book.open_zoom("porcupine")
	if book.find_children("*", "CardZoom", true, false).size() != 1:
		_failures.append("[smoke-book] 点卡应该打开放大")


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
	# 整理手牌：按图鉴的默认顺序（卡牌序号）
	var hand: Node = setup.get_node("player_hand")
	hand.sort_hand()
	var numbers: Array = hand.player_hand.map(func(c): return CardDB.card(c.card_id if c.card_id else c.equip_id).no)
	var sorted := numbers.duplicate()
	sorted.sort()
	if numbers != sorted:
		_failures.append("[smoke-lineup] 整理手牌后应按序号排列，实际 %s" % [numbers])


func _expect_compact(scene: Node, on: bool, label: String) -> void:
	if global_var.compact_mode != on or scene.get_node("%Compact").button_pressed != on:
		_failures.append("[smoke-compact] %s：紧凑模式应是 %s，实际 %s" % [label, on, global_var.compact_mode])


## 关卡选择的已通关样式和存档一致
func _check_cleared_tiles(select: Node, label: String) -> void:
	var ids: Array = LevelDB.all().keys()
	var tiles := select.find_children("*", "LevelTile", true, false)
	for i in tiles.size():
		if tiles[i].cleared != SaveData.is_cleared(ids[i]):
			_failures.append("[smoke-records] %s：关卡 %s 的已通关样式和存档不一致" % [label, ids[i]])


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


## 模拟玩家点击：开始战斗 → 跳过 → 等结束 → 返回；开战速度是默认值，速度按钮按顺序循环。返回胜负
func _play_battle_and_return(manager: Node) -> int:
	await _frames(2)
	var battle_manager: Node = manager.get_node("main/battle_manager")
	if battle_manager.battle_speed != GameSettings.speed:
		_failures.append("[smoke-battle] 开战速度应是默认的 %s×，实际 %s×" % [GameSettings.speed, battle_manager.battle_speed])
	# 默认速度在上面的设置里改成了 0.5×；按一圈速度按钮回到 0.5×
	var speed_button: Button = manager.get_node("main/Controls/SpeedButton")
	var shown: Array[String] = []
	for i in GameSettings.SPEEDS.size():
		battle_manager._on_speed_button_pressed()
		shown.append(speed_button.text)
	if shown != ["1×", "2×", "5×", "20×", "0.5×"] or battle_manager.battle_speed != 0.5:
		_failures.append("[smoke-battle] 速度按钮应按 1×、2×、5×、20×、0.5× 循环，实际 %s" % [shown])
	battle_manager._on_start_battle_pressed_battle()
	await _frames(2)
	battle_manager._on_skip_button_pressed()
	while battle_manager.winner == 0:
		await process_frame
	_check_replay(battle_manager, "smoke-battle")
	var winner: int = battle_manager.winner
	battle_manager._on_start_battle_pressed_battle()
	await _frames(2)
	return winner


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
