extends Node


var current_scene = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	load_menu_scene()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

###
# "主菜单"
###
func load_menu_scene():
	# 清除其他场景
	if current_scene:
		current_scene.queue_free()
		current_scene = null
	
	var menu_scene = preload("res://scenes/menu_scene.tscn").instantiate()
	menu_scene.connect("to_test_mode", Callable(self, "_on_to_test_mode"))
	menu_scene.connect("to_single_mode", Callable(self, "_on_to_single_mode"))
	menu_scene.connect("to_book_mode", Callable(self, "_on_to_book_mode"))

	add_child(menu_scene)

###
# "科研模式"
###
func _on_to_test_mode():

	get_node("MenuScene").queue_free()

	current_scene = preload("res://scenes/test_scene.tscn").instantiate()
	current_scene.get_node("select_manager").connect("start_battle",Callable(self, "_on_start_battle"))
	current_scene.connect("back_to_menu",Callable(self, "_on_selection_back_to_menu"))

	add_child(current_scene)

###
# "闯关模式"
###
func _on_to_single_mode():

	get_node("MenuScene").queue_free()

	current_scene = preload("res://scenes/level_select_scene.tscn").instantiate()
	current_scene.connect("select_level",Callable(self, "_on_select_level"))
	current_scene.connect("back_to_menu",Callable(self, "_on_selection_back_to_menu"))

	add_child(current_scene)

# 进入指定关卡
func _on_select_level(level_name):
	get_node("LevelSelectScene").queue_free()
	current_scene = preload("res://scenes/pre_battle.tscn").instantiate()
	current_scene.connect("back_to_level_select",Callable(self, "_on_back_to_level_select"))
	current_scene.connect("start_battle",Callable(self, "_on_start_battle"))
	current_scene.level_name = level_name
	add_child(current_scene)

# 返回关卡选择
func _on_back_to_level_select():
	get_node("PreBattleScene").queue_free()

	current_scene = preload("res://scenes/level_select_scene.tscn").instantiate()
	current_scene.connect("select_level",Callable(self, "_on_select_level"))
	current_scene.connect("back_to_menu",Callable(self, "_on_selection_back_to_menu"))

	add_child(current_scene)

###
# "图鉴模式"
###
func _on_to_book_mode():
	get_node("MenuScene").queue_free()
	current_scene = preload("res://scenes/book_scene.tscn").instantiate()
	current_scene.connect("back_to_menu",Callable(self, "_on_selection_back_to_menu"))
	add_child(current_scene)




# 返回主菜单
func _on_selection_back_to_menu():
	current_scene.queue_free()
	current_scene = null
	load_menu_scene()

# "开始战斗"
func _on_start_battle():
	var battle_scene = preload("res://scenes/main.tscn").instantiate()
	battle_scene.get_node("battle_manager").connect("back_to_last_scene",Callable(self,"_on_back_to_last_scene"))
	# 隐藏当前场景
	current_scene.visible = false
	# 将整个场景向下移动到屏幕外，防止射线投射检测
	current_scene.position.y += 1500

	add_child(battle_scene)

# 战斗结束返回到上一层
func _on_back_to_last_scene():
	get_node("main").queue_free()
	# 显示当前场景
	current_scene.visible = true
	# 将整个场景向上移动到屏幕内
	current_scene.position.y -= 1500
