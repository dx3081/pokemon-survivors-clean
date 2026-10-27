extends Node3D
# 口袋妖怪这边由 main/arts.gd 的 _apply_world_fx 开关：雨 = 雨 2 + 云影 2；雪 = 雪 3 + 寒冷 2；雾 = 雾 2；冰雹 = 冰雹 3；沙暴 = 沙暴 4；别的天气全关。
# 雪 / 落叶 / 雾 / 云影：weather.set_snow(n) / set_leaves(n) / set_fog(n) / set_clouds(n)，都是 0 到 4 档，可以随便叠（比如雪 + 雾）。
# 用法（在 main.gd 里）：
#   add_child(weather)
#   weather.setup(player)            # player = 主角节点，雨跟着它走
#   weather.set_rain(2)              # 0 无雨 / 1 小雨 / 2 中雨 / 3 大雨 / 4 暴雨（带雷光）
#   weather.set_wind(Vector2(0.4, 0.1))  # 风向 + 力度：雨丝斜着落，方向跟着风
# 都是代码画的，不要任何图片；粒子在世界坐标里，所以主角跑动时雨不会跟着“粘”在身上。
# 雨层挂在主角头上，范围略大于屏幕，不在视野里的雨不会画；屏幕压暗层放在 CanvasLayer -1（在 3D 之上、界面之下），不会盖住血条。

const RAIN_AMOUNT := [0, 900, 2200, 4200, 6800]        # 各档雨丝数量
const SPLASH_AMOUNT := [0, 220, 520, 900, 1400]        # 地面水花数量
const DIM_ALPHA := [0.0, 0.10, 0.18, 0.27, 0.36]       # 各档屏幕压暗强度
const AREA := Vector2(44.0, 34.0)                        # 下雨范围（米，以主角为中心）
const HEIGHT := 8.0                                      # 雨丝从多高落下（要比镜头低，否则离镜头太近的雨丝会又粗又长）
const FALL_SPEED := 20.0

var level := 0
var wind := Vector2(0.35, 0.10)
var target: Node3D

var _rig: Node3D
var _rain: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _splash: GPUParticles3D
var _dim: ColorRect
var _flash: ColorRect
var _layer: CanvasLayer
var _flash_timer := 6.0
var _amount_ratio := 0.0
var snow_level := 0
var leaves_level := 0
var fog_level := 0
var cloud_level := 0
var _snow: GPUParticles3D
var _snow_mat: ParticleProcessMaterial
var _leaves: GPUParticles3D
var _leaves_mat: ParticleProcessMaterial
var _fog: ColorRect
var _fog_mat: ShaderMaterial
var _cloud: MeshInstance3D
var _cloud_mat: ShaderMaterial

const SNOW_AMOUNT := [0, 500, 1200, 2400, 4000]
const LEAF_AMOUNT := [0, 90, 220, 420, 650]
const FOG_ALPHA := [0.0, 0.18, 0.32, 0.46, 0.60]
const CLOUD_DARK := [0.0, 0.10, 0.18, 0.26, 0.34]

# 冰雹、沙暴（10-21 加）
const HAIL_AMOUNT := [0, 350, 800, 1500, 2400]
const HAIL_BOUNCE := [0, 120, 300, 520, 800]
const SAND_AMOUNT := [0, 1000, 2600, 5000, 8500]
const SAND_HAZE := [0.0, 0.25, 0.42, 0.58, 0.72]
var hail_level := 0
var sand_level := 0
var _hail: GPUParticles3D
var _hail_bounce: GPUParticles3D
var _hail_mat: ParticleProcessMaterial
var _sand: GPUParticles3D
var _sand_mat: ParticleProcessMaterial
var _sand_dust: GPUParticles3D
var _sand_dust_mat: ParticleProcessMaterial
var _sand_haze: ColorRect
var _sand_haze_mat: ShaderMaterial
var _sand_dim: ColorRect


