extends RefCounted
# 原作六种异常状态 + 混乱 · 纯规则层（本轮新增；本作 AI 工程实现）。
#
# 只读来源、逐块 SHA256、原函数语义与本轮未实现边界见同目录 game/POKEMON_STATUS_SOURCE.md；
# 只读源（静态核对，不执行整包）：
#
# 设计边界（本任务只交规则，不接真实战斗）：
#   - 每个单位一个本实例，字段互不共享；不持有 Node / SceneTree / 真实 HP，不画 UI、不播音、
#     不起计时器。调用者拿返回的 damage / can_act 自己扣 HP、自己决定死亡。
#   - 一个主要异常（中毒 1 / 麻痹 3 / 睡眠 4 / 冰冻 5 / 灼伤 6，互斥）+ 独立混乱计数，可共存。
#   - 计数与随机数分开：主要异常 turnCount 与混乱 turnCount 各管各的；随机只走可覆盖的 _roll()。
#   - 保留明确 before-action / end-turn 两个入口，不把“回合”藏进 delta；下一段实时接线时由
#     调用者按用户回合换秒统一推进。
#
# 原枚举 Re（源偏移 3115906，块 sha256 C77D85BE...）：
#   NONE=0 POISON=1 TOXIC=2 PARALYSIS=3 SLEEP=4 FREEZE=5 BURN=6 FAINT=7。
#   本轮只做 NONE/POISON/PARALYSIS/SLEEP/FREEZE/BURN；TOXIC=2 / FAINT=7 不扩。
#
# 属性数字照本作 data/pokemon_type_chart.gd 的 18 属性顺序（0 一般 … 3 毒 … 8 钢 … 9 火 …
#   12 电 … 14 冰）。免疫只按原 canSetStatus()（源偏移 5449703）：
#   中毒 = 毒 / 钢；麻痹 = 电；冰冻 = 冰；灼伤 = 火；睡眠无普通类型免疫。
#
# 原时间推进（源偏移 5577760 MovePhase / 5593765 PostTurnStatusEffectPhase）：
#   - PostTurn（源 isPostTurn() = effect 1/2/6，本作去 TOXIC）：end-turn 先 turnCount++，
#     再按 maxHP 算持续伤害；中毒 max(maxHP>>3,1)，灼伤 max(maxHP>>4,1)。
#   - 非 PostTurn（PARALYSIS/SLEEP/FREEZE）：before-action 先 turnCount++，再按下述判定。
#   - 主要状态先判；被睡眠/麻痹/冰冻取消行动时源 MovePhase 不执行 lapseTags(MOVE)，
#     所以混乱计数与自伤骰都不推进。醒来/解冻当次可行动，才轮到混乱。
#
# 混乱（源偏移 5254930 ConfusedTag，lapseType = ps.MOVE = 1）：
#   - 初值由 AddBattlerTagAttr 用 randSeedInt(max-min, min) 抽（源偏移 5314758/5317240/5457773）；
#     ConfuseAttr 是 (2,5)，randSeedInt(3,2) => integerInRange(2,4)，实际 2..4，5 不包含。
#   - 每次有效 MOVE lapse：先 --turnCount；==0 直接移除、当次不掷骰、可行动；>0 才 randSeedInt(3)。
#   - `if(...&& t.randSeedInt(3))` 是**非零即自伤**：0..2 里 1/2 自伤（2/3），0 正常行动。
#   - 自伤取消该行动；伤害 = ceil(((2*level/5+2)*40*ATK/DEF/50+2)*(roll/100))，
#     roll = randSeedInt(15,85) = 85..99；ATK/DEF 是已含能力等级的**有效值**，
#     无本系 / 属性克制 / 会心 / 灼伤再减半；不涉及对方，不扣对方 HP。
#
# 与源的两处刻意差异（都只影响 RNG 次数，不影响可观察状态）：
#   1. 源 AddBattlerTagAttr 先算 duration 再调 addTag，addTag 才发现已有混乱而拒绝，因此重复
#      混乱尝试在源里会白抽一次 duration；本模块把 duration 抽签拆成 roll_confusion_duration()，
#      try_confuse() 在已有混乱时直接拒绝、不抽骰。可观察计数一致（重复不刷新）。
#   2. 源自解冻招式 / 天气 / 地形 / 特性 / BYPASS_SLEEP 等本作都没有，不臆造；接口不模拟。

