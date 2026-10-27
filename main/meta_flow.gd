extends "res://main/cards.gd"
# 本轮取消功法存档、品质、研习和秘籍奖励；原 save.json 保留，不读取也不覆盖。

func _exit_tree() -> void:
    _cancel_events()
    preload("res://game/i18n.gd").uninstall()   # 退出前摘掉翻译表，防关闭时崩；重开场景时 apply_saved 会再挂上
    if DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(null)

# Esc / Q / E 都是同一个键位：战斗中打开抓宠界面，抓宠界面里再按继续游戏（用户 2026-10-17：“q、e 键进入捕捉界面”）。
const PAUSE_KEYS := [KEY_ESCAPE, KEY_Q, KEY_E]


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_X and evac_ready and not paused:
        get_viewport().set_input_as_handled()
        _evacuate()
        return
    if not (event is InputEventKey) or not event.pressed or event.echo or not PAUSE_KEYS.has(event.physical_keycode):
        return
    # 暂停抓宠界面：Esc 先取消瞄准，没在瞄准就继续游戏。
    if capture_pause_mode:
        get_viewport().set_input_as_handled()
        if ball_aiming:
            _cancel_ball_aim()
        else:
            _resume()
        return
    # 捕获第 2 段：正在瞄准地面圈时，Esc 只取消瞄准，不打开商店（同一次按键不两用）。
    if ball_aiming:
        get_viewport().set_input_as_handled()
        _cancel_ball_aim()
        return
    # 商店 / 设置自己处理 Esc（商店返回抓宠界面、设置返回），这里不再处理，避免一个 Esc 开两次 / 两层弹窗。
    if shop_page != null and shop_page.is_open():
        return
    if pause_page.is_open():
        return
    if _open_pause_screen():
        get_viewport().set_input_as_handled()


# 战斗 Esc：暂停并进入抓宠界面（球面板 + 右上角商店按钮；商店里才有继续 / 设置 / 放弃之外的买卖）。
# 条件不满足返回 false，什么都不做。
func _open_pause_screen() -> bool:
    # 捕获演出期间（capture_presenting）照样能开店：此时 _event_pending 可能被推迟，
    # 不能用它误挡；没有演出时仍保持原门槛（有 pending 的进化 / 换招不在这时开店）。
    var event_ready := capture_presenting or (not _event_pending and not _event_pump_running)
    if not (started and not dead and not choosing and not evolving and not paused and not settled
            and event_ready):
        return false
    paused = true
    Engine.time_scale = 0.0
    _cancel_ball_aim()
    # 捕获 FX 时间和自有音频一起冻结（Engine.time_scale=0 已停推进；音频要显式 paused）。
    _set_capture_fx_paused(true)
    _enter_capture_pause()
    return true


func _resume() -> void:
    capture_pause_mode = false
    _refresh_special_marks()   # 回到实时：去掉「未捕获」标记
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("set_pause_mode"):
        capture_page.call("set_pause_mode", false)
    if shop_page != null:
        shop_page.close()
    pause_page.close()
    paused = false
    Engine.time_scale = 1.0
    if _slowmo_on_resume:
        _slowmo_on_resume = false
        if not dead:
            _start_ball_slowmo(CAPTURE_AFTER_SLOWMO_SECS, CAPTURE_AFTER_SLOWMO_SCALE)   # 暂停抓宠页里抓到的：回到游戏先慢 1 秒
    # 与 Esc 开店时的 set_paused(true) 配对：从同一点接着播，不重播开场音 / 不漏 cue。
    _set_capture_fx_paused(false)
    # 暂停期间被推迟的进化 / 换招事件在这里继续（捕获演出结束后也会自己重新排）。
    if _event_pending or not _pending_learns.is_empty():
        _start_event_pump()


# 局内商店 → 设置：先收商店再开设置，返回时回商店，不并排留两个弹窗。
func _on_shop_settings() -> void:
    if shop_page != null:
        shop_page.close()
    pause_page.open_settings(false, true)


