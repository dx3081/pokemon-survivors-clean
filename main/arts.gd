extends "res://main/combat.gd"
# 招式槽（active_moves）开局为原表 1 级两招（撞击 / 吐丝），各 1 级；这里的数值是本作战斗规则，
# 不是原作回合制威力。9 级虫咬 / 进化招由 main/combat.gd 的学习事件加入。学习 / 替换只换招式 id，
# 仍固定 Lv1；原 Rogue 特效播放器 rogue_moves.gd 不改。
#
# 本轮（招式数据）：命中按原作 randSeedInt(100,1) <= accuracy 掷 1..100 整数骰；
# 撞击 / 虫咬 / 起风 / 抓 / 拍击 / 啄 / 电光一闪 / 电击只打最近一个活敌人且无击退；吐丝打范围内一圈活敌人、
# 每目标独立判命中并降速度等级 2；瞪眼 / 摇尾巴打范围内一圈、每目标独立判命中并降**目标**防御等级 1（0 伤害）。
# 后续“学招前置”补了变硬 / 起风：变硬是自己使用的变化招（不掷命中骰、给玩家临时防御等级 +1、
# 0 直接伤害）；起风是飞行特殊招，走 SPATK/SPDEF 原公式。
# 原作 power / accuracy / pp / target / 效果来源见 data/POKEMON_MOVES_SOURCE.md；
# 伤害已接原作公式（game/pokemon_damage.gd），cd / range 仍是本作实时值，速度决定冷却留后续迁移。
const STAT_STAGE_MIN := -6
const PokemonPP := preload("res://game/pokemon_pp.gd")
const STAT_STAGE_MAX := 6
# 原作命中 / 闪避阶段比例纯层（ACC/EVA 先合并再钳 6、3 基数）。敌人近身撞击的命中判定走它，
# 不改玩家命中骰现有口径（玩家侧仍是无阶段修正的 `_accuracy` / `_hit`）。
const PokemonAccuracy := preload("res://game/pokemon_accuracy.gd")
# 玩家当前没有 EVA（闪避）能力阶段系统，恒 0；只作事实占位，不搬玩家命中 / 闪避系统。
const PLAYER_EVA_STAGE := 0
# 招式计时 / 计数声明在 main/state.gd（基类）：combat.gd 的异常阻断分支也要读写它们。
# 兼容占位：旧吐丝飞行丝弹已按本项删掉（改用原群体效果），字段保留空数组免得其他清理路径报错。
var silk_bolts: Array[Dictionary] = []
const PokemonRecoil := preload("res://game/pokemon_recoil.gd")
const RogueFX := preload("res://fx/rogue_moves.gd")
var rogue_fx: RogueFX = null
const PackFX := preload("res://fx/pack_fx.gd")
var pack_fx: PackFX = null

# 懒创建一个独立的 Rogue 原特效播放子节点；不碰 main.gd、ui、data。
func _rogue() -> RogueFX:
    if rogue_fx == null or not is_instance_valid(rogue_fx):
        rogue_fx = RogueFX.new()
        rogue_fx.setup(cam)
        add_child(rogue_fx)
    return rogue_fx

# 新派特效包播放子节点（懒创建，跟 _rogue() 一样）。
func _pack() -> PackFX:
    if pack_fx == null or not is_instance_valid(pack_fx):
        pack_fx = PackFX.new()
        pack_fx.setup(_rogue())
        add_child(pack_fx)
    return pack_fx

# 按 active_moves 重建计时 / 计数键，保留已存在招式的进度；换招后不残留旧键。
func _sync_move_slots() -> void:
    var timers := {}
    var casts := {}
    for id: String in active_moves:
        if not MOVES.is_implemented(id):
            continue
        timers[id] = float(move_timer.get(id, 0.0))
        casts[id] = int(move_casts.get(id, 0))
    move_timer = timers
    move_casts = casts

# 招式槽变化后统一刷新：arts 计时键 + HUD 技能栏。move_lv 仍固定 1。
func _refresh_moves() -> void:
    _sync_move_slots()
    _show_moves()
    # 学过的招记到这一系名下：以后在选宠页就能给它买 PP 提升剂（用户 2026-10-20；不改开局能选哪些招）
    # 开局招 / 买过的技能机器本来就会列出，不用记（这样出发时不写存档）
    if points_wallet != null and not player_is_ditto and points_wallet.has_method("note_moves_learned"):
        var known: Array = _starter_pool(run_starter_id) + _owned_tms(run_starter_id)
        var fresh: Array = []
        for mid: String in active_moves:
            if not known.has(mid) and not points_wallet.moves_learned_for(player_species_id).has(mid):
                fresh.append(mid)
        if not fresh.is_empty():
            points_wallet.note_moves_learned(player_species_id, fresh)

# 旧升级卡卡面兼容占位（main/cards.gd 的旧选卡代码会引用本函数；Cards.CARDS_ENABLED=false 时
# 从不执行）。伤害已改走 game/pokemon_damage.gd 的原公式，不再由“本作基础伤害 × ATK 比例”
# 得到；本函数不参与生产伤害路径，只为旧卡面代码解析通过而保留。
func _dmg(_id: String) -> float:
    return 0.0

# 攻击距离上限（用户 2026-10-17：截图里围着主角画了个圈，“攻击距离最高就是这个大”；原 8 米会打到屏幕外没看见的宠物）。
# 圈半径按相机（fov 45、高 12 / 后 8）换算约 4 米；所有玩家招式的射程一律不超过它（含升级加成），敌人的弹药射程和飞行距离同口径。
const MAX_ATTACK_RANGE := 4.0
func _range(id: String) -> float:
    return minf(float(MOVES.MOVES[id]["range"]) + 0.12 * (int(move_lv.get(id, 1)) - 1), MAX_ATTACK_RANGE) * attack_range_scale


# 不打单个目标的招（场地 / 范围 / 自身触发）用的距离：一律是标准攻击圈（最远 4 米 × 设置里的攻击距离），
# 不再各写各的（用户 2026-10-22：“距离要是一个标准，不论任何技能”；原来终焉之歌写死 8 米、撒菱 4 米、守住 5 米）。
func _std_range() -> float:
    return MAX_ATTACK_RANGE * attack_range_scale

# 回血招（自我再生 / 羽栖 / 光合作用这类“回自己最大 HP 的一部分”）太强（用户 2026-10-18：“回血技能太变态了，加冷却时间”）：
# 冷却至少 HEAL_MOVE_MIN_CD 秒，不吃出招速度加成。
const MoveRoles := preload("res://game/pokemon_move_roles.gd")
const HEAL_MOVE_MIN_CD := 20.0


func _is_self_heal_move(id: String) -> bool:
    for eff: Dictionary in MOVES.MOVES[id].get("effects", []):
        if str(eff.get("kind", "")) == "heal" and str(eff.get("who", "self")) == "self":
            return true
        # 换了名字的回自己血招也算（2026-10-22 审查：睡觉 10 秒回满、祈愿 6 秒、吞下 2.4 秒都绕过了 20 秒下限）
        if str(eff.get("kind", "")) in ["rest", "wish", "swallow", "strength_sap"]:
            return true
    return false


# 强化自己的招：变化招、所有效果都是“自己的能力等级”（剑舞 / 高速移动 / 龙之舞 / 破壳…）。
func _is_self_buff_move(id: String) -> bool:
    return MoveRoles.is_self_buff(id)   # 规则在 game/pokemon_move_roles.gd，说明文字也用它


# 血量门槛自动触发的回血招（自我再生 / 羽栖 / 生蛋 / 光合作用 / 睡觉…）；祈愿 / 吞下 / 吸取力量流程特殊，不算。
func _heal_gate_of(id: String) -> float:
    return MoveRoles.heal_gate(id, heal_gate_ratio)


# 光环：变化招、所有效果都是“降别人的能力等级”（瞪眼 / 摇尾巴 / 叫声 / 刺耳声 / 吐丝 / 可怕面孔…）。
func _is_aura_move(id: String) -> bool:
    return MoveRoles.is_aura(id)


func _is_screen_move(id: String) -> bool:
    return MoveRoles.is_screen(id)


# 常驻护盾：带着（没关掉）的反射壁 / 光墙 / 极光幕。kind = "physical" / "special"。
func _passive_screen_mult(kind: String) -> float:
    if not screens_passive:
        return 1.0
    var m := 1.0
    for id: String in active_moves:
        if disabled_moves.has(id) or not _is_screen_move(id):
            continue
        for eff: Dictionary in MOVES.MOVES[id].get("effects", []):
            if str(eff.get("kind", "")) != "screen":
                continue
            var which := str(eff.get("screen", ""))
            if which == "both":
                m = minf(m, MoveRoles.VEIL_MULT)
            elif which == kind:
                m = minf(m, MoveRoles.SCREEN_MULT)
    return m


# 光环：每 AURA_TICK 秒查一次，标准攻击圈里的怪对每个光环招各降一次（走原来的降能力函数，特性挡得住的照样挡）。
func _aura_tick(delta: float) -> void:
    if not aura_on:
        return
    _aura_clock += delta
    if _aura_clock < AURA_TICK:
        return
    _aura_clock = 0.0
    var auras: Array = []
    for id: String in active_moves:
        if not disabled_moves.has(id) and MOVES.is_implemented(id) and _is_aura_move(id):
            auras.append(id)
    if auras.is_empty():
        return
    var r := float(call("_std_range"))
    for e in _near_enemies(r):
        if e.dying >= 0.0:
            continue
        for id in auras:
            if e.aura_hit.has(id):
                continue
            e.aura_hit[id] = true
            if MoveRoles.is_expose_aura(id):
                e.exposed_ghost = true
                e.exposed_until = 1.0e12   # 识破光环：一直被识破
                continue
            for eff: Dictionary in MOVES.MOVES[id].get("effects", []):
                _generic_stat_change(false, e, _norm_stat(str(eff["stat"])), int(eff["stages"]))


func _is_field_move(id: String) -> bool:
    return MoveRoles.is_field(id)


func _cd(id: String) -> float:
    # PP 越低冷却越长（用户 2026-10-20），PP 提升剂按招带在 run_held 里；规则 game/pokemon_pp.gd
    var base_cd := PokemonPP.move_cd(id, int(run_held.get(HeldItems.pp_up_item(id), 0)))
    var cd := maxf(0.35, base_cd / maxf(0.1, stats.value("aspd")))
    if _is_self_heal_move(id) or id == "perish_song":
        cd = maxf(cd, HEAL_MOVE_MIN_CD)   # 终焉之歌（范围内普通怪必死）也吃 20 秒下限（用户 2026-10-22）
    if heal_gate_ratio > 0.0 and (_heal_gate_of(id) > 0.0 or MoveRoles.is_guard(id) or MoveRoles.is_cure(id)):
        cd = maxf(cd, HEAL_AUTO_CD)   # 回血 / 防守救急 / 解异常：触发后冷却 40 秒   # 血低才自动放的回血招：触发后冷却 40 秒（像树果，用户 2026-10-24）
    if field_cd_on and _is_field_move(id):
        cd = maxf(cd, FIELD_MOVE_MIN_CD)   # 天气 / 场地：持续 20 秒、冷却 40 秒
    return cd * attack_cd_scale   # 设置里的“攻击冷却”系数乘在所有玩家招式的冷却上（用户 2026-10-18：找个舒服的数值）

# 原作命中判定：无天气 / 特性 / 命中闪避修正时 randSeedInt(100,1) <= accuracy。
# 测试子类可覆写本函数注入确定骰值；生产路径没有作弊开关。
func _accuracy_roll(_id: String) -> int:
    return randi_range(1, 100)

func _accuracy(id: String) -> int:
    # 剧毒（原 ToxicAccuracyAttr）：出招者是毒属性时必中。
    if bool(MOVES.MOVES[id].get("poison_sure", false)) and _player_types().has("毒"):
        return -1
    # 打雷 / 暴风：雨天必中、晴天 50；暴风雪：雪天必中。
    var wa := str(MOVES.MOVES[id].get("weather_acc", ""))
    if wa == "thunder":
        if weather == "rain":
            return -1
        if weather == "sun":
            return 50
    elif wa == "blizzard" and weather == "snow":
        return -1
    return int(MOVES.MOVES[id]["accuracy"])

# 特性对命中的修正：攻方复眼 ×1.3；守方雪隐（下雪）/ 蹒跚（混乱）让命中变低。attacker / defender 为 null = 玩家。
func _ab_adjust_accuracy(acc: int, attacker, defender) -> int:
    if acc <= 0 or acc >= 101:
        return acc
    var f := 1.0
    for key in _ab_keys(attacker):
        f *= AB.accuracy_mult(str(key))
    var confused: bool = _actor_status(defender).has_confusion() if _actor_status(defender) != null else false
    for key in _ab_keys(defender):
        f /= AB.evade_divisor(str(key), weather, confused)
    return clampi(int(round(float(acc) * f)), 1, 100) if f != 1.0 else acc


func _ab_crit_bonus(unit) -> int:
    var n := 0
    for key in _ab_keys(unit):
        n += AB.crit_stage_bonus(str(key))
    return n


func _hit(id: String, e = null) -> bool:
    if player_lock_on and int(MOVES.MOVES[id]["target"]) != 0:
        player_lock_on = false   # 锁定：下一次出招必中，用掉就清
        return true
    var acc := _accuracy(id)
    if acc < 0:
        return true   # 原作命中 -1 = 必中（影子拳等），不掷骰，也不受速度影响
    var mult := 1.0 if e == null else _speed_hit_multiplier(e)
    acc = _ab_adjust_accuracy(acc, null, e)   # 特性：复眼 / 对手的雪隐·蹒跚
    acc += 5 * int(run_held.get("WIDE_LENS", 0))   # 携带道具·广角镜：原版命中 +5 / 个
    if weather == "fog":
        acc = int(floorf(acc * 0.9))   # 起雾：原版命中 ×0.9（PokéRogue 自己的数）
    if run_clock < gravity_until:
        acc = int(floorf(acc * 5.0 / 3.0))   # 重力：原版命中 ×1.67
    var eva: int = e.eva_stage if e != null else 0
    if player_acc_stage == 0 and eva == 0 and mult == 1.0:
        return _accuracy_roll(id) <= acc
    # 玩家 ACC 能力等级（磨爪等）：原 hitCheck 的 3 基数阶段倍率；守方 EVA = 敌人的闪避等级（甜甜香气等会降它）；再乘速度命中倍率，上限 100。
    return PokemonSpeed.hits(acc, player_acc_stage, eva, mult, _accuracy_roll(id))


# 速度的命中 / 闪避倍率：玩家出招 = clamp((玩家速度 ÷ 目标速度)^0.25, 0.85, 1.15)。测试子类可覆写成 1.0。
func _speed_hit_multiplier(e: Enemy) -> float:
    return PokemonSpeed.hit_multiplier(_player_effective_speed(), _enemy_effective_speed(e))


# 敌人出招：clamp((敌人速度 ÷ 玩家速度)^0.25, 0.85, 1.15)。测试子类可覆写成 1.0。
func _enemy_speed_hit_multiplier(e: Enemy) -> float:
    return PokemonSpeed.hit_multiplier(_enemy_effective_speed(e), _player_effective_speed())


# 敌人命中骰：生产就是原 1..100 整数骰；测试子类可覆写本函数注入确定值。
# 不能借用玩家侧的 `_accuracy_roll` / `forced_roll`：旧「玩家失误 101」夹具只针对玩家出招，
# 不能让敌人命中判定跟着玩家测试骰走（生产路径没有作弊开关）。
func _enemy_accuracy_roll(_e: Enemy) -> int:
    return randi_range(1, 100)


# 敌人近身撞击的一次命中判定：原 Tackle accuracy（100）× 原 ACC/EVA 阶段比例。
# 先合并「攻方 ACC - 守方 EVA」再钳 [-6,6]（纯层 game/pokemon_accuracy.gd），不是两个倍率相乘；
# 攻击方 ACC 用该敌人自己的 `e.acc_stage`；防守方玩家当前 EVA 恒 0（本作没有玩家闪避系统）。
func _enemy_move_hits(e: Enemy) -> bool:
    var base := _ab_adjust_accuracy(int(MOVES.MOVES[e.cur_move]["accuracy"]), e, null)
    if weather == "fog" and base > 0:
        base = int(floorf(base * 0.9))   # 起雾：敌人出招命中也 ×0.9
    if run_clock < gravity_until and base > 0:
        base = int(floorf(base * 5.0 / 3.0))   # 重力：原版命中 ×1.67
    return PokemonSpeed.hits(base, e.acc_stage, player_eva_stage, _enemy_speed_hit_multiplier(e), _enemy_accuracy_roll(e))


func _nearest(radius: float) -> Enemy:
    var best: Enemy = null
    var dist := INF
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e):
            continue
        var d := player.position.distance_to(e.node.position)
        if d <= radius + float(e.t["radius"]) and d < dist:
            best = e
            dist = d
    return best

# 「活目标」定义与捕获圈一致：未进入死亡（dying < 0）且真实 HP > 0。
# 0 血但还没标 dying 的构造态不算有效目标，不选为单体目标、也不进群体范围。
func _is_live_target(e: Enemy) -> bool:
    if e == null or not is_finite(e.hp):
        return false
    return e.hp > 0.0

# 吐丝 = 原作 ALL_NEAR_ENEMIES：范围内一圈活敌人；出招时定目标，之后每目标独立判定。
func _near_enemies(radius: float) -> Array[Enemy]:
    var out: Array[Enemy] = []
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e):
            continue
        if player.position.distance_to(e.node.position) <= radius + float(e.t["radius"]):
            out.append(e)
    return out

# 回合换秒适配：真正的单目标选择在「命中判定之前」定下来并全程复用。
# 不能先掷命中再 _nearest（会重新选一次最近目标），否则移动中的同一帧内可能打错人 /
# 命中一个目标却把状态挂在另一个目标上。返回 null 表示范围内没有活敌人。
func _single_target(id: String) -> Enemy:
    # 多重镜的“再来一次”：指定了目标就打它（见 _cast_move 的包装）；平时和以前一样打最近的，并记下是谁。
    if _forced_target != null and is_instance_valid(_forced_target.node) and _forced_target.dying < 0.0:
        return _forced_target
    var t := _nearest(_range(id))
    _lens_last_target = t
    return t


# ================= 五招原状态效果（字符串属性 → TypeChart 数字，不 int("火") 变 0）=================

# 招式对目标的免疫判定，照原 `Pokemon.apply`（偏移约 5439134）分两层：
#   1) **伤害属性 0 倍**：源式是
#        `d = new Kt(!A && (s!==Lt.STATUS || l.getAttrs(_O).find(R=>h.includes(R.immuneType)))
#              ? this.getAttackTypeEffectiveness(c,t) : 1)`
#      —— 只有「非变化招」，或带招式特设 `TypeImmunityAttr(_O)` 的变化招，才走属性克制表；
#      本作五招都不含 `_O`，所以**普通变化招不套伤害属性免疫**（超音波打幽灵不会被 0 倍挡掉）。
#   2) **招式自带 `isTypeImmune`**：`h.find(R=>l.isTypeImmune(R)) && (d.value=0)`；原
#      `isTypeImmune(t){switch(t){case S.GRASS: if(this.hasFlag(4096))return!0}return!1}`，
#      flag 4096 就是 `powderMove()`。所以本作只有「粉末招 + 草」这一条。
# 主要异常的毒/钢、电等免疫不在这里，仍在 `game/pokemon_status.gd::is_immune`。
func _move_type_immune(id: String, defender_types: Array, e = null) -> bool:
    if bool(MOVES.MOVES[id].get("powder", false)) and (defender_types.has("草") or (e != null and _ab_has(e, "OVERCOAT"))):
        return e == null or not _status_pierce(e)   # 穿透石板：草系 / 防尘也吃粉末招
    if str(MOVES.MOVES[id]["category"]) == "变化":
        return false
    var move_type := str(MOVES.MOVES[id]["type"])
    return _effectiveness(move_type, _exposed_types(move_type, defender_types, e)) == 0.0


