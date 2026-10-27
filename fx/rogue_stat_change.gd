extends Node3D
# 原作 StatChangePhase 强化演出（平原头目破段）· 只读移植 + 2.5D 适配。
#
# 源块：`index-7def6496.js` @ 5588704 `const sR=class sR extends Mi{...}` 的
# `if(o.filter(s=>s).length&&this.scene.moveAnimations){...}` 段（见
#
# 原演出：
#   tileSprite(u, m, c, h, "battle_stats", 单项名 | "mix")，c = 156*scale、h = 316*scale（源像素），
#   setScale(6)、setOrigin(.5,1)、alpha 0 → .8375（250ms）hold 到 1.25s → 1.25..1.5s 淡出 0，
#   1500ms 上移 160*6 源像素，1750ms disableMask + 提交并移除；期间播 `stat_up`。
#   遮罩是角色的 alpha（BitmapMask），只显示角色轮廓内的图案，不是整块矩形。
#
#   - 图案仍按原「32px 图块、6 倍放大」的比例；四边形贴到角色画布大小，
#     tile_count = 画布像素 / (32*6)，横竖各一份；上升用 UV 滚动等价重现（源像素 960 / 1.5s）。
#     帧变化当帧更新 uniform，所以随实际物种 / 朝向 / 原帧 / trim / 翻转走，不显示整块矩形。
#   - 世界像素比例是自定值；不改原角色动画、不是第二个角色渲染器。
#
# 生命周期：单条 1.75s；`clear()` 幂等，死亡 / 取消 / 结算 / 退出都会停图层与音频、重入无残留。
const DIR := "res://assets/pokemon/stat_fx/"
const JSON_PATH := DIR + "battle_stats.json"
const SHEET_PATH := DIR + "battle_stats.png"
const SOUND_PATH := DIR + "stat_up.wav"
const SHADER_PATH := "res://fx/rogue_stat_change.gdshader"

const FRAME_PX := 32.0        # battle_stats 每格 32x32 源像素
const TILE_SCALE := 6.0       # 源 `E.setScale(6)`
const RISE_PX := 160.0 * 6.0  # 源 `y: "-=160*6"`，1500ms
const RISE_SECS := 1.5
const PEAK_ALPHA := 0.8375
const DURATION := 1.75

# 源 `le[r[0]].toLowerCase()` 的 5 项 + `r.length>1 ? "mix"`。
const STAT_KEYS: Array[String] = ["atk", "def", "spatk", "spdef", "spd"]
const MIX_KEY := "mix"

var cam: Camera3D
# 检查用固定时钟：manual=true 时 _process 不自动推进，由 advance() 手动推。
var manual := false
var load_error := ""

var _regions := {}          # key -> Rect2（图集归一化）
var _sheet: Texture2D
var _shader: Shader
var _plays: Array = []
# overlay 已结束、WAV 尾声仍在播的归属：[{"owner": ..., "player": AudioStreamPlayer}]。
var _tails: Array = []
var _audio: Array = []
var _next_id := 0
var _loaded := false


func setup(camera: Camera3D) -> void:
	cam = camera


func _ready() -> void:
	_ensure_loaded()
	set_process(not manual)


func set_manual(value: bool) -> void:
	manual = value
	set_process(not manual)


func _ensure_loaded() -> bool:
	if _loaded:
		return _sheet != null
	_loaded = true
	if not FileAccess.file_exists(JSON_PATH):
		load_error = "missing " + JSON_PATH
		push_warning("rogue_stat_change: " + load_error)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	if not (data is Dictionary) or not data.has("textures") or (data["textures"] as Array).is_empty():
		load_error = "bad " + JSON_PATH
		push_warning("rogue_stat_change: " + load_error)
		return false
	var tex0: Dictionary = data["textures"][0]
	var size: Dictionary = tex0["size"]
	var w := maxf(1.0, float(size["w"]))
	var h := maxf(1.0, float(size["h"]))
	for f in tex0["frames"]:
		var fr: Dictionary = f["frame"]
		_regions[str(f["filename"])] = Rect2(float(fr["x"]) / w, float(fr["y"]) / h,
			float(fr["w"]) / w, float(fr["h"]) / h)
	if ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH) as Texture2D
	if ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH) as Shader
	if _sheet == null:
		load_error = "missing " + SHEET_PATH
		push_warning("rogue_stat_change: " + load_error)
	return _sheet != null


