extends RefCounted
# 平原实际普通野生物种抽样 · 转写自原作 `Arena.randomSpecies()` / `Ty.getWildSpeciesForLevel()` /
# `arena_pool_sampling` / `actor_species_class` / `seeded_integer` / `strength_enum` /
# `wild_delay_enum` / `arena_form_choice` / `wave_cycle_offset`）。
#
# 普通抽样只做**普通池 0..4 / ordinary / f=false**（`roll_encounter` / `sample_species`
# 语义与耗骰不变）；头目第 1 段另加**独立 boss 抽样入口** `sample_boss_species` /
# `roll_boss_encounter`：走原 BOSS 池 5..8 + `Ze(64)` + WEAKER=1，仍不接真实刷怪 / 分段伤害。
# 等级由调用方走已验的 game/pokemon_encounter_levels.gd（含原 10 倍数分支）。
#
# 随机来源是一颗可注入的 **0..1 Callable**（不传就用本对象自己的 RandomNumberGenerator）：
#   - 原 `Ze(i,t=0)`（= Phaser integerInRange）：`i<=1` 直接返回 t、**不耗骰**；否则 floor(unit*i)+t。
#   - 原累计 Map 选择用 `Ze(m)`，**m 可为小数**：m<=1 直接 0；否则 floor(unit*m)，整数结果再与累计小数键比较。
#   - 原生存骰 `realInRange(0,1)`：`c===1` 短路不耗骰；否则一次 unit，`unit < c` 才留在原物种。
# 不复刻 Phaser RNG，不建 GameMode / 多 RNG 框架。
#
# 抽样顺序：先生成等级（调用方），再抽 tier / 池条目 / 候选物种；同一局只取一次
# cycleOffset = Ze(8)*5（0,5,...,35），按原 40 波周期算时段，不每只怪重抽 offset。
#
# 来源与边界见 data/POKEMON_PLAINS_SOURCE.md。

const Plains := preload("res://data/pokemon_plains.gd")
const Levels := preload("res://game/pokemon_encounter_levels.gd")
const Species := preload("res://data/pokemon_wild_species.gd")
const BossRules := preload("res://game/pokemon_boss_rules.gd")

# 原作 xe 强度枚举。
const STRENGTH_WEAKEST := 0
const STRENGTH_WEAKER := 1
const STRENGTH_WEAK := 2
const STRENGTH_AVERAGE := 3
const STRENGTH_STRONG := 4
const STRENGTH_STRONGER := 5
# 原作 X1 延迟枚举。
const WILD_DELAY_NONE := 0
# 原作 `randomSpecies` 传奇门槛重试上限：第 11 次仍不满足也沿原作返回。
const LEGENDARY_RETRY_LIMIT := 10
# 745 鬃岩狼人（唯一按时段取形的平原物种；BURMY / ROTOM 不在平原池）。
const LYCANROC := 745

# 本局的地区池（默认平原；其它地区由 data/pokemon_biome_pools.gd 给，格式相同）。
var pool_data: Dictionary = Plains.PLAINS
# 本局时段偏移：一次 Ze(8)*5。测试可直接赋值固定值。
var cycle_offset := 0
var _rng := RandomNumberGenerator.new()
var _unit_rand := Callable()


func _init(rng_seed := 0, unit_rand := Callable()) -> void:
    if unit_rand.is_valid():
        _unit_rand = unit_rand
    elif rng_seed == 0:
        _rng.randomize()
    else:
        _rng.seed = rng_seed


# 原作 `Phaser.Math.RND.frac()` 的等效单次 0..1（含 0，不含 1）。
func unit() -> float:
    if _unit_rand.is_valid():
        return float(_unit_rand.call())
    return _rng.randf()


# 原作 `Ze(i,t=0)`：i<=1 直接返回 t、不耗骰；否则 integerInRange(t, i-1+t) = floor(unit*i)+t。
func ze(count: int, offset := 0) -> int:
    if count <= 1:
        return offset
    return int(floor(unit() * float(count))) + offset


