extends Node
# 割草小项目的战斗音效：挥刀、砍中、杀怪、挨打、捡经验球、倒下。自成一体，main.gd 只管调下面六个函数。
# 界面音效（卡片悬停 / 选中 / 升级面板 / 倒下的提示音）在 ui/hud.gd 里，这里不重复。
#
# 用法：
#   sfx.swing()  sfx.hit(pos)  sfx.kill(pos, "wolf")  sfx.hurt()  sfx.pickup()  sfx.player_death()
#
# 一刀砍二十只怪、一秒捡几十个球都很常见，所以每种声音都限了数量：
#   gap    两次开始之间至少隔多少秒
#   late   同一瞬间来了好几个时，后面的最多往后排多少秒（0 = 排不上就直接丢掉）
#   burst  window 秒之内最多响几次
#   voices 这种声音同时最多占几个播放器
# 同一刀的几声“砍中”一声比一声小，并且错开几十毫秒，免得叠成一坨。
# 不做方位（相机一直跟着主角，声音都在画面中间附近），pos 参数先留着不用。

const SWING := [
	preload("res://audio/sfx/swing/swing_1.wav"),
	preload("res://audio/sfx/swing/swing_2.wav"),
	preload("res://audio/sfx/swing/swing_3.wav"),
]
const HIT := [
	preload("res://audio/sfx/hit/hit_1.wav"),
	preload("res://audio/sfx/hit/hit_2.wav"),
	preload("res://audio/sfx/hit/hit_3.wav"),
]
const KILL := [
	preload("res://audio/sfx/kill/gore_1.wav"),
	preload("res://audio/sfx/kill/gore_2.wav"),
	preload("res://audio/sfx/kill/gore_3.wav"),
]
const KILL_BANDIT := [
	preload("res://audio/sfx/kill_bandit/grunt_1.wav"),
	preload("res://audio/sfx/kill_bandit/grunt_2.wav"),
	preload("res://audio/sfx/kill_bandit/grunt_3.wav"),
]
const HURT := [
	preload("res://audio/sfx/hurt/hurt_1.wav"),
	preload("res://audio/sfx/hurt/hurt_2.wav"),
	preload("res://audio/sfx/hurt/hurt_3.wav"),
]
const PICKUP := [
	preload("res://audio/sfx/pickup/pickup_1.wav"),
	preload("res://audio/sfx/pickup/pickup_2.wav"),
	preload("res://audio/sfx/pickup/pickup_3.wav"),
]
const PLAYER_DEATH := [
	preload("res://audio/sfx/player_death/death_1.wav"),
]

# db = 相对总音量的高低；pitch = 音高随机浮动的幅度；step_db = 同一阵里每多一声降多少
const EVENTS := {
	"swing": {"streams": SWING, "db": -9.0, "pitch": 0.07, "gap": 0.15, "late": 0.0, "burst": 99, "window": 1.0, "voices": 2, "step_db": 0.0},
	"hit": {"streams": HIT, "db": -5.0, "pitch": 0.08, "gap": 0.04, "late": 0.09, "burst": 3, "window": 0.30, "voices": 3, "step_db": 2.5},
	"kill": {"streams": KILL, "db": -2.0, "pitch": 0.06, "gap": 0.05, "late": 0.06, "burst": 2, "window": 0.30, "voices": 3, "step_db": 2.0},
	"kill_bandit": {"streams": KILL_BANDIT, "db": -6.0, "pitch": 0.06, "gap": 0.35, "late": 0.0, "burst": 99, "window": 1.0, "voices": 2, "step_db": 0.0},
	"hurt": {"streams": HURT, "db": 0.0, "pitch": 0.06, "gap": 0.22, "late": 0.0, "burst": 99, "window": 1.0, "voices": 2, "step_db": 0.0},
	"pickup": {"streams": PICKUP, "db": -11.0, "pitch": 0.03, "gap": 0.07, "late": 0.0, "burst": 99, "window": 1.0, "voices": 3, "step_db": 0.0},
	"player_death": {"streams": PLAYER_DEATH, "db": 0.0, "pitch": 0.03, "gap": 1.0, "late": 0.0, "burst": 99, "window": 1.0, "voices": 1, "step_db": 0.0},
}
const POOL_SIZE := 16          # 各种声音的 voices 加起来正好 16，所以池子不会不够用
const BUS := "Sfx"             # 自己建一条总线，上面挂限幅器兜底；没建成就走 Master
const PICKUP_STREAK_GAP := 0.6 # 连着捡球：隔这么久没捡就从头算
const PICKUP_STREAK_MAX := 14  # 连捡时音高一声比一声高，每声半个半音，最多升 7 个半音
const KIND_PITCH := {"wolf": 1.12, "bandit": 0.92}   # 狼的死亡声高一点，山贼低一点；别的怪用原音高

var volume_db := -8.0          # 这些音效的总音量
var enabled := true
var bandit_voice := false      # 山贼死的时候再叠一声男声。关着：那三个文件是在念“one / two / ten”（用户 10-14 听出来的，v2.0.3）

# 统计，给 audio/sfx_test.gd 用：asked = 被叫了多少次，played = 真响了多少次，peak = 同时最多占了几个播放器
var stats := {}

