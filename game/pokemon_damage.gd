extends RefCounted
# 原作伤害公式 · 纯计算层（本轮新增；本作 AI 工程实现）。
# 只读来源与逐段核对写在同目录 game/POKEMON_DAMAGE_SOURCE.md；不读节点、不掷骰、不写状态。
#
# 原 Pokemon.apply(t,n) 的 PHYSICAL / SPECIAL 分支（源内约偏移 5441274）：
#   f.value = Math.ceil(
#       ((2*t.level/5 + 2) * L.value * M.value / G.value / 50 + 2)
#       * w.value * d.value * C.value * y.value
#       * ((this.scene.randBattleSeedInt(15)+85)/100) * B.value)
# 本作当前没有天气 / 场地 / 屏障 / 特性 / 道具 / 太晶，C=y=1；调用方传 L=原作 power、
# M/G=物理 ATK/DEF 或特殊 SPATK/SPDEF、w=本系(1.5/1.0)、d=克制乘积、B=会心(1.5/1.0)。
# 整式只在最后 ceil 一次，不做层层 floor。
#
# 原会心：Q = [24,8,2,1][clamp(crit_stage,0,3)]；Q==1 必会心，否则 randBattleSeedInt(Q)==0。
# 原随机：randBattleSeedInt(15) 上界语义是 0..14（源内 Ze(i,t)=integerInRange(t, i-1+t)，
#   且 n<=1 直接返回 t），故 +85 后是整数 85..99。
#
# 能力等级：原 getBattleStat() 会心时忽略攻击方负 ATK/SPATK 等级、忽略防守方正 DEF/SPDEF 等级；
# 等级倍率 max(2,2+s)/max(2,2-s)，乘原能力值后 floor。本作当前实战只有吐丝的速度等级，
# 物理攻防等级默认 0；这里保留少量参数支持并测原会心语义，不搭全局能力等级系统。

# 原 randBattleSeedInt(15) + 85 的边界（含）。
const DAMAGE_ROLL_MIN := 85
const DAMAGE_ROLL_MAX := 99
# 原作会心倍率 B.value：会心 1.5，否则 1。
const CRIT_MULTIPLIER := 1.5
# 原会心分母表 [24,8,2,1]，下标由 crit_stage 钳到 0..3。
const CRIT_DENOMINATORS := [24, 8, 2, 1]


# 会心分母 Q（原 [24,8,2,1][Math.max(0,Math.min(stage,3))]）。
static func crit_denominator(crit_stage: int) -> int:
    return int(CRIT_DENOMINATORS[clampi(crit_stage, 0, 3)])


# 原 getBattleStat() 的等级后数值：base_stat * max(2,2+s)/max(2,2-s)，最后 floor。
# is_attacker=true 用于攻击方 ATK/SPATK，false 用于防守方 DEF/SPDEF。
# 会心时：攻击方把负等级按 0（max(...,0)），防守方把正等级按 0（min(...,0)）；其他等级保留。
static func battle_stat(base_stat: int, stage: int, crit: bool, is_attacker: bool) -> float:
    var s := stage
    if crit:
        s = maxi(s, 0) if is_attacker else mini(s, 0)
    var mult := maxf(2.0, 2.0 + float(s)) / maxf(2.0, 2.0 - float(s))
    return floorf(float(base_stat) * mult)


# 原 randBattleSeedInt(15)+85：传入 randBattleSeedInt(15) 的 0..14 结果，返回 85..99。
static func damage_roll_from(rng_0_14: int) -> int:
    return DAMAGE_ROLL_MIN + rng_0_14


# 公式主体。roll = 原 (randBattleSeedInt(15)+85) 的整数 85..99；type_eff 为已算好的克制乘积。
# 返回整式一次 ceil 后的整数伤害。type_eff < 0（未接入的攻击属性）按 0 处理，不冒充 1 倍。
static func compute(level: int, power: int, attack_stat: int, defence_stat: int,
        stab: float, type_eff: float, roll: int, crit: bool,
        atk_stage: int = 0, def_stage: int = 0) -> int:
    if type_eff < 0.0:
        return 0
    var atk := battle_stat(attack_stat, atk_stage, crit, true)
    var dfn := battle_stat(defence_stat, def_stage, crit, false)
    if dfn <= 0.0:
        # 原式不会除 0（原作能力值最小为 1）；防御为 0 时按 0 伤害，不崩、不臆造。
        return 0
    var base := (2.0 * float(level) / 5.0 + 2.0) * float(power) * atk / dfn / 50.0 + 2.0
    var total := base * stab * type_eff * (float(roll) / 100.0) * (CRIT_MULTIPLIER if crit else 1.0)
    return int(ceil(total))


# 物理分支：M/G = 攻击方 ATK / 防守方 DEF（六项顺序 [HP,ATK,DEF,SPATK,SPDEF,SPD]）。
static func compute_physical(level: int, power: int, attacker_stats: Array, defender_stats: Array,
        stab: float, type_eff: float, roll: int, crit: bool,
        atk_stage: int = 0, def_stage: int = 0) -> int:
    return compute(level, power, int(attacker_stats[1]), int(defender_stats[2]),
        stab, type_eff, roll, crit, atk_stage, def_stage)


# 特殊分支：M/G = 攻击方 SPATK / 防守方 SPDEF。
static func compute_special(level: int, power: int, attacker_stats: Array, defender_stats: Array,
        stab: float, type_eff: float, roll: int, crit: bool,
        atk_stage: int = 0, def_stage: int = 0) -> int:
    return compute(level, power, int(attacker_stats[3]), int(defender_stats[4]),
        stab, type_eff, roll, crit, atk_stage, def_stage)
