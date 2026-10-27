shader_type spatial;
// 拳风（用户 2026-10-18：“有拳风的从人发射出去到怪物的”）：8 帧白色拳风图集（assets/fx/fist_shot/sheet.png，4 列 2 行），
// 亮的一团在前，气流向下拖。面片朝向相机，再在屏幕平面里绕自己转 roll，让图的“上”朝着飞行方向。
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_linear;
uniform float frame = 0.0;      // 当前帧 0..7
uniform float cols = 4.0;
uniform float rows = 2.0;
uniform float roll = 0.0;       // 屏幕平面里的旋转（弧度），图的“上”转到这个方向
uniform float alpha = 1.0;

void vertex() {
	float c = cos(roll);
	float s = sin(roll);
	VERTEX.xy = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 cell = vec2(mod(frame, cols), floor(frame / cols));
	vec4 t = texture(tex, (UV + cell) / vec2(cols, rows));
	ALBEDO = t.rgb;
	ALPHA = t.a * alpha;
}