# 原作 `Ze(m)`，m 可为小数：m<=1 返回 0、不耗骰；否则 floor(unit*m)。
func ze_float(m: float, offset := 0) -> int:
    if m <= 1.0:
        return offset
    return int(floor(unit() * m)) + offset


# 原作 `getGeneratedWaveCycleOffset()`：本局一次 Ze(8)*5（0,5,...,35）。
func roll_cycle_offset() -> int:
    cycle_offset = ze(8) * 5
    return cycle_offset


func time_for_wave(wave_index: int) -> int:
    return Plains.time_for_wave(wave_index, cycle_offset)


# 745 照原作 `arena.getSpeciesFormIndex`：平原没有 BURMY / ROTOM 分支；
# DAY/DAWN=0（白昼）、DUSK=2（黄昏）、NIGHT=1（午夜）。其余物种默认 0。
static func form_index_for(species_id: int, time: int) -> int:
    if species_id == LYCANROC:
        match time:
            Plains.TIME_DAWN, Plains.TIME_DAY:
                return 0
            Plains.TIME_DUSK:
                return 2
            Plains.TIME_NIGHT:
                return 1
    return 0


# 一次完整普通遭遇：先生成原等级，再抽物种 / 形态（顺序同任务约定）。
# 返回 {"species_id", "form_index", "level"}；species_id < 0 表示有界失败（真实平原池不会发生）。
func roll_encounter(wave_index: int) -> Dictionary:
    var level := Levels.level_for_wave(wave_index, unit, false, false)
    var pick := sample_species(wave_index, level)
    pick["level"] = level
    return pick


# 原 `randomSpecies(wave, level, 0)` + 原 `getWildSpeciesForLevel(level, true, false, classic)`。
func sample_species(wave_index: int, level: int) -> Dictionary:
    var time := time_for_wave(wave_index)
    var rolled := _random_species(wave_index, level, 0)
    if rolled < 0:
        return {"species_id": -1, "form_index": 0}
    var final_id := secondary_species(rolled, level, time)
    return {"species_id": final_id, "form_index": form_index_for(final_id, time)}


# 独立头目抽样（原 `randomSpecies` 的 BOSS 分支）：始终按原 f=true 走池 5..8（`Ze(64)`），
# 二次修正用 `getWildSpeciesForLevel(level, true, true, classic)` 即 WEAKER=1；等级由调用方先算。
# 返回 {"species_id", "form_index"}；species_id < 0 = 有界失败（未知物种显式失败，不换绿毛虫）。
func sample_boss_species(wave_index: int, level: int) -> Dictionary:
    var time := time_for_wave(wave_index)
    var rolled := _random_species(wave_index, level, 0, true)
    if rolled < 0:
        return {"species_id": -1, "form_index": 0}
    var final_id := secondary_species(rolled, level, time, true)
    if not Species.has_species(final_id):
        push_error("pokemon_wild_encounters.sample_boss_species: unknown plains species %d" % final_id)
        return {"species_id": -1, "form_index": 0}
    return {"species_id": final_id, "form_index": form_index_for(final_id, time)}


# 独立头目入口：等级仍原 `Levels.level_for_wave`（默认 final_boss=false，不把 200 波当
# FINAL_BOSS）；先生成等级、再抽 species/form，最后按**最终物种**原 baseTotal / 传奇 flags
# 算段数。forced 只进段数规则（原 `getEncounterBossSegments` 的 l），不改变池抽样本身。
# 返回 {"species_id", "form_index", "level", "base_total", "segments"}；失败 species_id=-1。
func roll_boss_encounter(wave_index: int, forced := false) -> Dictionary:
    var level := Levels.level_for_wave(wave_index, unit, false, false)
    var pick := sample_boss_species(wave_index, level)
    pick["level"] = level
    var species_id := int(pick["species_id"])
    if species_id < 0:
        pick["base_total"] = 0
        pick["segments"] = 0
        return pick
    pick["base_total"] = int(Species.row_of(species_id)["base_total"])
    pick["segments"] = BossRules.segments_for_species(wave_index, level, species_id, forced)
    return pick


