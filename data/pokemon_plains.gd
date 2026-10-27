extends RefCounted
#
# 只读源（静态读取，不执行整包）：
#   SHA256 = d3d97fe1acedd66094c3801b1ed13381eb0fa5ae0f64fdb7febe581adeec955c
#   原块 `plains_pool` @ UTF-16 offset 3552425，
#   SHA256 = 0dc3acb7bc209338a85a0e68fbebaad1550b06e68b01d7ef591f57a6a16d0f4b。
#   本文件 9 稀有度 × 5 时段表逐项转写该原块，顺序 / 重复 / 空数组 / 进化门槛全部保留。
#   完整来源、9 条原块清单与尚未接入的边界见 `data/POKEMON_PLAINS_SOURCE.md`。
#
# 并静态核对只读 bundle 里的原块 raw / SHA256 / UTF-16 offset。
#
# 本段只有**资料与纯查询**：不接 Pokedex 查询、不接渲染、不改实际刷怪 / 波次节奏。
# `PALDEA_TAUROS` = 8128 是源地区形态 ID，原样保留：不折成全国图鉴 128，也不因当前图鉴 1025 而删。
#
# 稀有度枚举照原作 `Sa`：普通 0..4，头目 5..8。BOSS 行只作只读资料保留，本段不启用头目玩法。
# 时段枚举照原作 `U`：ALL=-1、DAWN=0、DAY=1、DUSK=2、NIGHT=3。

const TIME_ALL := -1
const TIME_DAWN := 0
const TIME_DAY := 1
const TIME_DUSK := 2
const TIME_NIGHT := 3

const TIME_NAMES := {
    TIME_ALL: "ALL",
    TIME_DAWN: "DAWN",
    TIME_DAY: "DAY",
    TIME_DUSK: "DUSK",
    TIME_NIGHT: "NIGHT",
}

const TIER_COMMON := 0
const TIER_UNCOMMON := 1
const TIER_RARE := 2
const TIER_SUPER_RARE := 3
const TIER_ULTRA_RARE := 4
const TIER_BOSS := 5
const TIER_BOSS_RARE := 6
const TIER_BOSS_SUPER_RARE := 7
const TIER_BOSS_ULTRA_RARE := 8

# 本段实际参与普通稀有度 roll 的 5 档；BOSS 5..8 只留资料。
const NORMAL_TIERS := [TIER_COMMON, TIER_UNCOMMON, TIER_RARE, TIER_SUPER_RARE, TIER_ULTRA_RARE]
const BOSS_TIERS := [TIER_BOSS, TIER_BOSS_RARE, TIER_BOSS_SUPER_RARE, TIER_BOSS_ULTRA_RARE]

const TIER_NAMES := {
    TIER_COMMON: "COMMON",
    TIER_UNCOMMON: "UNCOMMON",
    TIER_RARE: "RARE",
    TIER_SUPER_RARE: "SUPER_RARE",
    TIER_ULTRA_RARE: "ULTRA_RARE",
    TIER_BOSS: "BOSS",
    TIER_BOSS_RARE: "BOSS_RARE",
    TIER_BOSS_SUPER_RARE: "BOSS_SUPER_RARE",
    TIER_BOSS_ULTRA_RARE: "BOSS_ULTRA_RARE",
}

