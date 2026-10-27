extends "res://main/abilities.gd"
var potions: Array[Node3D] = []
# 金珠 / 大金珠（用户 2026-10-23）：普通怪 1% 掉金珠（= 这只 10 次击杀的点数），头目必掉大金珠（= 50 次）；
# 捡到一次性加点数，也吃护身金币。原版金珠是一次性给钱，本作给点数。
const NUGGET_CHANCE := 0.01
const NUGGET_KILLS := 10
const BIG_NUGGET_KILLS := 50
var nuggets: Array[Node3D] = []


func _drop_nugget(pos: Vector3, points: int, big: bool, cake := false) -> void:
    var root := Node3D.new()
    var spr := Sprite3D.new()
    spr.texture = preload("res://ui/rogue_atlas.gd").frame("icons/items", "strawberry_sweet" if cake else ("big_nugget" if big else "nugget"))
    spr.pixel_size = 0.03 if big else 0.024
    spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    spr.position = Vector3(0, 0.45, 0)
    root.add_child(spr)
    root.position = Vector3(pos.x, 0, pos.z)
    root.set_meta("points", points)
    root.set_meta("big", big)
    root.set_meta("cake", cake)
    add_child(root)
    nuggets.append(root)


func _update_nuggets() -> void:
    var i := nuggets.size() - 1
    while i >= 0:
        var ng := nuggets[i]
        if not is_instance_valid(ng):
            nuggets.remove_at(i)
            i -= 1
            continue
        ng.get_child(0).position.y = 0.45 + sin(time * 3.0 + i) * 0.06
        var off := player.position - ng.position
        off.y = 0
        var pull := _magnet_radius()
        if off.length_squared() < pull * pull:
            ng.position += off.normalized() * minf(off.length(), 8.0 * get_process_delta_time())   # 和经验球一样被吸过来
        if off.length_squared() < 0.8 * 0.8:
            if bool(ng.get_meta("cake", false)):
                if points_wallet == null:
                    _points_begin_run()
                points_wallet.add_cake(1)
                if hud != null:
                    hud.show_banner("捡到蛋糕！现在有 %d 块（回选宠页可以生蛋）" % points_wallet.cakes)
            else:
                var got := _points_award_flat(int(ng.get_meta("points")))
                if hud != null and got > 0:
                    hud.show_banner("捡到%s：+%d 点" % ["大金珠" if bool(ng.get_meta("big")) else "金珠", got])
            sfx.pickup()
            ng.queue_free()
            nuggets.remove_at(i)
        i -= 1
var spawn_queue: Array = []
var unit_cache := {}
# 平原真实野生敌人模板缓存：key 必含物种 / 形态 / 等级，不同形态不串，也不与旧 unit_cache 共用。
var wild_cache := {}
const CATERPIE_SCENE := preload("res://characters/caterpie.tscn")

# 刷怪方向偏向前进方向（用户 2026-10-17：“怪一直在屁股后面追着，没有迎面过来的”）：
# 主角一直跑的话，侧面 / 后面刷的怪追不上、会排成一队跟在身后（现在主角和野怪基础速度同为 4.8，仍按速度六维拉开）；所以一半的怪从前进方向 ±60° 里刷。
const SPAWN_FRONT_SHARE := 0.5
const SPAWN_FRONT_CONE_DEG := 60.0


func _spawn_angle() -> float:
    if randf() < SPAWN_FRONT_SHARE:
        return atan2(facing.z, facing.x) + randf_range(-1.0, 1.0) * deg_to_rad(SPAWN_FRONT_CONE_DEG)
    return randf() * TAU


# 撤离倒计时：真正的实现在 main/meta_flow.gd（子类覆盖）。
func _evac_tick() -> void:
    pass


# 物种糖果的好感（原版起始种好感）：每过一分钟（= 一场）+4，攒满给 1 颗糖果；记在开局那只的起始种上。
func _starter_friendship_tick(waves_passed: int) -> void:
    if points_wallet == null or waves_passed <= 0 or player_train_key <= 0:
        return
    var root := AB.root_of(player_train_key)
    var per := int(floorf(SpeciesCandy.FRIENDSHIP_PER_WAVE * HeldItems.friendship_mult(int(run_held.get("SOOTHE_BELL", 0)))))   # 安抚之铃
    var got: int = points_wallet.add_friendship(root, per * waves_passed, SpeciesCandy.friendship_cap(root))
    if got > 0 and hud != null:
        hud.show_banner("好感满了：物种糖果 +%d" % got)


