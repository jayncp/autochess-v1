extends Node2D

var player_cards = {1:[],2:[]}
var player_equips = {1:[],2:[]}


var player_slots = {1:[],2:[]}
var player_battle_fields = {1:[],2:[]}

# 战斗阶段变量
var winner = 0
var is_pre_battle = false

signal back_to_last_scene


#==============================================
##### 初始化部分 #####
#==============================================
func _ready() -> void:
	player_cards[1] = global_var.battle_card_list_1
	player_cards[2] = global_var.battle_card_list_2
	player_equips[1] = global_var.battle_equip_list_1
	player_equips[2] = global_var.battle_equip_list_2
	# 加载双方卡牌
	pre_load()
	load_player_deck()

func pre_load():
	# 切换整合技能UI
	$"../skill_union".button_pressed = true
	show_battle_speed()
	# 加载双方卡槽
	player_slots[1].append($"../card_slots/card_slot1")
	player_slots[1].append($"../card_slots/card_slot2")
	player_slots[1].append($"../card_slots/card_slot3")
	player_slots[1].append($"../card_slots/card_slot4")
	player_slots[1].append($"../card_slots/card_slot5")
	player_slots[1].append($"../card_slots/card_slot6")
	player_slots[1].append($"../card_slots/card_slot7")

	player_slots[2].append($"../card_slots/card_slot8")
	player_slots[2].append($"../card_slots/card_slot9")
	player_slots[2].append($"../card_slots/card_slot10")
	player_slots[2].append($"../card_slots/card_slot11")
	player_slots[2].append($"../card_slots/card_slot12")
	player_slots[2].append($"../card_slots/card_slot13")
	player_slots[2].append($"../card_slots/card_slot14")

func load_player_deck():
	for i in range(1,3):
		for n in range(player_cards[i].size()):
			var card_id: String = player_cards[i][n]
			var equip_id: String = player_equips[i][n]
			var new_card = load_card.generate(card_id, equip_id)
			new_card.position = player_slots[i][n].position

			# 载入战斗属性（角色与装备合并后）
			var stats := CardDB.combine(card_id, equip_id)
			new_card.strength = stats.strength
			new_card.skill_time = stats.timings
			new_card.normal_skill = stats.normal_skills
			new_card.special_skill = stats.special_skills

			# 整合技能UI
			new_card.get_node("all_time").text = load_card.timing_name(stats.timings)
			# 显示整合UI
			new_card.get_node("card_skill_UI").modulate.a = 255
			new_card.get_node("all_time").visible = true
			new_card.get_node("all_normal_skill").visible = true
			# 实时状态只显示红色的当前战力，隐藏黑色的装备战力，避免误解
			new_card.get_node("strength_2").visible = false

			new_card.get_node("all_normal_skill").text = load_card.generate_skill_string(stats.normal_skills)
			# 显示卡牌(加入card_manager)
			$"../card_manager".add_child(new_card)
			# 进入玩家战斗队列
			player_battle_fields[i].append(new_card)


#==============================================
##### 胜利者更新部分 #####
#==============================================

# 检查胜利条件
func update_winner():
	# 检查特殊平局
	if check_special_draw() or no_death_rounds >= NO_DEATH_DRAW_ROUNDS:
		winner = 3
		return 3
	if player_battle_fields[1].size() == 0 and player_battle_fields[2].size() == 0:
		winner = 3
		return 3
	elif player_battle_fields[2].size() == 0:
		winner = 1
		return 1
	elif player_battle_fields[1].size() == 0:
		winner = 2
		return 2
	else:
		return 0

# 特殊平局二：主战斗连续 20 轮无人阵亡（振奋等持续加成会绕过特殊平局一，导致战斗无限进行）
const NO_DEATH_DRAW_ROUNDS = 20
var no_death_rounds = 0

# 特殊平局一：连续 7 次检查，双方所有角色战斗力均未改变
var not_change_cnt = 0
var strength_list_1 = []
var strength_list_2 = []
func check_special_draw():
	var new_strength_list_1 = []
	var new_strength_list_2 = []
	for i in player_battle_fields[1]:
		new_strength_list_1.append(i.strength)
	for i in player_battle_fields[2]:
		new_strength_list_2.append(i.strength)
	if strength_list_1 == new_strength_list_1 and strength_list_2 == new_strength_list_2:
		not_change_cnt += 1
		if not_change_cnt >= 7:
			return true
		else:
			return false
	else :
		strength_list_1 = new_strength_list_1
		strength_list_2 = new_strength_list_2
		not_change_cnt = 0
		return false

