extends Sprite2D

func _ready():
	adjust_size()

func adjust_size():
	var target_width = 30.0  # 目标宽度
	var target_height = 30.0  # 目标高度

	# 获取纹理的原始宽度和高度
	var original_width = self.texture.get_width()
	var original_height = self.texture.get_height()

	# 计算缩放比例
	var scale_x = target_width / original_width
	var scale_y = target_height / original_height
	
	# 设置sprite的缩放
	self.scale = Vector2(scale_x, scale_y)
