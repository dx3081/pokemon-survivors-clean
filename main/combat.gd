extends "res://main/state.gd"
# 升级 / 进化 / 换招接线（2026-10-15；含静默升级与四招补充轮）。
# - 普通升级静默：只按原作公式重算六项，不弹面板、不暂停、不选卡。
# - 事件型选择只有两种：进化确认 / 暂缓、四招满时换招 / 放弃，走 ui/pokemon_choice.gd。
# - 所有事件由一个事件泵串行处理，同一时刻最多一个，避免同帧多个经验球重复排队进化。
# 经验曲线按当前物种走 game/pokemon_growth.gd → game/pokemon_species_exp.gd；
# 公式与来源见 game/POKEMON_GROWTH_SOURCE.md、game/POKEMON_SPECIES_EXP_RUNTIME_SOURCE.md。

const BossRules := preload("res://game/pokemon_boss_rules.gd")
const MovePP := preload("res://game/pokemon_pp.gd")
# 玩家准确物种资料（名字 / form0 原六维 / 精灵图类型）：唯一委托 game/pokemon_starters.gd，
# 8128 等图鉴外地区 ID 也取准确资料，不用绿毛虫六维兜底。经验公式 / 事件泵不改。
const PokemonStarters := preload("res://game/pokemon_starters.gd")
const PokemonSpeed := preload("res://game/pokemon_speed.gd")
const WildSpecies := preload("res://data/pokemon_wild_species.gd")
# 破段强化的可注入骰：0..1 单次 frac。生产用 randf()；检查可注入固定序列验证耗骰次数 / 顺序。
var stat_boost_rand := Callable()

# 当前玩家升级门槛：按**当前** player_species_id + level 查原成长率（唯一委托纯层）。
# 每次现算、不缓存物种，进化提交后查的是新物种；未知物种 / 无效门槛返回 -1。
func _xp_need() -> int:
    # 百变怪经验曲线是自己的（MEDIUM_FAST），不跟着被选物种走。
    return PokemonGrowth.xp_needed(level, PokemonStarters.DITTO_ID if player_is_ditto else player_species_id)

# 唯一升级入口：加经验，按**当前物种原成长率**结算（可一次升多级），静默重算六项。
# 入口先查当前 species_id / level 的门槛：未知资料 / 无效门槛（-1）在加 XP / 进循环之前直接拒绝，
# 不把 -1 当门槛一路升到 100。已知物种 100 级按既有上限不再升级（门槛 0，循环不进入），
# 满级经验存留语义不变（XP 照加、不再升级）。
# 商店第 2 段：两种全体类原经验护符的全局加成**只在这里应用一次**（不同时在 kill / 球 / 入口乘三次）。
# 每种按首次获得顺序 floor(value*(1+stacks*percent/100))；没有购买时 floor(原值) 完全保留原行为。
# 先记下本批升级前等级：原 LevelUpPhase / EvolutionPhase 都用 getLevelMoves(lastLevel+1)，
# 一次经验跨多级时要查 [lastLevel+1, 当前等级] 整段，不能只看最终等级一个点。
# 买到的经验护符总倍率（×1.0 = 没买），给设置页显示最高值。
func _exp_charm_mult() -> float:
    var w = points_wallet if points_wallet != null else Points.new(points_path)
    return PokemonShop.apply_exp(1000.0, w.charm_order, w.charm_stacks) / 1000.0


func _gain_xp(amount: float) -> void:
    if amount <= 0.0 or dead:
        return
    # 未知资料 / 无效升级门槛：拒绝在加 XP / 进循环之前（不允许 -1 门槛死循环升级）。
    if _xp_need() < 0:
        return
    var applied := amount
    if points_wallet != null:
        applied = PokemonShop.apply_exp(amount, points_wallet.charm_order, points_wallet.charm_stacks)
    # 设置页的“经验加成”：护符多出来的那部分只生效 xp_rate_pct%（0% = 原经验）。
    if xp_rate_pct < 100:
        var plain := floorf(amount)
        applied = floorf(plain + (applied - plain) * float(xp_rate_pct) / 100.0)
    var share := _global_charm("EXP_SHARE")
    if share > 0:
        applied = floorf(applied * (1.0 + 0.2 * share))   # 学习装置（本作不做队伍：直接加给上场那只）
    var egg := int(run_held.get("LUCKY_EGG", 0))
    if egg > 0:
        applied = floorf(applied * HeldItems.lucky_egg_mult(egg))   # 携带道具·幸运蛋（原版 floor(exp × (1 + 个数 × 0.4))）
    var gegg := int(run_held.get("GOLDEN_EGG", 0))
    if gegg > 0:
        applied = floorf(applied * (1.0 + HeldItems.GOLDEN_EGG_BOOST * gegg))   # 金蛋：原版是另一个同类加成，分开乘
    if not PokemonShop.exp_boosts_on:
        applied = floorf(amount)   # 经验加成已禁（2026-10-25，见 game/pokemon_shop.gd EXP_BANNED）：买过的也不生效
    if applied <= 0.0:
        return
    var level_before := level
    xp += applied
    var gained := 0
    while level < PokemonGrowth.MAX_LEVEL:
        # 每次从当前物种 / 当前等级重新查率：进化提交后也不会缓存上一个物种的门槛。
        var need := _xp_need()
        if need <= 0 or xp < float(need):
            break
        xp -= float(need)
        level += 1
        gained += 1
    if gained > 0:
        _after_level_up(level_before)

# 普通升级：不调用事件面板，只重算 + 提示；再按当前形态原表把本批可学的已实现招式排队，
# 最后检查进化事件。普通升级永远静默、不暂停。
func _after_level_up(level_before: int) -> void:
    _recalculate_player_stats()
    hud.show_banner("升级！Lv %d" % level)
    _note_learn_floor(level_before)
    _queue_learns(player_species_id, false)
    _fusion_partner_evolve()
    _schedule_event_check()


# 融合：主宠这一级不能进化时，融合对象那一半按自己的等级进化表进化（原版 FusionSpeciesFormEvolution）。
func _fusion_partner_evolve() -> void:
    if player_fusion_id <= 0 or not _evolution_candidates().is_empty():
        return
    var targets: Array = preload("res://game/pokemon_evolution.gd").level_targets(player_fusion_id, level, player_friendship, active_moves)
    if targets.is_empty():
        return
    var from := player_fusion_id
    player_fusion_id = int(targets[0])
    _recalculate_player_stats()
    hud.show_banner("融合的%s进化成了%s！" % [_species_name(from), _species_name(player_fusion_id)])


func _fused_name() -> String:
    return Fusion.name_of(_species_name(player_species_id), _species_name(player_fusion_id)) if player_fusion_id > 0 else _species_name(player_species_id)

# 原 getLevelMoves(t, ...) 的 t = lastLevel + 1 就是这里 _learn_floor 的下界。
# 连着收经验（多批）时取最小下界，免得后一批把前一批的区间盖掉；事件泵全部处理完再清 0。
func _note_learn_floor(level_before: int) -> void:
    var floor_level := level_before + 1
    _learn_floor = floor_level if _learn_floor == 0 else mini(_learn_floor, floor_level)

# 按“当前形态”原表把本批可学的已实现招式排进 _pending_learns：
# include_evolution_moves 只在确认进化并演完后查新形态时置 true（原 getLevelMoves(t, true)）。
# 已会 / 已在排队 / 正在等选择的同招都不再重复入队。未实现招式由 learnable_between 直接过滤。
func _queue_learns(species_id: int, include_evolution_moves: bool) -> void:
    var from_level := _learn_floor if _learn_floor > 0 else level
    var learn: Array = MOVES.learnable_between(species_id, from_level, level, include_evolution_moves)
    if player_fusion_id > 0 and species_id == player_species_id:
        learn.append_array(MOVES.learnable_between(player_fusion_id, from_level, level, false))   # 融合：对象那只的升级招也能学
    for move_id: String in learn:
        if active_moves.has(move_id) or _pending_learns.has(move_id) or move_id == _learning_move:
            continue
        _pending_learns.append(move_id)

# 按当前物种 / 等级 / 占位 IV / 中性性格重算六项，并把生命 / 攻击 / 防御接到本作战斗。
# 特攻 / 特防 / 原作速度照实存进 player_stats 供显示，不当伤害或移速使用。
func _recalculate_player_stats() -> void:
    if stats == null:
        return
    var old_max := stats.value("hp_max")
    # 性格倍率由 25 性格表的 id 现算（本轮默认 id 0，中性）；player_nature 保留为最近一次使用的倍率。
    player_nature = PokemonGrowth.nature_multipliers(player_nature_id)
    player_nature = HeldItems.soul_dew_nature(player_nature, int(run_held.get("SOUL_DEW", 0)))   # 携带道具·心之水滴
    _ab_refresh_player()   # 特性随物种 / 栏位变（进化沿用栏位）
    # 营养饮料的努力值按“本局开局选的那只”存（进化后同一只，换了形态也带着）；没买过 = 全 0，公式与原作一致。
    var evs: Array = []
    if points_wallet != null and player_train_key > 0:
        evs = points_wallet.ev_for(player_train_key)
    var base_stats: Array = _species_base_stats(player_species_id)
    if not player_special_form.is_empty():
        base_stats = (player_special_form["stats"] as Array).duplicate()   # 超级 / 超极巨形态的种族值
    if player_fusion_id > 0 and not player_is_ditto:
        base_stats = Fusion.base_stats(base_stats, _species_base_stats(player_fusion_id))   # 融合：种族值平均（向上取整）
    if player_is_ditto:
        base_stats = PokemonStarters.ditto_base_stats(player_species_id)
    player_base_stats = base_stats.duplicate()   # 详情页六边形图用（种族值：含超级形态 / 融合平均）
    player_stats = PokemonGrowth.calculate_stats(base_stats, level, player_ivs, player_nature, evs)
    var wonder_guard := player_ability == "WONDER_GUARD" or (player_passive_on and player_passive == "WONDER_GUARD")
    if wonder_guard:
        player_stats[0] = 1   # 神奇守护：最大 HP 恒为 1（原版 calculateStats，融合也一样）
    stats.set_cap("hp_max", 1.0 if wonder_guard else -1.0)   # 闪光开局 +10% 之类的百分比也压回 1（2026-10-22 审查发现 1.1）
    _apply_held_stat_boosters()
    stats.set_base("hp_max", float(player_stats[0]))
    stats.set_base("attack", float(player_stats[1]))
    stats.set_base("defence", float(player_stats[2]))
    # 招式伤害不再做“本作基础伤害 × 原作 ATK / 初始 ATK(5)”的过渡适配：main/arts.gd 直接用
    # 这里的 player_stats 六维 + 目标实际六维走 game/pokemon_damage.gd 的原公式（含本系 / 克制 /
    # 会心 / 随机），最终伤害不再二次减防。stats 的 attack.xxx 过渡键已删除。
    # 实时战斗参数保留本作值：原作“速度”是等级后的原作速度属性，不是米/秒，也不是冷却倍率。
    stats.set_base("move_speed", float(player_unit["speed"]))
    stats.set_base("aspd", float(player_unit["aspd"]))
    stats.set_base("magnet", float(player_unit["magnet"]))
    _apply_hp_after_max_change(old_max)
    _sync_player_unit_species(player_species_id)


