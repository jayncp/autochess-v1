extends Node2D
## 手牌：占满底部一整行，居中排开；放不下时依次叠压，右边的压住左边的。张数不设上限。
## 位置和卡牌缩放由布阵界面按布局给出（layout）。

const GAP := 18.0
const DEFAULT_CARD_MOVE_SPEED = 0.1

var player_hand = []
## 手牌的缩放（完整卡）
var card_scale := 0.6
var _top := 800.0
var _left := 40.0
var _right := 1880.0


## 手牌一行的位置：顶边 top，左右范围 [left, right]，卡牌缩放 hand_scale
func layout(top: float, left: float, right: float, hand_scale: float) -> void:
	_top = top
	_left = left
	_right = right
	card_scale = hand_scale
	for card in player_hand:
		card.set_look(card_scale, false)
	update_hand_positions(0)


func add_card_to_hand(card, speed):
	card.set_look(card_scale, false)
	card.face.shadow = true
	if card not in player_hand:
		player_hand.append(card)
		update_hand_positions(speed)
	else:
		card.move_to(card.starting_position, DEFAULT_CARD_MOVE_SPEED)


## 整理手牌：按图鉴的默认顺序（卡牌序号，角色在前、装备在后）；合并过的卡按角色算
func sort_hand() -> void:
	player_hand.sort_custom(func(a, b): return _number(a) < _number(b))
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED * 2)


func _number(card) -> int:
	return CardDB.card(card.card_id if card.card_id else card.equip_id).no


func remove_card_from_hand(card):
	if card in player_hand:
		player_hand.erase(card)
		card.face.shadow = false
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED)


## 依次排开：间距是卡宽加 GAP，放不下时缩小间距（叠压），整体居中
func update_hand_positions(speed):
	var count := player_hand.size()
	if count == 0:
		return
	var size: Vector2 = player_hand[0].face.get_size()
	var step := size.x + GAP
	if count > 1:
		step = minf(step, (_right - _left - size.x) / (count - 1))
	var total := step * (count - 1) + size.x
	var x0 := _left + (_right - _left - total) / 2 + size.x / 2
	for i in count:
		var card = player_hand[i]
		var target := Vector2(x0 + i * step, _top + size.y / 2)
		card.z_index = i
		card.old_z_index = i
		card.starting_position = target
		card.move_to(target, speed)
