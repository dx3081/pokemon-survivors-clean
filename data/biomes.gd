extends RefCounted
# 本作地图 / 地区总表（本轮只开放平原，不制作实际新地图、不导入素材、不做解锁条件）。
# 35 个地区的唯一数据源：稳定 id 供出发和后续存档引用，中文名给界面显示，opened 表示本轮是否可选。
# ui/town.gd 只读这张表，不复制任何地区数据；出发只认 opened = true 的 id。
#
# 用法：
#   Biomes.list()            # 35 行 {"id", "name", "opened"}
#   Biomes.resolve(id)       # 未知或未开放 id 一律回退 "plains"
#   Biomes.name_of("plains") # "平原"

const DEFAULT_ID := "plains"

# 顺序固定，按用户给的清单；只有 plains 标记 opened。
const LIST: Array[Dictionary] = [
    {"id": "town", "name": "城镇", "opened": false},
    {"id": "plains", "name": "平原", "opened": true},
    {"id": "grass", "name": "草地", "opened": true},
    {"id": "tall_grass", "name": "高草丛", "opened": true},
    {"id": "metropolis", "name": "都市", "opened": true},
    {"id": "forest", "name": "森林", "opened": true},
    {"id": "sea", "name": "海洋", "opened": true},
    {"id": "swamp", "name": "沼泽", "opened": true},
    {"id": "beach", "name": "海滩", "opened": true},
    {"id": "lake", "name": "湖泊", "opened": true},
    {"id": "seabed", "name": "海底", "opened": true},
    {"id": "mountain", "name": "山地", "opened": true},
    {"id": "badlands", "name": "荒地", "opened": true},
    {"id": "cave", "name": "洞窟", "opened": true},
    {"id": "desert", "name": "沙漠", "opened": true},
    {"id": "ice_cave", "name": "冰窟", "opened": true},
    {"id": "meadow", "name": "花田", "opened": true},
    {"id": "power_plant", "name": "发电厂", "opened": true},
    {"id": "volcano", "name": "火山", "opened": true},
    {"id": "graveyard", "name": "墓地", "opened": true},
    {"id": "dojo", "name": "道场", "opened": true},
    {"id": "factory", "name": "工厂", "opened": true},
    {"id": "ruins", "name": "古代遗迹", "opened": true},
    {"id": "wasteland", "name": "荒野", "opened": true},
    {"id": "abyss", "name": "深渊", "opened": true},
    {"id": "space", "name": "太空", "opened": true},
    {"id": "construction_site", "name": "工地", "opened": true},
    {"id": "jungle", "name": "丛林", "opened": true},
    {"id": "fairy_cave", "name": "妖精洞窟", "opened": true},
    {"id": "temple", "name": "神殿", "opened": true},
    {"id": "slum", "name": "贫民窟", "opened": true},
    {"id": "snowy_forest", "name": "雪地森林", "opened": true},
    {"id": "island", "name": "岛屿", "opened": true},
    {"id": "laboratory", "name": "实验室", "opened": true},
    {"id": "end", "name": "???", "opened": true},
]


# ===== 等级带（用户 2026-10-17：“游戏里面的高等级应该如何实现？每个图选等级 1-60 / 50-110 / 100-160？”）=====
# 原作一局 200 波、敌人等级从 1 涨到 ~165（getLevelForWave：1 + 波/2 + (波/25)²）；本作一局 20 分钟，不是 200 场战斗。
# 做法：每个地区有一条“战斗波次带” [起, 止]：一局里从起点线性走到终点（RUN_SECONDS = 1200 秒），敌人等级 / 稀有物种的等级门槛 /
# 野外进化 / 头目段数 / 昼夜都按这个“战斗波次”算，和原作同一套公式。
#   第一档 1 → 60  （平原、草地…）  → 等级约 1 → 37
#   第二档 50 → 110                 → 等级约 26 → 75
#   第三档 100 → 160                → 等级约 58 → 122
#   终局   150 → 200                → 等级约 91 → 165
# 数字是我先定的，试玩觉得难 / 简单调这张表。
# 2026-10-22 起（用户：“1 级去高级图根本弄不了”“撤离之后 50 级，地图应该 match 50 级或者 45-40 级”）：
# 带的**起点不再用**，敌人等级从入场等级 / 撤离时你的等级 × EVAC_LEVEL_RATIO 开始；带只剩“宽度 = 涨多快”。
const BANDS := {
    "plains": [1, 60], "grass": [1, 60], "tall_grass": [1, 60], "metropolis": [1, 60], "forest": [1, 60], "sea": [1, 60],
    "swamp": [1, 60], "beach": [1, 60], "lake": [1, 60], "mountain": [1, 60],
    "seabed": [50, 110], "badlands": [50, 110], "cave": [50, 110], "desert": [50, 110], "ice_cave": [50, 110], "meadow": [50, 110],
    "power_plant": [50, 110], "volcano": [50, 110], "graveyard": [50, 110], "dojo": [50, 110], "factory": [50, 110], "ruins": [50, 110],
    "wasteland": [100, 160], "abyss": [100, 160], "space": [100, 160], "construction_site": [100, 160], "jungle": [100, 160],
    "fairy_cave": [100, 160], "temple": [100, 160], "slum": [100, 160], "snowy_forest": [100, 160], "island": [100, 160],
    "laboratory": [100, 160],
    "end": [150, 200],
}
const DEFAULT_BAND := [1, 60]


