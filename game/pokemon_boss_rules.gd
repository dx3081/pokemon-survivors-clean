extends RefCounted
# 平原头目纯规则（第一段）· 转写自原作 `Arena.getEncounterBossSegments()` 与
# `encounter_boss_segments` / `arena_pool_sampling` / `seeded_integer` / `strength_enum`）。
#
# 只读源（静态读取，不执行整包）：
#   SHA256 = d3d97fe1acedd66094c3801b1ed13381eb0fa5ae0f64fdb7febe581adeec955c
#   原块 `encounter_boss_segments` @ UTF-16 offset 5824784，
#   SHA256 = 33e9ea2f316e41935071465a9dacb42d295239cc03d015a0b560eed398d8cbf2。
#
# 本段**只做 Classic 平原的头目纯查询 / 纯抽样规则**：不接真实刷怪、分段伤害、破段强化、
# 头目奖励、训练家；不搭 Daily / Endless / `hasRandomBosses` 的游戏模式框架。
# Classic 明确 `hasRandomBosses = false`：原作那条 `Ze(100) < min(max(ceil((t-250)/50),0)*2,30)`
# 随机头目支路在平原 Classic 不触发，段数触发只剩 `forced / 传奇标志 / wave%10==0`。
#
# 原作（`getEncounterBossSegments(t,n,r,l=!1)`，t=wave、n=level、r=物种对象、l=强制）：
#   1. daily 波末 -> 5（本段无 Daily，不实现）。
#   2. f = l || (r && (r.subLegendary||r.legendary||r.mythical)) ? true
#        : (t%10===0) || (hasRandomBosses && Ze(100) < ...)；Classic 下无 Ze 抽样。
#   3. !f -> 0。
#   4. o = 2；n>=100 -> +1；r && r.baseTotal>=670 -> +1；o += floor(t/250)。
#
# `get_encounter_boss_segments()` 是纯查询：调用方给最终物种的原 baseTotal / 传奇三项标志。
# `segments_for_species()` 用既有 81 物种资料把 species_id 翻成这些原值；未知物种返回 -1
# （显式失败，不兜底绿毛虫）。
#
# BOSS 池 `Ze(64)` 的 5..8 映射与逐级向下回退照原 `randomSpecies()`：
#   64 掷（`boss_tier_for_roll`）：0 -> BOSS_ULTRA_RARE(8)，1..5 -> BOSS_SUPER_RARE(7)，
#   6..19 -> BOSS_RARE(6)，20..63 -> BOSS(5)；44/14/5/1。
#   池空 `for(;!pool[tier].length;) tier--`（`boss_tier_with_fallback`）会一路回退到普通池 0，
#   真实平原表 tier 8 恒空、tier 5..7 恒非空；tier 0 也空时返回 -1（有界，不越界）。
#
# 详细来源、原块清单与尚未接入的边界见 `data/POKEMON_PLAINS_SOURCE.md`。

const Plains := preload("res://data/pokemon_plains.gd")
const Species := preload("res://data/pokemon_wild_species.gd")

# 原 `getEncounterBossSegments` 常量。
const SEGMENT_BASE := 2
const SEGMENT_LEVEL_THRESHOLD := 100
const SEGMENT_BASE_TOTAL_THRESHOLD := 670
const SEGMENT_WAVE_DIVISOR := 250

# 原 `Ze(f?64:512)` 的 BOSS 骰；`Ze(64)` = 0..63。
const BOSS_ROLL_DIE := 64
# 原 `o>=20?Sa.BOSS:o>=6?Sa.BOSS_RARE:o>=1?Sa.BOSS_SUPER_RARE:Sa.BOSS_ULTRA_RARE` 的阈值。
const BOSS_TIER_BOSS_MIN_ROLL := 20
const BOSS_TIER_RARE_MIN_ROLL := 6
const BOSS_TIER_SUPER_MIN_ROLL := 1

# 段数纯查询：Classic 平原，无 Daily / Endless / hasRandomBosses。
# wave / level / base_total / 传奇标志都按原值传入；base_total 缺省 0 等价于原作 r 为空。
static func get_encounter_boss_segments(wave: int, level: int, base_total := 0,
        forced := false, sub_legendary := false, legendary := false, mythical := false) -> int:
    var is_boss := forced or sub_legendary or legendary or mythical or (wave % 10 == 0)
    if not is_boss:
        return 0
    var segments := SEGMENT_BASE
    if level >= SEGMENT_LEVEL_THRESHOLD:
        segments += 1
    if base_total >= SEGMENT_BASE_TOTAL_THRESHOLD:
        segments += 1
    segments += int(floor(float(wave) / float(SEGMENT_WAVE_DIVISOR)))
    return segments