# 气味侦测识破后：一般 / 格斗招打幽灵属性时把幽灵当作不存在（原 ExposedTag.ignoreImmunity），其余属性照常。
func _exposed_types(move_type: String, defender_types: Array, e) -> Array:
    if e != null and e.exposed_ghost and run_clock < e.exposed_until and (move_type == "一般" or move_type == "格斗") and defender_types.has("幽灵"):
        return defender_types.filter(func(t): return t != "幽灵")
    return defender_types


# 把 string 属性列表换成 core 要的数字列表。
func _status_types(defender_types: Array) -> Array:
    return _type_ids(defender_types)


# 命中后的状态附加：走 combat.gd 的真实 actor 入口（附加 + 起钟 + 标识 + 成功才播 common）。
# 命中骰已经掷过，不在这一层重掷；冷却由调用方统一消耗。返回结果码，便于检查与 UI 反馈。
func _apply_move_status(id: String, e: Enemy) -> String:
    if e == null or e.dying >= 0.0:
        return "invalid"
    var effect := int(MOVES.MOVES[id].get("effect", 0))
    if effect == PokemonStatus.NONE:
        return _actor_apply_confusion_status(e)
    return _actor_apply_major_status(e, effect)


# 变化招（变化 0 直接伤害）：命中 → 播原动画 → 附加状态 → 反馈。
# 未命中不播、不附加，但照样消耗已定冷却（由调用方统一处理）。
# 属性免疫 / 重复仍播原动画再报「没有效果」（原引擎也是先演出再报），但不扣血、不击退。
func _cast_status_move(id: String, e: Enemy) -> void:
    var name := str(MOVES.MOVES[id]["name"])
    if not _hit(id, e):
        return
    _play_move_fx(id, e)
    if _move_type_immune(id, _enemy_types(e), e):
        _show_status_feedback("%s 对%s没有效果" % [e.t["name"], name])
        return
    var result := _apply_move_status(id, e)
    _show_status_feedback(_status_feedback(str(e.t["name"]), name, result))


# 单体招式的原动画播放：user = 玩家、target = 该敌人。变化招没有直接伤害 /
# 没有击退，但仍然要放各自的原本体动画与音效（supersonic / 三粉各 25..29 帧）。
# 原 AnimTimedSoundEvent 空 resourceName 的音效依赖出招方物种（原 `n.user.cry(r)`），
# 所以把玩家当前准确物种 ID 一起传给播放器；旧 3/4 参调用仍走默认 0，不影响其它招。
func _play_move_fx(id: String, e: Enemy) -> void:
    if e == null or not is_instance_valid(e.node):
        return
    # 新派特效包接管的招式（fx/pack_fx.gd 的 RECIPES）：特效图层由它画，原播放器只留声音和身体动作。
    var power := float(MOVES.MOVES[id].get("power", 40)) if MOVES.MOVES.has(id) else 40.0
    var handled := _pack().play(id, player, e.node, maxf(power, 40.0))
    _rogue().play(id, player, e.node, true, player_species_id, not handled)


# 念力附加混乱的骰：源 randSeedInt(100) = 0..99，`< chance` 才附加。
# 测试子类可覆写本函数注入确定值；生产路径没有作弊开关。
func _confusion_roll() -> int:
    return randi_range(0, 99)


# 电击等招附加主要异常的概率骰：源 `StatusEffectAttr.apply` 的 `t.randSeedInt(100) < r.chance`，
# 即 0..99 的整数、严格小于 chance（chance 10 → 0..9 附加，9 中 10 不中）。
# 与念力的混乱骰分开：本骰只服务主要异常概率，且独立于命中 / 伤害 / 会心骰，每次释放至多掷一次。
# 测试子类可覆写本函数注入确定值；生产路径没有作弊开关。
func _major_status_roll() -> int:
    return randi_range(0, 99)


# 念力：先原特殊伤害，有效命中且目标仍活着才 randSeedInt(100) < 10 附加混乱（0..99 中 0..9）。
# 未命中不播；属性 0 倍免疫仍播原动画但不伤害、不附加；已死不附加。
# 命中骰只掷一次（与其它单体招共用同一次 _hit），不在这一层重掷。
func _cast_confusion_move(id: String, e: Enemy) -> void:
    var name := str(MOVES.MOVES[id]["name"])
    if not _hit(id, e):
        return
    var dir := (e.node.position - player.position).normalized()
    if dir.length_squared() < 0.001:
        dir = facing
    _play_move_fx(id, e)
    if _move_type_immune(id, _enemy_types(e), e):
        # 恶系对超能力 0 倍：演出照放，但不伤害、不附加混乱
        _show_status_feedback("%s 对%s没有效果" % [e.t["name"], name])
        return
    _damage(e, _player_move_damage(id, e), dir, 0.0, id)
    var chance := int(MOVES.MOVES[id].get("chance", -1))
    if chance <= 0 or e.dying >= 0.0:
        return
    if _confusion_roll() < chance:
        # 走真实 actor 入口：成功 onAdd 播一次 common-confusion；重复不播不刷新。
        var applied := _actor_apply_confusion_status(e)
        _show_status_feedback(_status_feedback(str(e.t["name"]), "混乱", applied))


# 电击：先原特殊伤害（唯一 SPATK/SPDEF 公式），有效命中且目标仍活着才 `randSeedInt(100) < chance`
# 附加主要异常（本站 chance 10 → 0..9）。未命中不播、不伤害、不附加；伤害属性 0 倍免疫（地面）
# 仍播原动画但不伤害、不附加，也不向远目标换靶；电属性目标照吃电伤害，但 state 层的麻痹免疫
# 拒绝附加；已有主要异常不覆盖不刷新、可与独立混乱共存；伤害致死不再给死者附加状态。
# 命中骰只掷一次（与其它单体招共用同一次 `_hit`），概率骰独立于命中 / 伤害 / 会心、每次至多一次。
func _cast_thunder_shock_move(id: String, e: Enemy) -> void:
    var name := str(MOVES.MOVES[id]["name"])
    if not _hit(id, e):
        return
    var dir := (e.node.position - player.position).normalized()
    if dir.length_squared() < 0.001:
        dir = facing
    _play_move_fx(id, e)
    if _move_type_immune(id, _enemy_types(e), e):
        # 地面免疫电伤害：演出照放，但不伤害、不附加麻痹。
        _show_status_feedback("%s 对%s没有效果" % [e.t["name"], name])
        return
    _damage(e, _player_move_damage(id, e), dir, 0.0, id)
    var chance := int(MOVES.MOVES[id].get("chance", -1))
    if chance <= 0 or e.dying >= 0.0:
        return
    if _major_status_roll() < chance:
        # 先掷概率、再走真实 actor 主要异常入口：已有主要异常 / 类型免疫不覆盖不刷新、不播 common。
        var applied := _apply_move_status(id, e)
        _show_status_feedback(_status_feedback(str(e.t["name"]), "麻痹", applied))


# 状态反馈走已验收的 HUD 横幅（用户能看懂的「附加 / 没有效果」）；HUD 不在时静默。
func _show_status_feedback(text: String) -> void:
    if hud != null and text != "":
        hud.show_banner(text)


# 通用状态发动动画接线（combat.gd 的强类型调用经 main/state.gd 占位到这里）。
# unit == null 表示玩家（挂在 `player` 根）；敌人挂各自 `e.node` 根。原 CommonBattleAnim 是
# 自我施受，所以 user = target = 该单位根节点；不画在攻击者或全局中心。
func _play_common_fx(common_id: String, unit) -> void:
    if common_id == "":
        return
    var node: Node3D = player if unit == null else unit.node
    if node == null or not is_instance_valid(node):
        return
    _rogue().play_common(common_id, node)


# 临时原招 / common 播放清理：取消 / 放弃 / 结算 / 场景退出都走这里（combat 的 `_cancel_events`）。
# 只清当前播放，不释放播放器节点；`_rogue()` 之后仍能按需重建，所以取消后继续战斗还能放招。
# 头目破段强化演出（fx/rogue_stat_change.gd）也在这里一起停图层与音频，重入无残留。
func _clear_status_fx() -> void:
    if rogue_fx != null and is_instance_valid(rogue_fx):
        rogue_fx.clear()
    if stat_fx != null and is_instance_valid(stat_fx):
        stat_fx.clear()


# 头目破段强化演出（原 StatChangePhase tileSprite + 角色 alpha 遮罩 + stat_up）。
# 与 moves / common 播放器分开，旧 43 份原 FX 与其播放器不改。
const StatChangeFX := preload("res://fx/rogue_stat_change.gd")
var stat_fx: StatChangeFX = null


func _stat_fx() -> StatChangeFX:
    if stat_fx == null or not is_instance_valid(stat_fx):
        stat_fx = StatChangeFX.new()
        stat_fx.setup(cam)
        add_child(stat_fx)
    return stat_fx


# 本批聚合后的 stats（单项播该项、多项 mix）挂到单位根：玩家 = `player`，敌人挂各自 `e.node`。
# owner_unit 传敌人对象以支持「死亡即停」；玩家传 null。
func _play_stat_change_fx(stat_ids: Array, unit) -> void:
    if stat_ids.is_empty():
        return
    var node: Node3D = player if unit == null else unit.node
    if node == null or not is_instance_valid(node):
        return
    _stat_fx().play(stat_ids, node, unit)



# ================= Rogue 原伤害公式接入（玩家与敌人共用）=================
# 公式 / 会心 / 能力等级在 game/pokemon_damage.gd；这里只负责取真实物种属性、本系、克制与掷骰。

# 攻击方物种的真实属性列表（本系按真实物种 types 算，不写死绿毛虫虫招）。
# 唯一委托 game/pokemon_starters.gd：图鉴内 / 1025 外地区 ID（8128 格斗）都取准确 types。
func _types_of(species_id: int) -> Array:
    var prof := PokemonStarters.profile(species_id)
    var types: Array = prof.get("types", [])
    if not types.is_empty():
        return types
    var entry := Pokedex.entry(species_id)
    return entry.get("types", []) if not entry.is_empty() else []

func _player_types() -> Array:
    var own: Array = (player_special_form["types"] as Array).duplicate() if not player_special_form.is_empty() else _types_of(player_species_id)   # 超级 / 超极巨形态的属性
    if player_fusion_id > 0:
        return Fusion.types(own, _types_of(player_fusion_id))   # 融合
    return own

func _enemy_types(e: Enemy) -> Array:
    if not e.type_override.is_empty():
        return e.type_override   # 浸水 / 魔法粉 / 万圣夜 / 森林诅咒换过属性
    return e.t.get("types", [])

# 本系：原 apply() 的 w.value 从 1 起，攻击方属性含招式属性就 +0.5（1.5），否则 1。
func _stab(move_type: String, attacker_types: Array) -> float:
    return 1.5 if attacker_types.has(move_type) else 1.0

# 原克制乘积 d（双属性相乘）。返回 -1 表示攻击属性尚未接入，调用方报错，不当 1 倍。
func _effectiveness(move_type: String, defender_types: Array) -> float:
    return TypeChart.effectiveness(move_type, defender_types)

# 生产骰：原作 randBattleSeedInt(15)+85 = 整数 85..99；测试子类覆写注入确定值。
func _damage_roll() -> int:
    return PokemonDamage.damage_roll_from(randi_range(0, 14))

# 生产会心：Q=[24,8,2,1][clamp(stage,0,3)]；Q==1 必会心，否则 randBattleSeedInt(Q)==0。
# 当前三招没有会心提升 attr，也没有相关特性 / 道具，故 crit_stage 恒 0（默认 1/24）。
var _no_crit_now := false   # 幸运咒语：敌人打玩家时不会会心


func _crit_roll(crit_stage: int) -> bool:
    if _no_crit_now:
        _last_crit = false
        return false
    var q := PokemonDamage.crit_denominator(crit_stage)
    _last_crit = q <= 1 or randi_range(0, q - 1) == 0
    return _last_crit

# 一次物理招式的最终伤害（原公式整式一次 ceil）。type_eff<0 表示攻击属性未接入，报错并返回 0。
# atk_stage / def_stage 是原作能力等级（这里只有玩家的临时防御等级走 def_stage）。
func _physical_damage(level_v: int, power: int, attacker_stats: Array, defender_stats: Array,
        stab: float, type_eff: float, crit_stage := 0, atk_stage := 0, def_stage := 0) -> float:
    if type_eff < 0.0:
        push_error("pokemon_damage: 攻击属性尚未接入，跳过伤害")
        return 0.0
    return float(PokemonDamage.compute_physical(level_v, power, attacker_stats, defender_stats,
        stab, type_eff, _damage_roll(), _crit_roll(crit_stage), atk_stage, def_stage))

# 一次特殊招式的最终伤害；M/G 读 SPATK/SPDEF，不能拿 ATK/DEF 冒充特殊招式。
func _special_damage(level_v: int, power: int, attacker_stats: Array, defender_stats: Array,
        stab: float, type_eff: float, crit_stage := 0, atk_stage := 0, def_stage := 0) -> float:
    if type_eff < 0.0:
        push_error("pokemon_damage: 攻击属性尚未接入，跳过伤害")
        return 0.0
    return float(PokemonDamage.compute_special(level_v, power, attacker_stats, defender_stats,
        stab, type_eff, _damage_roll(), _crit_roll(crit_stage), atk_stage, def_stage))

# 随机挑一招（挥指）；测试子类可覆写注入确定值。
func _pick_random_move(pool: Array) -> String:
    return str(pool[randi_range(0, pool.size() - 1)])


# 范围内最近的“满血”活敌人（击掌奇袭）：普通怪 hp >= 最大 HP；头目按当前分段回满等价于 hp >= t.hp。
func _nearest_full_hp(radius: float) -> Enemy:
    var best: Enemy = null
    var dist := INF
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e):
            continue
        if e.hp < _enemy_max_hp(e):
            continue
        var d := player.position.distance_to(e.node.position)
        if d <= radius + float(e.t["radius"]) and d < dist:
            best = e
            dist = d
    return best


# 自己的某项能力等级被改动后刷新 20 秒的消退计时（到时整项回 0）。
func _touch_stage_timer(stat: String) -> void:
    player_stage_until[stat] = run_clock + STAGE_TTL


func _player_stage_clear(stat: String) -> void:
    var base := int(buff_base.get(stat, 0))   # 被动强化的底子（强化招只生效一次、常驻）
    match stat:
        "atk":
            player_atk_stage = base
        "def":
            player_def_stage = base
        "spatk":
            player_spatk_stage = base
        "spdef":
            player_spdef_stage = base
        "spd":
            player_spd_stage = base
        "acc":
            player_acc_stage = base
        "eva":
            player_eva_stage = base


# 老格式招式数据的能力名（变硬 "defence"、叫声 "attack"…）统一成新格式。
const STAT_ALIAS := {"attack": "atk", "defence": "def", "defense": "def", "speed": "spd", "special_attack": "spatk",
    "special_defence": "spdef", "special_defense": "spdef", "accuracy": "acc", "evasion": "eva"}


func _norm_stat(stat: String) -> String:
    return str(STAT_ALIAS.get(stat, stat))


# 强化招放完这一次：把它加的等级记成底子，并且不进 20 秒消退。
func _stage_snapshot() -> Dictionary:
    return {"atk": player_atk_stage, "def": player_def_stage, "spatk": player_spatk_stage, "spdef": player_spdef_stage,
        "spd": player_spd_stage, "acc": player_acc_stage, "eva": player_eva_stage}


# 强化招放完这一次：放之前 / 之后能力等级的差就是它加的，记成底子、不进 20 秒消退
# （剑舞 / 点穴随机那项 / 腹鼓 / 甩肉都一样算）；聚气、水流环另外改成不过期。
func _lock_buff(_id: String, before: Dictionary) -> void:
    var after := _stage_snapshot()
    for st in after:
        var d := int(after[st]) - int(before.get(st, after[st]))
        if d != 0:
            buff_base[st] = clampi(int(buff_base.get(st, 0)) + d, STAT_STAGE_MIN, STAT_STAGE_MAX)
            player_stage_until.erase(st)
    for eff: Dictionary in MOVES.MOVES.get(_id, {}).get("effects", []):
        match str(eff.get("kind", "")):
            "crit_boost":
                player_crit_boost_until = 0.0   # 0 = 不过期（聚气常驻）
            "regen":
                regen_until = 1.0e12            # 水流环 / 扎根：一直回血


# 限时效果的统一刷新（_attack_tick 每帧调）：能力等级 / 聚气到时消退；寄生种子按秒吸血并回给玩家。
func _timed_tick() -> void:
    _field_tick()
    _charge_tick()
    for stat in player_stage_until.keys():
        if run_clock >= float(player_stage_until[stat]):
            _player_stage_clear(str(stat))
            player_stage_until.erase(stat)
    if player_crit_boost and player_crit_boost_until > 0.0 and run_clock >= player_crit_boost_until:
        player_crit_boost = false
        player_crit_boost_until = 0.0
    for e in enemies:
        # 哈欠：到点睡着（已经有别的主要异常就睡不着，由状态核心判）。
        if e.yawn_at > 0.0 and e.dying < 0.0 and run_clock >= e.yawn_at:
            e.yawn_at = 0.0
            _generic_status("yawn", e, "sleep")
        # 缠绕：到期放开；期间每 residual_secs 秒削一次最大 HP 的 1/8。
        if e.trapped_until > 0.0 and e.dying < 0.0:
            if run_clock >= e.trapped_until:
                e.trapped_until = 0.0
            else:
                while e.trap_next <= run_clock and e.trap_next < e.trapped_until and e.dying < 0.0:
                    e.trap_next += residual_secs
                    var frac := TRAP_BOSS_FRACTION if bool(e.t.get("boss", false)) else TRAP_FRACTION
                    _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / frac)), 1))
        if e.seeded_until <= 0.0 or e.dying >= 0.0:
            continue
        if run_clock >= e.seeded_until:
            e.seeded_until = 0.0
            continue
        while e.seed_next <= run_clock and e.seed_next < e.seeded_until and e.dying < 0.0:
            e.seed_next += residual_secs
            var drain := maxi(int(floorf(_enemy_max_hp(e) / 8.0)), 1)
            var before := e.hp
            _enemy_status_damage(e, drain)
            var drained := minf(float(drain), maxf(before, 0.0))
            if drained > 0.0 and not dead and player_hp > 0.0:
                heal(drained)


