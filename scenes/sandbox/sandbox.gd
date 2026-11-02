extends Node2D


signal back_to_menu

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var background_path = "res://assets/backgrounds/setup.png"
	# 设置背景图片
	var background_texture = load_background.set_texture_for_node(
		$Background, 
		background_path, 
		0.5, 
		Vector2(1920, 1080)
	)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_back_button_pressed() -> void:
	emit_signal("back_to_menu")