# 用最终物种的原 baseTotal / subLegendary / legendary / mythical 算段数；未知物种 -> -1。
static func segments_for_species(wave: int, level: int, species_id: int, forced := false) -> int:
    var row: Dictionary = Species.row_of(species_id)
    if row.is_empty():
        return -1
    return get_encounter_boss_segments(wave, level, int(row["base_total"]), forced,
        bool(row["sub_legendary"]), bool(row["legendary"]), bool(row["mythical"]))


# 原 `Ze(64)` 的 tier 映射（0..63）。
static func boss_tier_for_roll(roll: int) -> int:
    if roll >= BOSS_TIER_BOSS_MIN_ROLL:
        return Plains.TIER_BOSS
    if roll >= BOSS_TIER_RARE_MIN_ROLL:
        return Plains.TIER_BOSS_RARE
    if roll >= BOSS_TIER_SUPER_MIN_ROLL:
        return Plains.TIER_BOSS_SUPER_RARE
    return Plains.TIER_BOSS_ULTRA_RARE


# 原 `for(Sa[I];!this.pokemonPool[I].length;) I--`：从映射 tier 逐级向下回退到第一个非空池，
# 必要时回到普通池 0..4；全部为空返回 -1（原作会越界，本实现显式有界）。
# availability 为空时用当前时段的真实合并池（ALL + 时段）；否则用调用方给的 index=tier 可用性，
# 给固定空池 / 普通池回退检查用（与 `Plains.roll_rare_tier_with_availability` 同一约定）。
static func boss_tier_with_fallback(roll: int, time: int, availability: Array = [], data: Dictionary = Plains.PLAINS) -> int:
    var tier := boss_tier_for_roll(roll)
    while tier >= Plains.TIER_COMMON:
        var available := false
        if availability.is_empty():
            available = not Plains.merged_pool_in(data, tier, time).is_empty()
        elif tier < availability.size():
            available = bool(availability[tier])
        if available:
            return tier
        tier -= 1
    return -1


# ================= 第二段：原分段伤害 / 破段强化 =================
#
# 逐句转写源 `Pokemon.damage(t,n=!1,r=!1)` 的头目分支（原块 `boss_segment_damage` @ 5470022）
# 与 `handleBossSegmentCleared(l)`（同块）。本作**不实现** `Ba.FINAL_BOSS` 的
# `!formIndex && bossSegmentIndex<1 -> min(t,hp-1)` 锁血保护：final 在本作只表示“这局胜利”。
# 因此 `canBypassBossSegments(c+1)` 恒 true，`Math.round` 一律用 Godot `roundi`（正数同值）。
#
# 段数划分的是**原六维 HP**（`getMaxHp()`），不乘任何头目 HP/ATK/XP/level 倍率。
# `index` 用运行态存储值，不按当前 HP 现算；`bypass=false` 时普通攻击 / 状态自伤都绕不过分段。
const STAT_RAND := -1
# 源 `xt(le)` 前 5 项：ATK / DEF / SPATK / SPDEF / SPD；`randSeedInt(le.SPD+1)=Ze(5)`。
const STAT_COUNT := 5
const STAT_KEYS: Array[String] = ["atk", "def", "spatk", "spdef", "spd"]


# 源 `handleBossSegmentCleared` 里 `switch(t)` 的每次强化量：l=1 且 N>=3 -> 2；l=2 且 N>=5 -> 2；其余 1。
static func boost_amount(target_l: int, segments: int) -> int:
    var s := 1
    match target_l:
        1:
            if segments >= 3:
                s += 1
        2:
            if segments >= 5:
                s += 1
    return s


# `handleBossSegmentCleared(l)` 的循环次数：`while(l-1 < bossSegmentIndex)` -> index-(l-1) 次。
static func cleared_segments(index: int, target_l: int) -> int:
    if target_l <= index:
        return index - target_l + 1
    return 0


