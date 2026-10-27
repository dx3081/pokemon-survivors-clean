extends RefCounted
#
# 只做「一次投球对一只敌人」的概率 / 尝试结果，不接投球 UI、地面选圈、球库存、
# 捕获移除敌人、持久解锁、选角或捕获特效。调用者拿到结果自己播动画 / 记解锁。
#
# 来源（静态只读，不执行原包）：
#   bundle SHA256 D3D97FE1...，原块 `attempt_capture`（UTF-16 offset 5619295）等见
#
# 当前已迁移 Classic 版原公式（不升级游戏版本，不引入新版 critical capture）：
#   n = 3 * maxHp
#   r = 2 * hp
#   a = JS Math.round((n - r) * catchRate * ballMultiplier / n * statusMultiplier)
#   b = JS Math.round(65536 / Math.sqrt(Math.sqrt(255 / a)))
#   JS Math.round 对正数 = floor(x + 0.5)，本模块显式 floor(x+0.5)，不用 Godot 的取整。
#   不先 floor hp、不 clamp a 到 255、不改四次摇球；满 3 次摇球后无条件成功。
#   hp 是 float：真实 Enemy.hp（main/state.gd）可带小数，三个公开入口与内部计算
#   端到端保留小数，绝不在入口 int / floor / round 掩盖；maxHp 仍按实际整数。
#   非有限 hp（NaN / ±INF）按 invalid 处理（0 骰、不报错），不当正常概率。
#
# 逐次判定（严格 roll < b）：
#   randSeedInt(65536) ∈ [0, 65535]，只有 roll < b 才继续摇；失败立即停止。
#   必中过阈值的球仍消耗 3 次骰；a = 0 / b = 0 时第一次 roll 失败、耗 1 次。
#   最多 3 次。MASTER_BALL 走 `f === -1` 保证捕获分支，耗 0 次骰。
#   不可获得对象在原 `onRepeat` 先拒绝（连 MASTER 也不绕过），耗 0 次。
#   HP <= 0 在 `start()` 就 `end()`，不会进入捕获，耗 0 次。
#
# 球倍率用**官方**值（commit 7a692ebf6905f4c3c1030319b5eb6d353be1c201）：
#   0 POKEBALL=1 / 1 GREAT_BALL=1.5 / 2 ULTRA_BALL=2 / 3 ROGUE_BALL=3 /
#   4 MASTER_BALL=-1 / 5 LUXURY_BALL=1（enum 资料，不在原 PLAYER 奖励池 / 商店卖）。
#   本地“100%捕捉无限抽卡版”把前四球改成 100；本模块**不采用**那组作弊倍率。
#
# 状态倍率照原 `wae`：POISON=1 / TOXIC=2 / PARALYSIS=3 / BURN=6 -> 1.5；
#   SLEEP=4 / FREEZE=5 -> 2.5；其余（含无状态与未知值）-> 1。
#   混乱是独立 tag，不在这个主要异常枚举里，**不额外加成**。
#
# 返回值 keys：result / captured / shakes / rolls / modified_catch_rate /
#   shake_threshold / reason。refused / invalid 路径的 a、b 记 -1（不适用），
#   绝不伪装成正常概率；本模块不 printerr / push_error。

const Species := preload("res://data/pokemon_capture_species.gd")

# 球枚举 0..5（照源 PokeballType 顺序）。
const BALL_POKEBALL := 0
const BALL_GREAT_BALL := 1
const BALL_ULTRA_BALL := 2
const BALL_ROGUE_BALL := 3
const BALL_MASTER_BALL := 4
const BALL_LUXURY_BALL := 5

# 官方 getPokeballCatchMultiplier（不是本地 100 版）。
const BALL_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.0, 3.0, -1.0, 1.0]

# 原主要异常 Re 枚举（混乱不在这里）。
const STATUS_NONE := 0
const STATUS_POISON := 1
const STATUS_TOXIC := 2
const STATUS_PARALYSIS := 3
const STATUS_SLEEP := 4
const STATUS_FREEZE := 5
const STATUS_BURN := 6

# 原 wae 的两个倍率。
const STATUS_MULTIPLIER_POST_TURN := 1.5 # 1 / 2 / 3 / 6
const STATUS_MULTIPLIER_SLEEP_FREEZE := 2.5 # 4 / 5
const STATUS_MULTIPLIER_NONE := 1.0

# 原 randSeedInt(65536)：请求上界不含，返回值 [0, 65535]。
const RNG_MAX_EXCLUSIVE := 65536
# 最多 3 次摇球；3 次都过阈即成功。
const SHAKE_COUNT := 3
# 原 catchRate 正常范围（HP 检查用同 species 表）。
const MAX_CATCH_RATE := 255

# 尝试结果码（少量、明确）。
const RESULT_CAPTURED := 0
const RESULT_BROKE_FREE := 1
const RESULT_NOT_OBTAINABLE := 2
const RESULT_FAINTED := 3
const RESULT_INVALID := 4

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# 唯一随机入口：rng 有效时调用注入的 Callable（签名 `func(max_exclusive: int) -> int`，
# 返回 [0, max_exclusive) 的整数；本模块只请求 65536）；否则用 Godot 整数骰。
func _next_roll(rng: Callable = Callable()) -> int:
	if rng.is_valid():
		return int(rng.call(RNG_MAX_EXCLUSIVE))
	return _rng.randi_range(0, RNG_MAX_EXCLUSIVE - 1)


static func is_valid_ball(ball_type: int) -> bool:
	return ball_type >= 0 and ball_type < BALL_MULTIPLIERS.size()


# 球倍率；非法球返回 NAN（调用前先用 is_valid_ball 判定）。
static func ball_multiplier(ball_type: int) -> float:
	if not is_valid_ball(ball_type):
		return NAN
	return BALL_MULTIPLIERS[ball_type]


