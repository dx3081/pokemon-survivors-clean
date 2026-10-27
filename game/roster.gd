extends RefCounted
const Stats := preload("res://game/stats.gd")
const Units := preload("res://data/units.gd")
const Pokedex := preload("res://data/pokedex.gd")
const PokemonGrowth := preload("res://game/pokemon_growth.gd")
const WildSpecies := preload("res://data/pokemon_wild_species.gd")

# 平原真实野生敌人的本作实时外形 / 碰撞值：与现有 caterpie 模板同量级，不按物种改世界尺寸。
const WILD_SCALE := 0.85
const WILD_RADIUS := 0.32
const BOSS_SIZE := 1.6   # 头目体型（含碰撞半径）放大倍数（用户 2026-10-20：头目每次看不到，要大一点）
# 野怪基础世界速度 = 主角基础速度（用户 2026-10-17：“一样的，不要做区别”“不如大家都改成 4.8”）：原来野怪 3.4、主角 6，再封顶 5.3，
# 跑起来怪永远追不上、排成一队跟在身后；现在两边同一个起点 4.8 米/秒，快慢只看各自的速度六维（game/pokemon_speed.gd 同一套系数）。
const WILD_SPEED := 4.8
# 世界米/秒上限 = 基础 4.8 × 速度系数的总上限 3.0（与主角同口径，不再单给野怪压低）。原六维 SPD 与此无关。
const WILD_SPEED_CAP := 9.6   # 野生怪移速上限 = 4.8 × 2（和玩家移动倍率上限 2 倍一致，2026-10-24）

static func unit_stats(unit_id: String, _level := 1) -> Stats:
    var u: Dictionary = Units.UNITS[unit_id]
    var st := Stats.new()
    for pair in [["hp_max", "hp"], ["attack", "attack"], ["defence", "defence"], ["move_speed", "speed"], ["aspd", "aspd"], ["magnet", "magnet"]]:
        st.set_base(pair[0], float(u.get(pair[1], 0.0)))
    return st

static func speed_jitter() -> float:
    return randf_range(0.9, 1.1)

# 物种六项种族值（顺序 [HP,ATK,DEF,SPATK,SPDEF,SPD]）；图鉴缺行时用绿毛虫兜底。
static func _species_base_stats(species_id: int) -> Array:
    var entry := Pokedex.entry(species_id)
    var base: Array = entry.get("stats", []) if not entry.is_empty() else []
    if base.size() >= PokemonGrowth.STAT_COUNT:
        return base
    return [45, 30, 35, 20, 20, 45]

static func _species_types(species_id: int) -> Array:
    var entry := Pokedex.entry(species_id)
    return entry.get("types", []) if not entry.is_empty() else []

# _xp_mult（旧参数名 xp_mult）：波次的旧经验倍率，保留形参只为兼容现有调用，
# 本轮起明确不参与经验计算；经验只由 species_id 的原作基础经验 + 实际 enemy level 决定。
#
# 敌人六维：按 Pokedex 种族值 + 实际 level + 已定默认 IV0 / 中性性格，走 PokemonGrowth.calculate_stats
# 现算（与玩家同一原公式）。普通 / 精英 / 现有四个头目同物种同等级得到同一套原能力值，
# 不再用旧 HP12 + 每级 7、精英 HP*3、固定头目 850..3600 或 ATK+1.2。
# rank / 外形 scale / radius / move speed / 波次等级 / 原经验 / 掉落仍按原样保留。
static func enemy(unit_id: String, level := 1, rank := "", speed_mult := 1.0, scale_mult := 1.0, _xp_mult := 1.0) -> Dictionary:
    var u: Dictionary = Units.UNITS[unit_id]
    var t := u.duplicate(true)
    if rank == "":
        rank = str(u.get("rank", ""))
    var elite := rank == "elite"
    var size := float(u["scale"]) * scale_mult * (1.4 if elite else 1.0)
    var species_id := int(u.get("species_id", 0))
    var base_exp := int(Units.SPECIES_BASE_EXP.get(species_id, 0))
    var six: Array = PokemonGrowth.calculate_stats(_species_base_stats(species_id), level,
        PokemonGrowth.DEFAULT_IVS, PokemonGrowth.nature_multipliers(PokemonGrowth.DEFAULT_NATURE_ID))
    # 击倒经验照搬原作单参与者野生战：按敌人自己的 species_id 查基础经验，用实际 level 现算。
    # 普通 / 精英 / 四个头目同物种同等级结果相同，不再吃精英 *5 或波次 xp_mult（0.9、0.8、0.4 等）。
    t.merge({"id": unit_id, "level": level, "rank": rank, "boss": rank == "boss", "elite": elite,
        "final": bool(u.get("final", false)), "scene": Units.SCENE, "scale": size,
        "radius": float(u["radius"]) * size,
        "hp": float(six[0]), "stats": six, "types": _species_types(species_id),
        "attack": float(six[1]), "defence": float(six[2]),
        "speed": minf(WILD_SPEED_CAP, float(u["speed"]) * speed_mult), "xp": float(PokemonGrowth.defeat_exp(base_exp, level)),
        "knock": 0.15 if rank == "boss" else (0.5 if elite else 1.0)}, true)
    if elite:
        t["name"] = "精英绿毛虫"
    return t


