class_name LevelDB
## 关卡数据：读取 data/levels.json。
## enemy 是敌方阵容 [[角色, 装备], ...]（装备为空字符串表示不带），hand 是玩家手牌（按发牌顺序）。

const PATH := "res://data/levels.json"

static var _levels := {}


## 全部关卡：id -> 关卡数据，顺序与文件一致
static func all() -> Dictionary:
	if _levels.is_empty():
		for level in JSON.parse_string(FileAccess.get_file_as_string(PATH)):
			_check(level)
			_levels[level.id] = level
	return _levels


static func level(id: String) -> Dictionary:
	return all()[id]


static func _check(level: Dictionary) -> void:
	var cards := CardDB.all()
	var refs: Array = level.hand.duplicate()
	for unit in level.enemy:
		refs.append(unit[0])
		if unit[1] != "":
			refs.append(unit[1])
	for id in refs:
		if not cards.has(id):
			push_error("levels.json：%s 引用了不存在的卡 %s" % [level.id, id])
