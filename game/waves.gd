# 绿毛虫波次：沿用原刷怪节奏和同屏上限处理，全部物种来自 data/units.gd。
extends RefCounted






























const RUN_SECONDS := 1200.0
const PHASE_SECONDS := 60.0
const RAMP_START := 0.25
const RAMP_SECS := 300.0

# ===== 松紧循环（用户 2026-10-21：“敌人强度保持松紧松紧的循环”“同一个地图待 20-30 分钟也要这个节奏”）=====
# 刷怪速度和成群 / 包围 / 精英 / 头目按“在这个地区待了多久”算，5 分钟一个大循环，里面套 3 个小波浪
# （用户 2026-10-22 试：原来只有第 1 分钟松，要到第 6 分钟才感觉到“松了”）：
#   0:00–0:45 松 → 0:45–1:30 紧（一群）→ 1:30–2:15 松 → 2:15–3:00 紧（包围）→ 3:00–3:45 松 → 3:45–4:30 更紧（单只来袭 + 大包围；事件 kind 仍叫 "elite"，但 10-15 起就是普通野怪，不再叫精英，用户 2026-10-23 定）
#   → 4:30 头目压轴；每个小波浪比上一个紧一点；
#   5:00 出撤离按钮（main/meta_flow.gd）。撤离到新地区从“松”重来；不撤离也是 5 分钟一轮重来。
#   整体还会越来越难：每过 5 分钟（整局时间，不管换没换地区）怪量 +15%；敌人等级仍跟着玩家等级走（另一套）。
# cycle_mode = false 时走下面旧的 20 分钟总表（只有老检查还用）。
var cycle_mode := true
const CYCLE_SECONDS := 300.0
# 一轮里每一段的平时刷怪速度：[这一段到第几秒结束, 只 / 秒]
const CYCLE_SEGMENTS := [[45.0, 1.0], [90.0, 2.5], [135.0, 1.5], [180.0, 3.5], [225.0, 2.0], [270.0, 4.5], [300.0, 3.0]]
const CYCLE_GROWTH := 0.15
# 只管整局最开始那一轮（撤离后的新地图照旧）——1:00 前保持上一段的速度，1:00–1:30 线性涨到原来的量；1:00 那一群减半。
const FIRST_RAMP_FROM := 60.0
const FIRST_RAMP_TO := 90.0
const FIRST_PACK_SCALE := 0.5
var first_ramp := true   # 老检查要旧节奏时关掉
const CYCLE_EVENTS: Array[Dictionary] = [
    {"at": 60.0, "kind": "pack", "id": "caterpie", "count": 8, "speed": 1.15, "label": "野生宝可梦来了"},     # 第 1 个紧
    {"at": 150.0, "kind": "encircle", "id": "caterpie", "count": 12, "label": "被围住了"},                    # 第 2 个紧
    {"at": 165.0, "kind": "pack", "id": "caterpie", "count": 8, "speed": 1.15},
    {"at": 230.0, "kind": "elite", "id": "caterpie", "count": 1, "label": "野生宝可梦袭来"},               # 第 3 个紧（最紧）
    {"at": 240.0, "kind": "encircle", "id": "caterpie", "count": 16, "label": "被围住了"},
    {"at": 255.0, "kind": "pack", "id": "caterpie", "count": 10, "speed": 1.15},
    {"at": 270.0, "kind": "boss_wild", "count": 1, "label": "头目来了", "final": false},                    # 头目压轴
    {"at": 270.0, "kind": "pack", "id": "caterpie", "count": 8, "speed": 1.15},
]
var _map_cycle := -1        # 这个地区现在在第几轮（换地区重算）
var _map_cycle_next := 0    # 这一轮下一个要触发的事件
var _last_map_time := -1.0

var max_alive := 250
var density := 1.0   # 敌人密度系数（设置页可调）：平时刷怪率和成群事件数量的倍率，头目 / 精英不动
var rng_seed := 0












