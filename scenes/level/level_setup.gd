extends Control
## 闯关布阵（构筑阶段）：上面一排是对方，中间一排是我方的卡位，底部一整行是手牌；
## 右列是关卡名（和对方一排对齐）、上场计数、"开始战斗"、紧凑模式开关、整理手牌（和我方一排对齐）。
## 布局按画布大小算，多出来的高度给手牌；紧凑模式下双方队列换成紧凑卡，腾出的高度也给手牌。拖放规则在 advanced_card_manager。

signal back_to_level_select
signal start_battle

## 对方一排的缩放（非紧凑模式）
const ENEMY_SCALE := 0.6
const MARGIN := 14.0
const GAP_ENEMY_ALLY := 30.0
const GAP_ALLY_HAND := 24.0
## 手牌最大缩放；紧凑模式下队列的缩放要保证手牌至少能按 HAND_MIN 显示
const HAND_MAX := 1.0
const HAND_MIN := 0.87
## 返回按钮下面才放对方的旗子
const BACK_BOTTOM := 92.0

var level_id
## 卡位上限（关卡数据的 slots，默认 7）
var slot_limit := BoardLayout.SLOTS

@onready var _cards = $advanced_card_manager
@onready var _hand = $player_hand
var _enemy_tag := SideTag.new(tr("ui.board.enemy"), true)
var _ally_tag := SideTag.new(tr("ui.board.ally"), false)
var _preview := CardPreview.new()


func _ready() -> void:
	var level := LevelDB.level(level_id)
	slot_limit = level.get("slots", BoardLayout.SLOTS)
	var index: int = LevelDB.all().keys().find(level_id)
	%Name.text = tr("level." + level_id)
	%Subtitle.text = tr("ui.level_setup.subtitle") % (index + 1)
	%Limit.text = "/ %d" % slot_limit
	for i in BoardLayout.SLOTS:
		var slot: CardSlot = preload("res://scenes/components/card_slot.tscn").instantiate()
		slot.number = i + 1
		slot.locked = i >= slot_limit
		$player_card_slots.add_child(slot)
	add_child(_enemy_tag)
	add_child(_ally_tag)
	add_child(_preview)
	_cards.preview = _preview
	_cards.lineup_changed.connect(_update_count)
	%Compact.button_pressed = global_var.compact_mode
	%Compact.toggled.connect(_on_compact_toggled)
	resized.connect(_layout)
	_layout()
	_update_count()


func _on_back_button_pressed() -> void:
	back_to_level_select.emit()


func _on_compact_toggled(on: bool) -> void:
	global_var.compact_mode = on
	_layout()


func _on_start_battle_pressed() -> void:
	var lineup = generate_battle_list()
	# 至少上场一个角色（装备不能单独上场，所以场上的卡都有角色）
	if lineup[0].is_empty():
		Dialog.notice(self, tr("ui.dialog.hint"), tr("ui.level_setup.need_character"))
		return
	var enemy: Array = LevelDB.level(level_id).enemy
	global_var.battle_card_list_1 = enemy.map(func(u): return u[0])
	global_var.battle_card_list_2 = lineup[0]
	global_var.battle_equip_list_1 = enemy.map(func(u): return u[1])
	global_var.battle_equip_list_2 = lineup[1]
	start_battle.emit()


# 检索我方队伍：按卡槽从左到右
func generate_battle_list():
	var battle_card_list = []
	var battle_equip_list = []
	for slot in $"player_card_slots".get_children():
		var card = slot.card_in_slot
		if card == null:
			continue
		battle_card_list.append(card.card_id)
		battle_equip_list.append(card.equip_id)
	return [battle_card_list,battle_equip_list]


func _update_count() -> void:
	%Deployed.text = str(generate_battle_list()[0].size())


