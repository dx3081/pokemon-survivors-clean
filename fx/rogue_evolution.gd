extends CanvasLayer
# Rogue (PokeRogue) evolution presentation, adapted from the source Phaser
# EvolutionPhase. Only stage timing, particle motion, video, sparkle texture and
# audio are reused; this is not a pixel-exact Phaser port.
#
# Source (read-only): game/assets/index-7def6496.js
#   class EvolutionPhase (search evolutionContainer / doSpiralUpward /
#   doCircleInward / doCycle / doSpray), helpers Fi / $A / ST / ai.
#
# Contract:
#   signal finished
#   play_evolution(from_id, to_id, from_portrait, to_portrait) -> void
# Presentation only: it never touches race data, level, HP, Engine.time_scale or
# get_tree().paused. It runs in PROCESS_MODE_ALWAYS with its own clock so it
# survives a paused gameplay loop. finished is emitted exactly once per play,
# both for the normal ending and for the skip entry.

signal finished

# PokeRogue internal coordinate space for the evolution stage (320x132: the
# 320x180 canvas minus the 48px message area; default_bg is 320x132).
const STAGE := Vector2(320.0, 132.0)
const CENTER := Vector2(160.0, 66.0)
const STEP := 1.0 / 60.0

const SPARKLE_PATH := "res://assets/pokemon/evolution_fx/evo_sparkle.png"
const DEFAULT_BG_PATH := "res://assets/pokemon/evolution_fx/default_bg.png"
const VIDEO_PATH := "res://assets/pokemon/evolution_fx/evo_bg.ogv"
const SHADER_PATH := "res://fx/rogue_evolution.gdshader"
const MUSIC_PATH := "res://assets/pokemon/evolution_fx/audio/evolution.mp3"
const FANFARE_PATH := "res://assets/pokemon/evolution_fx/audio/evolution_fanfare.mp3"
const SFX_PATHS := {
	"charge": "res://assets/pokemon/evolution_fx/audio/charge.wav",
	"beam": "res://assets/pokemon/evolution_fx/audio/beam.wav",
	"sparkle": "res://assets/pokemon/evolution_fx/audio/sparkle.wav",
	"shine": "res://assets/pokemon/evolution_fx/audio/shine.wav",
}
const NAMES := {10: "绿毛虫", 11: "铁甲蛹", 12: "巴大蝶"}

# Particle kinds, mirroring doSpiralUpward / doArcDownward / doCircleInward / doSpray.
const P_SPIRAL := 0
const P_ARC := 1
const P_CIRCLE := 2
const P_SPRAY := 3


class _Particle:
	var sprite: Sprite2D
	var kind := 0  # P_SPIRAL
	var angle := 0.0
	var l := 0
	var f := 0.0
	var o := 0.0
	var age := 0
	var drift := 0
	var amp := 0.0
	var yoff := 0
	var shrink := 0


var _built := false
var _active := false
var _finished := true
var _skip_requested := false
var _elapsed := 0.0
var _particle_accum := 0.0
var _from_id := 10
var _to_id := 11

var _stage: Node2D
# 进化时背后那块大幕布（用户 2026-10-15 截图 / 2026-10-17 “能做的就推进”）：关掉，只留宝可梦自己的进化动画、
# 光点和白闪，战场照常露在后面。三层背景（竞技场底图 / 进化视频 / 变暗层）都不显示；计时和事件照旧走。
const SHOW_BACKDROP := false
var _base_bg: Control
var _video: VideoStreamPlayer
var _bg_overlay: ColorRect
var _base_sprite: Sprite2D
var _base_tint: Sprite2D
var _evo_sprite: Sprite2D
var _evo_tint: Sprite2D
var _white_flash: ColorRect
var _particle_layer: Node2D
var _root: Control
var _name_label: Label
var _skip_button: Button
var _music: AudioStreamPlayer
var _fanfare: AudioStreamPlayer
var _sfx: AudioStreamPlayer

var _sparkle: Texture2D
var _particles: Array = []

