extends SceneTree
## 界面截图：把各界面截到指定目录，用来对照样稿、给用户看。需要窗口（不能 --headless）。
## 用法：just shots <输出目录> [宽度]，宽度默认 1920，手机用 2376
## 截图：主菜单、主题控件、对话框；卡牌一览（cards_*，缩放 1，和样稿 cards.html 的几页对应）；用到卡牌的各界面

var out: String


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/autochess_shots"
	var width := int(args[1]) if args.size() > 1 else 1920
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(width, 1080)
	root.content_scale_size = Vector2i(width, 1080)
	await _frames(3)

	var manager: Node = load("res://scenes/app/scene_manager.tscn").instantiate()
	root.add_child(manager)
	await _frames(5)
	await _shot("menu")
	manager.free()

	var kit := _ui_kit()
	root.add_child(kit)
	await _frames(5)
	await _shot("ui_kit")
	Dialog.confirm(kit, "清空全部", "确定要清空双方的阵容吗？")
	await _frames(5)
	await _shot("dialog")
	kit.free()

	await _card_pages()
	await _screens()
	quit()


## 主题控件一览
func _ui_kit() -> Control:
	var page := Control.new()
	page.theme = load("res://assets/ui/theme.tres")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/backgrounds/menu.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var panel := PanelContainer.new()
	panel.position = Vector2(80, 60)
	panel.custom_minimum_size = Vector2(1100, 900)
	page.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 26)
	panel.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "主题控件"
	column.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 30)
	column.add_child(buttons)
	for spec in [["返回", ""], ["交换双方", ""], ["开始战斗", "PrimaryButton"], ["不可用", ""]]:
		var b := UiButton.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 66)
		b.theme_type_variation = spec[1]
		b.disabled = spec[0] == "不可用"
		buttons.add_child(b)
	var icon := Button.new()
	icon.theme_type_variation = &"IconButton"
	icon.icon = load("res://assets/ui/icons/back.png")
	icon.expand_icon = true
	icon.custom_minimum_size = Vector2(66, 66)
	buttons.add_child(icon)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 30)
	column.add_child(toggles)
	for spec in [["紧凑模式", true], ["紧凑模式", false]]:
		var t := CheckButton.new()
		t.text = spec[0]
		t.button_pressed = spec[1]
		toggles.add_child(t)
	for spec in [["角色", true], ["装备", false]]:
		var c := CheckBox.new()
		c.text = spec[0]
		c.button_pressed = spec[1]
		toggles.add_child(c)
	var inputs := HBoxContainer.new()
	inputs.add_theme_constant_override("separation", 30)
	column.add_child(inputs)
	var edit := LineEdit.new()
	edit.placeholder_text = "卡名、种族、词条、效果"
	edit.custom_minimum_size = Vector2(420, 62)
	inputs.add_child(edit)
	var option := OptionButton.new()
	for item in ["排序：序号", "排序：星级", "排序：战斗力"]:
		option.add_item(item)
	option.custom_minimum_size = Vector2(260, 56)
	inputs.add_child(option)
	var tabs := TabBar.new()
	tabs.add_tab("角色")
	tabs.add_tab("装备")
	tabs.add_tab("教学关")
	column.add_child(tabs)
	var hint := Label.new()
	hint.theme_type_variation = &"HintLabel"
	hint.text = "长按卡牌查看详情"
	column.add_child(hint)
	var body := Label.new()
	body.text = "正文：每次交战后，自身受到 4 点伤害。"
	column.add_child(body)
	return page


