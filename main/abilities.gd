extends "res://main/arts.gd"
# 特性（用户 2026-10-18）的战斗接线：规则在 game/pokemon_abilities.gd（纯计算），这里把它们接到战斗里。
# 生产链：state → combat → arts → abilities → enemies → cards → meta_flow → main。
#   伤害类（出招 / 挨打倍率、属性吸收、狙击手…）  覆写 _player_move_damage / _enemy_move_damage，在原公式的最终伤害上乘。
#   状态 / 能力保护、命中、速度、天气·场地抑制       内联在 combat.gd / arts.gd 里（它们只读 AB 规则，不需要这里的方法）。
#   周期类（加速 / 心情不定 / 冰冻之躯 / 湿润之躯 / 蜕皮）、威吓·场地制造者（敌人第一次靠近时触发）  _ab_tick。
#   事件类（自信过度 / 胆怯 / 愤怒穴位 / 接触反击 / 同步）  覆写 combat.gd 里的 _ab_* 空钩子。
# 本作的取舍都写在 AB.RULES 旁边；没有对应系统的特性（换人 / 队友 / 道具 / 性别）不假装做了。

const AB_SAY_GAP_MS := 1500
const AB_NEAR := 12.0            # 敌人进入这个距离才算“出场”：威吓 / 场地制造者此时触发
# 威吓是“范围”不是全局（用户 2026-10-18：“威吓这种我觉得做成范围比较好”）：敌人走进这个距离（米）才吃一次威吓 / 才威吓玩家，
# 远处没走近的怪不受影响。比 AB_NEAR 小得多，和玩家的攻击圈（最远约 4 米）同一量级。
const AB_INTIMIDATE_RANGE := 6.0
const AB_INTIMIDATE_GAP := 4.0   # 敌人威吓玩家的最小间隔（秒），免得一群怪把攻击等级一次压到底
const AB_TICK_GAP := 0.5
const AB_STAT_NAMES := {"atk": "攻击", "def": "防御", "spatk": "特攻", "spdef": "特防", "spd": "速度", "acc": "命中"}
const AB_TERRAIN_NAMES := {"electric": "电气场地", "grassy": "青草场地", "misty": "薄雾场地", "psychic": "精神场地"}

var _ab_say_ms := 0
var _ab_timers: Dictionary = {}          # 特性 key -> 下一次周期结算时刻（run_clock 秒）
var _ab_intimidate_next := 0.0
var ab_log: Array = []                    # 触发记录（检查用）：每条是展示出去的那句话


func _ab_say(text: String) -> void:
    ab_log.append(text)
    if ab_log.size() > 40:
        ab_log.pop_front()
    var now := Time.get_ticks_msec()
    if now - _ab_say_ms < AB_SAY_GAP_MS:
        return
    _ab_say_ms = now
    _show_status_feedback(text)


# 开新局：清掉周期计时和一次性状态。
func _ab_reset_run() -> void:
    _ab_timers = {}
    _ab_intimidate_next = 0.0
    player_fire_boost_until = 0.0
    _ab_say_ms = 0
    ab_log = []


# 玩家的特性 / 被动按“开局那只”的栏位选择取（进化沿用栏位）；隐藏栏要抓到过隐藏特性才开放。
func _ab_refresh_player() -> void:
    var root := player_train_key if player_train_key > 0 else AB.root_of(player_species_id)
    # 融合：特性用对象那只的，栏位也按对象那一系选的（选宠页融合时按 E 换的就是它，用户 2026-10-22）
    # 栏位和隐藏特性都记在这一系最前面那只名下（选宠页 / 抓宠都这么存）；皮卡丘开局要按皮丘读（2026-10-22 审查发现）
    var ab_root := AB.root_of(player_fusion_id) if player_fusion_id > 0 else AB.root_of(root)
    var slot := 0
    if points_wallet != null:
        slot = points_wallet.ability_slot_for(ab_root)
        if slot == 2 and not points_wallet.has_hidden_ability(ab_root):
            slot = 0
    player_ability_slot = slot
    player_ability = AB.slot_ability(player_fusion_id if player_fusion_id > 0 else player_species_id, slot)   # 融合：用对象那只的特性
    if not player_special_form.is_empty() and str(player_special_form.get("kind", "")) == "mega":
        var fa: Array = player_special_form.get("abilities", [])
        if not fa.is_empty() and str(fa[0]) != "NONE":
            player_ability = str(fa[0])   # 超级进化：特性换成超级形态的（原版）
    player_passive = AB.passive_of(player_species_id)
    # 被动：花物种糖果解锁（原版），选宠页可关；按起始种记（用户 2026-10-20）
    var candy_root := AB.root_of(root)
    player_passive_on = player_passive != "" and points_wallet != null and points_wallet.is_passive_on(candy_root)