## 对方、我方、手牌三行上下居中排开；我方一排的缩放受宽度和高度限制；
## 多出来的高度给手牌（最大 1），再给对方一排（最大和我方一样大）。紧凑模式下队列是紧凑卡，手牌更大
func _layout() -> void:
	var compact: bool = global_var.compact_mode
	var full := BoardLayout.card_height(1, false)
	var short := BoardLayout.card_height(1, true)
	var fit: float
	if compact:
		fit = (size.y - 2 * MARGIN - GAP_ENEMY_ALLY - GAP_ALLY_HAND - full * HAND_MIN) / (2 * short)
	else:
		fit = (size.y - 2 * MARGIN - full * ENEMY_SCALE - GAP_ENEMY_ALLY - GAP_ALLY_HAND) / 2 / full
	var columns := BoardLayout.columns(BoardLayout.TAG_COLUMN, size.x - BoardLayout.RIGHT_COLUMN, fit)
	var card_scale: float = columns.scale
	var row_height := BoardLayout.card_height(card_scale, compact)
	var enemy_scale := card_scale if compact else minf(ENEMY_SCALE, card_scale)
	var enemy_height := BoardLayout.card_height(enemy_scale, compact)
	# 多出来的高度先给手牌（最大 HAND_MAX），再给对方一排（最大和我方一样大），剩下的上下平分
	var room := size.y - 2 * MARGIN - enemy_height - GAP_ENEMY_ALLY - row_height - GAP_ALLY_HAND
	var hand_scale := minf(HAND_MAX, room / full)
	if not compact:
		enemy_scale = minf(card_scale, enemy_scale + (room - full * hand_scale) / full)
		enemy_height = BoardLayout.card_height(enemy_scale, compact)
	var used := enemy_height + GAP_ENEMY_ALLY + row_height + GAP_ALLY_HAND + full * hand_scale
	var enemy_y := (size.y - used) / 2
	var ally_y := enemy_y + enemy_height + GAP_ENEMY_ALLY
	var hand_y := ally_y + row_height + GAP_ALLY_HAND

	var enemy: Array = _cards.enemy_cards
	for i in enemy.size():
		enemy[i].set_look(enemy_scale, compact)
		enemy[i].position = Vector2(columns.center.call(i), enemy_y + enemy_height / 2)
	_cards.lineup_look = [card_scale, compact]
	_cards.lineup_band = Vector2(ally_y - GAP_ENEMY_ALLY, ally_y + row_height + GAP_ALLY_HAND / 2)
	var slots := $player_card_slots.get_children()
	for i in slots.size():
		var slot: CardSlot = slots[i]
		slot.size = Vector2(columns.width, row_height)
		slot.position = Vector2(columns.center.call(i), ally_y + row_height / 2)
		if slot.card_in_slot:
			slot.card_in_slot.set_look(card_scale, compact)
			slot.card_in_slot.move_to(slot.position, 0)
	_hand.layout(hand_y, 40, size.x - 40, hand_scale)

	var tag_x := (BoardLayout.TAG_COLUMN - SideTag.WIDTH) / 2 + 8
	var enemy_top := maxf(enemy_y, BACK_BOTTOM)
	_enemy_tag.position = Vector2(tag_x, enemy_top + (enemy_y + enemy_height - enemy_top - _enemy_tag.size.y) / 2)
	_ally_tag.position = Vector2(tag_x, ally_y + (row_height - _ally_tag.size.y) / 2)
	var front: Control = $FrontMark
	front.size = front.get_combined_minimum_size()
	front.position = Vector2(columns.center.call(0) - front.size.x / 2, enemy_y + enemy_height + 2)
	var right_center: float = (columns.right + size.x) / 2
	_center(%Name.get_parent(), Vector2(right_center, enemy_y + enemy_height / 2))
	_center($RightColumn, Vector2(right_center, ally_y + row_height / 2))


func _center(control: Control, center: Vector2) -> void:
	control.size = control.get_combined_minimum_size()
	control.position = center - control.size / 2