func setup(player: Node3D) -> void:
	target = player
	_rig = Node3D.new()
	_rig.name = "RainRig"
	add_child(_rig)
	_build_rain()
	_build_splash()
	_build_screen()
	_build_snow()
	_build_leaves()
	_build_fog()
	_build_clouds()
	_build_hail()
	_build_sand()
	_build_blizzard()
	_build_cold()
	set_rain(level)


func set_rain(l: int) -> void:
	level = clampi(l, 0, 4)
	if _rain == null:
		return
	var on := level > 0
	_rain.emitting = on
	_splash.emitting = on
	_rain.amount = maxi(RAIN_AMOUNT[maxi(level, 1)], 1)
	_splash.amount = maxi(SPLASH_AMOUNT[maxi(level, 1)], 1)
	_update_dim()
	_flash_timer = randf_range(4.0, 9.0)


func set_wind(w: Vector2) -> void:
	wind = w
	if _rain_mat != null:
		_rain_mat.direction = _drop_dir()
	if _snow_mat != null:
		_snow_mat.gravity = Vector3(wind.x * 1.6, -1.2, wind.y * 1.6)
	if _leaves_mat != null:
		_leaves_mat.gravity = Vector3(wind.x * 3.0, -0.9, wind.y * 3.0)
	if _cloud_mat != null:
		_cloud_mat.set_shader_parameter("drift", Vector2(wind.x, wind.y) * 0.035 + Vector2(0.01, 0.004))
	if _hail_mat != null:
		_hail_mat.direction = Vector3(wind.x * 0.5, -1.0, wind.y * 0.5).normalized()
	if _sand_mat != null:
		_sand_mat.direction = _sand_dir()
	if _sand_dust_mat != null:
		_sand_dust_mat.direction = _sand_dir()
	if _bliz_mat != null:
		_bliz_mat.direction = _bliz_dir()
		_bliz_dust_mat.direction = _bliz_dir()


func _drop_dir() -> Vector3:
	return Vector3(wind.x, -1.0, wind.y).normalized()


func _process(delta: float) -> void:
	if target != null and _rig != null:
		_rig.global_position = Vector3(target.global_position.x, 0.0, target.global_position.z)
	if level >= 4:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = randf_range(6.0, 14.0)
			_lightning()


func _lightning() -> void:
	if _flash == null:
		return
	var tw := create_tween()
	_flash.color.a = 0.0
	tw.tween_property(_flash, "color:a", 0.55, 0.04)
	tw.tween_property(_flash, "color:a", 0.10, 0.07)
	tw.tween_property(_flash, "color:a", 0.45, 0.04)
	tw.tween_property(_flash, "color:a", 0.0, 0.35)


# ---------- 雨丝 ----------

func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 1000
	_rain.lifetime = (HEIGHT + 2.0) / FALL_SPEED
	_rain.local_coords = false
	_rain.preprocess = _rain.lifetime
	_rain.visibility_aabb = AABB(Vector3(-AREA.x, -2.0, -AREA.y), Vector3(AREA.x * 2.0, HEIGHT + 6.0, AREA.y * 2.0))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.position = Vector3(0, HEIGHT, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.5, 0.2, AREA.y * 0.5)
	pm.direction = _drop_dir()
	pm.spread = 1.5
	pm.initial_velocity_min = FALL_SPEED * 0.92
	pm.initial_velocity_max = FALL_SPEED * 1.08
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	_rain_mat = pm
	_rain.process_material = pm
	_rain.draw_pass_1 = _streak_mesh()
	_rig.add_child(_rain)


