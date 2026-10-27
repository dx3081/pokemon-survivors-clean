extends Node3D
# 场景布景：无边的草地 + 按区块撒的树、石头、灌木、草和花。
#
# 用法：
#   add_child(scenery)
#   scenery.setup(player)                 # 之后它自己跟着 player 建区块、拆区块、挪地面
#   scenery.blocked(pos, radius)          # 这个圆有没有压到树干或大石头
#   scenery.push_out(pos, radius)         # 附送：把压到障碍的位置推到障碍外面（想让怪绕着走时用）
#
# 做法：
#   - 世界切成 CHUNK 米见方的区块，区块坐标做种子，同一块地每次回来都长一样的东西
#   - 每个区块里每种物件一个 MultiMeshInstance3D，不给单个物件建节点
#   - 哪里是林子、哪里是空地，看一张可平铺的噪声图；地面着色器和撒点用的是同一张，所以土路上不长树
#   - 树叶贴图只管形状，颜色由着色器按高度从深到浅给；法线改成从树冠中心往外鼓，叶片才不会一片亮一片黑
#   - 挡在相机和主角之间的树、灌木会被打成网点透掉，主角不会被树冠盖住
#   - 每帧只做三件小事：挪地面、更新"主角在哪"给着色器、主角跨区块时排队建新区块（一帧最多建一块）

const CHUNK := 24.0            # 区块边长（米）
const LOAD_RING := 1           # 主角所在区块往外建几圈（1 = 3x3）
const KEEP_RING := 2           # 超过这么多圈才拆，免得在边界来回走时反复建拆
const WORLD_SEED := 20261013
const MASK_SIZE := 256         # 噪声图边长（像素）
const MASK_PERIOD := 128.0     # 噪声图铺多少米重复一次
const SPAWN_CLEAR := 7.0       # 出生点周围这么多米不放树和石头
const FADE_RADIUS := 1.8       # 相机到主角这条线周围多少米内的树要透掉
const MODEL_DIR := "res://assets/nature/models/"
const TEX_DIR := "res://assets/nature/textures/"

# 树叶 / 草的配色：low = 底部颜色，high = 顶部颜色
const PALETTES := {
	"leaf": [Color(0.15, 0.27, 0.12), Color(0.38, 0.50, 0.22)],
	"leaf_b": [Color(0.18, 0.29, 0.11), Color(0.46, 0.52, 0.24)],
	"autumn": [Color(0.50, 0.21, 0.10), Color(0.72, 0.46, 0.20)],
	"pine": [Color(0.08, 0.20, 0.14), Color(0.20, 0.36, 0.22)],
	"bush": [Color(0.13, 0.25, 0.12), Color(0.32, 0.45, 0.21)],
	"grass": [Color(0.24, 0.33, 0.15), Color(0.46, 0.56, 0.26)],
	"grass_dry": [Color(0.28, 0.32, 0.15), Color(0.56, 0.55, 0.28)],
}

# 物件表。s = 缩放范围；shadow = 投不投影子；pal = 叶子配色；block = 障碍半径（按缩放前算，0 = 不挡路）
# 原模型的树有 7 到 9 米高，缩到 5 到 6.5 米；草原本 1.3 米高，缩到小腿高，别挡住狼
const PROPS := {
	"tree_a": {"model": "CommonTree_1", "s": [0.72, 0.90], "shadow": true, "pal": "leaf", "block": 0.42},
	"tree_b": {"model": "CommonTree_2", "s": [0.70, 0.86], "shadow": true, "pal": "leaf_b", "block": 0.42},
	"tree_c": {"model": "CommonTree_3", "s": [0.56, 0.70], "shadow": true, "pal": "leaf", "block": 0.40},
	"tree_d": {"model": "CommonTree_5", "s": [0.76, 0.95], "shadow": true, "pal": "leaf_b", "block": 0.40},
	"tree_fall": {"model": "CommonTree_5", "s": [0.76, 0.95], "shadow": true, "pal": "autumn", "block": 0.40},
	"tree_fall_b": {"model": "CommonTree_2", "s": [0.68, 0.84], "shadow": true, "pal": "autumn", "block": 0.42},
	"pine_a": {"model": "Pine_1", "s": [0.74, 0.92], "shadow": true, "pal": "pine", "block": 0.40},
	"pine_b": {"model": "Pine_3", "s": [0.74, 0.92], "shadow": true, "pal": "pine", "block": 0.40},
	"bush": {"model": "Bush_Common", "s": [0.55, 0.85], "shadow": true, "pal": "bush", "block": 0.0},
	"bush_flower": {"model": "Bush_Common_Flowers", "s": [0.55, 0.85], "shadow": true, "pal": "bush", "block": 0.0},
	"rock_a": {"model": "Rock_Medium_1", "s": [0.38, 0.72], "shadow": true, "block": 1.25},
	"rock_b": {"model": "Rock_Medium_2", "s": [0.38, 0.72], "shadow": true, "block": 1.20},
	"rock_c": {"model": "Rock_Medium_3", "s": [0.36, 0.66], "shadow": true, "block": 1.35},
	"grass_a": {"model": "Grass_Common_Short", "s": [0.30, 0.50], "shadow": false, "pal": "grass", "block": 0.0},
	"grass_b": {"model": "Grass_Wispy_Short", "s": [0.34, 0.52], "shadow": false, "pal": "grass_dry", "block": 0.0},
	"fern": {"model": "Fern_1", "s": [0.15, 0.22], "shadow": false, "block": 0.0},
	"clover": {"model": "Clover_1", "s": [0.26, 0.36], "shadow": false, "block": 0.0},
	"plant": {"model": "Plant_7", "s": [0.7, 1.1], "shadow": false, "block": 0.0},
	"flower_a": {"model": "Flower_3_Group", "s": [0.26, 0.34], "shadow": false, "block": 0.0},
	"flower_b": {"model": "Flower_3_Single", "s": [0.26, 0.34], "shadow": false, "block": 0.0},
	"flower_c": {"model": "Flower_4_Group", "s": [0.22, 0.30], "shadow": false, "block": 0.0},
	"mushroom": {"model": "Mushroom_Common", "s": [0.8, 1.3], "shadow": false, "block": 0.0},
	"pebble_a": {"model": "Pebble_Round_1", "s": [0.8, 1.8], "shadow": false, "block": 0.0},
	"pebble_b": {"model": "Pebble_Round_3", "s": [0.8, 1.8], "shadow": false, "block": 0.0},
	"pebble_c": {"model": "Pebble_Square_1", "s": [0.8, 1.6], "shadow": false, "block": 0.0},
	"pebble_d": {"model": "Pebble_Square_4", "s": [0.8, 1.6], "shadow": false, "block": 0.0},
}
const TREES_GREEN := ["tree_a", "tree_b", "tree_c", "tree_d"]
const TREES_FALL := ["tree_fall", "tree_fall_b"]
const TREES_PINE := ["pine_a", "pine_b"]
const ROCKS := ["rock_a", "rock_b", "rock_c"]
const PEBBLES := ["pebble_a", "pebble_b", "pebble_c", "pebble_d"]
const FLOWERS := ["flower_a", "flower_b", "flower_c"]