# 变威力：嚣张 / 辅助力量 = 基础 + 20 × 自己所有正能力等级之和；抓狂按自己剩余 HP 比例分档。
func _move_power(m: Dictionary) -> int:
    var power := int(m["power"])
    if m.has("power_stages"):
        power += int(m["power_stages"]) * _player_positive_stages()
    if bool(m.get("power_by_hp", false)):
        power = _flail_power()
    # 滚动（原 ConsecutiveUseDoublePowerAttr 5 次）：连续命中第 n 次威力 ×2^n（30 / 60 / 120 / 240 / 480），
    # 先用过变圆（限时内）再 ×2。
    # 连斩（用户 2026-10-17 贴 52poke：每次命中下次威力翻倍，封顶 160；打空 / 失败重置）：40 / 80 / 160。
    # 中间用别的招、换目标都不打断（自动连放下几个招交替出）；只有打空 / 被免疫 / 开新局才清。
    if m.has("consecutive") and consec_count > 0 and consec_id == str(m.get("source", "")).to_lower():
        power = power * (1 << clampi(consec_count, 0, int(m["consecutive"])))
    # 日光束 / 日光刃（本作不用蓄力）：晴天以外的雨 / 沙 / 雪天里威力减半。
    if bool(m.get("weather_halve", false)) and (weather == "rain" or weather == "sand" or weather == "snow" or weather == "hail" or weather == "fog"):
        power = maxi(power / 2, 1)
    if bool(m.get("rollout", false)):
        power = power * (1 << clampi(rollout_count, 0, 4))
        if run_clock < player_curled_until:
            power *= 2
    if m.has("friendship_power"):
        var fp := int(floorf(minf(float(player_friendship), 255.0) / 2.5))
        power = maxi(fp if str(m["friendship_power"]) == "return" else 102 - fp, 1)
    # 受击蓄势招（恶意追击 / 以牙还牙）：这一次出招的威力倍率。
    if _cast_power_mult != 1.0:
        power = int(power * _cast_power_mult)
    if bool(m.get("spit_up", false)):
        power = 100 * stockpile   # 喷出：原版威力 = 100 × 蓄力层数（没蓄就打不出伤害）
    # 携带道具·属性强化（木炭 / 神秘水滴…）：同属性招式威力 ×(1 + 0.2 × 个数)，原版向下取整
    var tb := int(run_held.get(HeldItems.type_item(str(m.get("type", ""))), 0))
    if tb > 0:
        power = int(floorf(float(power) * HeldItems.type_power_mult(tb)))
    return power


# 原 countPositiveStatStages：ATK / DEF / SPATK / SPDEF / SPD / ACC（本作没有 EVA）里大于 0 的等级相加。
func _player_positive_stages() -> int:
    var total := 0
    for st in [player_atk_stage, player_def_stage, player_spatk_stage, player_spdef_stage, player_spd_stage, player_acc_stage]:
        if int(st) > 0:
            total += int(st)
    return total


# 原 LowHpPowerAttr：hpRatio 取两位小数（getHpRatio 四舍五入到 0.01），< .0417→200、< .1042→150、< .2083→100、
# < .3542→80、< .6875→40，否则 20。
func _flail_power() -> int:
    var hp_max := maxf(1.0, float(stats.value("hp_max")))
    var ratio := roundf(clampf(player_hp / hp_max, 0.0, 1.0) * 100.0) / 100.0
    if ratio < 0.0417:
        return 200
    if ratio < 0.1042:
        return 150
    if ratio < 0.2083:
        return 100
    if ratio < 0.3542:
        return 80
    if ratio < 0.6875:
        return 40
    return 20


# 精神波的随机百分比：源 randSeedIntRange(50, 150)；测试子类可覆写注入确定值。
func _level_damage_roll(lo: int, hi: int) -> int:
    return randi_range(lo, hi)


# 三重攻击等“随机挑一种”：源 randSeedItem；测试子类可覆写注入确定下标。
func _effect_pick(count: int) -> int:
    return randi_range(0, count - 1)


# 玩家招式对目标敌人的伤害；变化招（变硬 / 吐丝 / 超音波 / 三粉）不直接伤害，返回 0。
# 物理读 ATK/DEF、特殊读 SPATK/SPDEF（起风 / 念力是特殊）；本系 / 克制与物理共用。
# 目标 DEF/SPDEF 用**独立的敌人阶段**（破段强化后的 e.def_stage / e.spdef_stage），
# 不再把玩家自己的 player_def_stage 当成目标 DEF（玩家变硬只影响受击，不降低自己的输出）。
# 攻击方灼伤时，只有普通物理招在整式 ceil 之后再 floor(/2)（core 提供函数，不改原公式）。
func _player_move_damage(id: String, target: Enemy) -> float:
    return _player_move_damage_core(id, target) * _lens_damage_mult   # 进攻多重镜的整体折扣（没开镜时是 1.0）


func _player_move_damage_core(id: String, target: Enemy) -> float:
    var m: Dictionary = MOVES.MOVES[id]
    var category := str(m["category"])
    if category != "物理" and category != "特殊":
        return 0.0
    var move_type := str(m["type"])
    # 一击必杀（地裂 / 极落钳 / 角钻 / 绝对零度）：伤害 = 目标当前 HP；头目免疫（原作 failOnBoss 同类处理）。
    if bool(m.get("ohko", false)):
        return 0.0 if bool(target.t.get("boss", false)) else maxf(target.hp, 1.0)
    # 愤怒门牙 / 自然之怒 / 大灾难：伤害 = 目标当前 HP 的一半（至少 1）。
    if bool(m.get("half_hp", false)):
        return float(maxi(int(floorf(target.hp / 2.0)), 1))
    # 蛮干：伤害 = 目标当前 HP − 自己当前 HP（目标不比自己多就没效果）。
    if bool(m.get("match_hp", false)):
        return maxf(target.hp - player_hp, 0.0)
    # 精神波：固定伤害 = 自己等级 × (50..150)%，向下取整最低 1；不走威力 / 本系 / 克制公式（属性免疫在出招前已挡）。
    if m.has("level_damage"):
        var span: Array = m["level_damage"]
        var pct := _level_damage_roll(int(span[0]), int(span[1]))
        return float(maxi(int(floorf(float(level) * (float(pct) * 0.01))), 1))
    var eff := _effectiveness(move_type, _exposed_types(move_type, _enemy_types(target), target))
    var stab := _stab(move_type, _player_types())
    var crit_stage := int(m.get("crit_stage", 0)) + (2 if player_crit_boost else 0) + _ab_crit_bonus(null) + int(run_held.get("SCOPE_LENS", 0)) \
        + (2 if int(run_held.get("LEEK", 0)) > 0 and HeldItems.species_ok("LEEK", player_species_id) else 0)   # 焦点镜 +1；大葱 +2（大葱鸭 / 葱游兵）
    if bool(m.get("crit_only", false)) or laser_focus_next:
        crit_stage = 3   # 会心阶段 >= 3 → 1/1，必定会心（原 CritOnlyAttr；磨砺 = 下一招必定会心）
        laser_focus_next = false
    var power := _move_power(m)
    power = _power_rules(m, power, target, eff)
    # 气象球：天气里威力 ×2、属性随天气变（雨水 / 晴火 / 沙岩石 / 雪冰）。
    if bool(m.get("weather_ball", false)) and weather != "":
        power *= 2
        move_type = {"rain": "水", "sun": "火", "sand": "岩石", "snow": "冰", "hail": "冰", "fog": "一般"}.get(weather, move_type)
        eff = _effectiveness(move_type, _exposed_types(move_type, _enemy_types(target), target))
        stab = _stab(move_type, _player_types())
    # 唤醒巴掌：目标睡着时威力 ×2（之后由 wake 效果叫醒）。
    if m.has("sleep_boost") and target.status.major_effect == PokemonStatus.SLEEP:
        power = int(float(power) * float(m["sleep_boost"]))
    # 充电：限时内下一次电系伤害招威力 ×2，用掉就清（原 ChargedTag）。
    if move_type == "电" and run_clock < player_charged_until:
        power *= 2
        player_charged_until = 0.0
    # 天气 / 场地：水火招、四个场地各自加成，沙暴岩石 / 雪天冰系的防御加成（两边共用）。
    var field := _field_mult(move_type, category, _player_types(), _enemy_types(target))
    var a_stats: Array = player_stats
    var d_stats: Array = target.t["stats"]
    var a_stage := player_atk_stage
    var spdef_stage: int = target.spdef_stage
    if bool(m.get("use_target_atk", false)):   # 欺诈：用目标的攻击算
        a_stats = player_stats.duplicate()
        a_stats[1] = d_stats[1]
        a_stage = target.atk_stage
    if bool(m.get("use_def_as_atk", false)):   # 身体压制：用自己的防御算
        a_stats = player_stats.duplicate()
        a_stats[1] = player_stats[2]
        a_stage = player_def_stage
    if bool(m.get("use_def", false)):          # 精神冲击 / 神秘之剑：特殊招打对方的防御
        d_stats = d_stats.duplicate()
        d_stats[4] = d_stats[2]
        spdef_stage = target.def_stage
    if category == "特殊":
        return _apply_field(_special_damage(level, power, a_stats, d_stats, stab, eff,
            crit_stage, player_spatk_stage, spdef_stage), field)
    var final := _physical_damage(level, power, a_stats, d_stats, stab, eff,
        crit_stage, a_stage, target.def_stage)
    return _apply_field(_burn_physical(id, final, player_status), field)

# 敌人这一次挥击用哪一招：从它的近身招池里随机挑（测试子类可覆写）。
# 定身法封住的招不会被选；近身招全被封住就返回 ""（这次不挥击）。
func _enemy_pick_move(e: Enemy) -> String:
    var pool := _enemy_usable(e, e.melee_moves)
    if pool.is_empty():
        return ""
    if pool.size() == 1:
        return str(pool[0])
    return str(pool[_enemy_move_roll(pool.size())])


# ================= 定身法（DISABLE，用户 2026-10-17 第一个封印招）=================
# 原作：封住目标上一次用过的招 4 回合，目标没用过招就失败。本作：玩家的定身法只挑“用过招”的敌人，
# 封住它上一次出的那一招 DISABLE_SECS 秒；封期里该招不会被选，正在蓄力 / 挥的那一下也取消。
const DISABLE_SECS := 4.0


func _enemy_move_disabled(e: Enemy, move_id: String) -> bool:
    return e.disabled_move == move_id and e.disabled_until > run_clock


func _enemy_usable(e: Enemy, pool: Array) -> Array:
    var out: Array = []
    for m in pool:
        if not _enemy_move_disabled(e, str(m)):
            out.append(m)
    return out


# 范围内最近的、用过招且当前没被封住的活敌人（定身法的目标）。
func _nearest_with_last_move(radius: float) -> Enemy:
    var best: Enemy = null
    var dist := INF
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e) or e.last_move == "":
            continue
        if e.disabled_until > run_clock:
            continue
        var d := player.position.distance_to(e.node.position)
        if d <= radius + float(e.t["radius"]) and d < dist:
            best = e
            dist = d
    return best


# ================= 受击蓄势 / 反击类招式（用户 2026-10-17）=================
const HURT_WINDOW := 6.0        # 挨打后这么多秒内蓄势有效
# 瞬间移动（用户 2026-10-17 改：“他们在后面，直接拉 10 个传送到面前 5-7 米，当然不是脸上”）：
# 把身后（背对前进方向那一半）的怪拉最多 10 只，传送到主角面前 5..7 米、前进方向 ±50° 的扇形里（头目不拉）。
# 瞬间移动是主动技能（用户 2026-10-18：“做成主动的，我们可以传送到任意地点，然后有个和抓宠一样的时间减速”）：
# 学了它以后按 T → 画面慢下来、鼠标跟着一个小圈 → 左键点要去的地方，主角立刻过去；右键 / Esc 取消。
# 冷却走这招自己的冷却；不再自动放。传送距离最远 TELEPORT_PLAYER_MAX 米，目标会被树 / 石头推出来。
const TELEPORT_AIM := -2
const TELEPORT_PLAYER_MAX := 14.0
const TELEPORT_COUNT := 10
const TELEPORT_MIN := 5.0
const TELEPORT_MAX := 7.0
const TELEPORT_CONE_DEG := 50.0
const HEAL_BLOCK_SECS := 5.0    # 回复封锁：5 回合 ≈ 5 秒（本作 1 回合 ≈ 1 秒的统一口径）


# 受击蓄势：序号比这招上次用掉的新，且在窗口内。
func _hurt_ready(id: String) -> bool:
    return hurt_serial > int(hurt_used.get(id, 0)) and run_clock - hurt_at <= HURT_WINDOW


func _hurt_consume(id: String) -> void:
    hurt_used[id] = hurt_serial


# 双倍奉还：最近一次物理招伤害的来源（还活着、在射程内）才是目标。
func _counter_target(id: String) -> Enemy:
    var kind := str(MOVES.MOVES[id].get("counter_kind", "physical"))
    var serial := hurt_phys_serial
    var at := hurt_phys_at
    var src = hurt_phys_src
    if kind == "special":
        serial = hurt_spec_serial
        at = hurt_spec_at
        src = hurt_spec_src
    elif kind == "any":
        serial = hurt_serial
        at = hurt_at
        src = hurt_any_src
    if serial <= int(hurt_used.get(id, 0)) or run_clock - at > HURT_WINDOW:
        return null
    var e: Enemy = src as Enemy
    if e == null or not is_instance_valid(e.node) or e.dying >= 0.0 or not _is_live_target(e):
        return null
    if player.position.distance_to(e.node.position) > _range(id) + float(e.t["radius"]):
        return null
    return e


# 双倍奉还：把最近一次受到的物理伤害 ×2 作为固定伤害还给打自己的敌人；只认属性免疫（格斗打幽灵无效），
# 不套 STAB / 克制 / 会心（原 CounterDamageAttr：忽略其他属性相克和属性一致加成）。
func _cast_counter(id: String) -> bool:
    var e := _counter_target(id)
    if e == null:
        return false
    var m: Dictionary = MOVES.MOVES[id]
    move_casts[id] = int(move_casts.get(id, 0)) + 1
    var ckind := str(m.get("counter_kind", "physical"))
    var base_dmg := hurt_phys_dmg if ckind == "physical" else (hurt_spec_dmg if ckind == "special" else hurt_any_dmg)
    var dmg := base_dmg * float(m.get("counter", 2.0))
    hurt_used[id] = hurt_phys_serial if ckind == "physical" else (hurt_spec_serial if ckind == "special" else hurt_serial)
    if not _hit(id, e):
        return true
    _play_move_fx(id, e)
    if _move_type_immune(id, _enemy_types(e), e):
        _show_status_feedback("%s 对%s没有效果" % [str(e.t["name"]), str(m["name"])])
        return true
    var dir := (e.node.position - player.position).normalized()
    if dir.length_squared() < 0.001:
        dir = facing
    _damage(e, dmg, dir, 0.0, id)
    return true


# 突袭的目标：范围内最近的、正要出招的敌人（近身挥击还没落下，或弹药在蓄力）。
# 被缠绕的普通敌人原地不动（头目不被定身，只掉血）；仍然能在原地攻击贴身的玩家。
func _trap_holds(e: Enemy) -> bool:
    return e.trapped_until > run_clock and not bool(e.t.get("boss", false))


func _nearest_sleeping(radius: float) -> Enemy:
    var best: Enemy = null
    var dist := INF
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e) or e.status.major_effect != PokemonStatus.SLEEP:
            continue
        var d := player.position.distance_to(e.node.position)
        if d <= radius + float(e.t["radius"]) and d < dist:
            best = e
            dist = d
    return best


func _nearest_attacking(radius: float) -> Enemy:
    var best: Enemy = null
    var dist := INF
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e):
            continue
        if not ((e.hit_in > 0.0 and e.atk_left > 0.0) or e.shoot_wind > 0.0):
            continue
        var d := player.position.distance_to(e.node.position)
        if d <= radius + float(e.t["radius"]) and d < dist:
            best = e
            dist = d
    return best


# 身后能被拉走的怪：活着、不是头目、在主角背后那一半（离得最远的优先，最多 TELEPORT_COUNT 只）。
func _pullable_enemies() -> Array[Enemy]:
    var behind: Array[Enemy] = []
    var fwd := Vector3(facing.x, 0.0, facing.z).normalized()
    for e in enemies:
        if e.dying >= 0.0 or not _is_live_target(e) or bool(e.t.get("boss", false)):
            continue
        var off := e.node.position - player.position
        off.y = 0.0
        if off.dot(fwd) < 0.0:
            behind.append(e)
    behind.sort_custom(func(a: Enemy, b: Enemy): return a.node.position.distance_squared_to(player.position) > b.node.position.distance_squared_to(player.position))
    return behind.slice(0, TELEPORT_COUNT)


# 能不能现在用瞬间移动：学了、没关、冷却好了。返回空串 = 可以；否则返回给玩家看的原因。
func _teleport_block_reason() -> String:
    if not active_moves.has("teleport"):
        return "还没学会瞬间移动"
    if disabled_moves.has("teleport"):
        return "瞬间移动被你关掉了（暂停时在左下角技能开关里打开）"
    var left := float(move_timer.get("teleport", 0.0))
    if left > 0.0:
        return "瞬间移动还在冷却（%.1f 秒）" % left
    return ""


# 按 T：进入点地面传送的瞄准（慢动作 + 一个小圈跟着鼠标）。
func _begin_teleport_aim() -> void:
    if not _ball_aim_allowed() or paused or capture_pause_mode:
        return
    var why := _teleport_block_reason()
    if why != "":
        if hud != null and active_moves.has("teleport"):
            hud.show_banner(why)
        return
    ball_aiming = true
    ball_aim_type = TELEPORT_AIM
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("show_aim"):
        capture_page.call("show_aim", TELEPORT_AIM, 0.8)
    _start_ball_slowmo()


# 左键点了地面：主角传过去（最远 TELEPORT_PLAYER_MAX 米，被树 / 石头挡住就推出来），进冷却，收掉瞄准和慢动作。
func _teleport_to(world_pos: Vector3) -> bool:
    if _teleport_block_reason() != "":
        _cancel_ball_aim()
        return false
    var from := player.position
    var off := world_pos - from
    off.y = 0.0
    if off.length() > TELEPORT_PLAYER_MAX:
        off = off.normalized() * TELEPORT_PLAYER_MAX
    var target := from + off
    if scenery != null:
        target = scenery.push_out(target, 0.6)
    target.y = from.y
    player.position = target
    move_timer["teleport"] = _cd("teleport")
    move_casts["teleport"] = int(move_casts.get("teleport", 0)) + 1
    last_used_move = "teleport"
    _cancel_ball_aim()
    if hud != null:
        hud.show_banner("瞬间移动！")
    return true


# 瞬间移动：把身后的怪传送到面前 TELEPORT_MIN..TELEPORT_MAX 米的前方扇形里；被树 / 石头挡住就推出去，
# 传过去的怪清掉正在进行的攻击、先喘一口气（不会一落地就出招），身上闪一下白。
func _pull_enemies_ahead() -> int:
    var picked := _pullable_enemies()
    var base := atan2(facing.z, facing.x)
    var cone := deg_to_rad(TELEPORT_CONE_DEG)
    for e in picked:
        var ang := base + randf_range(-cone, cone)
        var dist := randf_range(TELEPORT_MIN, TELEPORT_MAX)
        var target := player.position + Vector3(cos(ang), 0.0, sin(ang)) * dist
        if scenery != null:
            target = scenery.push_out(target, float(e.t["radius"]) * 0.6)
        target.y = 0.0
        e.node.position = target
        e.kb = Vector3.ZERO
        e.atk_left = 0.0
        e.hit_in = -1.0
        e.shoot_wind = -1.0
        e.attack_cd = maxf(e.attack_cd, 0.8)
        if e.node.has_method("flash_white"):
            e.node.call("flash_white")
    if not picked.is_empty():
        _show_status_feedback("身后的 %d 只宝可梦被传送到了面前" % picked.size())
    return picked.size()