# 携带道具·按物种 / 进化的能力倍率（原版 EvolutionStatBooster / SpeciesStatBooster），乘在算好的六维上、向下取整。
func _apply_held_stat_boosters() -> void:
    var mul := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    if int(run_held.get("EVIOLITE", 0)) > 0 and not player_is_ditto and not PokemonEvolution.entries(player_species_id).is_empty():
        mul[2] *= HeldItems.EVIOLITE_MULT
        mul[4] *= HeldItems.EVIOLITE_MULT
    if int(run_held.get("LIGHT_BALL", 0)) > 0 and HeldItems.species_ok("LIGHT_BALL", player_species_id):
        mul[1] *= HeldItems.SPECIES_STAT_MULT
        mul[3] *= HeldItems.SPECIES_STAT_MULT
    if int(run_held.get("THICK_CLUB", 0)) > 0 and HeldItems.species_ok("THICK_CLUB", player_species_id):
        mul[1] *= HeldItems.SPECIES_STAT_MULT
    if int(run_held.get("METAL_POWDER", 0)) > 0 and player_is_ditto:
        mul[2] *= HeldItems.SPECIES_STAT_MULT
    for i in range(1, 6):
        if mul[i] != 1.0:
            player_stats[i] = int(floorf(float(player_stats[i]) * mul[i]))


# 携带道具·用掉一个（复活种子 / 白色香草）：这一局少一个，钱包里也真的少一个。
func _use_up_held(item: String) -> void:
    run_held[item] = maxi(0, int(run_held.get(item, 0)) - 1)
    if points_wallet != null and points_wallet.has_method("consume_held"):
        points_wallet.consume_held(run_starter_id, item)


# 携带道具·每秒检查一次：白色香草（能力被降就全部恢复）、剧毒 / 火焰宝珠（没异常就自己中）。
var _held_sec_clock := 0.0
func _held_second_tick(delta: float) -> void:
    _held_sec_clock += delta
    if _held_sec_clock < 1.0 or dead or player_hp <= 0.0:
        return
    _held_sec_clock = 0.0
    if int(run_held.get("WHITE_HERB", 0)) > 0:
        var low := player_atk_stage < 0 or player_def_stage < 0 or player_spatk_stage < 0 or player_spdef_stage < 0 \
            or player_spd_stage < 0 or player_acc_stage < 0 or player_eva_stage < 0
        if low:
            player_atk_stage = maxi(0, player_atk_stage)
            player_def_stage = maxi(0, player_def_stage)
            player_spatk_stage = maxi(0, player_spatk_stage)
            player_spdef_stage = maxi(0, player_spdef_stage)
            player_spd_stage = maxi(0, player_spd_stage)
            player_acc_stage = maxi(0, player_acc_stage)
            player_eva_stage = maxi(0, player_eva_stage)
            _use_up_held("WHITE_HERB")
            _show_status_feedback("白色香草让能力恢复了！")
    if player_status != null and not player_status.has_major():
        if int(run_held.get("TOXIC_ORB", 0)) > 0:
            _actor_apply_major_status(null, PokemonStatus.POISON, true)
        elif int(run_held.get("FLAME_ORB", 0)) > 0:
            _actor_apply_major_status(null, PokemonStatus.BURN)


# 玩家模板（旧世界模板深副本）的元信息跟随当前准确物种：
#   species_id / name / types / base_stats 从 game/pokemon_starters.gd::profile 复制（副本，不共用常量）；
#   模板保留的 hp / attack / defence 字段按**唯一** player_stats 原计算结果同步，不留旧 11/5/5。
# 世界实时字段 scene / anims / speed / aspd / magnet / body_radius 等照旧，不在这里改。
# 初次选角、升级与 10→11→12 进化提交后都会走 _recalculate_player_stats，因此元信息始终一致。
func _sync_player_unit_species(species_id: int) -> void:
    if player_unit == null or player_unit.is_empty():
        return
    var prof := PokemonStarters.profile(species_id)
    if prof.is_empty():
        return
    player_unit["species_id"] = species_id
    var pname := str(prof.get("name", ""))
    if pname != "":
        player_unit["name"] = pname
    player_unit["types"] = (prof.get("types", []) as Array).duplicate()
    player_unit["base_stats"] = (PokemonStarters.ditto_base_stats(species_id) if player_is_ditto else (prof.get("base_stats", []) as Array)).duplicate()
    if player_stats.size() >= PokemonGrowth.STAT_COUNT:
        player_unit["hp"] = float(player_stats[0])
        player_unit["attack"] = float(player_stats[1])
        player_unit["defence"] = float(player_stats[2])

# 源头 calculateStats() 的 HP 语义：新上限增加时正 HP 补差额、下降时 clamp、0 血不复活。
func _apply_hp_after_max_change(old_max: float) -> void:
    var new_max := stats.value("hp_max")
    if player_hp > new_max:
        player_hp = new_max
    elif player_hp > 0.0 and new_max > old_max:
        player_hp += new_max - old_max
    player_hp = maxf(0.0, player_hp)

func _species_base_stats(species_id: int) -> Array:
    # 准确资料唯一委托 game/pokemon_starters.gd：图鉴内用原种族值，1025 范围外地区 ID（8128）
    # 用 WildSpecies.form_at 的准确六维，不落到绿毛虫兜底。
    var prof := PokemonStarters.profile(species_id)
    var base: Array = prof.get("base_stats", [])
    if base.size() >= PokemonGrowth.STAT_COUNT:
        return base
    return [45, 30, 35, 20, 20, 45]  # 最后兜底：只有资料缺失才用


# ================= 事件泵（进化 / 换招）=================
# 设计要点：
# (1) 不再预先 append 10→11→12 队列；每次迭代都用最新 level + 已确认 player_species_id
#     现算下一段，事件泵运行中再次升级只置 _event_pending，不会重复追加。
# (2) 每个 await 之后都用 event_token + _run_valid() 校验；_settle / 放弃 / 退出会让
#     token 失效并释放演出连接，之后不再切种族。
# (3) 一轮内先处理 _pending_learns（普通升级学习 / 已确认进化的新形态学习），再处理进化；
#     原 LevelUpPhase 也是先学招再进 EvolutionPhase，而进化招只在前一段真正提交后才入队。
# 暂缓语义：不确认就 break，只有后续真实升级重新置 _event_pending 才会再问；
# 不会逐帧重弹。第二段只在前一段确认进化后由循环再次生成。

func _run_valid() -> bool:
    return is_inside_tree() and not dead and not settled

func _event_valid(token: int) -> bool:
    return token == event_token and _run_valid()

# 一次真实升级后调用：检查是否有进化事件待处理。
func _schedule_event_check() -> void:
    _event_pending = true
    _start_event_pump()

func _start_event_pump() -> void:
    if _event_pump_running:
        return
    # 捕获演出期间（capture_presenting）不推进进化 / 换招；暂停 / 商店时也先不启动。
    # 两者解除后由 _finish_capture_presentation / _resume 重新调用本入口，门槛不会失效。
    if capture_presenting or paused:
        return
    _event_pump_running = true
    _event_pump()

func _event_pump() -> void:
    var token := event_token
    while _event_valid(token):
        if not _pending_learns.is_empty():
            var move_id: String = _pending_learns.pop_front()
            _learning_move = move_id
            await _learn_move_event(move_id, token)
            _learning_move = ""
            if not _event_valid(token):
                break
            continue
        if _event_pending:
            _event_pending = false
            var candidates := _evolution_candidates()
            var by_item := _item_evolution_to > 0
            if not by_item:
                var still: Array[int] = []
                for c in candidates:
                    if not _evo_declined.has(c) or level >= int(_evo_declined[c]) + evo_decline_levels:
                        still.append(c)
                candidates = still
            if candidates.is_empty():   # 没有可进化的 / 百变怪不进化 / 刚暂缓过
                continue
            var to_id: int = candidates[0]
            var confirmed := false
            if candidates.size() > 1:
                to_id = await _ask_evolution_pick(candidates, token)   # 多个分支（伊布…）：玩家自己选
                confirmed = to_id > 0
            elif by_item:
                confirmed = true   # 进化道具买了就进化，不再问一次
            else:
                confirmed = await _ask_evolution(to_id, token)
            if not _event_valid(token):
                break
            if not confirmed:
                if not by_item:
                    for c in candidates:
                        _evo_declined[c] = level   # 记下：这几级先别再问
                _item_evolution_to = 0
                _event_pending = false  # 丢弃选择前同批经验的升级标记；下次真实升级才重试
                break  # 本次暂缓；下一次真实升级会把 _event_pending 重新置位
            var played := await _play_evolution(player_species_id, to_id, token)
            if not _event_valid(token):
                break
            if not played:
                # 演出资源 / 信号缺失：保留原形态，清掉本批待检查标记，不宣称进化成功。
                _item_evolution_to = 0
                _event_pending = false
                break
            _item_evolution_to = 0
            player_species_id = to_id
            player_special_form = {}   # 再进化：超级 / 超极巨形态没了
            _unlock_evolved_species(to_id)
            _refresh_player_species_visual()
            _recalculate_player_stats()
            # 原 EvolutionPhase：evolve 真正提交后用 getLevelMoves(lastLevel+1, true) 查“新形态”的
            # level 0 进化招 + 本批合法区间；不补所有低等级 / 等级 1 招。
            _queue_learns(player_species_id, true)
            _event_pending = true  # 立刻检查下一段（确认前不会生成 11→12）
            continue
        break
    _event_pump_running = false
    if _event_valid(token) and (_event_pending or not _pending_learns.is_empty()):
        _start_event_pump()
    elif _event_valid(token):
        _learn_floor = 0  # 本批事件全部处理完，下一批升级重新记下界