# 一份着色器模板出三种材质：GRADIENT = 颜色按高度渐变（树叶、草）；CUTOUT = 按贴图透明度镂空、双面；
# 都不开 = 普通贴图实心物件（树干、石头、蘑菇）
const PROP_SHADER := """
shader_type spatial;
render_mode specular_disabled RENDER_MODE;
DEFINES
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 col_low : source_color = vec3(1.0);
uniform vec3 col_high : source_color = vec3(1.0);
uniform float y_low = 0.0;
uniform float y_high = 1.0;
uniform float round_normal = 0.0;   // 1 = 法线改成从中心往外鼓的球面法线
uniform float up_bias = 0.6;        // 球面法线往上偏多少，越大越像平地那样受光
uniform float sway = 0.0;           // 随风摆的幅度（模型单位），0 = 不摆
uniform float cutoff = 0.35;
uniform float fade_radius = 0.0;    // 0 = 不参与"挡主角就透掉"
uniform vec3 focus_pos;
uniform vec3 cam_pos;
varying vec3 wp;
varying vec3 wn;
varying float grad;
varying vec3 tint;

void vertex() {
	grad = clamp((VERTEX.y - y_low) / max(0.001, y_high - y_low), 0.0, 1.0);
	tint = INSTANCE_CUSTOM.rgb;
	float ph = INSTANCE_CUSTOM.a * 6.2832;
	vec3 centre = vec3(0.0, mix(y_low, y_high, 0.4), 0.0);
	vec3 ball = normalize(VERTEX - centre + vec3(0.0, up_bias * (y_high - y_low), 0.0));
	vec3 n = normalize(mix(NORMAL, ball, round_normal));
	VERTEX.xz += vec2(sin(TIME * 1.7 + ph + VERTEX.y * 0.8), cos(TIME * 1.3 + ph * 1.7)) * sway * grad * grad;
	wn = normalize(mat3(MODEL_MATRIX) * n);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(tex, UV);
#ifdef CUTOUT
	if (t.a < cutoff) discard;
#endif
	if (fade_radius > 0.0) {
		// 相机到主角连一条线，离这条线近、又在主角前面的像素按网点丢掉
		vec3 ab = focus_pos - cam_pos;
		float along = dot(wp - cam_pos, ab) / dot(ab, ab);
		float d = length(wp - (cam_pos + ab * clamp(along, 0.0, 1.0)));
		float cut = (1.0 - smoothstep(fade_radius * 0.55, fade_radius, d)) * smoothstep(0.97, 0.90, along) * 0.88;
		float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (cut > dither) discard;
	}
#ifdef GRADIENT
	ALBEDO = mix(col_low, col_high, grad) * tint;
#else
	ALBEDO = t.rgb * col_high * tint;
#endif
	NORMAL = normalize(mat3(VIEW_MATRIX) * wn);
	ROUGHNESS = 1.0;
}
"""


