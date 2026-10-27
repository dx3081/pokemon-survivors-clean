extends Node3D
# 特效：买来的 2D 序列帧图集贴在不受光的透明面片上播。挂在场景根下（原点、不旋转不缩放）就能用。
# 所有特效都从对象池里拿面片，同一种特效共用一份材质，每个面片只靠“实例参数”区分当前帧和颜色，
# 所以一秒几十个受击 / 死亡 / 捡球也不会新建节点和材质。
# 播放走 _process 的 delta：三选一时 Engine.time_scale = 0，delta 是 0，特效自然停住。
#
# 对外的函数：slash / hit / death / pickup / level_up / make_shield / flash / blood / sword_strike / fist

enum SlashStyle { BLUE, GOLD, WIND, RIBBON }

## 刀光的样子：BLUE 冰蓝月刃（默认）、GOLD 金色弦月、WIND 青绿风刃、RIBBON 主项目自己的银色飘带刀光
@export var slash_style: SlashStyle = SlashStyle.BLUE
## 刀光下面垫一层很淡的扇形，标出真正能砍到的范围；0 = 不垫。RIBBON 不垫（主项目的刀光本来就只有一条飘带）
@export_range(0.0, 1.0) var slash_area_alpha := 0.10
## 受击溅血后要不要在地上留一小滩
@export var blood_splat := true

const FX_DIR := "res://assets/fx/"

# 刀光图集是“摊平”的长条：横轴 = 扇形角度，纵轴 = 半径，从内圈 RHO0 到外圈 RHO1（1.0 = 砍击半径）
const SLASH_RHO0 := 0.40
const SLASH_RHO1 := 1.12
# frames = 帧数；fps = 播放速度；add = 加色混合；flip = 左右翻转（网格的 U 从 -X 一侧到 +X 一侧，翻转后反过来）；
# underlay = false：这一种不垫底下那层扇形；
# scale = 整体再放大多少（原画的月牙比拟合出来的外沿小一圈时用）
const SLASH_STYLES := [
	{"sheet": "slash_blue", "frames": 9, "fps": 30.0, "add": false, "flip": true, "scale": 1.12, "area": Color(0.6, 0.9, 1.0)},
	{"sheet": "slash_gold", "frames": 6, "fps": 24.0, "add": false, "flip": false, "scale": 1.0, "area": Color(1.0, 0.85, 0.4)},
	{"sheet": "slash_wind", "frames": 5, "fps": 20.0, "add": false, "flip": true, "scale": 1.0, "area": Color(0.6, 1.0, 0.6)},
	# 主项目的刀光（CombatVfxStyle.Blade，代码画的银白飘带，烤成图集）。飘带在图集里从 U=0 长到 U=1；
	# 主角的横扫（Slash_H_A）是先把刀收到左肩、再从左手边（朝 +Z 时的 +X）扫到右手边（-X），所以要翻转
	{"sheet": "slash_ribbon", "frames": 10, "fps": 40.0, "add": false, "flip": true, "scale": 1.0, "area": Color(0.97, 0.985, 1.0), "underlay": false},
]

