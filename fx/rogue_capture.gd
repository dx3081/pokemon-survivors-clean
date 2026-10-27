extends Node3D
#
# 只做「一次投球对一只目标」的**原演出播放器**：可独立 setup/play/advance，不接真实投球、
# 不掷捕获骰、不扣球、不落盘、不发 XP / 进化 / 胜利，也不改输入 actor 本体。
# 目标用一个只读快照的短命副本来演吸入 / 挣脱；原 actor 先释放播放仍安全。
# 真实接线（谁投球 / 何时暂停敌人 / 成功后给什么）是下一段，由调用者管理。
#
# 来源（静态只读，不执行原包）：
#   来源 / 原始时间轴 / 适配边界见 game/POKEMON_CAPTURE_FX_SOURCE.md 与
#   assets/pokemon/capture_fx/SOURCES.md。
#
# 原演出（源 `Jk extends Mi` / `start()`）：
#   addFieldSprite(16,80,"pb",m).setOrigin(.5,.625)，pb_throw；
#   500ms 投球（x 线性 / y Cubic.easeOut）→ `${m}_opening` → 17ms 后 `${m}_open` + pb_rel +
#   球色 tint(QT) + 开球粒子 MX；目标 500ms Sine.easeIn scale .25 / y 20；
#   → `${m}_opening` + 目标隐藏 + pb_catch → 17ms 后 `${m}`；
#   250ms 后 nie(this.scene,pokeball,16,72,350,doShake) 弹跳；弹跳完 doShake：
#   addCounter(from0,to1,repeat4,yoyo,duration250,repeatDelay500,Cubic.easeOut)，
#   前 3 次成功各 pb_move，第 4 次 pb_lock + Zne 三颗星 + setTintFill(0) 黑闪（非白闪）；
#   onComplete 走 `catch()`（真实奖励由游戏层做，本段只到球淡出）。
#   失败 failCatch：pb_rel → opening → 17ms 后 open，目标回原位置 / Sine.easeOut 250ms 全尺寸 /
#   原色 untint 250，removePb 250+250 淡出结束；不倒放成功星星 / 不伪造锁定声。
#
#   - 8 次落地 / 7 次上升，系数 1,.5,.25,.125,.0625,.03125,.015625,.0078125，共 1044.53125ms。
#   - onUpdate 只在 h=1/2/3 时 wiggle：±4 源像素、±27.5°、CubicOut 往复、h 奇偶决定方向。
#   - result.shakes 是**第几次判定失败**（1..3），不是成功次数：失败 1 无 pb_move，
#     失败 2 只有 1 次 move，失败 3 只有 2 次 move。
#   - 黑闪 `setTintFill(0)` 是黑色；源写 `easing` 而 Phaser builder 只认 `ease`，
#     实际退化成默认 Power0 线性（100ms 时 alpha=.1875），不能纠成 Sine。
#   - 星 X 偏移 `Bq(25)` 是无上限 Box-Muller 高斯，不是均匀 ±25，也不 clamp。
#   - 星 alpha 有**两条** tween：`setAlpha(.5)`；第一条 Y 上移 250ms 的 onComplete 新建
#     `{y:t.y, alpha:0, ease:"Sine.easeIn", duration:250}`（250..500 写 alpha），
#     另有 `{alpha:0, delay:425, duration:75, onComplete:destroy}`（425..500 写 alpha）。
#     `TweenManager.step` 按 `this.tweens` 数组顺序逐个 `update`，`add` 只 `push` 到末尾；
#     星是先建 delay425 再在其 onComplete 里建 SineIn（后者下标更大、同帧后写），
#     故 425..500 两条都写时**后建的 SineIn 覆盖前者**，最终 alpha = .5*cos(((t-250)/250)*PI/2)。
#     本实现照此取 SineIn 曲线；被覆盖的 delay425 那条在 state 里以 `alpha_tail` 留档，不静默删除。
#   - 粒子 `$A/$ST` 是 `sin(angle*Math.PI/128)`（256 为一圈），不是度 / 360。
#   - 普通 / 超级球 radius 48 / 96、repeat16 = 17 次发射（20..340ms 每 20ms）、
#     每个 575ms 运动、最后 75ms 淡出、frames 0..3 @16fps、startFrame (I+3)%4；
#     高级 / 肉鸽 10 个扇出 frame 8/10，初角 f*25、每 16ms 步进 5；
#     大师 16 个 frame 4，两组 8 个、初角 f*32、步进 8、x/y 速度 1/2 互换；750ms 后 250ms 淡出。
#
#   - 源像素 → 世界比例沿角色 pixel_size 0.045；球画布按源 sourceSize + spriteSourceSize
#     还原（trim + 原 origin .5/.625），不把裁剪帧中心当画布中心。
#   - 投球（2026-10-15 修正为实际起终点）：from_world 就是实际起点，to_world 就是实际
#     catch/open 点；X/Z 在两点间线性，Y 从 from_world.y 到 to_world.y 按原 Cubic.easeOut
#     走，原 500ms 不变。**不再额外叠加 64 源像素的“抛高”**——旧 +64px 是隔离阶段的适配，
#     直接套进游戏会从玩家头顶凭空出现 / 落入地下。游戏侧用真实玩家位置当 from、
#     目标脚边 catch_height() 当 to。
#   - “球落地”= to_world 下移 56 源像素（源 |72-16|），是弹跳地面；ground_height() 是
#     闭球底边贴地时的 origin 高度（闭球画布底边距 origin 6px）。catch/open 点比落点高
#     56*PX。地面是调用者给的世界点，不随相机漂移。
#   - 屏幕平面内的位移（wiggle / 粒子 / 星）沿相机视图基向量换算。
#   - 所有图片按视图基 billboard 手摆（Sprite3D 不靠引擎 billboard），angle 绕视图轴转。
#
# API（供后续真实接线）：
#   setup(cam) / set_manual(bool) / set_paused(bool) / play(ball_type, from_world, to_world,
#   attempt_result, target_snapshot, sound=true) -> id（拒绝返回 -1）/ advance(delta) /
#   play_count() / play_state(id) / last_play() / clear()（幂等）/ snapshot_actor(actor)（只读，不改 actor）。
#   set_paused(true) 冻结自动推进（_process 不再 advance）并暂停自有 AudioStreamPlayer.stream_paused；
#   set_paused(false) 从同一点继续、不重播开场音、不漏 cue。advance() 也尊重 paused（检查用确定性时钟）。
#   不接管 Engine.time_scale、不写暂停管理器；由游戏层在 Esc 商店 / 设置时配对调用。
#   play 只读 attempt_result 的 result / captured / shakes。FAINTED(3) / INVALID(4) 直接拒绝，
#   不建图层、不播声音；NOT_OBTAINABLE(2) 是**先完整演出、第一次 onRepeat 才失败**：原
#   `onRepeat` 里 `if(!species.isObtainable()){A.stop();failCatch(h)}` 在 `h++<3` 之前，
#   连 MASTER 也不绕过、h 仍 0 ⇒ 0 次成功 move、无 lock / 星 / 黑闪，3794.53125 淡出结束。
#   advance(delta) 单位是秒，大 delta 逐条补事件不漏不重复。
#   可发 `cue(play_id, name)` 给后续接线；绝不发任何游戏奖励。
#
# play_state(id) 的返回契约（调用者必须先看 finished / play_count，不能把历史摘要当活动播放）：
#   - 播放还在进行（play_count() 数得到这条 id）：返回**活动状态**，含每帧几何
#     `ball_pos / ball_angle_deg / ball_alpha / ball_frame`、`target_pos / target_scale /
#     target_modulate / target_visible`、`flash_alpha`、`stars_state`、`particles_state`、
#     `cues`、`events`、`visual_end`；`finished == false`。
#   - 播放已自然结束 / 被 clear（play_count() 已没有它）：返回**结束摘要**（进 `_done`），
#     只有 `id / ball_type / captured / shakes / result / t / visual_end / finished == true /
#     cues` 与 `ball_visible=false / ball_alpha=0 / target_visible=false`；
#     **没有每帧几何字段**（节点已释放，不伪造 ball_pos 等）。要检查活动过程就在结束前采样，
#     或读 `_done` 摘要的固定字段。`_done` 只保留最近 64 条；更早的返回 `{}`。