# 进化后的新形态按“已捕获”算（用户 2026-10-17）：写进持久图鉴，之后可以直接选它出发；已有就不重复写。
func _unlock_evolved_species(to_id: int) -> void:
    if points_wallet == null:
        return
    var res: Dictionary = points_wallet.unlock_species(to_id)
    if bool(res.get("added", false)):
        _refresh_rare_markers()
        _show_status_feedback("图鉴新增：%s（进化后算已捕获）" % _species_name(to_id))
    # 闪光个体进化：进化形态的同一档闪光也算抓到过（用户 2026-10-20），下次能直接用它闪光开局
    if player_shiny_variant >= 0 and bool(res.get("ok", false)):
        if not player_shiny_borrowed:   # 融合借来的闪光不解锁
            points_wallet.mark_shiny_caught(to_id, player_shiny_variant)


# ================= 进化选择与演出 =================

# 现在能进化成谁：道具进化优先（商店买了道具），否则按等级 / 亲密度 / 当前招式栏查进化表（game/pokemon_evolution.gd）。
func _evolution_candidates() -> Array[int]:
    if player_is_ditto:
        return []
    if _item_evolution_to > 0:
        return [_item_evolution_to]
    return preload("res://game/pokemon_evolution.gd").level_targets(player_species_id, level, player_friendship, active_moves)




func _decline_text() -> String:
    return "暂缓（%d 级内不再问）" % evo_decline_levels if evo_decline_levels > 0 else "暂缓"


func _evolution_info(to_id: int) -> String:
    var cur: Array = player_base_stats if not player_base_stats.is_empty() else _species_base_stats(player_species_id)
    var nxt: Array = _species_base_stats(to_id)
    var labels := ["HP", "攻击", "防御", "特攻", "特防", "速度"]
    var parts: Array = []
    for i in mini(6, mini(cur.size(), nxt.size())):
        var d := int(nxt[i]) - int(cur[i])
        parts.append("%s %d→%d%s" % [labels[i], int(cur[i]), int(nxt[i]), "" if d == 0 else ("（+%d）" % d if d > 0 else "（%d）" % d)])
    var keep: Array = []
    for m in active_moves:
        keep.append(str(MOVES.MOVES[m]["name"]) if MOVES.MOVES.has(m) else m)
    var learn: Array = []
    for m in MOVES.learnable_between(to_id, level, level, true):
        if not active_moves.has(str(m)):
            learn.append(str(MOVES.MOVES[str(m)]["name"]))
    var line := "能力（种族值）：" + "　".join(parts)
    line += "\n招式：现在的招全部保留（%s）" % "、".join(keep)
    line += "；进化后会学：%s（招满了会问你换不换）。" % "、".join(learn) if not learn.is_empty() else "；进化时不会学新招。"
    return line


# 多个进化分支时让玩家选（原作也是选）：返回选中的物种 ID，暂缓 / 取消返回 -1。
func _ask_evolution_pick(candidates: Array[int], token: int) -> int:
    var names: Array = []
    var details: Array = []
    for c in candidates:
        names.append(_species_name(c))
        details.append(_evolution_info(c))
    var idx := await _ask_choice("进化", "%s 可以进化成哪一个？（把鼠标移到选项上看能力和招式）" % _species_name(player_species_id), names,
        _decline_text(), token, details)
    if not _event_valid(token) or idx < 0 or idx >= candidates.size():
        return -1
    return candidates[idx]


func _ask_evolution(to_id: int, token: int) -> bool:
    var from_name := _species_name(player_species_id)
    var to_name := _species_name(to_id)
    var idx := await _ask_choice("进化", "%s 要进化成 %s 吗？" % [from_name, to_name],
        ["进化"], _decline_text(), token, [], _evolution_info(to_id))
    if not _event_valid(token):
        return false
    return idx == 0

# 演出期间 evolving=true：main._process 早退，主循环推进和伤害都停；不动 Engine.time_scale，
# 免得演出动画被 time_scale=0 冻死。token 失效就断开连接并释放 fx。
# 返回值就是“演出真的正常结束或用户跳过”这一个成功契约：资源 / finished 信号缺失时返回
# false，调用方保留原形态并恢复事件状态，不拿 0.4 秒直切数据冒充进化。
func _play_evolution(from_id: int, to_id: int, token: int) -> bool:
    evolving = true
    var fx: Node = _make_evolution_fx()
    if fx == null:
        evolving = false
        _evolution_unavailable()
        return false
    _evolution_finished = false
    _evolution_fx = fx
    fx.connect("finished", Callable(self, "_on_evolution_finished"), CONNECT_ONE_SHOT)
    fx.call("play_evolution", from_id, to_id, _portrait_for(from_id), _portrait_for(to_id))
    while not _evolution_finished:
        if not _event_valid(token):
            _release_evolution_fx(fx)
            evolving = false
            return false
        await get_tree().process_frame
    _release_evolution_fx(fx)
    evolving = false
    return true

# 演出依赖不可用（资源 / 信号缺失）时的恢复分支：只警告 + 屏幕提示，不 push_error 冒充引擎故障。
func _evolution_unavailable() -> void:
    push_warning("进化演出不可用（fx/rogue_evolution.gd 或 finished 信号缺失）；保留原形态，本次不进化。")
    if hud != null:
        hud.show_banner("进化演出不可用，暂时保留原形态")

func _on_evolution_finished() -> void:
    _evolution_finished = true

# 懒创建另一条约定的 fx/rogue_evolution.gd；文件 / 方法 / finished 信号缺一就返回 null，不造 stub。
func _make_evolution_fx() -> Node:
    if not ResourceLoader.exists("res://fx/rogue_evolution.gd"):
        return null
    var script: GDScript = load("res://fx/rogue_evolution.gd")
    if script == null or not script.can_instantiate():
        return null
    var raw: Object = script.new()
    if not (raw is CanvasLayer) or not raw.has_method("play_evolution") or not raw.has_signal("finished"):
        if raw is Node:
            (raw as Node).queue_free()
        return null
    var fx := raw as Node
    add_child(fx)
    return fx

# 参数故意不收窄类型：取消 / 死亡可能已经 queue_free 过同一个 fx，再传进来要能安全忽略，
# 否则把“已释放对象”塞进 `fx: Node` 会在调用点直接报 SCRIPT ERROR。
func _release_evolution_fx(fx) -> void:
    if fx == null or not is_instance_valid(fx):
        if fx == _evolution_fx:
            _evolution_fx = null
        return
    if fx == _evolution_fx:
        _evolution_fx = null
    var cb := Callable(self, "_on_evolution_finished")
    if fx.is_connected("finished", cb):
        fx.disconnect("finished", cb)
    # 立刻从树上摘掉，别把一个已完成 / 跳过的演出节点留到帧末，让下一段演出和它短暂并存。
    if fx.get_parent() == self and is_inside_tree():
        remove_child(fx)
    fx.queue_free()

func _refresh_player_species_visual() -> void:
    if player != null and player.get_child_count() > 0:
        var visual := player.get_child(0)
        if visual.has_method("set_species") and visual.has_method("set_wild_species"):
            # 10/11/12 用内置三形态；其余 84 表物种（含 8128）用平原原图集 form0，不冒充绿毛虫。
            if not player_special_form.is_empty() and visual.has_method("set_form_sprite"):
                visual.set_form_sprite(player_species_id, str(player_special_form["sprite_key"]), player_shiny_variant)
            elif _player_uses_wild_sprite():
                visual.set_wild_species(player_species_id, 0, player_shiny_variant)
            else:
                visual.set_species(player_species_id, player_shiny_variant)
    if hud != null:
        # 起了名字就显示名字（按开局选的那只记，进化后还是这个名字，照原版）
        var nick: String = points_wallet.nickname_for(player_train_key) if points_wallet != null and player_train_key > 0 else ""
        var shown := _species_name(player_species_id)
        var pic := _portrait_for(player_species_id)
        if not player_special_form.is_empty():
            shown = SpecialForms.display_name(shown, player_special_form)
            var visual2 := player.get_child(0) if player != null and player.get_child_count() > 0 else null
            if visual2 != null and visual2.has_method("portrait_for_form"):
                var fp: Texture2D = visual2.portrait_for_form(player_species_id, str(player_special_form["sprite_key"]), player_shiny_variant)
                if fp != null:
                    pic = fp
        hud.set_portrait(pic, nick if nick != "" else ("百变怪·" if player_is_ditto else "") + shown)


# 玩家当前物种是否走平原原图集（非内置 10/11/12 且在 WildSpecies 里有资料）。
func _player_uses_wild_sprite() -> bool:
    var prof := PokemonStarters.profile(player_species_id)
    return str(prof.get("sprite", "none")) == "wild"

# 立绘优先走另一条约定的 portrait_for_species(id)（内置三形态）/ portrait_for_wild(id, 0)（原图集）。
# 接口不在 / 该物种无图就退回当前立绘，不新造图、不把绿毛虫立绘当成新物种。
func _portrait_for(species_id: int) -> Texture2D:
    if player != null and player.get_child_count() > 0:
        var visual := player.get_child(0)
        var prof := PokemonStarters.profile(species_id)
        if str(prof.get("sprite", "none")) == "wild" and visual.has_method("portrait_for_wild"):
            if _wild_portrait_available(species_id):
                var wtex: Texture2D = visual.portrait_for_wild(species_id, 0)
                if wtex != null:
                    return wtex
        if str(prof.get("sprite", "none")) == "builtin" and visual.has_method("portrait_for_species"):
            var tex: Texture2D = visual.portrait_for_species(species_id)
            if tex != null:
                return tex
        if visual.has_method("portrait_texture"):
            return visual.portrait_texture()
    return player_portrait


# 该物种的原图集是否齐全（front/back 都有）；缺失时不要调 portrait_for_wild 触发断言。
func _wild_portrait_available(species_id: int) -> bool:
    if not WildSpecies.has_species(species_id):
        return false
    var form := WildSpecies.form_at(species_id, 0)
    var key := str(form.get("sprite_key", ""))
    return not WildSpecies.atlas_entry(species_id, key, "front").is_empty() \
        and not WildSpecies.atlas_entry(species_id, key, "back").is_empty()


func _species_name(species_id: int) -> String:
    var prof := PokemonStarters.profile(species_id)
    var n := str(prof.get("name", ""))
    if n != "":
        return n
    var entry := Pokedex.entry(species_id)
    if not entry.is_empty():
        var dn := str(entry.get("name", ""))
        if dn != "":
            return dn
    return str(player_unit.get("name", "绿毛虫"))


# ================= 选择面板与状态清理 =================

func _choice_page() -> Node:
    if choice_page == null or not is_instance_valid(choice_page):
        choice_page = PokemonChoice.new()
        add_child(choice_page)
    return choice_page

