extends "res://main/meta_flow.gd"
# 自动战斗、移动、城镇入口和有限时长的截图模式。
const Biomes := preload("res://data/biomes.gd")
const ShopPage := preload("res://ui/pokemon_shop.gd")
static var skip_title := false
var capture_secs := 20.0
var start_time := 0.0
var still := false
var cam_zoom := 1.0
var snap_prefix := ""
var snap_timer := 0.5
var snap_n := 0
var spawn_at_start: PackedStringArray = []
var finishing_capture := false
# 本局出发地 map_id：声明在 main/state.gd（敌人等级带要读它）；由城镇 selected_map_id() 传入；默认和回退都是 plains。

func _ready() -> void:
    Engine.time_scale = 1.0
    # 当前存档槽（没被测试注入别的路径时才按槽取）：默认 1 号槽 = 原来的 pokemon_points.cfg。
    if points_path == Points.DEFAULT_PATH:
        points_path = SaveSlots.path_for(SaveSlots.current())
    # 场景加载就读一次持久点数余额（城镇要显示它；真正开新局时 start_run 会再读一次同一文件）。
    _points_begin_run()
    var args := OS.get_cmdline_user_args()
    for a in args:
        if a.begins_with("capture"):
            capture = true
            if a.contains("="):
                capture_secs = float(a.get_slice("=", 1))
        elif a == "forceshiny":
            shiny_force = true
            push_warning("forceshiny 已开启：所有野生敌人必闪光（调试参数；正常游玩去掉它，闪光率恢复 1/1024）")
        elif a == "still":
            still = true
        elif a == "zoom":
            cam_zoom = 0.5
        elif a.begins_with("stress="):
            stress = clampi(int(a.trim_prefix("stress=")), 0, MAX_ENEMIES)
        elif a.begins_with("time="):
            start_time = maxf(0.0, float(a.trim_prefix("time=")))
        elif a.begins_with("power="):
            debug_power = maxf(0.0, float(a.trim_prefix("power=")))
        elif a.begins_with("offer="):
            force_offer = a.trim_prefix("offer=").split(",", false)
        elif a.begins_with("seed="):
            seed(int(a.trim_prefix("seed=")))
        elif a.begins_with("spawn="):
            spawn_at_start = a.trim_prefix("spawn=").split(",", false)
        elif a.begins_with("snap="):
            snap_prefix = a.trim_prefix("snap=")
    card_defs = CARDS.by_id()
    for id in card_defs:
        card_lv[id] = 0
    # 主角模板是旧世界模板的**深副本**：之后按当前准确 profile 同步物种 / 名字 / 六维输入 / 属性，
    # 不把只读全局 UNITS 常量当成会变的玩家对象，也不与它共享数组。
    player_unit = UNITS.UNITS[UNITS.PLAYER].duplicate(true)
    _build_world()
    _build_player()
    scenery = preload("res://world/scenery.gd").new()
    add_child(scenery)
    scenery.setup(player)
    sfx = preload("res://audio/sfx.gd").new()
    add_child(sfx)
    _build_hud()
    hud.visible = false
    _aim_camera()
    PausePage.apply_saved()
    _set_cursor()
    pause_page = PausePage.new()
    add_child(pause_page)
    pause_page.resume_pressed.connect(_resume)
    pause_page.xp_max_provider = _exp_charm_mult
    pause_page.xp_rate_changed.connect(func(pct: int) -> void: xp_rate_pct = pct)
    xp_rate_pct = PausePage.saved_xp_rate_pct()
    _load_tuning()
    pause_page.tuning_changed.connect(_load_tuning)
    pause_page.abandon_pressed.connect(_abandon)
    # 商店第 2 段：城镇「商店」入口 + 战斗 Esc 局内商店；落款 / 规则都在 state + game/pokemon_shop.gd。
    shop_page = ShopPage.new()
    add_child(shop_page)
    shop_page.purchase_pressed.connect(_shop_buy)
    shop_page.resume_pressed.connect(_resume)
    shop_page.settings_pressed.connect(_on_shop_settings)
    shop_page.abandon_pressed.connect(_abandon)
    shop_page.closed.connect(_on_town_shop_closed)
    shop_page.back_pressed.connect(_shop_back_to_capture)
    shop_page.ball_chosen.connect(_on_shop_ball_chosen)
    pause_page.settings_returned.connect(_on_shop_settings_return)
    # 捕获第 2 段：战斗内五球小 HUD + 地面选圈。只发信号，库存 / 判定 / 落盘都在 state / game。
    capture_page = CapturePage.new()
    add_child(capture_page)
    capture_page.call("setup", cam, Callable(self, "_capture_hud_state"))
    capture_page.connect("ball_pressed", _on_capture_ball_pressed)
    capture_page.connect("throw_requested", _on_capture_throw_requested)
    capture_page.connect("cancelled", _cancel_ball_aim)
    capture_page.connect("shop_pressed", _on_capture_shop_pressed)
    capture_page.connect("resume_pressed", _resume)
    capture_page.connect("detail_pressed", _on_capture_detail_pressed)
    capture_page.connect("settings_pressed", _on_capture_settings_pressed)
    capture_page.connect("teleport_requested", _begin_teleport_aim)
    var shot := args.has("townshot") or args.has("selectshot")
    var overview := args.has("townoverview")
    var via_town := args.has("viaselect")
    if (capture or stress > 0 or args.has("skipselect")) and not (via_town or shot or overview):
        start_run()
        return
    town_page = RogueStarter.new() if _use_rogue_starter() else TownPage.new()
    town_page.start_level_provider = func(sid: int) -> int:
        var w = points_wallet if points_wallet != null else Points.new(points_path)
        return 1 + w.candy_for(sid) * (1 + int(w.charm_stacks.get("CANDY_JAR", 0)))
    add_child(town_page)
    town_page.setup(player_portrait, player_unit)
    town_page.set_points(_points_total())
    town_page.set_collection(_collection_snapshot())
    town_page.depart_pressed.connect(_on_town_depart)
    town_page.title_pressed.connect(_back_to_title)
    town_page.shop_pressed.connect(_on_town_shop)
    if town_page.has_signal("refresh_requested"):
        town_page.refresh_requested.connect(_refresh_town_page)
        town_page.buy_requested.connect(_on_starter_buy)
        town_page.move_toggle_requested.connect(_on_starter_buy)
        if town_page.has_signal("ability_slot_requested"):
            town_page.ability_slot_requested.connect(_on_ability_slot)
        if town_page.has_signal("favorite_requested"):
            town_page.favorite_requested.connect(func(sid: int, on: bool):
                if points_wallet != null:
                    points_wallet.set_favorite(sid, on))
        if town_page.has_signal("nickname_requested"):
            town_page.nickname_requested.connect(func(sid: int, nick: String):
                if points_wallet != null:
                    points_wallet.set_nickname(sid, nick)
                if town_page.has_method("show_message"):
                    town_page.show_message(("起名「%s」" % nick) if nick != "" else "去掉了名字"))
        if town_page.has_signal("learn_plan_requested"):
            town_page.learn_plan_requested.connect(func(sid: int, mid: String):
                if points_wallet != null:
                    if mid == "":
                        points_wallet.clear_learn_plan(sid)
                    else:
                        points_wallet.toggle_learn_plan(sid, mid))
        if town_page.has_signal("fusion_requested"):
            if town_page.has_signal("breed_requested"):
                town_page.breed_requested.connect(_on_breed)
            town_page.fusion_requested.connect(func(sid: int, pid: int):
                if points_wallet != null:
                    points_wallet.set_fusion(sid, pid)
                _refresh_town_page()
                if town_page.has_method("show_message"):
                    town_page.show_message(("下一局和「%s」融合出发" % _species_name(pid)) if pid > 0 else "不融合了"))
        if town_page.has_signal("nature_requested"):
            town_page.nature_requested.connect(func(root_id: int, nid: int):
                if points_wallet != null:
                    points_wallet.set_nature_pick(root_id, nid)
                if town_page.has_method("show_message"):
                    var ncount := (points_wallet.natures_for(root_id) as Array).size() if points_wallet != null else 1
                    town_page.show_message("性格换成「%s」，下一局开局按它算六维；这一系抓到过 %d 种性格，点一下或按 N 换" % [PokemonGrowth.nature_label(nid), ncount]))
        if town_page.has_signal("passive_requested"):
            town_page.passive_requested.connect(_on_passive_request)
    title_page = TitlePage.new()
    add_child(title_page)
    title_page.start_pressed.connect(func(): title_page.close(); town_page.set_points(_points_total()); town_page.set_collection(_collection_snapshot()); town_page.open_skills())
    title_page.skills_pressed.connect(func(): title_page.close(); town_page.open_skills())
    title_page.slot_selected.connect(_on_slot_selected)
    title_page.settings_pressed.connect(func(): title_page.close(); pause_page.open_settings(true))
    pause_page.closed.connect(func(): if not started: title_page.open())
    if skip_title or via_town or shot or overview:
        if overview:
            town_page.open_overview()
        else:
            town_page.open_skills()
    else:
        title_page.open()
    skip_title = false
    if shot or overview or args.has("titleshot"):
        for i in 6:
            await get_tree().process_frame
        await _shot("res://outputs/town_overview.png" if overview else ("res://outputs/town_skills.png" if shot else "res://outputs/title.png"))
        get_tree().quit()
    elif via_town:
        await get_tree().create_timer(0.5).timeout
        town_page._depart_btn.pressed.emit()

