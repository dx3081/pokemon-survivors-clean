extends CanvasLayer
# 地图天气画面（用户 2026-10-20：照原版天气，“原版虽然是回合制，但是可能能适用”）。用原版天气动画（battle-anims/common-*.json）：
#   雨 / 冰雹 / 雪：原版是“PRAS- Weather”图集里的雨点 / 冰粒，每帧几颗、29 帧一循环；原版只在战场那一块播，
#     这里把同一段动画按原坐标铺满整个屏幕（一格一格平铺）并一直循环。
#   晴：原版是“PRAS- Sunny Day”背景（斜条纹光）淡入淡出；用户 2026-10-20 不要条纹、明暗变化留着 →
#     只铺一层暖色、按原版节奏一亮一暗。
#   沙暴：原版没有画面只有声音；这里给一层淡淡的沙色。起雾：原版没有动画；给一层灰白。
# 声音：换天气时播一次原版音效（原版每回合播一次，这里一直播太吵）。
# 用法：overlay.set_weather("rain" / "sun" / "sand" / "snow" / "hail" / "fog" / "")

const DIR := "res://assets/pokemon/move_fx/"
const FRAME_SECS := 0.05
const CELL := 96
const SUN_COLOR := Color(1.0, 0.93, 0.62)   # 晴天暖光
const ANIMS := {}
const SOUNDS := {"rain": "PRSFX- Rain.wav", "hail": "PRSFX- Hail.wav", "snow": "PRSFX- Hail.wav", "sun": "PRSFX- Sunny.wav", "sand": "PRSFX- Sand.wav"}
const TINTS := {}
# 原动画坐标范围（雨 / 冰雹 / 雪三段一样）：x -64..185、y -112..32，加一格 96 像素的图块。
const SPAN := Vector2(185 + 64 + CELL, 32 + 112 + CELL)
const ORIGIN := Vector2(-64, -112)
const DROP_SCALE := 1.0    # 雨点本身照原版画面比例（原版画面 180 像素高 → 屏幕高）
const TILE_SCALE := 0.8    # 平铺间距（屏幕高 720 时一格约 280×190 像素，越小越密）

var kind := ""
var _tint: ColorRect
var _sun: ColorRect
var _drops: Control
var _sheet: Texture2D
var _frames: Array = []   # 每帧 [[x, y, graphicFrame, opacity, zoomX, zoomY], ...]（只留 target 2 = 特效图层）
var _clock := 0.0
var _player: AudioStreamPlayer
var _pool: Array[TextureRect] = []
var _cache := {}


func _init() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	root.add_child(_tint)
	_sun = ColorRect.new()
	_sun.color = SUN_COLOR
	_sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.visible = false
	root.add_child(_sun)
	_drops = Control.new()
	_drops.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drops.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(_drops)
	_player = AudioStreamPlayer.new()
	_player.volume_db = -10.0
	add_child(_player)


func set_weather(k: String) -> void:
	if k == kind:
		return
	kind = k
	_clock = 0.0
	_frames = []
	_tint.visible = TINTS.has(k)
	if _tint.visible:
		_tint.color = TINTS[k]
	_sun.visible = k == "sun"
	if ANIMS.has(k):
		_load_anim(str(ANIMS[k]))
	_hide_drops(0)
	if SOUNDS.has(k):
		var s = _load(DIR + str(SOUNDS[k]))
		if s is AudioStream:
			_player.stream = s
			_player.play()


func _load(path: String):
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _tex(file: String) -> Texture2D:
	return _load(DIR + file) as Texture2D


func _load_anim(file: String) -> void:
	var text := FileAccess.get_file_as_string(DIR + file)
	var d = JSON.parse_string(text)
	if not (d is Dictionary):
		return
	_sheet = _tex(str(d.get("graphic", "")) + ".png")
	for f in d.get("frames", []):
		var row: Array = []
		for s in f:
			if int(s.get("target", -1)) == 2 and bool(s.get("visible", true)):
				row.append([float(s["x"]), float(s["y"]), int(s.get("graphicFrame", 0)), float(s.get("opacity", 255)) / 255.0, float(s.get("zoomX", 100)) / 100.0, float(s.get("zoomY", 100)) / 100.0])
		_frames.append(row)


func _process(delta: float) -> void:
	if kind == "":
		return
	_clock += delta
	if kind == "sun":
		# 原版：淡入到 99/255、停一会、淡出；这里 3 秒一个来回（纯色铺满，比原条纹淡一些）
		var t := fmod(_clock, 3.0) / 3.0
		_sun.modulate.a = 0.04 + 0.14 * sin(t * PI)
	if _frames.is_empty() or _sheet == null:
		return
	var fi := int(_clock / FRAME_SECS) % _frames.size()
	var row: Array = _frames[fi]
	var view: Vector2 = _drops.size
	if view.x <= 0.0:
		return
	var k := view.y / 720.0 * TILE_SCALE
	var dk := view.y / 180.0 * DROP_SCALE
	var tile := SPAN * k
	var cols := int(ceil(view.x / tile.x)) + 1
	var rows := int(ceil(view.y / tile.y)) + 1
	var cols_in_sheet := maxi(1, _sheet.get_width() / CELL)
	var used := 0
	for ty in rows:
		for tx in cols:
			var base := Vector2(tx * tile.x, ty * tile.y)
			for s: Array in row:
				var r := _drop(used)
				used += 1
				var gf := int(s[2])
				var at := r.texture as AtlasTexture
				at.region = Rect2((gf % cols_in_sheet) * CELL, (gf / cols_in_sheet) * CELL, CELL, CELL)
				r.size = Vector2(CELL * float(s[4]), CELL * float(s[5])) * dk
				r.position = base + (Vector2(float(s[0]), float(s[1])) - ORIGIN) * k - r.size * 0.5
				r.modulate.a = float(s[3])
				r.visible = true
	_hide_drops(used)


func _drop(i: int) -> TextureRect:
	while _pool.size() <= i:
		var r := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = _sheet
		r.texture = at
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drops.add_child(r)
		_pool.append(r)
	var rr := _pool[i]
	(rr.texture as AtlasTexture).atlas = _sheet
	return rr


func _hide_drops(from: int) -> void:
	for i in range(from, _pool.size()):
		_pool[i].visible = false


# 测试用：现在这一帧画了几颗雨点 / 冰粒。
func visible_drops() -> int:
	var n := 0
	for r in _pool:
		if r.visible:
			n += 1
	return n