# 敌人能不能回复 HP（回复封锁期间不能）。现在敌人没有任何回复手段，先把入口留好，以后给敌人加吸血 / 回复时统一过它。
func _enemy_can_heal(e: Enemy) -> bool:
    return run_clock >= e.heal_blocked_until


func _apply_disable(e: Enemy) -> void:
    e.disabled_move = e.last_move
    e.disabled_until = run_clock + DISABLE_SECS
    if e.cur_move == e.disabled_move and e.hit_in > 0.0:
        e.atk_left = 0.0
        e.hit_in = -1.0
    if e.shoot_wind > 0.0 and e.shoot_move == e.disabled_move:
        e.shoot_wind = -1.0
    var zh := str(MOVES.MOVES[e.disabled_move]["name"]) if MOVES.MOVES.has(e.disabled_move) else e.disabled_move
    _show_status_feedback("%s 的「%s」被封住了！" % [str(e.t["name"]), zh])


func _enemy_move_roll(count: int) -> int:
    return randi_range(0, count - 1)


# ================= 敌人弹药（用户 2026-10-17）=================
# 远程（特殊）招不再瞬间锁定：敌人在射程内先蓄力 0.4 秒，然后朝**发射时**玩家所在位置直线射出一发弹体，
# 弹体不追踪，玩家走开就能躲；飞到玩家身上才掷命中骰、算伤害（仍是 `_enemy_move_hits` / `_enemy_move_damage`）。
# 蓄力和飞行期间敌人照常往玩家走（不站桩）。弹体外观 = 该招原特效图层（起风 = 小龙卷风）；没有就画色球。
const ENEMY_SHOOT_RANGE := 4.0   # 与玩家 MAX_ATTACK_RANGE 同口径（用户：包括敌人也是）
const ENEMY_SHOOT_CD := 2.5
const ENEMY_SHOOT_WIND := 0.4
const BOLT_SPEED := 6.0
const BOLT_LIFE := 0.75   # 6 米/秒 × 0.75 秒 = 最多飞 4.5 米，不会飞到屏幕外
const BOLT_HIT_RADIUS := 0.45
const BOLT_HEIGHT := 0.6
const MAX_BOLTS := 40
const BOLT_COLORS := {
    "火": Color(1.0, 0.45, 0.15), "水": Color(0.3, 0.55, 1.0), "电": Color(1.0, 0.9, 0.2),
    "草": Color(0.4, 0.85, 0.3), "冰": Color(0.6, 0.9, 1.0), "超能力": Color(1.0, 0.4, 0.8),
    "幽灵": Color(0.5, 0.3, 0.7), "龙": Color(0.4, 0.3, 0.9), "恶": Color(0.35, 0.25, 0.3),
    "毒": Color(0.7, 0.3, 0.8), "虫": Color(0.65, 0.8, 0.2), "地面": Color(0.75, 0.6, 0.3),
    "岩石": Color(0.7, 0.65, 0.4), "格斗": Color(0.85, 0.35, 0.25), "钢": Color(0.7, 0.75, 0.8),
    "飞行": Color(0.75, 0.85, 1.0), "一般": Color(0.9, 0.9, 0.85), "妖精": Color(1.0, 0.6, 0.85),
}


func _enemy_ranged_pick(e: Enemy) -> String:
    var pool := _enemy_usable(e, e.ranged_moves)
    if pool.is_empty():
        return ""
    if pool.size() == 1:
        return str(pool[0])
    return str(pool[_enemy_move_roll(pool.size())])


# 削弱招（叫声 / 瞪眼 / 摇尾巴 / 泼沙…）也是弹药：命中才掷命中、再降玩家一项能力；
# 敌人造成的降低最多到 ENEMY_DEBUFF_FLOOR（-2）级，免得一屋子怪把防御叠到 -6（“被搞死”）；照旧 20 秒消退。
const ENEMY_DEBUFF_CD := 10.0
const ENEMY_DEBUFF_FLOOR := -2
const ENEMY_DEBUFF_CHANCE := 0.5   # 冷却好了、又有伤害弹药可选时，选削弱招的概率
var _last_debuff_banner_ms := -100000


# 选这次发射的招：削弱招冷却好了就有机会选它；只会削弱招的怪（没有伤害弹药）冷却好了必选它。
func _enemy_pick_shot(e: Enemy) -> String:
    var debuffs := _enemy_usable(e, e.debuff_moves)
    var shots := _enemy_usable(e, e.ranged_moves)
    if not debuffs.is_empty() and e.debuff_cd <= 0.0 and (shots.is_empty() or randf() < ENEMY_DEBUFF_CHANCE):
        e.debuff_cd = ENEMY_DEBUFF_CD * float(call("_ab_pressure_factor"))   # 玩家的压迫感
        return str(debuffs[_enemy_move_roll(debuffs.size())])
    if shots.is_empty():
        return ""
    return _enemy_ranged_pick(e)


func _player_stage_of(stat: String) -> int:
    match stat:
        "atk":
            return player_atk_stage
        "def":
            return player_def_stage
        "spatk":
            return player_spatk_stage
        "spdef":
            return player_spdef_stage
        "acc":
            return player_acc_stage
        "spd":
            return player_spd_stage
    return 0


# 削弱弹药命中玩家：命中骰（招式命中）→ 降一项能力（不低于 ENEMY_DEBUFF_FLOOR）→ 战斗报告 + 一句提示。
func _enemy_debuff_hit(e: Enemy, move_id: String) -> bool:
    var info := EnemyMoves.debuff_of(move_id, MOVES.MOVES, MOVES.IMPLEMENTED)
    if info.is_empty():
        return false
    if bool(MOVES.MOVES[move_id].get("powder", false)) and (_player_types().has("草") or _ab_has(null, "OVERCOAT")):
        return false   # 粉末招：草系 / 防尘无效
    var keep := e.cur_move
    e.cur_move = move_id
    var hit := _enemy_move_hits(e)
    e.cur_move = keep
    if not hit:
        return false
    var stat := str(info["stat"])
    var before := _player_stage_of(stat)
    var want := clampi(before + int(info["stages"]), ENEMY_DEBUFF_FLOOR, STAT_STAGE_MAX)
    var delta := want - before
    if delta < 0 and run_clock < mist_until:
        return true   # 白雾：能力不会被降低（招式算打中了，只是没效果）
    if delta < 0:
        if _ab_bounces(null):
            _ab_say("%s 的特性把「%s」反弹了回去！" % [_ab_owner(null), str(MOVES.MOVES[move_id]["name"])])
            _generic_stat_change(false, e, stat, delta)
            return true
        _generic_stat_change(true, null, stat, delta, true)
    var stat_zh: String = str({"atk": "攻击", "def": "防御", "spatk": "特攻", "spdef": "特防", "spd": "速度", "acc": "命中", "eva": "闪避"}.get(stat, stat))
    var move_name := str(MOVES.MOVES[move_id]["name"])
    battle_report.record_debuff(run_clock, str(e.t.get("name", "敌人")), move_name, str(stat_zh), delta, _player_stage_of(stat))
    var now := Time.get_ticks_msec()
    if delta < 0 and now - _last_debuff_banner_ms > 3000:
        _last_debuff_banner_ms = now
        _show_status_feedback("%s 的「%s」：%s 下降了" % [str(e.t.get("name", "敌人")), move_name, stat_zh])
    return true


func _enemy_shoot_tick(e: Enemy, dist: float, radius: float, fleeing: bool, delta: float) -> void:
    if e.ranged_moves.is_empty() and e.debuff_moves.is_empty():
        return
    e.debuff_cd = maxf(0.0, e.debuff_cd - delta)
    if e.shoot_wind > 0.0:
        # 蓄力中：被畏缩 / 睡眠 / 冰冻等打断就取消（冷却照扣）。
        if fleeing or not _unit_can_act(e):
            e.shoot_wind = -1.0
            return
        e.shoot_wind -= delta
        if e.shoot_wind <= 0.0:
            e.shoot_wind = -1.0
            _fire_bolt(e)
        return
    e.shoot_cd = maxf(0.0, e.shoot_cd - delta)
    if e.shoot_cd > 0.0 or fleeing or e.atk_left > 0.0 or stress != 0:
        return
    if dist <= radius + 0.55 * enemy_range_scale or dist > ENEMY_SHOOT_RANGE * enemy_range_scale:
        return   # 贴身了走近身挥击；太远不射
    e.shoot_cd = ENEMY_SHOOT_CD * float(call("_ab_pressure_factor"))   # 玩家的压迫感
    if not _unit_can_act(e):
        return
    e.shoot_move = _enemy_pick_shot(e)
    if e.shoot_move == "":
        return   # 只有削弱招、还在冷却（或招被定身法封住）：这次不射
    e.last_move = e.shoot_move
    e.shoot_wind = ENEMY_SHOOT_WIND
    e.pulse = 1.0   # 蓄力提示：身体鼓一下


func _fire_bolt(e: Enemy) -> void:
    if bolts.size() >= MAX_BOLTS or e.node == null or not is_instance_valid(e.node):
        return
    var dir := player.position - e.node.position
    dir.y = 0.0
    if dir.length() < 0.001:
        return
    dir = dir.normalized()
    var b := Bolt.new()
    b.owner = e
    b.move = e.shoot_move
    b.dir = dir
    b.left = BOLT_LIFE * maxf(1.0, enemy_range_scale)   # 射程放大时弹体也要飞得到
    var origin := e.node.position + dir * float(e.t["radius"]) + Vector3(0, BOLT_HEIGHT, 0)
    var fx := _rogue().make_projectile(b.move)
    if fx != null:
        b.node = fx
        b.sprite = true
    else:
        var orb := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 0.18
        mesh.height = 0.36
        orb.mesh = mesh
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color = BOLT_COLORS.get(str(MOVES.MOVES[b.move]["type"]), Color.WHITE)
        orb.material_override = mat
        add_child(orb)
        b.node = orb
    _place_bolt(b, origin)
    bolts.append(b)
    _rogue().play_launch_sound(b.move)   # 发射声 = 该招原动画开头的声音


func _place_bolt(b: Bolt, pos: Vector3) -> void:
    if b.sprite:
        _rogue().place_projectile(b.node as MeshInstance3D, pos, b.age)
    else:
        b.node.position = pos


func _free_bolt(b: Bolt) -> void:
    if b.node != null and is_instance_valid(b.node):
        b.node.queue_free()


# 命中特效：弹体打中玩家时，在玩家身上播该招原图层的“到了目标身上”那一段（没有飞行图层的招 = 一个扩散的色球）。
const IMPACT_ORB_SECS := 0.3


func _spawn_impact(move_id: String) -> void:
    if impacts.size() >= MAX_BOLTS:
        return
    var imp := {"move": move_id, "age": 0.0, "life": _rogue().IMPACT_SECS, "sprite": true}
    var node: Node3D = _rogue().make_impact(move_id)
    if node == null:
        imp["sprite"] = false
        imp["life"] = IMPACT_ORB_SECS
        var orb := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 0.25
        mesh.height = 0.5
        orb.mesh = mesh
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.albedo_color = BOLT_COLORS.get(str(MOVES.MOVES[move_id]["type"]), Color.WHITE)
        orb.material_override = mat
        add_child(orb)
        node = orb
    imp["node"] = node
    impacts.append(imp)
    _place_impact(imp)


func _place_impact(imp: Dictionary) -> void:
    var pos := player.position + Vector3(0, BOLT_HEIGHT, 0)
    var node: Node3D = imp["node"]
    if bool(imp["sprite"]):
        _rogue().place_impact(node as MeshInstance3D, pos, float(imp["age"]))
        return
    var t := clampf(float(imp["age"]) / float(imp["life"]), 0.0, 1.0)
    node.position = pos
    node.scale = Vector3.ONE * (1.0 + 1.4 * t)
    var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
    var c := mat.albedo_color
    c.a = 1.0 - t
    mat.albedo_color = c


func _update_impacts(delta: float) -> void:
    for i in range(impacts.size() - 1, -1, -1):
        var imp: Dictionary = impacts[i]
        imp["age"] = float(imp["age"]) + delta
        var node: Node3D = imp["node"]
        if float(imp["age"]) >= float(imp["life"]) or node == null or not is_instance_valid(node):
            if node != null and is_instance_valid(node):
                node.queue_free()
            impacts.remove_at(i)
            continue
        _place_impact(imp)


func _update_bolts(delta: float) -> void:
    _update_impacts(delta)
    for i in range(bolts.size() - 1, -1, -1):
        var b: Bolt = bolts[i]
        var pos: Vector3 = b.node.global_position
        pos += b.dir * BOLT_SPEED * delta
        b.age += delta
        b.left -= delta
        var flat := Vector2(pos.x - player.position.x, pos.z - player.position.z)
        if flat.length() <= BOLT_HIT_RADIUS:
            bolts.remove_at(i)
            _free_bolt(b)
            var e := b.owner
            if str(MOVES.MOVES[b.move]["category"]) == "变化":
                if _enemy_debuff_hit(e, b.move):
                    _spawn_impact(b.move)
                continue
            var keep := e.cur_move
            e.cur_move = b.move   # 不打断同一只敌人正在挥的近身招
            if _enemy_move_hits(e):
                _spawn_impact(b.move)
                _hurt(_enemy_move_damage(e), e)
            e.cur_move = keep
            if player_hp <= 0.0:
                break
            continue
        if b.left <= 0.0:
            bolts.remove_at(i)
            _free_bolt(b)
            continue
        _place_bolt(b, pos)


func _clear_bolts() -> void:
    for b: Bolt in bolts:
        _free_bolt(b)
    bolts.clear()
    for imp: Dictionary in impacts:
        if imp["node"] != null and is_instance_valid(imp["node"]):
            (imp["node"] as Node).queue_free()
    impacts.clear()


# 敌人近身攻击（第一步，用户 2026-10-16）：用 e.cur_move 这一招——威力 / 属性 / 物理或特殊 / 命中都按招式；
# 招式附带的异常 / 能力变化 / 吸血 / 反伤一律不用。攻击方 = 敌人实际 level / 物种 / 六维，防守方 = 玩家当前进化形态 /
# 六维；物理读 ATK / DEF（玩家临时防御等级进防守方），特殊读 SPATK / SPDEF（玩家特防等级进防守方）；
# 敌人破段强化的 ATK / SPATK 阶段进攻击方。不新造敌人选招 AI 之外的东西，保留现有攻击动作 / 命中时刻 / 冷却 1.2。
# 敌人自身灼伤时，普通物理招末端 floor(/2)（特殊不减）。反射壁 / 光墙按招式类别各减半。
func _enemy_move_damage(e: Enemy) -> float:
    var m: Dictionary = MOVES.MOVES[e.cur_move]
    var move_type := str(m["type"])
    var eff := _effectiveness(move_type, _player_types())
    var stab := _stab(move_type, _enemy_types(e))
    _last_crit = false
    var power := int(m["power"])
    var lv := int(e.t["level"])
    if run_clock < float_until and move_type == "地面":
        return 0.0   # 电磁飘浮：免疫地面招
    var field := _field_mult(move_type, str(m["category"]), _enemy_types(e), _player_types())
    _no_crit_now = run_clock < lucky_chant_until   # 幸运咒语
    if str(m["category"]) == "特殊":
        var sfinal := _apply_field(_special_damage(lv, power, e.t["stats"], player_stats, stab, eff, _ab_crit_bonus(e), e.spatk_stage, player_spdef_stage), field)
        _no_crit_now = false
        if run_clock < player_screen_spec_until:
            sfinal *= 0.5
        return sfinal * _passive_screen_mult("special")
    var final := _physical_damage(lv, power, e.t["stats"], player_stats, stab, eff, _ab_crit_bonus(e), e.atk_stage, player_def_stage)
    _no_crit_now = false
    final = _apply_field(_burn_physical(e.cur_move, final, e.status), field)
    # 反射壁：限时内受到的物理伤害 ×0.5。
    if run_clock < player_screen_phys_until:
        final *= 0.5
    return final * _passive_screen_mult("physical")



# 自动释放由实际掌握的 active_moves 驱动，而不是写死三招；未实现的 id 跳过。
# 只要本次真的释放（命中或未命中）就进入冷却，避免未命中时每帧重试直到命中。
# 当秒被异常状态挡住（睡眠 / 冰冻的立即阻断，或主要异常 / 混乱的当秒判定缓存）：
# 招式 timer 继续走，**一旦走到就绪并发现被挡，就当场消耗原冷却**——不放原特效、不扣目标 HP、
# 不增加实际释放计数。不能只在整秒 tick 那一刻处理「原本就已经就绪」的招，否则秒内才就绪的招
# 会一直保持 0 冷却、每帧空重试。醒来后后续就绪招正常放，不积压成一帧刷 N 发。
func _attack_tick(delta: float) -> void:
    run_clock += delta
    _timed_tick()
    _aura_tick(delta)
    for id: String in active_moves:
        if not MOVES.is_implemented(id) or disabled_moves.has(id):
            continue
        move_timer[id] = maxf(0.0, float(move_timer.get(id, 0.0)) - delta)
        if id == "teleport":
            continue   # 瞬间移动是主动技能（按 T 点地面），不自动放
        if float(move_timer[id]) > 0.0:
            continue
        if (aura_on and _is_aura_move(id)) or (screens_passive and _is_screen_move(id)):
            continue   # 光环 / 常驻护盾：带着就生效，不自动放
        var buff := buff_once and (_is_self_buff_move(id) or MoveRoles.is_passive_other(id))
        if buff and buff_done.has(id):
            continue   # 强化招这局已经生效过：不再放、不叠层
        var gate := _heal_gate_of(id) if heal_gate_ratio > 0.0 else 0.0
        if heal_gate_ratio > 0.0 and MoveRoles.is_guard(id):
            gate = MoveRoles.GUARD_GATE
        if gate > 0.0 and player_hp > float(stats.value("hp_max")) * gate:
            continue   # 回血 / 防守救急：血量还没低到门槛，先不放（计时器保持就绪，血一低马上触发）
        if heal_gate_ratio > 0.0 and MoveRoles.is_cure(id) and not (player_status != null and player_status.has_major()):
            continue   # 解异常：没中异常就不放
        if not _can_act() or run_clock < rest_until:
            move_timer[id] = minf(_cd(id), 1.0) if run_clock < rest_until else _cd(id)
            continue
        var before := _stage_snapshot() if buff else {}
        if _cast_move(id):
            if buff:
                buff_done[id] = true
                _lock_buff(id, before)
            if heal_gate_ratio > 0.0 and MoveRoles.is_guard(id):
                player_protect_until = maxf(player_protect_until, run_clock + MoveRoles.GUARD_SECS)   # 救急：1.5 秒什么都伤不到
            move_timer[id] = _cd(id)
            if id != "copycat":
                last_used_move = id