var _spiral_on := false
var _arc_on := false
var _circle_on := false
var _spray_on := false
var _spiral_t := 0
var _arc_t := 0
var _circle_t := 0
var _spray_t := 0

var _stages: Array = []
var _stage_index := 0
var _cycle_segs: Array = []
var _finish_at := 0.0

# Timeline (seconds). Video / particle stages follow the source tween chain.
const T_BG_FADE_START := 1.5
const T_BG_FADE_END := 3.0
const T_VIDEO := 4.0
const T_HIDE_BASE := 6.0
const T_ARC := 7.1
const T_CYCLE := 8.6

var _t_video := T_VIDEO
var _t_hide_base := T_HIDE_BASE
var _t_arc := T_ARC
var _t_cycle := T_CYCLE
var _t_circle := 0.0
var _t_white := 0.0
var _t_peak := 0.0
var _t_fade_start := 0.0
var _t_fade_end := 0.0
var _t_dark_end := 0.0
var _t_done := 0.0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_ensure_built()
	set_process(_active)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_stop_playback()


# --- public API ---

func play_evolution(from_id: int, to_id: int, from_portrait: Texture2D, to_portrait: Texture2D) -> void:
	_ensure_built()
	if _active:
		_stop_playback()
	_from_id = from_id
	_to_id = to_id
	_reset_visuals(from_portrait, to_portrait)
	_reset_timeline()
	_elapsed = 0.0
	_particle_accum = 0.0
	_skip_requested = false
	_finished = false
	_active = true
	_name_label.text = "正在进化：%s…" % _name_of(from_id)
	visible = true
	_layout()
	_run_stage("intro")
	_stage_index = 1
	set_process(true)


# --- build ---

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_sparkle = load(SPARKLE_PATH)

	_stage = Node2D.new()
	_stage.name = "Stage"
	add_child(_stage)

	# Original Rogue arena backdrop (320x132, default_bg.png); dark ColorRect is
	# only a fallback if the copied asset is missing.
	var bg_tex: Texture2D = load(DEFAULT_BG_PATH)
	if bg_tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.texture = bg_tex
		bg_rect.position = Vector2.ZERO
		bg_rect.size = STAGE
		bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
		bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_base_bg = bg_rect
	else:
		var bg_color := ColorRect.new()
		bg_color.color = Color(0.10, 0.10, 0.14, 1.0)
		bg_color.position = Vector2.ZERO
		bg_color.size = STAGE
		bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_base_bg = bg_color
	_base_bg.visible = SHOW_BACKDROP
	_stage.add_child(_base_bg)

	_video = VideoStreamPlayer.new()
	_video.name = "EvoBg"
	var vs: VideoStream = load(VIDEO_PATH)
	if vs != null:
		_video.stream = vs
	_video.position = Vector2.ZERO
	_video.size = STAGE
	_video.expand = true
	_video.loop = false
	_video.visible = false
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_video)

	_bg_overlay = ColorRect.new()
	_bg_overlay.color = Color(0x26 / 255.0, 0x26 / 255.0, 0x26 / 255.0, 1.0)
	_bg_overlay.position = Vector2.ZERO
	_bg_overlay.size = STAGE
	_bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_overlay.modulate.a = 0.0
	_bg_overlay.visible = SHOW_BACKDROP
	_stage.add_child(_bg_overlay)

	var tint_mat := _make_tint_material()
	_base_sprite = _make_portrait_sprite(tint_mat, false)
	_base_tint = _make_portrait_sprite(tint_mat, true)
	_evo_sprite = _make_portrait_sprite(tint_mat, false)
	_evo_tint = _make_portrait_sprite(tint_mat, true)
	_evo_sprite.visible = false
	_evo_tint.visible = false

	_particle_layer = Node2D.new()
	_particle_layer.name = "Particles"
	_stage.add_child(_particle_layer)

	_build_ui()

	_music = AudioStreamPlayer.new()
	_music.name = "EvolutionMusic"
	_music.stream = load(MUSIC_PATH)
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_fanfare = AudioStreamPlayer.new()
	_fanfare.name = "EvolutionFanfare"
	_fanfare.stream = load(FANFARE_PATH)
	_fanfare.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fanfare)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "EvolutionSfx"
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)

	visible = false