signal cue(play_id: int, cue_name: StringName)

const DIR := "res://assets/pokemon/capture_fx/"
const BALL_JSON := DIR + "pb.json"
const BALL_PNG := DIR + "pb.png"
const PART_JSON := DIR + "pb_particles.json"
const PART_PNG := DIR + "pb_particles.png"
const SOUND_NAMES := ["pb_throw", "pb_rel", "pb_catch", "pb_move", "pb_lock", "pb_bounce_1"]

const PX := 0.045                       # 沿角色 pixel_size（2.5D 适配常量）
const BALL_ORIGIN := Vector2(0.5, 0.625)  # 原 setOrigin(.5,.625)
# 闭球画布底部距 origin 的源像素：sourceSize.h(16) - origin.y(.625)*16 = 6。
# 落点 origin 至少要留 6px 高（再加一点余量），闭球底边才不会穿到地面以下。
const BALL_BOTTOM_PX := 6.0
const GROUND_MARGIN := 0.02             # 落地 origin 的小余量（世界单位）
# 世界坐标落点 / catch 点高度（游戏接线用；不是原世界尺度，是 2.5D 适配值）：
#   ground_height = 闭球底边贴地时的 origin 高度
#   catch_height  = ground_height + 56px（原 bounceRangePx；catch/open 点比落点高这么多）
static func ground_height() -> float:
	return BALL_BOTTOM_PX * PX + GROUND_MARGIN


static func catch_height() -> float:
	return ground_height() + BOUNCE_RANGE_PX * PX

# ---- 原时间轴（毫秒，逻辑声明值，不做 Phaser 帧量化） ----
const THROW_MS := 500.0
# 源 |80-16| 的垂直跨度，只作来源留档；2026-10-15 修正后**不再**当成额外起手高度叠加
# （游戏侧 from/to 就是实际起点 / catch 点）。
const THROW_LIFT_PX := 64.0
const OPEN_AFTER_MS := 17.0
const ABSORB_MS := 500.0
const ABSORB_SCALE := 0.25
const BEFORE_BOUNCE_MS := 250.0
const BOUNCE_BASE_MS := 350.0
const BOUNCE_RANGE_PX := 56.0           # 源 |72-16|
const BOUNCE_FACTORS := [1.0, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625, 0.0078125]
const BOUNCE_TOTAL_MS := 1044.53125
const SHAKE_MS := 250.0
const SHAKE_REPEAT := 4
const SHAKE_DELAY_MS := 500.0
const SHAKE_CYCLE_MS := SHAKE_MS * 2.0 + SHAKE_DELAY_MS  # 1000
const SHAKE_OFFSET_PX := 4.0
const SHAKE_ANGLE_DEG := 27.5

const T_OPEN := THROW_MS                          # 500 开球 / 吸入
const T_OPEN_FRAME := T_OPEN + OPEN_AFTER_MS      # 517
const T_CATCH := T_OPEN + ABSORB_MS               # 1000 入球
const T_BALL_BASE := T_CATCH + OPEN_AFTER_MS      # 1017
const T_BOUNCE := T_CATCH + BEFORE_BOUNCE_MS      # 1250 开始弹跳
const T_SHAKE := T_BOUNCE + BOUNCE_TOTAL_MS       # 2294.53125 开始摇球
const T_LOCK := T_SHAKE + SHAKE_REPEAT * SHAKE_CYCLE_MS  # 6294.53125 锁定
const T_COMPLETE := T_LOCK + SHAKE_MS * 2.0       # 6794.53125 源 catch / onComplete
const T_END := T_COMPLETE + 500.0                 # 7294.53125 球淡出结束
const FAIL_CLEANUP_MS := 500.0                    # failCatch: removePb 250 延迟 + 250 淡出

const STAR_COUNT := 3
const STAR_FRAME := "4.png"
const STAR_GAUSS := 25.0
const STAR_MS := 500.0
const STAR_RISE_PX := 10.0
const FLASH_PEAK := 0.375
const FLASH_IN_MS := 200.0
const FLASH_OUT_MS := 200.0
const REMOVE_DELAY_MS := 250.0
const REMOVE_FADE_MS := 250.0