# 两片十字交叉的细长面片：从任何方向看都是一条细线，没有朝向问题
func _streak_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.016
	var h := 0.62
	for ang in [0.0, PI * 0.5]:
		var ax := Vector3(cos(ang), 0, sin(ang)) * w
		var a := -ax + Vector3(0, h * 0.5, 0)
		var b := ax + Vector3(0, h * 0.5, 0)
		var c := ax - Vector3(0, h * 0.5, 0)
		var d := -ax - Vector3(0, h * 0.5, 0)
		# 竖向渐变：头亮尾淡，看起来有拖影
		var top := Color(1, 1, 1, 0.85)
		var bot := Color(1, 1, 1, 0.0)
		st.set_color(top); st.add_vertex(a)
		st.set_color(top); st.add_vertex(b)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(top); st.add_vertex(a)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(bot); st.add_vertex(d)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.78, 0.86, 1.0, 0.7)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mesh.surface_set_material(0, mat)
	return mesh


# ---------- 地面水花 ----------

func _build_splash() -> void:
	_splash = GPUParticles3D.new()
	_splash.name = "Splash"
	_splash.amount = 400
	_splash.lifetime = 0.42
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-AREA.x, -1.0, -AREA.y), Vector3(AREA.x * 2.0, 3.0, AREA.y * 2.0))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash.position = Vector3(0, 0.04, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.5, 0.0, AREA.y * 0.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.scale_min = 0.9
	pm.scale_max = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.75))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_splash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.42, 0.42)
	q.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _ring_texture()
	mat.albedo_color = Color(0.82, 0.9, 1.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	_splash.draw_pass_1 = q
	_rig.add_child(_splash)


func _ring_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - absf(d - 0.78) / 0.16, 0.0, 1.0)
			a *= clampf((1.0 - d) * 6.0, 0.0, 1.0) if d > 0.85 else 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


# ---------- 屏幕压暗和雷光 ----------

func _build_screen() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -1
	add_child(_layer)
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(0.10, 0.14, 0.24, 0.0)
	_layer.add_child(_dim)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.9, 0.93, 1.0, 0.0)
	_layer.add_child(_flash)


# ---------- 雪 ----------

func set_snow(l: int) -> void:
	snow_level = clampi(l, 0, 4)
	if _snow == null:
		return
	_snow.emitting = snow_level > 0
	_snow.amount = maxi(SNOW_AMOUNT[maxi(snow_level, 1)], 1)


func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 1200
	_snow.lifetime = 6.5
	_snow.local_coords = false
	_snow.preprocess = _snow.lifetime
	_snow.emitting = false
	_snow.visibility_aabb = AABB(Vector3(-AREA.x, -2.0, -AREA.y), Vector3(AREA.x * 2.0, HEIGHT + 6.0, AREA.y * 2.0))
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.position = Vector3(0, HEIGHT, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.5, 0.2, AREA.y * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(wind.x * 1.6, -1.2, wind.y * 1.6)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.9
	pm.turbulence_noise_scale = 2.2
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	_snow_mat = pm
	_snow.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _dot_texture()
	mat.albedo_color = Color(0.97, 0.98, 1.0, 0.9)
	q.material = mat
	_snow.draw_pass_1 = q
	_rig.add_child(_snow)


func _dot_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) * 1.6))
	return ImageTexture.create_from_image(img)


# ---------- 风吹落叶 ----------

func set_leaves(l: int) -> void:
	leaves_level = clampi(l, 0, 4)
	if _leaves == null:
		return
	_leaves.emitting = leaves_level > 0
	_leaves.amount = maxi(LEAF_AMOUNT[maxi(leaves_level, 1)], 1)