# 在putput文本中显示胜利者; 显示返回按钮
func show_winner():
	$"../start_battle".text = tr("ui.common.back")
	match winner:
		1:$"../output_text".text = tr("ui.battle.p1_win")
		2:$"../output_text".text = tr("ui.battle.p2_win")
		3:$"../output_text".text = tr("ui.battle.draw")


#==============================================
##### 按钮控件 #####
#==============================================

### "速度"按钮: 循环调整动画速度
var battle_speed = 1.0
var have_been_skipped = false
@onready var speed_button = $"../speed_button"

func _on_speed_button_pressed() -> void:
	cycle_battle_speed()
	show_battle_speed()

func show_battle_speed():
	speed_button.text = tr("ui.battle.speed") % str(battle_speed)

# 调整战斗速度功能
func cycle_battle_speed():
	# Cycle speed: 1.0x -> 1.5x -> 2.0x -> 3.0x -> 1.0x
	if battle_speed == 1.0:
		battle_speed = 2.0
	elif battle_speed == 2.0:
		battle_speed = 5.0
	elif battle_speed == 5.0:
		battle_speed = 20.0
	else:
		battle_speed = 1.0
	return battle_speed


### "跳过战斗"按钮: 通过关闭动画, 快速战斗
var play_animation = true
@onready var skip_button = $"../skip_button"
func _on_skip_button_pressed() -> void:
	# 战前结算标签为true(战斗已经开始), 并且战斗未结束, 并且未点击过跳过
	if is_pre_battle == true and update_winner() == 0 and have_been_skipped == false:
		# 关闭动画
		play_animation = false
		# 标记已经跳过, 防止重复点击
		have_been_skipped = true


### "开始战斗"按钮: 开始战斗; 显示战斗阶段; 返回上一层
func _on_start_battle_pressed_battle() -> void:
	if is_pre_battle == false:
		is_pre_battle = true
		$"../start_battle".text = tr("ui.battle.pre_battle_running")
		await pre_battle_part()
		$"../start_battle".text = tr("ui.battle.running")
		await main_battle_part()
		show_winner()
		# 针对跳过战斗情况，显示最终场面
		if have_been_skipped:
			await move_character()
	elif winner:
		emit_signal("back_to_last_scene")


#==============================================
##### 战斗主要流程部分 #####
#==============================================

# 结算战前技能，y = 3-x, 交换1和2
func pre_battle_part():
	while 1:
		# 胜利判定
		if update_winner():
			break

		# 查找双方第一个未执行战前技能的卡牌
		var pos_1 = null
		var pos_2 = null
		for i in player_battle_fields[1]:
			if i.finish_pre_battle == false:
				pos_1 = i
				i.finish_pre_battle = true
				break
		for i in player_battle_fields[2]:
			if i.finish_pre_battle == false:
				pos_2 = i
				i.finish_pre_battle = true
				break
		# 若全部执行完了，退出循环
		if (pos_1 == null) and (pos_2 == null):
			break
		# 卡牌预备状态显示
		if play_animation:
			if card_prepare_animation(pos_1,pos_2,"up"):
				await get_tree().create_timer(0.5/battle_speed).timeout

		# 结算"战前"技能
		var is_pos_1 = false
		var is_pos_2 = false
		var act_pose_1 = null
		var act_pose_2 = null
		if pos_1 != null:
			if "pre_battle" in pos_1.skill_time:
				is_pos_1 = true
				act_pose_1 = pos_1

		if pos_2 != null:
			if "pre_battle" in pos_2.skill_time:
				is_pos_2 = true
				act_pose_2 = pos_2

		# 卡牌进入技能释放状态
		if play_animation:
			if card_act_skill_animation(act_pose_1,act_pose_2,"up"):
				await get_tree().create_timer(0.5/battle_speed).timeout

		if is_pos_1:
			settlement_normal_skill(pos_1,1)
		if is_pos_2:
			settlement_normal_skill(pos_2,2)
		if (is_pos_1 or is_pos_2) and play_animation:
			await get_tree().create_timer(0.5/battle_speed).timeout

		# 卡牌退出技能释放状态
		if play_animation:
			if card_act_skill_animation(act_pose_1,act_pose_2,"down"):
				await get_tree().create_timer(0.75/battle_speed).timeout

		# 卡牌退出预备状态
		if play_animation:
			if card_prepare_animation(pos_1,pos_2,"down"):
				await get_tree().create_timer(0.5/battle_speed).timeout
		
		if await settlement_death():
			if play_animation:
				await get_tree().create_timer(1.5/battle_speed).timeout
				await move_character()
				await get_tree().create_timer(1.5/battle_speed).timeout