# 切换存档槽：记下选择，整个场景重新载入（点数 / 糖果 / 捕获 / 护符等所有读档状态一次刷新，不留旧档残影）。
func _on_slot_selected(slot: int) -> void:
    if slot == SaveSlots.current():
        return
    SaveSlots.set_current(slot)
    skip_title = false
    get_tree().reload_current_scene()


# 设置页里的三个系数（游戏速度 / 敌人密度 / 捕捉圈大小）：开局和每次改动都重读，局内改了立刻生效。
func _load_tuning() -> void:
    game_speed = PausePage.saved_tuning("game_speed")
    enemy_density = PausePage.saved_tuning("enemy_density")
    capture_ring_scale = PausePage.saved_tuning("capture_ring")
    attack_range_scale = PausePage.saved_tuning("attack_range")
    points_rate_scale = 1.0   # 点数滑块收掉了（用户 2026-10-23）：倍率改由护身金币给
    attack_cd_scale = PausePage.saved_tuning("attack_cd")
    legendary_hp_scale = PausePage.saved_tuning("legendary_hp")
    shiny_hp_scale = PausePage.saved_tuning("shiny_hp")
    shiny_chance = clampf(SHINY_CHANCE * PausePage.saved_tuning("shiny_rate"), 0.0, 1.0)   # 闪光几率 = 原版基础几率 × 设置里的倍率
    enemy_range_scale = attack_range_scale   # 用户 2026-10-21：敌人攻击距离跟着同一条“攻击距离”一起变
    show_ranges = PausePage.saved_flag("show_ranges")
    newbie_tips = PausePage.saved_flag("newbie_tips", true)
    squad_on = PausePage.saved_flag("squad", false)
    var was_outline := outline_uncaught
    outline_uncaught = PausePage.saved_flag("outline_uncaught")
    if was_outline != outline_uncaught and started:
        _refresh_base_outlines()
    if waves != null:
        waves.density = enemy_density


# 用哪个选宠页：真实游戏（有画面）= 原生 UI 的新页；无界面（headless，也就是自动检查）和设了环境变量 OLD_TOWN 时仍用旧的城镇页，
func _use_rogue_starter() -> bool:
    return USE_ROGUE_STARTER and DisplayServer.get_name() != "headless" and OS.get_environment("OLD_TOWN") == ""


# 选宠页（原生 UI）直接从钱包读图鉴 / 闪光 / 通关 / 糖果 / 技能机器 / 开局招留下名单 / 点数。
func _refresh_town_page() -> void:
    if town_page == null or not town_page.has_method("refresh_from"):
        return
    if points_wallet == null:
        _points_begin_run()
    town_page.refresh_from(points_wallet)


# 选宠页里买糖果 / 带上 / 留下开局招 / 带上 / 取下技能机器：走同一条商店购买入口（_shop_buy），结果显示在页面底部。
func _on_starter_buy(product_id: String) -> void:
    var result: Dictionary = _shop_buy(product_id)
    _refresh_town_page()
    if town_page != null and town_page.has_method("show_message"):
        town_page.show_message(_shop_message(product_id, result))


# 抓宠界面“宠物详情”：把当前上场宠物的资料打包给详情页（只读）。
var detail_page: CanvasLayer = null


func _on_capture_detail_pressed() -> void:
    if not (capture_pause_mode and started and not dead and not settled):
        return
    if detail_page == null:
        detail_page = preload("res://ui/pokemon_detail.gd").new()
        add_child(detail_page)
    detail_page.call("open", _detail_snapshot())


# 详情页头像：超级 / 超极巨形态用它自己的图。
func _detail_portrait() -> Texture2D:
    if not player_special_form.is_empty() and player != null and player.get_child_count() > 0 and player.get_child(0).has_method("portrait_for_form"):
        var t: Texture2D = player.get_child(0).portrait_for_form(player_species_id, str(player_special_form["sprite_key"]), player_shiny_variant)
        if t != null:
            return t
    return _portrait_for(player_species_id)