# 原块 `plains_pool`：tier -> time -> 该时段条目数组。
# 条目两种形态：直接 Int（固定物种 ID）或 Dictionary{ 门槛等级: [候选物种 ID, ...] }。
# 门槛是**数值**比较（原作 `parseInt(Object.keys(...))`），不是字符串字典序。
const PLAINS := {
    0: {
        TIME_DAWN: [{1: [161], 15: [162]}, {1: [734], 30: [735]}, {1: [819], 24: [820]}],
        TIME_DAY: [{1: [161], 15: [162]}, {1: [734], 30: [735]}, {1: [819], 24: [820]}],
        TIME_DUSK: [{1: [52], 28: [53]}, {1: [261], 18: [262]}],
        TIME_NIGHT: [{1: [41], 22: [42]}, {1: [52], 28: [53]}, {1: [261], 18: [262]}],
        TIME_ALL: [{1: [263], 20: [264]}, {1: [399], 15: [400]}, {1: [915], 18: [916]}],
    },
    1: {
        TIME_DAWN: [{1: [84], 31: [85]}, {1: [261], 18: [262]}, {1: [396], 14: [397], 34: [398]}, {1: [519], 21: [520], 32: [521]}, {1: [921], 18: [922], 32: [923]}],
        TIME_DAY: [{1: [84], 31: [85]}, {1: [261], 18: [262]}, {1: [396], 14: [397], 34: [398]}, {1: [519], 21: [520], 32: [521]}, {1: [744], 25: [745]}, {1: [921], 18: [922], 32: [923]}],
        TIME_DUSK: [{1: [56], 28: [57], 75: [979]}],
        TIME_NIGHT: [{1: [56], 28: [57], 75: [979]}],
        TIME_ALL: [{1: [16], 18: [17], 36: [18]}, {1: [21], 20: [22]}, 25, {1: [661], 17: [662], 35: [663]}],
    },
    2: {
        TIME_DAWN: [8128],
        TIME_DAY: [8128],
        TIME_DUSK: [{1: [403], 15: [404], 30: [405]}],
        TIME_NIGHT: [{1: [403], 15: [404], 30: [405]}],
        TIME_ALL: [{1: [63], 16: [64]}, {1: [427], 20: [428]}, {1: [821], 18: [822], 38: [823]}],
    },
    3: {
        TIME_DAWN: [],
        TIME_DAY: [],
        TIME_DUSK: [],
        TIME_NIGHT: [],
        TIME_ALL: [83, 108, 113, 133, 143, {1: [206], 62: [982]}],
    },
    4: {
        TIME_DAWN: [],
        TIME_DAY: [],
        TIME_DUSK: [],
        TIME_NIGHT: [],
        TIME_ALL: [132, 380, 381],
    },
    5: {
        TIME_DAWN: [85, 162, 735, 820],
        TIME_DAY: [85, 162, 735, 820],
        TIME_DUSK: [53, 262],
        TIME_NIGHT: [53, 262],
        TIME_ALL: [264, 400, 428, 916],
    },
    6: {
        TIME_DAWN: [923, 8128],
        TIME_DAY: [745, 923, 8128],
        TIME_DUSK: [],
        TIME_NIGHT: [],
        TIME_ALL: [83, 143, 463, 982],
    },
    7: {
        TIME_DAWN: [],
        TIME_DAY: [],
        TIME_DUSK: [],
        TIME_NIGHT: [],
        TIME_ALL: [380, 381],
    },
    8: {
        TIME_DAWN: [],
        TIME_DAY: [],
        TIME_DUSK: [],
        TIME_NIGHT: [],
        TIME_ALL: [],
    },
}

# 原块 `plains_pool` 用到的物种枚举名 -> 源物种 ID，共 65 条，顺序同原块首次出现顺序。
# 这些是**源物种 ID**（含地区形态 8128），不是本作图鉴编号。
const SPECIES := {
    "SENTRET": 161, "FURRET": 162, "YUNGOOS": 734, "GUMSHOOS": 735, "SKWOVET": 819, "GREEDENT": 820, "MEOWTH": 52, "PERSIAN": 53, "POOCHYENA": 261, "MIGHTYENA": 262, "ZUBAT": 41, "GOLBAT": 42, "ZIGZAGOON": 263, "LINOONE": 264, "BIDOOF": 399, "BIBAREL": 400, "LECHONK": 915, "OINKOLOGNE": 916, "DODUO": 84, "DODRIO": 85, "STARLY": 396, "STARAVIA": 397, "STARAPTOR": 398, "PIDOVE": 519, "TRANQUILL": 520, "UNFEZANT": 521, "PAWMI": 921, "PAWMO": 922, "PAWMOT": 923, "ROCKRUFF": 744, "LYCANROC": 745, "MANKEY": 56, "PRIMEAPE": 57, "ANNIHILAPE": 979, "PIDGEY": 16, "PIDGEOTTO": 17, "PIDGEOT": 18, "SPEAROW": 21, "FEAROW": 22, "PIKACHU": 25, "FLETCHLING": 661, "FLETCHINDER": 662, "TALONFLAME": 663, "PALDEA_TAUROS": 8128, "SHINX": 403, "LUXIO": 404, "LUXRAY": 405, "ABRA": 63, "KADABRA": 64, "BUNEARY": 427, "LOPUNNY": 428, "ROOKIDEE": 821, "CORVISQUIRE": 822, "CORVIKNIGHT": 823, "FARFETCHD": 83, "LICKITUNG": 108, "CHANSEY": 113, "EEVEE": 133, "SNORLAX": 143, "DUNSPARCE": 206, "DUDUNSPARCE": 982, "DITTO": 132, "LATIAS": 380, "LATIOS": 381, "LICKILICKY": 463,
}

# 回合数 -> 时段的纯查询，照原作 `getTimeOfDay()`（`biomeType` 走平原分支）：
#   t = (waveIndex + waveCycleOffset) % 40；t < 15 DAY、t < 20 DUSK、t < 35 NIGHT，否则 DAWN。
# 本实现用 `posmod` 保证任意输入（含负数）都落在 0..39：原作 waveIndex / waveCycleOffset 非负，
# 合法输入下与正文公式逐值一致；不接墙钟 / 用户时区 / 真实计时器。
static func time_for_wave(wave_index: int, cycle_offset: int = 0) -> int:
    var t := posmod(wave_index + cycle_offset, 40)
    if t < 15:
        return TIME_DAY
    if t < 20:
        return TIME_DUSK
    if t < 35:
        return TIME_NIGHT
    return TIME_DAWN


