extends RefCounted
# 原敌人等级公式 · 转写自原作 `Battle.getLevelForWave()` / `randSeedGaussForLevel()`
# （原块 `wave_levels` @ UTF-16 offset 5086655，SHA256 = be3d13ecbaba150decea4bedfabdf2204ca6a13900369434bd2ee2dba0fc2f1）。
#
# 只读源（静态读取，不执行整包）：
#   SHA256 = d3d97fe1acedd66094c3801b1ed13381eb0fa5ae0f64fdb7febe581adeec955c
#
# 本段只搬**等级公式**：不启动头目刷怪 / 分段血 / 奖励 / 训练家系统，不搭 GameMode 框架，
# 不改玩家成长 / 等级上限 / 现有 XP；也不把原作波次换算成本作秒数。
# 详细来源与边界见 `data/POKEMON_PLAINS_SOURCE.md`。
#
# 原作（classic 时 `getWaveForDifficulty(waveIndex) === waveIndex`）：
#   t = waveIndex
#   n = 1 + t/2 + (t/25)^2
#   非 10 倍数：f = 10/t；
#       randSeedGaussForLevel(f) = (循环 r 从 f 每次 -1、只要 r>0 就 sum += real(0,1)) / f
#       即**非整数 f 时跑 ceil(f) 次真实抽样，但分母仍是 f**（保留原怪异公式，不做平滑 / 缩放 / 钳制）；
#       再 level = max(Math.round(n + abs(noise)), 1)。
#   10 的倍数：o = floor(n*1.2)；
#       若 battleSpec === FINAL_BOSS 或 waveIndex%250==0 -> ceil(o/25)*25（**不抽样**）；
#       否则 waveFinal -> 不加随机；非 waveFinal -> o + Math.round(real(-1,1) * floor(t/10))。
#
# 随机来源通过**很小的 Callable 输入 0..1**（不传时用 Godot 全局 `randf()`）：
#   高斯分支每次抽样调用一次；10 倍数分支的 real(-1,1) = 2u-1 也调用一次。
# 测试可传固定队列 Callable；不复刻整套 Phaser RNG、不改全局 seed。
#
# **JS `Math.round` 负半值朝 +∞**（= floor(x+0.5)）；Godot `round()` 负半值不同，
# 所以这里显式用 `js_round()`，原向量里 unit=0.25 的 -0.5 就是反例。

# 原 `initBattleSpec()`：classic 且 waveIndex===200 时 FINAL_BOSS。
const CLASSIC_FINAL_BOSS_WAVE := 200
const WAVE_LEVEL_MULTIPLIER := 1.2
const BOSS_ROUND_UNIT := 25


# JS Math.round：floor(x + 0.5)，负半值朝 +∞（与 Godot round() 的负半值行为不同）。
static func js_round(value: float) -> int:
    return int(floor(value + 0.5))


# 原基础等级 n = 1 + t/2 + (t/25)^2（未加噪声）。
static func base_level(wave_index: int) -> float:
    var t := float(wave_index)
    var q := t / 25.0
    return 1.0 + t / 2.0 + q * q


# classic 的 FINAL_BOSS 判定（只做资料；实际 battleSpec 分段留给后续段）。
static func is_classic_final_boss(wave_index: int) -> bool:
    return wave_index == CLASSIC_FINAL_BOSS_WAVE


# 非 10 倍数分支的**真实抽样次数** = ceil(f)（f<=0 时 0 次）。只作资料 / 检查对照。
static func gauss_call_count(wave_index: int) -> int:
    if wave_index % 10 == 0:
        return 0
    var f := 10.0 / float(wave_index)
    if f <= 0.0:
        return 0
    return int(ceil(f))


# 按原公式返回等级；同时给出该次计算真实消耗的 RNG 调用次数（给检查 / 下一段接线用）。
static func level_and_calls(wave_index: int, unit_rand: Callable = Callable(),
        final_boss: bool = false, wave_final: bool = false) -> Dictionary:
    var t := float(wave_index)
    var n := base_level(wave_index)
    if wave_index % 10 != 0:
        var f := 10.0 / t
        var total := 0.0
        var calls := 0
        var r := f
        while r > 0.0:
            total += _rand01(unit_rand)
            r -= 1.0
            calls += 1
        var noise := absf(total / f)
        return {"level": maxi(js_round(n + noise), 1), "calls": calls}
    var o := int(floor(n * WAVE_LEVEL_MULTIPLIER))
    if final_boss or wave_index % 250 == 0:
        return {"level": int(ceil(float(o) / float(BOSS_ROUND_UNIT))) * BOSS_ROUND_UNIT, "calls": 0}
    if wave_final:
        return {"level": o, "calls": 0}
    var jitter := js_round((_rand01(unit_rand) * 2.0 - 1.0) * floor(t / 10.0))
    return {"level": o + jitter, "calls": 1}


# 只要等级的薄封装。
static func level_for_wave(wave_index: int, unit_rand: Callable = Callable(),
        final_boss: bool = false, wave_final: bool = false) -> int:
    return int(level_and_calls(wave_index, unit_rand, final_boss, wave_final)["level"])


static func _rand01(unit_rand: Callable) -> float:
    if unit_rand.is_valid():
        return float(unit_rand.call())
    return randf()
