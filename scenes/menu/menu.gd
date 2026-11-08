extends Control
## 主菜单：左侧标题和文字按钮。冒险、线下对战还没做，按钮不可用。

signal to_test_mode
signal to_book_mode
signal to_single_mode


func _on_test_mode_pressed() -> void:
	to_test_mode.emit()


func _on_single_mode_pressed() -> void:
	to_single_mode.emit()


func _on_book_mode_pressed() -> void:
	to_book_mode.emit()