# 左上角“这局带着什么”的清单（ui/hud.gd set_effects）：闪光加成、三种镜片的实际等级（含闪光加级）、被动。
const SHINY_TIER_LABEL := ["闪光", "蓝闪", "红闪"]
const SHINY_TIER_STYLE := ["summary_gold", "summary_blue", "summary_red"]


func _run_effects() -> Array:
    var out: Array = []
    if not player_special_form.is_empty():
        var sf_icon := str(player_special_form.get("item", "")).to_lower()
        out.append({"icon": sf_icon, "style": "summary_gold", "text": "%s（%s，这一局一直保持；再进化会变回去）" % [
            SpecialForms.display_name(_species_name(player_species_id), player_special_form), SpecialForms.item_name(player_special_form)]})
    var coin_owned := int(points_wallet.charm_stacks.get("AMULET_COIN", 0)) if points_wallet != null else 0
    if coin_owned > 0:   # 护身金币：点数倍率，点图标调用几层（用户 2026-10-23）
        var coin_on := _global_charm("AMULET_COIN")
        out.append({"icon": "amulet_coin", "badge": "×%.1f" % (1.0 + 0.2 * coin_on), "action": "amulet",
            "style": "summary_gold" if coin_on > 0 else "window",
            "text": "护身金币：击杀点数 / 金珠 ×%.1f（买了 %d 层，这局用 %d 层）\n左键 +1 层，右键 -1 层" % [1.0 + 0.2 * coin_on, coin_owned, coin_on]})
    if player_fusion_id > 0:   # 融合（用户 2026-10-22：融合要标识出来）
        out.append({"icon": "dna_splicers", "text": "融合：%s + %s（外观 / 经验曲线用前者，特性用后者，六维取平均）" % [_species_name(player_species_id), _species_name(player_fusion_id)]})
    var tier := player_shiny_variant
    var bonus := _shiny_lens_bonus()   # 融合时两只闪光加级相加
    if tier >= 0:
        out.append({"icon": "shiny_charm", "style": SHINY_TIER_STYLE[tier], "badge": "+%d" % bonus,
            "text": "%s：最大血量 +%d%%，镜片 +%d 级" % [SHINY_TIER_LABEL[tier], [10, 15, 20][tier], bonus]})
    var bought := {"support": lens_support, "attack": lens_attack, "capture": lens_capture}
    var icons := {"support": "wide_lens", "attack": "scope_lens", "capture": "catching_charm"}
    for kind: String in PokemonLens.KINDS:
        var lv := PokemonLens.effective_level_bonus(int(bought[kind]), bonus)
        if lv <= 0:
            continue
        var what := ""
        match kind:
            "support":
                what = "变化招多打 %d 个" % lv
            "attack":
                what = "伤害招多打 %d 个，伤害 ×%s" % [lv, str(PokemonLens.damage_mult("attack", lv))]
            "capture":
                what = "捕获率 ×%s" % str(PokemonLens.capture_mult(lv))
        var src := "" if bonus <= 0 or int(bought[kind]) <= 0 else "（买 %d + 闪光 %d）" % [int(bought[kind]), mini(bonus, lv - int(bought[kind]))]
        out.append({"icon": icons[kind], "badge": str(lv), "text": "%s Lv%d%s：%s" % [PokemonLens.NAMES[kind], lv, src, what]})
    # 携带道具：每样一个图标，角标 = 个数（悬停看效果）
    for it: String in run_held:
        var hn := int(run_held[it])
        if hn > 0:
            out.append({"icon": HeldItems.icon_of(it), "badge": str(hn), "text": "%s ×%d：%s" % [HeldItems.name_of(it), hn, HeldItems.desc_of(it, hn)]})
    if player_passive_on and player_passive != "":
        out.append({"icon": "ability_capsule", "style": "summary_gold", "text": "被动：%s" % AB.name_of(player_passive)})
    return out