# 释放一次招式；有目标就计次并消耗冷却，未命中也一样；没有目标才不计。
# 变硬是自身变化招（原作 target 0 / SelfStatusMove）：不需要附近敌人，也不掷 1..100 命中骰。
# 五招（超音波 / 念力 / 三粉）都是 target 3 最近单体；念力有直接伤害，其余四招 0 直接伤害。
# ================= 多重镜（局外商店单只培养里买，规则见 game/pokemon_lens.gd）=================
# 单体招放出去以后，再对最近的另外几只各放一次（每级多 1 只）；进攻镜给所有目标的伤害打折。
# 实现是“包装 + 回放”：第一次照旧放，记下它打的是谁，再把目标指定成别的敌人各回放一次，
# 冷却 / 命中判定 / 异常 / 伤害公式全走原来的路径，不另写一套。
var _forced_target: Enemy = null
var _lens_last_target: Enemy = null
var _lens_busy := false
var _lens_damage_mult := 1.0


# 这招吃哪种多重镜：""（不吃）/ "support"（变化类单体）/ "attack"（有伤害的单体）。
func _lens_kind_for(id: String) -> String:
    var m: Dictionary = MOVES.MOVES[id]
    if int(m.get("target", 3)) != 3 or bool(m.get("group", false)) or m.has("condition"):
        return ""
    for eff: Dictionary in m.get("effects", []):
        if PokemonLens.EXCLUDED_EFFECTS.has(str(eff.get("kind", ""))):
            return ""
    return "support" if str(m.get("category", "")) == "变化" else "attack"


# 除了 primary 以外、射程内最近的 count 只活敌人。
func _lens_extra_targets(id: String, count: int, primary: Enemy) -> Array[Enemy]:
    var pool: Array[Enemy] = []
    for e in _near_enemies(_range(id)):
        if e != primary:
            pool.append(e)
    pool.sort_custom(func(a: Enemy, b: Enemy): return a.node.position.distance_squared_to(player.position) < b.node.position.distance_squared_to(player.position))
    return pool.slice(0, count)


func _cast_move(id: String) -> bool:
    var kind := _lens_kind_for(id)
    var bought := lens_support if kind == "support" else (lens_attack if kind == "attack" else 0)
    var level := PokemonLens.effective_level_bonus(bought, _shiny_lens_bonus()) if kind != "" else 0   # 闪光开局另加等级
    if level <= 0 or _lens_busy:
        return _cast_move_core(id)
    _lens_busy = true
    _lens_last_target = null
    _lens_damage_mult = PokemonLens.damage_mult(kind, level)
    var ok := _cast_move_core(id)
    var primary := _lens_last_target
    if ok and primary != null:
        for e in _lens_extra_targets(id, level, primary):
            _forced_target = e
            _cast_move_core(id)
        _forced_target = null
    _lens_damage_mult = 1.0
    _lens_busy = false
    return ok


func _cast_move_core(id: String) -> bool:
    var m: Dictionary = MOVES.MOVES[id]
    # 第二批数据驱动招式（gen2）：单独一条通用路径，旧招分支原样不动。
    if bool(m.get("gen2", false)):
        return _cast_generic(id)
    # 1) 自身变化招（变硬 / 变圆）：不需要附近敌人，也不掷命中骰。
    if str(m["category"]) == "变化" and int(m["target"]) == 0:
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _cast_harden(id)
        return true
    # 2) 全体变化招（吐丝 / 瞪眼 / 摇尾巴 / 叫声）：范围内一圈活敌人，每目标独立判命中
    #    （先于单体分支，否则会被当成单目标）。吐丝降目标 SPD 等级 2；瞪眼 / 摇尾巴降目标 DEF 1；
    #    叫声按原创构造 `.attr(Se,le.ATK,-1).target(6)` 显式分派降目标 ATK 1，不误用吐丝的降速 / 动画。
    if int(m["target"]) == 6:
        var candidates := _near_enemies(_range(id))
        if candidates.is_empty():
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        if id == "growl":
            _cast_attack_drop(candidates)
        elif id == "leer" or id == "tail_whip":
            _cast_stat_drop(candidates, id)
        else:
            _cast_string_shot(candidates)
        return true
    # 3) 单体变化招：超音波 / 三粉（附加状态、0 直接伤害）；泼沙降目标 ACC；念力是特殊招，另有 10% 混乱。
    if str(m["category"]) == "变化":
        var single := _single_target(id)
        if single == null:
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        if id == "sand_attack":
            _cast_accuracy_drop(single)
        else:
            _cast_status_move(id, single)
        return true
    if id == "confusion":
        var confuse_target := _single_target(id)
        if confuse_target == null:
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _cast_confusion_move(id, confuse_target)
        return true
    # 3.5) 电击（电 / 特殊）：与念力同一条「先伤害、命中后独立概率附加主要状态」窄路径，
    #      不是通用效果架构。target 3 最近单体：定好目标再掷命中，命中后不再重新选最近目标。
    if id == "thunder_shock":
        var shock_target := _single_target(id)
        if shock_target == null:
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _cast_thunder_shock_move(id, shock_target)
        return true
    # 4) 单体伤害招（撞击 / 虫咬 / 起风 / 啄 / 抓 / 拍击 / 电光一闪）：定好目标再掷命中，命中后不再重新选最近目标。
    #    电光一闪的 `priority: 1` 只是 data 里的原字段 metadata（未来口子），本函数不读它，
    #    也不因此多打一次 / 加速 / 插队 / 冲刺 / 位移 / 击退：与同 power / type / category 的撞击同一条路径。
    var target := _single_target(id)
    if target == null:
        return false
    move_casts[id] = int(move_casts.get(id, 0)) + 1
    if not _hit(id, target):
        return true
    var dir := (target.node.position - player.position).normalized()
    if dir.length_squared() < 0.001:
        dir = facing
    _rogue().play(id, player, target.node, true, player_species_id)
    # 反伤招（猛撞 / 舍身冲撞）按本次**实际扣掉的目标 HP**反伤：普通怪按剩余 HP 限伤（e.hp 可为负，取 max 0）、
    # 头目取分段后实际扣血；miss / 免疫 / 0 伤害根本走不到这里或 dealt 为 0。无 recoil 字段的招 dealt 不被使用。
    var hp_before := target.hp
    _damage(target, _player_move_damage(id, target), dir, 0.0, id)
    _apply_recoil(id, hp_before - maxf(target.hp, 0.0))
    return true


# ================= 第二批：通用数据驱动招式路径（gen2）=================
# 字段见 data/pokemon_moves.gd 第二批注释：crit_stage / hits / drain / recoil / group / effects。
# 顺序照原 MoveEffectPhase：命中判定（必中 -1 不掷骰）→ 播原动画 → 属性免疫 → 伤害（连击逐次）→
# 吸血 / 反伤 → 对目标 / 自己的附带效果（各自掷 chance：-1 或 100 必附加，否则 0..99 骰 < chance）。

# 限时效果（秒）：用户 2026-10-16“很多东西要有个时间限制”。
const STAGE_TTL := 20.0        # 自己的能力等级：每改动一次刷新一次，到时整项回 0
const CRIT_BOOST_TTL := 30.0   # 聚气
const EXPOSE_TTL := 20.0       # 气味侦测
const CURL_TTL := 30.0         # 变圆（给滚动加倍）
const FLINCH_SECS := 1.0       # 畏缩：敌人向反方向跑开 1 秒
const SEED_SECS := 10.0        # 寄生种子
const ROLLOUT_WINDOW := 5.0    # 滚动连续命中的最长间隔
const ROLLOUT_MAX := 5
const GEN2_STAGE_INDEX := {"atk": 0, "def": 1, "spatk": 2, "spdef": 3, "spd": 4}
const GEN2_STAT_NAME := {"atk": "攻击", "def": "防御", "spatk": "特攻", "spdef": "特防", "spd": "速度", "acc": "命中"}
const GEN2_STATUS := {"toxic": PokemonStatus.POISON, "burn": PokemonStatus.BURN, "paralysis": PokemonStatus.PARALYSIS, "poison": PokemonStatus.POISON,
    "freeze": PokemonStatus.FREEZE, "sleep": PokemonStatus.SLEEP}
const GEN2_STATUS_NAME := {"burn": "灼伤", "paralysis": "麻痹", "poison": "中毒", "confusion": "混乱", "freeze": "冰冻", "toxic": "剧毒", "sleep": "睡眠"}


# 附带效果概率骰：源 randSeedInt(100) = 0..99；测试子类可覆写注入确定值。
func _effect_roll() -> int:
    return randi_range(0, 99)


# 连击次数骰：源 randSeedInt(16) = 0..15（测试子类可覆写）。
func _multi_hit_roll() -> int:
    return randi_range(0, 15)


# 原 MultiHitAttr 2~5 次：>=10 → 2、>=4 → 3、>=2 → 4、否则 5；固定 hits [n, n] 直接取 n。
func _generic_hit_count(m: Dictionary) -> int:
    var hits: Array = m.get("hits", [])
    if hits.is_empty():
        return 1
    if int(hits[0]) == int(hits[1]):
        return int(hits[0])
    var r := _multi_hit_roll()
    if r >= 10:
        return 2
    if r >= 4:
        return 3
    if r >= 2:
        return 4
    return 5


func _cast_generic(id: String) -> bool:
    var m: Dictionary = MOVES.MOVES[id]
    # 挥指：从已接进战斗的招里随机放一个（不含它自己和模仿）；放不出去（没目标）就不消耗冷却。
    if bool(m.get("random_move", false)):
        var pool: Array = []
        for mid: String in MOVES.IMPLEMENTED:
            if mid != "metronome" and mid != "copycat":
                pool.append(mid)
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        return _cast_move(_pick_random_move(pool))
    # 模仿：复制自己招式栏里上一个刚用过的招；一个都没用过就放不出去。
    if bool(m.get("copy_last", false)):
        if last_used_move == "" or last_used_move == "copycat" or not MOVES.is_implemented(last_used_move):
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        return _cast_move(last_used_move)
    # 受击后才能用的招（瞬间移动）：没挨过打（或这一下已经被这招用掉）就放不出去、不耗冷却。
    var cond := str(m.get("condition", ""))
    if cond == "player_hurt" and not _hurt_ready(id):
        return false
    if cond == "enemies_behind" and _pullable_enemies().is_empty():
        return false   # 身后没有怪可拉：放不出去、不耗冷却
    if m.has("counter"):
        return _cast_counter(id)
    # 自身状态招的“别白放”条件（屏障已在 / 回血已开 / 满血睡觉 …），不满足不耗冷却。
    match cond:
        "screen_off":
            var all_on := true
            for se: Dictionary in m.get("effects", []):
                if str(se["kind"]) == "screen":
                    var w := str(se["screen"])
                    if (w != "special" and run_clock >= player_screen_phys_until) or (w != "physical" and run_clock >= player_screen_spec_until):
                        all_on = false
            if all_on:
                return false
        "aurora":
            if weather != "snow" or (run_clock < player_screen_phys_until and run_clock < player_screen_spec_until):
                return false
        "regen_off":
            if run_clock < regen_until:
                return false
        "float_off":
            if run_clock < float_until:
                return false
        "lock_off":
            if player_lock_on:
                return false
        "hp_low":
            if player_hp > stats.value("hp_max") * 0.6:
                return false
        "hp_high":
            if player_hp <= stats.value("hp_max") * 0.6 or player_atk_stage >= STAT_STAGE_MAX:
                return false
    # 蓄力招（挖洞 / 飞翔 / 弹跳 / 神鸟猛击 …）：先蓄力，到点自动出击。
    if m.has("charge"):
        return _begin_charge(id)
    # 狂暴类（大闹一番 / 逆鳞 / 花瓣舞）：连出 frenzy 下，之后自己混乱；连击期间不重复放。
    if m.has("frenzy"):
        for p0: Dictionary in pending_strikes:
            if str(p0["id"]) == id:
                return false
        var ft := _single_target(id)
        if ft == null:
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _cast_generic_single(id, ft)
        var n := int(m["frenzy"])
        for k in range(1, n):
            pending_strikes.append({"id": id, "due": run_clock + FRENZY_GAP * float(k), "target": ft, "frenzy_end": k == n - 1})
        return true
    # 自身变化招（磨爪 / 龙之舞 / 高速移动）：不要目标、不掷命中，写自己的能力等级。
    if int(m["target"]) == 0:
        # 守住 / 看穿 / 挺住（月桂式护盾）：已经有盾 / 盾刚破还在冷却 / 标准攻击圈内没有敌人，都不放（不耗冷却）。
        if cond == "field_off":
            for eff0: Dictionary in m.get("effects", []):
                if (str(eff0["kind"]) == "weather" and weather == str(eff0["weather"])) or (str(eff0["kind"]) == "terrain" and terrain == str(eff0["terrain"])):
                    return false   # 已经是这个天气 / 场地，不重复放
        if cond == "enemy_near" and (player_shield != "" or run_clock < shield_ready_at or _near_enemies(_std_range()).is_empty()):
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _rogue().play(id, player, player, true, player_species_id)
        _generic_effects(id, null, 0.0)
        return true
    if bool(m.get("group", false)) or int(m["target"]) == 6:
        var candidates := _near_enemies(_range(id))
        if candidates.is_empty():
            return false
        move_casts[id] = int(move_casts.get(id, 0)) + 1
        _cast_generic_group(id, candidates)
        return true
    var target := _single_target(id)
    # 击掌奇袭：只对满血的敌人有效（用户：“满血的呗”，当作“还没被打过的第一击”）；没有满血目标就不出招、不耗冷却。
    if cond == "target_full_hp":
        target = _nearest_full_hp(_range(id))
    # 突袭：只打“正要出招”的敌人（蓄力弹药 / 近身挥击还没落下），抢在它前面；没有这样的敌人就不出招。
    elif cond == "target_attacking":
        target = _nearest_attacking(_range(id))
    # 定身法：只对用过招、且没被封住的敌人出（原作目标没用过招 / 已被封住都会失败）。
    elif str(m.get("condition", "")) == "target_has_last_move":
        target = _nearest_with_last_move(_range(id))
    # 食梦：只打睡着的敌人（原作目标没睡着会失败）。
    elif cond == "target_sleeping":
        target = _nearest_sleeping(_range(id))
    if target == null:
        return false
    move_casts[id] = int(move_casts.get(id, 0)) + 1
    # 恶意追击 / 以牙还牙：挨过打后的第一次威力 ×2，用掉这一下的蓄势（命中与否都算用掉）。
    var boosted := m.has("hurt_boost") and _hurt_ready(id)
    if boosted:
        _cast_power_mult = float(m["hurt_boost"])
    _cast_generic_single(id, target)
    _cast_power_mult = 1.0
    if boosted:
        _hurt_consume(id)
    return true


const TRAP_SECS := 4.5   # 缠绕持续（原作 4~5 回合）
const TRAP_FRACTION := 8.0         # 普通敌人每次削 1/8 最大 HP（原 TrapTag）
const TRAP_BOSS_FRACTION := 16.0   # 头目只削 1/16，而且不定身
const REST_SECS := 2.5      # 睡觉：这么多秒内不能出招
const REGEN_SECS := 20.0    # 水流环 / 扎根：持续回血的秒数
const FLOAT_SECS := 20.0    # 电磁飘浮（2026-10-24：和天气 / 场上效果一样 20 秒，冷却 40 秒）
const WISH_SECS := 2.0      # 祈愿：这么多秒后回血
const FRENZY_GAP := 0.5     # 狂暴类：连续出击的间隔
const YAWN_SECS := 2.0   # 哈欠：这么多秒后睡着（原作下一回合）
# 守住类招：标准攻击圈（_std_range）内有敌人才放（原来写死 5 米）
const SHIELD_COOLDOWN := 10.0        # 护盾挡下第一次伤害后，要等这么多秒才能再撑（试玩觉得长短改它）
const SHIELD_GRACE := 0.3            # 盾破后的缓冲（秒）：同一时刻好几只怪的伤害不会连破
# ================= 天气 / 场地（用户 2026-10-17：先做天气场地）=================
# 实时版：天气 / 场地各持续 WEATHER_SECS / TERRAIN_SECS 秒（原作 5 回合），玩家和敌人共用同一份；新的盖掉旧的。
#   雨：水系招 ×1.5、火系 ×0.5，打雷 / 暴风必中；晴：火 ×1.5、水 ×0.5，打雷 / 暴风命中 50，日光束不用等；
#   沙暴：每秒削非岩石 / 地面 / 钢属性 1/16 最大 HP，岩石系特防 ×1.5；雪：冰系防御 ×1.5，暴风雪必中。
#   场地（只对“在地面上”的，飞行系不吃）：电气 ×1.3 电系招 + 睡不着；青草 ×1.3 草系招 + 每秒回 1/16；
#   薄雾 龙系招打地面目标 ×0.5 + 状态异常上不去；精神 ×1.3 超能力招。
const WEATHER_SECS := 20.0
const TERRAIN_SECS := 20.0
const WEATHER_TEXT := {"rain": "下起了雨！", "sun": "日照变强了！", "sand": "沙暴刮起来了！", "snow": "下起了雪！", "hail": "下起了冰雹！", "fog": "起雾了！"}
const MAP_WEATHER_FOREVER := 1.0e12   # 地图天气不会自己到期（原版 trySetWeather(…, false) = 0 回合 = 一直在）
const WeatherOverlay := preload("res://fx/weather_overlay.gd")
const Weather3D := preload("res://fx/weather_3d.gd")
const RAIN_LEVEL := 2   # 0 无 / 1 小雨 / 2 中雨 / 3 大雨 / 4 暴雨（带雷光）
const SNOW_LEVEL := 3   # 2 档在游戏镜头下太稀，看不出在下雪
const FOG_LEVEL := 2
const RAIN_CLOUD_LEVEL := 2   # 下雨时地上的云影
const SNOW_COLD_LEVEL := 2    # 下雪时的寒冷滤镜（用户 2026-10-21 看图点头的是 2 档）
const HAIL_LEVEL := 3
const SAND_LEVEL := 4         # 用户 2026-10-21 看图点头的是 4 档
const BiomeWeather := preload("res://data/biome_weather.gd")
const TERRAIN_TEXT := {"electric": "脚下流淌着电流！", "grassy": "脚下长出了青草！", "misty": "脚下起了薄雾！", "psychic": "脚下泛起奇异的光！"}
const WEATHER_TINT := {"rain": Color(0.2, 0.35, 0.75, 0.16), "sun": Color(1.0, 0.78, 0.3, 0.13), "sand": Color(0.78, 0.6, 0.3, 0.22), "snow": Color(0.88, 0.94, 1.0, 0.16)}
var _weather_layer: CanvasLayer = null   # fx/weather_overlay.gd：原版天气动画铺满屏幕（雨 / 雪 / 雾的画面改用 _world_fx）+ 天气音效
var _world_fx: Node3D = null   # fx/weather_3d.gd：雨 / 雪 / 雾 / 云影


# 招式召来的天气（求雨 / 大晴天…）：持续 WEATHER_SECS，到期回到地图天气。kind "" = 清掉招式天气、回到地图天气。
func _set_weather(kind: String) -> void:
    if kind == "":
        _apply_weather(map_weather, MAP_WEATHER_FOREVER if map_weather != "" else 0.0)
        return
    _apply_weather(kind, run_clock + WEATHER_SECS)


func _apply_weather(kind: String, until: float) -> void:
    weather = kind
    weather_until = until if kind != "" else 0.0
    if kind != "":
        weather_next = run_clock + residual_secs
    _apply_world_fx(kind)
    if _weather_layer == null or not is_instance_valid(_weather_layer):
        if kind == "":
            return
        _weather_layer = WeatherOverlay.new()
        add_child(_weather_layer)
    _weather_layer.call("set_weather", kind)


