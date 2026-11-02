extends Node2D

const HAND_COUNT = 5
const CARD_WIDTH = 200
const HAND_Y_POSITION = 850
const DEFAULT_CARD_MOVE_SPEED = 0.1

var player_hand = []
var center_screen_x

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2
	# 强制适应1920*1080 比例
	center_screen_x = 960


func add_card_to_hand(card,speed):
	# 向玩家手牌添加卡牌
	if card not in player_hand:
		card.z_index = 0
		player_hand.insert(0,card)
		update_hand_positions(speed)
	else :
		animate_card_to_position(card, card.starting_position,DEFAULT_CARD_MOVE_SPEED)
		
func update_hand_positions(speed):
	# 整理玩家手牌位置
	for i in range(player_hand.size()):
		var new_position = Vector2(calculate_card_position(i),HAND_Y_POSITION)
		var card = player_hand[i]
		card.z_index = player_hand.size()-i-1
		card.old_z_index = player_hand.size()-i-1
		card.starting_position = new_position
		animate_card_to_position(card, new_position,speed)
		

func calculate_card_position(index):
	# 计算给定序号的卡牌的位置，从居中位置向两侧延伸
	var x_offset
	var total_width = (player_hand.size() - 1) * CARD_WIDTH
	if total_width < 1600:
		x_offset = center_screen_x - index * CARD_WIDTH + total_width / 2.0
	else:
		var card_width_adjust = CARD_WIDTH * 1600.0 / total_width
		total_width = (player_hand.size() - 1) * card_width_adjust
		x_offset = center_screen_x - index * card_width_adjust + total_width / 2.0
	return x_offset
	
func animate_card_to_position(card, new_position,speed):
	# 实现卡牌移动到指定位置的动画效果
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)

func remove_card_from_hand(card):
	# 删除手牌中指定卡牌
	if card in player_hand:
		player_hand.erase(card)
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