# ================= 伤害 =================
func _ab_ctx(id: String, attacker, defender_types: Array, attacker_types: Array) -> Dictionary:
    var m: Dictionary = MOVES.MOVES[id]
    var mt := str(m["type"])
    var st: PokemonStatus = _actor_status(attacker)
    var eff := _effectiveness(mt, defender_types)
    return {
        "move_id": id, "move_type": mt, "category": str(m["category"]),
        "power": _move_power(m), "eff": eff,
        "contact": RogueFX.is_contact_move(id),
        "stab": attacker_types.has(mt),
        "status": st != null and st.has_major(),
        "burned": st != null and st.major_effect == PokemonStatus.BURN,
    }


func _ab_stage_factor(stage: int) -> float:
    return stat_stage_multiplier(stage)


func _player_move_damage(id: String, target: Enemy) -> float:
    _last_crit = false
    var base := super._player_move_damage(id, target)
    if base <= 0.0:
        return base
    var m: Dictionary = MOVES.MOVES[id]
    var cat := str(m["category"])
    if cat != "物理" and cat != "特殊":
        return base
    var mt := str(m["type"])
    # 对手属性吸收 / 免疫（飘浮 / 蓄电 / 储水 / 避雷针 / 食草 / 引火）
    for key in _ab_keys(target):
        var kind := AB.absorb_kind(str(key), mt)
        if kind != "":
            _ab_absorb(target, str(key), kind)
            return 0.0
        if AB.wonder_guard(str(key)) and _effectiveness(mt, _exposed_types(mt, _enemy_types(target), target)) < 2.0:
            _ab_say("%s 的「神奇守护」让攻击没有效果" % _ab_owner(target))
            return 0.0
    var ctx := _ab_ctx(id, null, _enemy_types(target), _player_types())
    var mult := 1.0
    for key in _ab_keys(null):
        mult *= AB.attack_mult(str(key), ctx)
        if _last_crit:
            mult *= AB.crit_mult(str(key))
        if AB.ignores_stages(str(key)):
            # 纯朴：无视对手的能力等级（对手的防御等级抵消掉）
            mult *= _ab_stage_factor(target.def_stage if cat == "物理" else target.spdef_stage)
    for key in _ab_keys(target):
        mult *= AB.defend_mult(str(key), ctx)
        if AB.ignores_stages(str(key)):
            mult /= _ab_stage_factor(player_atk_stage if cat == "物理" else player_spatk_stage)
    if mt == "火" and run_clock < player_fire_boost_until:
        mult *= 1.5
    return base * mult if mult == 1.0 else maxf(floorf(base * mult), 1.0)


func _enemy_move_damage(e: Enemy) -> float:
    var base := super._enemy_move_damage(e)
    if base <= 0.0:
        return base
    var m: Dictionary = MOVES.MOVES[e.cur_move]
    var cat := str(m["category"])
    var mt := str(m["type"])
    for key in _ab_keys(null):
        var kind := AB.absorb_kind(str(key), mt)
        if kind != "":
            _ab_absorb(null, str(key), kind)
            return 0.0
        if AB.wonder_guard(str(key)) and cat != "变化" and _effectiveness(mt, _player_types()) < 2.0:
            _ab_say("%s 的「神奇守护」让攻击没有效果" % _ab_owner(null))
            return 0.0
    var ctx := _ab_ctx(e.cur_move, e, _player_types(), _enemy_types(e))
    var mult := 1.0
    for key in _ab_keys(e):
        mult *= AB.attack_mult(str(key), ctx)
        if _last_crit:
            mult *= AB.crit_mult(str(key))
        if AB.ignores_stages(str(key)):
            mult *= _ab_stage_factor(player_def_stage if cat == "物理" else player_spdef_stage)
    for key in _ab_keys(null):
        mult *= AB.defend_mult(str(key), ctx)
        if AB.ignores_stages(str(key)):
            mult /= _ab_stage_factor(e.atk_stage if cat == "物理" else e.spatk_stage)
    return base if mult == 1.0 else maxf(floorf(base * mult), 1.0)