# 按地区换的贴图地面（data/biome_ground.gd）：一张可平铺的贴图按世界坐标铺，再混一层转了 90 度、换了尺度的自己，打散重复感。
const GROUND_TEX_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform float period = 128.0;
uniform float tile = 6.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float vary = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wp.xz / tile;
	vec3 a = texture(tex, uv).rgb;
	vec3 b = texture(tex, vec2(uv.y, -uv.x) * 0.37 + vec2(0.31, 0.77)).rgb;
	float m = texture(mask, wp.xz / period * 0.5).r;
	float v = texture(mask, wp.xz / period * 5.3 + vec2(0.37, 0.11)).r;
	ALBEDO = mix(a, b, smoothstep(0.35, 0.65, m) * 0.55) * tint * (1.0 + (v - 0.5) * vary);
	ROUGHNESS = 1.0;
}
"""

# 地面：草色 + 土路色，分界看噪声图；再叠两层细一点的噪声做深浅变化。按世界坐标算，地面网格怎么挪都不会滑
const GROUND_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform float period = 128.0;
uniform vec3 grass_a : source_color;
uniform vec3 grass_b : source_color;
uniform vec3 grass_wood : source_color;
uniform vec3 dirt_a : source_color;
uniform vec3 dirt_b : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wp.xz / period;
	float m = texture(mask, uv).r;
	float n1 = texture(mask, uv * 5.3 + vec2(0.37, 0.11)).r;
	float n2 = texture(mask, uv * 23.0 + vec2(0.71, 0.53)).r;
	float fine = n1 * 0.65 + n2 * 0.35;
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.3, 0.7, fine));
	grass = mix(grass, grass_wood, smoothstep(0.58, 0.85, m) * 0.7);
	vec3 dirt = mix(dirt_a, dirt_b, smoothstep(0.25, 0.75, fine));
	float edge = m + (fine - 0.5) * 0.10;
	ALBEDO = mix(dirt, grass, smoothstep(0.30, 0.37, edge));
	ROUGHNESS = 1.0;
}
"""