# 原 `Ty.getWildSpeciesForLevel(level, wild=true, isBoss, gameMode)`：
# 普通图（非 endless）is_boss=false -> getSpeciesForLevel(level, true, false, AVERAGE=3)；
# 头目 is_boss=true -> WEAKER=1。`trainer` 恒 false（野生，绝不能把 boss 当 trainer）。
# 单独命名是给检查直接喂固定 rolled 物种 / 等级，不经过 tier roll。
func secondary_species(species_id: int, level: int, time: int, is_boss := false) -> int:
    var strength := STRENGTH_WEAKER if is_boss else STRENGTH_AVERAGE
    return _get_species_for_level(species_id, level, true, false, strength, time,
        form_index_for(species_id, time))


# 原作 `randomSpecies(t, n, r)` 的池分支：is_boss=false 走普通池 `Ze(512)` 0..4；
# is_boss=true 走 BOSS 池 `Ze(64)` 5..8（空池逐级回退，必要时到普通池）。
# 返回源物种 ID，-1 = 本实现的有界失败。
var last_tier := -1   # 上一次普通遭遇抽到的档（0 普通 1 少见 2 稀有 3 超稀有 4 究极稀有）：“稀有”标签看它（2026-10-24）


func _random_species(wave_index: int, level: int, retry: int, is_boss := false) -> int:
    var time := time_for_wave(wave_index)
    var tier := -1
    if is_boss:
        tier = BossRules.boss_tier_with_fallback(ze(BossRules.BOSS_ROLL_DIE), time, [], pool_data)
    else:
        tier = Plains.roll_rare_tier(ze(512), time, pool_data)
        last_tier = tier
    if tier < 0:
        return -1
    var pool := Plains.merged_pool_in(pool_data, tier, time)
    if pool.is_empty():
        return -1
    # 先均匀抽**池条目**，不是把门槛字典展开后按物种均分。
    var entry: Variant = pool[ze(pool.size())]
    var candidates := Plains.pool_entry_candidates(entry, level)
    if candidates.is_empty():
        # 条目的最低等级门槛比当前等级还高（只在平原之外的个别地区池里出现）：整次重新抽，上限同传奇重试。
        if retry < LEGENDARY_RETRY_LIMIT:
            return _random_species(wave_index, level, retry + 1, is_boss)
        return -1
    var species_id := int(candidates[0]) if candidates.size() <= 1 else int(candidates[ze(candidates.size())])
    var row: Dictionary = Species.row_of(species_id)
    if row.is_empty():
        return -1
    var needs_retry := false
    if bool(row["sub_legendary"]) or bool(row["legendary"]) or bool(row["mythical"]):
        var total := int(row["base_total"])
        if total >= 720:
            needs_retry = level < 90
        elif total >= 670:
            needs_retry = level < 70
        elif total >= 580:
            needs_retry = level < 50
        else:
            needs_retry = level < 30
    if needs_retry and retry < LEGENDARY_RETRY_LIMIT:
        # 整次重新抽 tier / 条目；第 11 次仍不满足也沿原作返回（不无限重试、不换绿毛虫）。
        return _random_species(wave_index, level, retry + 1, is_boss)
    return species_id