# 属性吸收：蓄电 / 储水回血，避雷针 / 食草提能力，引火加火招，飘浮只是免疫。unit == null = 玩家。
func _ab_absorb(unit, key: String, kind: String) -> void:
    var who := _ab_owner(unit)
    var ab_name := AB.name_of(key)
    match kind:
        "heal":
            if unit == null:
                heal(float(maxi(int(floorf(stats.value("hp_max") / 4.0)), 1)))
            elif _enemy_can_heal(unit):
                unit.hp = minf(_enemy_max_hp(unit), unit.hp + float(maxi(int(floorf(_enemy_max_hp(unit) / 4.0)), 1)))
            _ab_say("%s 的「%s」吸收了攻击，回复了体力！" % [who, ab_name])
        "spatk", "atk":
            _generic_stat_change(unit == null, unit, kind, 1)
            _ab_say("%s 的「%s」吸收了攻击，%s提高了！" % [who, ab_name, AB_STAT_NAMES[kind]])
        "fire_boost":
            if unit == null:
                player_fire_boost_until = run_clock + 20.0
            _ab_say("%s 的「%s」吸收了火焰！" % [who, ab_name])
        _:
            _ab_say("%s 的「%s」让攻击没有效果" % [who, ab_name])


# ================= 事件 =================
func _ab_after_hurt(_lost: float, source) -> void:
    if source == null or not ("cur_move" in source) or not MOVES.MOVES.has(source.cur_move):
        return
    var mt := str(MOVES.MOVES[source.cur_move]["type"])
    for key in _ab_keys(null):
        var r := AB.rule(str(key))
        if r.has("rattled") and (mt == "虫" or mt == "恶" or mt == "幽灵"):
            _ab_say("%s 的「%s」发动了，速度提高！" % [_ab_owner(null), AB.name_of(str(key))])
            _generic_stat_change(true, null, "spd", 1)
        if r.has("on_crit") and _last_crit:
            _ab_say("%s 的「%s」发动了，攻击提到最大！" % [_ab_owner(null), AB.name_of(str(key))])
            _generic_stat_change(true, null, str(r["on_crit"][0]), int(r["on_crit"][1]))
        if source.dying < 0.0 and RogueFX.is_contact_move(str(source.cur_move)):
            _ab_contact_retaliate(str(key), source, null)


# 玩家打中了敌人（带招式 id）：对方的接触反击特性（静电 / 火焰之躯 / 铁刺）。
func _ab_on_enemy_damaged(e: Enemy, _applied: float, move: String) -> void:
    if not RogueFX.is_contact_move(move):
        return
    # 对方的接触特性每只每秒最多触发一次（原版“每次出手一次”，本作群攻 × 每个目标 × 每次命中都触发被放大几十倍（2026-10-22 审查，用户让我定：每秒最多结算一次））
    if run_clock < e.contact_ready_at:
        return
    e.contact_ready_at = run_clock + 1.0
    for key in _ab_keys(e):
        _ab_contact_retaliate(str(key), null, e)