func _make_tint_material() -> ShaderMaterial:
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _make_portrait_sprite(tint_mat: ShaderMaterial, tinted: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = true
	s.position = CENTER
	if tinted and tint_mat != null:
		s.material = tint_mat
		s.modulate.a = 0.0
	_stage.add_child(s)
	return s


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Ui"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# 闪白铺满整个屏幕（用户 2026-10-19：“进化有个大白边，去掉”）：以前闪白只盖舞台那块矩形，半透明时能看到一个白色大方框的边。
	_white_flash = ColorRect.new()
	_white_flash.color = Color.WHITE
	_white_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white_flash.modulate.a = 0.0
	_root.add_child(_white_flash)

	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_name_label.offset_top = -48.0
	_name_label.offset_bottom = -14.0
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 6)
	_root.add_child(_name_label)

	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "跳过 SKIP (Esc)"
	_skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left = -170.0
	_skip_button.offset_top = -50.0
	_skip_button.offset_right = -16.0
	_skip_button.offset_bottom = -16.0
	_skip_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_skip_button.pressed.connect(_request_skip)
	_root.add_child(_skip_button)


# --- timeline ---

func _reset_timeline() -> void:
	var cycle_total := _cycle_duration()
	_t_circle = T_CYCLE + cycle_total          # real new form + circle-inward
	_t_white = _t_circle + 0.9                 # evolve: spray + white flash
	_t_peak = _t_white + 0.25                  # dark overlay on, video hidden
	_t_fade_start = _t_peak + 0.15             # white flash + evo tint fade out
	_t_fade_end = _t_fade_start + 2.0
	_t_dark_end = _t_fade_end + 0.25
	_t_done = _t_dark_end + 0.5 + 1.25         # cry gap + fanfare + done text
	_finish_at = _t_done + 2.5
	_stages = [
		{"t": 0.0, "key": "intro"},
		{"t": 1.0, "key": "music"},
		{"t": _t_video, "key": "video"},
		{"t": _t_hide_base, "key": "hide_base"},
		{"t": _t_arc, "key": "arc"},
		{"t": _t_cycle, "key": "cycle"},
		{"t": _t_circle, "key": "circle"},
		{"t": _t_white, "key": "white"},
		{"t": _t_peak, "key": "peak"},
		{"t": _t_done, "key": "done"},
	]
	_build_cycle_segments(_t_cycle)


func _run_stage(key: String) -> void:
	match key:
		"intro":
			pass
		"music":
			if _music.stream != null:
				_music.play()
		"video":
			_video.visible = SHOW_BACKDROP
			if _video.stream != null:
				_video.play()
			_play_sfx("charge")
			_start_spiral()
		"hide_base":
			_base_sprite.visible = false
		"arc":
			_play_sfx("beam")
			_start_arc()
		"cycle":
			_evo_tint.visible = true
			_evo_tint.scale = Vector2.ONE * 0.25
		"circle":
			_play_sfx("sparkle")
			_evo_sprite.visible = true
			_base_tint.visible = false  # source hides the old-form tint after the pulse cycle
			_start_circle()
		"white":
			_play_sfx("shine")
			_start_spray()
		"peak":
			# Source hides the evolution video when the dark overlay reaches full.
			# Do it once here instead of calling stop() every frame.
			_video.stop()
			_video.visible = false
		"done":
			_music.stop()
			if _fanfare.stream != null:
				_fanfare.play()
			_name_label.text = "%s 进化成了 %s！" % [_name_of(_from_id), _name_of(_to_id)]


func _advance_stages() -> void:
	while _stage_index < _stages.size() and _elapsed >= float(_stages[_stage_index]["t"]):
		_run_stage(_stages[_stage_index]["key"])
		_stage_index += 1