## 卡牌一览：缩放 1，和样稿 cards.html 的几页对应。演示用的卡（测试角色、测试装备）只在截图时加入
func _card_pages() -> void:
	var names := Translation.new()
	names.locale = "zh_CN"
	names.add_message("card.demo_hero", "测试角色")
	names.add_message("card.demo_gear", "测试装备")
	TranslationServer.add_translation(names)
	CardDB.add_cards([
		{"id": "demo_hero", "no": 0, "type": "character", "star": 3, "races": ["beast", "human", "divine"], "strength": 9,
			"timing_1": "on_enter", "skills_1": {"rage": 2, "rally": 1, "inspire": 1, "corrode": 3}},
		{"id": "demo_gear", "no": 0, "type": "equipment", "star": 3, "strength": 3,
			"timing_2": "on_engage", "skills_2": {"support": 3, "wealth": 2}, "special_skills": {"sturdy": 2}},
	])
	var tiers := []
	var equipment_tiers := []
	for star in range(1, 6):
		tiers.append({"card": "paladin", "star": star, "caption": "%d★ 角色" % star})
		equipment_tiers.append({"equip": "holy_shield", "star": star, "caption": "%d★ 装备" % star})
	await _card_page("cards_tiers", [["星级：边框材质 + 法阵纹路", tiers], ["装备：底色随星级", equipment_tiers]])

	var characters := ["tiger", "tiger_man", "toad", "wisp", "half_elf", "maneater"].map(func(id): return {"card": id})
	var equipment := ["iron_sword", "holy_shield", "war_banner", "holy_water", "necklace", "hollow"].map(func(id): return {"equip": id})
	await _card_page("cards_build", [["构筑阶段", characters], ["装备卡", equipment]])

	var pairs := [["tiger_man", "war_banner"], ["porcupine", "holy_shield"], ["fairy", "holy_water"], ["soldier", "necklace"], ["maneater", "hollow"], ["demo_hero", "demo_gear"]]
	var combined := pairs.map(func(pair): return {"card": pair[0], "equip": pair[1]})
	var live := [
		{"card": "tiger_man", "equip": "war_banner", "live": {"firing": "on_engage", "strength": 13, "base_skills": {"rally": 4}}, "caption": "交战发动；改变的数值为紫色"},
		{"card": "porcupine", "equip": "holy_shield", "live": {"specials": {}, "strength": 6}, "caption": "庇护用完"},
		{"card": "fairy", "equip": "holy_water", "live": {"firing": "pre_battle"}, "caption": "战前发动"},
		{"card": "toad", "live": {"firing": "on_enter"}, "caption": "入场发动"},
		{"card": "soldier", "equip": "necklace", "live": {}, "caption": "未发动"},
		{"card": "demo_hero", "equip": "demo_gear", "live": {"firing": "on_enter", "strength": 15}, "caption": "多词条自动缩字"},
	]
	await _card_page("cards_combo", [["角色 + 装备", combined], ["战斗实时状态", live]])

	var races := [[["beast"], 2], [["beast", "human"], 2], [["beast", "human", "divine"], 3], [["beast", "human", "elf", "nature"], 4]]
	var multi := races.map(func(r): return {"card": "tiger_man", "races": r[0], "star": r[1], "caption": "%d 种族" % r[0].size()})
	var compact := [
		{"card": "tiger_man", "equip": "war_banner", "compact": true},
		{"card": "porcupine", "equip": "holy_shield", "compact": true},
		{"card": "fairy", "equip": "holy_water", "compact": true, "live": {"firing": "pre_battle"}, "caption": "紧凑卡 + 实时状态"},
		{"card": "toad", "compact": true},
		{"equip": "iron_sword", "compact": true},
		{"card": "demo_hero", "equip": "demo_gear", "compact": true},
	]
	await _card_page("cards_compact", [["多种族背景", multi], ["紧凑卡", compact]])
	CardDB.all().erase("demo_hero")
	CardDB.all().erase("demo_gear")
	TranslationServer.remove_translation(names)


## 一页：每行一个标题和一排卡
func _card_page(name: String, rows: Array) -> void:
	var page := Control.new()
	page.theme = load("res://assets/ui/theme.tres")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("161c38")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var column := VBoxContainer.new()
	column.position = Vector2(24, 12)
	column.add_theme_constant_override("separation", 6)
	page.add_child(column)
	for row in rows:
		var title := Label.new()
		title.text = row[0]
		title.add_theme_font_size_override("font_size", 26)
		column.add_child(title)
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 48 if row[1].size() <= 5 else 16)
		column.add_child(cards)
		for spec in row[1]:
			cards.add_child(_card_cell(spec))
	root.add_child(page)
	await _frames(5)
	await _shot(name)
	page.free()


