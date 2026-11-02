extends Control

signal back_to_menu
signal select_level

var font_size = 35  # 字体大小
var button_size = Vector2(200, 90)  # 按钮尺寸

signal level_select(level_id)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var background_path = "res://assets/backgrounds/level_select.png"
	# 设置背景图片
	var background_texture = load_background.set_texture_for_node(
		$Background, 
		background_path, 
		0.5, 
		Vector2(1920, 1080)
	)
	for level_id in LevelDB.all():
		add_level_button(level_id)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func add_level_button(level_id):
	var button = Button.new()  # 创建新按钮
	button.text = tr("level." + level_id)  # 显示关卡名
	button.add_theme_font_size_override("font_size",font_size)
	button.custom_minimum_size = button_size  # 设置按钮最小尺寸
	# 连接 "pressed" 信号，传递关卡 id 作为参数
	button.connect("pressed", self._on_level_select_button_pressed.bind(level_id))
	$"FlowContainer".add_child(button)  # 将按钮添加到 FlowContainer

func _on_level_select_button_pressed(level_id):
	emit_signal("select_level", level_id)


func _on_back_button_pressed() -> void:
	emit_signal("back_to_menu")