# 晴天还是原来的一亮一暗。换成别的天气就全关。
func _apply_world_fx(kind: String) -> void:
    var wants := kind in ["rain", "snow", "fog", "hail", "sand"]
    if _world_fx == null or not is_instance_valid(_world_fx):
        if not wants or player == null:
            return
        _world_fx = Weather3D.new()
        add_child(_world_fx)
        _world_fx.call("setup", player)
        _world_fx.call("set_wind", Vector2(randf_range(-0.4, 0.4), randf_range(0.0, 0.2)))
    _world_fx.call("set_rain", RAIN_LEVEL if kind == "rain" else 0)
    _world_fx.call("set_clouds", RAIN_CLOUD_LEVEL if kind == "rain" else 0)
    _world_fx.call("set_snow", SNOW_LEVEL if kind == "snow" else 0)
    _world_fx.call("set_cold", SNOW_COLD_LEVEL if kind == "snow" else 0)
    _world_fx.call("set_fog", FOG_LEVEL if kind == "fog" else 0)
    _world_fx.call("set_hail", HAIL_LEVEL if kind == "hail" else 0)
    _world_fx.call("set_sandstorm", SAND_LEVEL if kind == "sand" else 0)


# 地图天气（原版每场战斗按地区天气表掷一次）：招式天气还没到期就先不换画面，到期后回到这个。
func _set_map_weather(kind: String, announce := true) -> void:
    var changed := kind != map_weather
    map_weather = kind
    var move_weather_on := weather != "" and weather_until < MAP_WEATHER_FOREVER and run_clock < weather_until
    if not move_weather_on:
        _apply_weather(kind, MAP_WEATHER_FOREVER if kind != "" else 0.0)
    if changed and announce and kind != "" and hud != null:
        hud.show_banner(str(WEATHER_TEXT.get(kind, "")))


# 每过一分钟（= 原版一场战斗）按当前地区的天气表重掷；has_sun 照原版：黎明 / 白天才可能晴。
# minute_wave = 第几分钟（换了才重掷）；battle_wave = 战斗波次（昼夜按它算，和野生宝可梦同一套）。
func _map_weather_tick(minute_wave: int, battle_wave := 1) -> void:
    if map_weather_wave == minute_wave:
        return
    map_weather_wave = minute_wave
    var tod: int = wild.time_for_wave(battle_wave) if wild != null else 1
    _set_map_weather(BiomeWeather.roll(map_id, tod < 2, weather_roll))


func _set_terrain(kind: String) -> void:
    terrain = kind
    if kind == "":
        terrain_until = 0.0
    else:
        terrain_until = run_clock + TERRAIN_SECS
        terrain_next = run_clock + residual_secs


func _grounded(types: Array) -> bool:
    return not types.has("飞行")


# 天气 / 场地对一次攻击伤害的总倍率。attacker / defender = 属性数组（汉字）。
func _field_mult(move_type: String, category: String, attacker_types: Array, defender_types: Array) -> float:
    var m := 1.0
    match ("" if _weather_suppressed() else weather):
        "rain":
            if move_type == "水":
                m *= 1.5
            elif move_type == "火":
                m *= 0.5
        "sun":
            if move_type == "火":
                m *= 1.5
            elif move_type == "水":
                m *= 0.5
        "sand":
            if category == "特殊" and defender_types.has("岩石"):
                m /= 1.5
        "snow":
            if category == "物理" and defender_types.has("冰"):
                m /= 1.5
    if _grounded(attacker_types):
        if (terrain == "electric" and move_type == "电") or (terrain == "grassy" and move_type == "草") or (terrain == "psychic" and move_type == "超能力"):
            m *= 1.3
    if terrain == "misty" and move_type == "龙" and _grounded(defender_types):
        m *= 0.5
    # 玩水 / 玩泥巴：原版火系 / 电系威力 ×0.33（双方都吃）
    if move_type == "火" and run_clock < water_sport_until:
        m *= 0.33
    if move_type == "电" and run_clock < mud_sport_until:
        m *= 0.33
    return m


# 无关天气（特性）：玩家有它时天气对伤害的影响消失（沙暴·冰雹的削血另算，见 _field_tick）。
func _weather_suppressed() -> bool:
    for key in _ab_keys(null):
        if AB.suppresses_weather(str(key)):
            return true
    return false


# 天气 / 场地倍率是 1（没天气）时原样返回，不动原公式的取整；否则向上取整。
func _apply_field(damage: float, field: float) -> float:
    return damage if field == 1.0 else ceilf(damage * field)


# 沙暴削血 / 青草回血 / 到期：每帧由 _timed_tick 调。
func _field_tick() -> void:
    _extra_tick()
    if weather != "" and run_clock >= weather_until:
        _set_weather("")   # 招式天气到期：回到地图天气
    if terrain != "" and run_clock >= terrain_until:
        _set_terrain("")
    if (weather == "sand" or weather == "hail") and run_clock >= weather_next:
        weather_next += residual_secs
        # 沙暴：岩石 / 地面 / 钢不扣；冰雹：冰不扣（原版 isTypeDamageImmune）
        var immune := ["岩石", "地面", "钢"] if weather == "sand" else ["冰"]
        # 防尘：两种天气都不扣（原版 OVERCOAT）
        if not dead and player_hp > 0.0 and _player_types().filter(func(t): return immune.has(t)).is_empty() and not _ab_has(null, "OVERCOAT"):
            _player_dot(maxi(int(floorf(stats.value("hp_max") / 16.0)), 1))
        for e in enemies:
            if e.dying < 0.0 and _enemy_types(e).filter(func(t): return immune.has(t)).is_empty() and not _ab_has(e, "OVERCOAT"):
                _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / 16.0)), 1))
    if regen_until > 0.0:
        if run_clock >= regen_until:
            regen_until = 0.0
        elif run_clock >= regen_next:
            regen_next += residual_secs
            if not dead and player_hp > 0.0:
                heal(float(maxi(int(floorf(stats.value("hp_max") / 16.0)), 1)))
    if terrain == "grassy" and run_clock >= terrain_next:
        terrain_next += residual_secs
        if not dead and player_hp > 0.0 and _grounded(_player_types()):
            heal(float(maxi(int(floorf(stats.value("hp_max") / 16.0)), 1)))
        for e in enemies:
            if e.dying < 0.0 and _grounded(_enemy_types(e)) and _enemy_can_heal(e):
                e.hp = minf(_enemy_max_hp(e), e.hp + float(maxi(int(floorf(_enemy_max_hp(e) / 16.0)), 1)))


# ================= 蓄力招（用户 2026-10-17：“可以，躲地震这个记着，之后要补”）=================
# 原作两回合：第一回合蓄力（半隐身招躲在地下 / 天上 / 水里打不到），第二回合出击。实时版：放出后蓄力 `charge` 秒，
# 到点对那一刻最近的敌人（群招 = 身边一圈）自动出击，走原来的命中 / 伤害 / 附带效果路径；
# 半隐身（"semi"）的蓄力期间敌人的伤害全免（和盾破后的缓冲同一套 player_protect_until），主角半透明。
# 蓄力中不重复放同一招；死亡 / 开新局取消。
# 半隐身照原版（用户 2026-10-20 补上“躲地震”那条）：躲着的时候只有特定招打得到，而且有的打双倍——
#   地下（挖洞）：地震 / 震级 / 地裂打得到，地震 / 震级 ×2；
#   天上（飞翔 / 弹跳）：起风 / 龙卷风 ×2，打雷 / 暴风 / 冲天拳 / 击落 / 千箭齐发 打得到；
#   水里（潜水）：冲浪 / 潮旋 ×2；暗影潜袭 / 潜灵奇袭：什么都打不到。
const SEMI_KIND := {"dig": "underground", "fly": "air", "bounce": "air", "dive": "water", "shadow_force": "void", "phantom_force": "void"}
const SEMI_HITS := {
    "underground": {"earthquake": 2.0, "magnitude": 2.0, "fissure": 1.0},
    "air": {"gust": 2.0, "twister": 2.0, "thunder": 1.0, "hurricane": 1.0, "sky_uppercut": 1.0, "smack_down": 1.0, "thousand_arrows": 1.0},
    "water": {"surf": 2.0, "whirlpool": 2.0},
}


# 敌人这一下打不打得到躲起来的玩家：0 = 不在躲 / 打不到；>0 = 打得到，返回伤害倍率。
func _semi_hit_mult(source) -> float:
    if player_semi_kind == "" or run_clock >= player_semi_until:
        return 0.0
    if source == null or not ("cur_move" in source):
        return 0.0
    return float((SEMI_HITS.get(player_semi_kind, {}) as Dictionary).get(str(source.cur_move), 0.0))
func _begin_charge(id: String) -> bool:
    var m: Dictionary = MOVES.MOVES[id]
    for p: Dictionary in pending_strikes:
        if str(p["id"]) == id:
            return false
    var group := bool(m.get("group", false)) or int(m["target"]) == 6
    var target: Enemy = null
    if int(m["target"]) == 0:
        if _near_enemies(_range(id) + 4.0).is_empty():
            return false   # 大地掌控这类自身招：身边没敌人不蓄力
    elif group:
        if _near_enemies(_range(id)).is_empty():
            return false
    else:
        target = _single_target(id)
        if target == null:
            return false
    move_casts[id] = int(move_casts.get(id, 0)) + 1
    var secs := float(m["charge"])
    pending_strikes.append({"id": id, "due": run_clock + secs, "target": target, "started": run_clock})
    _rogue().play(id + "_charging", player, target.node if target != null else player, true, player_species_id)
    if bool(m.get("semi", false)):
        player_protect_until = maxf(player_protect_until, run_clock + secs)
        player_semi_kind = str(SEMI_KIND.get(id, "void"))
        player_semi_until = run_clock + secs
        _set_charge_visual(true)
    _generic_effects(id, null, 0.0, "charge_effects")   # 火箭头锤蓄力时防御 +1 之类
    _show_status_feedback("%s 正在蓄力…" % str(m["name"]))
    return true


func _set_charge_visual(on: bool) -> void:
    if player == null or player.get_child_count() == 0:
        return
    var spr: Sprite3D = player.get_child(0).get_node_or_null("Sprite")
    if spr != null:
        var c: Color = spr.modulate
        c.a = 0.3 if on else 1.0
        spr.modulate = c


func _cancel_charges() -> void:
    pending_strikes.clear()
    _set_charge_visual(false)


# 每帧：到点的蓄力招出击。
func _charge_tick() -> void:
    if pending_strikes.is_empty():
        return
    if dead:
        _cancel_charges()
        return
    var rest: Array = []
    var any_semi := false
    for p: Dictionary in pending_strikes:
        if run_clock < float(p["due"]):
            rest.append(p)
            if bool(MOVES.MOVES[str(p["id"])].get("semi", false)):
                any_semi = true
            continue
        var id := str(p["id"])
        var m: Dictionary = MOVES.MOVES[id]
        if p.has("heal"):   # 祈愿：到点回血
            heal(float(maxi(int(floorf(stats.value("hp_max") * float(p["heal"]))), 1)))
            _show_status_feedback("祈愿实现了！")
            continue
        if bool(m.get("fail_if_hurt", false)) and hurt_at >= float(p.get("started", 0.0)) and hurt_serial > 0:
            _show_status_feedback("%s 的气势被打散了！" % _species_name(player_species_id))   # 真气拳：蓄力中挨打就失败
            continue
        if int(m["target"]) == 0:
            _rogue().play(id, player, player, true, player_species_id)
            _generic_effects(id, null, 0.0)
        elif bool(m.get("group", false)) or int(m["target"]) == 6:
            var cands := _near_enemies(_range(id))
            if not cands.is_empty():
                _cast_generic_group(id, cands)
        else:
            var t: Enemy = p["target"]
            if t == null or t.dying >= 0.0 or not is_instance_valid(t.node):
                t = _single_target(id)
            if t != null:
                _cast_generic_single(id, t)
        # 狂暴类最后一击之后自己混乱（原作锁定 2~3 回合后混乱）。
        if bool(p.get("frenzy_end", false)):
            _show_status_feedback("%s 因为大闹一番而混乱了！" % _species_name(player_species_id))
            _actor_apply_confusion_status(null)
    pending_strikes = rest
    if not any_semi:
        _set_charge_visual(false)


# 护盾：kind = "" 收起 / "protect" / "endure"；身上挂一个半透明的泡泡给玩家看。
func _set_shield(kind: String, move_id := "") -> void:
    player_shield = kind
    player_shield_move = move_id if kind != "" else ""
    var old := player.get_node_or_null("ShieldBubble") if player != null else null
    if old != null:
        old.queue_free()
        player.remove_child(old)
    if kind == "" or player == null:
        return
    var bubble := MeshInstance3D.new()
    bubble.name = "ShieldBubble"
    var sphere := SphereMesh.new()
    sphere.radius = 0.95
    sphere.height = 1.9
    bubble.mesh = sphere
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(0.45, 0.85, 1.0, 0.30) if kind == "protect" else Color(1.0, 0.8, 0.35, 0.30)
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    bubble.material_override = mat
    bubble.position = Vector3(0, 0.85, 0)
    player.add_child(bubble)


# 盾被打破：收盾、开始冷却、给一小段缓冲。
func _break_shield(source = null) -> void:
    var sm := player_shield_move
    _set_shield("")
    shield_ready_at = run_clock + SHIELD_COOLDOWN
    player_protect_until = run_clock + SHIELD_GRACE
    # 尖刺防守 / 王者盾牌 / 恶臭 / 灼热…：打破盾的那只敌人吃一份反击（来源是敌人本身才有效）。
    if sm != "" and source != null and source is Enemy and (source as Enemy).dying < 0.0 and MOVES.MOVES.has(sm):
        var e: Enemy = source
        var m: Dictionary = MOVES.MOVES[sm]
        if m.has("shield_thorns"):
            _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) * float(m["shield_thorns"]))), 1))
        for eff: Dictionary in m.get("shield_effects", []):
            if str(eff["kind"]) == "stat":
                _generic_stat_change(false, e, str(eff["stat"]), int(eff["stages"]))
            elif str(eff["kind"]) == "status":
                _generic_status(sm, e, str(eff["status"]))


# 连续命中加威力的招：命中 +1 层（到顶不再涨），打空 / 失败清零；不设超时，也不被别的招打断。
func _consec_note(id: String, hit: bool) -> void:
    if not MOVES.MOVES[id].has("consecutive") and not MOVES.MOVES[id].has("consecutive_linear"):
        return
    if not hit:
        consec_count = 0
        consec_id = ""
        return
    if consec_id == id:
        consec_count = mini(consec_count + 1, int(MOVES.MOVES[id].get("consecutive", MOVES.MOVES[id].get("consecutive_linear", 0))))
    else:
        consec_count = 1
    consec_id = id


# 大爆炸 / 玉石俱碎 / 惊爆大头 / 临别礼物：用完扣掉自己 self_cost 比例的最大 HP（最低留 1 点；原作是自己倒下，本作没有队伍，折成扣血）。
func _apply_self_cost(id: String) -> void:
    var cost := float(MOVES.MOVES[id].get("self_cost", 0.0))
    if cost > 0.0 and not dead:
        player_hp = maxf(1.0, player_hp - stats.value("hp_max") * cost)
        _show_status_feedback("%s 拼尽了全力！" % _species_name(player_species_id))


func _cast_generic_single(id: String, e: Enemy) -> void:
    var m: Dictionary = MOVES.MOVES[id]
    var rolling := bool(m.get("rollout", false))
    if rolling and run_clock - rollout_last > ROLLOUT_WINDOW:
        rollout_count = 0
    if not _hit(id, e):
        if rolling:
            rollout_count = 0
        _consec_note(id, false)
        _apply_crash(id)   # 飞膝踢 / 飞踢 / 下压踢：原版 MissEffectAttr(crashDamage) —— 打空摔到自己
        return
    _play_move_fx(id, e)
    var dealt := 0.0
    # 粉末招（孢子 / 催眠粉）打草属性：没有效果（变化招本来不走属性免疫，这条是粉末特设）。
    if str(m["category"]) == "变化" and _move_type_immune(id, _enemy_types(e), e):
        _show_status_feedback("%s 对%s没有效果" % [e.t["name"], str(m["name"])])
        return
    if str(m["category"]) != "变化":
        if _move_type_immune(id, _enemy_types(e), e):
            _show_status_feedback("%s 对%s没有效果" % [e.t["name"], str(m["name"])])
            if rolling:
                rollout_count = 0
            _consec_note(id, false)
            _apply_crash(id)   # 原版 NoEffectAttr(crashDamage)：属性免疫（如格斗打幽灵）也算摔到自己
            return
        for _i in _generic_hit_count(m):
            if e.dying >= 0.0:
                break
            var d := _generic_strike(id, e, 1.0)
            dealt += d
            _apply_drain(id, d)
        _apply_recoil(id, dealt)
        _consec_note(id, true)
        if rolling:
            rollout_count += 1
            rollout_last = run_clock
            if rollout_count >= ROLLOUT_MAX:
                rollout_count = 0
    _generic_effects(id, e, dealt)
    _apply_self_cost(id)


# 身边一圈（大声咆哮 / 活活气泡）：每个目标各自掷命中、各自算伤害；多于一个目标时伤害 ×0.75（原作群招的分摊系数）。
func _cast_generic_group(id: String, candidates: Array[Enemy]) -> void:
    var m: Dictionary = MOVES.MOVES[id]
    var spread := 0.75 if candidates.size() > 1 else 1.0
    var first_sound := true
    for e in candidates:
        if e.dying >= 0.0 or not _hit(id, e):
            continue
        _rogue().play(id, player, e.node, first_sound, player_species_id)
        first_sound = false
        var dealt := 0.0
        if str(m["category"]) != "变化":
            if _move_type_immune(id, _enemy_types(e), e):
                continue
            dealt = _generic_strike(id, e, spread)
            _apply_drain(id, dealt)
        _generic_effects(id, e, dealt)
    _apply_self_cost(id)


# ================= 威力随条件变的招（用户 2026-10-17：“这一批里面能立马完成的全完成”）=================
# 数据里的 power_rule：hp_user / hp_target / weight_target / weight_ratio / gyro / electro；其余是独立的小开关。
static var _weights: Dictionary = {}


func _species_weight(species_id: int) -> float:
    if _weights.is_empty():
        var f := FileAccess.open("res://data/rogue_upstream/species.json", FileAccess.READ)
        if f != null:
            var parsed: Variant = JSON.parse_string(f.get_as_text())
            if parsed is Dictionary:
                for k in parsed:
                    _weights[int(parsed[k]["id"])] = float(parsed[k].get("weight", 50.0))
    return float(_weights.get(species_id, 50.0))