# 原 Re 枚举里本轮支持的六个值（数字照源）。
const NONE := 0
const POISON := 1
const PARALYSIS := 3
const SLEEP := 4
const FREEZE := 5
const BURN := 6

# 本轮允许的主要异常（互斥，不含 TOXIC=2 / FAINT=7）。
const MAJOR_EFFECTS: Array[int] = [POISON, PARALYSIS, SLEEP, FREEZE, BURN]

# 类型数字照 data/pokemon_type_chart.gd::TYPES 顺序。
const TYPE_POISON := 3
const TYPE_STEEL := 8
const TYPE_FIRE := 9
const TYPE_ELECTRIC := 12
const TYPE_ICE := 14

# 持续伤害分母与最低值（源 PostTurnStatusEffectPhase：POISON max(maxHP>>3,1)、BURN max(maxHP>>4,1)）。
const POISON_MAX_HP_DIVISOR := 8
const BURN_MAX_HP_DIVISOR := 16
const DOT_DAMAGE_FLOOR := 1

# 主要状态抽签边界（上界不含，配合 _roll(min, max_exclusive)）。
# 麻痹：源 randSeedInt(4) ∈ 0..3，只有 0 不能行动。
const PARALYSIS_ROLL_MIN := 0
const PARALYSIS_ROLL_MAX_EXCLUSIVE := 4
const PARALYSIS_BLOCK_ROLL := 0
# 冰冻：源 randSeedInt(5) ∈ 0..4，只有 0 解冻。
const FREEZE_ROLL_MIN := 0
const FREEZE_ROLL_MAX_EXCLUSIVE := 5
const FREEZE_THAW_ROLL := 0

# 混乱 / 睡眠抽签边界（上界不含，配合 _roll(min, max_exclusive)）。
# 睡眠首次附加：源 randSeedIntRange(2,4) = randSeedInt(3,2) = integerInRange(2,4) => 2..4。
const SLEEP_CURE_MIN := 2
const SLEEP_CURE_MAX_EXCLUSIVE := 5
# 混乱初值：同样 2..4（源 ConfuseAttr(2,5) 经 randSeedInt 上界不含 5）。
const CONFUSION_DURATION_MIN := 2
const CONFUSION_DURATION_MAX_EXCLUSIVE := 5
# 混乱自伤触发：源 randSeedInt(3) ∈ 0..2，非零（1/2）才自伤，0 正常行动。
const CONFUSION_TRIGGER_ROLL_MIN := 0
const CONFUSION_TRIGGER_ROLL_MAX_EXCLUSIVE := 3
const CONFUSION_ACT_ROLL := 0
# 混乱自伤：源 randSeedInt(15,85) = integerInRange(85,99) => 85..99。
const CONFUSION_SELF_HIT_POWER := 40
const CONFUSION_SELF_HIT_ROLL_MIN := 85
const CONFUSION_SELF_HIT_ROLL_MAX_EXCLUSIVE := 100
# 原 ConfusedTag 的 lapseType 是 ps.MOVE = 1（不是 PRE_MOVE = 2）。
const CONFUSION_TAG_TYPE := 1

