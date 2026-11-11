class_name GameSettings
## 玩家设置：默认速度、默认紧凑模式。存在 user://settings.cfg（ConfigFile 文本），改了立刻保存。
## 静态类，启动时 load() 一次。缺的项用默认值，不认识的项和不合法的值忽略。
## 默认值只在进入时读：构筑阶段、科研模式读紧凑模式，每场开战读速度；当次临时改的不写回。

const SPEEDS: Array[float] = [1.0, 2.0, 5.0, 20.0]

## 文件路径；测试里改成测试专用的文件
static var path := "user://settings.cfg"
static var speed := 1.0
static var compact := true


static func load() -> void:
	speed = 1.0
	compact = true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	var saved_speed = file.get_value("battle", "speed", speed)
	if (saved_speed is float or saved_speed is int) and float(saved_speed) in SPEEDS:
		speed = float(saved_speed)
	var saved_compact = file.get_value("board", "compact", compact)
	if saved_compact is bool:
		compact = saved_compact


static func save() -> void:
	var file := ConfigFile.new()
	file.set_value("battle", "speed", speed)
	file.set_value("board", "compact", compact)
	if file.save(path) != OK:
		push_warning("设置保存失败：%s" % path)