# 普通序列。cols/rows = 图集格子；size = 一格在世界里的宽（米）；pivot = 格子里哪一点对准给定位置（左上是 0,0）；
# billboard = 始终正对相机；nodepth = 不被模型挡住；max = 池子上限，超了就回收最早的那个
# 受击 / 倒地尘土 / 护盾 / 溅血是主项目（主神模拟器2）VfxKit 里已经接好的同一批图集，帧率、混合方式、锚点照搬。
const CLIPS := {
	"hit": {"sheet": "hit", "cols": 5, "rows": 1, "frames": 5, "fps": 30.0, "size": 1.2, "pivot": Vector2(0.5, 0.5),
		"billboard": true, "nodepth": true, "max": 48},
	"dust_sweep": {"sheet": "dust_sweep", "cols": 6, "rows": 2, "frames": 8, "fps": 14.0, "size": 2.4, "pivot": Vector2(0.5, 0.66),
		"billboard": true, "max": 32},
	"dust_ring": {"sheet": "dust_ring", "cols": 6, "rows": 1, "frames": 6, "fps": 14.0, "size": 2.4, "pivot": Vector2(0.5, 0.66),
		"billboard": true, "max": 32},
	"pickup": {"sheet": "hit", "cols": 5, "rows": 1, "frames": 5, "fps": 30.0, "size": 0.8, "pivot": Vector2(0.5, 0.5),
		"billboard": true, "add": true, "palette": [Color(0.0, 0.25, 0.45), Color(0.75, 1.0, 1.0)], "max": 32},
	"levelup": {"sheet": "levelup", "cols": 6, "rows": 3, "frames": 18, "fps": 15.0, "size": 4.2, "pivot": Vector2(0.5, 0.80),
		"billboard": true, "max": 2},
	# 血是灰白素材，用主项目的 blood 调色板（暗 #2a0306 → 亮 #c8202a）上色
	"blood": {"sheet": "blood", "cols": 4, "rows": 3, "frames": 10, "fps": 20.0, "size": 1.8, "pivot": Vector2(0.22, 0.53),
		"palette": [Color("2a0306"), Color("c8202a")], "max": 48},
	"splat": {"sheet": "blood", "cols": 4, "rows": 3, "frames": 10, "fps": 20.0, "size": 1.5, "pivot": Vector2(0.22, 0.53),
		"palette": [Color("1c0204"), Color("7a1018")], "max": 48},
	# 天降拳风（主项目 CombatVfx.Fist.cs 的 DrawFallingFist，代码画的，烤成图集）。size 是砸出 FIST_NATIVE_RADIUS 那么大的圈时的尺寸，
	# 用的时候按半径整体缩放。拳风竖着正对相机、不被模型挡（主项目里它本来就是盖在画面最上面的一层）；落地圈平铺在地上。
	"fist_wind": {"sheet": "fist_wind", "cols": 8, "rows": 2, "frames": 16, "fps": 40.0, "size": 300.0 / 180.0, "pivot": Vector2(0.5, 278.5 / 320.0),
		"billboard": true, "nodepth": true, "max": 12},
	"fist_ground": {"sheet": "fist_ground", "cols": 5, "rows": 3, "frames": 13, "fps": 30.0, "size": 460.0 / 180.0, "pivot": Vector2(0.5, 0.5),
		"max": 12},
}

# 剑气（主项目 CombatVfx.Weapons.cs 的 DrawWeaponFan，“三道剑气”里中间那一道，代码画的，烤成图集）。
# 图集一帧是 512×64 的长条：横向 = 沿剑气方向，盖住起点前 24 到命中点后 36（单位：主项目的屏幕像素，180 像素 = 1 米，
const SWORD := {"sheet": "sword_ray", "frames": 16, "fps": 40.0}
const SWORD_Z0 := -24.0 / 756.0   # 网格沿剑气方向的范围，1.0 = 剑气长度
const SWORD_Z1 := 792.0 / 756.0
const SWORD_HALF := 51.0 / 180.0  # 原始比例下一格的半宽（米）
## 剑气横向放大多少。原画很细（最粗处约 0.13 米），真实命中宽 1.2 米；1.0 = 原样
@export_range(1.0, 4.0) var sword_widen := 2.0

# 天降拳风：主项目里拳风从命中前 0.2 秒开始往下落（落差 250 像素，先慢后快），命中后地上一圈震波扩到 190 像素
const FIST_DELAY := 0.2
const FIST_NATIVE_RADIUS := 190.0 / 180.0
const FIST_DROP := 250.0 / 180.0

const SHIELD := {"sheet": "shield", "cols": 6, "rows": 2, "frames": 10, "fps": 14.0}
const SHIELD_RADIUS := 1.2       # 护盾圈的半径（米）
const SHIELD_RING_IN_CELL := 0.25  # 图集里那个圈的半径占一格宽度的比例
const FLASH_HOLD := 0.4          # 闪白：前 40% 时间保持全白，后面淡出（主项目是保持 0.05 秒 + 淡出 0.07 秒）


