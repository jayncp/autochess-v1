// 阵亡烧散：卡牌临时套一个 CanvasGroup，整张卡（含光晕）画完后再按这个着色器输出。
// 先变灰（grey 0 → 1），再按噪声镂空（progress 0 → 1），镂空边缘一圈橙色的燃烧边。
// 噪声按屏幕像素取，每 320 像素一个周期（卡在烧散时不动）。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float grey = 0.0;
uniform float progress = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.62, 0.22, 1.0);

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	float light = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(light) * 0.7, grey);
	float n = texture(noise, SCREEN_UV / SCREEN_PIXEL_SIZE / 320.0).r;
	float threshold = progress * 1.1 - 0.05;
	c.rgb = mix(edge_color.rgb, c.rgb, smoothstep(threshold, threshold + 0.06, n));
	c.a *= step(threshold, n);
	COLOR *= c;
}