# 球 atlas key / 原 tint（QT 原十进制值）/ 开球粒子风格。
const BALL_KEYS := ["pb", "gb", "ub", "rb", "mb", "lb"]
const BALL_TINTS := [13969705, 9745630, 15125809, 13969705, 10764733, 16768618]
const RADIAL_RADIUS := [48.0, 96.0]     # POKEBALL / GREAT_BALL
const FAN_FRAME := [8, 10]              # ULTRA_BALL / ROGUE_BALL
const FAN_ANGLE0 := 25.0
const FAN_STEP := 5.0
const MASTER_FRAME := 4
const MASTER_ANGLE0 := 32.0
const MASTER_STEP := 8.0
const PARTICLE_STEP_MS := 16.0          # Fi(1) = floor(1000/60) = 16
const RADIAL_START_MS := 20.0
const RADIAL_EMISSIONS := 17            # repeat16
const RADIAL_MOVE_MS := 575.0
const RADIAL_FADE_MS := 75.0
const FAN_FADE_AT_MS := 750.0
const FAN_FADE_MS := 250.0

# 原 Capture 结果码（只读输入，不在这里掷骰）。
const RESULT_CAPTURED := 0
const RESULT_BROKE_FREE := 1
const RESULT_NOT_OBTAINABLE := 2
const RESULT_FAINTED := 3
const RESULT_INVALID := 4

var cam: Camera3D
# 检查用确定性时钟：manual=true 时不自动 _process，由 advance() 手动推。
var manual := false
# 游戏层暂停（Esc 商店 / 设置）：冻结自动推进与自有音频；不碰 Engine.time_scale。
var paused := false
var load_error := ""

var _ball_frames := {}
var _part_frames := {}
var _sounds := {}
var _plays: Array = []
var _done: Array = []
var _audio: Array = []
var _next_id := 0
var _loaded := false
var _rng := RandomNumberGenerator.new()


func setup(camera: Camera3D) -> void:
	cam = camera


func _ready() -> void:
	_rng.randomize()
	_ensure_loaded()
	set_process(not manual)


func set_manual(value: bool) -> void:
	manual = value
	set_process(not manual)


# 小 pause 接口（不取代 manual 检查方式）：冻结自动推进 + 自有 AudioStreamPlayer.stream_paused。
# 幂等；clear / 复播都安全：clear 会停掉全部音频，set_paused(false) 只对仍活着的播放器生效。
func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	for pl in _audio:
		if is_instance_valid(pl):
			pl.stream_paused = value


func is_paused() -> bool:
	return paused


# 注入视觉随机（只用于星星高斯偏移 = 原 Bq）。绝不消费 Capture / gameplay RNG。
func set_visual_rng(rng: RandomNumberGenerator) -> void:
	if rng != null:
		_rng = rng


func _process(delta: float) -> void:
	if manual or paused:
		return
	advance(delta)


# ================= 载入 =================

func _ensure_loaded() -> bool:
	if _loaded:
		return not _ball_frames.is_empty()
	_loaded = true
	if not FileAccess.file_exists(BALL_JSON):
		load_error = "missing " + BALL_JSON
		push_warning("rogue_capture: " + load_error)
		return false
	var ok := _load_atlas(BALL_JSON, BALL_PNG, _ball_frames)
	ok = _load_atlas(PART_JSON, PART_PNG, _part_frames) and ok
	for n in SOUND_NAMES:
		var path := DIR + str(n) + ".wav"
		if ResourceLoader.exists(path):
			_sounds[str(n)] = load(path)
	return ok


func _load_atlas(json_path: String, png_path: String, into: Dictionary) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (data is Dictionary) or not data.has("textures") or (data["textures"] as Array).is_empty():
		load_error = "bad " + json_path
		push_warning("rogue_capture: " + load_error)
		return false
	var atlas: Texture2D = null
	if ResourceLoader.exists(png_path):
		atlas = load(png_path) as Texture2D
	if atlas == null:
		load_error = "missing " + png_path
		push_warning("rogue_capture: " + load_error)
		return false
	for f in data["textures"][0]["frames"]:
		var region: Dictionary = f["frame"]
		var source: Dictionary = f["sourceSize"]
		var trim: Dictionary = f["spriteSourceSize"]
		var tex := AtlasTexture.new()
		tex.atlas = atlas
		tex.region = Rect2(float(region["x"]), float(region["y"]), float(region["w"]), float(region["h"]))
		# margin 把裁剪帧放回 sourceSize 画布：position = trim 偏移，size = 画布补边。
		tex.margin = Rect2(float(trim["x"]), float(trim["y"]),
			float(source["w"]) - float(region["w"]), float(source["h"]) - float(region["h"]))
		into[str(f["filename"])] = {"tex": tex, "source": Vector2(float(source["w"]), float(source["h"])),
			"region": tex.region, "trim": Vector2(float(trim["x"]), float(trim["y"]))}
	return not into.is_empty()


func has_ball_frame(name: String) -> bool:
	return _ball_frames.has(name)


func has_particle_frame(name: String) -> bool:
	return _part_frames.has(name)


# 球帧在 pb 图集里的原始 region（供检查对 fixture 的 frame 值）。
func ball_region(name: String) -> Rect2:
	if _ball_frames.has(name):
		return (_ball_frames[name] as Dictionary)["region"]
	return Rect2()


func particle_region(name: String) -> Rect2:
	if _part_frames.has(name):
		return (_part_frames[name] as Dictionary)["region"]
	return Rect2()


func ball_frame_names() -> Array:
	var out: Array = _ball_frames.keys()
	out.sort()
	return out


func particle_frame_names() -> Array:
	var out: Array = _part_frames.keys()
	out.sort()
	return out


static func ball_atlas_key(ball_type: int) -> String:
	if ball_type < 0 or ball_type >= BALL_KEYS.size():
		return ""
	return BALL_KEYS[ball_type]


static func ball_tint(ball_type: int) -> Color:
	if ball_type < 0 or ball_type >= BALL_TINTS.size():
		return Color.WHITE
	var v: int = BALL_TINTS[ball_type]
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


# ================= 只读快照 =================

# 读 actor 当前的 Sprite3D 画面（texture / offset / pixel_size / flip_h / modulate /
# 世界位置与比例），不改 actor、不保留 actor 引用；actor 之后被释放也不影响播放。
static func snapshot_actor(actor) -> Dictionary:
	var sprite := _sprite_of(actor)
	if sprite == null:
		return {}
	var gt := sprite.global_transform
	return {
		"name": String(actor.name) if actor is Node else "",
		"texture": sprite.texture,
		"offset": sprite.offset,
		"pixel_size": sprite.pixel_size,
		"flip_h": sprite.flip_h,
		"modulate": sprite.modulate,
		"global_position": gt.origin,
		"global_scale": gt.basis.get_scale(),
	}