## 一张卡加说明文字；spec 见 _card_pages（star、races 临时覆盖卡牌数据，live 是战斗实时状态）
func _card_cell(spec: Dictionary) -> Control:
	var face := CardFace.new()
	face.display_scale = 1.0
	face.compact = spec.get("compact", false)
	var id: String = spec.get("card", spec.get("equip"))
	var original := CardDB.card(id)
	if spec.has("star") or spec.has("races"):
		var data := original.duplicate(true)
		data.star = spec.get("star", data.star)
		if spec.has("races"):
			data.races = spec.races
		CardDB.add_cards([data])
	face.show_cards(spec.get("card", ""), spec.get("equip", ""))
	CardDB.add_cards([original])
	if spec.has("live"):
		face.start_live(CardDB.combine(spec.card, spec.get("equip", "")))
		var state: Dictionary = spec.live
		face.set_firing(state.get("firing", ""))
		face.set_strength(state.get("strength", face.live.strength))
		face.set_specials(state.get("specials", face.live.special_skills))
		face.live.base_skills.merge(state.get("base_skills", {}), true)
	var cell := VBoxContainer.new()
	var holder := Control.new()
	holder.custom_minimum_size = face.get_size() + Vector2(0, 8)
	face.position = holder.custom_minimum_size / 2
	holder.add_child(face)
	cell.add_child(holder)
	var caption := Label.new()
	caption.theme_type_variation = &"HintLabel"
	caption.text = spec.get("caption", "")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(caption)
	return cell


## 用到卡牌的界面（还是旧布局，卡牌缩放 0.6）：图鉴、科研模式、闯关布阵、战斗开始前、战斗中、战斗结束
func _screens() -> void:
	var manager: Node = load("res://scenes/app/scene_manager.tscn").instantiate()
	root.add_child(manager)
	await _frames(3)
	manager.get_node("MenuScene")._on_book_mode_pressed()
	await _frames(5)
	await _shot("book")
	manager.current_scene._on_back_button_pressed()
	await _frames(3)

	manager.get_node("MenuScene")._on_single_mode_pressed()
	await _frames(3)
	manager.current_scene._on_level_select_button_pressed(LevelDB.all().keys()[0])
	await create_timer(0.6).timeout
	await _shot("level")
	manager.current_scene._on_back_button_pressed()
	await _frames(3)
	manager.current_scene._on_back_button_pressed()
	await _frames(3)

	manager.get_node("MenuScene")._on_test_mode_pressed()
	await _frames(3)
	var select: Node = manager.current_scene.get_node("select_manager")
	var lineup := [[1, 0, "tiger_man", "lionheart"], [1, 1, "toad", ""], [1, 2, "fairy", "holy_water"], [1, 3, "paladin", ""],
		[2, 0, "porcupine", "holy_shield"], [2, 1, "wisp", ""], [2, 2, "half_elf", ""], [2, 3, "sludge", "thorns"], [2, 4, "captain", ""]]
	for slot in lineup:
		select.init_card_list[slot[0]][slot[1]] = slot[2]
		select.init_equip_list[slot[0]][slot[1]] = slot[3]
		select.update_display(slot[0], slot[1], slot[2], slot[3])
	await _frames(3)
	await _shot("sandbox")
	select._on_start_battle_pressed()
	await _frames(5)
	await _shot("battle_start")
	var battle_manager: Node = manager.get_node("main/battle_manager")
	battle_manager._on_start_battle_pressed_battle()
	await create_timer(2.2).timeout
	await _shot("battle_mid")
	battle_manager._on_skip_button_pressed()
	await _frames(5)
	await _shot("battle_end")
	manager.free()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("截图 ", name)
