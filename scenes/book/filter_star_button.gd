extends OptionButton


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_popup().add_theme_font_size_override("font_size",30)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