static func _sprite_of(node) -> Sprite3D:
	if node == null or not is_instance_valid(node):
		return null
	if node is Sprite3D:
		return node
	var direct: Node = node.get_node_or_null("Sprite")
	if direct is Sprite3D:
		return direct
	if node.get_child_count() > 0:
		var child: Node = node.get_child(0)
		if is_instance_valid(child):
			var nested: Node = child.get_node_or_null("Sprite")
			if nested is Sprite3D:
				return nested
	return null


# ================= 播放 =================

# 播一次捕获演出。attempt_result 只读；FAINTED / INVALID 拒绝并返回 -1（不建图层、不播声音），
# NOT_OBTAINABLE 照原演出并在第一次 onRepeat 失败（不是拒绝）。
func play(ball_type: int, from_world: Vector3, to_world: Vector3, attempt_result: Dictionary,
		target_snapshot: Dictionary, sound := true) -> int:
	if not _ensure_loaded():
		return -1
	if not (attempt_result is Dictionary):
		return -1
	if not (target_snapshot is Dictionary) or target_snapshot.is_empty() or target_snapshot.get("texture") == null:
		return -1
	var key := ball_atlas_key(ball_type)
	if key == "" or not _ball_frames.has(key):
		return -1
	var res := int(attempt_result.get("result", RESULT_CAPTURED))
	# 死亡 / 非法才根本不该创建播放；不可获得是「先演出、第一次 onRepeat 失败」。
	if res == RESULT_FAINTED or res == RESULT_INVALID:
		return -1
	var captured := bool(attempt_result.get("captured", res == RESULT_CAPTURED))
	var shakes := int(attempt_result.get("shakes", 3 if captured else 1))
	if res == RESULT_NOT_OBTAINABLE:
		# 原 `onRepeat` 先判 `!species.isObtainable()`：连 Master 也不绕过，h 仍 0。
		captured = false
		shakes = 0
	if not captured and (shakes < 0 or shakes > 3):
		return -1

	var p := {
		"id": _next_id,
		"ball_type": ball_type,
		"key": key,
		"from": from_world,
		"to": to_world,
		"ground": to_world + Vector3(0.0, -BOUNCE_RANGE_PX * PX, 0.0),
		"captured": captured,
		"shakes": shakes,
		"result": res,
		"sound": sound,
		"t": 0.0,
		"ball_frame": key,
		"ball_pos": from_world,
		"ball_angle_deg": 0.0,
		"ball_alpha": 1.0,
		"ball_visible": true,
		"target_scale": 1.0,
		"target_pos": Vector3.ZERO,
		"target_modulate": Color.WHITE,
		"target_visible": true,
		"flash_alpha": 0.0,
		"flash_visible": false,
		"flash": null,
		"flash_t0": -1.0,
		"open_pos": to_world,
		"remove_t": -1.0,
		"fail_t": -1.0,
		"absorb_t": -1.0,
		"events": [],
		"ei": 0,
		"cues": [],
		"particles": [],
		"stars": [],
		"audio": [],
		"finished": false,
		"visual_end": T_END,
		"snap_name": str(target_snapshot.get("name", "")),
	}
	_next_id += 1
	p["tint"] = ball_tint(ball_type)
	p["snap"] = target_snapshot.duplicate()
	p["ball"] = _new_sprite(_ball_frames[key]["tex"], PX, _origin_offset(_ball_frames[key], BALL_ORIGIN), false, Color.WHITE)
	p["target"] = _new_sprite(target_snapshot["texture"], float(target_snapshot.get("pixel_size", PX)),
		target_snapshot.get("offset", Vector2.ZERO), bool(target_snapshot.get("flip_h", false)),
		target_snapshot.get("modulate", Color.WHITE))
	p["target_scale_base"] = target_snapshot.get("global_scale", Vector3.ONE)
	_build_events(p)
	_plays.append(p)
	_advance_play(p, 0.0)
	if bool(p["finished"]):
		_free_play(p)
		_plays.erase(p)
	return int(p["id"])


func play_count() -> int:
	return _plays.size()


func last_play() -> Dictionary:
	return _plays.back() if not _plays.is_empty() else {}


# 活动播放返回每帧状态（finished=false）；已结束的返回 `_done` 摘要（finished=true，
# 没有每帧几何字段，见文件头契约）。调用者要判断结束请用 finished / play_count()，
# 不要在摘要上读 ball_pos / particles_state 这类活动字段。
func play_state(id: int) -> Dictionary:
	for p in _plays:
		if int(p["id"]) == id:
			return p
	for p in _done:
		if int(p["id"]) == id:
			return p
	return {}


# 是否还有这条 id 的活动播放（结束摘要不算）。等价于 play_state(id).get("finished", true)。
func is_active(id: int) -> bool:
	for p in _plays:
		if int(p["id"]) == id:
			return true
	return false


# ================= 事件表 =================

func _build_events(p: Dictionary) -> void:
	var ev: Array = []
	ev.append({"t": 0.0, "name": &"throw"})
	ev.append({"t": T_OPEN, "name": &"open"})
	ev.append({"t": T_OPEN_FRAME, "name": &"open_frame"})
	ev.append({"t": T_CATCH, "name": &"catch"})
	ev.append({"t": T_BALL_BASE, "name": &"ball_base"})
	ev.append({"t": T_BOUNCE, "name": &"bounce_start"})
	var landings := bounce_landings()
	for i in landings.size():
		ev.append({"t": T_BOUNCE + float(landings[i]["t"]), "name": &"bounce_land",
			"factor": float(landings[i]["factor"]), "index": i + 1})
	ev.append({"t": T_SHAKE, "name": &"shake_start"})
	var fail_index := 0
	if not bool(p["captured"]):
		fail_index = clampi(int(p["shakes"]), 1, 3)
	# 前 3 次 onRepeat 才是判定（move / fail）；第 4 次 onRepeat 走锁定，不是第 4 次 move。
	for k in range(1, 4):
		var tk := T_SHAKE + float(k) * SHAKE_CYCLE_MS
		if bool(p["captured"]) or k < fail_index:
			ev.append({"t": tk, "name": &"move", "shake": k})
		elif k == fail_index:
			ev.append({"t": tk, "name": &"fail", "shake": k})
			ev.append({"t": tk + OPEN_AFTER_MS, "name": &"fail_open", "shake": k})
			break
	if bool(p["captured"]):
		ev.append({"t": T_LOCK, "name": &"lock"})
		ev.append({"t": T_COMPLETE, "name": &"complete"})
		ev.append({"t": T_END, "name": &"end"})
	else:
		var fail_t := T_SHAKE + float(fail_index) * SHAKE_CYCLE_MS
		ev.append({"t": fail_t + FAIL_CLEANUP_MS, "name": &"end"})
	for i in ev.size():
		ev[i]["seq"] = i
	ev.sort_custom(func(a, b):
		if float(a["t"]) == float(b["t"]):
			return int(a["seq"]) < int(b["seq"])
		return float(a["t"]) < float(b["t"]))
	p["events"] = ev
	p["visual_end"] = float(ev[ev.size() - 1]["t"])