func _power_rules(m: Dictionary, power: int, target: Enemy, eff: float) -> int:
    var rule := str(m.get("power_rule", ""))
    var base := int(m.get("power_base", m["power"]))
    var tw := _species_weight(int(target.t.get("species_id", 0)))
    var uw := _species_weight(player_species_id)
    match rule:
        "hp_user":     # 喷火 / 喷水 / 巨龙威能：威力 = 基础 × 自己剩余 HP 比例（至少 1）
            power = maxi(int(floorf(float(base) * player_hp / maxf(stats.value("hp_max"), 1.0))), 1)
        "hp_target":   # 绞紧 / 捏碎：威力 = 基础 × 目标剩余 HP 比例（至少 1）
            power = maxi(int(floorf(float(base) * target.hp / maxf(_enemy_max_hp(target), 1.0))), 1)
        "weight_target":   # 踢倒 / 打草结：按目标体重
            power = 20 if tw < 10.0 else (40 if tw < 25.0 else (60 if tw < 50.0 else (80 if tw < 100.0 else (100 if tw < 200.0 else 120))))
        "weight_ratio":    # 重磅冲撞 / 高温重压：自己体重是目标的几倍
            var r := uw / maxf(tw, 0.1)
            power = 120 if r >= 5.0 else (100 if r >= 4.0 else (80 if r >= 3.0 else (60 if r >= 2.0 else 40)))
        "gyro":        # 陀螺球：目标越快越强
            power = mini(150, int(floorf(25.0 * _enemy_effective_speed(target) / maxf(_player_effective_speed(), 1.0))) + 1)
        "electro":     # 电球：自己比目标越快越强
            var sr := _player_effective_speed() / maxf(_enemy_effective_speed(target), 1.0)
            power = 150 if sr >= 4.0 else (120 if sr >= 3.0 else (80 if sr >= 2.0 else (60 if sr >= 1.0 else 40)))
    if m.has("power_mult"):
        power = int(float(power) * float(m["power_mult"]))              # 杂技：没带道具 ×2
    if m.has("power_target_low_hp") and target.hp < _enemy_max_hp(target) * 0.5:
        power = int(float(power) * float(m["power_target_low_hp"]))     # 盐水：目标不到一半血 ×2
    if m.has("power_target_status") and target.status.major_effect != PokemonStatus.NONE:
        power = int(float(power) * float(m["power_target_status"]))   # 祸不单行 / 毒液冲击：目标有异常 ×2
    if m.has("power_target_poison") and target.status.major_effect == PokemonStatus.POISON:
        power = int(float(power) * float(m["power_target_poison"]))
    if m.has("power_user_status") and player_status.major_effect != PokemonStatus.NONE:
        power = int(float(power) * float(m["power_user_status"]))      # 硬撑：自己有异常 ×2
    if m.has("power_if_hurt") and run_clock - hurt_at <= HURT_WINDOW and hurt_serial > 0:
        power = int(float(power) * float(m["power_if_hurt"]))          # 报复 / 雪崩：刚挨过打 ×2
    if m.has("power_after") and last_used_move == str(m["power_after"]):
        power *= 2                                                      # 交错火焰 / 交错闪电：上一招是对方 ×2
    if m.has("power_super_effective") and eff >= 2.0:
        power = int(float(power) * float(m["power_super_effective"]))  # 全开猛撞 / 闪电猛冲：效果绝佳 ×1.33
    if m.has("consecutive_linear") and consec_count > 0 and consec_id == str(m.get("source", "")).to_lower():
        power = base * (1 + mini(consec_count, int(m["consecutive_linear"])))   # 回声：40 / 80 / 120 / 160 / 200
    return power


# 一次伤害：走唯一的 _player_move_damage（含会心阶段 / 玩家攻击等级），返回本次实际扣掉的目标 HP。
func _generic_strike(id: String, e: Enemy, scale: float) -> float:
    var dir := (e.node.position - player.position).normalized()
    if dir.length_squared() < 0.001:
        dir = facing
    var hp_before := e.hp
    var dmg := _player_move_damage(id, e) * scale
    if bool(MOVES.MOVES[id].get("cannot_kill", false)):
        dmg = minf(dmg, maxf(e.hp - 1.0, 0.0))   # 点到为止：至少留 1 点血
    _damage(e, dmg, dir, 0.0, id)
    return hp_before - maxf(e.hp, 0.0)


# 原 HitHealAttr：回复 = toDmgValue(本次实际造成伤害 × 比例) = max(floor(x), 1)；没造成伤害不回复。
func _apply_drain(id: String, dealt: float) -> void:
    var ratio := float(MOVES.MOVES[id].get("drain", 0.0))
    if ratio <= 0.0 or dealt <= 0.0 or dead or player_hp <= 0.0:
        return
    heal(float(maxi(int(floorf(dealt * ratio)), 1)))


# 附带效果：who=self 的只要命中就生效（目标被打死也照常）；who=target 的要求目标还活着。
func _ab_bounces(unit) -> bool:
    for key in _ab_keys(unit):
        if AB.bounces(str(key)):
            return true
    return false


func _ab_ignores_secondary(unit) -> bool:
    for key in _ab_keys(unit):
        if AB.ignores_secondary(str(key)):
            return true
    return false


# 携带道具·打中时：贝壳之铃（打出伤害的 1/8 × 个数回血，原版至少 1）、王者之证（每个 10% 让对方畏缩）。
# 贝壳之铃 / 王者之证：原版“每次出手一次”，本作群攻 × 每个目标 × 每次命中都触发被放大几十倍（2026-10-22 审查，用户让我定：每秒最多结算一次）。
# 贝壳之铃：这一秒打出的伤害先攒着，_bell_tick 每秒按总伤害回一次；王者之证：每只敌人每秒最多掷一次。
const ON_HIT_SECS := 1.0


func _held_on_hit(e: Enemy, applied: float) -> void:
    var bell := int(run_held.get("SHELL_BELL", 0))
    if bell > 0 and applied > 0.0:
        _bell_pool += applied
    # 黄金拳头：2026-10-25 起改成击杀点数加成（main/state.gd _points_award_kill），不再按伤害算
    var rock := int(run_held.get("KINGS_ROCK", 0))
    if rock > 0 and e.hp > 0.0 and run_clock >= e.rock_ready_at:
        e.rock_ready_at = run_clock + ON_HIT_SECS
        if HeldItems.kings_rock_flinches(rock, _held_roll10()) and not _ab_blocks_flinch(e):
            e.flee_until = run_clock + FLINCH_SECS


# 贝壳之铃每秒结一次：这一秒的总伤害 × 1/8 × 个数（原公式 shell_bell_heal）。
func _bell_tick(delta: float) -> void:
    _bell_clock += delta
    if _bell_clock < ON_HIT_SECS:
        return
    _bell_clock -= ON_HIT_SECS
    var bell := int(run_held.get("SHELL_BELL", 0))
    var pool := _bell_pool
    _bell_pool = 0.0
    if bell > 0 and pool > 0.0 and not dead and player_hp > 0.0 and player_hp < stats.value("hp_max"):
        heal(maxf(1.0, HeldItems.shell_bell_heal(pool, bell)))


func _ab_blocks_flinch(unit) -> bool:
    for key in _ab_keys(unit):
        if AB.blocks_flinch(str(key)):
            return true
    return false


func _generic_effects(id: String, e: Enemy, dealt: float, key := "effects") -> void:
    for eff: Dictionary in MOVES.MOVES[id].get(key, []):
        var chance := int(eff.get("chance", -1))
        var is_self := str(eff.get("who", "target")) == "self"
        if not is_self and (e == null or e.dying >= 0.0):
            continue
        if chance >= 0 and chance < 100:
            if not is_self and _ab_ignores_secondary(e):
                continue   # 鳞粉：不受招式追加效果影响
            var eff_chance := chance
            for ak in _ab_keys(null):
                eff_chance = int(round(float(eff_chance) * AB.chance_mult(str(ak))))
            if _effect_roll() >= eff_chance:
                continue
        match str(eff["kind"]):
            "stat":
                _generic_stat_change(is_self, e, str(eff["stat"]), int(eff["stages"]))
            "status":
                var status := str(eff["status"])
                if status == "random":
                    var pool: Array = eff["pool"]
                    status = str(pool[_effect_pick(pool.size())])
                _generic_status(id, e, status)
            "crit_boost":
                if not player_crit_boost:
                    _show_status_feedback("%s 提高了会心率！" % _species_name(player_species_id))
                player_crit_boost = true
                player_crit_boost_until = run_clock + CRIT_BOOST_TTL
            "reset_stats":
                _generic_reset_stats(e)
            "expose":
                e.exposed_ghost = true
                e.exposed_until = run_clock + EXPOSE_TTL
                _show_status_feedback("%s 被识破了" % str(e.t["name"]))
            "screen":
                var secs := float(eff.get("seconds", 5.0))
                var which := str(eff["screen"])
                if which == "physical" or which == "both":
                    player_screen_phys_until = run_clock + secs
                    _show_status_feedback("反射壁展开了！")
                if which == "special" or which == "both":
                    player_screen_spec_until = run_clock + secs
                    _show_status_feedback("光墙展开了！")
            "charge":
                player_charged_until = run_clock + float(eff.get("seconds", 20.0))
                _show_status_feedback("%s 充满了电！" % _species_name(player_species_id))
            "seed":
                if _enemy_types(e).has("草"):
                    _show_status_feedback("%s 对%s没有效果" % [str(e.t["name"]), "寄生种子"])
                elif e.seeded_until <= run_clock:
                    e.seeded_until = run_clock + SEED_SECS
                    e.seed_next = run_clock + residual_secs
                    _show_status_feedback("%s 被种下了种子！" % str(e.t["name"]))
            "flinch":
                if _ab_blocks_flinch(e):
                    continue
                e.flee_until = run_clock + FLINCH_SECS
                for ak in _ab_keys(e):
                    var fr := AB.rule(str(ak))
                    if fr.has("on_flinch"):
                        _generic_stat_change(false, e, str(fr["on_flinch"][0]), int(fr["on_flinch"][1]))
            "disable":
                if e.last_move != "" and e.disabled_until <= run_clock:
                    _apply_disable(e)
            "teleport":
                _pull_enemies_ahead()
            "heal_block":
                e.heal_blocked_until = run_clock + HEAL_BLOCK_SECS
                _show_status_feedback("%s 被封住了回复！" % str(e.t["name"]))
            "heal":
                # 原 HealAttr：回复 = 最大 HP × 比例（自我再生 / 羽栖 / 光合作用 0.5），走 heal() 吃回复倍率与回复封锁以外的规则。
                var ratio := float(eff.get("ratio", 0.5))
                if bool(eff.get("weather_heal", false)):
                    ratio = 0.5 if weather == "" else (2.0 / 3.0 if weather == "sun" else 0.25)   # 光合作用类：晴 2/3，其余天气 1/4
                var amount := float(maxi(int(floorf(stats.value("hp_max") * ratio)), 1))
                heal(amount)
                _show_status_feedback("%s 回复了体力！" % _species_name(player_species_id))
            "protect":
                _set_shield(str(eff.get("mode", "protect")), id)
                _show_status_feedback("%s 撑起了护盾！" % _species_name(player_species_id))
            "weather":
                var wk := str(eff["weather"])
                if weather != wk:
                    _set_weather(wk)
                    _show_status_feedback(str(WEATHER_TEXT[wk]))
            "terrain":
                var tk := str(eff["terrain"])
                if terrain != tk:
                    _set_terrain(tk)
                    _show_status_feedback(str(TERRAIN_TEXT[tk]))
            "trap":
                if e.trapped_until <= run_clock:
                    e.trapped_until = run_clock + TRAP_SECS
                    e.trap_next = run_clock + residual_secs
                    _show_status_feedback("%s 被%s困住了！" % [str(e.t["name"]), str(MOVES.MOVES[id]["name"])])
            "lock_on":
                player_lock_on = true
                _show_status_feedback("%s 锁定了目标！" % _species_name(player_species_id))
            "rest":
                player_status.reset_all()
                player_hp = stats.value("hp_max")
                rest_until = run_clock + REST_SECS
                _show_status_feedback("%s 睡着了，体力全满！" % _species_name(player_species_id))
            "regen":
                regen_until = run_clock + REGEN_SECS
                regen_next = run_clock + residual_secs
                _show_status_feedback("%s 扎下了根，持续回复体力！" % _species_name(player_species_id))
            "float":
                float_until = run_clock + FLOAT_SECS
                _show_status_feedback("%s 浮在了空中！" % _species_name(player_species_id))
            "belly_drum":
                var half := stats.value("hp_max") * 0.5
                if player_hp > half and player_atk_stage < STAT_STAGE_MAX:
                    player_hp -= half
                    player_atk_stage = STAT_STAGE_MAX
                    _touch_stage_timer("atk")
                    _show_status_feedback("%s 削减体力，攻击大幅提升！" % _species_name(player_species_id))
            "wish":
                pending_strikes.append({"id": id, "due": run_clock + WISH_SECS, "heal": float(eff.get("ratio", 0.5)), "target": null})
                _show_status_feedback("%s 许下了愿望…" % _species_name(player_species_id))
            "push":
                if e != null and e.dying < 0.0 and not bool(e.t.get("boss", false)):
                    var pd := (e.node.position - player.position).normalized()
                    if pd.length_squared() < 0.001:
                        pd = facing
                    e.kb = pd * float(eff.get("power", 80.0))
                    e.flee_until = run_clock + 1.0
            "yawn":
                if e.yawn_at <= 0.0 and e.status.major_effect == PokemonStatus.NONE:
                    e.yawn_at = run_clock + YAWN_SECS
                    _show_status_feedback("%s 打起了哈欠！" % str(e.t["name"]))
            "wake":
                if e.status.major_effect == PokemonStatus.SLEEP:
                    e.status.reset_major()
                    _actor_refresh_ui(e)
            "cure_self":
                if clear_major_status_item():
                    _show_status_feedback("异常状态被治愈了！")
            _:
                _extra_effect(id, eff, e)


# 冰冻之风 / 清除之雾（ResetStatsAttr）：把出招者与被打中的目标的所有能力等级清回 0（单挑口径：场上就这两方）。
func _generic_reset_stats(e: Enemy) -> void:
    player_atk_stage = 0
    player_def_stage = 0
    player_spatk_stage = 0
    player_spdef_stage = 0
    player_spd_stage = 0
    player_acc_stage = 0
    # 目标明确（清除之烟）只清它；没有目标（黑雾）清场上所有敌人。
    var targets: Array = [e] if e != null else enemies
    for t in targets:
        if t == null or t.dying >= 0.0:
            continue
        for idx in 5:
            _set_enemy_stage(t, idx, 0)
        t.acc_stage = 0
    _show_status_feedback("所有能力变化都消失了！")


func _generic_stat_change(is_self: bool, e: Enemy, stat: String, stages: int, from_foe := false) -> void:
    var target = null if is_self else e
    # 特性：单纯 = 能力变化 ×2；健壮胸肌 / 锐利目光 = 对应项不会被降低。
    for key in _ab_keys(target):
        stages *= AB.stage_multiplier(str(key))
    if stages < 0:
        for key in _ab_keys(target):
            if AB.protects_stat(str(key), stat):
                _ab_say("%s 的「%s」发动了，能力没有降低" % [_ab_owner(target), AB.name_of(str(key))])
                return
    _generic_stat_apply(is_self, e, stat, stages)
    # 不服输：被对手降低能力时攻击大幅提高（自己招式带来的降低不算）。
    if stages < 0 and (from_foe or not is_self):
        for key in _ab_keys(target):
            var dr := AB.rule(str(key))
            if dr.has("on_drop"):
                _ab_say("%s 的「%s」发动了！" % [_ab_owner(target), AB.name_of(str(key))])
                _generic_stat_apply(is_self, e, str(dr["on_drop"][0]), int(dr["on_drop"][1]))


func _ab_owner(unit) -> String:
    return _species_name(player_species_id) if unit == null else str(unit.t.get("name", "敌人"))


# 说一句特性提示：同一时间不刷屏（1.5 秒一句）。abilities.gd 里有真正的实现。
func _ab_say(_text: String) -> void:
    pass