func _spawn_tick(delta: float) -> void:
    _evac_tick()
    # 本段实时适配：waveIndex = 当前阶段序号 + 1（0..59.999s = 1，60..119.999 = 2，…）。
    var wave_index := waves.wave_index(time)   # 真实第几分钟（亲密度每分钟 +2、刷怪节奏 / 阶段名用它）
    var battle_wave: int = preload("res://data/biomes.gd").run_wave(map_id, time - map_time_start, entry_wave, maxi(1, level - candy_levels), Waves.RUN_SECONDS) if battle_wave_scaling else wave_index   # 战斗波次（无尽）：等级 / 稀有门槛 / 野外进化 / 头目段数 / 昼夜按它算；入场波次 + 地区带速度，敌人等级不低于玩家等级（去掉糖果等级）的 70%
    battle_wave = _map_grace_wave(battle_wave)
    # 亲密度：每过一波 +2（原版每打赢一场 +2），上限 255（迁怒 / 报恩的威力用它）。
    _map_weather_tick(wave_index, battle_wave)   # 地图天气：每过一分钟（原版一场战斗）重掷
    if wave_index > friendship_wave:
        var soothe := HeldItems.friendship_mult(int(run_held.get("SOOTHE_BELL", 0)))   # 携带道具·安抚之铃
        player_friendship = mini(255, player_friendship + int(floorf(2.0 * soothe)) * (wave_index - friendship_wave))
        _starter_friendship_tick(wave_index - friendship_wave)
        friendship_wave = wave_index
    for s in waves.tick(time, delta, enemies.size() + spawn_queue.size(), time - map_time_start):   # 松紧循环按在这个地区待了多久
        var n: int = s["count"]
        var base_ang := _spawn_angle()
        var src := str(s.get("source", "legacy"))
        var is_wild: bool = src == "wild"
        var is_boss: bool = src == "boss"
        var boss_name := ""
        for k in n:
            # 每一只实际入队敌人都各自抽一颗：物种 / 原等级 / 形态 / 六维；一群不共享。
            # 头目用独立原 BOSS 池入口（含原 segments）；普通用原普通池入口。
            # 世界移速沿用 waves 已经提供的 speed_mult（普通 1.0、事件 1.05/1.15/1.2/1.25…）。
            var t: Dictionary
            if is_boss:
                t = _boss_unit(battle_wave, bool(s.get("final", false)) and not endless, float(s["speed_mult"]))
            elif is_wild:
                t = _wild_unit(battle_wave, float(s["speed_mult"]))
            else:
                t = _unit(s["id"], s["level"], s["rank"], s["speed_mult"], s["scale_mult"], s["xp_mult"])
            if t.is_empty():
                continue
            if is_boss:
                boss_name = str(t["name"])
            var off: Vector3
            match s["pattern"]:
                "cluster":   # 从同一个方向来一群：都在 3 米以内
                    var j := randf() * TAU
                    off = Vector3(cos(base_ang), 0, sin(base_ang)) * SPAWN_RADIUS + Vector3(cos(j), 0, sin(j)) * randf() * 3.0
                "encircle":  # 均匀围成一整圈
                    var a := base_ang + TAU * k / n
                    off = Vector3(cos(a), 0, sin(a)) * ENCIRCLE_RADIUS
                _:           # 四周随机
                    var a2 := _spawn_angle()
                    off = Vector3(cos(a2), 0, sin(a2)) * SPAWN_RADIUS
            spawn_queue.append([t, off])
        if is_boss and boss_name != "":
            hud.show_banner("头目 %s 来了！" % boss_name)
        elif s["label"] != "":
            hud.show_banner(s["label"])
    _squad_tick(battle_wave)


# 逐只真实抽样：等级走原 level_for_wave（先生成），物种 / 形态走原 randomSpecies +
# getWildSpeciesForLevel。同一局共用 wild 里那颗 RNG；队列存的是当时抽好的 t，跨波 drain 不重抽。
# speed_mult 进缓存键：相同 species/form/level 的 1.0 与 1.15 是两份模板，互不覆盖；
# 抽样/RNG 次数与 speed_mult 无关（每只仍各掷一次）。
func _wild_unit(wave_index: int, speed_mult := 1.0) -> Dictionary:
    var pick: Dictionary = wild.roll_encounter(wave_index)
    var species_id := int(pick["species_id"])
    if species_id < 0:
        push_error("wild encounter sampling failed at wave %d" % wave_index)
        return {}
    var level := int(pick["level"])
    var form_index := int(pick["form_index"])
    var key := "%d|%d|%d|%.4f" % [species_id, form_index, level, speed_mult]
    if not wild_cache.has(key):
        wild_cache[key] = Roster.wild_enemy(species_id, form_index, level, speed_mult)
    var out: Dictionary = (wild_cache[key] as Dictionary).duplicate()   # 浅拷：每只记自己抽到的档，不写共享模板
    out["pool_tier"] = wild.last_tier
    return out


# 真实头目抽样：等级 / species / form / segments 一次抽齐（原 BOSS 池 + WEAKER=1），
# 六维 / 类型 / baseExp / XP 由 Roster.wild_boss_enemy 取最终原物种（原 getMaxHp = 原六维 HP，
# 不乘旧头目 HP/ATK/XP/level 倍率）。缓存键含 boss/final/segments/speed，绝不与普通 wild 混。
func _boss_unit(wave_index: int, final: bool, speed_mult := 1.0) -> Dictionary:
    var pick: Dictionary = wild.roll_boss_encounter(wave_index, true)
    var species_id := int(pick["species_id"])
    if species_id < 0:
        push_error("boss encounter sampling failed at wave %d" % wave_index)
        return {}
    var level := int(pick["level"])
    var form_index := int(pick["form_index"])
    var segments := int(pick["segments"])
    var key := "boss|%d|%d|%d|%d|%d|%.4f" % [species_id, form_index, level, segments,
        1 if final else 0, speed_mult]
    if not wild_cache.has(key):
        wild_cache[key] = Roster.wild_boss_enemy(species_id, form_index, level, segments, final, speed_mult)
    return wild_cache[key]