# 主战斗阶段
func main_battle_part():
	while 1:
		if update_winner():
			break
		# 如果没有入场效果则进入交战阶段
		if (await settlement_entering_part()) == false:
			await settlement_fight_part()
		if await settlement_death():
			no_death_rounds = 0
			if play_animation:
				await get_tree().create_timer(1.5/battle_speed).timeout
				await move_character()
				await get_tree().create_timer(1.5/battle_speed).timeout
		else:
			no_death_rounds += 1

# 入场技能结算
func settlement_entering_part():
	var is_entering_part = false
	var head_card_1 = null
	var head_card_2 = null
	if ("on_enter" in player_battle_fields[1][0].skill_time) and (player_battle_fields[1][0].finish_entering==false):
		head_card_1 = player_battle_fields[1][0]
		is_entering_part = true
		head_card_1.finish_entering = true
	if ("on_enter" in player_battle_fields[2][0].skill_time) and (player_battle_fields[2][0].finish_entering==false):
		head_card_2 = player_battle_fields[2][0]
		is_entering_part = true
		head_card_2.finish_entering = true
	if (head_card_1 == null) and (head_card_2 == null):
		return is_entering_part

	# 卡牌预备状态显示
	if play_animation:
		if card_prepare_animation(head_card_1,head_card_2,"up"):
			await get_tree().create_timer(0.5/battle_speed).timeout
	# 卡牌进入技能释放状态
	if play_animation:
		if card_act_skill_animation(head_card_1,head_card_2,"up"):
			await get_tree().create_timer(0.5/battle_speed).timeout

	if head_card_1 != null:
		if play_animation:
			buff_text_effect(head_card_1,load_card.timing_name("on_enter"),"blue")
	if head_card_2 != null:
		if play_animation:
			buff_text_effect(head_card_2,load_card.timing_name("on_enter"),"blue")
	if (head_card_1 != null) or (head_card_2 != null):
		if play_animation:
			await get_tree().create_timer(0.1/battle_speed).timeout

	if (head_card_1 != null):
		settlement_normal_skill(head_card_1,1)
	if (head_card_2 != null):
		settlement_normal_skill(head_card_2,2)
		
	if (head_card_1 != null) or (head_card_2 != null):
		if play_animation:
			await get_tree().create_timer(0.5/battle_speed).timeout
	# 卡牌退出技能释放状态
	if play_animation:
		if play_animation:
			if card_act_skill_animation(head_card_1,head_card_2,"down"):
				await get_tree().create_timer(0.75/battle_speed).timeout
	# 卡牌退出预备状态
	if play_animation:
		if card_prepare_animation(head_card_1,head_card_2,"down"):
			await get_tree().create_timer(0.5/battle_speed).timeout
	return is_entering_part

