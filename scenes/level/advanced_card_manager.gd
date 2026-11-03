extends Node2D

# 场景转换相关
var level_id

var card_being_dragged
# 被拖动的卡原来所在的卡槽（从手牌拖出时为 null）
var drag_origin_slot
var is_hovering_on_card

var screen_size
var player_hand_reference

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

	# 载入关卡
	level_id = $"..".level_id
	var level := LevelDB.level(level_id)
	$"../level_name".text = tr("level." + level_id)

	# 初始化玩家手牌
	init_player_card_list = level.hand
	for id in init_player_card_list:
		add_card_to_hand_by_id(id)

	# 载入对手卡组
	for i in range(level.enemy.size()):
		var new_card = load_card.generate(level.enemy[i][0], level.enemy[i][1])
		new_card.position = Vector2(240 * (i+1), 230)
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
	# 正在拖动的卡保持在最上层：鼠标移动太快时会先移出卡牌区域触发"离开"，不能因此恢复它的图层
	if card == card_being_dragged:
		return
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

	# 如果卡牌在槽中，记下来源卡槽（互换时要把对方移过去），并清空卡槽
	drag_origin_slot = card.card_slot_card_is_in
	if card.card_slot_card_is_in != null:
		card.card_slot_card_is_in.card_in_slot = null
		card.card_slot_card_is_in = null

func finish_drag():
	drop_card(raycast_check_for_card_slot())

# 把正在拖动的卡放到 slot 上（null 表示格子以外）。
# 规则见 docs/design/game-design.md 第 7 节「布阵交互」
func drop_card(slot):
	var card = card_being_dragged
	var origin_slot = drag_origin_slot
	card_being_dragged = null
	drag_origin_slot = null
	# 重置鼠标悬停状态，结束拖拽后离开再放回才放大显示
	is_hovering_on_card = false
	card.scale = Vector2(DEFAULT_CARD_SCALE,DEFAULT_CARD_SCALE)

	# 放到格子以外（含敌方格子）：回手，已合并的卡拆开
	if slot == null or slot.interactable == false:
		drop_outside(card)
	# 空格：装备不能单独上场，退回手牌；角色或已合并的卡放入
	elif slot.card_in_slot == null:
		if card.card_id == "":
			player_hand_reference.add_card_to_hand(card,DEFAULT_CARD_MOVE_SPEED)
		else:
			place_card(card, slot)
	else:
		drop_on_card(card, slot, origin_slot)

# 放到有卡的格子上
func drop_on_card(card, slot, origin_slot):
	var target = slot.card_in_slot
	# 一张角色、一张装备，都没合并过：合并
	if can_merge(card, target):
		load_card.union_two_cards(target, card)
		target.z_index = 0
		target.old_z_index = 0
		player_hand_reference.remove_card_from_hand(card)
		card.queue_free()
	# 装备拖到已合并的卡上：换装备，旧装备回手
	elif card.card_id == "" and target.card_id != "" and target.equip_id != "":
		var old_equip_id = target.equip_id
		load_card.show_cards(target, target.card_id, card.equip_id)
		target.get_node("equip_image").adjust_size()
		player_hand_reference.remove_card_from_hand(card)
		card.queue_free()
		var old_equip = load_card.generate("", old_equip_id)
		old_equip.position = target.position
		self.add_child(old_equip)
		player_hand_reference.add_card_to_hand(old_equip,DEFAULT_CARD_MOVE_SPEED)
	# 场上的卡拖到场上另一张卡：互换位置，被换的卡移到原位置
	elif origin_slot != null:
		place_card(card, slot)
		target.card_slot_card_is_in = origin_slot
		origin_slot.card_in_slot = target
		animate_card_to_position(target, origin_slot.position, DEFAULT_CARD_MOVE_SPEED * 2)
	# 手牌拖到场上的卡：手牌占位，原来那张整张回手，不拆开
	else:
		target.card_slot_card_is_in = null
		slot.card_in_slot = null
		place_card(card, slot)
		player_hand_reference.add_card_to_hand(target,DEFAULT_CARD_MOVE_SPEED)

# 一张是只有角色的卡，另一张是只有装备的卡
func can_merge(card_1, card_2):
	var is_char = func(c): return c.card_id != "" and c.equip_id == ""
	var is_equip = func(c): return c.card_id == "" and c.equip_id != ""
	return (is_char.call(card_1) and is_equip.call(card_2)) or (is_equip.call(card_1) and is_char.call(card_2))

# 把卡牌放进格子
func place_card(card, slot):
	player_hand_reference.remove_card_from_hand(card)
	card.z_index = 0
	card.old_z_index = 0
	card.card_slot_card_is_in = slot
	card.position = slot.position
	slot.card_in_slot = card

# 放到格子以外：回手，已合并的卡拆开
func drop_outside(card):
	if card.card_id == "" or card.equip_id == "":
		player_hand_reference.add_card_to_hand(card,DEFAULT_CARD_MOVE_SPEED)
		return
	var new_chara_card = load_card.generate(card.card_id)
	var new_equip_card = load_card.generate("", card.equip_id)
	new_chara_card.position = card.position
	new_equip_card.position = card.position
	# 从手牌移除该牌(若在手牌中)，删除该牌
	player_hand_reference.remove_card_from_hand(card)
	card.queue_free()
	player_hand_reference.add_card_to_hand(new_chara_card,DEFAULT_CARD_MOVE_SPEED)
	player_hand_reference.add_card_to_hand(new_equip_card,DEFAULT_CARD_MOVE_SPEED)
	self.add_child(new_chara_card)
	self.add_child(new_equip_card)

func add_card_to_hand_by_id(id):
	var new_card = load_card.generate_single_card(id)
	player_hand_reference.add_card_to_hand(new_card,CARD_DRAW_SPEED)
	self.add_child(new_card)


func animate_card_to_position(card, new_position,speed):
	# 实现卡牌移动到指定位置的动画效果
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)