# 排着队的怪一帧造几只，位置按造出来那一刻主角在哪算
func _drain_spawns() -> void:
    var n := mini(SPAWN_PER_FRAME, spawn_queue.size())
    for i in n:
        var item: Array = spawn_queue[i]
        _spawn(item[0], player.position + item[1])
    if n > 0:
        spawn_queue = spawn_queue.slice(n)



# xp_mult 仅为兼容波次调用保留；roster 已改为按 species_id 基础经验 + 实际等级算 xp，不读它。
func _unit(id: String, lv: int, rank := "", speed_mult := 1.0, scale_mult := 1.0, xp_mult := 1.0) -> Dictionary:
    var key := "%s|%d|%s|%.3f|%.3f|%.3f" % [id, lv, rank, speed_mult, scale_mult, xp_mult]
    if not unit_cache.has(key):
        var t := Roster.enemy(id, lv, rank, speed_mult, scale_mult, xp_mult)
        t["scene"] = CATERPIE_SCENE
        unit_cache[key] = t
    return unit_cache[key]

func _stress_ids() -> Array[String]:
    return ["caterpie"]

func _spawn(t: Dictionary, pos: Vector3) -> void:
    var e := Enemy.new()
    # 每个敌人拿自己的一份数据副本：unit_cache 的 t 是同一 key 所有敌人共用的模板，
    # 若直接引用，任何一处按敌人改 t（类型 / 上限 / 掉落）都会串到别的同类敌人。
    # 只做浅拷贝：顶层字段各自一份，数组 / 场景等嵌套值仍共享（PackedScene 深拷后无法实例化）。
    e.t = t.duplicate()
    e.hp = float(e.t["hp"])
    e.born_at = run_clock
    # 头目：每敌人各持分段数 / 当前段 index（初始 N-1），各阶段独立；不写共享模板 t。
    e.segments = int(e.t.get("segments", 0)) if bool(e.t.get("boss", false)) else 0
    e.segment_index = (e.segments - 1) if e.segments > 0 else 0
    e.node = CATERPIE_SCENE.instantiate()
    # 平原真实野生物种：显示自己的物种 / 形态原图集；六维 / 属性 / 经验已在上面的 t 里。
    if bool(e.t.get("wild", false)):
        e.node.set_wild_species(int(e.t["species_id"]), int(e.t["form_index"]))
    e.node.scale = Vector3.ONE * float(t["scale"])
    e.node.position = pos
    add_child(e.node)
    e.ap = e.node.player_animation
    e.ap.play("move")
    e.ap.seek(randf() * e.ap.current_animation_length)
    e.speed_mult = Roster.speed_jitter()
    e.attack_cd = randf_range(0.1, 0.6)
    # 野生敌人：按自己的物种和等级取最后 4 个招里能近身打人的伤害招（第一步，无任何控制 / 远程招）。
    if bool(e.t.get("wild", false)):
        e.moves = EnemyMoves.pool(int(e.t["species_id"]), int(e.t["level"]), MOVES.MOVES, MOVES.IMPLEMENTED)
        var parts := EnemyMoves.split(e.moves, MOVES.MOVES)
        e.melee_moves = parts["melee"]
        e.ranged_moves = parts["ranged"]
        e.debuff_moves = EnemyMoves.debuff_pool(int(e.t["species_id"]), int(e.t["level"]), MOVES.MOVES, MOVES.IMPLEMENTED)
        e.debuff_cd = randf_range(2.0, 6.0)
        e.cur_move = str(e.melee_moves[0])
        e.shoot_cd = randf_range(0.5, 2.5)   # 错开，免得一屏怪同帧齐射
        e.legendary = EnemyMoves.is_legendary(int(e.t["species_id"]))
        if e.legendary and not is_equal_approx(legendary_hp_scale, 1.0):
            e.t["hp"] = float(e.t["hp"]) * legendary_hp_scale   # 这只自己的副本，不串到别的神兽
            e.hp = float(e.t["hp"])
        e.shiny = _shiny_roll()
        e.ivs = [randi() % 32, randi() % 32, randi() % 32, randi() % 32, randi() % 32, randi() % 32]   # 原版野生个体值 0–31
        e.nature_id = randi() % 25   # 原版野生个体随机性格（只用来抓到时解锁，不改敌人六维）
        if e.shiny:
            e.shiny_variant = _shiny_variant_roll(int(e.t["species_id"]), int(e.t["form_index"]))
            # 真换成闪光配色（普通闪光图集 / 蓝闪 / 红闪）
            e.node.set_wild_species(int(e.t["species_id"]), int(e.t["form_index"]), e.shiny_variant)
            # 血量：设置里的闪光血量倍率 × 档位倍率（金 ×1 / 蓝 ×1.5 / 红 ×2），再和神兽倍率叠乘（这只自己的副本）
            var shiny_hp_mult := shiny_hp_scale * float(SHINY_TIER_HP[e.shiny_variant])
            if not is_equal_approx(shiny_hp_mult, 1.0):
                e.t["hp"] = float(e.t["hp"]) * shiny_hp_mult
                e.hp = float(e.t["hp"])
        # 特性：普通野怪按物种掷栏位（隐藏 5%）；头目 / 神兽 / 闪光必定隐藏特性并带被动。
        var ab_special: bool = e.legendary or e.shiny or bool(e.t.get("boss", false))
        var ab_roll := AB.roll_enemy(int(e.t["species_id"]), ab_special, randf() / PokemonShop.ability_charm_mult(_global_charm("ABILITY_CHARM")), randf())   # 特性护符：隐藏特性几率 ×
        e.ability = str(ab_roll["key"])
        e.ability_slot = int(ab_roll["slot"])
        e.passive = AB.enemy_passive(int(e.t["species_id"]), ab_special)
        if e.ability == "WONDER_GUARD" or e.passive == "WONDER_GUARD":
            e.t["hp"] = 1.0   # 神奇守护：最大 HP 恒为 1（闪光 / 神兽倍率也乘不上去，原版就是 1）
            e.hp = 1.0
        if e.shiny:
            e.sparkle = EnemySpecial.make_sparkle(e.node)
        _apply_base_outline(e)   # 闪光 / 神兽金色、头目红色、（设置开了）没抓过的绿色
        e.special_t = randf() * 2.0   # 错开闪烁 / 呼吸的相位
        _mark_special(e, true)
    e.node.set_world_facing(player.position - pos, cam)
    enemies.append(e)