# 纯分段伤害：max_hp / segments / 存储 index / 当前 hp / damage / bypass。
# 返回 {"hp","index","damage","cleared","target","bypass"}：
#   damage  = 实际扣血量（= 原 `super.damage()` 的返回值，已 min(t,hp)）
#   target  = 传给 handleBossSegmentCleared 的 l（没有清段则 -1）
#   cleared = 清掉的段数（每个对应一次 StatChangePhase）
static func apply_segmented_damage(max_hp: int, segments: int, index: int, hp: int, damage: int,
        bypass := false) -> Dictionary:
    if segments <= 0 or index < 0 or hp <= 0:
        var applied0 := mini(maxi(damage, 0), maxi(hp, 0))
        return {"hp": maxi(hp, 0) - applied0, "index": index, "damage": applied0,
            "cleared": 0, "target": -1, "bypass": bypass}
    var t := maxi(damage, 0)
    var l := index + 1
    if not bypass:
        var o := float(max_hp) / float(segments)
        var i := index
        while i > 0:
            var u := roundi(o * float(i))
            if hp >= u:
                if hp - t <= u:
                    var m := hp - u
                    var c := 0
                    # 非 FINAL_BOSS：canBypassBossSegments 恒 true（仅受 c<index 限制）。
                    while c < index and (t - m) >= roundi(o * pow(2.0, float(c + 1))):
                        c += 1
                    t = m + roundi(o * float(c))
                    l = i - c
                break
            i -= 1
    var applied := mini(t, hp)
    var new_hp := hp - applied
    if bypass:
        var o2 := float(max_hp) / float(segments)
        l = ceili(float(new_hp) / o2)
    var cleared := cleared_segments(index, l)
    return {"hp": new_hp, "index": (l - 1) if cleared > 0 else index, "damage": applied,
        "cleared": cleared, "target": (l if cleared > 0 else -1), "bypass": bypass}


# 源 `StatChangePhase.getRandomStat()`：`randSeedInt(SPD+1)=Ze(5)` -> 0..4 均匀，含已 +6 项。
static func _random_stat(unit_rand: Callable) -> int:
    return clampi(int(floor(float(unit_rand.call()) * float(STAT_COUNT))), 0, STAT_COUNT - 1)


# 一次 `handleBossSegmentCleared(l)` 的纯强化结算：
#   1. 源权重数组为空、和为 NaN，`Ze(NaN)` 每个清段仍消费 1 次全局 frac（结果恒为 RAND）；
#      这里明确消费该次骰，不在 Godot 里真算 NaN。
#   2. 之后 StatChangePhase 用 Ze(5) 解析 RAND；同批阶段按源 `aggregateStatChanges` 聚合
#      （同能力项合并 levels、同 levels 项合并 stats）——单项播该项、多项播 mix。
# unit_rand 是 0..1 Callable（可注入固定序列验证耗骰次数 / 顺序）。
# 返回 {"amount": 每次强化量, "plays": [{"stats":[stat...], "levels":int}...]}，plays 按源阶段运行顺序。
static func simulate_stat_boosts(segments: int, target_l: int, clear_count: int,
        unit_rand: Callable) -> Dictionary:
    var amount := boost_amount(target_l, segments)
    for _i in clear_count:
        unit_rand.call()   # 源 Ze(NaN) 消费的全局 frac
    # 源用 unshiftPhase 逐条插到队首：先 push 的排在后面，队首是最后 push 的那条。
    var queue: Array = []
    for _i in clear_count:
        queue.push_front({"stats": [STAT_RAND], "levels": amount})
    var plays: Array = []
    while not queue.is_empty():
        var phase: Dictionary = queue.pop_front()
        var is_random := false
        var phase_stats: Array = phase["stats"]
        if phase_stats.size() == 1 and int(phase_stats[0]) == STAT_RAND:
            phase_stats[0] = _random_stat(unit_rand)
            is_random = true
        _aggregate_stat_phase(phase, queue, is_random, unit_rand)
        plays.append({"stats": (phase["stats"] as Array).duplicate(), "levels": int(phase["levels"])})
    return {"amount": amount, "plays": plays}


# 源 `aggregateStatChanges(t)` 的等价（本批只有单/多项同 levels 阶段，无 ACC/EVA、无特性）。
static func _aggregate_stat_phase(phase: Dictionary, queue: Array, is_random: bool,
        unit_rand: Callable) -> void:
    if phase["stats"].size() == 1:
        while true:
            var ri := -1
            for j in queue.size():
                var r: Dictionary = queue[j]
                if r["stats"].size() != 1:
                    continue
                var rs := int(r["stats"][0])
                if rs == int(phase["stats"][0]) or (is_random and rs == STAT_RAND):
                    ri = j
                    break
            if ri < 0:
                break
            var r2: Dictionary = queue[ri]
            if int(r2["stats"][0]) == STAT_RAND:
                r2["stats"][0] = _random_stat(unit_rand)
                if int(r2["stats"][0]) != int(phase["stats"][0]):
                    continue
            phase["levels"] = int(phase["levels"]) + int(r2["levels"])
            queue.remove_at(ri)
    while true:
        var ri2 := -1
        for j in queue.size():
            if int((queue[j] as Dictionary)["levels"]) == int(phase["levels"]):
                ri2 = j
                break
        if ri2 < 0:
            break
        var r3: Dictionary = queue[ri2]
        phase["stats"].append_array(r3["stats"])
        queue.remove_at(ri2)
