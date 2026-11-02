extends Node2D

# 场景转换相关
var level_name

var card_being_dragged
var is_hovering_on_card

var screen_size
var player_hand_reference
var level_database_reference

# 卡牌尺寸变化常数
const DEFAULT_CARD_SCALE = 1
const CARD_BIGGER_SCALE = 1.7
# 碰撞掩码
const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2

const DEFAULT_CARD_MOVE_SPEED = 0.1
const CARD_DRAW_SPEED = 0.2

var init_player_card_list

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../player_hand"
	$"../input_manager".connect("left_mouse_button_released",on_left_click_released)
	level_database_reference = preload("res://scripts/database/level_database.gd")
	var level_info = level_database_reference.LEVEL

	# 载入关卡
	level_name = $"..".level_name
	$"../level_name".text = level_name

	# 初始化玩家手牌
	init_player_card_list = level_info[level_name][2]+level_info[level_name][3]
	for c_name in init_player_card_list:
		add_card_to_hand_by_name(c_name)

	# 载入对手卡组
	for i in range(level_info[level_name][0].size()):
		var new_card = load_card.generate_single_card(level_info[level_name][0][i])
		new_card.position = Vector2(240 * (i+1), 230)
		if level_info[level_name][1][i] != "":
			var new_equip = load_card.generate_single_card(level_info[level_name][1][i])
			load_card.union_two_cards(new_card,new_equip)
		
		new_card.z_index = -1
		new_card.old_z_index = -1

		new_card.is_enemy_card = true
		add_child(new_card)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# 实时渲染被拖动卡牌位置
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		card_being_dragged.position = Vector2(clamp(mouse_pos.x,0,screen_size.x),clamp(mouse_pos.y,0,screen_size.y))

func on_left_click_released():
	# 鼠标指针被释放时

	# 如果有卡牌被拖动，结束拖动
	if card_being_dragged:
		finish_drag()

# 接收悬停信号
func connect_card_signals(card):
	card.connect("hovered",on_hovered_over_card)
	card.connect("hovered_off",on_hovered_off_card)

func on_hovered_over_card(card):
	if card.is_playing_animation:
		return
	# 鼠标指针选停在卡牌上时对卡牌进行高亮显示
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card,true)

# 放大突出显示卡牌		
func highlight_card(card, hovered):
	if hovered:
		# 有卡牌被拖拽时不放大
		if card_being_dragged:
			return
		card.scale = Vector2(CARD_BIGGER_SCALE,CARD_BIGGER_SCALE)
		card.z_index = 1000
	else:
		card.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)
		card.z_index = card.old_z_index

func on_hovered_off_card(card):
	# 鼠标指针离开卡牌时取消高亮显示
	if card.is_playing_animation == false:
		highlight_card(card,false)
	var new_card_hovered = raycast_check_for_card()
	if (new_card_hovered) and (new_card_hovered.is_playing_animation == false) and (card_being_dragged == null):
		highlight_card(new_card_hovered, true)
	else:
		is_hovering_on_card = false

# 卡牌射线投射
func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size()>0:
		return get_card_with_highest_z_index(result)
	else:
		return null

# 卡槽射线投射
func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size()>0:
		return result[0].collider.get_parent()
	else:
		return null

# 获取z_index最上面卡牌
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	
	for i in range(1,cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card

func card_clicked(card):
	if card.is_enemy_card:
		# 敌人卡牌无法点击
		return
	start_drag(card)

func start_drag(card):
	# 开始拖动卡牌
	card_being_dragged = card
	card.z_index = 1001
	# 拖动时取消放大效果
	card.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)

	# 如果卡牌在槽中
	if card.card_slot_card_is_in != null:
		# 重置卡槽状态
		card.card_slot_card_is_in.get_node("Area2D/CollisionShape2D").disabled = false
		card.card_slot_card_is_in.card_in_slot = null
		card.card_slot_card_is_in = null

func move_dragged_card_to_hand():
	player_hand_reference.add_card_to_hand(card_being_dragged,DEFAULT_CARD_MOVE_SPEED)
	card_being_dragged = null
	# 重置鼠标悬停状态，结束拖拽后离开再放回才放大显示
	is_hovering_on_card = false

