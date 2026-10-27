extends "res://main/enemies.gd"
# 升级三选一（旧技能 / 属性卡）本轮停用：升级改走 _gain_xp → _recalculate_player_stats
# 按原作公式自动重算六项。旧选卡函数保留为未来口子；CARDS_ENABLED=false 时全部不可操作，
# 也不会弹卡、不会设 choosing、不会动 Engine.time_scale。
const CARDS_ENABLED := false
var offered: Array[Dictionary] = []
var rerolls_left := REROLLS
var force_offer: PackedStringArray = []

func _card_ok(c: Dictionary) -> bool:
    if not CARDS_ENABLED:
        return false
    return int(card_lv.get(c["id"], 0)) < int(c["max"])

func _card_pool() -> Array[Dictionary]:
    var pool: Array[Dictionary] = []
    for c in CARDS.LIST:
        if _card_ok(c):
            pool.append(c)
    return pool

func _roll_three() -> Array:
    return Offer.choose(_card_pool(), {}, 3, [])

func _card_effect(c: Dictionary) -> String:
    var id: String = c["id"]
    if c.has("move"):
        if id == "string_shot":
            var lv := int(move_lv[id])
            return "减速 %d%% → %d%%；持续 %.1f → %.1f 秒" % [45 + 5 * (lv - 1), 45 + 5 * lv, 3.0 + 0.4 * (lv - 1), 3.0 + 0.4 * lv]
        return "伤害 %.1f → %.1f；范围 +0.12 米" % [_dmg(id), stats.value("attack." + id) * (1.0 + 0.2 * int(move_lv[id]))]
    return str(c.get("desc", ""))

# 旧三选一入口（未来口子）。停用时直接返回，不设 choosing、不动 Engine.time_scale，
# 避免暂停主循环和进化演出互相打架。
func _offer() -> void:
    if not CARDS_ENABLED:
        return
    offered.assign(_roll_three())
    if not force_offer.is_empty():
        offered.clear()
        for id in force_offer:
            if offered.size() < 3 and card_defs.has(id) and _card_ok(card_defs[id]):
                offered.append(card_defs[id])
        force_offer = []
        if offered.is_empty():
            offered.assign(_roll_three())
    if offered.is_empty():
        return
    var options: Array = []
    for c in offered:
        var current := int(move_lv[c["id"]]) if c.has("move") else int(card_lv[c["id"]])
        options.append({"id": c["id"], "name": c["name"], "category": c["cat"],
            "from_lv": current, "to_lv": current + 1, "effect": _card_effect(c)})
    hud.show_cards(options)
    hud.set_rerolls(rerolls_left)
    choosing = true

# 旧升级卡效果（未来口子）。本轮 CARDS_ENABLED=false，不会执行；move_lv 因此保持固定 1。
func _take_card(c: Dictionary) -> void:
    if not CARDS_ENABLED or not _card_ok(c):
        return
    var id: String = c["id"]
    card_lv[id] = int(card_lv[id]) + 1
    if c.has("move"):
        move_lv[c["move"]] += 1
    if c.has("stat"):
        stats.add(str(c["stat"]), "card:" + id, float(c.get("flat", 0.0)) * card_lv[id], float(c.get("pct", 0.0)) * card_lv[id])
    if c.has("heal"):
        heal(float(c["heal"]))
    _show_moves()

# HUD 技能栏只列当前实际掌握的招式名，不写等级，避免暗示还能练到 Lv5。
func _show_moves() -> void:
    var shown: Array = []
    for id: String in active_moves:
        if not MOVES.is_implemented(id):
            continue
        var shown_name := str(MOVES.MOVES[id]["name"]) + (" [T]" if id == "teleport" else "")   # 瞬间移动是主动技能，按 T 用
        shown.append({"id": id, "name": shown_name, "category": "技能", "on": not disabled_moves.has(id)})
    shown.append({"id": SPARE_TOGGLE_ID, "name": "手下留情", "category": "开关", "on": spare_special})
    if not learn_plan.is_empty():
        shown.append({"id": PLAN_TOGGLE_ID, "name": "学招计划", "category": "开关", "on": learn_plan_on})   # 关掉 = 照旧每次问   # 开着：闪光 / 神兽打不死
    hud.set_loadout(shown)

func _reroll() -> void:
    if not CARDS_ENABLED or not choosing or rerolls_left <= 0 or dead:
        return
    rerolls_left -= 1
    _offer()

func _pick(i: int) -> void:
    if not CARDS_ENABLED or not choosing or i < 0 or i >= offered.size():
        return
    _take_card(offered[i])
    choosing = false
    hud.hide_cards()