# Source doCycle: t = 1 -> 15 step 0.5, each step 500/t ms, yoyo except the last.
func _cycle_duration() -> float:
	var total := 0.0
	var t := 1.0
	while t <= 15.0:
		var dur := 0.5 / t
		total += dur
		if t < 15.0:
			total += dur
		t += 0.5
	return total


func _build_cycle_segments(start: float) -> void:
	_cycle_segs.clear()
	var cursor := start
	var t := 1.0
	while t <= 15.0:
		var dur := 0.5 / t
		var last := t > 15.0 - 0.0001
		var seg := {"f0": cursor, "f1": cursor + dur, "b0": -1.0, "b1": -1.0}
		cursor += dur
		if not last:
			seg["b0"] = cursor
			seg["b1"] = cursor + dur
			cursor += dur
		_cycle_segs.append(seg)
		t += 0.5


# Returns [base_tint_scale, evo_tint_scale] at absolute time `now`.
func _eval_cycle(now: float) -> Array:
	for seg in _cycle_segs:
		if now < float(seg["f1"]):
			var x := _cubic(clampf((now - float(seg["f0"])) / (float(seg["f1"]) - float(seg["f0"])), 0.0, 1.0))
			return [lerpf(1.0, 0.25, x), lerpf(0.25, 1.0, x)]
		if float(seg["b0"]) >= 0.0 and now < float(seg["b1"]):
			var x2 := _cubic(1.0 - clampf((now - float(seg["b0"])) / (float(seg["b1"]) - float(seg["b0"])), 0.0, 1.0))
			return [lerpf(1.0, 0.25, x2), lerpf(0.25, 1.0, x2)]
	return [0.25, 1.0]


# Phaser Cubic.easeInOut.
static func _cubic(x: float) -> float:
	if x < 0.5:
		return 4.0 * x * x * x
	var u := -2.0 * x + 2.0
	return 1.0 - u * u * u * 0.5


static func _sine_out(x: float) -> float:
	return sin(clampf(x, 0.0, 1.0) * PI * 0.5)


# --- per-frame ---

func _process(delta: float) -> void:
	if not _active or _finished:
		return
	_elapsed += delta
	_advance_stages()
	_update_visuals()
	_particle_accum += delta
	var guard := 0
	while _particle_accum >= STEP and guard < 8:
		_step_particles()
		_particle_accum -= STEP
		guard += 1
	_layout()
	if _skip_requested:
		_finish()
	elif _elapsed >= _finish_at:
		_finish()


func _layout() -> void:
	if not is_inside_tree() or _stage == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var s := minf(vp.x / STAGE.x, vp.y / STAGE.y) * 0.92
	_stage.scale = Vector2(s, s)
	_stage.position = (vp - STAGE * s) * 0.5


func _update_visuals() -> void:
	var e := _elapsed
	# Old form fades to a white silhouette (source pokemonTintSprite alpha 0 -> 1).
	if e < _t_video:
		_base_tint.modulate.a = 0.0
	elif e < _t_hide_base:
		_base_tint.modulate.a = clampf((e - _t_video) / 2.0, 0.0, 1.0)
	else:
		_base_tint.modulate.a = 1.0
	# Dark background overlay.
	var bg := 0.0
	if e >= T_BG_FADE_START and e < T_BG_FADE_END:
		bg = _sine_out((e - T_BG_FADE_START) / (T_BG_FADE_END - T_BG_FADE_START))
	elif e >= T_BG_FADE_END and e < _t_video:
		bg = 1.0
	elif e >= _t_video and e < _t_video + 0.25:
		bg = 1.0 - (e - _t_video) / 0.25
	elif e >= _t_peak and e < _t_dark_end:
		bg = 1.0
	elif e >= _t_dark_end and e < _t_dark_end + 0.25:
		bg = 1.0 - (e - _t_dark_end) / 0.25
	_bg_overlay.modulate.a = clampf(bg, 0.0, 1.0)
	# White flash + new-form tint alpha.
	var white := 0.0
	if e >= _t_white and e < _t_peak:
		white = (e - _t_white) / 0.25
	elif e >= _t_peak and e < _t_fade_start:
		white = 1.0
	elif e >= _t_fade_start and e < _t_fade_end:
		white = 1.0 - (e - _t_fade_start) / 2.0
	_white_flash.modulate.a = clampf(white, 0.0, 1.0)
	var evo_a := 0.0
	if e >= _t_cycle and e < _t_fade_start:
		evo_a = 1.0
	elif e >= _t_fade_start and e < _t_fade_end:
		evo_a = 1.0 - (e - _t_fade_start) / 2.0
	_evo_tint.modulate.a = clampf(evo_a, 0.0, 1.0)
	# Cancelable pulse cycle.
	if _cycle_segs.size() > 0 and e >= _t_cycle and e < _t_fade_start:
		var scales := _eval_cycle(e)
		_base_tint.scale = Vector2.ONE * float(scales[0])
		_evo_tint.scale = Vector2.ONE * float(scales[1])