# 稀有且还没捕获过：捕获率表里有、catchRate ≤ RARE_CATCH_RATE、钱包里没解锁。
# “稀有”（2026-10-24 用户同意）：这一只是从地区刷怪表的稀有档及以上抽出来的、而且没抓过。
# 以前看“捕获率低于 45”，新地图里进化后的宝可梦个个都低，满屏稀有，提示成了噪音。没记档的（老检查直接生成的）照旧看捕获率。
func _is_rare_enemy(e: Enemy) -> bool:
    var sid := int(e.t.get("species_id", 0))
    if sid <= 0 or not bool(e.t.get("wild", false)) or e.legendary:
        return false
    var tier := int(e.t.get("pool_tier", -1))
    if tier < 0:
        return _is_rare_uncaught(sid)
    return tier >= RARE_POOL_TIER and _is_uncaught(sid)


func _is_rare_uncaught(species_id: int) -> bool:
    var rate := CaptureSpecies.catch_rate(species_id)
    if rate == CaptureSpecies.UNKNOWN or rate > RARE_CATCH_RATE:
        return false
    if points_wallet != null and points_wallet.is_species_unlocked(species_id):
        return false
    return true


# 原版三档闪光（60% 金 / 30% 蓝 / 10% 红，源码 generateVariant：randSeedInt(10)，4–9→0、1–3→1、0→2）。
# 这只宠物没有蓝 / 红闪配色就落回金色（原版没有变体数据的物种也一直是 0 档）。测试子类可覆写掷骰。
const SHINY_TIER_HP := [1.0, 1.5, 2.0]
const ShinyData := preload("res://data/pokemon_shiny_variants.gd")


func _shiny_variant_roll(species_id: int, form_index: int) -> int:
    if shiny_variant_force >= 0:
        return clampi(shiny_variant_force, 0, 2)
    var roll := randi_range(0, 9)
    var v := 2 if roll == 0 else (1 if roll <= 3 else 0)
    var form: Dictionary = WildSpecies.form_at(species_id, form_index)
    var key := WildSpecies.file_base(species_id, str(form.get("sprite_key", "")))
    while v > 0 and not ShinyData.has_variant(key, v):
        v -= 1
    return v


# 闪光判定（测试子类可覆写）：野生敌人出生时掷一次；forceshiny 启动参数 = 必闪。
func _shiny_roll() -> bool:
    return shiny_force or randf() < shiny_chance * PokemonShop.shiny_charm_mult(_global_charm("SHINY_CHARM"))   # 闪耀护符


# 标名颜色（用户 2026-10-17）：稀有绿、神兽红、闪光黄；一只身上有几条就各上各的色。
const MARKER_SHINY_COLOR := Color(1.0, 0.9, 0.2)
const SHINY_TIER_TAG := ["★ 闪光", "★★ 蓝闪", "★★★ 红闪"]
const SHINY_TIER_COLOR := [Color(0.97, 0.75, 0.13), Color(0.13, 0.97, 0.94), Color(0.91, 0.06, 0.28)]   # 原版 getVariantTint：f8c020 / 20f8f0 / e81048
const SHINY_TIER_NAME := ["闪光", "蓝闪", "红闪"]
const MARKER_LEGEND_COLOR := Color(1.0, 0.3, 0.3)
const MARKER_RARE_COLOR := Color(0.4, 1.0, 0.4)


# 这只野生宠物的物种还没捕获过：捕获率表里有、钱包里没解锁（和“稀有”不同，不管捕获率高低）。
func _is_uncaught(species_id: int) -> bool:
    if CaptureSpecies.catch_rate(species_id) == CaptureSpecies.UNKNOWN:
        return false
    return points_wallet == null or not points_wallet.is_species_unlocked(species_id)


# 暂停抓宠界面进出时重画场上所有敌人的头顶标记（加 / 去掉「未捕获」）。
func _refresh_special_marks() -> void:
    for e in enemies:
        if e.dying >= 0.0 or e.node == null or not is_instance_valid(e.node):
            continue
        _mark_special(e, false)