# 平原真实野生敌人模板：物种 / 形态 / 等级 / 六维 / 属性 / 基础经验全部来自物种资料，
# 不读 data/units.gd 的绿毛虫兜底，也不吃旧精英 / 波次倍率。
# t["xp"] = 原作 defeat_exp(baseExp, level)（无 rank / density / xp_mult 系数）。
# 显示走 characters/caterpie.gd 的 set_wild_species(species_id, form_index)；未知物种返回空字典，
# 调用方必须显式跳过（不许静默换绿毛虫数值 / 画像）。
# speed_mult 是 game/waves.gd 已经提供的**本作实时世界移速倍率**（普通 1.0、事件 1.05/1.15/1.2/1.25 等）；
# 世界速度 = min(WILD_SPEED_CAP, WILD_SPEED * speed_mult)。原六维 SPD 仍只用于吐丝 / 麻痹比值，
# 不在这里换算成米/秒。speed_mult 只影响 speed，不影响物种抽样 / 六维 / 属性 / XP / RNG 次数。
static func wild_enemy(species_id: int, form_index: int, level: int, speed_mult := 1.0) -> Dictionary:
    var row: Dictionary = WildSpecies.row_of(species_id)
    if row.is_empty():
        push_error("roster.wild_enemy: unknown plains species %d" % species_id)
        return {}
    var form: Dictionary = WildSpecies.form_at(species_id, form_index)
    var six: Array = PokemonGrowth.calculate_stats(form["stats"], level,
        PokemonGrowth.DEFAULT_IVS, PokemonGrowth.nature_multipliers(PokemonGrowth.DEFAULT_NATURE_ID))
    var base_exp := int(form["base_exp"])
    return {
        "id": "wild_%d_%d" % [species_id, form_index],
        "wild": true,
        "source_species_id": species_id,
        "species_id": species_id,
        "form_index": form_index,
        "sprite_key": str(form["sprite_key"]),
        "name": str(row["display"]),
        "level": level,
        "rank": "",
        "boss": false,
        "elite": false,
        "final": false,
        "scene": Units.SCENE,
        "scale": WILD_SCALE,
        "radius": WILD_RADIUS,
        "hp": float(six[0]),
        "stats": six,
        "types": (form["types"] as Array).duplicate(),
        "attack": float(six[1]),
        "defence": float(six[2]),
        "speed": minf(WILD_SPEED_CAP, WILD_SPEED * speed_mult),
        "speed_mult": speed_mult,
        "xp": float(PokemonGrowth.defeat_exp(base_exp, level)),
        "knock": 1.0,
    }


# 平原真实头目模板（第二段）：物种 / 形态 / 等级 / 六维 / 类型 / baseExp / XP 全部取最终原物种，
# 与普通 wild 同一份 `wild_enemy`（原 source `getMaxHp()` 就是原六维 HP），**不乘旧头目
# HP/ATK/XP/level 倍率**。形体 / 碰撞 / 世界速度沿用当前 wild 模板；只在原 boss 模板上补
# `boss` / `final` / `segments` / 原 boss 击退系数 0.15。段数由调用方从 `roll_boss_encounter` 传入。
# `final` 只表示本作这一局是否胜利，不代表原 `Ba.FINAL_BOSS` 永恒之花锁血 / 变身保护。
const BOSS_HP_MULT := 3.0      # 头目血量 ×3（还是分段）
const BOSS_LEVEL_BONUS := 5    # 头目比同场普通怪高 5 级


static func wild_boss_enemy(species_id: int, form_index: int, level: int, segments: int,
        final := false, speed_mult := 1.0) -> Dictionary:
    var t := wild_enemy(species_id, form_index, level + BOSS_LEVEL_BONUS, speed_mult)
    if t.is_empty():
        return {}
    # 头目只在战斗里加强（用户 2026-10-22：“头目像高级兵”；抓到手的是普通的一只，抓宠只记物种 / 性格 / 个体值 / 闪光）
    t["hp"] = float(t["hp"]) * BOSS_HP_MULT
    t["rank"] = "boss"
    t["boss"] = true
    t["final"] = final
    t["segments"] = maxi(0, segments)
    t["knock"] = 0.15
    t["scale"] = float(t["scale"]) * BOSS_SIZE
    t["radius"] = float(t["radius"]) * BOSS_SIZE
    return t