# 左下角技能开关：只在暂停抓宠界面里能点；关掉的招不自动放（用户 2026-10-18：“只能在暂停界面点，不放，方便抓宠物”）。
func _on_move_toggled(id: String) -> void:
    if not (capture_pause_mode and started and not dead and not settled):
        return
    if id == SPARE_TOGGLE_ID:
        spare_special = not spare_special
        _show_moves()
        return
    if id == PLAN_TOGGLE_ID:
        learn_plan_on = not learn_plan_on
        _show_moves()
        return
    if disabled_moves.has(id):
        disabled_moves.erase(id)
    else:
        disabled_moves[id] = true
    _show_moves()


# 暂停抓宠界面右上角横条的“设置”：打开设置页，返回时回到暂停抓宠界面（不进商店）。
func _on_capture_settings_pressed() -> void:
    if not (capture_pause_mode and started and not dead and not settled):
        return
    _settings_from_capture = true
    pause_page.open_settings(false, true)


func _on_shop_settings_return() -> void:
    if _settings_from_capture:
        _settings_from_capture = false
        return
    if started and not dead and not settled:
        _push_evolution_items()
        _push_shop_extras()
        shop_page.open_run(_points_total(), _points_run(), _shop_owned(), _shop_ball_counts())


# 放弃这一局，回标题页。先取消事件 / 关面板，重开不残留 choosing / evolving。
func _abandon() -> void:
    if started and not settled:
        _persist_balls()
    if started and not settled and not battle_report.events.is_empty():
        _write_battle_report("abandon")
    if shop_page != null:
        shop_page.close()
    pause_page.close()
    paused = false
    Engine.time_scale = 1.0
    _cancel_events()
    get_tree().reload_current_scene()


# 鼠标用系统默认（用户 2026-10-26）。想换回汉 B 毛笔箭头把 USE_HANB_CURSOR 打开。
const USE_HANB_CURSOR := false
func _set_cursor() -> void:
    if not USE_HANB_CURSOR or DisplayServer.get_name() == "headless" or not ResourceLoader.exists("res://ui/hanb/cursor_arrow.png"):
        return
    var img: Image = (load("res://ui/hanb/cursor_arrow.png") as Texture2D).get_image()
    img.resize(36, int(36.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
    Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), Input.CURSOR_ARROW, Vector2(4, 2))



func _boss_reward(final: bool, boss_name := "") -> void:
    if dead or settled:
        return
    if final:
        _settle("won")
    else:
        # 本轮移除旧头目强化卡来源；其他头目只报一次真实物种名，不弹强化卡 / 新选项。
        # 头目本身仍掉药水（见 combat._kill）。
        var label := "击败头目！"
        if boss_name != "":
            label = "击败头目 %s！" % boss_name
        hud.show_banner(label)

# 毕业：每帧由 main._process 调；到点只触发一次（教学关不算）。
func _graduation_tick() -> void:
    if graduated or graduate_seconds <= 0.0 or time < graduate_seconds or dead or settled or tutorial_mode:
        return
    graduated = true
    if points_wallet != null and player_train_key > 0:
        points_wallet.add_win(player_train_key)   # 毕业就记通关，选继续也算
    _graduation_prompt()


func _graduation_prompt() -> void:
    var token := event_token
    var mins := int(graduate_seconds / 60.0)
    var idx := await _ask_choice("毕业", "撑过 %d 分钟，毕业了！（已记一次通关）\n可以现在结算这一局，也可以继续打无限模式：怪越来越多，倒下时再结算。" % mins,
        ["毕业，结算这一局"], "继续：无限模式", token)
    if not _event_valid(token):
        return
    if idx == 0:
        _settle("won")
    else:
        hud.show_banner("无限模式：撑到倒下为止")


