shader_type spatial;
// 原作 StatChangePhase 强化演出的 2.5D 移植：图案来自 battle_stats 图集，
// alpha 由角色当前帧（图集 region + trim 位置 + flip_h）遮罩，只显示角色轮廓内的图案。
// 参数由 fx/rogue_stat_change.gd 每帧同步；源像素比例与上升换算见 assets/pokemon/stat_fx/SOURCES.md。
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D stat_tex : filter_nearest;
uniform vec2 stat_region_pos = vec2(0.0, 0.0);
uniform vec2 stat_region_size = vec2(1.0, 1.0);
uniform vec2 tile_count = vec2(1.0, 1.0);
uniform float scroll_tiles = 0.0;

uniform sampler2D mask_tex : filter_nearest;
uniform vec2 mask_region_pos = vec2(0.0, 0.0);
uniform vec2 mask_region_size = vec2(1.0, 1.0);
uniform vec2 mask_place_pos = vec2(0.0, 0.0);
uniform vec2 mask_place_size = vec2(1.0, 1.0);
uniform float mask_flip = 0.0;

uniform float fx_alpha = 1.0;

varying vec2 quad_uv;

void vertex() {
	quad_uv = UV;
}

void fragment() {
	vec2 uvw = quad_uv;
	if (mask_flip > 0.5) {
		uvw.x = 1.0 - uvw.x;
	}
	float mask_a = 0.0;
	if (uvw.x >= mask_place_pos.x && uvw.x <= mask_place_pos.x + mask_place_size.x
			&& uvw.y >= mask_place_pos.y && uvw.y <= mask_place_pos.y + mask_place_size.y) {
		vec2 local = (uvw - mask_place_pos) / max(mask_place_size, vec2(0.000001));
		vec2 muv = mask_region_pos + local * mask_region_size;
		mask_a = texture(mask_tex, muv).a;
	}
	// 源：tileSprite 位置 y -= rise（整体上移）；固定屏幕点采样到的纹理 y 应 += rise/(32*6)。
	// 故 scroll_tiles 取正号（用减法会把上升方向做反，固定点结果 0.875 而非 0.375）。
	vec2 tuv = fract(quad_uv * tile_count + vec2(0.0, scroll_tiles));
	vec2 suv = stat_region_pos + tuv * stat_region_size;
	vec4 c = texture(stat_tex, suv);
	ALBEDO = c.rgb;
	ALPHA = c.a * mask_a * fx_alpha;
}