# 原作 `Ty.getSpeciesForLevel(level, wild, trainer, strength)`（含 prevolution 回退、wildDelay
# 概率、survival c、累计 Map 与递归修正）。trainer=false（野生）。
func _get_species_for_level(species_id: int, level: int, wild: bool, trainer: bool,
        strength: int, time: int, form_index: int) -> int:
    if not Species.has_species(species_id):
        return species_id
    var prevos := _prevolutions_of(species_id, form_index, time)
    var i := prevos.size() - 1
    while i >= 0:
        var p: Array = prevos[i]
        if level < int(p[1]):
            return int(p[0])
        i -= 1
    if not wild or not Species.has_evolution(species_id):
        return species_id
    var evos: Array = Species.row_of(species_id)["evolutions"]
    var acc := {}   # 累计小数键 -> 目标物种 ID（插入顺序 = 原 Map 顺序）
    var m := 0.0
    var c := 1.0
    for e: Dictionary in evos:
        var elevel := int(e["level"])
        if elevel > level:
            continue
        var target_id := int(e["species_id"])
        # r（trainer 标记）在野生路径恒 false：非地区物种 -> 地区演化直接 A=0 拒绝。
        var regional_target := (not Species.is_regional(species_id)) and Species.is_regional(target_id)
        var a := 0.0
        if (not trainer) and regional_target:
            a = 0.0
        elif int(e["wild_delay"]) == WILD_DELAY_NONE:
            if strength == STRENGTH_STRONGER:
                a = 1.0
            else:
                var r := _strength_level_diff(strength)
                var l := 0.875 - 0.125 * float(strength)
                var x := minf(float(level - elevel), float(r)) / float(r)
                a = minf(l + _ease_in(x) * (1.0 - l), 1.0)
        else:
            var r2 := maxf(float(elevel - 1 + int(e["wild_delay"]) * _strength_level_diff(strength)), 1.0)
            var l2 := maxf(float(elevel) if elevel > 1 else floorf(r2 / 2.0), 1.0)
            if elevel <= 1 and Species.prevolution_of(species_id) >= 0:
                var n := Species.evolution_level(Species.prevolution_of(species_id), species_id)
                if n > 1:
                    l2 = float(n)
            var above := maxf(float(level) - l2, 0.0)
            var x1 := minf(above, r2) / r2
            var x2 := minf(above, r2 * 2.5) / (r2 * 2.5)
            a = minf(0.65 * _ease_in(x1) + 0.35 * _ease_out(x2), 1.0)
        if a > 0.0:
            if regional_target:
                a = a / (16.0 if Species.is_rare_regional(target_id) else 4.0)
            m += a
            acc[m] = target_id
            # c = 1 - max(A)：只有 A 更大时才更新。
            if 1.0 - a < c:
                c = 1.0 - a
    # c===1 短路不耗骰；否则一次 real，unit < c 就留在原物种。
    if c == 1.0 or unit() < c:
        return species_id
    var h := 0
    if acc.size() != 1:
        h = ze_float(m)
    for key: float in acc.keys():
        if h < key:
            var target := int(acc[key])
            return _get_species_for_level(target, level, true, trainer, strength, time,
                form_index_for(target, time))
    return species_id


# 原作 `getPrevolutionLevels()`：遍历 Ut 全部行、保留顺序 / 重复行与 evoFormKey 过滤，再递归。
func _prevolutions_of(species_id: int, form_index: int, time: int) -> Array:
    var out: Array = []
    var forms: Array = Species.forms_of(species_id)
    var this_key := ""
    if not forms.is_empty():
        this_key = str(forms[clampi(form_index, 0, forms.size() - 1)]["form_key"])
    for from_id: int in Species.all_ids():
        for e: Dictionary in Species.row_of(from_id)["evolutions"]:
            if int(e["species_id"]) != species_id:
                continue
            var evo_form_key := str(e["evo_form_key"])
            if not forms.is_empty() and evo_form_key != "" and evo_form_key != this_key:
                continue
            var from_key := int(from_id)
            out.append([from_key, int(e["level"])])
            for sub: Array in _prevolutions_of(from_key, form_index_for(from_key, time), time):
                out.append(sub)
    return out


# 原作 `getStrengthLevelDiff()`（Math.min(t, STRONGER)）。
func _strength_level_diff(strength: int) -> int:
    match mini(strength, STRENGTH_STRONGER):
        STRENGTH_WEAKEST:
            return 60
        STRENGTH_WEAKER:
            return 40
        STRENGTH_WEAK:
            return 20
        STRENGTH_AVERAGE:
            return 10
        STRENGTH_STRONG:
            return 5
        _:
            return 0


# 原 Phaser `Sine.easeIn` = 1 - cos(pi*x/2)。
static func _ease_in(x: float) -> float:
    return 1.0 - cos(x * PI * 0.5)


# 原 Phaser `Sine.easeOut` = sin(pi*x/2)。
static func _ease_out(x: float) -> float:
    return sin(x * PI * 0.5)