func _generic_stat_apply(is_self: bool, e: Enemy, stat: String, stages: int) -> void:
    if is_self:
        match stat:
            "atk":
                player_atk_stage = clampi(player_atk_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "def":
                player_def_stage = clampi(player_def_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "spatk":
                player_spatk_stage = clampi(player_spatk_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "spdef":
                player_spdef_stage = clampi(player_spdef_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "spd":
                player_spd_stage = clampi(player_spd_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "acc":
                player_acc_stage = clampi(player_acc_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
            "eva":
                player_eva_stage = clampi(player_eva_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)   # 影子分身 / 变小
        _touch_stage_timer(stat)
        return
    if stat == "acc":
        e.acc_stage = clampi(e.acc_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)
        return
    if stat == "eva":
        e.eva_stage = clampi(e.eva_stage + stages, STAT_STAGE_MIN, STAT_STAGE_MAX)   # 甜甜香气 / 清除浓雾
        return
    var idx := int(GEN2_STAGE_INDEX[stat])
    _set_enemy_stage(e, idx, clampi(_enemy_stage(e, idx) + stages, STAT_STAGE_MIN, STAT_STAGE_MAX))


# 状态附加：走 combat.gd 已验收的真实 actor 入口（主要异常 / 混乱），并给 HUD 反馈。
func _generic_status(id: String, e: Enemy, status: String) -> void:
    # 薄雾场地：地面上的目标状态异常上不去；电气场地：地面上的目标睡不着。
    if e != null and _grounded(_enemy_types(e)) and (terrain == "misty" or (terrain == "electric" and status == "sleep")):
        _show_status_feedback("%s 被场地保护着，没有效果" % str(e.t["name"]))
        return
    var result := ""
    if status == "confusion":
        result = _actor_apply_confusion_status(e)
    else:
        result = _actor_apply_major_status(e, int(GEN2_STATUS[status]), status == "toxic")
    _show_status_feedback(_status_feedback(str(e.t["name"]), str(GEN2_STATUS_NAME[status]), result))


# 原 RecoilAttr（useHp=false）：反伤 = game/pokemon_recoil.gd::amount(实际造成伤害, 比例)，每次命中只反一次，
# 直接扣玩家 HP（不进 `_hurt`：不再乘 debug_power、不减 DEF / STAB / 属性 / 烧伤；攻击侧 debug 已在 `_damage`）。
# 玩家 HP 钳到 0；死亡仍由 main._process 的 `_settle("dead")` 走已有结算，同一 `_attack_tick` 里后续招被
# `_can_act`（player_hp <= 0）挡住不再释放。击杀（含最终头目）已在 `_damage → _kill` 里按幂等结算，
# 反伤致死时死亡结算优先（`_boss_reward` 见 dead 即不再胜利），不改头目规则。
var recoil_cap_ratio := 0.05
var recoil_never_kills := true   # 老检查要测原版“反伤能致死”时关掉   # 测原版反伤公式的老检查设成 1.0（= 不封顶）


func _apply_recoil(id: String, dealt: float) -> void:
    var ratio := float(MOVES.MOVES[id].get("recoil", 0.0))
    if ratio <= 0.0 or dealt <= 0.0 or dead or player_hp <= 0.0:
        return
    var loss := PokemonRecoil.amount(dealt, ratio)
    if recoil_cap_ratio < 1.0:   # ≥ 1 = 不封顶（测原版公式的老检查用）
        loss = mini(loss, maxi(1, int(ceilf(float(stats.value("hp_max")) * recoil_cap_ratio))))
    if recoil_never_kills and player_hp > 1.0:
        loss = mini(loss, int(ceilf(player_hp)) - 1)
    var recoil_hp := player_hp
    if loss <= 0 or not _player_dot(loss):
        return
    _report_hit("dot", "反伤（%s）" % str(MOVES.MOVES[id]["name"]), 0, recoil_hp)
    _flash_sprite(player.get_child(0), Color(1, 0.4, 0.35))
    sfx.hurt()


# 原版 crash damage（MissEffectAttr / NoEffectAttr(crashDamageFunc)，飞膝踢 / 飞踢 / 下压踢）：
# 打空或打中但属性免疫（“没有效果”）时，出招的玩家自己掉最大 HP 的一半（floor，至少 1）；打中并造成伤害不掉。
# 扣血走已验收的 `_player_dot`（同一入口：0 伤害 / 已倒下 / 魔法防守挡下都在里面判），死亡仍由 main 的
# `_settle("dead")` 结算；HUD 反馈照旁边现成的 `_show_status_feedback` 写法。
func _apply_crash(id: String) -> void:
    if not bool(MOVES.MOVES[id].get("crash", false)) or dead or player_hp <= 0.0:
        return
    var loss := maxi(int(floorf(stats.value("hp_max") / 2.0)), 1)
    if not _player_dot(loss):
        return
    _show_status_feedback("%s 摔到地上了！" % _species_name(player_species_id))


# 变硬 / 变圆：原作 StatChangeAttr 给自身 DEF +1（SelfStatusMove）。玩家临时防御等级每次 +1、钳到 +6；
# 已到 +6 时不再无意义重播原动画（仍算一次释放并进冷却）。不写基础六维 player_stats。
# 原素材 user / target 都是自己。move_id 只决定播哪份原动画（旧无参 `_cast_harden()` 仍等价变硬），
# 两招共享同一 player_def_stage / 同一受伤公式，不新建能力等级框架或第二套 DEF。
func _cast_harden(move_id := "harden") -> void:
    if move_id == "defense_curl":
        player_curled_until = run_clock + CURL_TTL
    if player_def_stage < STAT_STAGE_MAX:
        player_def_stage += 1
        _touch_stage_timer("def")
        _rogue().play(move_id, player, player)


# 吐丝：每个目标独立掷一次命中骰（原作 ALL_NEAR_ENEMIES 没有整次释放的单一命中判定），
# 命中后速度等级 -2、每敌人独立累加并钳到 -6，整场保留。
# 群体动画用各受击目标的原 19 帧；音频只由第一个命中目标播音，其余目标只播原图层，避免叠声。
func _cast_string_shot(candidates: Array[Enemy]) -> void:
    var first_sound := true
    for e in candidates:
        if e.dying >= 0.0:
            continue
        if not _hit("string_shot", e):
            continue
        _rogue().play("string_shot", player, e.node, first_sound)
        first_sound = false
        e.speed_stage = clampi(e.speed_stage - 2, STAT_STAGE_MIN, STAT_STAGE_MAX)


# 瞪眼 / 摇尾巴：原作 `new pe(...,100,30,chance,0,1).attr(Se,le.DEF,-1).target(6)`。
# 每个范围内活目标独立掷一次 1..100 命中骰（accuracy 100），命中后该目标 DEF 能力等级 -1、
# 每敌人独立累加并钳到 [-6,6]，整场存活期间保留；0 直接伤害，不改 ATK / SPD / HP / 基础六维，
# 也不硬写玩家防御（玩家临时防御等级只由变硬写）。变化招不套「一般打幽灵的伤害免疫」：
# `_move_type_immune` 对变化招返回 false，所以打幽灵仍降 DEF。
# 原构造第 5 参 chance（瞪眼 100 / 摇尾巴 -1）只作资料记录，不凭空补一轮随机概率。
# 群体 FX 每命中目标一份；音频沿用吐丝语义，只由第一个命中目标播音，其余只播原图层，不叠声。
func _cast_stat_drop(candidates: Array[Enemy], id: String) -> void:
    var first_sound := true
    for e in candidates:
        if e.dying >= 0.0:
            continue
        if not _hit(id, e):
            continue
        _rogue().play(id, player, e.node, first_sound)
        first_sound = false
        e.def_stage = clampi(e.def_stage - 1, STAT_STAGE_MIN, STAT_STAGE_MAX)


# 叫声：原作 `new pe(a.GROWL,S.NORMAL,100,40,-1,0,1).attr(Se,le.ATK,-1).soundBased().target(6)`。
# 每个范围内活目标独立掷一次 1..100 命中骰（accuracy 100），命中后该目标 ATK 能力等级 -1、
# 每敌人独立累加并钳到 [-6,6]，整场存活期间保留；0 直接伤害，不降 DEF / SPD / SPATK、
# 不改基础六维、也不硬写玩家攻击。变化招不套「一般打幽灵的伤害免疫」，所以打幽灵仍降 ATK。
# 群体 FX 每命中目标一份；音频沿用吐丝语义，只由第一个命中目标播音（播的是玩家物种原 cry）。
func _cast_attack_drop(candidates: Array[Enemy]) -> void:
    var first_sound := true
    for e in candidates:
        if e.dying >= 0.0:
            continue
        if not _hit("growl", e):
            continue
        _rogue().play("growl", player, e.node, first_sound, player_species_id)
        first_sound = false
        e.atk_stage = clampi(e.atk_stage - 1, STAT_STAGE_MIN, STAT_STAGE_MAX)


# 泼沙：原作 `new pe(a.SAND_ATTACK,S.GROUND,100,15,-1,0,1).attr(Se,le.ACC,-1)`。
# 最近一个活目标（target 3，不是群圈），一次 1..100 命中骰（accuracy 100）；命中后该目标
# ACC（命中）能力阶段 -1、每敌人独立累加并钳 [-6,6]，整场存活期间保留；0 直接伤害、无击退、
# 不降 SPD / DEF / ATK、不改基础六维、不当群体。变化招不套「地面打飞行的伤害免疫」：
# `_cast_accuracy_drop` 根本不走 `_move_type_immune`，对飞行敌人也照常降命中。
# 原两变体动画 / 帧 0 原声由 `_play_move_fx` 走唯一 rogue_moves 播放器，不新建第二套演出。
func _cast_accuracy_drop(e: Enemy) -> void:
    if not _hit("sand_attack", e):
        return
    _play_move_fx("sand_attack", e)
    e.acc_stage = clampi(e.acc_stage - 1, STAT_STAGE_MIN, STAT_STAGE_MAX)


# 旧吐丝飞行丝弹逻辑已随本项删除；保留空函数仅供旧清理路径 / 外部调用无副作用。
func _silk_tick(_delta: float) -> void:
    pass


# ================= 第二批变化招（2026-10-20，用户：剩下的招式做了吧）=================
# 照原版效果，回合制改成实时：原版“5 回合”的场地效果按天气那 20 秒（WEATHER_SECS），每回合扣血按每秒。
# 单挑口径：原版“对手 / 我方全体”都是“被打中的这只 / 玩家自己”；队友 / 换人 / 道具 / 性别 / PP 那类招不在这里（封着）。
const PERISH_SECS := 3.0          # 灭亡之歌：原版 3 回合后倒下（这里 3 秒；头目不吃，照原版 failOnBoss）
const DESTINY_SECS := 5.0         # 同命：原版持续到自己下次出招，这里 5 秒
# 陷阱半径 = 铺下那一刻的标准攻击圈（_std_range），存在每个陷阱的 "r" 里
const HAZARD_SECS := 20.0
const HAZARD_COLOR := {"spikes": Color(0.55, 0.5, 0.45, 0.55), "stealth_rock": Color(0.6, 0.5, 0.3, 0.55), "toxic_spikes": Color(0.6, 0.3, 0.75, 0.55), "sticky_web": Color(0.85, 0.85, 0.85, 0.45)}
const HAZARD_NAME := {"spikes": "撒菱", "stealth_rock": "隐形岩", "toxic_spikes": "毒菱", "sticky_web": "黏黏网"}
const SIDE_TEXT := {"safeguard": "被神秘的帷幕包围了！", "mist": "被白雾包围了！", "lucky_chant": "念起了幸运咒语！", "water_sport": "火的威力减弱了！", "mud_sport": "电的威力减弱了！", "gravity": "重力变强了！"}


func _extra_effect(id: String, eff: Dictionary, e: Enemy) -> void:
    var me := _species_name(player_species_id)
    match str(eff["kind"]):
        "curse":
            # 幽灵系：削自己一半最大 HP，让对方每秒掉 1/4（原 CurseAttr）；不是幽灵系：攻击 / 防御 +1、速度 -1
            if _player_types().has("幽灵"):
                if e == null or e.dying >= 0.0:
                    return
                player_hp = maxf(1.0, player_hp - floorf(stats.value("hp_max") / 2.0))
                e.cursed_until = run_clock + 1.0e9
                e.curse_next = run_clock + 1.0
                _show_status_feedback("%s 削减体力，诅咒了 %s！" % [me, str(e.t["name"])])
            else:
                _generic_stat_change(true, null, "atk", 1)
                _generic_stat_change(true, null, "def", 1)
                _generic_stat_change(true, null, "spd", -1)
        "stockpile":
            if stockpile < 3:
                stockpile += 1
                _generic_stat_change(true, null, "def", 1)
                _generic_stat_change(true, null, "spdef", 1)
                _show_status_feedback("%s 蓄力了 %d 次！" % [me, stockpile])
        "swallow":
            if stockpile > 0:
                var ratio: float = [0.25, 0.5, 1.0][stockpile - 1]
                heal(float(maxi(int(floorf(stats.value("hp_max") * ratio)), 1)))
                _generic_stat_change(true, null, "def", -stockpile)
                _generic_stat_change(true, null, "spdef", -stockpile)
                stockpile = 0
                _show_status_feedback("%s 吞下了蓄的力！" % me)
        "spit_up_reset":
            if stockpile > 0:
                _generic_stat_change(true, null, "def", -stockpile)
                _generic_stat_change(true, null, "spdef", -stockpile)
                stockpile = 0
        "side":
            var which := str(eff["side"])
            set(which + "_until", run_clock + WEATHER_SECS)
            _show_status_feedback(str(SIDE_TEXT.get(which, "")))
        "laser_focus":
            laser_focus_next = true
            _show_status_feedback("%s 磨砺了精神，下一招必定会心！" % me)
        "cut_hp_boost":
            # 魂舞烈音爆（1/3，全部 +1）/ 甩肉（1/2，攻击 特攻 速度 +2）：HP 不够就失败
            var cost := floorf(stats.value("hp_max") * float(eff["cost"]))
            if player_hp > cost:
                player_hp -= cost
                for st in eff["stats"]:
                    _generic_stat_change(true, null, str(st), int(eff["stages"]))
        "strength_sap":
            if e == null or e.dying >= 0.0:
                return
            var atk := floorf(float(e.t["stats"][1]) * stat_stage_multiplier(_enemy_stage(e, 0)))
            heal(maxf(1.0, atk))
            _generic_stat_change(false, e, "atk", -1)
        "pain_split":
            if e == null or e.dying >= 0.0 or bool(e.t.get("boss", false)):
                return
            var avg := floorf((player_hp + e.hp) / 2.0)
            player_hp = minf(stats.value("hp_max"), avg)
            e.hp = minf(_enemy_max_hp(e), avg)
            _show_status_feedback("%s 和 %s 分担了痛楚！" % [me, str(e.t["name"])])
        "psych_up":
            if e == null:
                return
            player_atk_stage = _enemy_stage(e, 0)
            player_def_stage = _enemy_stage(e, 1)
            player_spatk_stage = _enemy_stage(e, 2)
            player_spdef_stage = _enemy_stage(e, 3)
            player_spd_stage = _enemy_stage(e, 4)
            for st in ["atk", "def", "spatk", "spdef", "spd"]:
                _touch_stage_timer(st)
        "swap_stages":
            # 力量互换（攻击 / 特攻）、防守互换（防御 / 特防）：和对方交换能力等级
            if e == null:
                return
            for st in eff["stats"]:
                var idx := int(GEN2_STAGE_INDEX[str(st)])
                var mine := _player_stage_of(str(st))
                var theirs := _enemy_stage(e, idx)
                _set_enemy_stage(e, idx, mine)
                _generic_stat_apply(true, null, str(st), theirs - mine)
        "topsy_turvy":
            if e == null:
                return
            for idx in 5:
                _set_enemy_stage(e, idx, -_enemy_stage(e, idx))
            _show_status_feedback("%s 的能力变化颠倒了！" % str(e.t["name"]))
        "acupressure":
            var pick: String = ["atk", "def", "spatk", "spdef", "spd", "acc"][_effect_pick(6)]
            _generic_stat_change(true, null, pick, 2)
        "perish":
            for t in enemies:
                if t.dying < 0.0 and t.perish_at <= 0.0 and not bool(t.t.get("boss", false)) and t.node != null and t.node.position.distance_to(player.position) <= _std_range():
                    t.perish_at = run_clock + PERISH_SECS
            _show_status_feedback("听到灭亡之歌的宝可梦 3 秒后会倒下！")
        "destiny_bond":
            destiny_bond_until = run_clock + DESTINY_SECS
            _show_status_feedback("%s 想和对手同归于尽！" % me)
        "nightmare":
            if e != null and e.status.major_effect == PokemonStatus.SLEEP:
                e.nightmare = true
                _show_status_feedback("%s 开始做恶梦了！" % str(e.t["name"]))
        "psycho_shift":
            if e != null and player_status != null and player_status.has_major() and not e.status.has_major():
                var eff_id := player_status.major_effect
                if _actor_apply_major_status(e, eff_id) == "ok":
                    clear_major_status_item()
                    _show_status_feedback("%s 把异常转移给了 %s！" % [me, str(e.t["name"])])
        "eat_berry":
            if int(berries.get("SITRUS", 0)) > 0:
                berries["SITRUS"] = int(berries["SITRUS"]) - 1
                heal_item(PokemonBerries.sitrus_amount(maxf(1.0, stats.value("hp_max"))))
                _persist_berries()
                _berry_feedback("文柚果", "回复体力")
            elif int(berries.get("LUM", 0)) > 0 and player_status != null and (player_status.has_major() or player_status.has_confusion()):
                berries["LUM"] = int(berries["LUM"]) - 1
                clear_major_status_item()
                _persist_berries()
                _berry_feedback("木子果", "异常解除")
        "change_type":
            if e != null:
                e.type_override = [str(eff["type"])]
                _show_status_feedback("%s 变成了%s属性！" % [str(e.t["name"]), str(eff["type"])])
        "add_type":
            if e != null:
                var ts: Array = _enemy_types(e).duplicate()
                if not ts.has(str(eff["type"])):
                    ts.append(str(eff["type"]))
                e.type_override = ts
                _show_status_feedback("%s 多了%s属性！" % [str(e.t["name"]), str(eff["type"])])
        "set_ability":
            if e != null and not bool(e.t.get("boss", false)):
                e.ability = str(eff["ability"])
                if str(eff["ability"]) == "":
                    e.passive = ""   # 胃液：特性失效
                _show_status_feedback("%s 的特性变了！" % str(e.t["name"]))
        "copy_ability":
            # 扮演 / 涂鸦：自己变成对方的特性；特性互换：互换
            if e != null and str(e.ability) != "":
                var mine2 := player_ability
                player_ability = str(e.ability)
                if bool(eff.get("swap", false)):
                    e.ability = mine2
                _show_status_feedback("%s 的特性变成了「%s」！" % [me, AB.name_of(player_ability)])
        "give_ability":
            if e != null and player_ability != "":
                e.ability = player_ability
        "clear_field":
            # 清除浓雾：吹散雾、场地和陷阱
            if weather == "fog":
                _set_weather("")
            _set_terrain("")
            _clear_hazards()
        "hazard":
            _place_hazard(str(eff["hazard"]))


# 每帧（_field_tick 开头）：诅咒 / 恶梦掉血、灭亡之歌倒计时、陷阱区踩中。
func _extra_tick() -> void:
    for e in enemies:
        if e.dying >= 0.0:
            continue
        if e.cursed_until > run_clock and run_clock >= e.curse_next:
            e.curse_next += 1.0
            _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / 4.0)), 1))
        if e.nightmare:
            if e.status.major_effect != PokemonStatus.SLEEP:
                e.nightmare = false
            elif run_clock >= e.curse_next:
                e.curse_next = run_clock + 1.0
                _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / 4.0)), 1))
        if e.perish_at > 0.0 and run_clock >= e.perish_at and e.dying < 0.0:
            e.perish_at = 0.0
            _enemy_status_damage(e, int(ceilf(e.hp)) + 1)
    _hazard_tick()


# ===== 撒菱 / 隐形岩 / 毒菱 / 黏黏网：原版撒在对方场地上，换上场的宝可梦踩到；这里是在玩家脚下铺一圈陷阱区，
# 敌人走进去踩一次（每只每个陷阱区一次），20 秒消失。撒菱 1/8、隐形岩 1/8 × 岩石属性克制、毒菱中毒、黏黏网速度 -1。
func _place_hazard(kind: String) -> void:
    hazard_seq += 1
    var disc := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    var hr := _std_range()
    mesh.top_radius = hr
    mesh.bottom_radius = hr
    mesh.height = 0.02
    disc.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = HAZARD_COLOR.get(kind, Color(0.5, 0.5, 0.5, 0.5))
    disc.material_override = mat
    disc.position = Vector3(player.position.x, 0.03, player.position.z)
    add_child(disc)
    hazards.append({"id": hazard_seq, "kind": kind, "pos": player.position, "until": run_clock + HAZARD_SECS, "node": disc, "r": hr})
    _show_status_feedback("%s 在脚下撒了%s！" % [_species_name(player_species_id), str(HAZARD_NAME.get(kind, kind))])


func _clear_hazards() -> void:
    for h: Dictionary in hazards:
        if h["node"] != null and is_instance_valid(h["node"]):
            h["node"].queue_free()
    hazards.clear()


func _hazard_tick() -> void:
    if hazards.is_empty():
        return
    var keep: Array = []
    for h: Dictionary in hazards:
        if run_clock >= float(h["until"]):
            if h["node"] != null and is_instance_valid(h["node"]):
                h["node"].queue_free()
            continue
        keep.append(h)
        var center: Vector3 = h["pos"]
        for e in enemies:
            if e.dying >= 0.0 or e.node == null or e.hazard_hit.has(h["id"]):
                continue
            var d := Vector2(e.node.position.x - center.x, e.node.position.z - center.z)
            if d.length() > float(h.get("r", _std_range())):
                continue
            e.hazard_hit[h["id"]] = true
            _hazard_hit(e, str(h["kind"]))
    hazards = keep


func _hazard_hit(e: Enemy, kind: String) -> void:
    var types := _enemy_types(e)
    match kind:
        "spikes":
            if not types.has("飞行"):
                _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / 8.0)), 1))
        "stealth_rock":
            var mult := _effectiveness("岩石", types)
            _enemy_status_damage(e, maxi(int(floorf(_enemy_max_hp(e) / 8.0 * mult)), 1))
        "toxic_spikes":
            if not types.has("飞行") and not types.has("毒") and not types.has("钢"):
                _actor_apply_major_status(e, PokemonStatus.POISON)
        "sticky_web":
            if not types.has("飞行"):
                _generic_stat_change(false, e, "spd", -1)


# 同命：被打倒时，打倒你的那只一起倒下（combat.gd 的 _hurt 致命时调）。
func _destiny_bond_trigger(source) -> void:
    if run_clock < destiny_bond_until and source != null and source is Enemy and source.dying < 0.0 and not bool(source.t.get("boss", false)):
        destiny_bond_until = 0.0
        _enemy_status_damage(source, int(ceilf(source.hp)) + 1)
        _show_status_feedback("%s 和对手同归于尽了！" % _species_name(player_species_id))