# 原 wae：未知值（含无状态 / 混乱不在枚举）返回 1。
static func status_multiplier(status_effect: int) -> float:
	match status_effect:
		STATUS_POISON, STATUS_TOXIC, STATUS_PARALYSIS, STATUS_BURN:
			return STATUS_MULTIPLIER_POST_TURN
		STATUS_SLEEP, STATUS_FREEZE:
			return STATUS_MULTIPLIER_SLEEP_FREEZE
	return STATUS_MULTIPLIER_NONE


# a = JS Math.round((n-r)*catchRate*ballMultiplier/n*statusMultiplier)。
# 乘法顺序与源一致；正值 half-up 用 floor(x+0.5)。
# hp 是 float：真实 Enemy.hp（main/state.gd）可能带小数，全程保留，
# 绝不在此入口 int()/floor()/round() 先把 hp 变成整数。
static func modified_catch_rate(max_hp: int, hp: float, catch_rate: int,
		ball_mult: float, status_mult: float) -> int:
	var n := 3.0 * float(max_hp)
	var r := 2.0 * hp
	var raw := (n - r) * float(catch_rate) * ball_mult / n * status_mult
	return int(floor(raw + 0.5))


# b = JS Math.round(65536 / Math.sqrt(Math.sqrt(255 / a)))；a = 0 时源得 0。
# 不 clamp a；a >= 255 时 b >= 65536（roll 必过）。
static func shake_threshold(a: int) -> int:
	if a <= 0:
		return 0
	return int(floor(65536.0 / sqrt(sqrt(255.0 / float(a))) + 0.5))


static func _result(result: int, captured: bool, shakes: int, rolls: int,
		a: int, b: int, reason: String) -> Dictionary:
	return {
		"result": result,
		"captured": captured,
		"shakes": shakes,
		"rolls": rolls,
		"modified_catch_rate": a,
		"shake_threshold": b,
		"reason": reason,
	}


# 原始纯入口：直接给 catchRate。
#   hp 是 float，端到端保留真实小数 HP（不 int / floor / round）。
#   obtainable=false 复刻原 `!species.isObtainable()` 的第一时间拒绝（0 骰）。
#   非法球 / 非法 catchRate / 非法 HP 范围 -> RESULT_INVALID（0 骰，不伪装概率）。
#   hp == 0 -> RESULT_FAINTED（0 骰）。hp > maxHp / maxHp <= 0 / hp < 0 属非法范围。
#   非有限 hp（NaN / ±INF）-> RESULT_INVALID / hp_not_finite（0 骰，不报错、不当正常概率）。
#   未知 status 值不报错，按源 wae 返回倍率 1。
func attempt(max_hp: int, hp: float, catch_rate: int, ball_type: int,
		status_effect: int = STATUS_NONE, obtainable: bool = true,
		rng: Callable = Callable(), lens_mult: float = 1.0) -> Dictionary:
	if not is_valid_ball(ball_type):
		return _result(RESULT_INVALID, false, 0, 0, -1, -1, "unknown_ball")
	if catch_rate < 0 or catch_rate > MAX_CATCH_RATE:
		return _result(RESULT_INVALID, false, 0, 0, -1, -1, "catch_rate_range")
	if not is_finite(hp):
		return _result(RESULT_INVALID, false, 0, 0, -1, -1, "hp_not_finite")
	if max_hp <= 0 or hp < 0.0 or hp > float(max_hp):
		return _result(RESULT_INVALID, false, 0, 0, -1, -1, "hp_range")
	if hp == 0.0:
		return _result(RESULT_FAINTED, false, 0, 0, -1, -1, "fainted")
	if not obtainable:
		return _result(RESULT_NOT_OBTAINABLE, false, 0, 0, -1, -1, "not_obtainable")
	var ball_mult := ball_multiplier(ball_type)
	if ball_mult == -1.0:
		# 原 `f === -1 || ...`：保证捕获分支，不耗骰；仍是 3 次摇球演出后成功。
		return _result(RESULT_CAPTURED, true, SHAKE_COUNT, 0, -1, -1, "master_ball")
	# lens_mult = 捕捉镜倍率（局外买的，默认 1.0 = 没有）；和球倍率、异常状态倍率一起乘进去，原公式不改。
	var a := modified_catch_rate(max_hp, hp, catch_rate, ball_mult * lens_mult,
		status_multiplier(status_effect))
	var b := shake_threshold(a)
	var rolls := 0
	for i in SHAKE_COUNT:
		rolls += 1
		if _next_roll(rng) >= b:
			return _result(RESULT_BROKE_FREE, false, i + 1, rolls, a, b, "broke_free")
	return _result(RESULT_CAPTURED, true, SHAKE_COUNT, rolls, a, b, "captured")


# 按稳定 source_species_id 查当前 84 条捕获率表再尝试。
# 表外物种 -> RESULT_INVALID / reason=unknown_species（0 骰）。
# hp 同样是 float，原样透传给 attempt，不在本入口截断小数。
# 表内 84 条全是当前可获得 / 可捕获物种，故 obtainable 取 true；
# 原 `isObtainable()` 的表外不可获得分支由 attempt(..., obtainable=false) 留给后续接线。
func attempt_by_species(source_species_id: int, max_hp: int, hp: float, ball_type: int,
		status_effect: int = STATUS_NONE, rng: Callable = Callable(), lens_mult: float = 1.0) -> Dictionary:
	var rate := Species.catch_rate(source_species_id)
	if rate == Species.UNKNOWN:
		return _result(RESULT_INVALID, false, 0, 0, -1, -1, "unknown_species")
	return attempt(max_hp, hp, rate, ball_type, status_effect, true, rng, lens_mult)
