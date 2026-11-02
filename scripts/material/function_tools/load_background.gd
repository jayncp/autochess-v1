class_name load_background
extends Node

## 为指定的TextureRect节点设置纹理并调整其属性
## 参数:
## - texture_rect: TextureRect - 要设置纹理的TextureRect节点
## - texture_path: String - 纹理资源的路径
## - alpha: float - 纹理的透明度，默认为1.0（完全不透明）
## - size: Vector2 - 纹理的自定义大小，默认为Vector2.ZERO（不调整大小）
## 返回:
## - Texture - 加载的纹理资源
static func set_texture_for_node(texture_rect: TextureRect, texture_path: String, alpha: float = 1.0, size: Vector2 = Vector2.ZERO) -> Texture:
	# 加载指定路径的纹理资源
	var background_texture = load(texture_path)
	# 将纹理分配给TextureRect节点
	texture_rect.texture = background_texture
	
	# 如果指定了自定义大小，则调整TextureRect的大小和拉伸模式
	if size != Vector2.ZERO:
		texture_rect.expand = true
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		texture_rect.custom_minimum_size = size
	
	# 设置纹理的透明度
	texture_rect.modulate.a = alpha
	
	# 返回加载的纹理资源
	return background_texture