static func bounce_landings() -> Array:
	var out: Array = []
	var t := BOUNCE_BASE_MS                # 第一次落地：o=1 的下落
	out.append({"t": t, "factor": BOUNCE_FACTORS[0]})
	for i in range(1, BOUNCE_FACTORS.size()):
		var o: float = BOUNCE_FACTORS[i]
		t += 2.0 * BOUNCE_BASE_MS * o      # 上升 + 再次下落
		out.append({"t": t, "factor": o})
	return out


# ================= 推进 =================

func advance(delta: float) -> void:
	if paused:
		return
	var i := 0
	while i < _plays.size():
		var p: Dictionary = _plays[i]
		_advance_play(p, delta)
		if bool(p["finished"]):
			_free_play(p)
			_plays.remove_at(i)
		else:
			i += 1


func _advance_play(p: Dictionary, delta: float) -> void:
	if bool(p["finished"]):
		return
	var want := float(p["t"]) + maxf(0.0, delta) * 1000.0
	var evs: Array = p["events"]
	while int(p["ei"]) < evs.size() and float(evs[int(p["ei"])]["t"]) <= want + 0.000001:
		var ev: Dictionary = evs[int(p["ei"])]
		p["t"] = maxf(float(p["t"]), float(ev["t"]))
		_fire(p, ev)
		p["ei"] = int(p["ei"]) + 1
	p["t"] = want
	_apply_continuous(p)
	if float(p["t"]) + 0.000001 >= float(p["visual_end"]):
		p["t"] = float(p["visual_end"])
		_apply_continuous(p)
		p["finished"] = true


func _fire(p: Dictionary, ev: Dictionary) -> void:
	var name: StringName = ev["name"]
	(p["cues"] as Array).append({"t": float(ev["t"]), "name": String(name)})
	match name:
		&"throw":
			_play_sound(p, "pb_throw")
		&"open":
			p["ball_frame"] = str(p["key"]) + "_opening"
			p["absorb_t"] = float(ev["t"])
			p["open_pos"] = p["to"]
			_play_sound(p, "pb_rel")
			_spawn_particles(p, float(ev["t"]))
		&"open_frame":
			p["ball_frame"] = str(p["key"]) + "_open"
		&"catch":
			p["ball_frame"] = str(p["key"]) + "_opening"
			_play_sound(p, "pb_catch")
		&"ball_base":
			p["ball_frame"] = str(p["key"])
		&"bounce_start":
			pass
		&"bounce_land":
			_play_sound(p, "pb_bounce_1", float(ev.get("factor", 1.0)))
		&"shake_start":
			pass
		&"move":
			_play_sound(p, "pb_move")
		&"fail":
			p["fail_t"] = float(ev["t"])
			p["remove_t"] = float(ev["t"])
			p["ball_frame"] = str(p["key"]) + "_opening"
			_play_sound(p, "pb_rel")
		&"fail_open":
			p["ball_frame"] = str(p["key"]) + "_open"
		&"lock":
			_play_sound(p, "pb_lock")
			_spawn_stars(p, float(ev["t"]))
			_spawn_flash(p, float(ev["t"]))
		&"complete":
			p["remove_t"] = float(ev["t"])
		&"end":
			pass
	cue.emit(int(p["id"]), name)


# ================= 每帧连续状态 =================

func _apply_continuous(p: Dictionary) -> void:
	var t := float(p["t"])
	var vb := _view_basis()
	# ---- 球 ----
	var pos := p["to"] as Vector3
	var angle := 0.0
	if t < T_OPEN:
		pos = _throw_pos(p, t)
	elif t < T_BOUNCE:
		pos = p["to"]
	elif t < T_SHAKE:
		pos = _bounce_pos(p, t)
	else:
		var ts := t
		if float(p["fail_t"]) >= 0.0:
			ts = minf(t, float(p["fail_t"]))
		var sh := _shake_profile(ts - T_SHAKE)
		pos = (p["ground"] as Vector3) + _screen_offset(vb, sh.x, 0.0)
		angle = sh.y
	p["ball_pos"] = pos
	p["ball_angle_deg"] = angle
	var alpha := 1.0
	if float(p["remove_t"]) >= 0.0:
		var e := t - float(p["remove_t"])
		if e <= REMOVE_DELAY_MS:
			alpha = 1.0
		elif e < REMOVE_DELAY_MS + REMOVE_FADE_MS:
			alpha = cos(((e - REMOVE_DELAY_MS) / REMOVE_FADE_MS) * PI * 0.5)
		else:
			alpha = 0.0
	p["ball_alpha"] = alpha
	p["ball_visible"] = alpha > 0.001
	_set_view_sprite(p["ball"], pos, angle, Vector3.ONE)
	(p["ball"] as Sprite3D).modulate = Color(1.0, 1.0, 1.0, alpha)
	(p["ball"] as Sprite3D).visible = bool(p["ball_visible"])
	if _ball_frames.has(str(p["ball_frame"])):
		(p["ball"] as Sprite3D).texture = _ball_frames[str(p["ball_frame"])]["tex"]

	# ---- 目标快照副本 ----
	var snap: Dictionary = p["snap"]
	var base_pos: Vector3 = snap.get("global_position", Vector3.ZERO)
	var base_mod: Color = snap.get("modulate", Color.WHITE)
	var base_scale: Vector3 = p["target_scale_base"]
	var tint: Color = p["tint"]
	var tpos := base_pos
	var tscale := 1.0
	var tmod := base_mod
	var tvis := true
	if float(p["fail_t"]) >= 0.0 and t >= float(p["fail_t"]):
		var e := t - float(p["fail_t"])
		var pr := _sine_out(clampf(e / SHAKE_MS, 0.0, 1.0))
		tpos = base_pos
		tscale = lerpf(ABSORB_SCALE, 1.0, pr)
		tmod = base_mod * tint.lerp(Color.WHITE, pr)
		tvis = true
	elif t < T_OPEN:
		tpos = base_pos
		tscale = 1.0
		tmod = base_mod
		tvis = true
	elif t < T_CATCH:
		var pr := _sine_in(clampf((t - T_OPEN) / ABSORB_MS, 0.0, 1.0))
		tpos = base_pos.lerp(p["to"] as Vector3, pr)
		tscale = lerpf(1.0, ABSORB_SCALE, pr)
		tmod = base_mod * tint
		tvis = true
	else:
		tpos = p["to"]
		tscale = ABSORB_SCALE
		tmod = base_mod * tint
		tvis = false
	p["target_pos"] = tpos
	p["target_scale"] = tscale
	p["target_modulate"] = tmod
	p["target_visible"] = tvis
	var target: Sprite3D = p["target"]
	if target != null and is_instance_valid(target):
		_set_view_sprite(target, tpos, 0.0, base_scale * tscale)
		target.modulate = tmod
		target.visible = tvis

	_apply_stars(p, vb, t)
	_apply_flash(p, t)
	_apply_particles(p, vb, t)