func _build_leaves() -> void:
	_leaves = GPUParticles3D.new()
	_leaves.name = "Leaves"
	_leaves.amount = 100
	_leaves.lifetime = 7.0
	_leaves.local_coords = false
	_leaves.preprocess = _leaves.lifetime
	_leaves.emitting = false
	_leaves.visibility_aabb = AABB(Vector3(-AREA.x, -2.0, -AREA.y), Vector3(AREA.x * 2.0, HEIGHT + 6.0, AREA.y * 2.0))
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves.position = Vector3(0, HEIGHT * 0.7, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.5, 1.5, AREA.y * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(wind.x * 3.0, -0.9, wind.y * 3.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 1.4
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.80, 0.52, 0.20, 1))
	grad.set_color(1, Color(0.55, 0.28, 0.12, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	_leaves_mat = pm
	_leaves.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.46, 0.30)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _leaf_texture()
	q.material = mat
	_leaves.draw_pass_1 = q
	_rig.add_child(_leaves)


func _leaf_texture() -> ImageTexture:
	var w := 32
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var a := 1.0 if (u * u + (v * v) / 0.28) < 1.0 else 0.0
			var shade := 0.65 if absf(v) < 0.08 else 1.0   # 叶脉：中间一道略深
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return ImageTexture.create_from_image(img)


# ---------- 雾（屏幕空间，不用图）----------

func set_fog(l: int) -> void:
	fog_level = clampi(l, 0, 4)
	if _fog == null:
		return
	_fog.visible = fog_level > 0
	_fog_mat.set_shader_parameter("amount", FOG_ALPHA[fog_level])


const FOG_SHADER := """
shader_type canvas_item;
uniform float amount = 0.3;
uniform vec3 fog_col : source_color = vec3(0.78, 0.82, 0.86);
void fragment() {
	// 画面中心清楚、越靠边越浓；顶部（远处）比底部（近处）浓一点
	vec2 d = UV - vec2(0.5, 0.55);
	float r = clamp(length(d * vec2(1.0, 1.25)) * 1.5, 0.0, 1.0);
	float far = 1.0 - UV.y;
	float a = amount * (0.35 + 0.65 * smoothstep(0.15, 1.0, r)) * (0.75 + 0.5 * far);
	COLOR = vec4(fog_col, clamp(a, 0.0, 0.85));
}
"""


func _build_fog() -> void:
	_fog = ColorRect.new()
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.visible = false
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = sh
	_fog.material = _fog_mat
	_layer.add_child(_fog)
	_layer.move_child(_fog, 0)


# ---------- 云影（一大块贴地的滚动阴影）----------

func set_clouds(l: int) -> void:
	cloud_level = clampi(l, 0, 4)
	if _cloud == null:
		return
	_cloud.visible = cloud_level > 0
	_cloud_mat.set_shader_parameter("darkness", CLOUD_DARK[cloud_level])


const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float darkness = 0.2;
uniform vec2 drift = vec2(0.012, 0.004);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.018 + drift * TIME * 20.0;
	float c = texture(noise_tex, p).r * 0.65 + texture(noise_tex, p * 2.3 + vec2(0.37, 0.61)).r * 0.35;
	float shade = smoothstep(0.42, 0.70, c);
	ALBEDO = vec3(0.04, 0.06, 0.12);
	ALPHA = shade * darkness * 2.0;
}
"""


func _build_clouds() -> void:
	_cloud = MeshInstance3D.new()
	_cloud.name = "CloudShadow"
	var pl := PlaneMesh.new()
	pl.size = Vector2(120, 120)
	_cloud.mesh = pl
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = sh
	var fn := FastNoiseLite.new()
	fn.seed = 7
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.noise = fn
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	_cloud_mat.set_shader_parameter("noise_tex", nt)
	_cloud.material_override = _cloud_mat
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud.position = Vector3(0, 0.06, 0)
	_cloud.visible = false
	_rig.add_child(_cloud)
	set_wind(wind)


# ---------- 冰雹 ----------
# 比雨又快又短又白的小冰粒，落地弹起一小点白光；整体带一点冷色压暗。

func set_hail(l: int) -> void:
	hail_level = clampi(l, 0, 4)
	if _hail == null:
		return
	_hail.emitting = hail_level > 0
	_hail_bounce.emitting = hail_level > 0
	_hail.amount = maxi(HAIL_AMOUNT[maxi(hail_level, 1)], 1)
	_hail_bounce.amount = maxi(HAIL_BOUNCE[maxi(hail_level, 1)], 1)
	_update_dim()


func _build_hail() -> void:
	_hail = GPUParticles3D.new()
	_hail.name = "Hail"
	_hail.amount = 800
	_hail.lifetime = (HEIGHT + 2.0) / 30.0
	_hail.local_coords = false
	_hail.preprocess = _hail.lifetime
	_hail.emitting = false
	_hail.visibility_aabb = AABB(Vector3(-AREA.x, -2.0, -AREA.y), Vector3(AREA.x * 2.0, HEIGHT + 6.0, AREA.y * 2.0))
	_hail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hail.position = Vector3(0, HEIGHT, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.5, 0.2, AREA.y * 0.5)
	pm.direction = Vector3(wind.x * 0.5, -1.0, wind.y * 0.5).normalized()
	pm.spread = 2.5
	pm.initial_velocity_min = 27.0
	pm.initial_velocity_max = 33.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	_hail_mat = pm
	_hail.process_material = pm
	_hail.draw_pass_1 = _hail_mesh()
	_rig.add_child(_hail)

	# 落地弹起的小白点
	_hail_bounce = GPUParticles3D.new()
	_hail_bounce.name = "HailBounce"
	_hail_bounce.amount = 300
	_hail_bounce.lifetime = 0.38
	_hail_bounce.local_coords = false
	_hail_bounce.emitting = false
	_hail_bounce.visibility_aabb = AABB(Vector3(-AREA.x, -1.0, -AREA.y), Vector3(AREA.x * 2.0, 4.0, AREA.y * 2.0))
	_hail_bounce.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hail_bounce.position = Vector3(0, 0.08, 0)
	var bm := ParticleProcessMaterial.new()
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bm.emission_box_extents = Vector3(AREA.x * 0.5, 0.0, AREA.y * 0.5)
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 35.0
	bm.initial_velocity_min = 2.2
	bm.initial_velocity_max = 4.0
	bm.gravity = Vector3(0, -14.0, 0)
	bm.scale_min = 0.7
	bm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.95))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	bm.color_ramp = gt
	_hail_bounce.process_material = bm
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.13)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _dot_texture()
	q.material = mat
	_hail_bounce.draw_pass_1 = q
	_rig.add_child(_hail_bounce)


# 短粗的白色冰粒（十字交叉面片）
func _hail_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.05
	var h := 0.30
	for ang in [0.0, PI * 0.5]:
		var ax := Vector3(cos(ang), 0, sin(ang)) * w
		var a := -ax + Vector3(0, h * 0.5, 0)
		var b := ax + Vector3(0, h * 0.5, 0)
		var c := ax - Vector3(0, h * 0.5, 0)
		var d := -ax - Vector3(0, h * 0.5, 0)
		var top := Color(1, 1, 1, 1.0)
		var bot := Color(1, 1, 1, 0.15)
		st.set_color(top); st.add_vertex(a)
		st.set_color(top); st.add_vertex(b)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(top); st.add_vertex(a)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(bot); st.add_vertex(d)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.92, 0.96, 1.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


# ---------- 沙暴 ----------
# 贴着地面横着刮的沙粒和长沙线，加一层土黄色的雾和暖色压暗；风越大越斜越快。

func set_sandstorm(l: int) -> void:
	sand_level = clampi(l, 0, 4)
	if _sand == null:
		return
	_sand.emitting = sand_level > 0
	_sand.amount = maxi(SAND_AMOUNT[maxi(sand_level, 1)], 1)
	_sand_dust.emitting = sand_level > 0
	_sand_dust.amount = maxi(SAND_AMOUNT[maxi(sand_level, 1)], 1)
	_sand_haze.visible = sand_level > 0
	_sand_haze_mat.set_shader_parameter("amount", SAND_HAZE[sand_level])
	_sand_dim.visible = sand_level > 0
	_sand_dim.color = Color(0.30, 0.18, 0.07, 0.10 + 0.08 * sand_level)


func _sand_dir() -> Vector3:
	# 沙暴是横着吹的：整场沙都沿同一个方向（风向；没设风就默认往画面右边），沙线互相平行
	var w := wind if wind.length() > 0.05 else Vector2(1.0, 0.0)
	return Vector3(w.x, -0.04, w.y).normalized()


func _build_sand() -> void:
	_sand = GPUParticles3D.new()
	_sand.name = "Sand"
	_sand.amount = 1200
	_sand.lifetime = 2.4
	_sand.local_coords = false
	_sand.preprocess = _sand.lifetime
	_sand.emitting = false
	_sand.visibility_aabb = AABB(Vector3(-AREA.x * 1.3, -2.0, -AREA.y * 1.3), Vector3(AREA.x * 2.6, 10.0, AREA.y * 2.6))
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sand.position = Vector3(-AREA.x * 0.45 * _sand_dir().x, 3.0, -AREA.y * 0.45 * _sand_dir().z)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.6, 3.2, AREA.y * 0.6)
	pm.direction = _sand_dir()
	pm.spread = 0.6
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.15, Color(1, 1, 1, 0.9))
	grad.add_point(0.8, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var two := Gradient.new()
	two.set_color(0, Color(0.42, 0.27, 0.12, 1))   # 深褐
	two.set_color(1, Color(0.98, 0.92, 0.76, 1))   # 浅米
	two.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var two_t := GradientTexture1D.new()
	two_t.gradient = two
	pm.color_initial_ramp = two_t
	_sand_mat = pm
	_sand.process_material = pm
	_sand.draw_pass_1 = _sand_mesh()
	_rig.add_child(_sand)

	_sand_dust = GPUParticles3D.new()
	_sand_dust.name = "SandDust"
	_sand_dust.amount = 1500
	_sand_dust.lifetime = 2.6
	_sand_dust.local_coords = false
	_sand_dust.preprocess = _sand_dust.lifetime
	_sand_dust.emitting = false
	_sand_dust.visibility_aabb = _sand.visibility_aabb
	_sand_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sand_dust.position = _sand.position
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(AREA.x * 0.6, 3.2, AREA.y * 0.6)
	dm.direction = _sand_dir()
	dm.spread = 3.0
	dm.initial_velocity_min = 9.0
	dm.initial_velocity_max = 15.0
	dm.gravity = Vector3.ZERO
	dm.turbulence_enabled = true
	dm.turbulence_noise_strength = 0.5
	dm.turbulence_noise_scale = 1.2
	dm.scale_min = 0.8
	dm.scale_max = 2.4
	dm.color_ramp = gt
	dm.color_initial_ramp = two_t
	_sand_dust_mat = dm
	_sand_dust.process_material = dm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.10, 0.10)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = _dot_texture()
	dq.material = dmat
	_sand_dust.draw_pass_1 = dq
	_rig.add_child(_sand_dust)

	_sand_haze = ColorRect.new()
	_sand_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sand_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sand_haze.visible = false
	var sh := Shader.new()
	sh.code = FOG_SHADER
	_sand_haze_mat = ShaderMaterial.new()
	_sand_haze_mat.shader = sh
	_sand_haze_mat.set_shader_parameter("fog_col", Color(0.70, 0.52, 0.30))
	_sand_haze.material = _sand_haze_mat
	_layer.add_child(_sand_haze)
	_layer.move_child(_sand_haze, 0)
	_sand_dim = ColorRect.new()
	_sand_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sand_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sand_dim.visible = false
	_layer.add_child(_sand_dim)
	_layer.move_child(_sand_dim, 1)


# 细长的沙线（十字交叉面片，沿速度方向，一头淡一头实）
func _sand_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.022
	var h := 1.0
	for ang in [0.0, PI * 0.5]:
		var ax := Vector3(cos(ang), 0, sin(ang)) * w
		var a := -ax + Vector3(0, h * 0.5, 0)
		var b := ax + Vector3(0, h * 0.5, 0)
		var c := ax - Vector3(0, h * 0.5, 0)
		var d := -ax - Vector3(0, h * 0.5, 0)
		var top := Color(1, 1, 1, 0.9)
		var bot := Color(1, 1, 1, 0.0)
		st.set_color(top); st.add_vertex(a)
		st.set_color(top); st.add_vertex(b)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(top); st.add_vertex(a)
		st.set_color(bot); st.add_vertex(c)
		st.set_color(bot); st.add_vertex(d)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


# 冰雹时整体压暗一点（和雨共用压暗层，取较大值）
func _update_dim() -> void:
	var a: float = DIM_ALPHA[level]
	if hail_level > 0:
		a = maxf(a, 0.10 + 0.05 * hail_level)
	_dim.color = Color(0.10, 0.14, 0.24, a)
	_dim.visible = a > 0.0


# ---------- 寒冷滤镜 + 暴雪 ----------
# set_cold(n)：只是“冷”的滤镜——去一点色、整体偏冷蓝、微提对比，画面四周结一圈像素风的霜。可以单独用，也可以叠在雪 / 雾上。
# set_blizzard(n)：暴雪 = 沿风向横着吹的雪线 + 雪点 + 冷色雾 + 寒冷滤镜（档位越高越冷、越浓、越看不远）。

const BLIZZARD_AMOUNT := [0, 1800, 4200, 7000, 10500]
const COLD_AMOUNT := [0.0, 0.30, 0.50, 0.72, 0.92]
var cold_level := 0
var blizzard_level := 0
var _cold: ColorRect
var _cold_mat: ShaderMaterial
var _bliz: GPUParticles3D
var _bliz_mat: ParticleProcessMaterial
var _bliz_dust: GPUParticles3D
var _bliz_dust_mat: ParticleProcessMaterial
var _bliz_haze: ColorRect
var _bliz_haze_mat: ShaderMaterial

const COLD_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.5;
float hsh(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(c, vec3(l), 0.42 * amount);                                    // 去色
	g = mix(g, g * vec3(0.76, 0.91, 1.14) + vec3(0.0, 0.015, 0.05), amount);   // 偏冷蓝
	g = (g - 0.5) * (1.0 + 0.14 * amount) + 0.5 + 0.03 * amount;               // 微提对比
	// 四周结霜：像素风的粗颗粒，越靠边越多
	vec2 d = UV - 0.5;
	float r = length(d * vec2(1.0, 1.18));
	float v = smoothstep(0.36, 0.80, r);
	float n = hsh(floor(UV * vec2(128.0, 72.0)));
	float frost = clamp(v * (0.55 + 0.9 * n) * amount, 0.0, 1.0);
	g = mix(g, vec3(0.84, 0.93, 1.0), frost * 0.7);
	COLOR = vec4(g, 1.0);
}
"""