var _players: Array[AudioStreamPlayer] = []
var _voice_ev: Array[String] = []
var _starts := {}      # 事件名 -> 最近 window 秒里各次开始的时刻
var _last_var := {}    # 事件名 -> 上次用的是第几个变体（不连着放同一个）
var _queue: Array[Dictionary] = []
var _streak := 0
var _streak_at := -10.0
var _movie := false
var _movie_fps := 60.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 录像模式（--write-movie）下画面和声音不按真实时间走，改用帧数算时间
	_movie = OS.has_feature("movie")
	_movie_fps = float(ProjectSettings.get_setting("editor/movie_writer/fps", 60))
	var bus := _ensure_bus()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
		_voice_ev.append("")
	for ev: String in EVENTS:
		_starts[ev] = []
		_last_var[ev] = -1
		stats[ev] = {"asked": 0, "played": 0, "peak": 0}


# ================= 对外接口 =================

# 主角挥刀（每次出刀都调，砍没砍中都算）
func swing() -> void:
	_request("swing")


# 砍中一只怪（一刀可以调很多次，最多响三声）
func hit(_pos: Vector3) -> void:
	_request("hit")


# 怪死了。kind 是 "wolf" 或 "bandit"；不认识的怪只放通用的那一声
func kill(_pos: Vector3, kind: String) -> void:
	_request("kill", float(KIND_PITCH.get(kind, 1.0)))
	if kind == "bandit" and bandit_voice:
		_request("kill_bandit")


# 主角挨打
func hurt() -> void:
	_request("hurt")


# 捡到经验球。连着捡的时候音高一路往上走
func pickup() -> void:
	var now := _now()
	if now - _streak_at > PICKUP_STREAK_GAP:
		_streak = 0
	if _request("pickup", pow(2.0, _streak * 0.5 / 12.0)):
		_streak = min(_streak + 1, PICKUP_STREAK_MAX)
		_streak_at = now


# 主角倒下（界面那声提示音由 hud 放，这里是倒地和刀落地的声音）
func player_death() -> void:
	_queue.clear()
	_request("player_death")


# 某种声音现在占着几个播放器；不给名字就是全部
func _exit_tree() -> void:
	_queue.clear()
	for voice in _players:
		voice.stop()
		voice.stream = null


func active_voices(ev := "") -> int:
	var n := 0
	for i in _players.size():
		if _players[i].playing and (ev == "" or _voice_ev[i] == ev):
			n += 1
	return n


# ================= 内部 =================

func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var now := _now()
	var i := 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		if float(q["at"]) <= now:
			_queue.remove_at(i)
			_start(q["ev"], q["pitch"], q["db"])
		else:
			i += 1


func _now() -> float:
	if _movie:
		return Engine.get_process_frames() / _movie_fps
	return Time.get_ticks_usec() / 1000000.0


# 按 gap / late / burst 决定这一声放不放、什么时候放。返回 false = 丢掉了
func _request(ev: String, pitch_mul := 1.0) -> bool:
	var st: Dictionary = stats[ev]
	st["asked"] += 1
	if not enabled:
		return false
	var cfg: Dictionary = EVENTS[ev]
	var now := _now()
	var starts: Array = _starts[ev]
	while not starts.is_empty() and float(starts[0]) < now - float(cfg["window"]):
		starts.pop_front()
	if starts.size() >= int(cfg["burst"]):
		return false
	var at := now
	if not starts.is_empty():
		at = max(now, float(starts[-1]) + float(cfg["gap"]))
	if at - now > float(cfg["late"]) + 0.0005:
		return false
	var db: float = float(cfg["db"]) - float(cfg["step_db"]) * starts.size()
	starts.append(at)
	if at <= now:
		return _start(ev, pitch_mul, db)
	_queue.append({"at": at, "ev": ev, "pitch": pitch_mul, "db": db})
	return true


func _start(ev: String, pitch_mul: float, db: float) -> bool:
	var cfg: Dictionary = EVENTS[ev]
	var free_i := -1
	var busy := 0
	for i in _players.size():
		if _players[i].playing:
			if _voice_ev[i] == ev:
				busy += 1
		elif free_i < 0:
			free_i = i
	if busy >= int(cfg["voices"]) or free_i < 0:
		return false
	var streams: Array = cfg["streams"]
	var v := randi() % streams.size()
	if streams.size() > 1 and v == int(_last_var[ev]):
		v = (v + 1 + randi() % (streams.size() - 1)) % streams.size()
	_last_var[ev] = v
	var jitter: float = cfg["pitch"]
	var p := _players[free_i]
	p.stream = streams[v]
	p.pitch_scale = pitch_mul * randf_range(1.0 - jitter, 1.0 + jitter)
	p.volume_db = volume_db + db
	p.play()
	_voice_ev[free_i] = ev
	var st: Dictionary = stats[ev]
	st["played"] += 1
	st["peak"] = max(int(st["peak"]), busy + 1)
	return true


# 建一条挂着限幅器的 Sfx 总线（重开一局时场景会重载，已经有了就直接用）
func _ensure_bus() -> StringName:
	if AudioServer.get_bus_index(BUS) >= 0:
		return BUS
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -2.0
	AudioServer.add_bus_effect(idx, lim)
	return BUS
