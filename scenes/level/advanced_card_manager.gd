extends BoardDrag
## 闯关布阵的拖放规则（docs/design/game-design.md 第 7 节「布阵交互」）。拖动的公共部分见 BoardDrag。
## 卡牌的样子由布阵界面给出：队列（lineup_look）、手牌（由 player_hand 设置）；拖到队列上方时变成队列的样式。

const DEFAULT_CARD_MOVE_SPEED = 0.1
const CARD_DRAW_SPEED = 0.2

var level_id
var player_hand_reference
## 敌方的卡（不能拖动），布阵界面按布局摆放
var enemy_cards := []
## 队列里卡牌的样子：[缩放, 是否紧凑卡]；队列所在的竖直范围，拖到这里时卡牌变成队列的样式
var lineup_look := [0.6, false]
var lineup_band := Vector2(0, 0)


func _ready() -> void:
	player_hand_reference = $"../player_hand"
	level_id = $"..".level_id
	var level := LevelDB.level(level_id)
	for id in level.hand:
		add_card_to_hand_by_id(id)
	for unit in level.enemy:
		var card = load_card.generate(unit[0], unit[1])
		card.is_enemy_card = true
		add_child(card)
		enemy_cards.append(card)


func drag_look(at: Vector2) -> Array:
	if at.y >= lineup_band.x and at.y <= lineup_band.y:
		return lineup_look
	return [player_hand_reference.card_scale, false]


func return_card(card) -> void:
	if card.card_slot_card_is_in != null:
		place_card(card, card.card_slot_card_is_in)
	else:
		player_hand_reference.add_card_to_hand(card, DEFAULT_CARD_MOVE_SPEED)


# 把正在拖动的卡放到 slot 上（null 表示格子以外）。
# 规则见 docs/design/game-design.md 第 7 节「布阵交互」
func drop_card(slot) -> void:
	var card = card_being_dragged
	var origin_slot = drag_origin_slot
	end_drag()

	# 放到格子以外（含敌方一排、没解锁的卡位）：回手，已合并的卡拆开
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
	lineup_changed.emit()

# 放到有卡的格子上
func drop_on_card(card, slot, origin_slot):
	var target = slot.card_in_slot
	# 一张角色、一张装备，都没合并过：合并
	if can_merge(card, target):
		load_card.union_two_cards(target, card)
		player_hand_reference.remove_card_from_hand(card)
		card.queue_free()
	# 装备拖到已合并的卡上：换装备，旧装备回手
	elif card.card_id == "" and target.card_id != "" and target.equip_id != "":
		var old_equip_id = target.equip_id
		load_card.show_cards(target, target.card_id, card.equip_id)
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
	card.set_look(lineup_look[0], lineup_look[1])
	card.move_to(slot.position, 0)
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
