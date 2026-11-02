extends Control

signal to_test_mode
signal to_book_mode
signal to_single_mode


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 随机选择主菜单背景图片
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var background_index = rng.randi_range(1, 2)
	var background_path = "res://assets/background/main_menu_" + str(background_index) + ".png"
	
	# 设置背景图片
	var background_texture = load_background.set_texture_for_node(
		$Background, 
		background_path, 
		0.7, 
		Vector2(1920, 1080)
	)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_test_mode_pressed() -> void:
	emit_signal("to_test_mode")


func _on_single_mode_pressed() -> void:
	emit_signal("to_single_mode")

func _on_adventure_mode_pressed() -> void:
	pass # Replace with function body.

func _on_offline_battle_mode_pressed() -> void:
	pass # Replace with function body.

func _on_book_mode_pressed() -> void:
	emit_signal("to_book_mode")