class Shot:
	var node: MeshInstance3D
	var kind := ""
	var age := 0.0
	var fps := 20.0
	var frames := 1
	var first := 0           # 起始帧
	var life := 0.0          # 总时长
	var fade_from := -1.0    # 从第几秒开始淡出；负数 = 不淡出
	var color := Color.WHITE
	var follow: Node3D
	var offset := Vector3.ZERO
	var drop := Vector3.ZERO     # 下落：开始时离落点多远（世界坐标的位移）
	var drop_time := 0.0         # 落到位要几秒；0 = 不下落
	var base := Vector3.ZERO     # 下落的终点


var _shots: Array[Shot] = []
var _free := {}          # kind -> Array[MeshInstance3D]
var _made := {}          # kind -> 已经造了几个
var _mats := {}          # kind -> ShaderMaterial
var _meshes := {}        # kind -> QuadMesh
var _slash_mats: Array[ShaderMaterial] = []
var _arc_meshes := {}    # 角度（整数度）-> 扇环网格
var _fan_meshes := {}    # 角度（整数度）-> 实心扇形网格
var _fan_mat: ShaderMaterial
var _sword_mat: ShaderMaterial
var _sword_mesh: ArrayMesh
var _shield_mat: ShaderMaterial
var _shields: Array[Dictionary] = []
var _flash_mat: ShaderMaterial
var _sword_flip := false
var _flashes := {}       # 模型的实例 id -> {"meshes": [...], "age": 秒, "dur": 秒}


func _ready() -> void:
	for kind: String in CLIPS:
		var c: Dictionary = CLIPS[kind]
		var m := _sheet_material(c["sheet"], c["cols"], c["rows"], c.get("add", false), c.get("billboard", false), c.get("nodepth", false))
		if c.has("palette"):
			m.set_shader_parameter("use_palette", true)
			m.set_shader_parameter("pal_dark", c["palette"][0])
			m.set_shader_parameter("pal_light", c["palette"][1])
		m.render_priority = 3 if c.get("nodepth", false) else 2
		_mats[kind] = m
		var q := QuadMesh.new()
		var tex: Texture2D = m.get_shader_parameter("sheet")
		var w: float = c["size"]
		var h: float = w * (float(tex.get_height()) / c["rows"]) / (float(tex.get_width()) / c["cols"])
		var pv: Vector2 = c["pivot"]
		q.size = Vector2(w, h)
		q.center_offset = Vector3((0.5 - pv.x) * w, (pv.y - 0.5) * h, 0)
		_meshes[kind] = q
		_free[kind] = []
		_made[kind] = 0
	for s: Dictionary in SLASH_STYLES:
		var m := _sheet_material(s["sheet"], 1, s["frames"], s["add"], false, false)
		m.render_priority = 1
		_slash_mats.append(m)
	_free["slash"] = []
	_made["slash"] = 0
	_free["fan"] = []
	_made["fan"] = 0
	_fan_mat = ShaderMaterial.new()
	_fan_mat.shader = Shader.new()
	_fan_mat.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;
instance uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	// UV.x = 离主角的距离（0 在脚下，1 在刀尖）：越靠外越亮，最外面留一条细边
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.35 + 0.65 * UV.x * UV.x + 1.5 * smoothstep(0.96, 1.0, UV.x));
}
"""
	_sword_mat = _sheet_material(SWORD["sheet"], 1, SWORD["frames"], false, false, false)
	_sword_mat.render_priority = 1
	_sword_mesh = _build_strip(SWORD_Z0, SWORD_Z1, SWORD_HALF)
	_free["sword"] = []
	_made["sword"] = 0
	_shield_mat = _sheet_material(SHIELD["sheet"], SHIELD["cols"], SHIELD["rows"], true, true, false)
	_shield_mat.render_priority = 2
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = Shader.new()
	_flash_mat.shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix;
instance uniform float fx_flash = 0.0;
instance uniform vec4 fx_flash_color : source_color = vec4(1.0);
void vertex() {
	// 往外鼓一点点，免得和底下的模型抢深度出黑点
	VERTEX += NORMAL * 0.004;
}
void fragment() {
	ALBEDO = fx_flash_color.rgb;
	ALPHA = fx_flash * fx_flash_color.a;
}
"""