# 打开事件面板并等待选择；取消 / 关闭 / 死亡 / 退出 / token 失效都返回 -1。
# 返回值：>=0 是选项下标；-1 是取消 / 放弃 / 未选择。
func _ask_choice(title: String, message: String, options: Array, cancel_text: String, token: int, details: Array = [], header := "") -> int:
    var page: Node = _choice_page()
    var result := {"value": -2}
    var on_pick := func(i: int): result["value"] = i
    var on_cancel := func(): result["value"] = -1
    page.connect("picked", on_pick, CONNECT_ONE_SHOT)
    page.connect("cancelled", on_cancel, CONNECT_ONE_SHOT)
    page.call("open_choice", title, message, options, cancel_text, details, header)
    choosing = true
    while int(result["value"]) == -2:
        if not _event_valid(token):
            break
        await get_tree().process_frame
    choosing = false
    page.call("close")
    if page.is_connected("picked", on_pick):
        page.disconnect("picked", on_pick)
    if page.is_connected("cancelled", on_cancel):
        page.disconnect("cancelled", on_cancel)
    if not _event_valid(token):
        return -1
    return int(result["value"])


# 取消当前事件 / 清回调：_settle、放弃、退出 / 重开都走这里，不残留 choosing / evolving / 面板 /
# 播放器 / 待学习请求（旧局的学习进度、拒绝、待选状态不会带进新局）。
# 异常状态 / 实时状态钟也在这里收口：取消 / 结算 / reload 不留下旧秒钟与阻断缓存；
# 真实取消 / 放弃 / 结算 / 场景退出还要把临时原招 + common 播放、背景 / 图层、被写过的
# 展示层归属与音频一起清掉（否则 `_plays` / `_audio` 会留到下一局或结算画面）。
func _cancel_events() -> void:
    event_token += 1
    _event_pump_running = false
    _event_pending = false
    _item_evolution_to = 0
    _pending_learns.clear()
    _learning_move = ""
    _learn_floor = 0
    choosing = false
    evolving = false
    if _evolution_fx != null and is_instance_valid(_evolution_fx):
        _release_evolution_fx(_evolution_fx)
    _evolution_finished = false
    if choice_page != null and is_instance_valid(choice_page):
        choice_page.call("close")
    _cancel_ball_aim()
    capture_pause_mode = false
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("set_pause_mode"):
        capture_page.call("set_pause_mode", false)
    _clear_bolts()
    # 捕获演出批次：清原 FX 与自有音频、恢复仍活的失败目标显示、清待奖励 / 延迟头目（幂等）。
    _cancel_capture_presentation()
    _reset_status_state()
    _clear_status_fx()


# 异常状态 / 秒钟复位：供新局与事件取消共用。清空玩家状态（主要异常 + 混乱）、
# 复位实时钟与当秒阻断缓存、重画标识。升级 / 进化不调用本函数（原 status 保留）。
func _reset_status_state() -> void:
    if player_status != null:
        player_status.reset_all()
    if player_clock != null:
        player_clock.stop()
    player_status_blocked = false
    player_status_blocked_major = false
    player_status_key = ""
    if hud != null and hud.has_method("set_player_status"):
        hud.set_player_status("")



# ================= 学习 / 替换招式入口 =================

# 学习新招式：只接受 data/pokemon_moves.gd 标记为已实现（arts 有实际释放）的招式。
# 已会 / 已在排队 / 正在等选择的同招都忽略；请求统一排队，由唯一事件泵串行处理：
# 空槽直接加入（只提示、不弹选择），满四招才弹“替换哪招 / 放弃”。不自动替用户换招。
func request_learn_move(move_id: String) -> void:
    if not _run_valid():
        return
    if not MOVES.is_implemented(move_id):
        push_warning("request_learn_move: 尚未实现的招式，忽略: " + move_id)
        return
    if active_moves.has(move_id) or _pending_learns.has(move_id) or move_id == _learning_move:
        return
    _pending_learns.append(move_id)
    _start_event_pump()

# 选招面板里的一行名字：名字 · 属性 · 威力（变化招写“变化”）。
func _move_label(id: String) -> String:
    var m: Dictionary = MOVES.MOVES[id]
    var power := int(m.get("power", 0))
    return "%s · %s · %s" % [str(m["name"]), str(m["type"]), ("威力 %d" % power) if power > 0 else str(m["category"])]


# 招式资料：名字、属性 / 分类、威力、命中、冷却、射程、用途描述。
func _move_info(id: String) -> String:
    var m: Dictionary = MOVES.MOVES[id]
    var power := int(m.get("power", 0))
    var acc := int(m.get("accuracy", 100))
    var line := "%s　%s · %s · %s" % [str(m["name"]), str(m["type"]), str(m["category"]), MOVES.target_text(m)]
    line += "　威力 %s" % (str(power) if power > 0 else "—")
    line += "　命中 %s" % (str(acc) if acc > 0 else "必中")
    var ups := int(run_held.get(HeldItems.pp_up_item(id), 0))
    line += "　PP %d　冷却 %.1f 秒" % [MovePP.move_pp(id, ups), MovePP.move_cd(id, ups)]
    if m.has("range") and int(m.get("target", 3)) != 0:   # 只作用于自己的招（神秘守护…）不显示射程
        # 显示实际射程：原始数据封顶 4 米再乘设置里的攻击距离；自身 / 场地招用标准攻击圈（用户 2026-10-23：原来显示没封顶的“射程 8”）
        var real_range: float = float(call("_range", id)) if float(m["range"]) > 0.0 else float(call("_std_range"))
        line += "　射程 %.1f 米" % real_range
    return line + "\n" + preload("res://game/pokemon_move_roles.gd").desc_with_note(id)   # 原说明 + 本作规则（被动 / 光环 / 救急…）


func _learn_move_event(move_id: String, token: int) -> void:
    if not MOVES.is_implemented(move_id) or active_moves.has(move_id):
        return
    if active_moves.size() < _move_slots():
        # 空槽：直接学会并提示，不弹选择面板、不暂停。
        active_moves.append(move_id)
        _refresh_moves()
        if hud != null:
            hud.show_banner("学会了 %s！" % str(MOVES.MOVES[move_id]["name"]))
        return
    if learn_plan_on and not learn_plan.is_empty():
        # 学招计划（用户 2026-10-24：开局把要学的 4 个点上，别的跳过）：不在计划里的不学（记进“忘了的招”，记忆蘑菇能找回）；
        # 在计划里的自动顶掉一个不在计划里的招。
        var new_nm := str(MOVES.MOVES[move_id]["name"])
        if not learn_plan.has(move_id):
            _note_forgotten(move_id)
            if hud != null:
                hud.show_banner("没学「%s」（不在学招计划里，记忆蘑菇能找回）" % new_nm)
            return
        for i in active_moves.size():
            var old_id := str(active_moves[i])
            if not learn_plan.has(old_id):
                _note_forgotten(old_id)
                active_moves[i] = move_id
                _refresh_moves()
                if hud != null:
                    hud.show_banner("学会「%s」，换掉了「%s」（学招计划）" % [new_nm, str(MOVES.MOVES[old_id]["name"])])
                return
    var options: Array = []
    var details: Array = []
    for id: String in active_moves:
        options.append(_move_label(id))
        details.append(_move_info(id))
    var new_name := str(MOVES.MOVES[move_id]["name"])
    var idx := await _ask_choice("学习新招式",
        "已学满 %d 招，要用「%s」替换哪一招？" % [_move_slots(), new_name],
        options, "放弃", token, details, "新招式：" + _move_info(move_id))
    if not _event_valid(token):
        return
    if idx < 0 or idx >= active_moves.size():
        return
    _note_forgotten(str(active_moves[idx]))   # 被换掉的招：记忆蘑菇能恢复
    active_moves[idx] = move_id
    _refresh_moves()


# ================= 战斗（沿用首交）=================

func _kill(e: Enemy) -> void:
    # 幂等：重复 _kill / 死亡补帧 / 重复结算不再加钱、不再掉第二颗 XP 球、不再播第二次死亡。
    # 真正死亡（原伤害、异常 DoT / 混乱自伤、头目 / 最终头目）都只从这一处走一次。
    if e.dying >= 0.0:
        return
    e.dying = 0.0
    kills += 1
    _ab_on_kill(e)
    # 击杀点数：1 + 敌人等级 ÷ 20，头目 ×5（game/pokemon_points.gd kill_points_for），死亡当帧立即进账 + 立即保存；
    # 不乘经验 / 物种 baseExp / 稀有度 / 事件 / 密度 / debug_power。
    _points_award_kill(int(e.t.get("level", 0)), bool(e.t.get("boss", false)))
    e.ap.play("death")
    sfx.kill(e.node.position, "caterpie")
    var g := MeshInstance3D.new()
    g.mesh = gem_mesh
    g.material_override = gem_mat
    g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    g.position = e.node.position + Vector3(0, 0.3, 0)
    # 球里存的是 roster 按 species_id 原作基础经验 + 实际 enemy level 算出的**基础击倒值**；
    # 经验护符的本次唯一全局加成在拾取时的 `_gain_xp` 入口应用（这里不乘倍率）。
    g.set_meta("xp", e.t["xp"])
    add_child(g)
    gems.append(g)
    if e.t["boss"] or (e.t["elite"] and randf() < POTION_ELITE_CHANCE):
        _drop_potion(e.node.position)
    # 金珠：头目必掉大金珠，普通怪 1% 掉金珠（值 = 这只击杀点数的 50 / 10 倍）
    var kp := Points.kill_points_for(int(e.t.get("level", 1)), false)
    if bool(e.t["boss"]):
        call("_drop_nugget", e.node.position + Vector3(0.6, 0, 0), kp * 50, true)
    elif randf() < 0.01:
        call("_drop_nugget", e.node.position, kp * 10, false)
    # 蛋糕（生蛋用，用户 2026-10-23：“蛋糕类似金珠”）：头目必掉，普通怪 0.5%
    var EggRules := preload("res://game/pokemon_eggs.gd")
    if randf() < (EggRules.BOSS_CAKE_CHANCE if bool(e.t["boss"]) else EggRules.CAKE_CHANCE):
        call("_drop_nugget", e.node.position + Vector3(-0.6, 0, 0), 0, false, true)
    if e.t["boss"]:
        get_tree().create_timer(0.8, false).timeout.connect(
            _boss_reward.bind(bool(e.t["final"]), str(e.t["name"])))

# 战斗报告：记一次玩家掉血（hp_before 是这次掉血前的 HP）；顺带数 4 米内的活敌人（看密度）。
func _report_hit(kind: String, source: String, level: int, hp_before: float, move_name := "") -> void:
    battle_report.record(time, kind, source, level, hp_before - player_hp, player_hp, _nearby_enemy_count(), move_name)


func _nearby_enemy_count() -> int:
    if player == null:
        return 0
    var n := 0
    for e in enemies:
        if e.dying < 0.0 and e.node != null and is_instance_valid(e.node) \
                and player.position.distance_to(e.node.position) <= BattleReport.NEARBY_RADIUS:
            n += 1
    return n