func _settle(kind: String) -> void:
    if settled:
        return
    settled = true
    won = kind == "won"
    if won and not graduated and points_wallet != null and player_train_key > 0:
        points_wallet.add_win(player_train_key)   # 通关记录：图鉴格子上的徽章（毕业时已经记过的不重复记）
    dead = true
    Engine.time_scale = 1.0
    # 死亡 / 结算不残留商店面板或暂停。
    if shop_page != null:
        shop_page.close()
    if pause_page != null:
        pause_page.close()
    paused = false
    _cancel_events()   # 失效事件 token / 关面板；死亡后不再切种族或恢复战斗
    player_ap.play("death" if kind == "dead" else "idle")
    var learned: Array = []
    for id: String in active_moves:
        learned.append(str(MOVES.MOVES[id]["name"]))
    var lines: Array = ["本局招式：" + "、".join(learned)]
    if graduated and kind == "dead":
        lines.insert(0, "已毕业（%d 分钟），无限模式撑到 %d:%02d" % [int(graduate_seconds / 60.0), int(time) / 60, int(time) % 60])
    # 死亡 / 胜利结算：加一行本局获得 + 当前持久余额（同一份计数与余额，不另算）。
    lines.append("本局点数：%d · 点数余额：%d" % [_points_run(), _points_total()])
    lines.append_array(battle_report.summary_lines())
    _persist_balls()
    _write_battle_report(kind)
    if kind == "dead":
        hud.show_death(lines)
    else:
        hud.show_victory(lines)
    _result_line()

# 战斗报告落盘（非正式版之前每局都留一份 txt，跑完就能看“怎么回事”）：
#   kind = "dead" 倒下 / "won" 通关 / "abandon" 中途放弃（回标题）/ "quit" 中途关窗口。
#   从项目直接运行时找起来最方便；打包后写不进就静默跳过）。每处都有按时间命名的 report_*.txt / .json，
#   再加一份每次覆盖的 latest.txt；各保留最近 30 份。写不了就静默跳过，不影响结算。
func _write_battle_report(kind: String) -> void:
    var outcome := {"dead": "倒下", "won": "通关", "abandon": "中途放弃", "quit": "中途关闭游戏"}.get(kind, kind) as String
    var text := battle_report.full_text(time, level, kills, outcome, ["本局招式：" + "、".join(_move_names())])
    var json := JSON.stringify(battle_report.to_dict(time, level, kills, outcome))
    var dt := Time.get_datetime_dict_from_system()
    var stamp := "%04d%02d%02d_%02d%02d%02d_%03d_%s" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"], Time.get_ticks_msec() % 1000, kind]
    var first_path := ""
    for dir in ["user://battle_reports", "res://outputs/battle_reports"]:
        # 验收检查用的隔离用户目录（路径含 test_appdata）不往项目 outputs 里写，免得跑测试弄脏项目文件夹。
        if dir.begins_with("res://") and OS.get_user_data_dir().contains("test_appdata"):
            continue
        var made := DirAccess.make_dir_recursive_absolute(dir)
        if made != OK and not DirAccess.dir_exists_absolute(dir):
            continue
        var path := "%s/report_%s.txt" % [dir, stamp]
        if not _store_text(path, text):
            continue
        _store_text("%s/report_%s.json" % [dir, stamp], json)
        _store_text("%s/latest.txt" % dir, text)
        if first_path == "":
            first_path = path
        _trim_reports(dir)
        print("BATTLE_REPORT ", ProjectSettings.globalize_path(path))
    last_report_path = first_path


func _store_text(path: String, text: String) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(text)
    f.close()
    return true


func _trim_reports(dir: String) -> void:
    var reports: Array = []
    for n in DirAccess.get_files_at(dir):
        if n.begins_with("report_") and n.ends_with(".txt"):
            reports.append(n)
    reports.sort()
    while reports.size() > 30:
        var old: String = reports.pop_front()
        DirAccess.remove_absolute("%s/%s" % [dir, old])
        DirAccess.remove_absolute("%s/%s.json" % [dir, old.trim_suffix(".txt")])


# 中途关窗口也留一份报告（本局已开始、还没结算）。
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and started and not settled:
        _persist_balls()
        if not battle_report.events.is_empty():
            _write_battle_report("quit")


func _move_names() -> Array:
    var out: Array = []
    for id: String in active_moves:
        out.append(str(MOVES.MOVES[id]["name"]))
    return out