# 交战技能结算及对对碰
func settlement_fight_part():
	var head_card_1 = player_battle_fields[1][0]
	var head_card_2 = player_battle_fields[2][0]
	# 卡牌预备状态显示
	if play_animation:
		if card_prepare_animation(head_card_1,head_card_2,"up"):
			await get_tree().create_timer(0.5/battle_speed).timeout
	var is_fight_skill = false
	var fight_skill_1 = null
	var fight_skill_2 = null
	if "on_engage" in player_battle_fields[1][0].skill_time:
		fight_skill_1 = player_battle_fields[1][0]
		is_fight_skill = true
	if "on_engage" in player_battle_fields[2][0].skill_time:
		fight_skill_2 = player_battle_fields[2][0]
		is_fight_skill = true
	
	if is_fight_skill:
		# 卡牌进入技能释放状态
		if play_animation:
			if card_act_skill_animation(fight_skill_1,fight_skill_2,"up"):
				await get_tree().create_timer(0.5/battle_speed).timeout
		if (fight_skill_1 != null):
			if play_animation:
				buff_text_effect(fight_skill_1,load_card.timing_name("on_engage"),"blue")
				await get_tree().create_timer(0.1/battle_speed).timeout
			settlement_normal_skill(fight_skill_1,1)
		if (fight_skill_2 != null):
			if play_animation:
				buff_text_effect(fight_skill_2,load_card.timing_name("on_engage"),"blue")
				await get_tree().create_timer(0.1/battle_speed).timeout
			settlement_normal_skill(fight_skill_2,2)
		if (fight_skill_1 != null) or (fight_skill_2 != null):
			if play_animation:
				await get_tree().create_timer(0.5/battle_speed).timeout
		# 卡牌退出技能释放状态
		if play_animation:
			if card_act_skill_animation(fight_skill_1,fight_skill_2,"down"):
				await get_tree().create_timer(0.75/battle_speed).timeout
	
	# 如果双方还活着则发生对对碰
	if (head_card_1.strength > 0) and (head_card_2.strength > 0):
		if play_animation:
			var tween_attack = get_tree().create_tween().set_parallel(true)
			tween_attack.tween_property(head_card_1,"position",head_card_1.position+Vector2(0,+90),0.2/battle_speed)
			tween_attack.tween_property(head_card_2,"position",head_card_2.position+Vector2(0,-90),0.2/battle_speed)
			await get_tree().create_timer(0.25/battle_speed).timeout

		var attack_1 = head_card_1.strength
		var attack_2 = head_card_2.strength

		# 结算致命
		var is_deadly_1 = settlement_deadly(head_card_1)
		var is_deadly_2 = settlement_deadly(head_card_2)
		if is_deadly_1 or is_deadly_2:
			if is_deadly_1:
				attack_1 = 10000
				if play_animation:
					buff_text_effect(head_card_1,tr("keyword.lethal"),"green")
			if is_deadly_2:
				attack_2 = 10000
				if play_animation:
					buff_text_effect(head_card_2,tr("keyword.lethal"),"green")
			if play_animation:
				await get_tree().create_timer(0.1/battle_speed).timeout
	
		settlement_damage(head_card_1,attack_2)
		settlement_damage(head_card_2,attack_1)
		if play_animation:
			await get_tree().create_timer(0.2/battle_speed).timeout

		# 结算反噬（双方都要结算，不能用 or 短路）
		var self_hurt_1 = settlement_self_hurt(head_card_1)
		var self_hurt_2 = settlement_self_hurt(head_card_2)
		if self_hurt_1 or self_hurt_2:
			if play_animation:
				await get_tree().create_timer(0.1/battle_speed).timeout

		if play_animation:
			var tween_attack_back = get_tree().create_tween().set_parallel(true)
			tween_attack_back.tween_property(head_card_1,"position",head_card_1.position+Vector2(0,-90),0.2/battle_speed)
			tween_attack_back.tween_property(head_card_2,"position",head_card_2.position+Vector2(0,+90),0.2/battle_speed)
			await get_tree().create_timer(0.25/battle_speed).timeout

	# 卡牌退出预备状态
	if play_animation:
		if card_prepare_animation(head_card_1,head_card_2,"down"):
			await get_tree().create_timer(0.5/battle_speed).timeout


### 伤害结算
# 结算伤害
func settlement_damage(target_card, damage):
	#坚固减伤优先于庇护，即结算完减伤若伤害大于0才结算庇护

	# 结算坚固
	var solid_num = 0
	if target_card.special_skill.has("sturdy"):
		solid_num = target_card.special_skill.sturdy
		if play_animation:
			await get_tree().create_timer(0.1/battle_speed).timeout
			buff_text_effect(target_card,tr("keyword.sturdy")+str(solid_num),"green")
	damage = max(0, damage - solid_num)

	# 结算庇护（special_skill 是合并时复制出来的，可以直接移除）
	if target_card.special_skill.has("shelter") and (damage > 0):
		target_card.special_skill.erase("shelter")
		load_card.update_attribute_display(target_card,"skill_3",load_card.generate_skill_string(target_card.special_skill))

		damage = 0
		if play_animation:
			await get_tree().create_timer(0.1/battle_speed).timeout
			buff_text_effect(target_card,tr("keyword.shelter"),"green")

	target_card.strength -= damage
	# 改变战力面板显示
	target_card.get_node("strength_1").text = str(target_card.strength)