func _detail_snapshot() -> Dictionary:
    var moves: Array = []
    for id: String in active_moves:
        if MOVES.MOVES.has(id):
            moves.append({"name": str(MOVES.MOVES[id]["name"]), "info": _move_info(id).replace(str(MOVES.MOVES[id]["name"]) + "　", ""), "level": int(move_lv.get(id, 1))})
    var ab_key := player_ability
    var ability := {}
    if ab_key != "":
        ability = {"name": AB.name_of(ab_key), "desc": AB.desc_of(ab_key) + ("" if AB.is_active(ab_key) else AB.NO_EFFECT_NOTE), "slot": AB.SLOT_NAMES[clampi(player_ability_slot, 0, 2)]}
    var stages := [0, player_atk_stage, player_def_stage, player_spatk_stage, player_spdef_stage, player_spd_stage]
    return {
        "name": (SpecialForms.display_name(_fused_name(), player_special_form) if not player_special_form.is_empty() else _fused_name()), "level": level, "types": _player_types(),
        "fusion": ("%s + %s" % [_species_name(player_species_id), _species_name(player_fusion_id)]) if player_fusion_id > 0 else "",
        "portrait": _detail_portrait(), "hp": player_hp, "hp_max": stats.value("hp_max") if stats != null else 0,
        "stats": player_stats.duplicate(), "stages": stages, "base_stats": player_base_stats.duplicate(),
        "nature": PokemonGrowth.nature_label(player_nature_id),
        "ability": ability, "status": _player_status_label(), "moves": moves,
    }


# 起始页换特性栏位：写进存档，回显“特性名：说明”。
# 生蛋（game/pokemon_eggs.gd）：选宠页选了两只亲代 → 扣一块蛋糕、生一颗蛋（孵出来的样子此刻定好）。
func _on_breed(a: int, b: int) -> void:
    if points_wallet == null:
        _points_begin_run()
    var Eggs := preload("res://game/pokemon_eggs.gd")
    var shiny := [-1, -1]
    var ivs := [[], []]
    var nats := [0, 0]
    for i in 2:
        var p := a if i == 0 else b
        var tiers: Array = points_wallet.shiny_tiers_for(p)
        shiny[i] = int(tiers.max()) if not tiers.is_empty() else -1
        ivs[i] = points_wallet.ivs_for(AB.root_of(p))
        nats[i] = points_wallet.nature_pick_for(AB.root_of(p))
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var egg: Dictionary = Eggs.make_egg(a, b, shiny, ivs, nats, rng)
    var ok: bool = points_wallet.lay_egg(egg, Eggs.MAX_EGGS)
    _refresh_town_page()
    if town_page != null and town_page.has_method("show_message"):
        town_page.show_message(("生了一颗「%s」的蛋！打死 %d 只怪就孵出来（剩 %d 块蛋糕）" % [_species_name(int(egg["species"])), int(egg["need"]), points_wallet.cakes]) if ok else "没生成：蛋糕不够，或者已经有 %d 颗蛋了" % Eggs.MAX_EGGS)


func _on_ability_slot(root_id: int, slot: int) -> void:
    if points_wallet == null:
        return
    points_wallet.set_ability_slot(root_id, slot)
    if town_page != null and town_page.has_method("show_message"):
        var key := AB.slot_ability(root_id, slot)
        town_page.show_message("%s（%s）" % [AB.summary(key), AB.SLOT_NAMES[slot]])


# 选宠页被动那一行：花物种糖果解锁（原版），解锁后点一下开 / 关。
func _on_passive_request(root_id: int, action: String) -> void:
    if points_wallet == null:
        return
    var nm := AB.name_of(AB.passive_of(root_id))
    var msg := ""
    if action == "unlock":
        var cost := SpeciesCandy.passive_cost(root_id)
        var r: Dictionary = points_wallet.unlock_passive(root_id, cost)
        match str(r.get("reason", "")):
            "":
                msg = "解锁了被动「%s」：%s" % [nm, AB.desc_of(AB.passive_of(root_id))]
            "not_enough":
                msg = "糖果不够：解锁要 %d 颗，现在 %d 颗（抓到同一系的宝可梦、带它打满好感都给糖果）" % [cost, points_wallet.species_candy_for(root_id)]
            "already":
                msg = "已经解锁过了"
            _:
                msg = "存档写不进去，没解锁"
    else:
        var on := not points_wallet.is_passive_on(root_id)
        points_wallet.set_passive_enabled(root_id, on)
        msg = "被动「%s」%s" % [nm, "打开了" if on else "关掉了（这只出发时不带被动）"]
    _refresh_town_page()
    if town_page != null and town_page.has_method("show_message"):
        town_page.show_message(msg)


func _back_to_title() -> void:
    if shop_page != null:
        shop_page.close()
    town_page.close()
    town_page.set_points(_points_total())
    town_page.set_collection(_collection_snapshot())
    title_page.open()


# 城镇「商店」：局外分「全体加成 / 单只培养」，显示持久点数。商店盖在城镇上时先收城镇，
# 关闭后再按原页签打开城镇，出发 / 图鉴 / 地图 / 左 ABC 的位置都不动。
var _town_tab_before_shop := "pokedex"

func _on_town_shop() -> void:
    if town_page == null or not town_page.is_open():
        return
    _town_tab_before_shop = town_page.current_tab()
    town_page.close()
    if shop_page != null:
        shop_page.open_town(_points_total(), _shop_owned())
        _refresh_shop_candy()


func _on_town_shop_closed() -> void:
    if shop_page != null:
        shop_page.close()
    if town_page != null and not started:
        town_page.set_points(_points_total())
        if points_wallet != null:
            town_page.set_tm_equipped(points_wallet.tm_equipped)
        town_page.set_collection(_collection_snapshot())
        town_page.open(_town_tab_before_shop)

# 捕获第 2 段：战斗 HUD 点球 -> 进入地面选圈（入口自己再做地点 / 库存校验）。
func _on_capture_ball_pressed(ball_type: int) -> void:
    if _begin_ball_aim(ball_type):
        return
    if hud != null and _ball_count(ball_type) <= 0:
        hud.show_banner("这种球已经用完了")


# 捕获第 2 段：地面圈确认 -> 同一条真实提交入口；把结果翻成玩家可读的一句话。
func _on_capture_throw_requested(world_pos: Vector3) -> void:
    if ball_aim_type == TELEPORT_AIM:
        _teleport_to(world_pos)
        return
    if capture_presenting and _queue_throw(world_pos):
        if capture_pause_mode:
            _resume()   # 预约好了就回到游戏，等这只的动画播完自动扔
        return
    var result := _throw_ball_at(world_pos)
    _capture_feedback(result)
    # 暂停抓宠物：球真的投出去了（耗球）就恢复游戏；空圈 / 被挡等没耗球的保持暂停，可以重新放圈。
    if capture_pause_mode and bool(result.get("consumed", false)):
        _resume()