# 主要异常：effect + turnCount（+ 睡眠的 cureTurn），对应原 Status(effect, turnCount, cureTurn)。
var major_effect: int = NONE
var major_turn_count: int = 0
# 中毒 / 灼伤 / 剧毒的持续伤害几个“逻辑秒”结算一次（剧毒递增也跟着它走）。纯规则默认 1 = 每回合；
# 游戏里设成 4（用户 2026-10-22 定：原版“每回合”按最大 HP 比例掉血 / 回血的效果，本作每 4 秒结算一次（原来每秒一次，沙暴 19 秒打死人））。
var residual_period: int = 1
var _residual_ticks: int = 0
# 剧毒（原 StatusEffect.TOXIC）作为中毒的变体：major_effect 仍是 POISON，toxic = true 时每回合伤害递增。
var toxic: bool = false
var sleep_cure_turn: int = 0
# 独立混乱 tag 计数（>0 表示有混乱）；与主要异常互不影响。
var confusion_turn_count: int = 0

var _rng := RandomNumberGenerator.new()


func _init() -> void:
    _rng.randomize()


# RNG 唯一入口：返回 [min_inclusive, max_exclusive) 的整数。
# 生产用 Godot 随机；测试子类覆写本方法，按固定队列返回值并记录边界调用。
func _roll(min_inclusive: int, max_exclusive: int) -> int:
    return _rng.randi_range(min_inclusive, max_exclusive - 1)


func has_major() -> bool:
    return major_effect != NONE


func has_confusion() -> bool:
    return confusion_turn_count > 0


# 原 Status.isPostTurn()：effect 1/2/6 才是回合末持续伤害；本作只保留中毒/灼伤。
func is_post_turn() -> bool:
    return major_effect == POISON or major_effect == BURN


# 原 canSetStatus() 的类型免疫：双属性任一免疫即拒绝。
# 睡眠没有普通类型免疫；草/地面/幽灵的粉末 / 麻痹类免疫不属于这里。
static func is_immune(effect: int, types: Array) -> bool:
    for entry in types:
        var type_id := int(entry)
        match effect:
            POISON:
                if type_id == TYPE_POISON or type_id == TYPE_STEEL:
                    return true
            PARALYSIS:
                if type_id == TYPE_ELECTRIC:
                    return true
            FREEZE:
                if type_id == TYPE_ICE:
                    return true
            BURN:
                if type_id == TYPE_FIRE:
                    return true
    return false


# 附加主要异常。成功返回 true；否则完全无副作用。
# 拒绝路径：NONE / 不在本轮枚举 / 已有主要异常（不刷新计数）/ 类型免疫 —— 都不消耗随机数。
# 成功且是睡眠时消耗一次随机数抽 cureTurn（源在 trySetStatus 里 randSeedIntRange(2,4)）。
func try_set_major(effect: int, types: Array = [], is_toxic: bool = false) -> bool:
    if effect == NONE or not MAJOR_EFFECTS.has(effect):
        return false
    if major_effect != NONE:
        return false
    if is_immune(effect, types):
        return false
    if effect == SLEEP:
        sleep_cure_turn = _roll(SLEEP_CURE_MIN, SLEEP_CURE_MAX_EXCLUSIVE)
    major_effect = effect
    major_turn_count = 0
    _residual_ticks = 0
    toxic = is_toxic and effect == POISON
    return true


# 只清主要异常，保留混乱。
func reset_major() -> void:
    major_effect = NONE
    major_turn_count = 0
    _residual_ticks = 0
    toxic = false
    sleep_cure_turn = 0


# 只清混乱，保留主要异常。
func reset_confusion() -> void:
    confusion_turn_count = 0


# 全清（留给未来死亡 / 新局）。
func reset_all() -> void:
    reset_major()
    reset_confusion()


