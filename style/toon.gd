extends RefCounted
# 角色画风：把导入时默认的打光材质换成“不打光的手绘色块 + 描边”（建模线在 Blender 里用 render_rigged.py unlit ink2d=3 渲的那种）。
#
# 用法（不用挂节点，全是静态函数）：
#   Toon.apply(model, Toon.UNLIT_OUTLINE)
#
# 做法：
#   - 不改网格资源本身，只给每个 MeshInstance3D 的每个面设“表面覆盖材质”，随时能用 mode 0 还原。
#   - 同一份原材质 + 同样的参数只转一次，记在 _cache 里；几百只同种怪共用同一批材质，不逐只复制。
#   - 描边 = 换好的材质后面再挂一层 next_pass：把网格沿法线往外撑一圈、只画背面的黑壳。
#     没有用 material_overlay，所以和 fx.gd 的受击闪白（闪白占着 material_overlay）互不干扰。
#   - 影子：不打光的材质照样进阴影贴图，角色还是会在地上投影；黑壳那层关了投影，免得影子胖一圈。

const LIT := 0             # 保持导入时的样子（默认光照）
const UNLIT := 1           # 不打光
const UNLIT_OUTLINE := 2   # 不打光 + 描边
const LIT_OUTLINE := 3     # 打光 + 描边
const SOFT_OUTLINE := 4    # 弱光照（基本是平涂，但还吃一点明暗和影子）+ 描边

## true = 只描整个人的外轮廓（和 ink2d 一样，关节、衣服接缝里不出黑线）。靠模板缓冲：身体先写上编号，黑壳只画在没有这个编号的像素上。
## false = 普通的黑壳描边，每块网格各描各的：便宜一点点，但袖口、领口、腰带这些接缝里会翻出黑线。
static var silhouette_only := true
## 远处线宽的下限（屏幕像素）。离相机远了，按米算的线宽不到一个像素会断断续续，这里托个底
static var min_pixels := 2.0
## 线宽的上限 = outline_width 的多少倍（托底不会超过它，免得很远的小人被描成一团黑）
static var max_grow := 4.0
## 同一种怪轮流用几个模板编号。两只同编号的怪叠在一起时，中间那段线会并掉；编号越多越少见（材质份数也跟着乘这么多）
static var ref_variants := 4
## 弱光照档：平涂占多少、太阳光加多少。亮面 = soft_flat + soft_light，背光面和影子里 = soft_flat + soft_light * soft_wrap
static var soft_flat := 0.74
static var soft_light := 0.30
static var soft_wrap := 0.35

static var _cache := {}          # 键 -> [原材质（留着引用，免得实例号被别的资源顶替）, 换好的材质]
static var _outline_cache := {}  # 键 -> 黑壳材质
static var _shaders := {}        # 着色器源码 -> Shader
static var _refs := {}           # "模型文件#第几号" -> 模板编号（1～255）
static var _turn := {}           # 模型文件 -> 已经套过几只（用来轮流分编号）


static func apply(model: Node3D, mode: int, outline_width := 0.012, outline_color := Color(0.06, 0.05, 0.05)) -> void:
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var outlined := mode == UNLIT_OUTLINE or mode == LIT_OUTLINE or mode == SOFT_OUTLINE
	var ref := 0
	if outlined and silhouette_only:
		ref = _pick_ref(model)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null or mi.material_override != null or mi.has_meta("toon_skip"):
			continue
		# 第一次碰这个网格时，把它原来的材质记下来；之后换别的档、还原，都从原材质出发
		var src: Array
		if mi.has_meta("_toon_src"):
			src = mi.get_meta("_toon_src")
		else:
			src = []
			for s in mi.mesh.get_surface_count():
				src.append([mi.get_surface_override_material(s), mi.get_active_material(s)])
			mi.set_meta("_toon_src", src)
		for s in mini(src.size(), mi.mesh.get_surface_count()):
			var base := src[s][1] as BaseMaterial3D
			if mode == LIT or base == null:   # 不认识的材质（自己写的着色器）不动
				mi.set_surface_override_material(s, src[s][0])
			else:
				mi.set_surface_override_material(s, _convert(base, mode, ref, outline_width, outline_color))


