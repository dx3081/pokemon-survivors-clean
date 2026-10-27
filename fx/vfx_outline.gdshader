shader_type spatial;
// 弹药特效描边（用户 2026-10-17：“要不要给 vfx 加个描边？”）：同一帧图的 8 份深色剪影，朝 8 个方向各错开一点点，
// 垫在特效后面，只露出一圈边，让小火苗 / 水滴 / 小旋风在草地上看得清。挂在弹体 / 命中特效面片的子节点上（继承它的朝向和缩放）。
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 color : source_color = vec4(0.04, 0.05, 0.14, 0.95);
uniform vec2 shift = vec2(0.0);      // 面片本地单位的平移
uniform float alpha = 1.0;           // 跟着特效本体一起淡出
uniform vec2 uv_shift = vec2(0.0);   // shift 换算到图集 UV 的量：用来读“本体在这个屏幕位置”的透明度

void vertex() {
	VERTEX.xy += shift;
}

void fragment() {
	float a = texture(tex, UV).a;
	if (a < 0.1) {
		discard;
	}
	// 只在本体外面露一圈：本体自己在这个位置有像素的地方不画（半透明的特效垫了深色会发灰 / 发黑）。
	if (texture(tex, UV + uv_shift).a >= 0.1) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * alpha;
}
