shader_type canvas_item;
// 标题的金色渐变：只改白色的文字本体，描边和阴影保持原色。
// height 是文字区域的高度（像素），由使用它的节点设置。

uniform float height = 100.0;
uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.914, 0.69, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.851, 0.659, 0.29, 1.0);

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec4 base = COLOR * texture(TEXTURE, UV);
	if (COLOR.r + COLOR.g + COLOR.b > 2.9) {
		float t = clamp(local_y / height, 0.0, 1.0);
		vec3 gold = t < 0.5 ? mix(top_color.rgb, mid_color.rgb, smoothstep(0.15, 0.5, t)) : mix(mid_color.rgb, bottom_color.rgb, (t - 0.5) * 2.0);
		base.rgb = gold;
	}
	COLOR = base;
}
