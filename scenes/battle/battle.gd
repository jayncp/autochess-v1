extends Control
## 战斗界面：上面一排是对方，下面一排是我方，卡牌占满宽度；中间一带左边是交战位标记，
## 中间是状态（开战前"开始战斗"，战斗中阶段名和计数，结束后胜负和"返回"），右边是速度和跳过。
## 布局按画布大小算；播放逻辑在 battle_manager，这里只管位置和状态的显示。

## 卡牌最大缩放；两排卡离上下边的距离
const MAX_SCALE := 0.93
const EDGE := 22.0
const RIGHT_MARGIN := 30.0
const TIMING_COLORS := {"pre_battle": Color("33d0e2"), "on_enter": Color("66cc4c"), "on_engage": Color("f0503f")}

var card_scale := 0.6
## 两排卡之间的空隙（像素），卡牌出列、对撞的距离按它算
var row_gap := 300.0

var _columns: Dictionary
var _rows := {1: 0.0, 2: 0.0}  # 两排卡的中心 y
var _enemy_tag := SideTag.new(tr("ui.board.enemy"), true)
var _ally_tag := SideTag.new(tr("ui.board.ally"), false)

@onready var _manager = $battle_manager


func _ready() -> void:
	add_child(_enemy_tag)
	add_child(_ally_tag)
	move_child(_enemy_tag, $cards.get_index())
	move_child(_ally_tag, $cards.get_index())
	resized.connect(_layout)
	_layout()
	show_ready()


## 第 side 方第 n 个位置的中心
func slot_position(side: int, n: int) -> Vector2:
	return Vector2(_columns.center.call(n), _rows[side])


func _layout() -> void:
	_columns = BoardLayout.columns(BoardLayout.TAG_COLUMN, size.x - RIGHT_MARGIN, MAX_SCALE)
	card_scale = _columns.scale
	var height := BoardLayout.card_height(card_scale, false)
	_rows = {1: EDGE + height / 2, 2: size.y - EDGE - height / 2}
	row_gap = size.y - 2 * EDGE - 2 * height
	var middle := size.y / 2
	var tag_x := (BoardLayout.TAG_COLUMN - SideTag.WIDTH) / 2 + 8
	_enemy_tag.position = Vector2(tag_x, _rows[1] - _enemy_tag.size.y / 2)
	_ally_tag.position = Vector2(tag_x, _rows[2] - _ally_tag.size.y / 2)
	_center($ClashMark, Vector2(_columns.center.call(0), middle))
	# 状态区：一块居中容器，内容显隐变化时自己保持居中
	var status_width := 1000.0
	$Status.position = Vector2((_columns.center.call(0) + _columns.right) / 2 - status_width / 2, middle - row_gap / 2)
	$Status.size = Vector2(status_width, row_gap)
	var controls: Control = $Controls
	controls.size = controls.get_combined_minimum_size()
	controls.position = Vector2(_columns.right - controls.size.x, middle - controls.size.y / 2)
	_manager.relayout()


func _center(control: Control, center: Vector2) -> void:
	control.size = control.get_combined_minimum_size()
	control.position = center - control.size / 2


# ---------- 状态 ----------

## 开战前："开始战斗"
func show_ready() -> void:
	_show_only([%StartButton])
	_set_controls(true, false)


## 战斗中：阶段名（时机图标加名称）；下面一行是计数，空字符串表示没有
func show_phase(timing: String, sub: String) -> void:
	var color: Color = TIMING_COLORS[timing]
	%PhaseIcon.texture = CardFace.cached_texture("res://assets/ui/icons/%s.png" % timing)
	%PhaseIcon.modulate = color
	%PhaseLabel.text = tr("timing." + timing)
	%PhaseLabel.add_theme_color_override("font_shadow_color", Color(color, 0.6))
	show_note(sub)
	_set_controls(true, true)


## 只改下面一行（比如"双方僵持"）
func show_note(sub: String) -> void:
	%Sub.text = sub
	_show_only([%Phase, %Sub] if sub else [%Phase])


## 结束：胜利、失败或平局（我方是下面一排），原因，"返回"
func show_result(winner: int, sub: String) -> void:
	%Result.text = tr({1: "ui.battle.lose", 2: "ui.battle.win", 3: "ui.battle.draw"}[winner])
	%Sub.text = sub
	_show_only([%Result, %ResultRule, %Sub, %BackButton])
	_set_controls(false, false)


func _show_only(nodes: Array) -> void:
	for child in %StatusBox.get_children():
		child.visible = child in nodes


func _set_controls(speed: bool, skip: bool) -> void:
	%SpeedButton.disabled = not speed
	%SkipButton.disabled = not skip


func set_speed_text(speed: float) -> void:
	%SpeedButton.text = tr("ui.battle.speed") % str(int(speed))