# 接触反击：holder == 持有特性的一方（null = 玩家），victim_enemy / holder_enemy 二选一（谁被反击）。
func _ab_contact_retaliate(key: String, attacker_enemy, holder_enemy) -> void:
    var fx := AB.contact_effect(key)
    if fx.is_empty():
        return
    var holder = holder_enemy            # null = 玩家持有
    var victim = attacker_enemy          # null = 被反击的是玩家
    if fx.has("status") and randi_range(1, 100) <= int(fx["chance"]):
        var sname := str(fx["status"])
        if sname == "effect_spore":
            # 孢子：草系 / 防尘免疫（原版），否则三种里随机一个
            var vtypes: Array = _player_types() if victim == null else _enemy_types(victim)
            if vtypes.has("草") or _ab_has(victim, "OVERCOAT"):
                return
            sname = ["poison", "paralysis", "sleep"][randi() % 3]
        if victim == null:
            var result := _actor_apply_major_status(null, int(GEN2_STATUS[sname]), sname == "toxic")
            _ab_say(_status_feedback("你", str(GEN2_STATUS_NAME[sname]), result))
        elif victim.dying < 0.0:
            _generic_status("", victim, sname)
        _ab_say("%s 的「%s」发动了！" % [_ab_owner(holder), AB.name_of(key)])
    if fx.has("dmg_div"):
        if victim == null:
            var d := maxi(int(floorf(stats.value("hp_max") / float(fx["dmg_div"]))), 1)
            if _player_dot(d):
                _flash_sprite(player.get_child(0), Color(1, 0.4, 0.35))
        elif victim.dying < 0.0:
            _enemy_status_damage(victim, maxi(int(floorf(_enemy_max_hp(victim) / float(fx["dmg_div"]))), 1))
        _ab_say("%s 的「%s」发动了！" % [_ab_owner(holder), AB.name_of(key)])


func _ab_on_kill(_e: Enemy) -> void:
    for key in _ab_keys(null):
        var r := AB.rule(str(key))
        if r.has("on_kill"):
            _generic_stat_change(true, null, str(r["on_kill"][0]), int(r["on_kill"][1]))


# 同步：自己中了毒 / 麻痹 / 灼伤，最近打自己的那只敌人也跟着中。
func _ab_after_status(unit, effect: int, toxic: bool) -> void:
    if unit != null:
        return
    if not (effect == PokemonStatus.POISON or effect == PokemonStatus.PARALYSIS or effect == PokemonStatus.BURN):
        return
    for key in _ab_keys(null):
        if AB.rule(str(key)).has("synchronize"):
            var src = hurt_any_src
            if src != null and is_instance_valid(src.node) and src.dying < 0.0:
                _actor_apply_major_status(src, effect, toxic)
                _ab_say("%s 的「%s」发动了！" % [_ab_owner(null), AB.name_of(str(key))])
            return


# ================= 周期 / 出场 =================
func _timed_tick() -> void:
    super._timed_tick()
    _ab_tick()


func _ab_due(key: String, secs: float) -> bool:
    if run_clock < float(_ab_timers.get(key, 0.0)):
        return false
    _ab_timers[key] = run_clock + secs
    return true


func _ab_tick() -> void:
    if dead or player_hp <= 0.0 or not started:
        return
    for key in _ab_keys(null):
        _ab_player_periodic(str(key))
    _ab_arrivals()


func _ab_player_periodic(key: String) -> void:
    var r := AB.rule(key)
    if r.is_empty():
        return
    if r.has("tick_stage"):
        var t: Array = r["tick_stage"]
        if _ab_due(key, float(t[2])) and _player_stage_of(str(t[0])) < int(t[1]) * 6:
            _generic_stat_change(true, null, str(t[0]), int(t[1]))
            _ab_say("%s 的「%s」让%s提高了！" % [_ab_owner(null), AB.name_of(key), AB_STAT_NAMES[str(t[0])]])
    if r.has("moody") and _ab_due(key, float(r["moody"])):
        _ab_moody()
    if r.has("weather_heal") and weather == str(r["weather_heal"][0]) and _ab_due(key, 2.0):
        heal(float(maxi(int(floorf(stats.value("hp_max") / float(r["weather_heal"][1]))), 1)))
    if r.has("weather_cure") and weather == str(r["weather_cure"]) and _ab_due(key, 2.0) and player_status.has_major():
        player_status.reset_major()
        _refresh_player_status_ui()
        _ab_say("%s 的「%s」治好了异常状态！" % [_ab_owner(null), AB.name_of(key)])
    if r.has("shed_skin") and player_status.has_major() and _ab_due(key, 3.0) and randf() < float(r["shed_skin"]):
        player_status.reset_major()
        _refresh_player_status_ui()
        _ab_say("%s 的「%s」治好了异常状态！" % [_ab_owner(null), AB.name_of(key)])
    if r.has("surge") and terrain == "" and _ab_due(key, 5.0):
        _set_terrain(str(r["surge"]))
        _ab_say("%s 的「%s」布下了%s！" % [_ab_owner(null), AB.name_of(key), AB_TERRAIN_NAMES[str(r["surge"])]])