func _throw_pos(p: Dictionary, t: float) -> Vector3:
	var u := clampf(t / THROW_MS, 0.0, 1.0)
	var from := p["from"] as Vector3
	var to := p["to"] as Vector3
	# 横向线性；纵向从实际起点 Y 到实际 catch 点 Y，按原 Cubic.easeOut（源 y:80→16 的等价）。
	# 不再额外加 THROW_LIFT_PX * PX：游戏给的 from_world / to_world 就是实际起终点。
	var e := _cubic_out(u)
	return Vector3(
		lerpf(from.x, to.x, u),
		lerpf(from.y, to.y, e),
		lerpf(from.z, to.z, u))


func _bounce_pos(p: Dictionary, t: float) -> Vector3:
	var dt := t - T_BOUNCE
	var ground := p["ground"] as Vector3
	if dt <= BOUNCE_BASE_MS:
		return (p["to"] as Vector3).lerp(ground, _cubic_in(clampf(dt / BOUNCE_BASE_MS, 0.0, 1.0)))
	var acc := BOUNCE_BASE_MS
	for i in range(1, BOUNCE_FACTORS.size()):
		var o: float = BOUNCE_FACTORS[i]
		var d := BOUNCE_BASE_MS * o
		var up_end := acc + d
		var down_end := up_end + d
		var h := BOUNCE_RANGE_PX * o * PX
		if dt < up_end:
			return ground + Vector3(0.0, h * _cubic_out((dt - acc) / d), 0.0)
		if dt < down_end:
			return ground + Vector3(0.0, h * (1.0 - _cubic_in((dt - up_end) / d)), 0.0)
		acc = down_end
	return ground


# h=1/2/3 时 ±4px / ±27.5°、CubicOut 往复；其余时间归零（onUpdate 的 `if(h&&h<4)`）。
static func _shake_profile(dt: float) -> Vector2:
	if dt < SHAKE_CYCLE_MS or dt >= float(SHAKE_REPEAT) * SHAKE_CYCLE_MS:
		return Vector2.ZERO
	var r := int(floor(dt / SHAKE_CYCLE_MS))
	var local := dt - float(r) * SHAKE_CYCLE_MS
	var v := 0.0
	if local < SHAKE_MS:
		v = _cubic_out(local / SHAKE_MS)
	elif local < 2.0 * SHAKE_MS:
		v = _cubic_out(1.0 - (local - SHAKE_MS) / SHAKE_MS)
	var sign := 1.0 if (r % 2 == 1) else -1.0
	return Vector2(v * SHAKE_OFFSET_PX * sign, v * SHAKE_ANGLE_DEG * sign)


func _apply_stars(p: Dictionary, vb: Basis, t: float) -> void:
	var states: Array = []
	for s in p["stars"]:
		var e := t - float(s["t0"])
		var node: Sprite3D = s["node"]
		if e < 0.0 or e >= STAR_MS:
			if node != null and is_instance_valid(node):
				node.visible = false
			states.append({"visible": false, "dx": 0.0, "dy": 0.0, "alpha": 0.0, "alpha_tail": 0.0})
			continue
		var dy := 0.0
		if e < SHAKE_MS:
			dy = -STAR_RISE_PX * _sine_out(e / SHAKE_MS)
		else:
			dy = -STAR_RISE_PX * (1.0 - _sine_in((e - SHAKE_MS) / SHAKE_MS))
		var dx := float(s["gauss"]) * clampf(e / STAR_MS, 0.0, 1.0)
		# 原 Zne 两条 alpha tween 的最终结果（TweenManager.step 按 this.tweens 顺序 update，
		# add 只 push 到末尾；后建的 SineIn tween 下标更大、同帧后写，覆盖 delay425 那条）：
		#   0..250     只有 setAlpha(.5)，第一条 Y-up tween 不写 alpha          → a = .5
		#   250..500   第一条 Y-up 的 onComplete 新建 {alpha:0,SineIn,250} 写 .5→0 → a = .5*cos(((e-250)/250)*PI/2)
		#   425..500   delay425/duration75 那条也写，但先被 update，值被上面覆盖 → 只留档到 alpha_tail
		#   >=500      destroy                                              → 不可见
		var a := 0.5
		var a_tail := 0.0
		if e >= SHAKE_MS:
			a = 0.5 * (1.0 - _sine_in(clampf((e - SHAKE_MS) / SHAKE_MS, 0.0, 1.0)))
		if e >= 425.0:
			# tween 在 delay 结束后的首帧读当前值当 start（≈ .5*cos(.7*PI/2)），再 SineIn 到 0。
			var start3 := 0.5 * (1.0 - _sine_in(175.0 / SHAKE_MS))
			a_tail = start3 * (1.0 - _sine_in(clampf((e - 425.0) / 75.0, 0.0, 1.0)))
		if node != null and is_instance_valid(node):
			node.visible = true
			node.modulate = Color(1.0, 1.0, 1.0, a)
			_set_view_sprite(node, (p["ground"] as Vector3) + _screen_offset(vb, dx, dy), 0.0, Vector3.ONE)
		states.append({"visible": true, "dx": dx, "dy": dy, "alpha": a, "alpha_tail": a_tail,
			"gauss": float(s["gauss"])})
	p["stars_state"] = states