func _capture_feedback(result: Dictionary) -> void:
    if hud == null:
        return
    var reason := str(result.get("reason", ""))
    if reason == "no_targets":
        _show_capture_banner("圈里没有可以投出的目标")
        return
    if reason == "empty":
        _show_capture_banner("这种球已经用完了")
        return
    if reason in ["bad_position", "not_aiming", "not_allowed", "bad_ball"]:
        return
    var captured := int(result.get("captured", 0))
    var broke := int(result.get("broke_free", 0))
    var failed := int(result.get("persist_failed", 0))
    var blocked := int(result.get("blocked", 0))
    var parts: Array = []
    if captured > 0:
        parts.append("已捕获 %d 只" % captured)
    if broke > 0:
        parts.append("挣脱了 %d 只" % broke)
    if failed > 0:
        parts.append("%d 只的图鉴没能保存" % failed)
    if blocked > 0:
        parts.append("头目还有护体，先继续削弱或换大师球")  # 保留兜底；头目的分段捕捉保护已去掉，正常不会再出现
    if parts.is_empty():
        parts.append("这次没能捕获")
    _show_capture_banner("，".join(parts))


# 结果横幅：有演出者（命中且可演）延后到整批演出结束后再报；空圈 / 全被挡 / 保存失败等
# 没有演出者的即时结果立刻报，不让玩家以为没反应。
func _show_capture_banner(text: String) -> void:
    if hud == null:
        return
    if capture_presenting:
        _capture_pending_banner = text
    else:
        hud.show_banner(text)


# 城镇出发接线：把 D 图鉴选中的准确 ID + 地图一起交给 start_run（后端再独立校验最新档）。
# 键盘 Enter / 鼠标按钮都经 depart_pressed 到这里，和直接调用 start_run 走同一条后端校验。
func _on_town_depart() -> void:
    if town_page == null:
        return
    # 这个存档第一次出发：先问要不要玩 2 分钟教学关（用户 2026-10-24）。自动检查（无界面）不问。
    if _tutorial_wanted() and DisplayServer.get_name() != "headless":
        if _tut_asking:
            return
        var pick := await _ask_tutorial()
        if pick < 0:
            return   # 关掉询问框：留在选宠页，下次出发再问
        _mark_tutorial_done()
        if pick == 0:
            start_tutorial()
            if started:
                return
    start_shiny_variant = int(town_page.call("selected_shiny_variant")) if town_page.has_method("selected_shiny_variant") else -1
    start_shiny_borrowed = bool(town_page.call("selected_shiny_from_fusion")) if town_page.has_method("selected_shiny_from_fusion") else false
    start_shiny_parts = town_page.call("selected_shiny_parts") if town_page.has_method("selected_shiny_parts") else [-1, -1]
    start_run(town_page.selected_map_id(), town_page.selected_pokemon_id(), town_page.selected_ditto_target(), town_page.selected_entry_level())
    if not started and town_page.is_open():
        # 拒绝：面板不关闭、地图 / 主角 / 招式都不动；start_run 已按最新落盘档刷新解锁标识。
        if hud != null:
            var why := PokemonStarters.not_ready_reason(int(town_page.selected_pokemon_id()))
            hud.show_banner(why if why != "" else "这只宝可梦暂时不能上场，请先捕获或选择已准备好的宝可梦")

var _tut_asking := false


# 出发前的询问框：0 = 玩教学关，1 = 跳过直接出发，-1 = 关掉（不出发）。
func _ask_tutorial() -> int:
    _tut_asking = true
    var page: Node = _choice_page()
    var result := {"value": -2}
    var on_pick := func(i: int): result["value"] = i
    var on_cancel := func(): result["value"] = -1
    page.connect("picked", on_pick, CONNECT_ONE_SHOT)
    page.connect("cancelled", on_cancel, CONNECT_ONE_SHOT)
    page.call("open_choice", "第一次出发", "要不要先玩 2 分钟教学关？会用超极巨化的巴大蝶（绿毛虫进化到底的样子）把走位、技能开关、抓宠、商店、撤离都走一遍；抓到的宝可梦会留下。这个存档只问这一次。",
        ["玩教学关（2 分钟）", "跳过，直接出发"], "先不出发", [], "")
    while int(result["value"]) == -2 and is_inside_tree():
        await get_tree().process_frame
    page.call("close")
    if page.is_connected("picked", on_pick):
        page.disconnect("picked", on_pick)
    if page.is_connected("cancelled", on_cancel):
        page.disconnect("cancelled", on_cancel)
    _tut_asking = false
    return int(result["value"])


# 血量框上方：现在的能力变化（用户 2026-10-24：“被降速没问题，但是要有个让我知道被降速了的东西”）。
# 例：“速度 -4（12 秒） 攻击 +2”；被降的带剩余秒数（到时恢复），被动强化的常驻不写秒数。
func _stage_text() -> String:
    var parts: Array = []
    for row in [["atk", "攻击", player_atk_stage], ["def", "防御", player_def_stage], ["spatk", "特攻", player_spatk_stage],
            ["spdef", "特防", player_spdef_stage], ["spd", "速度", player_spd_stage], ["acc", "命中", player_acc_stage], ["eva", "闪避", player_eva_stage]]:
        var v := int(row[2])
        if v == 0:
            continue
        var t := "%s %s%d" % [row[1], "+" if v > 0 else "", v]
        if player_stage_until.has(row[0]):
            t += "（%d 秒）" % int(ceilf(maxf(0.0, float(player_stage_until[row[0]]) - run_clock)))
        parts.append(t)
    return "  ".join(parts)


# 同上，给 HUD 画图标用：[{key, name, v, secs(-1 = 一直有效)}]。
func _stage_rows() -> Array:
    var out: Array = []
    for row in [["atk", "攻击", player_atk_stage], ["def", "防御", player_def_stage], ["spatk", "特攻", player_spatk_stage],
            ["spdef", "特防", player_spdef_stage], ["spd", "速度", player_spd_stage], ["acc", "命中", player_acc_stage], ["eva", "闪避", player_eva_stage]]:
        var v := int(row[2])
        if v == 0:
            continue
        var secs := -1
        if player_stage_until.has(row[0]):
            secs = int(ceilf(maxf(0.0, float(player_stage_until[row[0]]) - run_clock)))
        out.append({"key": row[0], "name": row[1], "v": v, "secs": secs})
    return out


