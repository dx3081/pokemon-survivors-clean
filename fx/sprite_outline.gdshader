shader_type spatial;
// 金色描边（用户 2026-10-17：“另一个幸存者游戏有个金色描边的特效”）——给闪光 / 神兽宠物用。
// 做法：描边 = 同一张精灵图的 8 份纯金色剪影，朝 8 个方向各错开一点点，放在本体后面一丁点；
// 本体盖在上面，只露出一圈边。这个着色器画“纯色剪影”：朝向相机、按 shift 在相机平面上平移、略微往后。
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 color : source_color = vec4(1.0, 0.82, 0.2, 1.0);
uniform vec2 shift = vec2(0.0);        // 平移（精灵本地单位，宠物节点的缩放会再乘上去）
uniform float back = 0.03;             // 往后让多远，免得和本体同深度打架
uniform float shimmer = 0.18;          // 金光明暗起伏幅度

void vertex() {
	// 朝向相机的面片（保留节点缩放），同 Sprite3D 的 billboard。
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	VERTEX.xy += shift;
	VERTEX.z -= back;
}

void fragment() {
	if (texture(tex, UV).a < 0.1) {
		discard;
	}
	float glow = 1.0 - shimmer + shimmer * sin(TIME * 3.0);
	ALBEDO = color.rgb * glow;
}