static func band(id: String) -> Array:
    return BANDS.get(id, DEFAULT_BAND)


# 一局里 time 秒时的“战斗波次”：从该地区带的起点线性走到终点，至少 1（旧口径，限时 20 分钟；检查 / 兼容用）。
static func battle_wave(id: String, time: float, run_seconds := 1200.0) -> int:
    var b: Array = band(id)
    var t := clampf(time / run_seconds, 0.0, 1.0)
    return maxi(1, int(round(float(b[0]) + (float(b[1]) - float(b[0])) * t)))


# ---- 无尽波次 + 入场等级（用户 2026-10-17：“可以无尽波数，刚开始选择入场等级，因为有糖果可以从高等级开始”）----
# 波次不封顶：起点 = max(地区带起点, 入场波次)，之后每 1200 秒走“地区带宽度”那么多波（平原 59 波 / 20 分钟 ≈ 20 秒一波）。
# 敌人等级再不低于玩家等级的 LEVEL_FLOOR_RATIO（别出现 90 级打 30 级怪）。
const LEVEL_FLOOR_RATIO := 0.7
# 撤离到新地区：敌人从你（去掉糖果的）等级的 85% 起步（50 级 → 约 42 级）。
const EVAC_LEVEL_RATIO := 0.85
# 入场等级可选档（敌人的原基础等级）；低于地区起点的档不出现。
const ENTRY_LEVELS := [1, 10, 20, 30, 40, 60, 80, 100, 150, 200, 300, 500, 750, 1000]


# 原等级公式 n = 1 + w/2 + (w/25)² 的反解：至少多少波，敌人基础等级才 >= level。
static func wave_for_level(level: float) -> int:
    if level <= 1.5:
        return 1
    var x := (-12.5 + sqrt(156.25 - 4.0 * (1.0 - level))) / 2.0   # x = w / 25
    return maxi(1, int(ceil(x * 25.0 - 0.0001)))


# 入场等级上限 = 开局等级（1 + 神奇糖果）× 1.5：模拟（20 分钟站桩）发现 Lv.100 的宠物进 Lv.1000 的局一只怪都打不死；
# 敌人比自己高到 1.5 倍以内，同属性六维下还能来回打几下（试玩觉得松 / 紧改这个比例）。
const ENTRY_LEVEL_RATIO := 1.5


static func entry_cap(start_level: int) -> int:
    return int(floor(float(ENTRY_LEVEL_RATIO) * float(maxi(1, start_level))))


# 该地区能选的入场等级（第一项 = 地区起点本身，用 0 表示“默认”）；start_level > 0 时再去掉超过上限的档。
static func entry_levels(id: String, start_level := 0) -> Array[int]:
    var floor_lv := 1.0   # 2026-10-22 起地区不再有等级起点：1 级也能从任何地区开始
    var out: Array[int] = [0]
    for lv: int in ENTRY_LEVELS:
        if float(lv) > floor_lv + 0.5 and (start_level <= 0 or lv <= entry_cap(start_level)):
            out.append(lv)
    return out


# 入场等级 -> 入场波次（0 = 默认，用地区带起点）。
static func entry_wave(id: String, entry_level: int) -> int:
    if entry_level <= 0:
        return 1   # 2026-10-22 起不看地区带起点（用户：1 级去高级图根本打不了）
    return wave_for_level(float(entry_level))


# 无尽战斗波次：入场波次 + 经过时间 × 地区带速度；敌人等级再不低于玩家等级 × LEVEL_FLOOR_RATIO。
static func run_wave(id: String, time: float, entry_wave_v := 0, player_level := 1, run_seconds := 1200.0) -> int:
    var b: Array = band(id)
    var rate := (float(b[1]) - float(b[0])) / run_seconds
    # 地区只决定出什么宝可梦、涨得多快，不再决定从几级开始（用户 2026-10-22）：起点 = 入场 / 撤离时定的波次
    var start := maxi(1, entry_wave_v)
    var w := start + int(round(time * rate))
    if player_level > 1:
        w = maxi(w, wave_for_level(float(player_level) * LEVEL_FLOOR_RATIO))
    return maxi(1, w)


# 全部 35 行，顺序与上面常量一致。
static func list() -> Array[Dictionary]:
    return LIST


static func ids() -> Array[String]:
    var out: Array[String] = []
    for b: Dictionary in LIST:
        out.append(str(b["id"]))
    return out


static func by_id() -> Dictionary:
    var out := {}
    for b: Dictionary in LIST:
        out[str(b["id"])] = b
    return out


static func has_id(id: String) -> bool:
    for b: Dictionary in LIST:
        if str(b["id"]) == id:
            return true
    return false


static func is_opened(id: String) -> bool:
    for b: Dictionary in LIST:
        if str(b["id"]) == id:
            return bool(b["opened"])
    return false


# 找不到 id 时返回空串；界面只对已知 id 调用。
static func name_of(id: String) -> String:
    for b: Dictionary in LIST:
        if str(b["id"]) == id:
            return str(b["name"])
    return ""


# 出发用：未知、非字符串或未开放的 id 一律回退平原。
static func resolve(id: String) -> String:
    return id if is_opened(id) else DEFAULT_ID


static func opened_ids() -> Array[String]:
    var out: Array[String] = []
    for b: Dictionary in LIST:
        if bool(b["opened"]):
            out.append(str(b["id"]))
    return out