# 单项 -> 该项图块；多项 / 重复 -> "mix"（源 `r.length>1?"mix":...`）。
static func stat_texture_key(stat_ids: Array) -> String:
	if stat_ids.size() > 1:
		return MIX_KEY
	if stat_ids.is_empty():
		return ""
	return str(STAT_KEYS[clampi(int(stat_ids[0]), 0, STAT_KEYS.size() - 1)])


func region_of(key: String) -> Rect2:
	return _regions.get(key, Rect2())


func sheet() -> Texture2D:
	return _sheet


# 源 alpha 时间轴（8 个检查点：0 / .125 / .25 / 1.0 / 1.25 / 1.375 / 1.5 / 1.75）。
static func alpha_at(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t < 0.25:
		return PEAK_ALPHA * (t / 0.25)
	if t <= 1.25:
		return PEAK_ALPHA
	if t < 1.5:
		return PEAK_ALPHA * (1.0 - (t - 1.25) / 0.25)
	return 0.0


static func rise_at(t: float) -> float:
	return RISE_PX * clampf(t / RISE_SECS, 0.0, 1.0)


# 播一次强化演出。stat_ids 是本批源聚合后的 stats 数组（单项播该项、多项 mix）。
# owner_unit 可传敌人对象（有 dying 字段）用于死亡即停；玩家传 null。
func play(stat_ids: Array, actor: Node3D, owner_unit = null, sound := true) -> bool:
	if not _ensure_loaded() or actor == null or not is_instance_valid(actor):
		return false
	if _shader == null:
		push_warning("rogue_stat_change: shader missing, skip fx")
		return false
	var key := stat_texture_key(stat_ids)
	if key == "" or not _regions.has(key):
		return false
	var sprite := _sprite_of(actor)
	if sprite == null:
		return false
	var mi := MeshInstance3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 3
	mi.mesh = _unit_quad()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var pl := _make_sound() if sound else null
	var p := {
		"id": _next_id, "actor": actor, "sprite": sprite, "owner": owner_unit,
		"key": key, "mi": mi, "mat": mat, "audio": pl,
		"t": 0.0, "alpha": 0.0, "rise_px": 0.0, "sound": sound, "dead": false,
		"stop_audio": true,
	}
	_next_id += 1
	_plays.append(p)
	mat.set_shader_parameter("stat_tex", _sheet)
	var region: Rect2 = _regions[key]
	mat.set_shader_parameter("stat_region_pos", region.position)
	mat.set_shader_parameter("stat_region_size", region.size)
	mat.set_shader_parameter("fx_alpha", 0.0)
	_update_transform(p)
	return true


func _process(delta: float) -> void:
	if manual:
		return
	advance(delta)


# 推进所有播放；供 _process 与固定时钟检查共用。
func advance(delta: float) -> void:
	var i := 0
	while i < _plays.size():
		var p: Dictionary = _plays[i]
		_advance_play(p, delta)
		if bool(p["dead"]):
			_free_play(p)
			_plays.remove_at(i)
		else:
			i += 1
	_advance_audio_tails()


func play_count() -> int:
	return _plays.size()


func play_state(id: int) -> Dictionary:
	for p in _plays:
		if int(p["id"]) == id:
			return p
	return {}


func last_play() -> Dictionary:
	return _plays.back() if not _plays.is_empty() else {}


func _advance_play(p: Dictionary, delta: float) -> void:
	if not is_instance_valid(p["actor"]) or not is_instance_valid(p["sprite"]) or not is_instance_valid(p["mi"]):
		p["dead"] = true
		p["stop_audio"] = true
		return
	# 死亡即停：死亡动画一开始就不再跟随后续帧 / 不残留到下一只；只停自己这条音频。
	var owner = p["owner"]
	if owner != null and is_instance_valid(owner) and ("dying" in owner) and float(owner.dying) >= 0.0:
		p["dead"] = true
		p["stop_audio"] = true
		return
	var t := float(p["t"]) + delta
	p["t"] = t
	p["alpha"] = alpha_at(t)
	p["rise_px"] = rise_at(t)
	_apply_alpha(p)
	if t >= DURATION:
		# overlay 到 1.75s 结束、移除 mesh；原 WAV 若更长，尾声继续挂在该 owner 上播完。
		p["dead"] = true
		p["stop_audio"] = false
		return
	_update_transform(p)


func _apply_alpha(p: Dictionary) -> void:
	(p["mat"] as ShaderMaterial).set_shader_parameter("fx_alpha", float(p["alpha"]))


# 每帧同步：四边形贴到角色 sprite **实际绘制的那块纹理**（AtlasTexture region；trim 已由
# Sprite3D 的 offset 体现），尺寸与偏移的 X / Y **各取自己那一轴的比例**。
# 受击 pulse 的 node.scale 是非等比（x/z 放大、y 压扁），用 sscale.x 兼算 Y 尺寸与 Y 偏移会
# 让遮罩明显偏位；X/Y 分轴后遮罩和 body 重合，且不改角色动画 / 受击 pulse。
# 遮罩 UV 与 region 1:1（region 即四边形），随原帧 / trim / flip_h / 相机同步。
func _update_transform(p: Dictionary) -> void:
	var sprite: Sprite3D = p["sprite"]
	var basis := _view_basis()
	var sscale := sprite.global_transform.basis.get_scale()
	var sx := sprite.pixel_size * maxf(0.0001, absf(sscale.x))
	var sy := sprite.pixel_size * maxf(0.0001, absf(sscale.y))
	var tex_size := _texture_size(sprite)
	var center := sprite.global_position \
		+ basis.x * (sprite.offset.x * sx) \
		+ basis.y * (sprite.offset.y * sy)
	var mi: MeshInstance3D = p["mi"]
	mi.global_transform = Transform3D(basis, center)
	mi.scale = Vector3(maxf(0.0001, tex_size.x * sx), maxf(0.0001, tex_size.y * sy), 1.0)
	var mat: ShaderMaterial = p["mat"]
	mat.set_shader_parameter("tile_count",
		Vector2(tex_size.x / (FRAME_PX * TILE_SCALE), tex_size.y / (FRAME_PX * TILE_SCALE)))
	mat.set_shader_parameter("scroll_tiles", float(p["rise_px"]) / (FRAME_PX * TILE_SCALE))
	var tex := sprite.texture
	if tex is AtlasTexture:
		var at := tex as AtlasTexture
		mat.set_shader_parameter("mask_tex", at.atlas)
		var pw := maxf(1.0, float(at.atlas.get_width()))
		var ph := maxf(1.0, float(at.atlas.get_height()))
		mat.set_shader_parameter("mask_region_pos", Vector2(at.region.position.x / pw, at.region.position.y / ph))
		mat.set_shader_parameter("mask_region_size", Vector2(at.region.size.x / pw, at.region.size.y / ph))
		# 四边形一般就是本帧 region；若纹理尺寸实际是 “region+margin” 的整块画布，则把 region 放回画布位置。
		var cw := maxf(1.0, at.region.size.x + at.margin.size.x)
		var ch := maxf(1.0, at.region.size.y + at.margin.size.y)
		if absf(tex_size.x - cw) < 0.5 and absf(tex_size.y - ch) < 0.5:
			mat.set_shader_parameter("mask_place_pos", Vector2(at.margin.position.x / cw, at.margin.position.y / ch))
			mat.set_shader_parameter("mask_place_size", Vector2(at.region.size.x / cw, at.region.size.y / ch))
		else:
			mat.set_shader_parameter("mask_place_pos", Vector2.ZERO)
			mat.set_shader_parameter("mask_place_size", Vector2.ONE)
	else:
		mat.set_shader_parameter("mask_place_pos", Vector2.ZERO)
		mat.set_shader_parameter("mask_place_size", Vector2.ONE)
	mat.set_shader_parameter("mask_flip", 1.0 if sprite.flip_h else 0.0)


# 角色 sprite 实际绘制的纹理尺寸（AtlasTexture 为 region 尺寸；probe 用 texture.get_height()）。
static func _texture_size(sprite: Sprite3D) -> Vector2:
	var tex := sprite.texture
	if tex != null:
		var size := tex.get_size()
		if size.x > 0.0 and size.y > 0.0:
			return size
	return Vector2(1.0, 1.0)


static func _sprite_of(node: Node) -> Sprite3D:
	if node == null or not is_instance_valid(node):
		return null
	var direct := node.get_node_or_null("Sprite")
	if direct is Sprite3D:
		return direct
	if node.get_child_count() > 0:
		var child := node.get_child(0)
		if is_instance_valid(child):
			var nested := child.get_node_or_null("Sprite")
			if nested is Sprite3D:
				return nested
	return null


func _view_basis() -> Basis:
	if cam != null and is_instance_valid(cam):
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY


# 每个播放自己持有一条 AudioStreamPlayer（原 stat_up），player 记进该播放的 p["audio"]：
# 归属清晰，owner 死只停自己那条；overlay 1.75s 正常结束时若 WAV 还没放完，尾声转进 _tails
# 继续挂在该 owner 上播完（不无故截断），尾声期间 owner 死也会被停掉。
func _make_sound() -> AudioStreamPlayer:
	if not ResourceLoader.exists(SOUND_PATH):
		push_warning("rogue_stat_change: sound missing " + SOUND_PATH)
		return null
	var pl := AudioStreamPlayer.new()
	pl.stream = load(SOUND_PATH)
	pl.bus = _audio_bus()
	add_child(pl)
	pl.finished.connect(_on_sound_done.bind(pl))
	_audio.append(pl)
	pl.play()
	return pl


func _on_sound_done(pl: AudioStreamPlayer) -> void:
	_audio.erase(pl)
	for i in range(_tails.size() - 1, -1, -1):
		if _tails[i]["player"] == pl:
			_tails.remove_at(i)
	if is_instance_valid(pl):
		pl.queue_free()


# 停掉 / 回收一条音频。不引入音频总线或第二播放器框架；stop 后 queue_free。
func _stop_audio(pl) -> void:
	if pl == null or not is_instance_valid(pl):
		return
	pl.stop()
	pl.stream = null
	_audio.erase(pl)
	pl.queue_free()


# 尾声归属推进：overlay 已结束但 WAV 仍在播；owner 一死只停它自己那条，其他 owner 不受影响。
func _advance_audio_tails() -> void:
	var i := 0
	while i < _tails.size():
		var tail: Dictionary = _tails[i]
		var pl = tail["player"]
		if not is_instance_valid(pl):
			_tails.remove_at(i)
			continue
		var owner = tail["owner"]
		if owner != null and is_instance_valid(owner) and ("dying" in owner) and float(owner.dying) >= 0.0:
			_stop_audio(pl)
			_tails.remove_at(i)
			continue
		i += 1


func _audio_bus() -> StringName:
	if AudioServer.get_bus_index("Sfx") >= 0:
		return &"Sfx"
	return &"Master"


static func _unit_quad() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0),
		Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0)])
	var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# 释放一条播放：mesh 立即移除。音频按结束原因处理：
#   - stop_audio=true（owner 死 / 失效 / clear）：只停自己这条；
#   - 自然到 1.75s（stop_audio=false）：WAV 还在放就转进 _tails 保留 owner 归属继续放完，
#     已经放完的直接回收。
func _free_play(p: Dictionary) -> void:
	if is_instance_valid(p.get("mi")):
		(p["mi"] as Node).queue_free()
	var pl = p.get("audio")
	if pl != null and is_instance_valid(pl):
		if bool(p.get("stop_audio", true)) or not pl.playing:
			_stop_audio(pl)
		else:
			_tails.append({"owner": p.get("owner"), "player": pl})
	p["audio"] = null


# 停掉全部强化图层与音频；幂等，可安全在 _exit_tree / 取消 / 结算里重复调用。
func clear() -> void:
	for p in _plays:
		if is_instance_valid(p.get("mi")):
			(p["mi"] as Node).queue_free()
		p["audio"] = null
	_plays.clear()
	_tails.clear()
	for pl in _audio:
		if is_instance_valid(pl):
			pl.stop()
			pl.stream = null
			pl.queue_free()
	_audio.clear()


func _exit_tree() -> void:
	clear()
