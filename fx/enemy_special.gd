extends RefCounted
# 闪光 / 神兽宠物的特效与音效（用户 2026-10-17：“闪光 / 神兽宠要有特效和音效我们好辨识”）。
#
# 纯显示 + 一次性提示音，不碰战斗数值：
#   - 闪光：原作遇到闪光宠物时的星星闪烁（PokéRogue `images/effects/shiny.png`，35 帧 89×75，32 fps），
#     原版只在遇敌时播一次，这里每隔一小会儿再播（SPARKLE_GAP），宠物一直带着闪；
#   - 提示音：闪光 = 原 sparkle.wav，神兽 = 原 shine.wav；进入视野那一刻响一次。
# 素材来源与哈希见 assets/fx/SOURCES.md 第三节。

const SPARKLE_TEX := "res://assets/fx/special/shiny.png"
const SPARKLE_SIZE := Vector2(455.0, 539.0)
const SPARKLE_FRAME := Vector2(89.0, 75.0)
const SPARKLE_COLS := 5
const SPARKLE_FRAMES := 35
const SPARKLE_FPS := 32.0
const SPARKLE_GAP := 0.7          # 一轮播完后停多久再播
const SPARKLE_PIXEL := 0.04       # 原 1 像素 = 多少世界单位（宠物节点自己的缩放会再乘上去）
const SPARKLE_HEIGHT := 1.0
const SOUND_SHINY := "res://assets/fx/special/sparkle.wav"
const SOUND_LEGEND := "res://assets/fx/special/shine.wav"
const OUTLINE_COLOR := Color(1.0, 0.82, 0.2)   # 金色描边（闪光 / 神兽都有）
const BOSS_OUTLINE_COLOR := Color(1.0, 0.25, 0.2)   # 红色描边（头目，用户 2026-10-20：每次看不到）
const ALERT_DISTANCE := 12.0      # 进入这个距离（米，约等于进入屏幕）响提示音、弹横幅

static var _tex: Texture2D = null


# 第 i 帧在图集里的左上角像素（原图集是规整的 5 列网格，帧间距 91 / 77，边距 1）。
static func frame_origin(i: int) -> Vector2:
	var c := i % SPARKLE_COLS
	var r := i / SPARKLE_COLS
	return Vector2(1.0 + 91.0 * c, 1.0 + 77.0 * r)


static func _sparkle_texture() -> Texture2D:
	if _tex == null and ResourceLoader.exists(SPARKLE_TEX):
		_tex = load(SPARKLE_TEX) as Texture2D
	return _tex


# 闪光星星：一个朝向相机的小面片挂在宠物节点上；用 uv1 偏移换帧。
static func make_sparkle(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ShinySparkle"
	var quad := QuadMesh.new()
	quad.size = SPARKLE_FRAME * SPARKLE_PIXEL
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 3
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = _sparkle_texture()
	mat.uv1_scale = Vector3(SPARKLE_FRAME.x / SPARKLE_SIZE.x, SPARKLE_FRAME.y / SPARKLE_SIZE.y, 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, SPARKLE_HEIGHT, 0)
	mi.visible = false
	parent.add_child(mi)
	return mi


# 推进闪烁：t 是本只宠物自己的计时（秒）。一轮 = 35 帧 / 32fps ≈ 1.09 秒，再停 SPARKLE_GAP。
static func sparkle_frame_at(t: float) -> int:
	var cycle := float(SPARKLE_FRAMES) / SPARKLE_FPS + SPARKLE_GAP
	var phase := fposmod(t, cycle)
	var f := int(phase * SPARKLE_FPS)
	return f if f < SPARKLE_FRAMES else -1   # -1 = 停顿期，不显示


static func update_sparkle(mi: MeshInstance3D, t: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var f := sparkle_frame_at(t)
	if f < 0:
		mi.visible = false
		return
	mi.visible = true
	var o := frame_origin(f)
	var mat := mi.material_override as StandardMaterial3D
	mat.uv1_offset = Vector3(o.x / SPARKLE_SIZE.x, o.y / SPARKLE_SIZE.y, 0.0)
