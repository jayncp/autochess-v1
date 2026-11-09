class_name BoardLayout
## 布阵界面（构筑阶段、科研模式）的列：左边一列阵营旗帜，右边一列按钮，中间 7 个卡位等宽排开、整体居中。
## 卡牌缩放取"宽度放得下"和调用方给的上限（高度放得下）中较小的。

const TAG_COLUMN := 100.0
const RIGHT_COLUMN := 320.0
const GAP := 22.0
const SLOTS := 7


## 7 列在 [left, right] 里居中：scale 是卡牌缩放，x(i) 是第 i 列左边，center(i) 是中心
static func columns(left: float, right: float, max_scale: float) -> Dictionary:
	var scale := minf(max_scale, (right - left - (SLOTS - 1) * GAP) / SLOTS / CardFace.WIDTH)
	var width := CardFace.WIDTH * scale
	var total := SLOTS * width + (SLOTS - 1) * GAP
	var x0 := left + (right - left - total) / 2
	return {"scale": scale, "width": width, "left": x0, "right": x0 + total,
		"x": func(i: int) -> float: return x0 + i * (width + GAP),
		"center": func(i: int) -> float: return x0 + i * (width + GAP) + width / 2}


## 卡牌在缩放 scale 下的高度（完整卡或紧凑卡）
static func card_height(scale: float, compact: bool) -> float:
	return CardFace.LAYOUTS[compact].height * scale