# 血量旁边的“最近 5 秒持续掉血”（用户 2026-10-24：中后期主要死于中毒 / 反伤，却看不出来）：中毒 -18 反伤 -6。
func _recent_dot_text() -> String:
    if battle_report == null:
        return ""
    var sums := {}
    var evs: Array = battle_report.events
    for i in range(evs.size() - 1, -1, -1):
        var ev: Dictionary = evs[i]
        if float(ev["t"]) < time - 5.0:
            break
        if str(ev["kind"]) != "dot":
            continue
        var src := str(ev["source"])
        var key := "反伤" if src.begins_with("反伤") else src
        sums[key] = float(sums.get(key, 0.0)) + float(ev["amount"])
    var parts: Array = []
    for k in sums:
        parts.append("%s -%d" % [k, int(round(float(sums[k])))])
    return "  ".join(parts)


func _evac_hint() -> String:
    if tutorial_mode or BiomeLinks.LINKS.get(map_id, []).is_empty():
        return ""
    if not evac_ready:
        var left := maxf(0.0, EVAC_SECONDS - (time - map_time_start))
        return " · 撤离 %d:%02d" % [int(left) / 60, int(left) % 60]
    return " · 头目在场，打倒或等它走" if _boss_alive() else " · 可以撤离（X）"


# 教学关：超极巨化巴大蝶 30 级、平原、2 分钟。不用解锁巴大蝶（只在教学里借用）。
func start_tutorial() -> void:
    if started:
        return
    tutorial_mode = true
    _tut_shown = {}
    _tut_rare = null
    _tut_finishing = false
    _tut_caught = []
    start_run("plains", TUTORIAL_SPECIES)
    if not started:
        tutorial_mode = false
        return
    level = TUTORIAL_LEVEL
    candy_levels = TUTORIAL_LEVEL - 1   # 借来的等级不抬敌人等级（敌人还是平原开局的强度）
    var form: Dictionary = SpecialForms.form_of(TUTORIAL_SPECIES, "gigantamax")
    if not form.is_empty():
        _apply_special_form(form)
    else:
        _recalculate_player_stats()
    player_hp = stats.value("hp_max")
    _hud_stats()


# 出发前独立校验：准确 ID 必须在现 84 原表内、初始招全部有真实释放且至少一招能伤害；
# 非默认物种还必须已经持久解锁。只信重新从盘上读出的 collection，不信 UI disabled / 缓存 caught。
func _starter_departure_valid(species_id: int) -> bool:
    if tutorial_mode and species_id == TUTORIAL_SPECIES:
        return true   # 教学关借用巴大蝶，不要求解锁
    if not PokemonStarters.is_ready(species_id):
        return false
    if species_id == PokemonStarters.DEFAULT_SPECIES_ID:
        return true
    var w = Points.new(points_path)
    w.reload()
    if w.is_corrupt():
        return false
    return w.is_species_unlocked(species_id)

# 本页 D / 出发要显示的钱包 [collection] 深副本（点存档不在这里，只读当前的）。
func _collection_snapshot() -> Array:
    if points_wallet == null:
        return []
    return points_wallet.caught.duplicate()

# 把最新已捕获集合交给城镇。fresh=true 时重新从盘上读（拒绝出发 / 撤销解锁后刷新标识）。
func _refresh_town_collection(fresh := false) -> void:
    if town_page == null or not town_page.has_method("set_collection"):
        return
    if points_wallet != null and town_page.has_method("set_tm_equipped"):
        town_page.set_tm_equipped(points_wallet.tm_equipped)
    if fresh:
        var w = Points.new(points_path)
        w.reload()
        town_page.set_collection(w.caught.duplicate())
    else:
        town_page.set_collection(_collection_snapshot())

# 按准确物种 ID 设置开局真实初始招（最多 4）；只放已有真实释放实现的招。
# bench_sid > 0：按这只的“留在家里”名单跳过开局招（给技能机器腾槽）；百变怪不用（传 0）。
func _set_player_starter_moves(species_id: int, bench_sid := 0) -> void:
    active_moves.clear()
    run_forgotten.clear()    # 每局开始：没有被换掉过的招
    buff_done.clear()        # 强化招这局还没放过
    buff_base.clear()
    _evo_declined.clear()
    _queued_throw = {}
    _tips_shown = {}
    disabled_moves.clear()   # 每局开局技能全开
    var benched: Array = []
    if bench_sid > 0 and points_wallet != null:
        benched = points_wallet.tm_bench_for(bench_sid)
    for move_id in PokemonStarters.initial_moves(species_id):
        if MOVES.is_implemented(str(move_id)) and not benched.has(str(move_id)):
            active_moves.append(str(move_id))