func _result_line() -> void:
    if result_done:
        return
    result_done = true
    print("RESULT time=%.1f level=%d kills=%d hp=%.1f won=%s moves=%s move_lv=%s casts=%s points_total=%d points_run=%d" % [time, level, kills, player_hp, won, active_moves, move_lv, move_casts, _points_total(), _points_run()])


# ================= 撤离去下一个地区（用户 2026-10-20：5 分钟后可以撤离；按原版地区连线走、走到就解锁） =================
const BiomeLinks := preload("res://data/biome_links.gd")
const MapData := preload("res://data/biomes.gd")   # main.gd 里也有一个叫 Biomes 的，子类不能重名，这里换个名字
var evac_roll := Callable()   # 测试注入原版 1/n 掷骰；默认随机


# 每帧（_spawn_tick 开头）：在这个地区待满 5 分钟就亮出“撤离”按钮。
func _evac_tick() -> void:
    _boss_leave_tick()
    if evac_ready or time - map_time_start < EVAC_SECONDS or BiomeLinks.LINKS.get(map_id, []).is_empty():
        return
    evac_ready = true
    if hud != null and hud.has_method("set_evac_ready"):
        if hud.has_signal("evac_pressed") and not hud.evac_pressed.is_connected(_evacuate):
            hud.evac_pressed.connect(_evacuate)
        hud.set_evac_ready(true)
        hud.show_banner("可以撤离了：按 X 或点上面的「撤离」，去下一个地区")
    _tip("evac", "可以撤离了：按 X（或点上面的「撤离」）选下一个地区。等级、宠物、道具都带走；新地区的怪更强，刚进去的 1 分钟会弱一点。", "maps")


# 选下一个地区（原版连线，带 1/n 的掷一次）；选了就在同一局里换过去，取消就继续待着。
const BOSS_STAY_SECS := 60.0   # 头目出来 60 秒没打倒就自己离开（离开前不能撤离，用户 2026-10-22）


# 场上还在的头目（没在死、没被抓）。
func _boss_alive() -> bool:
    for e in enemies:
        if e.dying < 0.0 and bool(e.t.get("boss", false)):
            return true
    return false


# 每帧：头目待满 60 秒就走掉（不给奖励）。
func _boss_leave_tick() -> void:
    for e in enemies.duplicate():
        if e.dying < 0.0 and bool(e.t.get("boss", false)) and run_clock - e.born_at >= BOSS_STAY_SECS:
            _capture_remove_target(e)
            if hud != null:
                hud.show_banner("%s 离开了" % str(e.t.get("name", "头目")))


func _evacuate() -> void:
    if not evac_ready or dead or settled or choosing or evolving or paused:
        return
    if _boss_alive():
        if hud != null:
            hud.show_banner("头目还在！打倒它，或者等它离开，才能撤离")
        return
    var options: Array[String] = BiomeLinks.roll_options(map_id, evac_roll)
    if _global_charm("MAP") > 0:   # 地图：能去的地区全部列出来
        options = BiomeLinks.all_options(map_id)
    # 补给站里直接选地图（用户 2026-10-25：“补给站应该是能选择地图的，之前那个选择地图的界面就不需要了”）
    if supply_on and not tutorial_mode and points_wallet != null:
        _open_supply(options)
        return
    var names: Array = []
    for id in options:
        names.append("%s%s" % [MapData.name_of(id), "" if points_wallet == null or points_wallet.is_map_unlocked(id) else "（新）"])
    var token := event_token
    var idx: int = await _ask_choice("撤离", "离开「%s」，去哪里？（场上的怪留在这里；等级、宠物、道具都带走）" % MapData.name_of(map_id), names, "再待会儿", token)
    if idx < 0 or idx >= options.size():
        return
    _enter_map(options[idx])