func _apply_flash(p: Dictionary, t: float) -> void:
	var node: Sprite3D = p["flash"]
	if p["flash_t0"] < 0.0:
		p["flash_alpha"] = 0.0
		p["flash_visible"] = false
		return
	var e := t - float(p["flash_t0"])
	var a := 0.0
	if e >= 0.0 and e < FLASH_IN_MS:
		a = FLASH_PEAK * (e / FLASH_IN_MS)
	elif e >= FLASH_IN_MS and e < FLASH_IN_MS + FLASH_OUT_MS:
		a = FLASH_PEAK * (1.0 - (e - FLASH_IN_MS) / FLASH_OUT_MS)
	p["flash_alpha"] = a
	p["flash_visible"] = a > 0.0001
	if node != null and is_instance_valid(node):
		node.visible = bool(p["flash_visible"])
		node.modulate = Color(0.0, 0.0, 0.0, a)


func _apply_particles(p: Dictionary, vb: Basis, t: float) -> void:
	var states: Array = []
	var origin := p["open_pos"] as Vector3
	for pt in p["particles"]:
		var e := t - float(pt["t0"])
		var node: Sprite3D = pt["node"]
		if e < 0.0 or e >= float(pt["life"]):
			if node != null and is_instance_valid(node):
				node.visible = false
			states.append({"visible": false, "kind": str(pt["kind"]), "frame": str(pt["frame"]),
				"dx": 0.0, "dy": 0.0, "alpha": 0.0, "angle": 0.0})
			continue
		var dx := 0.0
		var dy := 0.0
		var a := 1.0
		var frame := str(pt["frame"])
		if str(pt["kind"]) == "radial":
			var pr := clampf(e / RADIAL_MOVE_MS, 0.0, 1.0)
			dx = float(pt["dx"]) * pr
			dy = float(pt["dy"]) * pr
			if e > RADIAL_MOVE_MS - RADIAL_FADE_MS:
				a = cos(clampf((e - (RADIAL_MOVE_MS - RADIAL_FADE_MS)) / RADIAL_FADE_MS, 0.0, 1.0) * PI * 0.5)
			var idx := (int(pt["start_frame"]) + int(floor(e * 16.0 / 1000.0))) % 4
			frame = str(idx) + ".png"
		else:
			var k := maxf(0.0, floor(e / PARTICLE_STEP_MS) - 1.0)
			var ang := float(pt["angle0"]) + k * float(pt["step"])
			dx = sin(ang * PI / 128.0) * k * float(pt["sx"])
			dy = cos(ang * PI / 128.0) * k * float(pt["sy"])
			if e > FAN_FADE_AT_MS:
				a = cos(clampf((e - FAN_FADE_AT_MS) / FAN_FADE_MS, 0.0, 1.0) * PI * 0.5)
		if node != null and is_instance_valid(node):
			node.visible = a > 0.001
			node.modulate = Color(1.0, 1.0, 1.0, a)
			if _part_frames.has(frame):
				node.texture = _part_frames[frame]["tex"]
			_set_view_sprite(node, origin + _screen_offset(vb, dx, dy), 0.0, Vector3.ONE)
		states.append({"visible": a > 0.001, "kind": str(pt["kind"]), "frame": frame,
			"dx": dx, "dy": dy, "alpha": a, "angle": 0.0})
	p["particles_state"] = states


# ================= 粒子 / 星 / 黑闪 =================

func _spawn_particles(p: Dictionary, t0: float) -> void:
	var bt := int(p["ball_type"])
	match bt:
		0:
			_spawn_radial(p, t0, RADIAL_RADIUS[0])
		1:
			_spawn_radial(p, t0, RADIAL_RADIUS[1])
		2, 3:
			for f in 10:
				var ang: float = float(f) * FAN_ANGLE0
				p["particles"].append(_particle(p, t0, str(FAN_FRAME[bt - 2]) + ".png",
					FAN_FADE_AT_MS + FAN_FADE_MS, {"kind": "fan", "angle0": ang, "step": FAN_STEP,
						"sx": 1.0, "sy": 1.0, "frame": str(FAN_FRAME[bt - 2]) + ".png"}))
		4:
			for group in 2:
				var sx := 2.0 if group == 0 else 1.0
				var sy := 1.0 if group == 0 else 2.0
				for f in 8:
					var ang: float = float(f) * MASTER_ANGLE0
					p["particles"].append(_particle(p, t0, str(MASTER_FRAME) + ".png",
						FAN_FADE_AT_MS + FAN_FADE_MS, {"kind": "master", "angle0": ang,
							"step": MASTER_STEP, "sx": sx, "sy": sy, "frame": str(MASTER_FRAME) + ".png"}))
		5:
			pass  # 原 MX switch 没有 LUXURY 分支：无粒子
		_:
			pass


func _spawn_radial(p: Dictionary, t0: float, radius: float) -> void:
	for i in range(1, RADIAL_EMISSIONS + 1):
		var ang := float(i) * 45.0
		var dx := radius * cos(ang * PI / 180.0)
		var dy := radius * sin(ang * PI / 180.0)
		var start_frame := (i + 3) % 4
		p["particles"].append(_particle(p, t0 + float(i) * RADIAL_START_MS,
			str(start_frame) + ".png", RADIAL_MOVE_MS,
			{"kind": "radial", "dx": dx, "dy": dy, "start_frame": start_frame, "frame": str(start_frame) + ".png"}))


func _particle(p: Dictionary, t0: float, frame: String, life: float, extra: Dictionary) -> Dictionary:
	var d := {"t0": t0, "life": life, "node": null}
	d.merge(extra, true)
	d["frame"] = frame
	if _part_frames.has(frame):
		var e: Dictionary = _part_frames[frame]
		d["node"] = _new_sprite(e["tex"], PX, _origin_offset(e, Vector2(0.5, 0.5)), false, Color.WHITE)
	else:
		d["node"] = null
	return d