# ---------------------------------------------------------------- 对外的函数

## 挥刀：主角面前的一道月牙刀光，平铺在地面上，外沿正好压在砍击半径上，左右张开 arc_deg 度
func slash(pos: Vector3, facing: Vector3, radius: float, arc_deg: float) -> void:
	var st: Dictionary = SLASH_STYLES[slash_style]
	var yaw := atan2(facing.x, facing.z)
	var key := int(round(arc_deg))
	if slash_area_alpha > 0.0 and st.get("underlay", true):
		if not _fan_meshes.has(key):
			_fan_meshes[key] = _build_sector(float(key), 0.0, 1.0, false)
		var f := _take("fan", 4)
		f.node.mesh = _fan_meshes[key]
		f.node.material_override = _fan_mat
		f.node.global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius, 1, radius)), Vector3(pos.x, pos.y + 0.05, pos.z))
		f.life = 0.22
		f.fade_from = 0.0
		f.color = Color(st["area"], slash_area_alpha)
		_start(f)
	if not _arc_meshes.has(key):
		_arc_meshes[key] = _build_sector(float(key), SLASH_RHO0, SLASH_RHO1, true)
	var s := _take("slash", 4)
	s.node.mesh = _arc_meshes[key]
	s.node.material_override = _slash_mats[slash_style]
	# 网格是朝 +Z 的单位扇环；左右翻转靠 X 取负
	var r: float = radius * st["scale"]
	s.node.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(-r if st["flip"] else r, 1, r)), Vector3(pos.x, pos.y + 0.08, pos.z))
	s.frames = st["frames"]
	s.fps = st["fps"]
	s.life = s.frames / s.fps
	_start(s)


## 受击火花：打中敌人时在给定位置（胸口高度）爆一下，正对相机，不被模型挡住
func hit(pos: Vector3) -> void:
	var s := _clip("hit", pos)
	s.node.rotation.z = randf() * TAU


## 敌人倒下：脚下一道向两边扫开的尘浪，再加一圈尘环
func death(pos: Vector3) -> void:
	_clip("dust_sweep", pos)
	var ring := _clip("dust_ring", pos)
	ring.age = -0.05
	ring.node.visible = false


## 捡到经验球：一个很小的青色闪光
func pickup(pos: Vector3) -> void:
	_clip("pickup", pos)


## 升级：一道金色光柱，播放期间跟着 target 走
func level_up(target: Node3D) -> void:
	var s := _clip("levelup", target.global_position)
	s.follow = target


## 护盾：一个套在 target 身上、循环播放的青色光圈。返回的节点挂在 target 下面，调用方自己开关 visible；
## 每次从隐藏变成显示，会先播一遍张开的过程。
func make_shield(target: Node3D) -> Node3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (SHIELD_RADIUS / SHIELD_RING_IN_CELL)
	mi.mesh = q
	mi.material_override = _shield_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = q.size.x
	mi.position = Vector3(0, 0.9, 0)
	target.add_child(mi)
	_shields.append({"node": mi, "age": 0.0, "shown": false})
	return mi


## 受击闪白：model 下面所有网格（包括挂在骨骼挂点上的头、武器）盖一层白，保持一下再淡出。
## 所有角色共用一份材质，每个网格只改自己的实例参数（闪多亮、什么颜色）；model 中途被释放也没事。
## color：盖上去的颜色，默认纯白；alpha 小于 1 就是半透明地染一层（比如主角挨打染红）。
func flash(model: Node3D, duration := 0.1, color := Color.WHITE) -> void:
	var id := model.get_instance_id()
	if _flashes.has(id):
		_flashes[id]["age"] = 0.0
		_flashes[id]["dur"] = duration
		for m in _flashes[id]["meshes"]:
			if is_instance_valid(m):
				m.set_instance_shader_parameter("fx_flash_color", color)
		return
	# 每个模型只找一次网格，记在它自己身上
	var meshes: Array
	if model.has_meta("_fx_meshes"):
		meshes = model.get_meta("_fx_meshes")
	else:
		meshes = model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		model.set_meta("_fx_meshes", meshes)
	for m in meshes:
		if is_instance_valid(m):
			m.material_overlay = _flash_mat
			m.set_instance_shader_parameter("fx_flash", 1.0)
			m.set_instance_shader_parameter("fx_flash_color", color)
	_flashes[id] = {"meshes": meshes, "age": 0.0, "dur": duration}


