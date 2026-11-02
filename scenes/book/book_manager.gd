extends Node2D

var card_database_reference

var this_page = 1
var display_list = []
var display_card_list = []

var is_filter_character = true
var is_filter_equipment = true
var filter_string = ""
var filter_star = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 默认开启角色和装备筛选
	$"../filter_character_button".button_pressed = true
	$"../filter_equipment_button".button_pressed = true

	card_database_reference = preload("res://scripts/database/card_database.gd")
	update_list()
	update_display(1)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if this_page <= 1:
		$"../last_page_button".visible = false
		$"../last_page_button".disabled = true
	else:
		$"../last_page_button".visible = true
		$"../last_page_button".disabled = false
	if this_page >= display_list.size() / 18 + 1:
		$"../next_page_button".visible = false
		$"../next_page_button".disabled = true
	else:
		$"../next_page_button".visible = true
		$"../next_page_button".disabled = false

func update_display(page: int):
	while display_card_list.size() > 0:
		var first_card = display_card_list[0]
		display_card_list.erase(first_card)
		first_card.queue_free()
	
	var tot_page = display_list.size() / 18 + 1
	$"../pages".text = "第"+str(page) + "页/共" + str(tot_page) + "页"
	for i in range((page-1)*18,min(display_list.size(),page*18)):
		var card_name = display_list[i]

		# 生成卡牌实例
		var new_card = load_card.generate_single_card(card_name)
		# 确定卡牌位置
		new_card.position = Vector2(((i%18)%6)*240 + 480,(i%18)/6*310 + 230)
		
		# 显示卡牌(加入card_manager)
		$"../card_manager".add_child(new_card)
		# 进入玩家战斗队列
		display_card_list.append(new_card)

func update_list():
	display_list = []
	for i in card_database_reference.CARDS.keys():
		if (is_filter_character == false) and (card_database_reference.CARDS[i][1] == "角色"):
				continue
		if (is_filter_equipment == false) and (card_database_reference.CARDS[i][1] == "装备"):
				continue
		if (filter_star != 0) and (card_database_reference.CARDS[i][2] != filter_star):
				continue

		if filter_string != "":
			var is_exist_str = false
			var card_data_list = card_database_reference.CARDS[i]
			if filter_string in i:
				is_exist_str = true
			if card_data_list[3]!=null:
				for j in card_data_list[3]:
					if filter_string in j:
						is_exist_str = true
			
			if card_data_list[6]!=null:
				if filter_string in card_data_list[6]:
					is_exist_str = true

			if card_data_list[7]!=null:		
				for j in card_data_list[7]:
					if filter_string in j.keys()[0]:
						is_exist_str = true

			if card_data_list[8]!=null:
				if filter_string in card_data_list[8]:
					is_exist_str = true

			if card_data_list[9]!=null:
				for j in card_data_list[9]:
					if filter_string in j.keys()[0]:
						is_exist_str = true

			if card_data_list[10]!=null:
				for j in card_data_list[10]:
					if filter_string in j.keys()[0]:
						is_exist_str = true

			if is_exist_str == false:
				continue
		display_list.append(i)

func _on_last_page_button_pressed() -> void:
	this_page -= 1
	update_display(this_page)

func _on_next_page_button_pressed() -> void:
	this_page += 1
	update_display(this_page)

func _on_filter_character_button_pressed() -> void:
	is_filter_character = not is_filter_character
	update_list()
	this_page = 1
	update_display(1)

func _on_filter_equipment_button_pressed() -> void:
	is_filter_equipment = not is_filter_equipment
	update_list()
	this_page = 1
	update_display(1)

func _on_filter_string_button_pressed() -> void:
	if $"../filter_string_input".text:
		filter_string = $"../filter_string_input".text
	else:
		filter_string = ""

	update_list()
	this_page = 1
	update_display(1)

func _on_filter_star_button_item_selected(index:int) -> void:
	filter_star = index
	update_list()
	this_page = 1
	update_display(1)
