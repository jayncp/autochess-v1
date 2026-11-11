class_name SaveData
## 进度存档：user://save.json，格式和升级规则见 docs/design/save-data.md。现在只有闯关的通关记录。
## 静态类，启动时 load() 一次，改了立刻保存。
## - 写入：先写 .tmp，原文件改名为 .bak，再把 .tmp 改名为正式文件；写到一半出错，原来的存档还在。
## - 读取：正式文件读不了时用 .bak 恢复，备份也不行就从空进度开始；读不了的正式文件改名为 .broken 留着。
## - 版本：读到比游戏新的版本（旧游戏打开新存档）时只读不写，免得覆盖新内容。
## 读取时遇到的问题记在 notice（翻译 key），由主菜单弹一次通知。

const VERSION := 1

## 文件路径；测试里改成测试专用的文件
static var path := "user://save.json"
## 读取时遇到的问题（翻译 key），没有为空；主菜单通知后清空
static var notice := ""
## 存档来自更新版本的游戏：只读不写
static var read_only := false
static var _data := _empty()


static func load() -> void:
	notice = ""
	read_only = false
	_data = _empty()
	var backup := path + ".bak"
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(backup):
		return  # 还没有存档
	var data = _read(path)
	if data == null:
		if FileAccess.file_exists(path):
			DirAccess.rename_absolute(path, path + ".broken")
		data = _read(backup)
		notice = "ui.save.reset" if data == null else "ui.save.restored"
		if data == null:
			return
	# 以后改格式时，在这里按版本号逐级升级旧存档（现在只有版本 1）
	if data.version > VERSION:
		read_only = true
		notice = "ui.save.newer"
	_data = data


static func save() -> void:
	if read_only:
		return
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify(_data, "\t")):
		push_warning("存档写入失败：%s" % temp)
		return
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	DirAccess.rename_absolute(temp, path)


static func is_cleared(level_id: String) -> bool:
	var entry = _data.levels.get(level_id)
	return entry is Dictionary and entry.get("cleared") == true


## 记下通关（第一次通关时记时间，已通关的不变）
static func mark_cleared(level_id: String) -> void:
	if is_cleared(level_id):
		return
	_data.levels[level_id] = {"cleared": true, "first_cleared": Time.get_datetime_string_from_system()}
	save()


static func clear_levels() -> void:
	_data.levels = {}
	save()


static func _empty() -> Dictionary:
	return {"version": VERSION, "levels": {}}


## 读一个存档文件：不存在、不是合法的 JSON、缺版本号或关卡记录时返回 null
static func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file_path)) != OK:
		return null
	var data = json.data
	if not (data is Dictionary and data.get("version") is float and data.version >= 1 and data.get("levels") is Dictionary):
		return null
	data.version = int(data.version)
	return data
