extends Node2D

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
	$"../pages".text = tr("ui.book.page") % [page, tot_page]
	for i in range((page-1)*18,min(display_list.size(),page*18)):
		# 生成卡牌实例
		var new_card = load_card.generate_single_card(display_list[i])
		# 确定卡牌位置
		new_card.position = Vector2(((i%18)%6)*240 + 480,(i%18)/6*310 + 230)
		
		# 显示卡牌(加入card_manager)
		$"../card_manager".add_child(new_card)
		# 进入玩家战斗队列
		display_card_list.append(new_card)

func update_list():
	display_list = []
	for id in CardDB.all():
		var data := CardDB.card(id)
		if (is_filter_character == false) and (data.type == "character"):
				continue
		if (is_filter_equipment == false) and (data.type == "equipment"):
				continue
		if (filter_star != 0) and (data.star != filter_star):
				continue
		if (filter_string != "") and not matches_filter_string(data):
				continue
		display_list.append(id)

# 关键词匹配显示的名字：卡名、种族、时机、技能名
func matches_filter_string(data: Dictionary) -> bool:
	var names := [tr("card." + data.id)]
	for race in data.get("races", []):
		names.append(tr("race." + race))
	for field in ["timing", "weapon_timing"]:
		if data.has(field):
			names.append(tr("timing." + data[field]))
	for field in ["skills", "weapon_skills", "special_skills"]:
		for skill in data.get(field, {}):
			names.append(tr("keyword." + skill))
	return names.any(func(n): return filter_string in n)

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