# 代码底色 + 绘画细节（data/biome_ground.gd 的 mix）：底色和平原一样按噪声在 a / b 间渐变，所以没有格子；
# 细节是一张灰度手绘图，用三个不同大小和朝向的采样平均后叠上去，不会出现重复的格子。
const GROUND_MIX_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float period = 128.0;
uniform float dtile = 6.0;
uniform float dstr = 0.6;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wp.xz / period;
	float n1 = texture(mask, uv * 5.3 + vec2(0.37, 0.11)).r;
	float n2 = texture(mask, uv * 23.0 + vec2(0.71, 0.53)).r;
	float fine = n1 * 0.65 + n2 * 0.35;
	vec3 base = mix(col_a, col_b, smoothstep(0.3, 0.7, fine));
	vec2 p = wp.xz / dtile;
	float d1 = texture(detail, p).r;
	float d2 = texture(detail, vec2(p.y, -p.x) * 0.61 + vec2(0.31, 0.77)).r;
	float d3 = texture(detail, p * 0.37 + vec2(0.53, 0.19)).r;
	float d = d1 * 0.6 + d2 * 0.25 + d3 * 0.15;
	d = 0.5 + (d - 0.5) * 1.5;
	ALBEDO = base * (1.0 + (d - 0.5) * 2.0 * dstr);
	ROUGHNESS = 1.0;
}
"""

# 混合多种材质（data/biome_ground.gd 的 blend）：a 铺满，b / c 用平原同款噪声一块块长出来，边界是软的。
# 每种材质各自再混一层转了 90 度、换了尺度的自己，打散重复。
const GROUND_BLEND_SHADER := """
shader_type spatial;
render_mode specular_disabled;
uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask : filter_linear_mipmap, repeat_enable;
uniform float period = 128.0;
uniform float tile_a = 7.0;
uniform float tile_b = 7.0;
uniform float tile_c = 7.0;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform vec3 tint_c : source_color = vec3(1.0);
uniform float thr = 0.5;
uniform float thr_c = 0.6;
uniform float soft = 0.15;
uniform float use_c = 0.0;
uniform float vary = 0.3;
uniform vec2 ofs = vec2(0.0);   // 每个地区一个不同的偏移，各地区花纹位置不一样
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec3 sample2(sampler2D t, float tl, float m) {
	vec2 uv = wp.xz / tl;
	vec3 a = texture(t, uv).rgb;
	vec3 b = texture(t, vec2(uv.y, -uv.x) * 0.37 + vec2(0.31, 0.77)).rgb;
	return mix(a, b, smoothstep(0.35, 0.65, m) * 0.5);
}
void fragment() {
	float m = texture(mask, wp.xz / period * 0.5 + ofs).r;
	float m2 = texture(mask, wp.xz / period * 0.5 + vec2(0.41, 0.17) + ofs).r;
	float n = texture(mask, wp.xz / period * 5.3 + vec2(0.37, 0.11) + ofs * 5.0).r;
	vec3 col = sample2(tex_a, tile_a, m) * tint_a;
	float rough = (texture(mask, wp.xz / period * 21.0 + vec2(0.13, 0.57)).r - 0.5) * 0.16;   // 细碎的噪声让交界参差不齐，不糊
	float wb = smoothstep(thr - soft, thr + soft, m + (n - 0.5) * 0.12 + rough);
	col = mix(col, sample2(tex_b, tile_b, m2) * tint_b, wb);
	if (use_c > 0.5) {
		float wc = smoothstep(thr_c - soft, thr_c + soft, m2 + (n - 0.5) * 0.12 + rough) * (1.0 - wb);
		col = mix(col, sample2(tex_c, tile_c, m) * tint_c, wc);
	}
	ALBEDO = col * (1.0 + (n - 0.5) * vary);
	ROUGHNESS = 1.0;
}
"""

const BiomeGround := preload("res://data/biome_ground.gd")
const BiomeDeco := preload("res://data/biome_deco.gd")
var deco_style := "sprite"      # 装饰物件的风格："model" 3D 模型 / "sprite" 像素牌子 / "off" 不加，见 data/biome_deco.gd
var biome := "plains"          # 本局地区（main.gd 出发时 set_biome）；平原 = 原来的程序地面
var _props_mode := "nature"    # 地面上长什么，见 data/biome_ground.gd 的 props
var _target: Node3D
var _ground: MeshInstance3D
var _mask := PackedByteArray()
var _mask_tex: ImageTexture
var _textures := {}
var _shaders := {}
var _meshes := {}              # 物件名 → 配好材质的 Mesh
var _fade_mats: Array[ShaderMaterial] = []
var _chunks := {}              # Vector2i → 区块节点
var _obstacles := {}           # Vector2i → PackedFloat32Array [x, z, r, x, z, r, ...]
var _queue: Array[Vector2i] = []
var _centre := Vector2i(999999, 999999)
var _max_block := 0.0


func setup(target: Node3D) -> void:
	_target = target
	if _ground == null:
		_build_mask()
		_build_ground()
		for id in PROPS:
			_meshes[id] = _load_prop(PROPS[id])
			_max_block = max(_max_block, PROPS[id]["block"] * PROPS[id]["s"][1])
	# 开局把周围一圈一次建完，之后才一帧一块慢慢补
	_refresh_chunks()
	while not _queue.is_empty():
		_build_chunk(_queue.pop_front())
	_follow()


func blocked(pos: Vector3, radius: float) -> bool:
	# 只查这个圆碰得到的区块（一般 1 块，压在边上时 2 到 4 块），每块里也就十来个障碍
	var reach := radius + _max_block
	var x0 := int(floor((pos.x - reach) / CHUNK))
	var x1 := int(floor((pos.x + reach) / CHUNK))
	var z0 := int(floor((pos.z - reach) / CHUNK))
	var z1 := int(floor((pos.z + reach) / CHUNK))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var obs: PackedFloat32Array = _obstacles.get(Vector2i(cx, cz), PackedFloat32Array())
			var i := 0
			while i < obs.size():
				var dx := pos.x - obs[i]
				var dz := pos.z - obs[i + 1]
				var rr := radius + obs[i + 2]
				if dx * dx + dz * dz < rr * rr:
					return true
				i += 3
	return false


func push_out(pos: Vector3, radius: float) -> Vector3:
	# 压到障碍就沿着圆心连线推出去；没压到原样返回。y 不动
	var reach := radius + _max_block
	var x0 := int(floor((pos.x - reach) / CHUNK))
	var x1 := int(floor((pos.x + reach) / CHUNK))
	var z0 := int(floor((pos.z - reach) / CHUNK))
	var z1 := int(floor((pos.z + reach) / CHUNK))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var obs: PackedFloat32Array = _obstacles.get(Vector2i(cx, cz), PackedFloat32Array())
			var i := 0
			while i < obs.size():
				var dx := pos.x - obs[i]
				var dz := pos.z - obs[i + 1]
				var rr := radius + obs[i + 2]
				var d2 := dx * dx + dz * dz
				if d2 < rr * rr:
					if d2 < 0.0001:
						dx = 1.0
						dz = 0.0
						d2 = 1.0
					var k := rr / sqrt(d2)
					pos.x = obs[i] + dx * k
					pos.z = obs[i + 1] + dz * k
				i += 3
	return pos


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_follow()
	var c := _chunk_of(_target.global_position)
	if c != _centre:
		_refresh_chunks()
	if not _queue.is_empty():
		_build_chunk(_queue.pop_front())


func _follow() -> void:
	var p := _target.global_position
	_ground.global_position = Vector3(snappedf(p.x, 4.0), 0.0, snappedf(p.z, 4.0))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var focus := p + Vector3(0, 1.0, 0)
		var cp := cam.global_position
		for m in _fade_mats:
			m.set_shader_parameter("focus_pos", focus)
			m.set_shader_parameter("cam_pos", cp)


# ---------- 地面和噪声图 ----------

func _build_mask() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = WORLD_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.022
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.45
	var img := noise.get_seamless_image(MASK_SIZE, MASK_SIZE)
	img.convert(Image.FORMAT_L8)
	_mask = img.get_data()
	img.generate_mipmaps()
	_mask_tex = ImageTexture.create_from_image(img)


func _mask_at(x: float, z: float) -> float:
	# 0 到 1：小于 0.33 左右是土路空地，大于 0.6 左右是林子
	var px := posmod(int(floor(x / MASK_PERIOD * MASK_SIZE)), MASK_SIZE)
	var pz := posmod(int(floor(z / MASK_PERIOD * MASK_SIZE)), MASK_SIZE)
	return _mask[pz * MASK_SIZE + px] / 255.0


func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	_ground.mesh = plane
	_ground.material_override = _ground_material()
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)


# 换地区：换地面贴图和物件，旧区块全拆了按新地区重建。
func set_biome(id: String) -> void:
	if id == biome:
		return
	biome = id
	if _ground == null:
		return
	_ground.material_override = _ground_material()
	for k in _chunks:
		(_chunks[k] as Node).queue_free()
	_chunks.clear()
	_obstacles.clear()
	_queue.clear()
	_centre = Vector2i(999999, 999999)
	if _target != null:
		_refresh_chunks()
		while not _queue.is_empty():
			_build_chunk(_queue.pop_front())
		_follow()


# 这类物件在当前地区长不长（none 什么都不长；rocks 只有石头 / 碎石；snow 只有松树 / 石头 / 碎石）
func _allows(kind: String) -> bool:
	match _props_mode:
		"none":
			return false
		"rocks":
			return kind == "rocks" or kind == "pebbles"
		"snow":
			return kind == "trees" or kind == "rocks" or kind == "pebbles"
	return true


func _ground_material() -> ShaderMaterial:
	_props_mode = "nature"
	if BiomeGround.has(biome):
		var e: Dictionary = BiomeGround.entry(biome)
		_props_mode = str(e.get("props", "nature"))
		var bl: Dictionary = BiomeGround.blend_of(biome)
		if not bl.is_empty():
			var ta := load(BiomeGround.blend_path(str(bl["a"]))) as Texture2D
			var tb := load(BiomeGround.blend_path(str(bl["b"]))) as Texture2D
			var has_c := bl.has("c")
			var tc := load(BiomeGround.blend_path(str(bl["c"]))) as Texture2D if has_c else ta
			if ta != null and tb != null and tc != null:
				var bsh := Shader.new()
				bsh.code = GROUND_BLEND_SHADER
				var bmat := ShaderMaterial.new()
				bmat.shader = bsh
				bmat.set_shader_parameter("mask", _mask_tex)
				bmat.set_shader_parameter("period", MASK_PERIOD)
				bmat.set_shader_parameter("tex_a", ta)
				bmat.set_shader_parameter("tex_b", tb)
				bmat.set_shader_parameter("tex_c", tc)
				for k in ["a", "b", "c"]:
					bmat.set_shader_parameter("tile_" + k, float(bl.get("tile_" + k, 7.0)))
					var tv := float(bl.get("tint_" + k, 1.0))
					bmat.set_shader_parameter("tint_" + k, Color(tv, tv, tv))
				bmat.set_shader_parameter("thr", float(bl.get("thr", 0.5)))
				bmat.set_shader_parameter("thr_c", float(bl.get("thr_c", float(bl.get("thr", 0.5)) + 0.08)))
				bmat.set_shader_parameter("soft", float(bl.get("soft", 0.15)))
				bmat.set_shader_parameter("use_c", 1.0 if has_c else 0.0)
				bmat.set_shader_parameter("vary", float(bl.get("vary", 0.3)))
				var hh: int = absi(biome.hash())
				bmat.set_shader_parameter("ofs", Vector2(float(hh % 997) / 997.0, float((hh / 997) % 991) / 991.0))
				return bmat
		var mx: Dictionary = BiomeGround.mix_of(biome)
		if not mx.is_empty():
			var dtex := load(BiomeGround.detail_path(biome)) as Texture2D
			if dtex != null:
				var msh := Shader.new()
				msh.code = GROUND_MIX_SHADER
				var mmat := ShaderMaterial.new()
				mmat.shader = msh
				mmat.set_shader_parameter("mask", _mask_tex)
				mmat.set_shader_parameter("detail", dtex)
				mmat.set_shader_parameter("period", MASK_PERIOD)
				mmat.set_shader_parameter("dtile", float(mx.get("dtile", 6.0)))
				mmat.set_shader_parameter("dstr", float(mx.get("dstr", 0.6)))
				mmat.set_shader_parameter("col_a", mx["a"])
				mmat.set_shader_parameter("col_b", mx["b"])
				return mmat
		var tex := load(BiomeGround.path_of(biome)) as Texture2D
		if tex != null:
			var tsh := Shader.new()
			tsh.code = GROUND_TEX_SHADER
			var tmat := ShaderMaterial.new()
			tmat.shader = tsh
			tmat.set_shader_parameter("tex", tex)
			tmat.set_shader_parameter("mask", _mask_tex)
			tmat.set_shader_parameter("period", MASK_PERIOD)
			tmat.set_shader_parameter("tile", float(e.get("tile", 6.0)))
			var tn := float(e.get("tint", 1.0))
			tmat.set_shader_parameter("tint", Color(tn, tn, tn))
			tmat.set_shader_parameter("vary", float(e.get("vary", 0.0)))
			return tmat
	return _procedural_ground_material()


func _procedural_ground_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask", _mask_tex)
	mat.set_shader_parameter("period", MASK_PERIOD)
	mat.set_shader_parameter("grass_a", Color(0.26, 0.34, 0.17))
	mat.set_shader_parameter("grass_b", Color(0.31, 0.39, 0.19))
	mat.set_shader_parameter("grass_wood", Color(0.20, 0.29, 0.15))
	mat.set_shader_parameter("dirt_a", Color(0.44, 0.38, 0.27))
	mat.set_shader_parameter("dirt_b", Color(0.49, 0.42, 0.30))
	return mat


# ---------- 模型和材质 ----------

func _tex(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load(TEX_DIR + file + ".png")
	return _textures[file]


func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		var defines := ""
		var mode := ""
		if kind == "gradient":
			defines = "#define GRADIENT\n#define CUTOUT\n"
			mode = ", cull_disabled"
		elif kind == "cutout":
			defines = "#define CUTOUT\n"
			mode = ", cull_disabled"
		sh.code = PROP_SHADER.replace("DEFINES", defines).replace("RENDER_MODE", mode)
		_shaders[kind] = sh
	return _shaders[kind]


func _load_prop(def: Dictionary) -> Mesh:
	var scene: PackedScene = load(MODEL_DIR + def["model"] + ".gltf")
	var inst := scene.instantiate()
	var mi: MeshInstance3D = inst if inst is MeshInstance3D else inst.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: ArrayMesh = mi.mesh.duplicate()
	inst.free()
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var mat_name := src.resource_name if src != null else ""
		var mat := ShaderMaterial.new()
		# 这一面的高度范围，渐变和球面法线都要用
		var lo := INF
		var hi := -INF
		for v: Vector3 in mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
			lo = min(lo, v.y)
			hi = max(hi, v.y)
		mat.set_shader_parameter("y_low", lo)
		mat.set_shader_parameter("y_high", hi)
		match mat_name:
			"Leaves_NormalTree", "Leaves_Pine", "Leaves_TwistedTree":
				# 树叶和灌木：贴图只取形状，颜色走配色表
				var file: String = {"Leaves_NormalTree": "Leaves_NormalTree_C", "Leaves_Pine": "Leaf_Pine_C", "Leaves_TwistedTree": "Leaves_TwistedTree_C"}[mat_name]
				var pal: Array = PALETTES[def["pal"]]
				mat.shader = _shader("gradient")
				mat.set_shader_parameter("tex", _tex(file))
				mat.set_shader_parameter("col_low", pal[0])
				mat.set_shader_parameter("col_high", pal[1])
				mat.set_shader_parameter("round_normal", 1.0)
				mat.set_shader_parameter("up_bias", 0.35)
				mat.set_shader_parameter("sway", 0.05)
				mat.set_shader_parameter("fade_radius", FADE_RADIUS)
			"Grass":
				var pal: Array = PALETTES[def["pal"]]
				mat.shader = _shader("gradient")
				mat.set_shader_parameter("tex", _tex("Grass"))
				mat.set_shader_parameter("col_low", pal[0])
				mat.set_shader_parameter("col_high", pal[1])
				mat.set_shader_parameter("cutoff", 0.0)
				mat.set_shader_parameter("round_normal", 1.0)
				mat.set_shader_parameter("up_bias", 3.0)
				mat.set_shader_parameter("sway", 0.10)
			"Leaves", "Flowers":
				# 花、蕨、三叶草：贴图本身带颜色，照用；法线朝上，受光和地面一致
				mat.shader = _shader("cutout")
				mat.set_shader_parameter("tex", _tex(mat_name))
				mat.set_shader_parameter("round_normal", 1.0)
				mat.set_shader_parameter("up_bias", 3.0)
				mat.set_shader_parameter("sway", 0.04)
			"Bark_NormalTree":
				mat.shader = _shader("solid")
				mat.set_shader_parameter("tex", _tex("Bark_NormalTree"))
				mat.set_shader_parameter("fade_radius", FADE_RADIUS)
			"Rocks":
				mat.shader = _shader("solid")
				mat.set_shader_parameter("tex", _tex("Rocks_Diffuse"))
			"PathRocks":
				mat.shader = _shader("solid")
				mat.set_shader_parameter("tex", _tex("PathRocks_Diffuse"))
			"Mushrooms":
				mat.shader = _shader("solid")
				mat.set_shader_parameter("tex", _tex("Mushrooms"))
			_:
				push_warning("scenery: 没见过的材质名 %s（%s）" % [mat_name, def["model"]])
				mat.shader = _shader("solid")
		if mat.get_shader_parameter("fade_radius") != null:
			_fade_mats.append(mat)
		mesh.surface_set_material(i, mat)
	return mesh


# ---------- 区块 ----------

func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))


func _refresh_chunks() -> void:
	_centre = _chunk_of(_target.global_position)
	for key: Vector2i in _chunks.keys():
		if max(abs(key.x - _centre.x), abs(key.y - _centre.y)) > KEEP_RING:
			_chunks[key].queue_free()
			_chunks.erase(key)
			_obstacles.erase(key)
	_queue.clear()
	for dx in range(-LOAD_RING, LOAD_RING + 1):
		for dz in range(-LOAD_RING, LOAD_RING + 1):
			var key := _centre + Vector2i(dx, dz)
			if not _chunks.has(key):
				_queue.append(key)
	# 离主角近的先建
	var here := Vector2(_target.global_position.x, _target.global_position.z) / CHUNK - Vector2(0.5, 0.5)
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(here) < Vector2(b).distance_squared_to(here))


func _build_chunk(key: Vector2i) -> void:
	if _chunks.has(key):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, WORLD_SEED))
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var items := {}                       # 物件名 → [Transform3D, Color, ...]
	var obs := PackedFloat32Array()

	# 树：6 米一格，每格最多一棵，林子里多、草地上偶尔一棵、土路上没有
	var cell := 6.0
	var n := int(CHUNK / cell) if _allows("trees") else 0
	for ix in n:
		for iz in n:
			var x := ox + (ix + rng.randf_range(0.18, 0.82)) * cell
			var z := oz + (iz + rng.randf_range(0.18, 0.82)) * cell
			var roll := rng.randf()
			var kind := rng.randf()
			var pick := rng.randi()
			var m := _mask_at(x, z)
			if m < 0.40 or Vector2(x, z).length() < SPAWN_CLEAR:
				continue
			if roll > 0.05 + 0.45 * smoothstep(0.52, 0.74, m):
				continue
			# 另取一处噪声决定这一片是绿树、秋色还是松树，同一片林子树种大致一样
			var zone := _mask_at(x * 0.5 + 300.0, z * 0.5 + 170.0)
			var group: Array = TREES_GREEN
			if zone > 0.60 and kind < 0.8:
				group = TREES_FALL
			elif zone < 0.40 and kind < 0.8:
				group = TREES_PINE
			if _props_mode == "snow":
				group = TREES_PINE
			var id: String = group[pick % group.size()]
			var s := _put(items, id, rng, x, z)
			obs.append_array([x, z, PROPS[id]["block"] * s])
			# 树脚下偶尔长几朵蘑菇、一丛蕨
			if rng.randf() < 0.35:
				for k in rng.randi_range(1, 3):
					var a := rng.randf() * TAU
					var r := rng.randf_range(0.6, 1.1)
					_put(items, "mushroom", rng, x + cos(a) * r, z + sin(a) * r)
			if rng.randf() < 0.5:
				var a := rng.randf() * TAU
				_put(items, "fern", rng, x + cos(a) * 1.3, z + sin(a) * 1.3)

	# 大石头：每块 2 到 4 次机会，躲开树和出生点；旁边带几颗碎石
	for i in (rng.randi_range(2, 4) if _allows("rocks") else 0):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var id: String = ROCKS[rng.randi() % ROCKS.size()]
		var lo: float = PROPS[id]["s"][0]
		var hi: float = PROPS[id]["s"][1]
		var s := rng.randf_range(lo, hi)
		var r: float = PROPS[id]["block"] * s
		var extra := rng.randi_range(2, 5)
		if Vector2(x, z).length() < SPAWN_CLEAR + r or _hits(obs, x, z, r + 0.8):
			continue
		_put(items, id, rng, x, z, s)
		obs.append_array([x, z, r])
		for k in extra:
			var a := rng.randf() * TAU
			var d := r + rng.randf_range(0.2, 1.2)
			_put(items, PEBBLES[rng.randi() % PEBBLES.size()], rng, x + cos(a) * d, z + sin(a) * d)

	# 灌木：喜欢林子边上
	for i in (10 if _allows("bush") else 0):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var roll := rng.randf()
		var flowered := rng.randf() < 0.35
		var m := _mask_at(x, z)
		if m < 0.42 or roll > 0.25 + 0.5 * smoothstep(0.45, 0.6, m):
			continue
		if Vector2(x, z).length() < SPAWN_CLEAR or _hits(obs, x, z, 0.9):
			continue
		_put(items, "bush_flower" if flowered else "bush", rng, x, z)

	# 草：一平米一次半机会，土路上稀、草地和林子里密
	for i in (int(CHUNK * CHUNK * 1.6) if _allows("cover") else 0):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var roll := rng.randf()
		var wispy := rng.randf() < 0.3
		var m := _mask_at(x, z)
		if roll > 0.04 + 0.62 * smoothstep(0.30, 0.42, m):
			continue
		_put(items, "grass_b" if wispy else "grass_a", rng, x, z)

	# 花：一簇一簇地长，一簇一个品种
	for i in (rng.randi_range(3, 6) if _allows("flowers") else 0):
		var cx := ox + rng.randf() * CHUNK
		var cz := oz + rng.randf() * CHUNK
		var id: String = FLOWERS[rng.randi() % FLOWERS.size()]
		var count := rng.randi_range(4, 10)
		var spread := rng.randf_range(1.2, 2.6)
		if _mask_at(cx, cz) < 0.36:
			continue
		for k in count:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * spread
			_put(items, id, rng, cx + cos(a) * d, cz + sin(a) * d)

	# 三叶草、小叶片：零散地铺一点
	for i in (26 if _allows("cover") else 0):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var id := "clover" if rng.randf() < 0.5 else "plant"
		if _mask_at(x, z) < 0.38:
			continue
		_put(items, id, rng, x, z)

	# 碎石：土路上多一些
	for i in (30 if _allows("pebbles") else 0):
		var x := ox + rng.randf() * CHUNK
		var z := oz + rng.randf() * CHUNK
		var roll := rng.randf()
		var id: String = PEBBLES[rng.randi() % PEBBLES.size()]
		if roll > (0.75 if _mask_at(x, z) < 0.34 else 0.15):
			continue
		_put(items, id, rng, x, z)

	_place_deco(items, key, ox, oz, obs)

	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [key.x, key.y]
	for id: String in items:
		var list: Array = items[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[id]
		mm.instance_count = list.size() / 2
		for i in mm.instance_count:
			mm.set_instance_transform(i, list[i * 2])
			mm.set_instance_custom_data(i, list[i * 2 + 1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = id
		mmi.multimesh = mm
		var casts: bool = bool(PROPS[id]["shadow"]) if PROPS.has(id) else bool(BiomeDeco.def_of(id).get("shadow", false))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	add_child(node)
	_chunks[key] = node
	_obstacles[key] = obs


# 这个地区的装饰物件（data/biome_deco.gd）。用单独的随机数种子，不扰乱上面树 / 石头 / 草的摆放；
# 全是装饰：不挡路、不进障碍表。
func _place_deco(items: Dictionary, key: Vector2i, ox: float, oz: float, obs: PackedFloat32Array) -> void:
	if deco_style == "off":
		return
	var list: Array = BiomeDeco.list_for(biome, deco_style)
	if list.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, WORLD_SEED + 777))
	for e: Dictionary in list:
		var id: String = e["id"]
		var n: float = float(e.get("n", 1.0)) * BiomeDeco.DENSITY
		var cnt := int(n) + (1 if rng.randf() < n - floorf(n) else 0)
		var clear: float = float(e.get("clear", 8.0))
		for i in cnt:
			var x := ox + rng.randf() * CHUNK
			var z := oz + rng.randf() * CHUNK
			if Vector2(x, z).length() < clear:
				continue
			if e.has("mask"):
				var m := _mask_at(x, z)
				if m < float(e["mask"][0]) or m > float(e["mask"][1]):
					continue
			if _hits(obs, x, z, 0.8):
				continue
			if e.has("group"):
				var g: Array = e["group"]
				var spread: float = float(e.get("spread", 1.6))
				for k in rng.randi_range(int(g[0]), int(g[1])):
					var a := rng.randf() * TAU
					var d := sqrt(rng.randf()) * spread
					_put_deco(items, id, rng, x + cos(a) * d, z + sin(a) * d, float(e.get("tint", 1.0)))
			else:
				_put_deco(items, id, rng, x, z, float(e.get("tint", 1.0)))


func _put_deco(items: Dictionary, id: String, rng: RandomNumberGenerator, x: float, z: float, tint := 1.0) -> void:
	var def: Dictionary = BiomeDeco.def_of(id)
	if not _meshes.has(id):
		_meshes[id] = BiomeDeco.build_mesh(id)
	var sr: Array = def.get("s", [0.85, 1.15])
	var s := rng.randf_range(float(sr[0]), float(sr[1]))
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
	var shade := rng.randf_range(0.92, 1.06)
	if not items.has(id):
		items[id] = []
	items[id].append(Transform3D(basis, Vector3(x, 0.0, z)))
	items[id].append(Color(shade * tint, shade * tint, shade * tint, rng.randf()))


func _put(items: Dictionary, id: String, rng: RandomNumberGenerator, x: float, z: float, forced_scale := 0.0) -> float:
	# 记一个物件：随机朝向、随机大小、颜色深浅略有不同（rgb）、摆动相位（a）。返回用的缩放
	var def: Dictionary = PROPS[id]
	var lo: float = def["s"][0]
	var hi: float = def["s"][1]
	var s := rng.randf_range(lo, hi)
	if forced_scale > 0.0:
		s = forced_scale
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
	var shade := rng.randf_range(0.88, 1.08)
	var warm := rng.randf_range(-0.05, 0.05)
	if not items.has(id):
		items[id] = []
	items[id].append(Transform3D(basis, Vector3(x, 0.0, z)))
	items[id].append(Color(shade + warm, shade, shade - warm, rng.randf()))
	return s


func _hits(obs: PackedFloat32Array, x: float, z: float, r: float) -> bool:
	var i := 0
	while i < obs.size():
		var rr := r + obs[i + 2]
		if (x - obs[i]) * (x - obs[i]) + (z - obs[i + 1]) * (z - obs[i + 1]) < rr * rr:
			return true
		i += 3
	return false