# 回合末持续伤害。只有 PostTurn 主要异常（中毒 / 灼伤）会动：
#   turnCount 先 +1；中毒 max(maxHP>>3,1)，灼伤 max(maxHP>>4,1)。不掷骰。
# 无 PostTurn 状态时返回 damage=0 且不改任何计数。
# 返回 { "effect": int, "damage": int }。
func end_turn(max_hp: int) -> Dictionary:
    var result := {"effect": NONE, "damage": 0}
    if residual_period > 1 and (major_effect == POISON or major_effect == BURN):
        _residual_ticks += 1
        if _residual_ticks % residual_period != 0:
            return result   # 这一秒不结算
    match major_effect:
        POISON:
            major_turn_count += 1
            result["effect"] = POISON
            if toxic:
                # 原 PostTurnStatusEffectPhase：max(floor(maxHP / 16 × turnCount), 1)，turnCount 先 +1（1/16、2/16、3/16…）。
                result["damage"] = maxi(int(floorf(float(max_hp) / 16.0 * float(major_turn_count))), DOT_DAMAGE_FLOOR)
            else:
                result["damage"] = maxi(max_hp / POISON_MAX_HP_DIVISOR, DOT_DAMAGE_FLOOR)
        BURN:
            major_turn_count += 1
            result["effect"] = BURN
            result["damage"] = maxi(max_hp / BURN_MAX_HP_DIVISOR, DOT_DAMAGE_FLOOR)
    return result


# 行动前判定。顺序照源 MovePhase：先非 PostTurn 主要异常（先 turnCount++），
# 被取消则混乱完全不动（不 --、不抽骰）；可行动时才处理一次 MOVE 混乱 lapse。
# level / effective_atk / effective_def 只在真的发生混乱自伤时才用（已是含能力等级的有效值）。
# 返回 {
#   "can_act": bool,            # 本回合是否允许执行该行动
#   "blocked_by": int,          # 因哪个主要异常被取消（NONE 表示没有）
#   "cured": int,               # 当次治愈的主要异常（睡眠 / 冰冻；NONE 表示没有）
#   "self_hit": bool,           # 混乱自伤（行动被取消）
#   "self_hit_damage": int,     # 原始规则伤害，调用者自己扣 HP
#   "confusion_cleared": bool,  # 混乱计数当次减到 0 并被移除
# }
func before_action(level: int = 1, effective_atk: float = 1.0, effective_def: float = 1.0) -> Dictionary:
    var result := {
        "can_act": true,
        "blocked_by": NONE,
        "cured": NONE,
        "self_hit": false,
        "self_hit_damage": 0,
        "confusion_cleared": false,
    }
    if major_effect != NONE and not is_post_turn():
        major_turn_count += 1
        match major_effect:
            PARALYSIS:
                # 源：randSeedInt(4) 为 0 才不能行动（0..3，1/4）；其余可行动且不自行痊愈。
                if _roll(PARALYSIS_ROLL_MIN, PARALYSIS_ROLL_MAX_EXCLUSIVE) == PARALYSIS_BLOCK_ROLL:
                    result["can_act"] = false
                    result["blocked_by"] = PARALYSIS
            SLEEP:
                # 源：turnCount === cureTurn 当次治愈并可行动；之前阻止。拒绝重复时不会改 cureTurn。
                if major_turn_count == sleep_cure_turn:
                    result["cured"] = SLEEP
                    reset_major()
                else:
                    result["can_act"] = false
                    result["blocked_by"] = SLEEP
            FREEZE:
                # 源：randSeedInt(5) 为 0 当次解冻并可行动（0..4，1/5）；其余阻止。
                # 本作没有自解冻招式 / 天气 / 地形 / 特性，不参与判定。
                if _roll(FREEZE_ROLL_MIN, FREEZE_ROLL_MAX_EXCLUSIVE) == FREEZE_THAW_ROLL:
                    result["cured"] = FREEZE
                    reset_major()
                else:
                    result["can_act"] = false
                    result["blocked_by"] = FREEZE
    if result["can_act"] and confusion_turn_count > 0:
        # 源 ConfusedTag.lapse（lapseType = MOVE）：先 --turnCount。
        confusion_turn_count -= 1
        if confusion_turn_count > 0:
            # 源 `if(r && ... && t.randSeedInt(3))`：非零即自伤（2/3 概率），0 正常行动。
            if _roll(CONFUSION_TRIGGER_ROLL_MIN, CONFUSION_TRIGGER_ROLL_MAX_EXCLUSIVE) != CONFUSION_ACT_ROLL:
                result["self_hit"] = true
                var roll := _roll(CONFUSION_SELF_HIT_ROLL_MIN, CONFUSION_SELF_HIT_ROLL_MAX_EXCLUSIVE)
                result["self_hit_damage"] = confusion_self_hit_damage(
                    level, effective_atk, effective_def, roll)
                result["can_act"] = false
        else:
            # 减到 0：移除 tag，当次不需要骰，可以行动。
            result["confusion_cleared"] = true
    return result


