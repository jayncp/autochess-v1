extends Node
## 场景切换：主菜单 → 科研模式 / 闯关（关卡选择 → 布阵）/ 图鉴 / 设置。启动时读设置和进度存档。
## 进入布阵、科研模式时紧凑模式设成默认值；从战斗回来不算重新进入，保持当次临时切的。
## 开战时战斗场景盖在当前场景上面，当前场景隐藏并停用（停用后它的卡牌不参与物理拾取），战斗结束后回到它。

const MENU := preload("res://scenes/menu/menu.tscn")
const SANDBOX := preload("res://scenes/sandbox/sandbox.tscn")
const LEVEL_SELECT := preload("res://scenes/level/level_select.tscn")
const LEVEL_SETUP := preload("res://scenes/level/level_setup.tscn")
const BOOK := preload("res://scenes/book/book.tscn")
const SETTINGS := preload("res://scenes/settings/settings.tscn")
const BATTLE := preload("res://scenes/battle/battle.tscn")

## 当前的场景（主菜单以外）；在主菜单时为 null
var current_scene = null


func _ready() -> void:
	GameSettings.load()
	SaveData.load()
	load_menu_scene()


func load_menu_scene() -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	var menu := MENU.instantiate()
	menu.to_test_mode.connect(_on_to_test_mode)
	menu.to_single_mode.connect(_show_level_select)
	menu.to_book_mode.connect(_on_to_book_mode)
	menu.to_settings.connect(_on_to_settings)
	add_child(menu)


## 换成新场景：去掉主菜单或当前场景
func _switch(scene: Node) -> void:
	if has_node("MenuScene"):
		get_node("MenuScene").queue_free()
	if current_scene:
		current_scene.queue_free()
	current_scene = scene
	add_child(scene)


func _on_to_test_mode() -> void:
	global_var.compact_mode = GameSettings.compact
	var sandbox := SANDBOX.instantiate()
	sandbox.start_battle.connect(_on_start_battle)
	sandbox.back_to_menu.connect(load_menu_scene)
	_switch(sandbox)


func _show_level_select() -> void:
	var select := LEVEL_SELECT.instantiate()
	select.select_level.connect(_on_select_level)
	select.back_to_menu.connect(load_menu_scene)
	_switch(select)


func _on_select_level(level_id: String) -> void:
	global_var.compact_mode = GameSettings.compact
	var setup := LEVEL_SETUP.instantiate()
	setup.level_id = level_id
	setup.back_to_level_select.connect(_show_level_select)
	setup.start_battle.connect(_on_start_battle)
	_switch(setup)


func _on_to_book_mode() -> void:
	var book := BOOK.instantiate()
	book.back_to_menu.connect(load_menu_scene)
	_switch(book)


func _on_to_settings() -> void:
	var settings := SETTINGS.instantiate()
	settings.back_to_menu.connect(load_menu_scene)
	_switch(settings)


func _on_start_battle() -> void:
	var battle := BATTLE.instantiate()
	battle.get_node("battle_manager").back_to_last_scene.connect(_on_back_to_last_scene)
	current_scene.visible = false
	current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(battle)


func _on_back_to_last_scene() -> void:
	get_node("main").queue_free()
	current_scene.visible = true
	current_scene.process_mode = Node.PROCESS_MODE_INHERIT