# 同一局换地区：清掉场上的怪、换地面和野生宝可梦池；敌人强度从现在的进度接着走（不回到新地区的起点）。
func _enter_map(id: String) -> void:
    # 新地区的敌人等级按你现在的等级起步（× 0.85，去掉糖果加的等级），不接着旧地区的进度、也不看新地区的档（用户 2026-10-22）
    var cur_wave: int = MapData.wave_for_level(maxf(1.0, float(level - candy_levels)) * MapData.EVAC_LEVEL_RATIO)
    for e in enemies.duplicate():
        _capture_remove_target(e)
    spawn_queue.clear()
    _clear_bolts()
    map_id = id
    map_time_start = time
    entry_wave = cur_wave
    evac_ready = false
    if hud != null and hud.has_method("set_evac_ready"):
        hud.set_evac_ready(false)
    if scenery != null:
        scenery.set_biome(map_id)
    var pool: Dictionary = preload("res://data/pokemon_biome_pools.gd").pool(map_id)
    if wild != null:
        if not pool.is_empty():
            wild.pool_data = pool
        wild.roll_cycle_offset()
    wild_cache.clear()
    map_weather_wave = -1   # 新地区马上按新地区的天气表掷
    _map_weather_tick(0, entry_wave)
    var fresh := points_wallet != null and points_wallet.unlock_map(map_id)
    if hud != null:
        hud.show_banner("来到了「%s」%s" % [MapData.name_of(map_id), "（新地区，以后可以直接选）" if fresh else ""])


# ================= 补给站（用户 2026-10-25：“换地图中间加个补给时间”）=================
# 撤离选好新地区、换过去之后马上弹出，游戏暂停。卖城镇里给宠物培养的东西（糖果 / 镜片 / 携带道具 / 技能机器），
# 走城镇同一条购买入口（扣点、存档、以后开局也有），买成功了这一局马上生效。按「出发」继续。
const SupplyPage := preload("res://ui/supply_station.gd")
const SUPPLY_WEATHER_ZH := {"rain": "雨", "sun": "晴", "sand": "沙暴", "snow": "雪", "hail": "冰雹", "fog": "雾"}
const SUPPLY_LENS_ICON := {"support": "wide_lens", "attack": "scope_lens", "capture": "catching_charm"}
var supply_page = null


var supply_options: Array[String] = []   # 这次撤离能去的地区（原版连线掷出来的）
var supply_idx := 0                      # 现在选的是第几个


func _open_supply(options: Array[String]) -> void:
    if not supply_on or tutorial_mode or points_wallet == null or dead or settled or not started or options.is_empty():
        return
    if supply_page == null or not is_instance_valid(supply_page):
        supply_page = SupplyPage.new()
        add_child(supply_page)
        supply_page.buy_pressed.connect(_supply_buy)
        supply_page.depart_pressed.connect(_supply_depart)
        supply_page.cancel_pressed.connect(_supply_cancel)
        supply_page.map_step.connect(_supply_step)
    supply_options = options.duplicate()
    supply_idx = 0
    supply_open = true
    paused = true
    Engine.time_scale = 0.0
    _cancel_ball_aim()
    _set_capture_fx_paused(true)
    supply_page.open(_supply_info())


# 现在选中的下一站。
func _supply_map() -> String:
    return supply_options[supply_idx] if not supply_options.is_empty() else map_id


# 换一个要去的地区（◀ ▶ / Q E）。
func _supply_step(step: int) -> void:
    if not supply_open or supply_options.is_empty():
        return
    supply_idx = posmod(supply_idx + step, supply_options.size())
    if supply_page != null and is_instance_valid(supply_page):
        supply_page.refresh(_supply_info())


# AI 接口用：直接选第 i 个。
func _supply_pick(i: int) -> bool:
    if not supply_open or i < 0 or i >= supply_options.size():
        return false
    supply_idx = i
    if supply_page != null and is_instance_valid(supply_page):
        supply_page.refresh(_supply_info())
    return true


# 出发：去选中的地区。
func _supply_depart() -> void:
    if not supply_open:
        return
    var target := _supply_map()
    supply_open = false
    if supply_page != null and is_instance_valid(supply_page):
        supply_page.close()
    if target != map_id:
        _enter_map(target)
    _hud_stats()
    _resume()


# 再待会儿：不换地区，回到这里接着打（买过的东西照样生效）；之后还能再按撤离。
func _supply_cancel() -> void:
    if not supply_open:
        return
    supply_open = false
    if supply_page != null and is_instance_valid(supply_page):
        supply_page.close()
    _hud_stats()
    _resume()