func set_cold(l: int) -> void:
	cold_level = clampi(l, 0, 4)
	_apply_cold()


# 寒冷滤镜的实际档位 = 单独设的档位 和 暴雪档位 取较大值（互不覆盖）
func _apply_cold() -> void:
	if _cold == null:
		return
	var n := maxi(cold_level, blizzard_level)
	_cold.visible = n > 0
	_cold_mat.set_shader_parameter("amount", COLD_AMOUNT[n])


func set_blizzard(l: int) -> void:
	blizzard_level = clampi(l, 0, 4)
	if _bliz == null:
		return
	var on := blizzard_level > 0
	_bliz.emitting = on
	_bliz_dust.emitting = on
	_bliz.amount = maxi(BLIZZARD_AMOUNT[maxi(blizzard_level, 1)], 1)
	_bliz_dust.amount = maxi(BLIZZARD_AMOUNT[maxi(blizzard_level, 1)], 1)
	_bliz_haze.visible = on
	_bliz_haze_mat.set_shader_parameter("amount", 0.22 + 0.16 * blizzard_level)
	_apply_cold()


func _bliz_dir() -> Vector3:
	var w := wind if wind.length() > 0.05 else Vector2(1.0, 0.15)
	return Vector3(w.x, -0.16, w.y).normalized()