### 死亡结算（遍历副本再从原数组移除：边遍历边 erase 会漏掉相邻的阵亡单位）
func settlement_death():
	var is_death = false
	for i in player_battle_fields[1]:
		if i.strength <= 0:
			is_death = true
	for i in player_battle_fields[2]:
		if i.strength <= 0:
			is_death = true
	if is_death:
		var tween_remove = null
		if play_animation:
			tween_remove = create_tween().set_parallel(true)
		
		for i in player_battle_fields[1].duplicate():
			if i.strength <= 0:
				if play_animation:
					tween_remove.tween_property(i,"modulate:a",0,1.0/battle_speed)
					tween_remove.tween_property(i,"position",i.position+Vector2(0,-500),1.2/battle_speed)
				else:
					# 不播放动画直接移除
					i.modulate.a = 0
					i.position = i.position+Vector2(0,-500)
				player_battle_fields[1].erase(i)
				is_death = true
		for i in player_battle_fields[2].duplicate():
			if i.strength <= 0:
				if play_animation:
					tween_remove.tween_property(i,"modulate:a",0,1.0/battle_speed)
					tween_remove.tween_property(i,"position",i.position+Vector2(0,+500),1.2/battle_speed)
				else:
					# 不播放动画直接移除
					i.modulate.a = 0
					i.position = i.position+Vector2(0,+500)
				player_battle_fields[2].erase(i)
				is_death = true
	return is_death

# 移动角色,补齐位置
func move_character():
	var is_move = false
	var unit_duration = 0.6
	for i in range(player_battle_fields[1].size()):
		var card = player_battle_fields[1][i]
		if card.position.x > (i+1)*240:
			is_move = true
	for i in range(player_battle_fields[2].size()):
		var card = player_battle_fields[2][i]
		if card.position.x > (i+1)*240:
			is_move = true
	if is_move == false:
		return is_move

	var tween_move = null
	if play_animation:
		tween_move = get_tree().create_tween().set_parallel(true)
	for i in range(player_battle_fields[1].size()):
		var card = player_battle_fields[1][i]
		if card.position.x > (i+1)*240:
			var num_move = (card.position.x)/240 - i - 1
			if play_animation:
				tween_move.tween_property(card,"position",card.position+Vector2(-240*num_move,0),unit_duration/battle_speed)
			else:
				card.position = card.position+Vector2(-240*num_move,0)
	for i in range(player_battle_fields[2].size()):
		var card = player_battle_fields[2][i]
		if card.position.x > (i+1)*240:
			var num_move = (card.position.x)/240 - i - 1
			if play_animation:
				tween_move.tween_property(card,"position",card.position+Vector2(-240*num_move,0),unit_duration/battle_speed)
			else:
				card.position = card.position+Vector2(-240*num_move,0)
	return is_move


#==============================================
##### 动画部分 #####
#==============================================

# 卡牌移动到指定位置的动画效果
func animate_card_to_position(card, new_position,speed):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed/battle_speed)

# 显示buff数字特效
func buff_text_effect(card, text, color):
	var buff_text_prefab = preload("res://scenes/battle/buff_text.tscn")
	var buff_text = buff_text_prefab.instantiate()
	$"../buff_text_container".add_child(buff_text)
	buff_text.position = card.position
	buff_text.get_node("buff_text_label").text = text
	buff_text.get_node("AnimationPlayer").play(color+"_text")

# 卡牌预备状态动画
func card_prepare_animation(card_1,card_2,direction):
	var is_card_prepare = false
	if (card_1 == null) and (card_2 == null):
		return is_card_prepare
	
	var direction_para = 1
	var scale_para = 1.1
	var duration_para = 0.3
	if direction == "down":
		direction_para = -1
		scale_para = 1.0
	var tween_prepare = get_tree().create_tween().set_parallel(true)
	if card_1 != null:
		tween_prepare.tween_property(card_1,"position",card_1.position+Vector2(0,30*direction_para),duration_para/battle_speed)
		tween_prepare.tween_property(card_1,"scale",Vector2(scale_para,scale_para),duration_para/battle_speed)
		is_card_prepare = true
	if card_2 != null:
		tween_prepare.tween_property(card_2,"position",card_2.position+Vector2(0,-30*direction_para),duration_para/battle_speed)
		tween_prepare.tween_property(card_2,"scale",Vector2(scale_para,scale_para),duration_para/battle_speed)
		is_card_prepare = true
	return is_card_prepare

