extends RefCounted
# 本作升级池（2026-10-15 属性升级轮起停用）。
#
# 用户决定：升级不再三选一，改按 Rogue 公式自动提升六项属性；技能升级本轮先不做。
# 因此 LIST 置空（ENABLED=false），旧的技能 / 属性升级卡整体停用，只作未来口子保留在
# LEGACY_LIST 里，不参与运行。升级接线见 main/combat.gd 的 _gain_xp / _recalculate_player_stats，
# 公式见 game/pokemon_growth.gd。
const ENABLED := false
const LIST: Array[Dictionary] = []
const LEGACY_LIST: Array[Dictionary] = [
    {"id": "tackle", "name": "撞击", "cat": "一般 · 物理", "move": "tackle", "max": 4},
    {"id": "string_shot", "name": "吐丝", "cat": "虫 · 变化", "move": "string_shot", "max": 4},
    {"id": "bug_bite", "name": "虫咬", "cat": "虫 · 物理", "move": "bug_bite", "max": 4},
    {"id": "hp", "name": "生命强化", "cat": "属性", "max": 5, "stat": "hp_max", "flat": 15.0, "heal": 15.0, "desc": "生命上限 +15，并回复 15 点生命。"},
    {"id": "attack", "name": "攻击强化", "cat": "属性", "max": 5, "stat": "attack", "pct": 0.12, "desc": "撞击和虫咬伤害 +12%。吐丝不造成伤害。"},
    {"id": "quick", "name": "招式加速", "cat": "属性", "max": 5, "stat": "aspd", "pct": 0.10, "desc": "三招释放速度 +10%。"},
    {"id": "move", "name": "移动强化", "cat": "属性", "max": 5, "stat": "move_speed", "pct": 0.06, "desc": "移动速度 +6%。"},
    {"id": "magnet", "name": "经验吸附", "cat": "属性", "max": 5, "stat": "magnet", "flat": 0.6, "desc": "吸取经验的范围 +0.6 米。"},
    {"id": "heal", "name": "回复生命", "cat": "回复", "max": 2147483647, "heal": 25.0, "desc": "立即回复 25 点生命。"},
]
static func by_id() -> Dictionary:
    var out := {}
    for c in LIST:
        out[c["id"]] = c
    return out