func _build_cold() -> void:
	_cold = ColorRect.new()
	_cold.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cold.visible = false
	var sh := Shader.new()
	sh.code = COLD_SHADER
	_cold_mat = ShaderMaterial.new()
	_cold_mat.shader = sh
	_cold.material = _cold_mat
	_layer.add_child(_cold)
	_layer.move_child(_cold, 0)   # 放最下面：只给 3D 画面调色，雾和压暗叠在它上面


func _build_blizzard() -> void:
	_bliz = GPUParticles3D.new()
	_bliz.name = "Blizzard"
	_bliz.amount = 4000
	_bliz.lifetime = 2.2
	_bliz.local_coords = false
	_bliz.preprocess = _bliz.lifetime
	_bliz.emitting = false
	_bliz.visibility_aabb = AABB(Vector3(-AREA.x * 1.3, -2.0, -AREA.y * 1.3), Vector3(AREA.x * 2.6, 10.0, AREA.y * 2.6))
	_bliz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bliz.position = Vector3(0, 3.5, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA.x * 0.75, 3.6, AREA.y * 0.75)
	pm.direction = _bliz_dir()
	pm.spread = 1.5
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(0.92, 0.96, 1.0, 0.0))
	grad.add_point(0.15, Color(0.92, 0.96, 1.0, 0.85))
	grad.add_point(0.8, Color(0.88, 0.94, 1.0, 0.85))
	grad.set_color(1, Color(0.88, 0.94, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_bliz_mat = pm
	_bliz.process_material = pm
	_bliz.draw_pass_1 = _sand_mesh()
	_rig.add_child(_bliz)

	_bliz_dust = GPUParticles3D.new()
	_bliz_dust.name = "BlizzardFlakes"
	_bliz_dust.amount = 4000
	_bliz_dust.lifetime = 2.6
	_bliz_dust.local_coords = false
	_bliz_dust.preprocess = _bliz_dust.lifetime
	_bliz_dust.emitting = false
	_bliz_dust.visibility_aabb = _bliz.visibility_aabb
	_bliz_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bliz_dust.position = _bliz.position
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(AREA.x * 0.75, 3.6, AREA.y * 0.75)
	dm.direction = _bliz_dir()
	dm.spread = 6.0
	dm.initial_velocity_min = 8.0
	dm.initial_velocity_max = 14.0
	dm.gravity = Vector3(0, -1.5, 0)
	dm.turbulence_enabled = true
	dm.turbulence_noise_strength = 1.2
	dm.turbulence_noise_scale = 1.4
	dm.scale_min = 0.8
	dm.scale_max = 2.0
	dm.color_ramp = gt
	_bliz_dust_mat = dm
	_bliz_dust.process_material = dm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.12, 0.12)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.albedo_texture = _dot_texture()
	dq.material = dmat
	_bliz_dust.draw_pass_1 = dq
	_rig.add_child(_bliz_dust)

	_bliz_haze = ColorRect.new()
	_bliz_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bliz_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bliz_haze.visible = false
	var hs := Shader.new()
	hs.code = FOG_SHADER
	_bliz_haze_mat = ShaderMaterial.new()
	_bliz_haze_mat.shader = hs
	_bliz_haze_mat.set_shader_parameter("fog_col", Color(0.82, 0.90, 0.98))
	_bliz_haze.material = _bliz_haze_mat
	_layer.add_child(_bliz_haze)
	_layer.move_child(_bliz_haze, 1)