# 受伤入口：dmg 已是原公式算好的最终伤害（防守方 DEF 已在公式里用过），这里不再二次减防、
# 也不再套“至少掉 1”。0 伤害（0 倍率免疫等）不减血、不闪、不出声。
func _hurt(dmg: float, _source = null) -> float:
    if dead:
        return 0.0
    var lost := maxf(0.0, dmg * debug_power)
    if lost <= 0.0:
        return 0.0
    # 半隐身（挖洞 / 飞翔…）时被专打这一招的命中：照原版打得到、有的 ×2（main/arts.gd SEMI_HITS）
    var semi_mult := _semi_hit_mult(_source)
    if semi_mult > 0.0:
        lost *= semi_mult
        _show_status_feedback("躲着也被「%s」打中了！" % str(MOVES.MOVES.get(str(_source.cur_move), {}).get("name", "")))
    # 护盾刚破的缓冲期 / 半隐身：伤害全挡（不弹字、不再消耗护盾）。
    elif run_clock < player_protect_until:
        return 0.0
    # 守住 / 看穿的护盾：挡下这一次伤害，然后进入冷却；挺住的护盾只在致命一击时触发（留 1 点血）。
    if player_shield == "protect" or (player_shield == "endure" and lost >= player_hp):
        var was := player_shield
        _break_shield(_source)
        _show_status_feedback("%s 的护盾挡住了攻击！" % _species_name(player_species_id) if was == "protect" else "%s 挺住了！" % _species_name(player_species_id))
        if was == "endure":
            lost = maxf(player_hp - 1.0, 0.0)
            if lost <= 0.0:
                return 0.0
        else:
            return 0.0
    # 新手保护（类似气势头带）：开局 EARLY_SASH_SECS 秒内，满血时挨的第一下不会致命，留 1 点血。
    if run_clock < EARLY_SASH_SECS and not early_sash_used and lost >= player_hp and player_hp >= maxf(1.0, stats.value("hp_max")) - 0.01:
        early_sash_used = true
        lost = maxf(player_hp - 1.0, 0.0)
        if lost <= 0.0:
            return 0.0
    # 携带道具·气势头带：致命一击时每个 10% 几率留 1 点血（原版 randSeedInt(10) < 个数）
    var band := int(run_held.get("FOCUS_BAND", 0))
    if band > 0 and lost >= player_hp and player_hp > 1.0 and HeldItems.focus_band_survives(band, _held_roll10()):
        lost = player_hp - 1.0
        _show_status_feedback("%s 靠气势头带撑住了！" % _species_name(player_species_id))
    # 携带道具·复活种子：倒下时以一半血复活、解除异常（原版 PokemonInstantReviveModifier），用掉
    if lost >= player_hp and _try_reviver_seed():
        return 0.0
    var hp_before := player_hp
    player_hp = maxf(0.0, player_hp - lost)
    if player_hp <= 0.0:
        _destiny_bond_trigger(_source)   # 同命
    _note_hurt(lost, _source)
    var src_name := "未知来源"
    var src_level := 0
    var src_move := ""
    if _source != null and "t" in _source:
        src_name = str(_source.t.get("name", "敌人"))
        src_level = int(_source.t.get("level", 0))
        if "cur_move" in _source and MOVES.MOVES.has(_source.cur_move):
            src_move = str(MOVES.MOVES[_source.cur_move]["name"])
    _report_hit("enemy", src_name, src_level, hp_before, src_move)
    _flash_sprite(player.get_child(0), Color(1, 0.4, 0.35))
    sfx.hurt()
    _ab_after_hurt(lost, _source)
    return lost


# 特性钩子（main/abilities.gd 覆写）：被敌人打中之后（胆怯 / 愤怒穴位…）、击倒敌人之后（自信过度 / 捡拾…）。
func _semi_hit_mult(_source) -> float:
    return 0.0   # 实现在 main/arts.gd（子类）


func _ab_after_hurt(_lost: float, _source) -> void:
    pass


func _ab_on_kill(_e: Enemy) -> void:
    pass


func _ab_refresh_player() -> void:
    pass


func _ab_on_enemy_damaged(_e: Enemy, _applied: float, _move: String) -> void:
    pass


func _ab_after_status(_unit, _effect: int, _toxic: bool) -> void:
    pass

# 记一次受伤：给“受击后蓄势”的招（双倍奉还 / 恶意追击 / 以牙还牙 / 瞬间移动）用。
# 物理招的伤害和来源单独记（双倍奉还只认最近一次物理伤害，来源是敌人本身；弹药 / 特殊招不算）。
func _note_hurt(lost: float, source) -> void:
    hurt_serial += 1
    hurt_at = run_clock
    hurt_any_dmg = lost
    hurt_any_src = source
    if source != null and "cur_move" in source and MOVES.MOVES.has(source.cur_move) \
            and str(MOVES.MOVES[source.cur_move]["category"]) == "特殊":
        hurt_spec_serial = hurt_serial
        hurt_spec_at = run_clock
        hurt_spec_dmg = lost
        hurt_spec_src = source
    if source != null and "cur_move" in source and MOVES.MOVES.has(source.cur_move) \
            and str(MOVES.MOVES[source.cur_move]["category"]) == "物理":
        hurt_phys_serial = hurt_serial
        hurt_phys_at = run_clock
        hurt_phys_dmg = lost
        hurt_phys_src = source


# 对敌入口：dmg 已是原公式最终伤害，不再减 DEF、不再套最小 1；0 伤害不误杀也不击退。
# 头目的分段伤害走 `_apply_enemy_damage`（普通怪路径不变）；被分段挡住 0 掉血时不闪 / 不击退 / 不出声。
func _damage(e: Enemy, dmg: float, push: Vector3, knock: float, _move := "") -> void:
    if e.dying >= 0.0:
        return
    var amount := dmg * debug_power
    if amount <= 0.0:
        return
    var before := e.hp
    _apply_enemy_damage(e, amount, false)
    var applied := before - e.hp
    if applied <= 0.0:
        return
    if _move != "":
        _ab_on_enemy_damaged(e, applied, _move)
        _held_on_hit(e, applied)
    e.kb = push * knock * float(e.t["knock"])
    e.pulse = 1.0
    _flash_sprite(e.node, Color(1.7, 1.7, 1.7))
    sfx.hit(e.node.position)
    if e.hp <= 0.0:
        _kill(e)


# ================= 头目分段伤害 / 破段强化接线 =================
# 唯一伤害落点：真实普通攻击与 `_enemy_status_damage`（中毒 / 灼伤 / 混乱自伤）都调这一处。
#   - 普通怪（segments<=0）：保持原 float 直扣路径，行为完全不变。
#   - 头目：走 `BossRules.apply_segmented_damage`（原分段公式，整数 HP / 原存储 index）。
#   - bypass 当前运行时恒 false：原 poison/burn 的 `t.damage(r)` 与混乱 `t.damageAndUpdate(o)`
func _apply_enemy_damage(e: Enemy, amount: float, bypass := false) -> void:
    # 闪光 / 神兽（不是头目）手下留情：你的招和持续伤害最多把它打到剩 1 血，要么抓要么等它走
    if (spare_special and (bool(e.shiny) or bool(e.legendary)) and not bool(e.t.get("boss", false))) or e.spared:
        amount = minf(amount, maxf(0.0, e.hp - 1.0))
    if e.segments <= 0:
        e.hp -= amount
        return
    var result: Dictionary = BossRules.apply_segmented_damage(
        int(e.t["hp"]), e.segments, e.segment_index, int(round(e.hp)), int(round(amount)), bypass)
    e.hp = float(result["hp"])
    e.segment_index = int(result["index"])
    if int(result["cleared"]) > 0:
        _handle_boss_segment_cleared(e, int(result["target"]), int(result["cleared"]))


# 破段强化：`BossRules.simulate_stat_boosts` 纯规则（含源 NaN 骰消费 + 5 选 1 + 源 aggregate），
# 这里只做「写到该敌人自己的阶段 + 按聚合结果播原演出」。己方 ATK/DEF/SPATK/SPDEF/SPD 独立
# [-6,6]；SPD 复用 `e.speed_stage`（吐丝 / 麻痹同一阶段）。基础六维不改。
# 致死 / 已死不强化（源 handleBossSegmentCleared 仍会 push，但本作按蓝图不复活、不留 FX）。
func _handle_boss_segment_cleared(e: Enemy, target_l: int, cleared: int) -> void:
    if cleared <= 0 or e.dying >= 0.0 or e.hp <= 0.0:
        return
    var batch: Dictionary = BossRules.simulate_stat_boosts(e.segments, target_l, cleared,
        Callable(self, "_boost_unit"))
    for play in batch["plays"]:
        var stats: Array = play["stats"]
        var levels := int(play["levels"])
        var any := false
        for st in stats:
            if clampi(_enemy_stage(e, int(st)) + levels, -6, 6) != _enemy_stage(e, int(st)):
                any = true
        for st in stats:
            _set_enemy_stage(e, int(st), clampi(_enemy_stage(e, int(st)) + levels, -6, 6))
        # 源：`o.filter(s=>s).length && moveAnimations` 才建 tileSprite + 播 stat_up；全无增量不播。
        if any:
            _play_stat_change_fx(stats, e)


# 0..4 -> 该敌人自己的五份能力阶段（顺序同源 ATK/DEF/SPATK/SPDEF/SPD）。
func _enemy_stage(e: Enemy, idx: int) -> int:
    match idx:
        0:
            return e.atk_stage
        1:
            return e.def_stage
        2:
            return e.spatk_stage
        3:
            return e.spdef_stage
        _:
            return e.speed_stage


func _set_enemy_stage(e: Enemy, idx: int, value: int) -> void:
    match idx:
        0:
            e.atk_stage = value
        1:
            e.def_stage = value
        2:
            e.spatk_stage = value
        3:
            e.spdef_stage = value
        _:
            e.speed_stage = value


# 源 `Ze(NaN)`（全局 frac）+ `randSeedInt(SPD+1)=Ze(5)`（每 Pokemon RNG）在本作都走这一颗可注入骰。
# 检查注入固定 0..1 序列即可验证「每个清段 1 次 NaN 骰、再 1 次 5 选 1」的准确耗骰。
func _boost_unit() -> float:
    if stat_boost_rand.is_valid():
        return float(stat_boost_rand.call())
    return randf()