# --- particles (original frame-based motion, stepped at 60 Hz) ---

func _start_spiral() -> void:
	_spiral_on = true
	_spiral_t = 0


func _start_arc() -> void:
	_arc_on = true
	_arc_t = 0


func _start_circle() -> void:
	_circle_on = true
	_circle_t = 0


func _start_spray() -> void:
	_spray_on = true
	_spray_t = 0


func _step_particles() -> void:
	if _spiral_on:
		_step_spiral_emitter()
	if _arc_on:
		_step_arc_emitter()
	if _circle_on:
		_step_circle_emitter()
	if _spray_on:
		_step_spray_emitter()
	var alive: Array = []
	for p in _particles:
		if _update_particle(p):
			alive.append(p)
		else:
			p.sprite.queue_free()
	_particles = alive


func _step_spiral_emitter() -> void:
	if _spiral_t >= 64:
		_spiral_on = false
		return
	if (_spiral_t & 7) == 0:
		for n in 4:
			_spawn(P_SPIRAL, float((_spiral_t & 120) * 2 + n * 64))
	_spiral_t += 1


func _step_arc_emitter() -> void:
	if _arc_t >= 96:
		_arc_on = false
		return
	if _arc_t < 6:
		for n in 9:
			_spawn(P_ARC, float(n * 16))
	_arc_t += 1


func _step_circle_emitter() -> void:
	if _circle_t >= 48:
		_circle_on = false
		return
	if _circle_t == 0:
		for n in 16:
			_spawn(P_CIRCLE, float(n * 16), 4)
	elif _circle_t == 32:
		for n in 16:
			_spawn(P_CIRCLE, float(n * 16), 8)
	_circle_t += 1


func _step_spray_emitter() -> void:
	# Source doSpray uses repeat:48, i.e. 48 emitter steps (t = 0..47):
	# 8 particles at t=0, then 1 random-angle particle per step.
	if _spray_t >= 48:
		_spray_on = false
		return
	if _spray_t == 0:
		for n in 8:
			_spawn(P_SPRAY, float(n), 0, 48.0 + float(randi() % 64), 3 - (randi() % 8))
	else:
		_spawn(P_SPRAY, float(randi() % 8), 0, 48.0 + float(randi() % 64), 3 - (randi() % 8))
	_spray_t += 1


func _spawn(kind: int, angle: float, shrink := 0, amp := 0.0, drift := 0) -> void:
	if _sparkle == null:
		return
	var s := Sprite2D.new()
	s.texture = _sparkle
	s.centered = true
	var p := _Particle.new()
	p.sprite = s
	p.kind = kind
	p.angle = angle
	match kind:
		P_SPIRAL:
			s.position = Vector2(CENTER.x, 0.0)
			p.f = 48.0
		P_ARC:
			s.position = Vector2(CENTER.x, 0.0)
			s.scale = Vector2.ONE * 0.5
			p.f = 8.0
		P_CIRCLE:
			s.position = CENTER
			p.o = 120.0
			p.shrink = shrink
		P_SPRAY:
			s.position = CENTER
			p.amp = amp
			p.drift = drift
	_particle_layer.add_child(s)
	_particles.append(p)