# 卡牌释放技能动画
func card_act_skill_animation(card_1,card_2,direction):
	var is_card_act = false
	if (card_1 == null) and (card_2 == null):
		return is_card_act
	
	var direction_para = 1
	var scale_para = 1.2
	var duration_para = 0.3
	if direction == "down":
		direction_para = -1
		scale_para = 1.1
	var tween_act = get_tree().create_tween().set_parallel(true)
	if card_1 != null:
		tween_act.tween_property(card_1,"position",card_1.position+Vector2(0,40*direction_para),duration_para/battle_speed)
		tween_act.tween_property(card_1,"scale",Vector2(scale_para,scale_para),duration_para/battle_speed)
		is_card_act = true
	if card_2 != null:
		tween_act.tween_property(card_2,"position",card_2.position+Vector2(0,-40*direction_para),duration_para/battle_speed)
		tween_act.tween_property(card_2,"scale",Vector2(scale_para,scale_para),duration_para/battle_speed)
		is_card_act = true
	return is_card_act

#==============================================
##### 普通技能部分 #####
#==============================================

### 整合依次结算 ###

# 结算普通技能
func settlement_normal_skill(card, card_owner):
	settlement_raging(card)
	if play_animation:
		await get_tree().create_timer(0.1/battle_speed).timeout
	settlement_assembling(card, card_owner)
	if play_animation:
		await get_tree().create_timer(0.1/battle_speed).timeout
	settlement_corrosion(card, card_owner)
	if play_animation:
		await get_tree().create_timer(0.1/battle_speed).timeout
	settlement_encouraging(card, card_owner)

### 单个技能部分 ###

# 结算狂暴
func settlement_raging(card):
	if card.normal_skill.has("rage"):
		var power = card.normal_skill.rage
		if play_animation:
			buff_text_effect(card,tr("keyword.rage")+" + "+str(power),"green")
		card.strength += power
		card.get_node("strength_1").text = str(card.strength)

# 结算集结
func settlement_assembling(card, card_owner):
	if card.normal_skill.has("rally"):
		var total_power = 0
		for partner in player_battle_fields[card_owner]:
			total_power += partner.normal_skill.get("rally", 0)
		if play_animation:
			buff_text_effect(card,tr("keyword.rally")+" + "+str(total_power),"green")
		card.strength += total_power
		card.get_node("strength_1").text = str(card.strength)

# 结算腐蚀
func settlement_corrosion(card, card_owner):
	# 如果对方无角色则不执行
	if player_battle_fields[3-card_owner].size() == 0:
		return

	if card.normal_skill.has("corrode"):
		var power = card.normal_skill.corrode
		var aim = player_battle_fields[3-card_owner][0]
		if play_animation:
			buff_text_effect(aim,tr("keyword.corrode")+" - "+str(power),"red")
		settlement_damage(aim, power)

# 结算振奋
func settlement_encouraging(card, card_owner):
	if card.normal_skill.has("inspire"):
		var power = card.normal_skill.inspire
		for aim in player_battle_fields[card_owner]:
			aim.strength += power
			aim.get_node("strength_1").text = str(aim.strength)
			if play_animation:
				buff_text_effect(aim,tr("keyword.inspire")+" + "+str(power),"green")


#==============================================
##### 特殊技能部分 #####
#==============================================

# 结算致命
func settlement_deadly(card):
	return card.special_skill.has("lethal")

# 结算反噬：走伤害流程（受坚固减免、可被庇护抵挡）
func settlement_self_hurt(card):
	if not card.special_skill.has("backlash"):
		return false
	var power = card.special_skill.backlash
	if play_animation:
		buff_text_effect(card,tr("keyword.backlash")+" - "+str(power),"red")
	settlement_damage(card, power)
	return true