# 心情不定：随机一项能力 +2，另一项 -1。
func _ab_moody() -> void:
    var stats_pool := ["atk", "def", "spatk", "spdef", "spd"]
    var up: String = stats_pool[randi_range(0, stats_pool.size() - 1)]
    stats_pool.erase(up)
    var down: String = stats_pool[randi_range(0, stats_pool.size() - 1)]
    _generic_stat_change(true, null, up, 2)
    _generic_stat_apply(true, null, down, -1)
    _ab_say("%s 的心情变了：%s大幅提高，%s降低" % [_ab_owner(null), AB_STAT_NAMES[up], AB_STAT_NAMES[down]])


# 敌人第一次靠近：场地制造者在 AB_NEAR 内触发；威吓只在敌人走进 AB_INTIMIDATE_RANGE 内才触发（见下），不是全局。
func _ab_arrivals() -> void:
    var near2 := AB_NEAR * AB_NEAR
    var intim2 := AB_INTIMIDATE_RANGE * AB_INTIMIDATE_RANGE
    var mine := _ab_keys(null)
    for e in enemies:
        if e.dying >= 0.0:
            continue
        if not e.ab_intim:
            var o2: Vector3 = e.node.position - player.position
            if o2.x * o2.x + o2.z * o2.z <= intim2:
                e.ab_intim = true
                for key in mine:
                    if AB.rule(str(key)).has("intimidate"):
                        _ab_intimidate_enemy(e, str(key))
                for key in _ab_keys(e):
                    if AB.rule(str(key)).has("intimidate") and run_clock >= _ab_intimidate_next:
                        _ab_intimidate_player(e, str(key))
        if e.ab_seen:
            continue
        var off: Vector3 = e.node.position - player.position
        if off.x * off.x + off.z * off.z > near2:
            continue
        e.ab_seen = true
        for key in _ab_keys(e):
            var r := AB.rule(str(key))
            if r.has("surge") and terrain == "":
                _set_terrain(str(r["surge"]))
                _ab_say("%s 的「%s」布下了%s！" % [_ab_owner(e), AB.name_of(str(key)), AB_TERRAIN_NAMES[str(r["surge"])]])


func _ab_intimidate_enemy(e: Enemy, key: String) -> void:
    for ek in _ab_keys(e):
        if AB.blocks_intimidate(str(ek)):
            _ab_say("%s 的「%s」不受威吓影响" % [_ab_owner(e), AB.name_of(str(ek))])
            return
    _generic_stat_change(false, e, "atk", -1)
    _ab_say("%s 的「%s」发动了，周围敌人的攻击降低！" % [_ab_owner(null), AB.name_of(key)])


func _ab_intimidate_player(e: Enemy, key: String) -> void:
    for pk in _ab_keys(null):
        if AB.blocks_intimidate(str(pk)):
            _ab_say("%s 的「%s」不受威吓影响" % [_ab_owner(null), AB.name_of(str(pk))])
            return
        if AB.rule(str(pk)).has("rattled"):
            _generic_stat_change(true, null, "spd", 1)
    if _player_stage_of("atk") <= ENEMY_DEBUFF_FLOOR:
        return
    _ab_intimidate_next = run_clock + AB_INTIMIDATE_GAP
    _generic_stat_change(true, null, "atk", -1, true)
    _ab_say("%s 的「%s」发动了，你的攻击降低！" % [_ab_owner(e), AB.name_of(key)])


# 压迫感：敌人的出手间隔变长（原作是对手多扣 PP，本作 PP 换成冷却，折成近身 / 远程 / 降能力三种冷却 ×1.5）。
# 特性和被动都是压迫感也只算一次（原版同一招只多扣一次，2026-10-22 审查：原来连乘成 2.25）。
func _ab_pressure_factor() -> float:
    var f := 1.0
    for key in _ab_keys(null):
        f = maxf(f, float(AB.rule(str(key)).get("pressure", 1.0)))
    return f
