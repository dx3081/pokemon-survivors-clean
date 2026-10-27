extends RefCounted
# 原作命中 / 闪避能力阶段比例 · 纯计算层（2026-10-15 泼沙接真实战斗轮）。
#
# 唯一事实：只读源 bundle 的原 `hitCheck(t)` 静态切片（不执行 JS）：
#   bundle SHA256 D3D97FE1ACEDD66094C3801B1ED13381EB0FA5AE0F64FDB7FEBE581ADEEC955C
#   hitCheck 原函数 UTF-16 offset 5586453、1352 字、SHA256
#   388D6C3A1C9733B6253F93DF277567EF7597D9C7FE80B110DD4372871810C1E0
#   经理 169 组合向量（ACC/EVA 各 -6..6 共 169，accuracy 95 / 100 两档）在该 fixture 里逐条对照。
#
# 源函数里与本层有关的一段（Normal 战斗、无天气 / 特性 / 道具 / 速度修正、无 applyModifiers 命中项）：
#   const o = new ft(n.summonData.battleStats[le.ACC]);   // 攻方 ACC 阶段
#   const I = new ft(t.summonData.battleStats[le.EVA]);   // 守方 EVA 阶段
#   const s = n.randSeedInt(100,1);                       // 1..100 整数骰
#   const u = new Kt(1);
#   o.value !== I.value && (u.value = o.value > I.value
#       ? (3+Math.min(o.value-I.value,6))/3
#       : 3/(3+Math.min(I.value-o.value,6)));
#   ...
#   return s <= l.value*u.value;
# 先合并「攻方 ACC 阶段 - 守方 EVA 阶段」再钳 [-6,6]，**不是**把两个阶段各算一个倍率再相乘；
# 原式是 3 基数（+1 级 = 4/3），不是能力值那套 2 基数（+1 级 = 3/2）。
# 没有提前 floor、不把原 float 阈值截成 int；原倍率允许阈值 > 100（骰仍 1..100，必命中），
# 本层不自己发明 100% cap / 速度修正 / 天气特性道具项。
#
# 有关「必中 / 直接成功」：原 `hitCheck` 在算阶段之前有
#   `const l=new Kt(this.move.getMove().accuracy); if(l.value===-1)return!0;`
# 所以 base_accuracy < 0 的招式在掷骰前直接命中，本层的 `hits` 保留这条早返回；
# `chance` 对这种招式返回 -1.0 作「不适用 / 必中」哨兵，调用方不得把它当阈值比较。
#
# 本层无 RNG、无存档、不读节点、不写状态：只做纯函数，命中骰由调用方掷（生产 randi_range(1,100)）。

# 原阶段钳制范围（StatChangeAttr 的 [-6,6]，与 data/pokemon_moves.gd / main/state.gd 同一值）。
const STAGE_MIN := -6
const STAGE_MAX := 6
# 原式阶段倍率的基数：3（+n → (3+n)/3，-n → 3/(3+n)）。
const STAGE_BASE := 3


# 原 `o.value !== I.value` 分支合成后的倍率：
#   delta = clamp(acc_stage - eva_stage, -6, 6)
#   delta >= 0 → (3+delta)/3；delta < 0 → 3/(3-delta)
# delta 是浮点比较的等价整数形式；delta == 0 与源码相同返回 1（不是 (3+0)/3 之外的任何值）。
static func stage_multiplier(acc_stage: int, eva_stage: int) -> float:
	var delta := clampi(acc_stage - eva_stage, STAGE_MIN, STAGE_MAX)
	if delta == 0:
		return 1.0
	if delta > 0:
		return float(STAGE_BASE + delta) / float(STAGE_BASE)
	return float(STAGE_BASE) / float(STAGE_BASE - delta)


# 原命中阈值 `l.value * u.value`（accuracy × 阶段倍率），不 floor、不截 int。
# base_accuracy < 0（原作 -1 必中）返回 -1.0 哨兵；其余返回原 float 阈值，可能 > 100。
static func chance(base_accuracy: int, acc_stage: int, eva_stage: int) -> float:
	if base_accuracy < 0:
		return -1.0
	return float(base_accuracy) * stage_multiplier(acc_stage, eva_stage)


# 原 `s <= l.value * u.value`：roll 是 randSeedInt(100,1) 的 1..100 整数骰。
# base_accuracy < 0 时按源在掷骰前的 `return !0` 直接命中（调用方仍可不掷骰，语义一致）。
static func hits(base_accuracy: int, acc_stage: int, eva_stage: int, roll: int) -> bool:
	if base_accuracy < 0:
		return true
	return float(roll) <= chance(base_accuracy, acc_stage, eva_stage)