# 新地区刚进去时野怪的大概等级（入场波次和“你的等级 70%”取大的那个，按原版等级公式）。
func _supply_enemy_level() -> int:
    var natural := level - candy_levels
    var w := MapData.wave_for_level(maxf(1.0, float(natural)) * MapData.EVAC_LEVEL_RATIO)   # 和 _enter_map 一样的起点
    if natural > 1:
        w = maxi(w, MapData.wave_for_level(float(natural) * MapData.LEVEL_FLOOR_RATIO))
    return maxi(1, int(1.0 + w / 2.0 + pow(w / 25.0, 2.0)))


# 新地区池里常见（普通 / 不常见档）的宝可梦，最多 10 只。
func _supply_species() -> Array:
    var out: Array = []
    var pool: Dictionary = preload("res://data/pokemon_biome_pools.gd").pool(_supply_map())
    for tier in [0, 1]:
        if not pool.has(tier):
            continue
        for tod in pool[tier]:
            for e in pool[tier][tod]:
                var ids: Array = []
                if e is Dictionary:
                    for th in e:
                        ids.append_array(e[th])
                else:
                    ids.append(e)
                for sid in ids:
                    if not out.has(int(sid)):
                        out.append(int(sid))
                    if out.size() >= 10:
                        return out
    return out


func _supply_info() -> Dictionary:
    var sid := run_starter_id
    var bal := _points_total()
    var weather: Array = []
    var next := _supply_map()
    for w in (BiomeWeather.POOLS.get(next, []) as Array):
        var zh := str(SUPPLY_WEATHER_ZH.get(str(w[0]), ""))
        if zh != "" and not weather.has(zh):
            weather.append(zh)
    # 培养：神奇糖果 + 三种镜片
    var grow: Array = []
    var jar := 1 + _global_charm("CANDY_JAR")
    var candy := points_wallet.candy_for(sid)
    var cprice := PokemonShop.price_at("RARE_CANDY", candy)
    grow.append({"id": "RARE_CANDY", "name": "神奇糖果", "icon": "rare_candy", "price": cprice, "badge": str(candy) if candy > 0 else "",
        "can": candy < PokemonShop.CANDY_CAP and bal >= cprice and level < PokemonGrowth.MAX_LEVEL,
        "state": "已吃 %d 颗" % candy,
        "desc": "马上升 %d 级（糖果罐 %d 层）。以后开局也多这些级。糖果加的等级不会让野怪变强，靠它拉开等级差。" % [jar, jar - 1]})
    for kind: String in PokemonLens.KINDS:
        var lv := points_wallet.lens_for(sid, kind)
        var lp := PokemonLens.next_price(kind, lv)
        var top := lv >= PokemonLens.MAX_LEVEL
        grow.append({"id": PokemonLens.product_id(kind), "name": str(PokemonLens.NAMES[kind]), "icon": str(SUPPLY_LENS_ICON[kind]),
            "price": -1 if top else lp, "badge": str(lv) if lv > 0 else "", "can": not top and bal >= lp,
            "state": "到顶了（%d 级）" % lv if top else "现在 %d 级" % lv, "desc": str(PokemonLens.DESC.get(kind, ""))})
    # 携带道具（和城镇一样的清单）
    var held: Array = []
    var neutral_nature := (PokemonGrowth.nature_multipliers(points_wallet.nature_pick_for(AB.root_of(sid))) as Array).all(func(x): return is_equal_approx(float(x), 1.0))
    for it: String in HeldItems.shop_items(_starter_profile(sid).get("types", []), sid):
        if it == "SOUL_DEW" and neutral_nature:
            continue
        var have := points_wallet.held_for(sid, it)
        var mx := HeldItems.max_stacks(it)
        var hp := HeldItems.price(it)
        held.append({"id": HeldItems.product_id(it), "name": HeldItems.name_of(it), "icon": HeldItems.icon_of(it), "price": hp if have < mx else -1,
            "badge": str(have) if have > 0 else "", "can": have < mx and bal >= hp,
            "state": ("已有 %d/%d" % [have, mx]) if have < mx else "到顶了", "desc": HeldItems.desc_of(it, have)})
    # 技能机器：买过的免费学；正在用的灰掉
    var tms: Array = []
    var owned := _owned_tms(sid)
    for m in TMRules.learnable_fused(sid, _fusion_of(sid)):
        var mid := str(m)
        if not MOVES.is_implemented(mid):
            continue
        var mv: Dictionary = MOVES.MOVES[mid]
        var using := active_moves.has(mid) or _pending_learns.has(mid)
        var has := owned.has(mid)
        var tp := TMRules.price(mid)
        tms.append({"id": TMRules.product_id(mid), "name": "技能机器 " + str(mv.get("name", mid)),
            "icon": "tm_" + str((preload("res://ui/rogue_ui.gd").TYPE_EN as Dictionary).get(str(mv.get("type", "")), "normal")),
            "price": -1 if using else (0 if has else tp), "badge": "✓" if using else ("有" if has else ""),
            "can": not using and (has or bal >= tp),
            "state": "正在用" if using else ("买过了，免费学" if has else ""),
            "desc": _move_info(mid) + "\n买了出发后马上学；招式满了会问你换掉哪一招。"})
    var maps: Array = []
    for id in supply_options:
        maps.append({"id": id, "name": MapData.name_of(id), "new": not points_wallet.is_map_unlocked(id)})
    return {"map_id": next, "map_name": MapData.name_of(next), "maps": maps, "map_index": supply_idx,
        "from_name": MapData.name_of(map_id), "enemy_lv": _supply_enemy_level(), "weather": weather,
        "species": _supply_species(), "points": bal, "tabs": {"grow": grow, "held": held, "tm": tms}}


