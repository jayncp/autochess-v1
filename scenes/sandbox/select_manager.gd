extends Node2D

const CARD_SELECT_BUTTON_PATH = "res://scenes/sandbox/card_select_button.tscn"
const EQUIP_SELECT_BUTTON_PATH = "res://scenes/sandbox/equip_select_button.tscn"
signal start_battle

var init_card_list = {1:["","","","","","",""],
					  2:["","","","","","",""]}
var init_equip_list = {1:["","","","","","",""],
					  2:["","","","","","",""]}
var card_display_list = []
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# player_1 角色
	for i in range(0,7):
		var card_select_button = preload(CARD_SELECT_BUTTON_PATH).instantiate()
		card_select_button.position.x = 137 + i *240
		card_select_button.position.y = 380
		self.add_child(card_select_button)
	# player_2 角色
	for i in range(0,7):
		var card_select_button = preload(CARD_SELECT_BUTTON_PATH).instantiate()
		card_select_button.position.x = 137 + i *240
		card_select_button.position.y = 578
		self.add_child(card_select_button)

	# player_1 装备
	for i in range(0,7):
		var card_select_button = preload(EQUIP_SELECT_BUTTON_PATH).instantiate()
		card_select_button.position.x = 137 + i *240
		card_select_button.position.y = 380 + 51 + 20
		self.add_child(card_select_button)
	# player_2 装备
	for i in range(0,7):
		var card_select_button = preload(EQUIP_SELECT_BUTTON_PATH).instantiate()
		card_select_button.position.x = 137 + i *240
		card_select_button.position.y = 578 + 51 + 20
		self.add_child(card_select_button)


# Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta: float) -> void:
# 	pass


func connect_card_select_signal(card_select_button):
	card_select_button.card_select.connect(update_init_card_list)
func connect_equip_select_signal(card_select_button):
	card_select_button.equip_select.connect(update_init_equip_list)

func update_init_card_list(button, index):
	var card_id = button.get_item_metadata(index)
	var button_owner
	var button_index
	if button.position.y < 540:
		button_owner = 1
	else:
		button_owner = 2
	button_index = floor(button.position.x/240)
	init_card_list[button_owner][button_index] = card_id if card_id else ""
	update_display(button_owner,button_index,init_card_list[button_owner][button_index],init_equip_list[button_owner][button_index])

func update_init_equip_list(button, index):
	var equip_id = button.get_item_metadata(index)
	var button_owner
	var button_index
	if button.position.y < 540:
		button_owner = 1
	else:
		button_owner = 2
	button_index = floor(button.position.x/240)
	init_equip_list[button_owner][button_index] = equip_id if equip_id else ""
	update_display(button_owner,button_index,init_card_list[button_owner][button_index],init_equip_list[button_owner][button_index])

func update_display(button_owner,button_index,card_id,equip_id):
	var pos_x = 240 * (button_index + 1)
	var pos_y = 230 if button_owner == 1 else 850
	for i in card_display_list:
		if (i.position.x == pos_x) and (i.position.y == pos_y):
			var card = i
			card_display_list.erase(i)
			card.queue_free()

	if (card_id != "") or (equip_id != ""):
		var new_card = load_card.generate(card_id, equip_id)
		new_card.position = Vector2(pos_x,pos_y)
		
		# 显示卡牌(加入card_manager)
		$"../card_manager".add_child(new_card)
		# 进入玩家战斗队列
		card_display_list.append(new_card)

func generate_battle_list():
	var battle_card_list = {1:[],2:[]}
	var battle_equip_list = {1:[],2:[]}
	for i in range(1,3):
		for j in range(0,7):
			if (init_card_list[i][j]=="") and (init_equip_list[i][j]!=""):
				return null
			if (init_card_list[i][j]=="") and (init_equip_list[i][j]==""):
				continue
			battle_card_list[i].append(init_card_list[i][j])
			battle_equip_list[i].append(init_equip_list[i][j])
	return [battle_card_list,battle_equip_list]

func _on_start_battle_pressed() -> void:
	if generate_battle_list()!= null:
		var list_card
		var list_equip
		list_card = generate_battle_list()[0]
		list_equip = generate_battle_list()[1]
		global_var.battle_card_list_1 = list_card[1]
		global_var.battle_card_list_2 = list_card[2]
		global_var.battle_equip_list_1 = list_equip[1]
		global_var.battle_equip_list_2 = list_equip[2]
		emit_signal("start_battle")
	else:
		$"../output_text".text = "阵容有误，请重新输入！"