## 溅血：从 pos 朝 dir（击退方向）喷出一股血，另外在落点的地上留一小滩，一秒多后淡掉
func blood(pos: Vector3, dir: Vector3) -> void:
	var x := Vector3(dir.x, 0, dir.z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	# 血朝 dir 喷，面片绕 dir 这根轴尽量转向相机
	var to_cam := Vector3.UP
	var up_on_screen := Vector3.UP
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		to_cam = (cam.global_position - pos).normalized()
		up_on_screen = cam.global_basis.y
	var z := to_cam - x * to_cam.dot(x)
	z = z.normalized() if z.length_squared() > 0.0001 else Vector3.UP
	var y := z.cross(x)
	if y.dot(up_on_screen) < 0.0:
		y = -y    # 别让血往天上“掉”
	var s := _clip("blood", pos)
	s.node.global_transform = Transform3D(Basis(x, y, z), pos)
	if blood_splat:
		var g := _clip("splat", Vector3(pos.x, 0.04, pos.z) + x * 0.35)
		g.node.global_transform = Transform3D(Basis(x, Vector3.UP.cross(x), Vector3.UP), g.node.global_position)
		# 地上那滩：等血落下来再出现，停在散开的那一帧上慢慢淡掉
		g.age = -0.15
		g.node.visible = false
		g.first = 6
		g.frames = 1
		g.life = 1.6
		g.fade_from = 0.6
		g.node.set_instance_shader_parameter("frame", 6.0)


## 剑法的一道剑气：从 pos（主角脚下）朝 angle 方向射出去，射到 length 米远。平铺在地面上。
## angle 和 node.rotation.y 一个意思：方向 = (sin(angle), 0, cos(angle))。
## 原特效是先用 0.18 秒射到头、再用 0.22 秒从尾巴收掉，一共 0.4 秒。
func sword_strike(pos: Vector3, angle: float, length: float) -> void:
	var s := _take("sword", 24)
	s.node.mesh = _sword_mesh
	s.node.material_override = _sword_mat
	s.node.extra_cull_margin = 0.5
	# 原画带一点 S 形的弯，隔一道左右翻一下，免得八道一模一样
	_sword_flip = not _sword_flip
	var w := -sword_widen if _sword_flip else sword_widen
	s.node.global_transform = Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(Vector3(w, 1, length)), Vector3(pos.x, pos.y + 0.08, pos.z))
	s.frames = SWORD["frames"]
	s.fps = SWORD["fps"]
	s.life = s.frames / s.fps
	_start(s)


## 拳法的一拳：一团拳风从天上砸到地面的 pos，砸中后地上一圈震波扩到 radius 米。
## 返回从调用到砸中的秒数（伤害该在这一刻结算）。
func fist(pos: Vector3, radius: float) -> float:
	var k := radius / FIST_NATIVE_RADIUS
	var up := Vector3.UP
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		up = cam.global_basis.y     # 顺着画面的“上”落下来，大小不会因为离相机近了而变
	var wind := _clip("fist_wind", pos)
	wind.node.global_transform = Transform3D(Basis.from_scale(Vector3(k, k, k)), pos)
	wind.node.extra_cull_margin = 4.0 * k
	wind.base = pos
	wind.drop = up * (FIST_DROP * k)
	wind.drop_time = FIST_DELAY
	wind.node.global_position = pos + wind.drop
	var d := k
	var g := _clip("fist_ground", pos)
	# 面片本来竖着朝 +Z，放倒铺在地上
	g.node.global_transform = Transform3D(Basis(Vector3(d, 0, 0), Vector3(0, 0, -d), Vector3(0, d, 0)), Vector3(pos.x, pos.y + 0.06, pos.z))
	g.node.extra_cull_margin = 0.5
	g.age = -FIST_DELAY
	g.node.visible = false
	return FIST_DELAY