# map_id_arg：城镇出发传 selected_map_id()；自动模式、截图和旧的无参调用不传，默认回退平原。
# starter_id：城镇 D 图鉴选中的准确 source_species_id；旧单参调用保持 #0010 绿毛虫。
# ditto_as：选百变怪（132）开局时它变成谁（平原已准备好的物种，见 PokemonStarters.ditto_targets）；其它物种忽略。
func start_run(map_id_arg := "", starter_id := 10, ditto_as := 0, entry_level := 0) -> void:
    if started:
        return
    var sid := int(starter_id)
    run_starter_id = sid
    player_special_form = {}   # 超级 / 超极巨形态只在当局（开局先清，后面换外形 / 算六维都按普通形态）
    # 后端先独立验证：无效就直接返回，不关面板、不动 started / 主角 / 招式 / 地图。
    if not _starter_departure_valid(sid):
        _refresh_town_collection(true)
        return
    var is_ditto := sid == PokemonStarters.DITTO_ID
    if is_ditto and not PokemonStarters.is_ditto_target(int(ditto_as)):
        return   # 百变怪必须先选变成谁（城镇里有选择框；直接调用传错也不出发）
    # 出发前收掉商店面板并恢复真实时间，重开 / 出发不残留暂停。
    if shop_page != null:
        shop_page.close()
    Engine.time_scale = 1.0
    _clear_bolts()
    rare_announced = {}
    map_id = Biomes.resolve(str(map_id_arg))
    map_time_start = 0.0
    evac_ready = false
    if hud != null and hud.has_method("set_evac_ready"):
        hud.set_evac_ready(false)
    if scenery != null:
        scenery.set_biome(map_id)   # 换地区的地面贴图和地面上的物件
    if town_page != null:
        town_page.close()
    if title_page != null:
        title_page.close()
    stats = Roster.unit_stats(UNITS.PLAYER)
    # 主角真从 D 选中的物种开 1 级（本作既有开局等级，不擅自换原 Rogue 5 级）：
    # 物种 ID / 原六维输入 / types 都按准确资料；世界移速 6 / 攻速 1 / 磁吸仍走旧实时适配。
    # 闪光个体开局（选宠页开了才有）：真闪光配色 + 最大血量小幅加成（金 +10% / 蓝 +15% / 红 +20%）。
    player_shiny_variant = start_shiny_variant if (start_shiny_variant >= 0 and not is_ditto) else -1
    player_shiny_borrowed = start_shiny_borrowed and player_shiny_variant >= 0
    # 融合了两半都有闪光加级：相加（蓝 + 蓝 = +4、金 + 红 = +4）；只有一半或没融合就按原来的一档算
    player_shiny_bonus = -1
    if player_shiny_variant >= 0 and int(start_shiny_parts[1]) >= 0 and points_wallet != null and points_wallet.fusion_for(sid) > 0:
        player_shiny_bonus = PokemonLens.shiny_bonus(int(start_shiny_parts[0])) + PokemonLens.shiny_bonus(int(start_shiny_parts[1]))
    start_shiny_parts = [-1, -1]
    start_shiny_variant = -1
    start_shiny_borrowed = false
    player_is_ditto = is_ditto
    player_species_id = int(ditto_as) if is_ditto else sid
    _set_player_starter_moves(player_species_id, 0 if is_ditto else sid)
    _refresh_player_species_visual()
    if player_shiny_variant >= 0:
        stats.add("hp_max", "shiny_start", 0.0, [0.10, 0.15, 0.20][player_shiny_variant])
    # 重置到 1 级 xp0（新实例本就如此，这里显式收口）；计时键 / 计数由 _refresh_moves 重建。
    level = 1
    xp = 0.0
    # 新局重置临时防御等级（变硬）为 0；只重置这条临时状态，不碰基础六维公式。
    player_def_stage = 0
    player_atk_stage = 0
    player_spatk_stage = 0
    player_spdef_stage = 0
    player_spd_stage = 0
    player_acc_stage = 0
    player_crit_boost = false
    run_clock = 0.0
    battle_report.reset()
    player_crit_boost_until = 0.0
    player_stage_until = {}
    player_screen_phys_until = 0.0
    player_screen_spec_until = 0.0
    player_charged_until = 0.0
    player_curled_until = 0.0
    rollout_count = 0
    rollout_last = 0.0
    last_used_move = ""
    hurt_serial = 0
    hurt_at = -1000.0
    hurt_phys_serial = 0
    hurt_phys_at = -1000.0
    hurt_phys_dmg = 0.0
    hurt_phys_src = null
    hurt_used = {}
    player_protect_until = 0.0
    early_sash_used = false
    _cancel_charges()
    _ab_reset_run()
    player_lock_on = false
    rest_until = 0.0
    regen_until = 0.0
    float_until = 0.0
    hurt_spec_serial = 0
    hurt_spec_at = -1000.0
    map_weather = ""
    map_weather_wave = -1
    _set_weather("")
    _set_terrain("")
    _set_shield("")
    shield_ready_at = 0.0
    consec_id = ""
    consec_count = 0
    _cast_power_mult = 1.0
    _item_evolution_to = 0
    friendship_wave = 1
    # 新局清掉异常状态 / 实时状态钟（旧局的秒钟与阻断缓存不带进新局）。
    _reset_status_state()
    # 击杀点数：每次开新局都重新读同一个持久余额文件，本局获得计数归零（总余额保留）。
    _points_begin_run()
    # 捕获第 2 段：每次开新局取 max(原 new run 5/0/0/0/0, 钱包里存下的球)，清掉旧局瞄准圈。
    _reset_ball_run()
    # 神奇糖果（局外买的，原 RARE_CANDY +1 级 / 颗）：这只宝可梦开局时就多这些等级；移招 / 进化事件在下面一起结算。
    player_train_key = sid   # 营养饮料努力值按开局选的那只存取
    if points_wallet != null and points_wallet.nickname_for(sid) != "" and hud != null:
        hud.set_portrait(_portrait_for(player_species_id), points_wallet.nickname_for(sid))   # 起的名字（上面刷外观时还不知道开局那只）
    run_held = points_wallet.held_all(sid) if points_wallet != null else {}   # 携带道具（按进化系）
    leftovers_clock = 0.0
    leftovers_bank = 0.0
    safeguard_until = 0.0
    _held_sec_clock = 0.0
    player_semi_kind = ""
    _slowmo_on_resume = false
    amulet_active = -1
    player_semi_until = 0.0
    player_ivs = points_wallet.ivs_for(AB.root_of(sid)) if points_wallet != null else PokemonGrowth.DEFAULT_IVS.duplicate()   # 个体值：这一系抓到过的每项最高值
    player_fusion_id = points_wallet.fusion_for(sid) if points_wallet != null and not player_is_ditto else 0   # 融合（选宠页选的）
    learn_plan = points_wallet.learn_plan_for(sid) if points_wallet != null and points_wallet.has_method("learn_plan_for") else []   # 学招计划
    learn_plan_on = true
    player_nature_id = points_wallet.nature_pick_for(AB.root_of(sid)) if points_wallet != null else PokemonGrowth.DEFAULT_NATURE_ID   # 选宠页选的性格（抓到过才有）
    player_friendship = preload("res://data/pokemon_friendship.gd").base(sid)   # 迁怒 / 报恩：从物种基础亲密度起步
    if not player_is_ditto:
        _equip_tm_moves(sid)     # 开局招（融合了两只的都算）+ 带着的机器，最多 4 个，机器优先
    _ensure_damage_move(sid)
    # candy_levels 记“糖果真正加的等级”（颗数 × (1 + 糖果罐层数)）：敌人等级下限按去掉它算，
    # 原来记的是颗数，糖果罐多加的那几级被算回敌人等级（2026-10-22 审查发现）
    candy_levels = (points_wallet.candy_for(sid) if points_wallet != null else 0) * (1 + _global_charm("CANDY_JAR"))
    level = 1 + candy_levels   # 糖果罐：每颗神奇糖果多升 1 级 / 层
    entry_wave = Biomes.entry_wave(map_id, mini(int(entry_level), Biomes.entry_cap(level)))   # 入场等级（不超过开局等级的 1.5 倍）-> 入场波次；0 = 地区带起点
    _recalculate_player_stats()
    if hud != null and hud.has_method("set_fusion_mark"):
        hud.set_fusion_mark(player_fusion_id > 0)
    if player_fusion_id > 0 and hud != null:
        if points_wallet == null or points_wallet.nickname_for(sid) == "":
            hud.set_portrait(_portrait_for(player_species_id), _fused_name())
        hud.show_banner("融合：%s + %s" % [_species_name(player_species_id), _species_name(player_fusion_id)])
    if player_ability != "" and hud != null:
        hud.show_banner("特性：%s —— %s" % [AB.name_of(player_ability), AB.desc_of(player_ability)])
    player_hp = stats.value("hp_max")
    waves = Waves.new()
    waves.density = enemy_density
    waves.max_alive = MAX_ENEMIES
    waves.setup(UNITS.enemy_ids())
    # 平原真实野生抽样：每局一颗 RNG + 一次原 cycleOffset = Ze(8)*5（0,5,...,35）。
    wild = WildEncounters.new()
    var biome_pool: Dictionary = preload("res://data/pokemon_biome_pools.gd").pool(map_id)
    if not biome_pool.is_empty():
        wild.pool_data = biome_pool   # 本局地区的野生物种池（平原仍是 data/pokemon_plains.gd 那份）
    wild.roll_cycle_offset()
    time = start_time
    waves.skip_to(time)
    # time= 跳时间只用于调试 / 回归：按每 20 秒补等级，走统一升级函数（静默重算 + 原表学习 + 进化事件）。
    _apply_debug_start_time()
    if level > 1 and start_time <= 0.0:
        _after_level_up(1)   # 神奇糖果带来的开局等级：补学原表里 2..level 级的招、检查进化（同调试跳时间那条路径）
    _refresh_moves()   # 按 active_moves 同步 arts 计时键和 HUD 技能栏
    hud.visible = true
    started = true
    # 手动在“管理招式”里选过开局招的，尊重那份选择，不再拿计划里的 1 级招去顶（2026-10-24）
    var manual_loadout: bool = points_wallet != null and not (points_wallet.loadout_for(sid) as Array).is_empty()
    if learn_plan_on and not learn_plan.is_empty() and not manual_loadout:
        for pm in learn_plan:
            var mid := str(pm)
            if active_moves.has(mid):
                continue
            var reachable: bool = MOVES.learnable_between(player_species_id, 1, level, false).has(mid)                 or (player_fusion_id > 0 and MOVES.learnable_between(player_fusion_id, 1, level, false).has(mid))
            if reachable:
                request_learn_move(mid)
    if hud.has_method("set_effects"):
        hud.set_effects(_run_effects())   # 左上角：这局的闪光加成 / 镜片 / 被动
    _hud_stats()
    for item in spawn_at_start:
        var id := item.get_slice(":", 0)
        if id == UNITS.PLAYER or not UNITS.UNITS.has(id):
            continue
        var count := clampi(int(item.get_slice(":", 1)), 1, MAX_ENEMIES)
        for i in mini(count, MAX_ENEMIES - enemies.size()):
            var angle := TAU * i / count
            _spawn(_unit(id, 1), player.position + Vector3(cos(angle), 0, sin(angle)) * 5.0)
    for i in stress:
        if enemies.size() >= MAX_ENEMIES:
            break
        var a := randf() * TAU
        _spawn(_unit("caterpie", 1), player.position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 16.0))