func finish_drag():
	# 结束拖动卡牌
	var card_slot_found = raycast_check_for_card_slot()
	# 判断检测到卡槽 and 卡槽可以交互
	if card_slot_found and card_slot_found.interactable == true :
		# 如果卡槽中没卡
		if card_slot_found.card_in_slot == null:
			# 卡牌缩放到默认大小
			card_being_dragged.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)
			# 卡牌z坐标置为底层
			card_being_dragged.z_index = 0
			card_being_dragged.old_z_index = 0
			# 重置鼠标悬停状态，结束拖拽后离开再放回才放大显示
			is_hovering_on_card = false
			# 设置卡牌所在卡槽属性
			card_being_dragged.card_slot_card_is_in = card_slot_found
			# 从手牌移除该牌(若在手牌中)
			player_hand_reference.remove_card_from_hand(card_being_dragged)
			# 卡牌位置吸附到卡槽中心
			card_being_dragged.position = card_slot_found.position
			# 设置卡槽存在卡牌属性
			card_slot_found.card_in_slot = card_being_dragged
			# # 卡槽无效化（清除碰撞）
			# card_slot_found.get_node("Area2D/CollisionShape2D").disabled = true
			
			# 清空正在拖拽卡牌变量
			card_being_dragged = null
		else:
			var card_1 = card_slot_found.card_in_slot
			var char_1 = card_1.get_node("character_name").text
			var equip_1 = card_1.get_node("equipment_name").text
			
			# 如果卡牌是对手卡牌，则退回手牌
			if card_1.is_enemy_card == true:
				move_dragged_card_to_hand()
			# 如果卡槽中有卡，且是合并过的卡，则退回手牌
			if char_1 != "" and equip_1 != "":
				move_dragged_card_to_hand()
			
			else :
				# 如果卡槽中有卡且未合并过，则检测是否可以合并
				var card_2 = card_being_dragged
				var char_2 = card_2.get_node("character_name").text
				var equip_2 = card_2.get_node("equipment_name").text
				# 如果种类相同,则退回手牌
				if char_1+char_2 == "" or equip_1+equip_2 == "":
					move_dragged_card_to_hand()
				# 如果拖拽的卡牌是合成卡牌也直接退回
				elif char_2 != "" and equip_2 != "":
					move_dragged_card_to_hand()
				else:
					# 清除缩放
					card_1.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)
					card_2.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)
					# 执行合并
					load_card.union_two_cards(card_1,card_2)

					# 卡牌z坐标置为底层
					card_1.z_index = 0
					card_1.old_z_index = 0
					
					# 从手牌移除该牌(若在手牌中)
					player_hand_reference.remove_card_from_hand(card_being_dragged)
					# 清除正在拖拽的卡牌
					card_being_dragged = null
					# 释放第二张卡牌
					card_2.queue_free()

					# 重置鼠标悬停状态，结束拖拽后离开再放回才放大显示
					is_hovering_on_card = false
	else:
		# 如果是合并的卡牌，拆分再回手
		var chara = card_being_dragged.get_node("character_name").text
		var equip = card_being_dragged.get_node("equipment_name").text
		if chara == "" or equip == "":
			move_dragged_card_to_hand()
		else :
			var new_chara_card = load_card.generate_single_card(chara)
			var new_equip_card = load_card.generate_single_card(equip)

			new_chara_card.position = card_being_dragged.position
			new_equip_card.position = card_being_dragged.position

			# 从手牌移除该牌(若在手牌中)
			player_hand_reference.remove_card_from_hand(card_being_dragged)
			# 删除该牌
			var old_card = card_being_dragged
			card_being_dragged = null
			old_card.queue_free()
			# 重置鼠标悬停状态，结束拖拽后离开再放回才放大显示
			is_hovering_on_card = false

			player_hand_reference.add_card_to_hand(new_chara_card,DEFAULT_CARD_MOVE_SPEED)
			player_hand_reference.add_card_to_hand(new_equip_card,DEFAULT_CARD_MOVE_SPEED)
			self.add_child(new_chara_card)
			self.add_child(new_equip_card)

func add_card_to_hand_by_name(card_name):
	var new_card = load_card.generate_single_card(card_name)
	player_hand_reference.add_card_to_hand(new_card,CARD_DRAW_SPEED)
	self.add_child(new_card)


func animate_card_to_position(card, new_position,speed):
	# 实现卡牌移动到指定位置的动画效果
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)