func _flash_sprite(visual: Node3D, color: Color) -> void:
    var sprite: Sprite3D = visual.get_node("Sprite")
    if sprite.has_meta("flash_tween"):
        var previous: Tween = sprite.get_meta("flash_tween")
        if previous.is_valid():
            previous.kill()
    # 受击闪白：命中那一下先盖一层纯白剪影（0.12 秒淡出），再接原来的着色淡回。
    if visual.has_method("flash_white"):
        visual.call("flash_white")
    sprite.modulate = color
    var tw := sprite.create_tween()
    tw.tween_property(sprite, "modulate", Color.WHITE, 0.15)
    sprite.set_meta("flash_tween", tw)

# ================= 速度的三个用处（game/pokemon_speed.gd）=================

# 玩家有效速度 = 原作速度六维 × 速度能力等级倍率（高速移动 / 龙之舞写 player_spd_stage）。
func _player_effective_speed() -> float:
    if player_stats.size() < 6:
        return 0.0
    return float(player_stats[5]) * stat_stage_multiplier(player_spd_stage)


func _enemy_effective_speed(e: Enemy) -> float:
    return float(e.t["stats"][5]) * stat_stage_multiplier(e.speed_stage)


# 移动快慢 / 吸经验球距离共用的速度总倍率：速度系数（以绿毛虫速度为 1 倍，0.7..2.0）× 速度能力等级倍率，整体 0.25..3.0。
func _player_speed_factor() -> float:
    if player_stats.size() < 6:
        return 1.0
    var ref := PokemonSpeed.reference_speed(level, player_ivs, [1, 1, 1, 1, 1, 1])
    return minf(PokemonSpeed.movement_multiplier(float(player_stats[5]), float(ref), stat_stage_multiplier(player_spd_stage)) * _ab_speed_mult(null), PokemonSpeed.MOVE_MAX)


# 敌人的移动速度倍率：同一套，用敌人自己的速度六维 / 等级 / 速度等级（吐丝 -2 → ×0.5 仍按能力等级倍率）。
func _enemy_speed_multiplier(e: Enemy) -> float:
    var ref := PokemonSpeed.reference_speed(int(e.t["level"]), [], [1, 1, 1, 1, 1, 1])
    return PokemonSpeed.movement_multiplier(float(e.t["stats"][5]), float(ref), stat_stage_multiplier(e.speed_stage)) * _ab_speed_mult(e)


# 特性的速度倍率（叶绿素 / 拨沙 / 冲浪之尾 / 飞毛腿）。
func _ab_speed_mult(unit) -> float:
    var m := 1.0
    var has_status := _actor_status(unit).has_major()
    for key in _ab_keys(unit):
        m *= AB.speed_mult(str(key), weather, terrain, has_status)
    return m


# 吸经验球的实际距离（米）：基础吸附距离 × 速度系数。
func _magnet_radius() -> float:
    return float(stats.value("magnet")) * _player_speed_factor()


# 唯一「一般治疗」入口（旧掉落药、未来普通回血共用）。原一般 HealPhase 是
# floor(baseHeal * healingMultiplier)：有治愈护符时按原式取整；**没有护符时保持本作旧 float
# 分支精确算好后由 heal_item 直接落 HP，不会被护符二次乘）。
func heal(amount: float) -> void:
    if not dead and player_hp > 0.0:
        var mult := _healing_multiplier()
        var applied := floorf(amount * mult) if mult != 1.0 else amount
        var hp_before := player_hp
        player_hp = minf(stats.value("hp_max"), player_hp + applied)
        battle_report.record_heal(player_hp - hp_before)


# 商店伤药的精确治疗：amount 已按原 PokemonHpRestoreModifier 的固定 / 百分比分支算好，
# 这里只封顶到 max、不再乘任何护符倍率。0 HP / 已死 / 非正数不治疗（不复活）。
func heal_item(amount: int) -> void:
    if amount <= 0 or dead or player_hp <= 0.0:
        return
    var hp_before := player_hp
    player_hp = minf(stats.value("hp_max"), player_hp + float(amount))
    battle_report.record_heal(player_hp - hp_before)


# 商店全复药 / 未来同类道具的清状态：原 resetStatus 只清**主要异常**，混乱是独立 tag，
# 剩余层数与它自己的秒钟原样保留（不抽骰、不 -- 回合）。主要异常造成的当秒阻断缓存随之解除；
# 只有混乱时不清它的缓存（`player_status_blocked_major` 记的是不是主要异常挡的）。
func clear_major_status_item() -> bool:
    if player_status == null or not player_status.has_major():
        return false
    player_status.reset_major()
    if player_status_blocked_major:
        player_status_blocked = false
        player_status_blocked_major = false
    if not player_status.has_confusion() and player_clock != null:
        player_clock.stop()
    _refresh_player_status_ui()
    return true


# 树果：带着就自动吃（规则和数值见 game/pokemon_berries.gd）。每帧调一次，delta 是战斗时间。
#   木子果：一中主要异常就吃，当场解除；文柚果：血量降到 25% 以下就吃（低于回血招的 50%），回最大 HP 的 25%。
#   两次吃之间隔一段时间（文柚果 8 秒、木子果 1 秒），免得一口气吃光。
# 同命：实现在 main/arts.gd（子类覆盖）。
func _destiny_bond_trigger(_source) -> void:
    pass


# 携带道具·打中时：实现在 main/arts.gd（要用畏缩那套），这里留空给子类覆盖。
func _held_on_hit(_e: Enemy, _applied: float) -> void:
    pass


# 0..9 的骰（测试子类可以覆写成固定值）。
func _held_roll10() -> int:
    return randi() % 10


# 携带道具·吃剩的东西：每秒攒最大 HP 的 LEFTOVERS_RATE × 个数，攒满整点才回（本作改成慢回血，见规则文件）。
func _leftovers_tick(delta: float) -> void:
    var n := int(run_held.get("LEFTOVERS", 0))
    if n <= 0 or dead or player_hp <= 0.0:
        return
    leftovers_clock += delta
    if leftovers_clock < HeldItems.LEFTOVERS_SECONDS:
        return
    leftovers_clock -= HeldItems.LEFTOVERS_SECONDS
    var mx: float = stats.value("hp_max")
    if player_hp >= mx:
        leftovers_bank = 0.0
        return
    leftovers_bank += HeldItems.leftovers_heal(mx, n)
    if leftovers_bank >= 1.0:
        var whole := floorf(leftovers_bank)
        leftovers_bank -= whole
        heal(whole)


func _berry_tick(delta: float) -> void:
    _leftovers_tick(delta)
    call("_bell_tick", delta)   # 贝壳之铃每秒结一次（在子类 arts.gd 里）
    _held_second_tick(delta)
    _berry_gap = maxf(0.0, _berry_gap - delta)
    if _berry_gap > 0.0 or dead or player_hp <= 0.0:
        return
    var lum := int(berries.get("LUM", 0))
    if lum > 0 and player_status != null and (player_status.has_major() or player_status.has_confusion()):
        clear_major_status_item()
        if player_status.has_confusion():
            player_status.reset_confusion()
            if not player_status.has_major() and player_clock != null:
                player_clock.stop()
            _refresh_player_status_ui()
        if not _berry_pouch_saves():
            berries["LUM"] = lum - 1
        _persist_berries()
        _berry_gap = PokemonBerries.LUM_GAP
        safeguard_until = maxf(safeguard_until, run_clock + PokemonBerries.LUM_GUARD)   # 之后几秒不再中异常
        _berry_feedback("木子果", "异常解除，%d 秒内不会再中" % int(PokemonBerries.LUM_GUARD))
        return
    var sit := int(berries.get("SITRUS", 0))
    var max_hp := maxf(1.0, stats.value("hp_max")) if stats != null else 1.0
    if sit > 0 and player_hp <= max_hp * PokemonBerries.SITRUS_TRIGGER:
        var before := player_hp
        heal_item(PokemonBerries.sitrus_amount(max_hp))
        if not _berry_pouch_saves():
            berries["SITRUS"] = sit - 1
        _persist_berries()
        _berry_gap = PokemonBerries.SITRUS_GAP
        _berry_feedback("文柚果", "回复 %d 点" % int(round(player_hp - before)))


# 树果袋：每层 1/3 几率这颗不消耗（原版 randSeedInt(3) < 层数）。
func _berry_pouch_saves() -> bool:
    var n := _global_charm("BERRY_POUCH")
    return n > 0 and _berry_pouch_roll() < n


func _berry_pouch_roll() -> int:
    return randi() % 3


func _berry_feedback(berry_name: String, what: String) -> void:
    if hud != null and hud.has_method("show_banner"):
        hud.show_banner("吃下%s：%s" % [berry_name, what])


# ================= 异常状态接线：真实战斗时间 / DoT / 行动阻断 =================
# 规则层是 game/pokemon_status.gd（纯回合制），实时层是 game/pokemon_status_clock.gd（余数 + 缓存）。
# 这里只做「谁被打、谁掉血、谁这一秒不能出招」，不重写任何原规则，也不把状态放进共享 unit_cache。
#
# 一秒回合适配的边界（PROJECT_MAP / game/POKEMON_STATUS_SOURCE.md 第七节有记录）：
#   - 每个有状态的单位按累计的有效战斗 delta 走钟；每满 1.0 秒只推进一次 before_action + end_turn。
#   - main._process 的 not started / paused / choosing / evolving / finishing_capture / dead 门控在前，
#     所以暂停 / 进化 / 满槽选择时状态时间也停。
#   - 目标太远 / 没有技能就绪照样走秒：这是「回合换秒」，不是「有交互才走时间」。

# 状态数字 → 中文名（HUD / 头顶标识 / 反馈文案共用一处事实）。
const STATUS_NAMES := {
    PokemonStatus.POISON: "中毒",
    PokemonStatus.PARALYSIS: "麻痹",
    PokemonStatus.SLEEP: "睡眠",
    PokemonStatus.FREEZE: "冰冻",
    PokemonStatus.BURN: "灼伤",
}
const CONFUSION_NAME := "混乱"

# 通用状态动画 id ↔ 主要异常 effect。唯一映射表，禁止对 effect 做算术（见 fx/rogue_moves.gd::COMMON_ENUM：
# POISON=1→2010、PARALYSIS=3→2012、SLEEP=4→2013、FREEZE=5→2014、BURN=6→2015；混乱独立 2016/CONFUSION）。
const COMMON_BY_EFFECT := {
    PokemonStatus.POISON: "poison",
    PokemonStatus.PARALYSIS: "paralysis",
    PokemonStatus.SLEEP: "sleep",
    PokemonStatus.FREEZE: "frozen",
    PokemonStatus.BURN: "burn",
}
const CONFUSION_COMMON := "confusion"

func _common_for_effect(effect: int) -> String:
    return str(COMMON_BY_EFFECT.get(effect, ""))

# 主循环死亡判断用的阈值：DoT / 自伤只扣自己的真实 HP，不伪造命中 / 击退。
func _player_max_hp() -> float:
    return maxf(1.0, stats.value("hp_max"))