# 补给站买东西：技能机器自己处理（买过的免费学），其余走城镇购买入口，扣了点数就马上生效。
func _supply_buy(pid: String) -> void:
    if not supply_open:
        return
    var sid := run_starter_id
    var msg := ""
    var before := _points_total()
    if TMRules.is_product(pid):
        var mv := TMRules.move_of(pid)
        var mname := str(MOVES.MOVES.get(mv, {}).get("name", mv))
        if active_moves.has(mv) or _pending_learns.has(mv):
            msg = "已经会「%s」了。" % mname
        else:
            var ok := _owned_tms(sid).has(mv)
            if not ok:
                var r: Dictionary = _shop_buy(pid)
                ok = _points_total() < before
                msg = _shop_message(pid, r)
            if ok:
                request_learn_move(mv)
                msg = "好了：出发后学「%s」（招式满了会问你换掉哪一招）。" % mname
    else:
        var r: Dictionary = _shop_buy(pid)
        msg = _shop_message(pid, r)
        if _points_total() < before:
            _supply_apply(pid)
            if pid == "RARE_CANDY":
                msg = "神奇糖果：升到 Lv%d 了（以后开局也多 1 颗糖的等级）。" % level
    if supply_page != null and is_instance_valid(supply_page):
        supply_page.refresh(_supply_info(), msg)


# 买成功之后，这一局马上生效（开局时读存档的那几样在这里重读一次）。
func _supply_apply(pid: String) -> void:
    var sid := run_starter_id
    if pid == "RARE_CANDY":
        var n := 1 + _global_charm("CANDY_JAR")
        var lv_before := level
        level = mini(PokemonGrowth.MAX_LEVEL, level + n)
        candy_levels += level - lv_before   # 糖果加的等级不抬野怪等级
        if level > lv_before:
            _after_level_up(lv_before)
    elif PokemonLens.is_product(pid):
        lens_support = points_wallet.lens_for(sid, "support")
        lens_attack = points_wallet.lens_for(sid, "attack")
        lens_capture = points_wallet.lens_for(sid, "capture")
    elif HeldItems.is_product(pid):
        run_held = points_wallet.held_all(sid)
        _recalculate_player_stats()
        _refresh_moves()
    if hud != null and hud.has_method("set_effects"):
        hud.set_effects(_run_effects())
    _hud_stats()