# time= 调试 / 回归跨级入口：每 20 秒补 1 级，走统一 _after_level_up 并给出正确的“升级前等级”，
# 因此原表按 [升级前等级+1, 当前等级] 整段查招，不会绕过学习表、也不会一次把全部低等级招补上。
func _apply_debug_start_time() -> void:
    if start_time <= 0.0:
        return
    var gained := int(start_time / 20.0)
    if gained <= 0:
        return
    var level_before := level
    level = mini(PokemonGrowth.MAX_LEVEL, level + gained)
    _after_level_up(level_before)

func _build_world() -> void:
    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color(0.2, 0.24, 0.18)
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color.WHITE
    env.environment.ambient_light_energy = 0.7
    add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, 30, 0)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 60.0
    add_child(sun)

    cam = Camera3D.new()
    cam.fov = 45.0
    add_child(cam)
    cam.current = true

    gem_mesh = SphereMesh.new()
    gem_mesh.radius = 0.18
    gem_mesh.height = 0.36
    gem_mesh.radial_segments = 8
    gem_mesh.rings = 4
    gem_mat = StandardMaterial3D.new()
    gem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    gem_mat.albedo_color = Color(0.3, 0.9, 1.0)



func _build_player() -> void:
    player = Node3D.new()
    add_child(player)
    var model: Node3D = load(player_unit["scene"]).instantiate()
    player.add_child(model)
    player_ap = model.find_child("AnimationPlayer", true, false)
    player_ap.play(player_unit["anims"]["idle"])


func _build_hud() -> void:
    hud = Hud.new()
    add_child(hud)
    var visual := player.get_child(0)
    if visual.has_method("portrait_texture"):
        player_portrait = visual.portrait_texture()
        hud.set_portrait(player_portrait, player_unit["name"])
    hud.card_picked.connect(_pick)   # 点卡片和按 1 / 2 / 3 都由界面自己接
    hud.reroll_pressed.connect(_reroll)   # 重抽按钮和 R 键
    hud.move_toggled.connect(_on_move_toggled)
    hud.effect_clicked.connect(func(act: String, step: int):
        if act == "amulet":
            _cycle_amulet(step))   # 暂停抓宠界面里点左下角技能开关



# 设置里“显示攻击范围”开着时：主角脚下青圈 = 招式最远射程，附近敌人红圈 = 贴身挥击、橙圈 = 远程招射程。
const RangeRings := preload("res://fx/range_rings.gd")
var range_rings: Node3D = null


func _update_range_rings() -> void:
    if range_rings == null:
        if not show_ranges:
            return
        range_rings = RangeRings.new()
        add_child(range_rings)
    if not show_ranges or not started or dead or player == null:
        range_rings.call("draw", [])
        return
    var rings: Array = [{"pos": player.position, "r": MAX_ATTACK_RANGE * attack_range_scale, "color": Color(0.3, 0.95, 0.9, 0.85)}]
    var shown := 0
    for e in enemies:
        if e.dying >= 0.0 or e.node == null or not is_instance_valid(e.node):
            continue
        var off: Vector3 = e.node.position - player.position
        if off.x * off.x + off.z * off.z > 196.0:
            continue
        rings.append({"pos": e.node.position, "r": float(e.t["radius"]) + 0.55 * enemy_range_scale, "color": Color(1.0, 0.3, 0.25, 0.7)})
        if e.ranged_moves.size() > 0:
            rings.append({"pos": e.node.position, "r": ENEMY_SHOOT_RANGE * enemy_range_scale, "color": Color(1.0, 0.65, 0.2, 0.4)})
        shown += 1
        if shown >= 40:
            break
    range_rings.call("draw", rings)


func _hud_stats() -> void:
    _update_range_rings()
    hud.set_berries(berries)
    hud.set_stats({"time": time, "map_time": time - map_time_start, "level": level, "xp": int(xp), "xp_need": _xp_need(),
        "hp": player_hp, "max_hp": stats.value("hp_max"), "dot_text": _recent_dot_text(), "stage_text": _stage_text(), "stage_rows": _stage_rows(), "phase": "%s · %s%s" % [Biomes.name_of(map_id), waves.phase_name(time), _evac_hint()],
        "kills": kills, "enemies": enemies.size(), "fps": int(Engine.get_frames_per_second()),
        "points_total": _points_total(), "points_run": _points_run(), "types": _player_types()})
    var bosses: Array = []
    for e in enemies:
        if e.t["boss"] and e.dying < 0.0:
            bosses.append({"name": e.t["name"], "hp": e.hp, "max": e.t["hp"],
                "segments": e.segments, "index": e.segment_index})
    hud.set_bosses(bosses)