const PHASES: Array[Dictionary] = [
    {"name": "野生宝可梦", "rate": 0.7, "lv": 1, "speed": 1.0, "xp": 1.0,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 0.9, "lv": 1, "speed": 1.0, "xp": 1.0,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 1.5, "lv": 1, "speed": 1.0, "xp": 1.0,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 1.9, "lv": 1, "speed": 1.0, "xp": 0.9,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 2.7, "lv": 1, "speed": 1.0, "xp": 0.8,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 1.4, "lv": 1, "speed": 1.0, "xp": 0.8,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 2.6, "lv": 2, "speed": 1.0, "xp": 0.7,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 3.0, "lv": 2, "speed": 1.0, "xp": 0.65,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 3.4, "lv": 2, "speed": 1.0, "xp": 0.6,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 4.0, "lv": 2, "speed": 1.0, "xp": 0.5,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 2.2, "lv": 3, "speed": 1.0, "xp": 0.5,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 3.8, "lv": 3, "speed": 1.0, "xp": 0.45,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 4.5, "lv": 4, "speed": 1.05, "xp": 0.45,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 4.5, "lv": 4, "speed": 1.0, "xp": 0.45,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 5.0, "lv": 4, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 2.8, "lv": 4, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 5.0, "lv": 5, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 5.5, "lv": 5, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 5.8, "lv": 6, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 6.0, "lv": 6, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
    {"name": "野生宝可梦", "rate": 3.5, "lv": 6, "speed": 1.0, "xp": 0.4,
        "mix": {"caterpie": 1}},
]














const EVENTS: Array[Dictionary] = [
    {"at": "2:30", "kind": "pack", "id": "caterpie", "count": 8, "speed": 1.15, "label": "野生宝可梦来了"},
    {"at": "3:30", "kind": "encircle", "id": "caterpie", "count": 14, "label": "被围住了"},
    {"at": "4:20", "kind": "pack", "id": "caterpie", "count": 12, "speed": 1.15, "label": "野生宝可梦来了"},
    {"at": "5:00", "kind": "boss_wild", "count": 1, "label": "头目来了", "final": false},
    {"at": "5:00", "kind": "pack", "id": "caterpie", "count": 10, "speed": 1.15},
    {"at": "5:40", "kind": "pack", "id": "caterpie", "count": 10, "speed": 1.15, "label": "野生宝可梦来了"},
    {"at": "6:30", "kind": "encircle", "id": "caterpie", "count": 18, "label": "被围住了"},
    {"at": "7:00", "kind": "elite", "id": "caterpie", "count": 1, "label": "野生宝可梦袭来"},
    {"at": "7:30", "kind": "pack", "id": "caterpie", "count": 14, "lv": 1, "speed": 1.2, "label": "野生宝可梦来了"},
    {"at": "8:00", "kind": "encircle", "id": "caterpie", "count": 22, "label": "被围住了"},
    {"at": "8:30", "kind": "elite", "id": "caterpie", "count": 1, "label": "野生宝可梦袭来"},
    {"at": "9:00", "kind": "elite", "id": "caterpie", "count": 1, "label": "野生宝可梦袭来"},
    {"at": "9:20", "kind": "pack", "id": "caterpie", "count": 8, "label": "野生宝可梦突袭"},
    {"at": "9:40", "kind": "encircle", "id": "caterpie", "count": 22, "label": "被围住了"},
    {"at": "10:00", "kind": "boss_wild", "count": 1, "label": "头目来了", "final": false},
    {"at": "10:00", "kind": "elite", "id": "caterpie", "count": 2},
    {"at": "11:00", "kind": "pack", "id": "caterpie", "count": 18, "lv": 1, "speed": 1.2, "label": "野生宝可梦来了"},
    {"at": "11:30", "kind": "elite", "id": "caterpie", "count": 2, "label": "野生宝可梦袭来"},
    {"at": "12:00", "kind": "encircle", "id": "caterpie", "count": 20, "label": "被围住了"},
    {"at": "12:30", "kind": "pack", "id": "caterpie", "count": 20, "lv": 1, "speed": 1.15, "label": "野生宝可梦涌来"},
    {"at": "12:45", "kind": "pack", "id": "caterpie", "count": 20, "lv": 1, "speed": 1.15},
    {"at": "13:00", "kind": "elite", "id": "caterpie", "count": 2, "label": "野生宝可梦袭来"},
    {"at": "13:30", "kind": "encircle", "id": "caterpie", "count": 24, "label": "被围住了"},
    {"at": "14:00", "kind": "pack", "id": "caterpie", "count": 12, "label": "野生宝可梦突袭"},
    {"at": "14:00", "kind": "elite", "id": "caterpie", "count": 2},
    {"at": "14:30", "kind": "encircle", "id": "caterpie", "count": 30, "label": "被围住了"},
    {"at": "15:00", "kind": "boss_wild", "count": 1, "label": "头目来了", "final": false},
    {"at": "15:00", "kind": "pack", "id": "caterpie", "count": 8},
    {"at": "16:00", "kind": "elite", "id": "caterpie", "count": 3, "label": "野生宝可梦袭来"},
    {"at": "16:30", "kind": "encircle", "id": "caterpie", "count": 28, "label": "被围住了"},
    {"at": "17:00", "kind": "pack", "id": "caterpie", "count": 24, "lv": 2, "speed": 1.25, "label": "野生宝可梦来了"},
    {"at": "17:30", "kind": "elite", "id": "caterpie", "count": 3, "label": "野生宝可梦袭来"},
    {"at": "17:30", "kind": "encircle", "id": "caterpie", "count": 20, "label": "被围住了"},
    {"at": "18:00", "kind": "elite", "id": "caterpie", "count": 3, "label": "野生宝可梦袭来"},
    {"at": "18:20", "kind": "pack", "id": "caterpie", "count": 16, "label": "野生宝可梦突袭"},
    {"at": "18:40", "kind": "encircle", "id": "caterpie", "count": 28, "label": "被围住了"},
    {"at": "19:10", "kind": "elite", "id": "caterpie", "count": 2, "label": "野生宝可梦袭来"},
    {"at": "19:30", "kind": "encircle", "id": "caterpie", "count": 24, "label": "被围住了"},
    {"at": "19:45", "kind": "pack", "id": "caterpie", "count": 24, "lv": 2, "speed": 1.25, "label": "野生宝可梦来了"},

    {"at": "20:00", "kind": "boss_wild", "count": 1, "label": "最终头目来了", "final": true},
    {"at": "20:00", "kind": "elite", "id": "caterpie", "count": 2},
]


const SOFT_FILL := 0.7
const MIN_RATE_SCALE := 0.3
const RESERVE := 12
const BOSS_RESERVE := 4
const EVENT_WAIT := 10.0
var _rng := RandomNumberGenerator.new()
var _ids: Array[String] = []
var _mix_ids: Array = []       # 每一行表一：这局里有的怪
var _mix_weights: Array = []   # 对应的比重
var _events: Array[Dictionary] = []   # 表二换算成秒、按时间排好
var _next_event := 0
var endless := true       # 无尽：20 分钟一轮，事件表按轮重复，每轮怪量 +20%，阶段表循环
var _cycle := 0           # 已经走完了几轮
var _pending: Array[Dictionary] = []  # 到点了但还没刷出来的事
var _acc := 0.0
var _is_set := false


# 开一局。type_ids = 游戏里有的怪的 id；表里写了但这里没有的怪会被跳过（头目、精英则换成最后一种怪顶上）
func setup(type_ids: Array[String]) -> void:
    _ids = type_ids.duplicate()
    if rng_seed == 0:
        _rng.randomize()
    else:
        _rng.seed = rng_seed
    _mix_ids.clear()
    _mix_weights.clear()
    for ph in PHASES:
        var ids: Array[String] = []
        var weights: Array[float] = []
        for id: String in ph["mix"]:
            if _ids.has(id):
                ids.append(id)
                weights.append(float(ph["mix"][id]))
        if ids.is_empty() and not _ids.is_empty():
            ids.append(_ids[0])
            weights.append(1.0)
        _mix_ids.append(ids)
        _mix_weights.append(weights)
    _events.clear()
    for src in EVENTS:
        var ev: Dictionary = src.duplicate()
        ev["t"] = _parse_time(ev["at"])
        _events.append(ev)
    _events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
    _next_event = 0
    _cycle = 0
    _pending.clear()
    _acc = 0.0
    _is_set = true


# 从第 time 秒开始看：这之前的定点事件都当作已经发生过，不会一口气全补出来
func skip_to(time: float) -> void:
    while true:
        while _next_event < _events.size() and _event_time(_next_event) < time:
            _next_event += 1
        if endless and _next_event >= _events.size() and time >= _cycle_offset() + RUN_SECONDS:
            _cycle += 1
            _next_event = 0
            continue
        break


# 每帧调一次。time = 这一局过了多少秒，alive = 现在场上有几只怪（连正在播死亡动作的一起算最稳）
func tick(time: float, delta: float, alive: int, map_time: float = -1.0) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if not _is_set or _ids.is_empty() or delta <= 0.0:
        return out
    var pi := _phase_index(time)
    var ph: Dictionary = PHASES[pi]
    var free: int = max_alive - alive
    var cyc := cycle_mode and map_time >= 0.0
    if cyc:
        _queue_cycle_events(time, map_time)

    # 先处理定点的事：头目、精英、狼群、合围
    while not cyc:
        while _next_event < _events.size() and _event_time(_next_event) <= time:
            var src: Dictionary = _events[_next_event]
            if _cycle > 0:
                src = src.duplicate()
                src["t"] = _event_time(_next_event)
                src["count"] = int(ceil(float(src["count"]) * (1.0 + 0.2 * _cycle)))
            if density != 1.0 and int(src["count"]) > 1 and str(src["kind"]) in ["pack", "encircle"]:
                src = src.duplicate()
                src["count"] = maxi(1, roundi(float(src["count"]) * density))
            _pending.append(src)
            _next_event += 1
        if endless and _next_event >= _events.size() and time >= _cycle_offset() + RUN_SECONDS:
            _cycle += 1
            _next_event = 0
            continue
        break
    var i := 0
    while i < _pending.size():
        var ev: Dictionary = _pending[i]
        var is_boss: bool = ev["kind"] == "miniboss" or ev["kind"] == "boss" or ev["kind"] == "boss_wild"
        var usable: int = free if is_boss else free - BOSS_RESERVE
        if usable <= 0:
            if not is_boss and time - float(ev["t"]) > EVENT_WAIT:
                _pending.remove_at(i)
            else:
                i += 1
            continue
        var want := int(ev["count"])
        var n: int = mini(want, usable)
        out.append(_event_spawn(ev, ph, n))
        free -= n
        _pending.remove_at(i)

    # 再刷平时的怪。同屏快满了就少刷几只（rate 缩放保留）；本段真实野生怪每只各自抽样，
    # 不再靠提高等级 / 加经验补数量。
    var fill := float(alive) / float(maxi(1, max_alive))
    var k := 1.0
    if fill > SOFT_FILL:
        k = lerpf(1.0, MIN_RATE_SCALE, clampf((fill - SOFT_FILL) / (1.0 - SOFT_FILL), 0.0, 1.0))
    # 开场缓坡：第一轮开头刷怪率从 RAMP_START 倍线性爬到 1 倍（RAMP_SECS 秒），让 1 级的起手招来得及杀。
    var ramp := 1.0 if _cycle > 0 else lerpf(RAMP_START, 1.0, clampf(time / RAMP_SECS, 0.0, 1.0))
    var rate := float(ph["rate"]) * (1.0 + 0.15 * float(int(time / RUN_SECONDS)))
    if cyc:
        rate = cycle_rate(time, map_time)
    _acc = minf(_acc + delta * rate * k * ramp * density, 4.0)   # 卡了一下也不会一口气补出一大堆
    var room: int = free - RESERVE
    while _acc >= 1.0 and room > 0:
        _acc -= 1.0
        room -= 1
        out.append(_wild_make(1, "ring", float(ph["speed"]), ""))
    if room <= 0:
        _acc = minf(_acc, 1.0)
    return out


# 松紧循环：这一刻的平时刷怪速度（这一轮第几分钟的档 × 整局时间带来的增长）。
func cycle_rate(time: float, map_time: float) -> float:
    var in_cycle := fmod(maxf(0.0, map_time), CYCLE_SECONDS)
    var rate := float(CYCLE_SEGMENTS[CYCLE_SEGMENTS.size() - 1][1])
    for seg in CYCLE_SEGMENTS:
        if in_cycle < float(seg[0]):
            rate = float(seg[1])
            break
    if first_ramp and time < CYCLE_SECONDS and in_cycle >= float(CYCLE_SEGMENTS[0][0]) and in_cycle < float(CYCLE_SEGMENTS[1][0]):
        var from := float(CYCLE_SEGMENTS[0][1])
        rate = lerpf(from, rate, clampf((in_cycle - FIRST_RAMP_FROM) / (FIRST_RAMP_TO - FIRST_RAMP_FROM), 0.0, 1.0))
    return rate * cycle_growth(time)


func cycle_growth(time: float) -> float:
    return 1.0 + CYCLE_GROWTH * float(int(maxf(0.0, time) / CYCLE_SECONDS))


# 松紧循环的事件：按“这一轮里第几秒”触发；换地区（map_time 变小）或进入下一轮就从头排。
func _queue_cycle_events(time: float, map_time: float) -> void:
    var c := int(maxf(0.0, map_time) / CYCLE_SECONDS)
    if map_time < _last_map_time or c != _map_cycle:
        _map_cycle = c
        _map_cycle_next = 0
    _last_map_time = map_time
    var in_cycle := map_time - float(c) * CYCLE_SECONDS
    var g := cycle_growth(time)
    while _map_cycle_next < CYCLE_EVENTS.size() and float(CYCLE_EVENTS[_map_cycle_next]["at"]) <= in_cycle:
        var ev: Dictionary = CYCLE_EVENTS[_map_cycle_next].duplicate()
        ev["t"] = time
        if int(ev["count"]) > 1:
            ev["count"] = maxi(1, roundi(float(ev["count"]) * g * (density if str(ev["kind"]) in ["pack", "encircle"] else 1.0)))
        if first_ramp and time < CYCLE_SECONDS and float(ev["at"]) <= FIRST_RAMP_FROM and str(ev["kind"]) == "pack":
            ev["count"] = maxi(1, roundi(float(ev["count"]) * FIRST_PACK_SCALE))   # 开局第一群减半
        _pending.append(ev)
        _map_cycle_next += 1


# 界面上显示的这一波的名字
func phase_name(time: float) -> String:
    var pi := _phase_index(time)
    return "第 %d 波 · %s" % [wave_index(time), PHASES[pi]["name"]]


# 到没到最终头目出场的时间。算不算赢由 main.gd 定（打死最终头目）
func is_finished(time: float) -> bool:
    return time >= RUN_SECONDS


# 四个头目各在第几秒出场，最后一个是最终头目
func boss_times() -> Array[float]:
    var out: Array[float] = []
    for ev in EVENTS:
        if ev["kind"] == "miniboss" or ev["kind"] == "boss" or ev["kind"] == "boss_wild":
            out.append(_parse_time(ev["at"]))
    out.sort()
    return out


func _cycle_offset() -> float:
    return float(_cycle) * RUN_SECONDS


func _event_time(i: int) -> float:
    return float(_events[i]["t"]) + _cycle_offset()


func _phase_index(time: float) -> int:
    if endless:
        return int(time / PHASE_SECONDS) % PHASES.size()   # 无尽：20 个阶段循环
    return clampi(int(time / PHASE_SECONDS), 0, PHASES.size() - 1)


# 本段实时适配：原 waveIndex = 当前阶段序号 + 1（0..59.999 → 1、60..119.999 → 2，…）。
# getWildSpeciesForLevel / randomSpecies / 时段偏移都用这个序号，不从旧 lv1..6 反推。
func wave_index(time: float) -> int:
    if endless:
        return int(time / PHASE_SECONDS) + 1   # 无尽：真实第几分钟，不封顶
    return _phase_index(time) + 1


# 少了几倍的怪不再换算成等级；本段普通 / 精英 / 群聚 / 合围一律真实野生抽样。


# 按比重随机挑一种怪（旧 pack / 普通路径的物种选择；本段普通怪改走真实野生抽样，只留旧兼容）
func _pick(pi: int) -> String:
    var ids: Array = _mix_ids[pi]
    var weights: Array = _mix_weights[pi]
    var total := 0.0
    for w: float in weights:
        total += w
    var r := _rng.randf() * total
    for j in ids.size():
        r -= float(weights[j])
        if r < 0.0:
            return ids[j]
    return ids[ids.size() - 1]


# 把表二的一行变成一条刷怪。n = 实际刷几只。
# 四个「头目事件」走 boss_wild 真实头目路径：不在波次层定物种 / 等级 / 段数，
# 每只头目在真实入队时各自按当时 wave 走原 BOSS 池抽样（`wild.roll_boss_encounter`）。
# 其余普通 / 精英 / 群聚 / 合围一律 wild：同样逐只真实抽样。
func _event_spawn(ev: Dictionary, _ph: Dictionary, n: int) -> Dictionary:
    var speed := float(ev.get("speed", 1.0))
    var scale := float(ev.get("scale", 1.0))
    var xp := float(ev.get("xp", 1.0))
    var label: String = ev.get("label", "")
    if endless and label == "最终头目来了":
        label = "头目来了"
    var kind: String = ev["kind"]
    if kind == "boss_wild":
        return {"id": "", "count": n, "pattern": "ring", "level": 0, "rank": "",
            "speed_mult": speed, "scale_mult": 1.0, "xp_mult": 1.0, "elite": false,
            "boss": true, "final": bool(ev.get("final", false)), "label": label, "source": "boss"}
    if kind == "miniboss" or kind == "boss":
        var id: String = ev["id"]
        if not _ids.has(id):
            id = _ids[_ids.size() - 1]
        if kind == "boss":
            return _make(id, n, "ring", 1 + int(ev.get("lv", 0)), "boss", speed, scale, xp, true, true, label)
        return _make(id, n, "ring", 1 + int(ev.get("lv", 0)), "boss", speed, scale, xp, true, false, label)
    var pattern := "encircle" if kind == "encircle" else ("cluster" if kind == "pack" else "ring")
    return _wild_make(n, pattern, speed, label)


# 本段普通敌人：物种 / 等级 / 形态 / 六维由 main/enemies.gd 入队时逐只真实抽样。
func _wild_make(count: int, pattern: String, speed: float, label: String) -> Dictionary:
    return {"id": "", "count": count, "pattern": pattern, "level": 0, "rank": "", "speed_mult": speed,
        "scale_mult": 1.0, "xp_mult": 1.0, "elite": false, "boss": false, "final": false, "label": label,
        "source": "wild"}


# 旧路径（四个占位头目）：单位模板 / 等级 / 形态照旧，source=legacy，不参与真实野生抽样。
func _make(id: String, count: int, pattern: String, level: int, rank: String, speed: float, scale: float, xp: float,
        boss: bool, final: bool, label: String) -> Dictionary:
    return {"id": id, "count": count, "pattern": pattern, "level": level, "rank": rank, "speed_mult": speed,
        "scale_mult": scale, "xp_mult": xp, "elite": rank == "elite", "boss": boss, "final": final, "label": label,
        "source": "legacy"}


# "5:00" → 300.0
func _parse_time(s: String) -> float:
    var parts := s.split(":")
    if parts.size() == 2:
        return float(parts[0]) * 60.0 + float(parts[1])
    return float(s)