func _enemy_max_hp(e: Enemy) -> float:
    return maxf(1.0, float(e.t["hp"]))


# 三个主要异常的结果码：ok = 真的附加；already = 已有主要异常（不刷新）；immune = 类型免疫；
# invalid = 状态码不合法。睡眠成功时由 core 抽一次 cureTurn。
func _apply_major_status(target_status: PokemonStatus, effect: int, types: Array, toxic := false) -> String:
    if effect == PokemonStatus.NONE or not PokemonStatus.MAJOR_EFFECTS.has(effect):
        return "invalid"
    if target_status.has_major():
        return "already"
    if PokemonStatus.is_immune(effect, types):
        return "immune"
    return "ok" if target_status.try_set_major(effect, types, toxic) else "already"


# 混乱结果码：ok = 真的附加（抽一次 2..4）；already = 已有混乱（重复不刷新）。
func _apply_confusion_status(target_status: PokemonStatus) -> String:
    if target_status.has_confusion():
        return "already"
    return "ok" if target_status.try_confuse_from_source() else "already"


# ================= 真实 actor 附加入口（玩家 / 敌人共用）=================
# 单一生产入口：附加 + 起钟 + 刷新标识 + 「成功才播一次对应 common」。
# unit == null 表示玩家（其状态 / 钟 / 根节点是 main 上的 player_status / player_clock / player）。
# 不是 debug 注入：调用方传进来的就是真实单位。重复 / 类型免疫 / invalid 都不播、不重置状态与时钟。

func _actor_status(unit) -> PokemonStatus:
    if unit == null:
        return player_status
    return _unit_status(unit)


func _actor_clock(unit) -> StatusClock:
    if unit == null:
        return player_clock
    if "clock" in unit:
        var c = unit.clock
        return c if c is StatusClock else null
    return null


# 类型免疫仍从真实 types 转 core 数字 id（玩家 / 敌人各自的真实物种属性）。
func _actor_type_ids(unit) -> Array:
    if unit == null:
        return _player_type_ids()
    return _enemy_type_ids(unit)


func _actor_refresh_ui(unit) -> void:
    if unit == null:
        _refresh_player_status_ui()
    else:
        _refresh_enemy_status_ui(unit)


# 特性（game/pokemon_abilities.gd）：免疫这种异常（柔软 / 干劲 / 免疫 / 我行我素 / 叶子防守）。
func _ab_blocks_status(unit, status_name: String) -> bool:
    for key in _ab_keys(unit):
        if AB.blocks_status(str(key), status_name, weather):
            return true
    return false


func _major_status_name(effect: int, toxic := false) -> String:
    match effect:
        PokemonStatus.POISON:
            return "toxic" if toxic else "poison"
        PokemonStatus.PARALYSIS:
            return "paralysis"
        PokemonStatus.SLEEP:
            return "sleep"
        PokemonStatus.FREEZE:
            return "freeze"
        PokemonStatus.BURN:
            return "burn"
    return ""


# 穿透石板：目标是敌人（unit 不为空）且玩家带着它。
func _status_pierce(unit) -> bool:
    return unit != null and int(run_held.get("STATUS_PIERCE", 0)) > 0


# 主要异常：成功得到任一主要异常后播一次对应 common（原 ObtainStatusEffectPhase）。
func _actor_apply_major_status(unit, effect: int, toxic := false) -> String:
    var st: PokemonStatus = _actor_status(unit)
    if st == null:
        return "invalid"
    if unit == null and run_clock < safeguard_until:
        return "immune"   # 神秘守护
    var pierce := _status_pierce(unit)   # 携带道具·穿透石板：给敌人上异常无视特性 / 属性免疫
    if not pierce and _ab_blocks_status(unit, _major_status_name(effect, toxic)):
        return "immune"
    var result := _apply_major_status(st, effect, [] if pierce else _actor_type_ids(unit), toxic)
    if result == "ok":
        var clk: StatusClock = _actor_clock(unit)
        if clk != null and not clk.running:
            clk.activate()
        _play_common_fx(_common_for_effect(effect), unit)
        _ab_after_status(unit, effect, toxic)
    _actor_refresh_ui(unit)
    return result


# 混乱：成功 onAdd 播一次 common-confusion（原 ConfusedTag.onAdd）；onOverlap 重复只报消息、不播不刷新。
func _actor_apply_confusion_status(unit) -> String:
    var st: PokemonStatus = _actor_status(unit)
    if st == null:
        return "invalid"
    if unit == null and run_clock < safeguard_until:
        return "immune"   # 神秘守护
    if not _status_pierce(unit) and _ab_blocks_status(unit, "confusion"):
        return "immune"
    var result := _apply_confusion_status(st)
    if result == "ok":
        var clk: StatusClock = _actor_clock(unit)
        if clk != null and not clk.running:
            clk.activate()
        _play_common_fx(CONFUSION_COMMON, unit)
    _actor_refresh_ui(unit)
    return result


# 治愈反馈文本。源 reset 时只有消息、没有新技能动画：本作只给一次短中文横幅，
# 不凭空生成“治愈 FX”。一个主要状态治愈不清混乱，混乱减到 0 也不清主要状态（core 已保证）。
func _cure_text(unit, cured_effect: int, confusion_cleared: bool) -> String:
    var who := "你" if unit == null else str(unit.t.get("name", "敌人"))
    if confusion_cleared:
        return "%s从混乱中清醒了" % who
    match cured_effect:
        PokemonStatus.SLEEP:
            return "%s醒了" % who
        PokemonStatus.FREEZE:
            return "%s解冻了" % who
    return "%s的异常解除了" % who


# 字符串属性（"火" / "毒" …）→ data/pokemon_type_chart.gd 的属性数字。
# 不认识的属性返回 -1，调用方跳过免疫判定（不当 0 = 一般，也不把 int("火") 悄悄变 0）。
func _type_ids(types: Array) -> Array:
    var out: Array = []
    for entry in types:
        var id: int = int(TypeChart.INDEX.get(str(entry), -1))
        if int(id) >= 0:
            out.append(int(id))
    return out


func _player_type_ids() -> Array:
    return _type_ids(_player_types())


func _enemy_type_ids(e: Enemy) -> Array:
    return _type_ids(_enemy_types(e))


# 每个单位各自一份状态；这里只做查询，实例本身在 state.gd::Enemy / player_status。
func _has_actor_status() -> bool:
    return player_status != null and (player_status.has_major() or player_status.has_confusion())


func _unit_status(unit) -> PokemonStatus:
    if unit == null or not (unit is Object) or not ("status" in unit):
        return player_status
    var st = unit.status
    return st if st is PokemonStatus else null


# 玩家的有效六维（含临时防御等级 / 速度等级），混乱自伤与麻痹速度都读自己这一份，
# 绝不读敌对方的 stats。返回 [level, effective_atk, effective_def, effective_speed]。
func _player_effective_combat_stats() -> Array:
    var atk := floorf(float(player_stats[1]) * stat_stage_multiplier(0))
    var dfn := floorf(float(player_stats[2]) * stat_stage_multiplier(player_def_stage))
    var spd := floorf(float(player_stats[5]) * stat_stage_multiplier(0))
    return [level, atk, dfn, spd]


func _enemy_effective_combat_stats(e: Enemy) -> Array:
    var six: Array = e.t["stats"]
    # 混乱自伤读己方有效 ATK/DEF：破段强化后的独立 ATK/DEF 阶段要进来（会心忽略正等级仍由公式处理）。
    var atk := floorf(float(six[1]) * stat_stage_multiplier(e.atk_stage))
    var dfn := floorf(float(six[2]) * stat_stage_multiplier(e.def_stage))
    var spd := floorf(float(six[5]) * stat_stage_multiplier(e.speed_stage))
    return [int(e.t["level"]), atk, dfn, spd]


# 中毒 / 灼伤 end-turn 持续伤害：只扣自己的真实 HP。0 伤害不闪不击退、不伪造命中。
func _player_dot(damage: int) -> bool:
    if damage <= 0 or dead:
        return false
    for key in _ab_keys(null):
        if AB.blocks_indirect(str(key)):
            return false   # 魔法防守：不受攻击以外的伤害
    if float(damage) >= player_hp and _try_reviver_seed():
        return true
    player_hp = maxf(0.0, player_hp - float(damage))
    return true


# 携带道具·复活种子：倒下时以一半血复活、解除异常（原版 PokemonInstantReviveModifier），用掉。返回 true = 救下来了。
func _try_reviver_seed() -> bool:
    if int(run_held.get("REVIVER_SEED", 0)) <= 0:
        return false
    _use_up_held("REVIVER_SEED")
    player_hp = maxf(1.0, floorf(stats.value("hp_max") / 2.0))
    clear_major_status_item()
    if player_status != null and player_status.has_confusion():
        player_status.reset_confusion()
        _refresh_player_status_ui()
    _show_status_feedback("%s 吃下复活种子，站起来了！" % _species_name(player_species_id))
    return true


# 敌人的持续伤害 / 自伤：走 `_apply_enemy_damage`（头目同样按分段结算，不旁路），
# 仍走 `_kill`（已有死亡 / 掉落 / 经验 / 结算路径，只触发一次）。
# debug_power 与击退都不参与，避免用调试倍率调整异常节奏。
func _enemy_status_damage(e: Enemy, damage: int) -> void:
    if damage <= 0 or e.dying >= 0.0:
        return
    _apply_enemy_damage(e, float(damage), false)
    e.pulse = 1.0
    if e.hp <= 0.0:
        _kill(e)


