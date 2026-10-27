shader_type spatial;
// 受击闪白（用户 2026-10-17：“受击之后的闪白应该加入”）：盖在本体前面一丁点的纯白剪影，
// amount 从 1 淡到 0（characters/caterpie.gd::flash_white 驱动）。朝向相机，保留节点缩放，同 Sprite3D 的 billboard。
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_nearest;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float front = 0.02;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	VERTEX.z += front;
}

void fragment() {
	float a = texture(tex, UV).a;
	if (a < 0.1) {
		discard;
	}
	ALBEDO = vec3(1.0);
	ALPHA = amount * a;
}