# 头顶标记 + 稀有出生横幅：闪光「★ 闪光」黄色、神兽「★ 神兽」红色、稀有且未捕获「★ 稀有」绿色，多条各自上色往上叠（神兽不再叠“稀有”）。
func _mark_special(e: Enemy, announce: bool) -> void:
    if e.node == null or not is_instance_valid(e.node) or not e.node.has_method("set_marker_tags"):
        return
    var sid := int(e.t.get("species_id", -1))
    var wild := bool(e.t.get("wild", false))
    var rare := wild and _is_rare_enemy(e)
    var tags: Array = []
    if rare:
        tags.append(["★ 稀有", MARKER_RARE_COLOR])
    if e.legendary:
        tags.append(["★ 神兽", MARKER_LEGEND_COLOR])
    if e.shiny:
        tags.append([SHINY_TIER_TAG[e.shiny_variant], SHINY_TIER_COLOR[e.shiny_variant]])
    e.node.call("set_marker_tags", tags)
    # 暂停抓宠时头上一个小精灵球：抓过的是原版彩色球（icon_owned），没抓过的是灰色球（用户 2026-10-19）
    if e.node.has_method("set_owned_icon"):
        var owned := points_wallet != null and points_wallet.is_species_unlocked(sid)
        var uncaught := _is_uncaught(sid)
        e.node.call("set_owned_icon", capture_pause_mode and wild and (owned or uncaught), owned)
    # 稀有（普通）出生就弹一次；闪光 / 神兽等它进入视野时一起提示（见 _special_tick）。
    if rare and announce and not e.shiny and not rare_announced.has(sid):
        rare_announced[sid] = true
        if hud != null:
            hud.show_banner("稀有宠物出现了：%s（Esc 暂停去抓）" % str(e.t.get("name", "")))
        _tip_catch()


# 场上的稀有 / 神兽 / 闪光汇总（右侧列表用）：[{text, color, count}]，同名同标记合并，神兽 > 闪光 > 稀有排序，最多 NOTABLE_MAX_ROWS 行。
const NOTABLE_MAX_ROWS := 6
var _notable_clock := 0.0


func _notable_summary() -> Array:
    var groups := {}
    for e in enemies:
        if e.dying >= 0.0 or e.node == null or not is_instance_valid(e.node):
            continue
        var sid := int(e.t.get("species_id", -1))
        var wild := bool(e.t.get("wild", false))
        var names: Array = []
        var rank := 9
        var color := MARKER_RARE_COLOR
        if e.legendary:
            names.append("神兽")
            rank = 0
            color = MARKER_LEGEND_COLOR
        if e.shiny:
            names.append(SHINY_TIER_NAME[e.shiny_variant])
            if rank > 1:
                rank = 1
                color = SHINY_TIER_COLOR[e.shiny_variant]
        if wild and _is_rare_enemy(e):
            names.append("稀有")
            if rank > 2:
                rank = 2
                color = MARKER_RARE_COLOR
        if names.is_empty():
            continue
        var text := "%s（%s）" % [str(e.t.get("name", "")), "·".join(names)]
        if groups.has(text):
            groups[text]["count"] = int(groups[text]["count"]) + 1
        else:
            groups[text] = {"text": text, "color": color, "count": 1, "rank": rank}
    var rows: Array = groups.values()
    rows.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]) or (int(a["rank"]) == int(b["rank"]) and str(a["text"]) < str(b["text"])))
    var out: Array = []
    for r: Dictionary in rows:
        if out.size() >= NOTABLE_MAX_ROWS:
            break
        out.append({"text": r["text"], "color": r["color"], "count": r["count"]})
    return out


func _notables_tick(delta: float) -> void:
    _notable_clock -= delta
    if _notable_clock > 0.0:
        return
    _notable_clock = 0.3
    if hud != null and hud.has_method("set_notables"):
        hud.set_notables(_notable_summary())


func _refresh_rare_markers() -> void:
    for e in enemies:
        if e.dying < 0.0:
            _mark_special(e, false)


# 闪光 / 神兽每帧：推进特效；第一次进入视野（ALERT_DISTANCE）响提示音 + 弹一条横幅。
func _special_tick(e: Enemy, dist: float, delta: float) -> void:
    e.special_t += delta
    if e.sparkle != null:
        EnemySpecial.update_sparkle(e.sparkle, e.special_t)
    if e.special_alerted or dist > EnemySpecial.ALERT_DISTANCE:
        return
    e.special_alerted = true
    var nm := str(e.t.get("name", ""))
    _tip_catch()
    if e.shiny:
        _play_special_sound(EnemySpecial.SOUND_SHINY)
        if hud != null:
            hud.show_banner("闪光宠物出现了：%s（Esc 暂停去抓）" % nm)
    elif e.legendary:
        _play_special_sound(EnemySpecial.SOUND_LEGEND)
        if hud != null:
            hud.show_banner("神兽出现了：%s（Esc 暂停去抓）" % nm)
    if e.shiny and e.legendary:
        _play_special_sound(EnemySpecial.SOUND_LEGEND)   # 又闪又神：两个提示音都响


func _play_special_sound(path: String) -> void:
    special_sound_log.append(path)
    if sfx != null and "enabled" in sfx and not bool(sfx.enabled):
        return
    if not ResourceLoader.exists(path):
        return
    var stream := load(path) as AudioStream
    if stream == null:
        return
    var pl := AudioStreamPlayer.new()
    pl.stream = stream
    pl.volume_db = 2.0
    pl.bus = &"Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else &"Master"
    add_child(pl)
    pl.finished.connect(pl.queue_free)
    pl.play()