func _aim_camera() -> void:
    cam.position = player.position + Vector3(0, 12, 8) * cam_zoom
    cam.look_at(player.position + Vector3(0, 1, 0))

# 屏幕外的闪光 / 神兽：在屏幕边缘画箭头指过去（用户 2026-10-24：闪光和神兽才是大头，别错过）。
func _special_edge_arrows() -> Array:
    var out: Array = []
    var cam := get_viewport().get_camera_3d()
    if cam == null:
        return out
    var rect := get_viewport().get_visible_rect()
    var margin := 36.0
    var center := rect.size * 0.5
    for e in enemies:
        if e.dying >= 0.0 or e.node == null or not is_instance_valid(e.node) or not (bool(e.shiny) or bool(e.legendary)):
            continue
        var wp: Vector3 = e.node.position + Vector3(0, 0.6, 0)
        var behind := cam.is_position_behind(wp)
        var sp := cam.unproject_position(wp)
        if not behind and rect.grow(-margin).has_point(sp):
            continue   # 在屏幕里，看得见就不画
        var dir := (sp - center) * (-1.0 if behind else 1.0)
        if dir.length() < 1.0:
            continue
        var half := center - Vector2(margin, margin)
        var k := minf(half.x / maxf(0.001, absf(dir.x)), half.y / maxf(0.001, absf(dir.y)))
        var col: Color = SHINY_TIER_COLOR[clampi(int(e.shiny_variant), 0, 2)] if bool(e.shiny) else MARKER_LEGEND_COLOR
        out.append({"pos": center + dir * k, "angle": dir.angle(), "color": col})
    return out


func _process(delta: float) -> void:
    _ball_slowmo_tick()
    _ball_highlight_tick()
    # 捕获演出批次：冻结战斗逻辑（时间 / 刷怪 / 双方移动攻击 / 异常钟 / 拾取），
    # 原 FX 自己的 _process 用真实 delta 继续播；这里只跑生产检查（完成 / 恢复失败目标 / 发延后奖励）。
    # 不用 Engine.time_scale=0：只像 evolving 一样做主循环门槛；Esc 商店的 paused 时也照样跑检查。
    if capture_presenting:
        _capture_presentation_tick()
        return
    # evolving 期间主循环推进和伤害全停，但不动 Engine.time_scale，进化演出自己的动画才能跑。
    if started and hud != null and hud.has_method("set_edge_arrows"):
        hud.set_edge_arrows(_special_edge_arrows())
    _tips_tick()
    if not started or choosing or paused or evolving or finishing_capture:
        return
    if dead:
        _auto_modes(delta)
        if Input.is_physical_key_pressed(KEY_R):
            skip_title = true
            get_tree().reload_current_scene()
        return
    delta *= game_speed   # 游戏速度系数：整个战斗世界的时间流速（FX 动画仍按真实时间播）
    time += delta
    _move_player(delta)
    # 异常状态：每个有效战斗秒推进一次 before_action + end_turn（玩家、敌人各走各的钟）。
    # 放在出招之前：当秒的阻断缓存当帧生效（附加睡眠 / 冰冻 / 麻痹当秒就不能出招），
    # DoT 或混乱自伤致死也当场停手；敌人那一段在 _update_enemies 里各自推。
    _status_tick(delta)
    if stress == 0:
        _spawn_tick(delta)
        if player_hp > 0.0:
            _attack_tick(delta)
    _drain_spawns()
    if player_hp > 0.0:
        _update_enemies(delta)
        _update_bolts(delta)
    _update_gems(delta)
    _notables_tick(delta)
    _aim_camera()
    _berry_tick(delta)
    _hud_stats()
    _graduation_tick()
    if player_hp <= 0.0:
        _settle("dead")
        sfx.player_death()
    _auto_modes(delta)


func _move_player(delta: float) -> void:
    var dir := Vector3.ZERO
    if capture or stress > 0:
        if not still:
            dir = Vector3(cos(time * 0.5), 0, sin(time * 0.5))
            var nearest := _nearest(12.0)
            if capture and nearest != null:
                var off := nearest.node.position - player.position
                if off.length() > _range("tackle") * 0.9:
                    dir = (dir * 0.25 + off.normalized() * 0.75).normalized()
    else:
        if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
        if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
        if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.z -= 1
        if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.z += 1
    moving = dir.length_squared() > 0.001
    # 睡眠 / 冰冻停止主动移动：状态在附加当帧就起效；麻痹只按原 SPD 比值缩放（不额外禁止走路）。
    if _status_stops_move(null):
        moving = false
    if moving:
        facing = dir.normalized()
        # 麻痹：用「原 SPD（含能力等级）有 / 无麻痹的比值」缩放已有米/秒，不对米/秒做 bitshift。
        var raw_spd := float(player_stats[5]) if player_stats.size() > 5 else 0.0
        var move_speed := _paralyzed_move_speed(float(stats.value("move_speed")) * _player_speed_factor(), player_status, raw_spd, player_spd_stage)
        player.position = scenery.push_out(_body_block(player.position + facing * move_speed * delta), 0.35)
    player.get_child(0).set_world_facing(facing, cam)
    var want := "move" if moving else "idle"
    if player_ap.current_animation != want:
        player_ap.play(want, 0.0, 1.3 if moving else 1.0)
    was_moving = moving

func _body_block(pos: Vector3) -> Vector3:
    for e in enemies:
        if e.dying >= 0.0:
            continue
        var off := pos - e.node.position
        off.y = 0
        var minimum := float(player_unit["body_radius"]) + float(e.t["radius"]) * 0.5
        var dist := off.length()
        if dist < minimum:
            pos += (off / dist if dist > 0.0001 else -facing) * (minimum - dist)
    return pos

func _auto_modes(delta: float) -> void:
    if capture and snap_prefix != "" and DisplayServer.get_name() != "headless":
        snap_timer -= delta
        if snap_timer <= 0.0:
            snap_timer = 0.5
            snap_n += 1
            await _shot("res://outputs/%s_%02d.png" % [snap_prefix, snap_n])
    # 死亡后游戏时间不再增加，自动模式仍须按墙钟退出。
    if dead and capture:
        capture_secs = 0.0
    if (capture and time >= start_time + capture_secs) or (stress > 0 and time >= 8.0):
        finishing_capture = true
        _result_line()
        await _shot("res://outputs/play_capture.png")
        get_tree().quit()