# 每一个有效战斗秒：先 before_action（主要异常 → 混乱）并处理自伤 / 死亡，再 end_turn 持续伤害。
# 返回 false 表示当秒中途死亡 / 事件取消，实时钟立刻停在当秒（余数不保留、不补下一步、不再掷骰）。
func _player_status_tick() -> bool:
    if player_status == null:
        return false
    if player_hp <= 0.0:
        # 已经死了：不再推进行动判定、不再掷骰（死后本帧不出招，死亡结算走 _settle）。
        return false
    var st := _player_effective_combat_stats()
    var conf_before: int = player_status.confusion_turn_count
    var r: Dictionary = player_status.before_action(int(st[0]), float(st[1]), float(st[2]))
    player_status_blocked = not bool(r["can_act"])
    # 主要异常**真的取消这一逻辑行动**才播阻断 common：麻痹判定通过 / 睡醒 / 解冻当次都不播。
    var blocked_by := int(r["blocked_by"])
    # 记下当秒阻断是不是主要异常造成的：全复药清主要异常后只解除这部分缓存，混乱自伤的缓存不动。
    player_status_blocked_major = blocked_by != PokemonStatus.NONE
    if blocked_by != PokemonStatus.NONE:
        _play_common_fx(_common_for_effect(blocked_by), null)
    elif conf_before > 0 and player_status.confusion_turn_count > 0:
        # 混乱有效 MOVE lapse：主要没阻断、先 --count 后仍 >0 才播（正常行动与自伤都播）；
        # 减到 0 解除那次不播。
        _play_common_fx(CONFUSION_COMMON, null)
    var cured := int(r["cured"])
    if cured != PokemonStatus.NONE and hud != null:
        hud.show_banner(_cure_text(null, cured, false))
    if bool(r["confusion_cleared"]) and hud != null:
        hud.show_banner(_cure_text(null, PokemonStatus.NONE, true))
    if bool(r["self_hit"]):
        var self_hp := player_hp
        if _player_dot(int(r["self_hit_damage"])):
            _report_hit("dot", "混乱自伤", 0, self_hp)
        if hud != null:
            hud.show_banner("混乱中的自己撞了上来 -%d" % int(r["self_hit_damage"]))
    _refresh_player_status_ui()
    if player_hp <= 0.0:
        _finish_player_status_on_death()
        return false
    # PostTurn 中毒 / 灼伤：先按原公式扣血，再播这一秒的 common（原伤害后播放；致死也有这次发动）。
    player_status.residual_period = maxi(1, int(residual_secs))
    var end_r: Dictionary = player_status.end_turn(int(_player_max_hp()))
    var dot_effect := int(end_r["effect"])
    var dot_hp := player_hp
    if _player_dot(int(end_r["damage"])):
        _report_hit("dot", ("剧毒" if player_status.toxic else "中毒") if dot_effect == PokemonStatus.POISON else "灼伤", 0, dot_hp)
    if dot_effect != PokemonStatus.NONE:
        _play_common_fx(_common_for_effect(dot_effect), null)
    if player_hp <= 0.0:
        # 本秒 DoT 致死：立刻停在这一秒，不许 2.5 秒大 delta 在尸体上再补一次 before_action。
        _finish_player_status_on_death()
        return false
    return true


# 状态伤害致死：清掉玩家状态并停钟，余数清零、之后不再推进（真正结算仍由 main._process 的
# `player_hp <= 0 → _settle("dead")` 走已有死亡 / 掉落 / 经验路径，只触发一次）。
func _finish_player_status_on_death() -> void:
    if player_status != null:
        player_status.reset_all()
    player_clock.stop()
    player_status_blocked = false
    player_status_blocked_major = false
    player_status_key = ""
    if hud != null and hud.has_method("set_player_status"):
        hud.set_player_status("")


# 实时钟每秒 tick 前的包装：先跑本秒 before_action（会写 player_status_blocked），
# 当秒被挡住就按契约消耗已就绪招的原冷却（不放特效、不扣目标 HP、不增加释放计数）。
func _player_status_clock_tick() -> bool:
    var keep := _player_status_tick()
    if player_status_blocked:
        _consume_blocked_moves()
    return keep


func _enemy_status_tick_body(e: Enemy) -> bool:
    if e == null or e.status == null:
        return false
    var es := _enemy_effective_combat_stats(e)
    var conf_before: int = e.status.confusion_turn_count
    var er: Dictionary = e.status.before_action(int(es[0]), float(es[1]), float(es[2]))
    if e.clock != null:
        # 当秒判定写回该敌人自己的缓存（时钟默认放行，只有这里能置 true）。
        e.clock.blocked = not bool(er["can_act"])
    var blocked_by := int(er["blocked_by"])
    if blocked_by != PokemonStatus.NONE:
        _play_common_fx(_common_for_effect(blocked_by), e)
    elif conf_before > 0 and e.status.confusion_turn_count > 0:
        _play_common_fx(CONFUSION_COMMON, e)
    var cured := int(er["cured"])
    if cured != PokemonStatus.NONE:
        _show_status_feedback(_cure_text(e, cured, false))
    if bool(er["confusion_cleared"]):
        _show_status_feedback(_cure_text(e, PokemonStatus.NONE, true))
    if bool(er["self_hit"]):
        _enemy_status_damage(e, int(er["self_hit_damage"]))
    _refresh_enemy_status_ui(e)
    if e.dying >= 0.0:
        return false
    e.status.residual_period = maxi(1, int(residual_secs))
    var end_r: Dictionary = e.status.end_turn(int(_enemy_max_hp(e)))
    var dot_effect := int(end_r["effect"])
    _enemy_status_damage(e, int(end_r["damage"]))
    if dot_effect != PokemonStatus.NONE:
        # 原伤害后播这一秒的发动；致死也播。死亡停步由返回 false 处理（不再补下一秒）。
        _play_common_fx(_common_for_effect(dot_effect), e)
    return e.dying < 0.0


# 当秒被状态挡住：已就绪的尝试消耗原冷却，但不放原特效、不扣目标 HP、不增加实际释放计数。
# 实时钟在每秒 tick 前通过闭包调用它（见 _enemy_status_tick / _status_tick）。
func _consume_blocked_moves() -> void:
    for id: String in active_moves:
        if not MOVES.is_implemented(id):
            continue
        if float(move_timer.get(id, 0.0)) <= 0.0:
            move_timer[id] = _cd(id)


# 玩家钟：每帧按有效战斗 delta 推进（main._process 的战斗门控之后才调）。
func _status_tick(delta: float) -> void:
    if player_status == null:
        return
    player_clock.update(player_status, Callable(self, "_player_status_clock_tick"), delta)
    _refresh_player_status_ui()


# 单个敌人的钟：在 enemies.gd 的每敌人循环里调用（每个敌人一份状态 + 一份钟）。
func _enemy_status_tick(e: Enemy, delta: float) -> void:
    if e.status == null:
        return
    e.clock.update(e.status, Callable(self, "_enemy_status_tick_body").bind(e), delta)


# 这个单位「现在」能不能出招。两层合成，都不掷骰、不推进计数：
#   1) 睡眠 / 冰冻：附加当帧就立刻停手（原契约：不必等第一个逻辑秒）。
#   2) 当秒判定缓存 `blocked`：主要异常（麻痹 / 睡眠 / 冰冻）与混乱在每秒 tick 时写。
# 麻痹的「当秒不能出招」在整秒时才判定，所以缓存到下一整秒前一直有效，不会每帧重掷。
func _unit_can_act(unit) -> bool:
    if _status_stops_move(unit):
        return false
    if unit == null:
        return not player_status_blocked
    return not unit.clock.blocked


# 玩家自动出招的豁免：死后本帧不出招 + 上面两层。
func _can_act() -> bool:
    if dead or player_hp <= 0.0:
        return false
    return _unit_can_act(null)


# 出招前的当秒豁免（群体释放时每目标各判一次，但共用同一个缓存，不重复掷）。
func _enemy_can_act(e: Enemy) -> bool:
    return _unit_can_act(e)


# ================= 状态数值换算（只读 core，不改公式）=================

# 灼伤末端：原公式整式 ceil 之后再 floor(/2)，只作用于普通物理招，特殊招不减。
# 放在 _player_move_damage / _enemy_move_damage 的最后一步，会心照原算完再减半。
func _burn_physical(id: String, damage: float, attacker_status: PokemonStatus) -> float:
    if attacker_status == null or not attacker_status.has_major():
        return damage
    if attacker_status.major_effect != PokemonStatus.BURN:
        return damage
    var category := str(MOVES.MOVES[id]["category"])
    if category != "物理":
        return damage
    return float(PokemonStatus.burn_physical_damage(int(damage)))


# 麻痹世界移速。**原能力 SPD 与本作世界米/秒是两个单位**，不能对米/秒做 bitshift。
# 照原 `getBattleStat` 的 SPD 段：有效原 SPD = `floor(raw_spd × 等级倍率)`，麻痹再 `int(...) >> 1`
# （core 的 `paralysis_speed`），最后用「有麻痹 / 无麻痹」这两个有效 SPD 的**比值**缩放已有米/秒。
#   raw_spd = 该 actor 的原作速度六维（玩家 `player_stats[5]`，敌人 `t["stats"][5]`）；
#   stage   = 该 actor 的速度能力等级（玩家当前 0，敌人是吐丝叠加的 `speed_stage`）。
# 无麻痹时**原样返回**（旧移速路径完全不动，不做 floor）。有效 SPD 降到 0 就是真的停，不擅加 min1。
func _paralyzed_move_speed(world_speed: float, status: PokemonStatus, raw_spd: float, stage: int = 0) -> float:
    if status == null or status.major_effect != PokemonStatus.PARALYSIS:
        return world_speed
    var scaled := raw_spd * stat_stage_multiplier(stage)
    var normal_spd := floorf(scaled)
    if normal_spd <= 0.0:
        return 0.0
    var para_spd := float(PokemonStatus.paralysis_speed(scaled))
    return world_speed * (para_spd / normal_spd)


# 睡眠 / 冰冻停止主动移动（麻痹只缩放 SPD，不额外禁止走路；当秒不能出招也不强加随机乱走）。
func _status_stops_move(unit) -> bool:
    var st: PokemonStatus = _unit_status(unit)
    if st == null:
        return false
    return st.major_effect == PokemonStatus.SLEEP or st.major_effect == PokemonStatus.FREEZE


# ================= 状态标识与反馈（最小 UI）=================

func _player_status_label() -> String:
    if player_status == null:
        return ""
    var names: Array = []
    if player_status.has_major():
        names.append(str(STATUS_NAMES.get(player_status.major_effect, "异常")))
    if player_status.has_confusion():
        names.append(CONFUSION_NAME)
    return " · ".join(names)


func _refresh_player_status_ui() -> void:
    var text := _player_status_label()
    if text == player_status_key:
        return
    player_status_key = text
    if hud != null:
        hud.set_player_status(text)


func _refresh_enemy_status_ui(e: Enemy) -> void:
    if e.status == null:
        return
    var names: Array = []
    if e.status.has_major():
        names.append(str(STATUS_NAMES.get(e.status.major_effect, "异常")))
    if e.status.has_confusion():
        names.append(CONFUSION_NAME)
    var text := " ".join(names)
    if text == e.status_key:
        return
    e.status_key = text
    if e.node != null and is_instance_valid(e.node) and e.node.has_method("set_status_text"):
        e.node.set_status_text(text)


# 附加结果 → 玩家能看懂的反馈。ok / already / immune / invalid 各写清。
func _status_feedback(target_name: String, name: String, result: String) -> String:
    match result:
        "ok":
            return "%s %s了！" % [target_name, name]
        "already":
            return "%s 已经%s了" % [target_name, name]
        "immune":
            return "%s 对%s没有效果" % [target_name, name]
    return "%s 没有效果" % target_name