# 换图缓坡（用户 2026-10-24：“可以低几级”）：撤离到新地区后前 MAP_GRACE_SECS 秒，敌人等级先低 MAP_GRACE_LEVELS 级、
func _map_grace_wave(w: int) -> int:
    if map_time_start <= 0.0 or MAP_GRACE_SECS <= 0.0 or not battle_wave_scaling:
        return w
    var since := time - map_time_start
    if since >= MAP_GRACE_SECS:
        return w
    var lv := 1.0 + float(w) / 2.0 + pow(float(w) / 25.0, 2.0)   # 原等级公式 n = 1 + w/2 + (w/25)²
    var grace := MAP_GRACE_LEVELS * (1.0 - since / MAP_GRACE_SECS)
    return mini(w, preload("res://data/biomes.gd").wave_for_level(maxf(1.0, lv - grace)))


func _update_enemies(delta: float) -> void:
    var grid := {}
    for e in enemies:
        if e.dying < 0.0:
            var key := Vector2i(floori(e.node.position.x / 1.2), floori(e.node.position.z / 1.2))
            if not grid.has(key):
                grid[key] = []
            grid[key].append(e)
    for i in range(enemies.size() - 1, -1, -1):
        var e := enemies[i]
        if e.dying >= 0.0:
            if e.squad_ring != null:
                e.squad_ring.queue_free()   # 点着了但先被打死：红圈收掉
                e.squad_ring = null
            e.dying += delta
            e.node.scale = Vector3.ONE * float(e.t["scale"]) * maxf(0.05, 1.0 - e.dying / 0.45)
            if e.dying >= 0.45:
                e.node.queue_free()
                enemies.remove_at(i)
            continue
        # 每个敌人各自走自己的状态秒；DoT / 混乱自伤可能当帧致死，先按死亡路径收掉。
        _enemy_status_tick(e, delta)
        if e.dying >= 0.0:
            continue
        if bool(e.t.get("squad", false)) and _squad_enemy_tick(e, delta):
            continue   # 自爆小队点着了：原地闪、到点爆炸，不走不打
        var pos := e.node.position
        var off := player.position - pos
        off.y = 0
        var dist := off.length()
        if e.shiny or e.legendary:
            _special_tick(e, dist, delta)
        var dir := off / dist if dist > 0.001 else Vector3.ZERO
        var radius := float(e.t["radius"])
        # 速度：原作能力等级（吐丝）先作用在米/秒上，再按「原 SPD 有/无麻痹的比值」缩放。
        # 麻痹不对米/秒做 bitshift；吐丝阶段与麻痹按源顺序组合（阶段同时进比值）。
        # 移动速度：原米/秒 × 速度倍率（速度六维系数 × 能力等级倍率，game/pokemon_speed.gd）；
        # 变快时不超过原上限（WILD_SPEED_CAP 与原本的速度取大者），变慢不设下限之外的额外规则。
        var base_speed := float(e.t["speed"]) * e.speed_mult
        var speed := base_speed * _enemy_speed_multiplier(e)
        if speed > base_speed:
            speed = minf(speed, maxf(base_speed, Roster.WILD_SPEED_CAP))
        speed = _paralyzed_move_speed(speed, e.status, float(e.t["stats"][5]), e.speed_stage)
        if e.slow_left > 0.0:
            var slowed_time := minf(delta, e.slow_left)
            e.slow_left = maxf(0.0, e.slow_left - delta)
            speed *= 1.0 - e.slow * slowed_time / maxf(0.0001, delta)
        e.attack_cd = maxf(0.0, e.attack_cd - delta)
        # 畏缩：1 秒内向反方向跑开、不攻击（取消正在挥的一击）。
        var fleeing := e.flee_until > run_clock
        if fleeing:
            e.atk_left = 0.0
            e.hit_in = -1.0
        if e.atk_left > 0.0:
            e.atk_left -= delta
            if e.hit_in > 0.0:
                e.hit_in -= delta
                if e.hit_in <= 0.0 and dist <= radius + 0.65 * enemy_range_scale and stress == 0:
                    if not _unit_can_act(e):
                        # 近身动作途中被附加睡眠 / 冰冻，或当秒判定缓存说不能出招：
                        # 取消这次挥击，不留下先前 hit_in 造成「睡着仍打人」。
                        e.atk_left = 0.0
                        e.hit_in = -1.0
                        e.ap.play("move")
                    else:
                        # 真实落击点：先按该敌人自己的 ACC 阶段与玩家 EVA 0，用原 Tackle accuracy
                        # 与原阶段比例独立掷一次命中骰（纯层 game/pokemon_accuracy.gd）。
                        # 未命中：不调用伤害 / 暴击骰 / `_hurt`，不改 HP / 护盾 / 受伤音效；
                        # 攻击动作与 1.2 秒现冷却照常消耗（开始挥击时已写 attack_cd，不在这里回退）。
                        # 命中：仍走唯一原伤害公式 `_enemy_move_damage` -> `_hurt`。
                        # 只在落击这一次掷；开始挥击（hit_in = 0.2）时不掷。
                        if _enemy_move_hits(e):
                            _hurt(_enemy_move_damage(e), e)
                            if player_hp <= 0.0:
                                break   # 玩家当帧被这一下打死：后续敌人攻击 / 自动招不再执行
            if e.atk_left <= 0.0:
                e.ap.play("move")
        elif fleeing:
            if not _status_stops_move(e) and not _trap_holds(e):
                pos -= dir * speed * delta
        elif dist <= radius + 0.55 * enemy_range_scale and e.attack_cd <= 0.0 and stress == 0:
            if _unit_can_act(e):
                e.cur_move = _enemy_pick_move(e)   # 这一次挥击用哪一招
                if e.cur_move == "":
                    e.cur_move = str(e.melee_moves[0])   # 近身招全被定身法封住：这次不挥
                    e.attack_cd = 1.2
                else:
                    e.last_move = e.cur_move
                    e.ap.play("attack")
                    e.atk_left = 0.45
                    e.hit_in = 0.2
                    e.attack_cd = 1.2 * _ab_pressure_factor()   # 玩家的压迫感：敌人出手间隔变长
            else:
                # 被挡：已就绪的近身尝试也消耗原冷却，不每帧空重试（与玩家出招同一条规则）。
                e.attack_cd = 1.2
        elif dist > radius + 0.45:
            # 睡眠 / 冰冻停止主动移动（麻痹只按原 SPD 缩放，当秒不能出招也不乱走）。
            if not _status_stops_move(e) and not _trap_holds(e):
                pos += dir * speed * delta
        _enemy_shoot_tick(e, dist, radius, fleeing, delta)
        pos += e.kb * delta
        e.kb = e.kb.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
        var cx := floori(pos.x / 1.2)
        var cz := floori(pos.z / 1.2)
        for dx in range(-2, 3):
            for dz in range(-2, 3):
                for other: Enemy in grid.get(Vector2i(cx + dx, cz + dz), []):
                    if other == e:
                        continue
                    var apart := pos - other.node.position
                    var minimum := radius + float(other.t["radius"])
                    var d2 := apart.length_squared()
                    if d2 < minimum * minimum:
                        var normal := apart.normalized() if d2 > 0.0001 else Vector3.RIGHT
                        pos += normal * (minimum - sqrt(d2)) * 0.5
        pos = scenery.push_out(pos, radius * 0.6)
        pos.y = 0
        e.node.position = pos
        e.node.set_world_facing(dir, cam)
        e.pulse = maxf(0.0, e.pulse - delta * 7.0)
        var pulse := sin(e.pulse * PI) * 0.14
        var base := float(e.t["scale"])
        e.node.scale = Vector3(base * (1.0 + pulse), base * (1.0 - pulse), base * (1.0 + pulse))

