class_name LineupCode
## 阵容码：一方的阵容写成一段文字，如"鹦鹉+狮心 / 士兵 / 士兵 / 千机魔女+铁剑"（规范见 docs/design/lineup-code.md）。
## 只和当前版本的卡核对：认得出的位置导入，认不出的位置空着，记下问题。
## 阵容的格式和 BattleSim 一样是 [[角色 id, 装备 id], ...]，装备为空字符串表示不带，空卡位是 []。

## 一方最多几个位置
const SLOTS := 7
## 导出时位置之间、角色和装备之间的写法
const SEPARATOR := " / "
const JOIN := "+"

## 导入时当成半角的写法：全角的加号、斜杠，全角空格和不换行空格
const LOOSE := {"＋": "+", "／": "/", "\u3000": " ", "\u00a0": " "}
## 换行和它旁边的 /、中间的空行合起来算一个分隔
static var _line_break := RegEx.create_from_string("[ \\t]*/?\\s*\\n\\s*/?")


## 写成文字：空着的卡位跳过；卡名用当前语言的名字
static func write(lineup: Array) -> String:
	var parts := []
	for unit in lineup:
		if unit.is_empty():
			continue
		parts.append(_name(unit[0]) + (JOIN + _name(unit[1]) if unit[1] != "" else ""))
	return SEPARATOR.join(parts)


## 读文字：第 k 段对应第 k 个卡位，各段互不影响。
## 返回 {slots: 7 个卡位, problems: 问题}。问题是 {slot: 第几位（从 1 起）, kind: 种类, name: 哪个名字}，种类：
## unknown 不认识的角色，not_character 写的是装备，no_character 只有装备，
## unknown_equipment 不认识的装备，not_equipment 装备位置写的是角色，extra_equipment 多写的装备（name 是多出来的那些）；
## 超过 7 段时最后加一条 {kind: too_many, count: 没有导入的段数}。一段是空的不算问题。
## 一个角色都认不出时 slots 全空，要不要导入由调用方决定
static func read(text: String) -> Dictionary:
	var lookup := _lookup()
	var slots := []
	var problems := []
	var segments := _segments(text)
	for i in segments.size():
		if i >= SLOTS:
			var dropped := segments.slice(SLOTS).filter(func(s): return s != "").size()
			if dropped > 0:
				problems.append({"kind": "too_many", "count": dropped})
			break
		slots.append(_read_unit(segments[i], i + 1, lookup, problems))
	while slots.size() < SLOTS:
		slots.append([])
	return {"slots": slots, "problems": problems}


## 一段：角色，后面最多一件装备
static func _read_unit(segment: String, slot: int, lookup: Dictionary, problems: Array) -> Array:
	if segment == "":
		return []
	var parts := Array(segment.split(JOIN)).map(func(p): return p.strip_edges())
	var name: String = parts[0]
	var equipment := parts.slice(1).filter(func(p): return p != "")
	var id: String = lookup.get(name, "")
	if name == "":
		problems.append({"slot": slot, "kind": "no_character", "name": ""})
		return []
	if id == "":
		problems.append({"slot": slot, "kind": "unknown", "name": name})
		return []
	if CardDB.card(id).type != "character":
		problems.append({"slot": slot, "kind": "not_character", "name": name})
		return []
	var unit := [id, ""]
	if not equipment.is_empty():
		var equip_id: String = lookup.get(equipment[0], "")
		if equip_id == "":
			problems.append({"slot": slot, "kind": "unknown_equipment", "name": equipment[0]})
		elif CardDB.card(equip_id).type != "equipment":
			problems.append({"slot": slot, "kind": "not_equipment", "name": equipment[0]})
		else:
			unit[1] = equip_id
	if equipment.size() > 1:
		problems.append({"slot": slot, "kind": "extra_equipment", "name": JOIN.join(equipment.slice(1))})
	return unit


## 拆成段：全角当半角，换行当分隔（和旁边的 / 算一个），去掉首尾和分隔符两边的空白
static func _segments(text: String) -> Array:
	for loose in LOOSE:
		text = text.replace(loose, LOOSE[loose])
	text = _line_break.sub(text.replace("\r", "").strip_edges(), "/", true)
	return Array(text.split("/")).map(func(s): return s.strip_edges())


## 认得的写法：当前语言的卡名和英文 id -> id（卡名互不重复、不和别的卡的 id 相同，由测试保证）
static func _lookup() -> Dictionary:
	var lookup := {}
	for id in CardDB.all():
		lookup[_name(id)] = id
		lookup[id] = id
	return lookup


static func _name(id: String) -> String:
	return String(TranslationServer.translate("card." + id))