func _spawn_stars(p: Dictionary, t0: float) -> void:
	if not _part_frames.has(STAR_FRAME):
		return
	var e: Dictionary = _part_frames[STAR_FRAME]
	for i in STAR_COUNT:
		var node := _new_sprite(e["tex"], PX, _origin_offset(e, BALL_ORIGIN), false, Color.WHITE)
		p["stars"].append({"t0": t0, "gauss": _gauss(STAR_GAUSS), "node": node})


func _spawn_flash(p: Dictionary, t0: float) -> void:
	if not _ball_frames.has("pb"):
		return
	var e: Dictionary = _ball_frames["pb"]
	# 原 `add.sprite(pokeball.x, pokeball.y, "pb", "pb")` 用基础球帧 + setTintFill(0) 黑闪。
	p["flash"] = _new_sprite(e["tex"], PX, _origin_offset(e, BALL_ORIGIN), false, Color(0, 0, 0, 0))
	p["flash_t0"] = t0


# 原 Bq(scale)：sqrt(-2 ln(1-Math.random())) cos(2 PI Math.random()) * scale，
# 无上限、不 clamp；用独立视觉 RNG。
func _gauss(scale: float) -> float:
	var u1 := 1.0 - _rng.randf()
	var u2 := _rng.randf()
	return sqrt(-2.0 * log(maxf(u1, 0.0000001))) * cos(2.0 * PI * u2) * scale


# ================= 节点 / 音频 =================

func _new_sprite(texture: Texture2D, pixel_size: float, offset: Vector2, flip_h: bool, color: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	s.pixel_size = pixel_size
	s.offset = offset
	s.flip_h = flip_h
	s.modulate = color
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.alpha_scissor_threshold = 0.1
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	return s


static func _origin_offset(frame: Dictionary, origin: Vector2) -> Vector2:
	var src: Vector2 = frame.get("source", Vector2.ONE)
	return Vector2(src.x * 0.5 - origin.x * src.x, origin.y * src.y - src.y * 0.5)


func _view_basis() -> Basis:
	if cam != null and is_instance_valid(cam):
		return cam.global_transform.basis.orthonormalized()
	return Basis.IDENTITY


# 源屏幕平面位移 → 世界（右 = 视图 x，上 = 视图 y；源 y 向下取负）。
static func _screen_offset(vb: Basis, dx: float, dy: float) -> Vector3:
	return vb.x * (dx * PX) - vb.y * (dy * PX)


func _set_view_sprite(node, pos: Vector3, angle_deg: float, scale_vec: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	var b := _view_basis().rotated(Vector3(0.0, 0.0, 1.0), deg_to_rad(angle_deg)).scaled(scale_vec)
	node.global_transform = Transform3D(b, pos)


func _play_sound(p: Dictionary, name: String, volume_linear := 1.0) -> void:
	if not bool(p["sound"]) or volume_linear <= 0.0:
		return
	if not _sounds.has(name) or _sounds[name] == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = _sounds[name]
	pl.bus = _audio_bus()
	pl.volume_db = linear_to_db(clampf(volume_linear, 0.0001, 1.0))
	# paused 中新建的音频也从暂停状态开始，避免暂停期间漏出声音。
	pl.stream_paused = paused
	add_child(pl)
	pl.finished.connect(_on_audio_done.bind(pl))
	p["audio"].append(pl)
	_audio.append(pl)
	pl.play()


func _on_audio_done(pl) -> void:
	_audio.erase(pl)
	for p in _plays:
		(p["audio"] as Array).erase(pl)
	if is_instance_valid(pl):
		pl.queue_free()


func _audio_bus() -> StringName:
	if AudioServer.get_bus_index("Sfx") >= 0:
		return &"Sfx"
	return &"Master"


# ================= 结束 / 释放 =================

func _free_play(p: Dictionary) -> void:
	for key in ["ball", "target", "flash"]:
		var n = p.get(key)
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
		p[key] = null
	for s in p["stars"]:
		var n = s.get("node")
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
		s["node"] = null
	for pt in p["particles"]:
		var n = pt.get("node")
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
		pt["node"] = null
	# 音频尾巴：还在播的留在 _audio 里由 finished 收尾（不无故截断），已停的立刻回收。
	for pl in (p["audio"] as Array).duplicate():
		if is_instance_valid(pl) and not pl.playing:
			_on_audio_done(pl)
	p["audio"] = []
	p["finished"] = true
	var summary := {
		"id": int(p["id"]), "ball_type": int(p["ball_type"]), "captured": bool(p["captured"]),
		"shakes": int(p["shakes"]), "result": int(p["result"]), "t": float(p["t"]),
		"visual_end": float(p["visual_end"]), "finished": true,
		"ball_visible": false, "ball_alpha": 0.0, "target_visible": false,
		"cues": (p["cues"] as Array).duplicate(true),
	}
	_done.append(summary)
	if _done.size() > 64:
		_done.pop_front()


# 停掉全部图像 / 粒子 / 自有音频，幂等；可安全在取消 / 退出树里重复调用。
func clear() -> void:
	for p in _plays.duplicate():
		if is_instance_valid(p.get("ball")):
			(p["ball"] as Node).queue_free()
		if is_instance_valid(p.get("target")):
			(p["target"] as Node).queue_free()
		if is_instance_valid(p.get("flash")):
			(p["flash"] as Node).queue_free()
		for s in p["stars"]:
			if is_instance_valid(s.get("node")):
				(s["node"] as Node).queue_free()
			s["node"] = null
		for pt in p["particles"]:
			if is_instance_valid(pt.get("node")):
				(pt["node"] as Node).queue_free()
			pt["node"] = null
		p["audio"] = []
		p["finished"] = true
	_plays.clear()
	_done.clear()
	for pl in _audio:
		if is_instance_valid(pl):
			pl.stop()
			pl.stream = null
			pl.queue_free()
	_audio.clear()
	# 全部图层 / 音频都清了，暂停状态也跟着复位：之后同一实例可以正常复播。
	paused = false


func _exit_tree() -> void:
	clear()


# ================= 缓动（原 Phaser 曲线） =================

static func _cubic_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _cubic_in(p: float) -> float:
	return p * p * p


static func _sine_out(p: float) -> float:
	return sin(clampf(p, 0.0, 1.0) * PI * 0.5)


static func _sine_in(p: float) -> float:
	return 1.0 - cos(clampf(p, 0.0, 1.0) * PI * 0.5)
