extends RefCounted
# 速度的三个用处 · 纯计算层（用户 2026-10-16 定：“速度不用太削弱”，移动 / 吸经验球距离 / 命中闪避都挂速度）。
#
# 1. 速度系数（移动快慢、吸经验球距离共用）：
#      factor = clamp( sqrt(有效速度 ÷ 参考速度), 0.7, 2.0 )
#    有效速度 = 玩家六维里的速度 × 速度能力等级倍率（高速移动 / 龙之舞这类招直接提升它）；
#    参考速度 = 种族值 45（绿毛虫）的“中性个体 / 中性性格 / 同等级”速度，所以默认绿毛虫 = 1 倍，手感不变；
#    速度翻倍约 ×1.41，四倍封顶 ×2；慢到一半约 ×0.71，再慢封底 ×0.7。试玩觉得过强过弱只调 0.7 / 2.0。
#    移动 / 吸球的总倍率还要乘速度能力等级倍率（原 max(2,2+s)/max(2,2-s)：+2 → ×2、-2 → ×0.5），
#    再整体夹在 0.25..3.0：movement_multiplier(速度, 参考, 等级倍率) = clamp(系数 × 等级倍率, 0.25, 3.0)。
#    玩家和敌人用同一套（敌人用自己的速度六维、自己的等级算参考速度）。
# 2. 命中 / 闪避加成（双方互相用）：
#      mult = clamp( (攻方速度 ÷ 守方速度) ^ 0.25, 0.85, 1.15 )
#    原作 hitCheck 算出的命中阈值再乘它，最后不超过 100%；一样快不变，必中招（命中 -1）不受影响。
#    命中和闪避用这一个式子同时体现，不另算。试玩觉得过强过弱只调 0.85 / 1.15。
# 无 RNG、无状态、不读节点；命中骰由调用方掷（1..100 整数）。

const Growth := preload("res://game/pokemon_growth.gd")
const Accuracy := preload("res://game/pokemon_accuracy.gd")

const REF_BASE_SPEED := 45
const FACTOR_MIN := 0.7
const FACTOR_MAX := 2.0
const FACTOR_EXP := 0.5
const MOVE_MIN := 0.25
const MOVE_MAX := 2.0   # 移动倍率上限（用户 2026-10-24：高速移动 + 风筝 16 分钟只挨 22 点，3 倍太快）
const HIT_MIN := 0.85
const HIT_MAX := 1.15
const HIT_EXP := 0.25


# 参考速度：种族值 45、同等级、给定个体值 / 性格倍率下的原作速度六维（第 6 项）。
static func reference_speed(level: int, ivs: Array = [], nature: Array = []) -> int:
	var base: Array = [REF_BASE_SPEED, REF_BASE_SPEED, REF_BASE_SPEED, REF_BASE_SPEED, REF_BASE_SPEED, REF_BASE_SPEED]
	return Growth.calculate_stats(base, level, ivs, nature)[5]


static func factor(effective_speed: float, ref_speed: float) -> float:
	if ref_speed <= 0.0:
		return 1.0
	if effective_speed <= 0.0:
		return FACTOR_MIN
	return clampf(pow(effective_speed / ref_speed, FACTOR_EXP), FACTOR_MIN, FACTOR_MAX)


static func movement_multiplier(speed_stat: float, ref_speed: float, stage_multiplier: float) -> float:
	return clampf(factor(speed_stat, ref_speed) * stage_multiplier, MOVE_MIN, MOVE_MAX)


static func hit_multiplier(attacker_speed: float, defender_speed: float) -> float:
	if attacker_speed <= 0.0 or defender_speed <= 0.0:
		return 1.0
	return clampf(pow(attacker_speed / defender_speed, HIT_EXP), HIT_MIN, HIT_MAX)


# 命中阈值：原作阶段阈值 × 速度倍率，上限 100；base < 0（必中）返回 -1.0 哨兵。
static func chance(base_accuracy: int, acc_stage: int, eva_stage: int, speed_mult: float) -> float:
	if base_accuracy < 0:
		return -1.0
	return minf(100.0, Accuracy.chance(base_accuracy, acc_stage, eva_stage) * speed_mult)


static func hits(base_accuracy: int, acc_stage: int, eva_stage: int, speed_mult: float, roll: int) -> bool:
	if base_accuracy < 0:
		return true
	return float(roll) <= chance(base_accuracy, acc_stage, eva_stage, speed_mult)