# Returns true while the particle lives.
func _update_particle(p: _Particle) -> bool:
	match p.kind:
		P_SPIRAL:
			if p.l != 0 and p.sprite.position.y <= 8.0:
				return false
			p.sprite.position = Vector2(CENTER.x, 88.0 - p.l * p.l / 80.0)
			p.sprite.position.y += _psin(p.angle, p.f) / 4.0
			p.sprite.position.x += _pcos(p.angle, p.f)
			p.sprite.scale = Vector2.ONE * (1.0 - p.l / 80.0)
			p.angle += 4.0
			if (p.l & 1) == 1:
				p.f -= 1.0
			p.l += 1
		P_ARC:
			if p.l != 0 and p.sprite.position.y >= 88.0:
				return false
			p.sprite.position = Vector2(CENTER.x, 8.0 + p.l * p.l / 5.0)
			p.sprite.position.y += _psin(p.angle, p.f) / 4.0
			p.sprite.position.x += _pcos(p.angle, p.f)
			p.f = 8.0 + _psin(p.l * 4.0, 40.0)
			p.l += 1
		P_CIRCLE:
			if p.o <= 8.0:
				return false
			p.sprite.position = CENTER
			p.sprite.position.y += _psin(p.angle, p.o)
			p.sprite.position.x += _pcos(p.angle, p.o)
			p.o -= p.shrink
			p.angle += 4.0
		P_SPRAY:
			if p.age >= 128:
				return false
			if (p.age & 3) == 0:
				p.yoff += 1
			p.sprite.position = Vector2(CENTER.x + p.drift * p.age / 3.0, CENTER.y + p.yoff)
			p.sprite.position.y -= _psin(p.angle, p.amp)
			if p.age > 108:
				p.sprite.scale = Vector2.ONE * (1.0 - (p.age - 108) / 20.0)
			p.angle += 1.0
			p.age += 1
	return true


static func _psin(a: float, r: float) -> float:
	return r * sin(a * PI / 128.0)


static func _pcos(a: float, r: float) -> float:
	return r * cos(a * PI / 128.0)


func _clear_particles() -> void:
	for p in _particles:
		if is_instance_valid(p.sprite):
			p.sprite.queue_free()
	_particles.clear()


# --- audio / cleanup ---

func _play_sfx(key: String) -> void:
	if not SFX_PATHS.has(key):
		return
	var st: AudioStream = load(SFX_PATHS[key])
	if st == null:
		return
	_sfx.stream = st
	_sfx.play()


func _request_skip() -> void:
	if _active and not _finished:
		_skip_requested = true


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _finished:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER):
			_request_skip()


func _stop_playback() -> void:
	if _video != null:
		_video.stop()
		_video.visible = false
	if _music != null:
		_music.stop()
	if _fanfare != null:
		_fanfare.stop()
	if _sfx != null:
		_sfx.stop()
	_spiral_on = false
	_arc_on = false
	_circle_on = false
	_spray_on = false
	_clear_particles()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_active = false
	_skip_requested = false
	_stop_playback()
	set_process(false)
	visible = false
	finished.emit()


# --- helpers ---

func _reset_visuals(from_portrait: Texture2D, to_portrait: Texture2D) -> void:
	_base_sprite.texture = from_portrait
	_base_tint.texture = from_portrait
	_evo_sprite.texture = to_portrait
	_evo_tint.texture = to_portrait
	_base_sprite.visible = true
	_base_sprite.modulate.a = 1.0
	_base_tint.visible = true
	_base_tint.modulate.a = 0.0
	_base_tint.scale = Vector2.ONE
	_evo_sprite.visible = false
	_evo_tint.visible = false
	_evo_tint.modulate.a = 0.0
	_evo_tint.scale = Vector2.ONE * 0.25
	_bg_overlay.modulate.a = 0.0
	_white_flash.modulate.a = 0.0
	_video.visible = false
	_clear_particles()


func _name_of(id: int) -> String:
	return NAMES.get(id, "宝可梦 #%d" % id)
