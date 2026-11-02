extends OptionButton

signal equip_select
var card_database_reference
var card_list = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_parent().connect_equip_select_signal(self)
	get_popup().add_theme_font_size_override("font_size",25)
	get_popup().max_size = Vector2(1000,300)
	card_database_reference = preload("res://scripts/database/card_database.gd")
	for i in card_database_reference.CARDS.keys():
		if card_database_reference.CARDS[i][1] == "装备":
			card_list.append(i)
	for i in card_list:
		get_popup().add_item(i)
	
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
	emit_signal("equip_select",self,index)