# 该 tier 在当前时段的原池条目：原作 `Object.assign([], 池[tier][ALL]).concat(池[tier][time])`，
# 即**原 ALL 在前 + 该时段在后**。time 传 TIME_ALL 时只返回 ALL 一次（不叠两遍）。
# 返回深副本：调用方改结果不会污染 PLAINS 原表。非法 tier / time 返回空数组（有界，不报错）。
static func merged_pool(tier: int, time: int) -> Array:
    return merged_pool_in(PLAINS, tier, time)


# 同上，但池数据由调用方给（其它地区的池，data/pokemon_biome_pools.gd）。
static func merged_pool_in(data: Dictionary, tier: int, time: int) -> Array:
    var tiers: Dictionary = data.get(tier, {})
    if tiers.is_empty() or not TIME_NAMES.has(time):
        return []
    var all_entries: Array = tiers.get(TIME_ALL, [])
    if time == TIME_ALL:
        return all_entries.duplicate(true)
    var out: Array = all_entries.duplicate(true)
    out.append_array((tiers.get(time, []) as Array).duplicate(true))
    return out


# 普通稀有度 roll 的 5 档映射，照原作 `Ze(512)` 的 0..511 与阈值：
#   >=156 COMMON、>=32 UNCOMMON、>=6 RARE、>=1 SUPER_RARE，否则 ULTRA_RARE。
# roll 超出 0..511 时按同样的阈值单调落档，不报错。
static func rolled_tier(roll: int) -> int:
    if roll >= 156:
        return TIER_COMMON
    if roll >= 32:
        return TIER_UNCOMMON
    if roll >= 6:
        return TIER_RARE
    if roll >= 1:
        return TIER_SUPER_RARE
    return TIER_ULTRA_RARE


# 原池 roll：先按阈值定档，再照原作 `for(;!pool[tier].length;) tier--` 逐级往下回退到非空档。
# 返回 -1 表示 5 档全空（原作会在此越界；本实现显式有界）。
static func roll_rare_tier(roll: int, time: int, data: Dictionary = PLAINS) -> int:
    var availability: Array = []
    for tier in NORMAL_TIERS:
        availability.append(not merged_pool_in(data, tier, time).is_empty())
    return roll_rare_tier_with_availability(roll, availability)


# 与上面同逻辑，但由调用方给出 5 档可用性（index=tier，缺项视为不可用）。
# 真实平原表 5 档都有 ALL 条目，此入口主要给固定输入 / 空表回退检查用。
static func roll_rare_tier_with_availability(roll: int, availability: Array) -> int:
    var tier := rolled_tier(roll)
    while tier >= TIER_COMMON:
        if tier < availability.size() and bool(availability[tier]):
            return tier
        tier -= 1
    return -1


# 原 `randomSpecies()` 里**单个池条目**按敌人等级的候选物种 ID 查询：
#   直接数值条目 -> 直接返回该 ID；
#   门槛字典 -> 取 <= enemy_level 的**最大数值门槛**，返回该门槛的候选数组（保留原数组顺序）。
# 没有 <= enemy_level 的门槛时返回空数组（有界）。
# 门槛键是 int 或数字字符串都按数值比较（不能按字符串字典序）。
#
# 边界：这只是池条目查询，**不是**完整实际野生物种生成。原作随后的
# legendary / mythical 最低等级重试、以及 `getWildSpeciesForLevel()` 的二次物种修正
# 都还没接入，留给下一段（见 `data/POKEMON_PLAINS_SOURCE.md`）。
static func pool_entry_candidates(entry: Variant, enemy_level: int) -> Array:
    if entry is int or entry is float:
        return [int(entry)]
    if entry is Dictionary:
        var dict: Dictionary = entry
        var best_threshold := -1
        var best_ids: Array = []
        for key in dict.keys():
            var threshold := _threshold_of(key)
            if threshold < 0:
                continue
            if threshold <= enemy_level and threshold > best_threshold:
                best_threshold = threshold
                best_ids = dict[key]
        return best_ids.duplicate()
    return []


# 门槛键 -> 数值；非数字键返回 -1（跳过），对应原作 `parseInt` 出 NaN 时不命中。
static func _threshold_of(key: Variant) -> int:
    if key is int:
        return key
    if key is float:
        return int(key)
    if key is String and (key as String).is_valid_int():
        return int(key)
    return -1
