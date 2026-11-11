extends Control
## 主菜单：左侧标题和文字按钮。冒险、线下对战还没做，按钮不可用。
## 启动时读存档遇到问题（用备份恢复、进度重置、存档来自更新版本）时，弹一次通知。

signal to_test_mode
signal to_book_mode
signal to_single_mode
signal to_settings


func _ready() -> void:
	if SaveData.notice:
		Dialog.notice(self, tr("ui.dialog.hint"), tr(SaveData.notice))
		SaveData.notice = ""


func _on_test_mode_pressed() -> void:
	to_test_mode.emit()


func _on_single_mode_pressed() -> void:
	to_single_mode.emit()


func _on_book_mode_pressed() -> void:
	to_book_mode.emit()


func _on_settings_pressed() -> void:
	to_settings.emit()