var potion_body: SphereMesh
var potion_neck: CylinderMesh
var potion_mat: StandardMaterial3D


func _drop_potion(pos: Vector3) -> void:
    if potion_body == null:
        potion_body = SphereMesh.new()
        potion_body.radius = 0.22
        potion_body.height = 0.44
        potion_neck = CylinderMesh.new()
        potion_neck.top_radius = 0.07
        potion_neck.bottom_radius = 0.09
        potion_neck.height = 0.18
        potion_mat = StandardMaterial3D.new()
        potion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        potion_mat.albedo_color = Color(0.95, 0.2, 0.2)
    var root := Node3D.new()
    var body := MeshInstance3D.new()
    body.mesh = potion_body
    body.material_override = potion_mat
    body.position = Vector3(0, 0.3, 0)
    root.add_child(body)
    var neck := MeshInstance3D.new()
    neck.mesh = potion_neck
    neck.material_override = potion_mat
    neck.position = Vector3(0, 0.58, 0)
    root.add_child(neck)
    if ResourceLoader.exists("res://ui/icons/hp.png"):
        var icon := Sprite3D.new()
        icon.texture = load("res://ui/icons/hp.png")
        icon.pixel_size = 0.004
        icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        icon.no_depth_test = true
        icon.position = Vector3(0, 1.05, 0)
        root.add_child(icon)
    root.position = Vector3(pos.x, 0, pos.z)
    add_child(root)
    potions.append(root)


func _update_potions() -> void:
    var i := potions.size() - 1
    while i >= 0:
        var pt := potions[i]
        pt.get_child(0).position.y = 0.3 + sin(time * 3.0 + i) * 0.06
        var off := player.position - pt.position
        off.y = 0
        if off.length_squared() < 0.8 * 0.8:
            # 旧掉落药基值 / 掉落率都不动：仍是 maxHP * POTION_HEAL 的 float。回血统一走
            # combat.heal 的「一般治疗」入口——有治愈护符时按原一般 HealPhase 取整加成，
            # 没护符时保持本作旧 float 行为；商店伤药不走这里（已按原固定 / 百分比分支算好）。
            var amt := stats.value("hp_max") * POTION_HEAL
            heal(amt)
            sfx.pickup()
            pt.queue_free()
            potions.remove_at(i)
        i -= 1


func _update_gems(delta: float) -> void:
    _update_potions()
    _update_nuggets()
    var p := player.position + Vector3(0, 0.3, 0)
    var magnet := _magnet_radius()   # 基础吸附距离 × 速度系数
    var i := gems.size() - 1
    while i >= 0:
        var g := gems[i]
        var d := p - g.position
        var dist := d.length()
        if dist < 0.6:
            var gained_xp := float(g.get_meta("xp"))
            sfx.pickup()
            g.queue_free()
            gems.remove_at(i)
            _gain_xp(gained_xp * kill_xp_scale)   # 球内是基础击倒值；先乘击杀经验系数，本次唯一全局经验护符加成在 _gain_xp 入口应用
        elif dist < magnet:
            g.position += d / dist * 14.0 * delta
        i -= 1


