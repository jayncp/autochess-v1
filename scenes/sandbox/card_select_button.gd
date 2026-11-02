extends OptionButton

signal card_select

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_parent().connect_card_select_signal(self)
	get_popup().add_theme_font_size_override("font_size",25)
	get_popup().max_size = Vector2(1000,300)
	# 第 0 项是"无"；其余每项显示中文名，metadata 存卡牌 id
	for id in CardDB.ids("character"):
		get_popup().add_item(tr("card." + id))
		get_popup().set_item_metadata(get_popup().item_count - 1, id)
	
	# 修改下拉菜单的主题
	var popup_theme = Theme.new()
	var vscroll_style = StyleBoxFlat.new()
	# 调整滚动条的宽窄
	vscroll_style.set_border_width_all(20)
	popup_theme.set_stylebox("scroll", "VScrollBar", vscroll_style)
	get_popup().theme = popup_theme


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_item_selected(index: int) -> void:
	emit_signal("card_select",self,index)