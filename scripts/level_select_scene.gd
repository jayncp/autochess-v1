extends Control

signal back_to_menu
signal select_level

var font_size = 35  # 字体大小
var button_size = Vector2(200, 90)  # 按钮尺寸

signal level_select(level_name)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var background_path = "res://assets/background/level_select_background.png"
	# 设置背景图片
	var background_texture = load_background.set_texture_for_node(
		$Background, 
		background_path, 
		0.5, 
		Vector2(1920, 1080)
	)
	var level_database_reference = preload("res://scripts/database/level_database.gd")
	var level_name_list = level_database_reference.LEVEL.keys()
	for level_name in level_name_list:
		add_button_by_text(level_name)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func add_button_by_text(button_name):
	var button = Button.new()  # 创建新按钮
	button.text = button_name  # 设置按钮文本
	button.add_theme_font_size_override("font_size",font_size)
	button.custom_minimum_size = button_size  # 设置按钮最小尺寸
	# 连接 "pressed" 信号到 _on_button_pressed 函数，传递文本作为参数
	button.connect("pressed", self._on_level_select_button_pressed.bind(button_name))
	$"FlowContainer".add_child(button)  # 将按钮添加到 FlowContainer

func _on_level_select_button_pressed(level_name):
	emit_signal("select_level", level_name)


func _on_back_button_pressed() -> void:
	emit_signal("back_to_menu")