# ================= 自爆小队（用户 2026-10-25：“可以有个自爆小队这种设定”“弄个开关，感觉有这个会很折磨”）=================
# 设置里打开才有（默认关）。在一个地区待满 2 分钟后，每 2 分半从一个方向冲来一队（6 只）会自爆的宝可梦，
# 跑得比普通野怪快；离你 2.2 米内就停下、地上亮红圈，1 秒后自爆：红圈里的你吃一发大爆炸 / 自爆（按原伤害公式 × 0.4），它自己倒下。
# 先打死就不会爆。
const SQUAD_SPECIES := [100, 101, 109, 110, 74, 75]   # 霹雳电球 / 顽皮雷弹 / 瓦斯弹 / 双弹瓦斯 / 小拳石 / 隆隆石
const SQUAD_EXPLOSION := [101, 110, 75]                # 这几只用大爆炸（威力 250），其余用自爆（200）
const SQUAD_FIRST := 120.0
const SQUAD_EVERY := 150.0
const SQUAD_SIZE := 6
const SQUAD_SPEED := 1.6
const SQUAD_TRIGGER := 2.2
const SQUAD_FUSE := 1.0
const SQUAD_BLAST := 2.8
const SQUAD_DMG := 0.4
var _squad_next := -1.0
var _squad_map_start := -999.0
var _squad_last_time := 0.0


func _squad_tick(battle_wave: int) -> void:
    if not squad_on or tutorial_mode or not started or wild == null:
        return
    # 换了地区 / 开了新局：重新从 2 分钟算
    if map_time_start != _squad_map_start or time < _squad_last_time - 1.0:
        _squad_map_start = map_time_start
        _squad_next = SQUAD_FIRST
    _squad_last_time = time
    var mt := time - map_time_start
    if mt < _squad_next:
        return
    _squad_next = mt + SQUAD_EVERY
    _spawn_squad(battle_wave)


func _spawn_squad(battle_wave: int) -> void:
    var pool: Array = []
    for sid in SQUAD_SPECIES:
        if WildSpecies.has_species(int(sid)):
            pool.append(int(sid))
    if pool.is_empty():
        return
    var lv := int(wild.roll_encounter(battle_wave).get("level", level))
    var species: int = pool[randi() % pool.size()]
    var t: Dictionary = Roster.wild_enemy(species, 0, maxi(1, lv), SQUAD_SPEED).duplicate()
    t["squad"] = true
    var base_ang := _spawn_angle()
    for k in SQUAD_SIZE:
        var j := randf() * TAU
        var off := Vector3(cos(base_ang), 0, sin(base_ang)) * SPAWN_RADIUS + Vector3(cos(j), 0, sin(j)) * randf() * 2.5
        spawn_queue.append([t.duplicate(), off])
    if hud != null:
        hud.show_banner("自爆小队来了！看到红圈快跑")


# 每帧：没点着就照常走（返回 false）；点着了就原地闪、到点爆（返回 true，跳过普通移动 / 攻击）。
func _squad_enemy_tick(e: Enemy, delta: float) -> bool:
    var off := player.position - e.node.position
    off.y = 0
    var dist := off.length()
    if e.squad_fuse < 0.0:
        if dist <= SQUAD_TRIGGER and _unit_can_act(e):
            e.squad_fuse = 0.0
            e.squad_ring = _squad_ring(e)
        return false
    e.squad_fuse += delta
    var k := clampf(e.squad_fuse / SQUAD_FUSE, 0.0, 1.0)
    var base := float(e.t["scale"])
    e.node.scale = Vector3.ONE * base * (1.0 + 0.12 * absf(sin(e.squad_fuse * (10.0 + 20.0 * k))))
    if e.squad_ring != null:
        (e.squad_ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.15, 0.1, 0.18 + 0.32 * k)
    if e.squad_fuse >= SQUAD_FUSE:
        _squad_blast(e, dist)
    return true


func _squad_ring(e: Enemy) -> MeshInstance3D:
    var ring := MeshInstance3D.new()
    var m := CylinderMesh.new()
    m.top_radius = SQUAD_BLAST
    m.bottom_radius = SQUAD_BLAST
    m.height = 0.03
    m.radial_segments = 40
    ring.mesh = m
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(1.0, 0.15, 0.1, 0.18)
    ring.material_override = mat
    ring.top_level = true   # 不跟着怪一起缩放；怪没了它也跟着没
    e.node.add_child(ring)
    ring.global_position = Vector3(e.node.position.x, 0.05, e.node.position.z)
    return ring


func _squad_blast(e: Enemy, dist: float) -> void:
    if e.squad_ring != null:
        e.squad_ring.queue_free()
        e.squad_ring = null
    if dist <= SQUAD_BLAST and player_hp > 0.0 and not dead:
        var keep := e.cur_move
        e.cur_move = "explosion" if SQUAD_EXPLOSION.has(int(e.t.get("species_id", 0))) else "self_destruct"
        var dmg := _enemy_move_damage(e) * SQUAD_DMG
        e.cur_move = keep
        _hurt(dmg, e)
    _kill(e)

