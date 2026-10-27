shader_type spatial;
// 虚影（用户 2026-10-18：“虚影改成蓝色 / 或者是影子，如果是本体调淡有时候会区分不了本体和分身”）：
// 把出招方的贴图压成一整块半透明蓝色剪影，和本体一眼就能分开。朝向相机、保留节点缩放，同 Sprite3D 的 billboard。
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(0.45, 0.68, 1.0, 0.62);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float a = texture(tex, UV).a;
	if (a < 0.1) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