# ---------------------------------------------------------------- 每帧更新

func _process(delta: float) -> void:
	var i := _shots.size() - 1
	while i >= 0:
		var s := _shots[i]
		s.age += delta
		if s.age >= s.life or (s.follow != null and not is_instance_valid(s.follow)):
			_release(i)
		elif s.age >= 0.0:
			if not s.node.visible:
				s.node.visible = true
			if s.follow != null:
				s.node.global_position = s.follow.global_position + s.offset
			if s.drop_time > 0.0:
				s.node.global_position = s.base + s.drop * (1.0 - pow(minf(1.0, s.age / s.drop_time), 2.8))
			if s.frames > 1:
				s.node.set_instance_shader_parameter("frame", float(s.first + min(s.frames - 1, int(s.age * s.fps))))
			if s.fade_from >= 0.0 and s.age > s.fade_from:
				var c := s.color
				c.a *= 1.0 - (s.age - s.fade_from) / (s.life - s.fade_from)
				s.node.set_instance_shader_parameter("tint", c)
		i -= 1

	for id in _flashes.keys():
		var f: Dictionary = _flashes[id]
		f["age"] += delta
		var t: float = f["age"] / max(0.001, f["dur"])
		var a := 1.0 if t <= FLASH_HOLD else 1.0 - (t - FLASH_HOLD) / (1.0 - FLASH_HOLD)
		for m in f["meshes"]:
			if not is_instance_valid(m):
				continue
			if t >= 1.0:
				m.material_overlay = null
			else:
				m.set_instance_shader_parameter("fx_flash", a)
		if t >= 1.0:
			_flashes.erase(id)

	var k := _shields.size() - 1
	while k >= 0:
		var sh := _shields[k]
		var n: MeshInstance3D = sh["node"]
		if not is_instance_valid(n):
			_shields.remove_at(k)
		elif not n.visible:
			sh["shown"] = false
		else:
			if not sh["shown"]:
				sh["shown"] = true
				sh["age"] = 0.0
			sh["age"] += delta
			var age: float = sh["age"]
			# 前 6 帧是光圈张开；之后停在张开的圈上，慢慢转、轻轻呼吸
			var open_t: float = 6.0 / SHIELD["fps"]
			var fr: int = min(5, int(age * SHIELD["fps"]))
			n.set_instance_shader_parameter("frame", float(fr))
			if age > open_t:
				n.set_instance_shader_parameter("rot", (age - open_t) * 1.2)
				n.set_instance_shader_parameter("tint", Color(1, 1, 1, 0.8 + 0.2 * sin((age - open_t) * 4.0)))
			else:
				n.set_instance_shader_parameter("rot", 0.0)
				n.set_instance_shader_parameter("tint", Color.WHITE)
		k -= 1


# ---------------------------------------------------------------- 内部

func _clip(kind: String, pos: Vector3) -> Shot:
	var c: Dictionary = CLIPS[kind]
	var s := _take(kind, c["max"])
	s.node.mesh = _meshes[kind]
	s.node.material_override = _mats[kind]
	s.node.extra_cull_margin = c["size"]
	s.node.global_transform = Transform3D(Basis.IDENTITY, pos)
	s.frames = c["frames"]
	s.fps = c["fps"]
	s.life = s.frames / s.fps
	_start(s)
	return s


# 从池子里拿一个面片；池子空了就新建，到上限了就把这一种里最早的那个抢过来用
func _take(kind: String, cap: int) -> Shot:
	var s := Shot.new()
	s.kind = kind
	var pool: Array = _free[kind]
	if not pool.is_empty():
		s.node = pool.pop_back()
	elif _made[kind] < cap:
		s.node = MeshInstance3D.new()
		s.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s.node)
		_made[kind] += 1
	else:
		for i in _shots.size():
			if _shots[i].kind == kind:
				s.node = _shots[i].node
				_shots.remove_at(i)
				break
	return s


func _start(s: Shot) -> void:
	s.node.visible = true
	s.node.set_instance_shader_parameter("frame", float(s.first))
	s.node.set_instance_shader_parameter("tint", s.color)
	_shots.append(s)