# 源 duration 抽签入口：一次 _roll(2,5)，返回 2..4（5 不包含）。只抽骰，不附加。
func roll_confusion_duration() -> int:
    return _roll(CONFUSION_DURATION_MIN, CONFUSION_DURATION_MAX_EXCLUSIVE)


# 用已抽好的初值附加混乱：无混乱且 turn_count > 0 才成功；已有混乱直接拒绝、不刷新、不抽骰。
func try_confuse(turn_count: int) -> bool:
    if turn_count <= 0:
        return false
    if confusion_turn_count > 0:
        return false
    confusion_turn_count = turn_count
    return true


# 便捷入口：先按源边界抽 duration 再附加；已有混乱时不抽骰直接拒绝。
func try_confuse_from_source() -> bool:
    if confusion_turn_count > 0:
        return false
    confusion_turn_count = roll_confusion_duration()
    return true


# 原 getBattleStat() SPD 段：基础×能力等级后 `s >>= 1`，最后 floor。
# 传入的 effective_speed 是已经算完能力倍率的有效速度；本函数只做整数半，
# 不写基础六维，也不决定米/秒 / 冷却。参数按源 bitshift 语义先截断再半（正常非负范围）。
# 11 -> 5，1 -> 0。
static func paralysis_speed(effective_speed: float) -> int:
    return int(effective_speed) >> 1


# 便捷包装：本单位麻痹时对已算完等级的有效速度施加整数半，否则按源最后一步 floor。
func battle_speed(effective_speed: float) -> int:
    if major_effect == PARALYSIS:
        return paralysis_speed(effective_speed)
    return int(floor(effective_speed))


# 灼伤物理末端 modifier：源在**完整伤害 ceil 之后**再 floor(damage/2)。
# 只用于普通物理招；特殊招保持原值，不提前砍 ATK、不加第二次 ceil / min1。
# 混乱自伤不走这里（源自伤公式里没有灼伤减半）。0 -> 0，1 -> 0，3 -> 1。
static func burn_physical_damage(final_damage: int) -> int:
    return final_damage >> 1


# 混乱自伤原始伤害（源 ConfusedTag.lapse 内公式，power 固定 40，roll 85..99）：
#   ceil(((2*level/5+2)*40*ATK/DEF/50+2)*(roll/100))
# ATK / DEF 是已含能力等级的有效值；无本系 / 克制 / 会心 / 灼伤修正，也没有对方。
static func confusion_self_hit_damage(level: int, effective_atk: float,
        effective_def: float, roll: int) -> int:
    if effective_def <= 0.0:
        return 0
    var base := (2.0 * float(level) / 5.0 + 2.0) * float(CONFUSION_SELF_HIT_POWER) \
        * float(effective_atk) / float(effective_def) / 50.0 + 2.0
    return int(ceil(base * float(roll) / 100.0))


# 游戏里用的实例：持续伤害每 4 秒结算一次（纯规则检查直接 new()，仍是每回合）。
static func for_game():
    var s = load("res://game/pokemon_status.gd").new()
    s.residual_period = 4
    return s