## 清掉缓存（换了描边参数想腾内存时用；正常不用管）
static func clear_cache() -> void:
	_cache.clear()
	_outline_cache.clear()


# 一个模型用哪个模板编号：按模型文件分，同一个文件的再轮流分 ref_variants 个；记在模型身上，换档时不变
static func _pick_ref(model: Node3D) -> int:
	if model.has_meta("_toon_ref"):
		return model.get_meta("_toon_ref")
	var file := model.scene_file_path
	if file == "":
		file = str(model.name)
	var n: int = _turn.get(file, 0)
	_turn[file] = n + 1
	var key := "%s#%d" % [file, n % maxi(1, ref_variants)]
	if not _refs.has(key):
		_refs[key] = 1 + _refs.size() % 255
	model.set_meta("_toon_ref", _refs[key])
	return _refs[key]


static func _convert(base: BaseMaterial3D, mode: int, ref: int, width: float, color: Color) -> Material:
	var outlined := mode != UNLIT
	var key := [base.get_instance_id(), mode, ref, width if outlined else 0.0, color if outlined else Color.BLACK]
	if _cache.has(key):
		return _cache[key][1]
	var out: Material
	if mode == SOFT_OUTLINE:
		out = _soft_material(base, ref)
	else:
		# 直接复制原材质再改：贴图、颜色、透明方式、顶点色、双面这些设置原样留着
		var m: BaseMaterial3D = base.duplicate()
		if mode == UNLIT or mode == UNLIT_OUTLINE:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if ref > 0:
			m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			m.stencil_reference = ref
		out = m
	if outlined:
		out.next_pass = _outline_material(base, ref, width, color)
	_cache[key] = [base, out]
	return out


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	return _shaders[code]


# 原材质用了哪种透明：0 不透明，1 混合，2 镂空（按阈值丢像素）
static func _alpha_kind(base: BaseMaterial3D) -> int:
	match base.transparency:
		BaseMaterial3D.TRANSPARENCY_DISABLED:
			return 0
		BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			return 2
	return 1


static func _copy_surface_params(base: BaseMaterial3D, m: ShaderMaterial) -> void:
	m.set_shader_parameter("albedo", base.albedo_color)
	if base.albedo_texture != null:
		m.set_shader_parameter("tex", base.albedo_texture)
	m.set_shader_parameter("uv_scale", base.uv1_scale)
	m.set_shader_parameter("uv_offset", base.uv1_offset)
	m.set_shader_parameter("scissor", base.alpha_scissor_threshold)


# 弱光照：贴图颜色大部分直接当自发光（平涂），剩下一小份吃太阳光和影子；不吃环境光、没有高光
static func _soft_material(base: BaseMaterial3D, ref: int) -> ShaderMaterial:
	var cull := "cull_back"
	if base.cull_mode == BaseMaterial3D.CULL_DISABLED:
		cull = "cull_disabled"
	elif base.cull_mode == BaseMaterial3D.CULL_FRONT:
		cull = "cull_front"
	var ak := _alpha_kind(base)
	var code := "shader_type spatial;\nrender_mode blend_mix, %s, ambient_light_disabled, specular_disabled%s;\n" % [cull, ", depth_prepass_alpha" if ak == 1 else ""]
	if ref > 0:
		code += "stencil_mode write, compare_always, %d;\n" % ref
	code += """
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float scissor = 0.5;
uniform float flat_amount = 0.74;
uniform float light_amount = 0.30;
uniform float wrap_amount = 0.35;
void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
}
void fragment() {
	vec4 c = texture(tex, UV) * albedo;
	VCOL
	ALBEDO = c.rgb;
	EMISSION = c.rgb * flat_amount;
	ALPHA_LINE
}
void light() {
	// 明暗压得很平：背光面也留 wrap_amount 这么多，影子只把这一小份光吃掉
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = mix(wrap_amount, 1.0, smoothstep(0.0, 0.35, nl) * ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * lit * light_amount;
}
"""
	code = code.replace("VCOL", "c *= COLOR;" if base.vertex_color_use_as_albedo else "")
	code = code.replace("ALPHA_LINE", ["", "ALPHA = c.a;", "ALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = scissor;"][ak])
	var m := ShaderMaterial.new()
	m.shader = _shader(code)
	m.resource_name = base.resource_name
	m.render_priority = base.render_priority
	_copy_surface_params(base, m)
	m.set_shader_parameter("flat_amount", soft_flat)
	m.set_shader_parameter("light_amount", soft_light)
	m.set_shader_parameter("wrap_amount", soft_wrap)
	return m


