shader_type canvas_item;
// 卡图背景（CardFace 用）：
// - mode 0 径向渐变：colors[0] 中心 → colors[1]（mid_stop 处）→ colors[2] 边缘；单种族角色、1–4★ 装备
// - mode 1 环形渐变：colors 前 count 个按扇区排开，每个扇区前 solid 的部分是纯色，其余渐变到下一个；多种族角色、5★ 装备
// 外圈压暗，四角按 radius 切成圆角。

uniform vec2 size;
uniform float radius;
uniform int mode = 0;
uniform vec4 colors[5] : source_color;
uniform int count = 1;
uniform float mid_stop = 0.4;
uniform float solid = 0.0;
uniform float start_angle = 0.0; // 度，0 是正上方，顺时针

const vec3 DARK = vec3(0.027, 0.039, 0.078);

vec3 radial(vec2 p) {
	float t = length((p - vec2(0.5, 0.38) * size) / (vec2(0.85, 0.7) * size));
	if (t < mid_stop) {
		return mix(colors[0].rgb, colors[1].rgb, t / mid_stop);
	}
	return mix(colors[1].rgb, colors[2].rgb, clamp((t - mid_stop) / (1.0 - mid_stop), 0.0, 1.0));
}

vec3 conic(vec2 p) {
	vec2 d = p - vec2(0.5, 0.4) * size;
	float turn = mod(degrees(atan(d.x, -d.y)) - start_angle + 720.0, 360.0) / 360.0 * float(count);
	int i = int(floor(turn)) % count;
	float t = clamp((fract(turn) - solid) / (1.0 - solid), 0.0, 1.0);
	return mix(colors[i].rgb, colors[(i + 1) % count].rgb, t);
}

void fragment() {
	vec2 p = UV * size;
	vec3 color = mode == 0 ? radial(p) : conic(p);
	// 外圈压暗：58% 以内不变，88% 处 0.35，100% 处 0.6
	float v = length((p - vec2(0.5, 0.4) * size) / (vec2(0.95, 0.8) * size));
	float shade = v < 0.88 ? mix(0.0, 0.35, clamp((v - 0.58) / 0.3, 0.0, 1.0)) : mix(0.35, 0.6, clamp((v - 0.88) / 0.12, 0.0, 1.0));
	color = mix(color, DARK, shade);
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - radius);
	float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	COLOR = vec4(color, clamp(0.5 - edge, 0.0, 1.0));
}
