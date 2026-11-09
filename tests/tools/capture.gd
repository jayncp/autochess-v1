extends SceneTree
## 界面截图：把各界面截到指定目录，用来对照样稿、给用户看。需要窗口（不能 --headless）。
## 用法：just shots <输出目录> [宽度]，宽度默认 1920，手机用 2376

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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("截图 ", name)