func _release(i: int) -> void:
	var s := _shots[i]
	s.node.visible = false
	_free[s.kind].append(s.node)
	_shots.remove_at(i)


# 图集材质：一张图集 + 当前帧号（实例参数）。同一种特效的所有面片共用这一份。
func _sheet_material(sheet: String, cols: int, rows: int, add: bool, billboard: bool, nodepth: bool) -> ShaderMaterial:
	var code := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, BLEND NODEPTH;
uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform vec2 grid = vec2(1.0, 1.0);
uniform bool use_palette = false;
uniform vec3 pal_dark : source_color = vec3(0.0);
uniform vec3 pal_light : source_color = vec3(1.0);
instance uniform float frame = 0.0;
instance uniform float rot = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
#ifdef BILLBOARD
	// 正对相机，保留节点自己的缩放和绕视线的旋转
	mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec2 r = normalize(MODEL_MATRIX[0].xy + vec2(0.0001, 0.0));
	m = m * mat4(vec4(r.x * sx, r.y * sx, 0.0, 0.0), vec4(-r.y * sy, r.x * sy, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
#endif
}
void fragment() {
	vec2 uv = UV - 0.5;
	uv = vec2(uv.x * cos(rot) - uv.y * sin(rot), uv.x * sin(rot) + uv.y * cos(rot)) + 0.5;
	// 夹在格子里，免得线性过滤采到隔壁那一帧
	vec2 half_texel = 0.5 * grid / vec2(textureSize(sheet, 0));
	uv = clamp(uv, half_texel, 1.0 - half_texel);
	vec2 cell = vec2(mod(frame, grid.x), floor(frame / grid.x));
	vec4 c = texture(sheet, (cell + uv) / grid);
	if (use_palette) {
		c.rgb = mix(pal_dark, pal_light, dot(c.rgb, vec3(0.299, 0.587, 0.114)));
	}
	ALBEDO = c.rgb * tint.rgb;
	ALPHA = c.a * tint.a;
}
"""
	code = code.replace("BLEND", "blend_add" if add else "blend_mix")
	code = code.replace(" NODEPTH", ", depth_test_disabled" if nodepth else "")
	if billboard:
		code = code.replace("shader_type spatial;", "shader_type spatial;\n#define BILLBOARD")
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	m.set_shader_parameter("sheet", load(FX_DIR + sheet + "/sheet.png"))
	m.set_shader_parameter("grid", Vector2(cols, rows))
	return m


# 平放的长条：沿 +Z 从 z0 到 z1，左右各 half 宽。U 沿 Z，V 横着。
func _build_strip(z0: float, z1: float, half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [[Vector3(-half, 0, z0), Vector2(0, 0)], [Vector3(half, 0, z0), Vector2(0, 1)],
		[Vector3(-half, 0, z1), Vector2(1, 0)], [Vector3(half, 0, z1), Vector2(1, 1)]]
	for idx in [0, 1, 2, 2, 1, 3]:
		st.set_uv(quad[idx][1])
		st.add_vertex(quad[idx][0])
	return st.commit()


# 朝 +Z 张开的单位扇环（内半径 r0、外半径 r1，左右各半个 arc_deg）。
# strip = true：贴刀光长条，U 沿角度从 -X 一侧到 +X 一侧，V 从内圈到外圈；false：U = 半径，给底下那层扇形用。
func _build_sector(arc_deg: float, r0: float, r1: float, strip: bool) -> ArrayMesh:
	var half := deg_to_rad(arc_deg) * 0.5
	var steps: int = max(4, int(ceil(arc_deg / 6.0)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var quad := []
		for j in [0, 1]:
			var t := float(i + j) / steps
			var a: float = -half + 2.0 * half * t
			var d := Vector3(sin(a), 0, cos(a))
			quad.append([d * r0, Vector2(t, 0.0) if strip else Vector2(r0, t)])
			quad.append([d * r1, Vector2(t, 1.0) if strip else Vector2(r1, t)])
		for idx in [0, 1, 2, 2, 1, 3]:
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])
	return st.commit()