# 黑壳：沿法线往外撑、只画背面。线宽按米算（近看和人成比例），远了不到 min_pixels 个像素就按像素托底。
# 原材质不透明的，所有角色共用同一份（按编号、线宽、颜色分）；带镂空贴图的另配一份带贴图的，壳才会跟着镂空。
static func _outline_material(base: BaseMaterial3D, ref: int, width: float, color: Color) -> ShaderMaterial:
	var ak := _alpha_kind(base)
	var cut := ak != 0 and base.albedo_texture != null
	var key := [ref, width, color, base.get_instance_id() if cut else 0, min_pixels, max_grow]
	if _outline_cache.has(key):
		return _outline_cache[key]
	var code := "shader_type spatial;\n"
	if ref > 0:
		# 放到透明那一趟去画：这时所有角色的身体都已经把编号写进模板缓冲了，哪只先画哪只后画不影响结果。
		# 不能加 depth_draw_always：试过，壳会先单独写一遍深度，把自己的线挡掉一大半
		code += "render_mode unshaded, cull_front, shadows_disabled, world_vertex_coords, blend_mix;\n"
		code += "stencil_mode read, compare_not_equal, %d;\n" % ref
	else:
		code += "render_mode unshaded, cull_front, shadows_disabled, world_vertex_coords;\n"
	code += """
uniform vec4 ink : source_color = vec4(0.06, 0.05, 0.05, 1.0);
uniform float width = 0.012;
uniform float min_px = 1.5;
uniform float max_grow = 3.0;
uniform sampler2D tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tex_alpha = 1.0;
uniform float scissor = 0.5;
void vertex() {
	// 这个顶点处一个屏幕像素合多少米（透视相机；正交相机时 PROJECTION_MATRIX[3][3] 是 1，直接用固定值）
	float dist = length(VERTEX - CAMERA_POSITION_WORLD);
	float metre_per_px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		metre_per_px *= dist;
	}
	float w = min(max(width, min_px * metre_per_px), width * max_grow);
	VERTEX += normalize(NORMAL) * w;
	PULL
}
void fragment() {
	ALBEDO = ink.rgb;
	ALPHA_LINE
}
"""
	var alpha_line := ""
	if ref > 0:
		alpha_line = "ALPHA = ink.a;"
	if cut:
		alpha_line = "ALPHA = ink.a * texture(tex, UV).a * tex_alpha;\n\tALPHA_SCISSOR_THRESHOLD = scissor;"
	code = code.replace("ALPHA_LINE", alpha_line)
	# 只描外轮廓时，壳再朝相机拉近一点（屏幕上位置不变）：脚底那圈线不会被地面吃掉；自己身上有模板挡着，不会画到身体上
	code = code.replace("PULL", "VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * w * 4.0;" if ref > 0 else "")
	var m := ShaderMaterial.new()
	m.shader = _shader(code)
	m.resource_name = "toon_outline"
	if ref > 0:
		m.render_priority = -1   # 比刀光、血、闪白这些半透明特效先画，特效盖在线上面
	m.set_shader_parameter("ink", color)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("min_px", min_pixels)
	m.set_shader_parameter("max_grow", max_grow)
	if cut:
		m.set_shader_parameter("tex", base.albedo_texture)
		m.set_shader_parameter("tex_alpha", base.albedo_color.a)
		m.set_shader_parameter("scissor", base.alpha_scissor_threshold)
	_outline_cache[key] = m
	return m
