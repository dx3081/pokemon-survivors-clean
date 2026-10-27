extends RefCounted
#
# 严格照原作 `ms(level, growthRate)`（源内 getLevelTotalExp）+ `rX = ms(i)-ms(i-1)`，
# 覆盖当前 84 物种实际出现的 4 组成长率：
#   1 = FAST / 2 = MEDIUM_FAST / 3 = MEDIUM_SLOW / 4 = SLOW。
#   0 = ERRATIC、5 = FLUCTUATING 本作 84 条里没有，明确不支持（返回 -1），不猜公式。
#
# 原函数（只读 bundle `index-7def6496.js`，源块 SHA256 见
# data/POKEMON_STARTER_SPECIES_SOURCE.md）：
#   function ms(i,t){
#     if(i<100){const r=Fae[t][i-1]; return t!==2?Math.floor(r*.325+ms(i,2)*.675):r}
#     let n; switch(t){
#       case 1:n=Math.pow(i,3)*4/5; break;
#       case 2:n=Math.pow(i,3); break;
#       case 3:n=Math.pow(i,3)*6/5-15*Math.pow(i,2)+100*i-140; break;
#       case 4:n=Math.pow(i,3)*5/4; break }
#     return Math.floor(t!==2?n*.325+ms(i,2)*.675:n)}
#   function rX(i,t){return ms(i,t)-ms(i-1,t)}
# 非 MEDIUM_FAST 组在原作里是「本组原值 *.325 + MEDIUM_FAST 原值 *.675」的混合，
# 次序固定为 .325 在前；level<100 用 Fae 表项，level>=100 用 switch 公式（**不读**
# Fae 表最后一格），两侧都要按 t!==2 再混合、再由 Math.floor 取整。100 是原函数
# 的分支边界，101 / 150 / 200 也照源公式，不做通用宝可梦网络公式、不加经验缩放。
#
# 本层只做纯计算：不读节点、不读存档、不弹界面、不改实场经验。旧
# game/pokemon_growth.gd 仍是当前实场曲线（MEDIUM_FAST 立方），本段**不接线**。

const Species := preload("res://data/pokemon_starter_species.gd")

# 没有等级上限（用户 2026-10-17）：原来这里封顶 100（xp_needed 在 level>=100 时返回 0）；
# 现在放到 9999 当“无限”，100 级以后按下面 total_exp 的公式分支继续算。
const MAX_LEVEL := 9999
# 未知成长组 / 未知物种 / level<1 的明确无资料值。
const UNKNOWN := -1


# 原作 ms(level, growth_rate)：该组该等级的原累计总经验；未知组或 level<1 返回 -1。
static func total_exp(level: int, growth_rate: int) -> int:
	if level < 1 or not Species.EXP_TABLES.has(growth_rate):
		return UNKNOWN
	if level < 100:
		var raw := float(Species.EXP_TABLES[growth_rate][level - 1])
		if growth_rate == 2:
			return int(raw)
		# 原 r 与 ms(level, MEDIUM_FAST) 的混合；MEDIUM_FAST 原值 = level^3 的表项。
		return int(floor(raw * 0.325 + float(total_exp(level, 2)) * 0.675))
	var n := 0.0
	match growth_rate:
		0:
			# ERRATIC（原 exp.ts：(level^4 + level^3 × 2000) / 3500）
			n = (pow(float(level), 4.0) + pow(float(level), 3.0) * 2000.0) / 3500.0
		5:
			# FLUCTUATING（原 exp.ts：level^3 × (level/2 + 8) × 4 / (100 + level)）
			n = pow(float(level), 3.0) * (float(level) / 2.0 + 8.0) * 4.0 / (100.0 + float(level))
		1:
			n = pow(float(level), 3.0) * 4.0 / 5.0
		2:
			n = pow(float(level), 3.0)
		3:
			n = (pow(float(level), 3.0) * 6.0 / 5.0
				- 15.0 * pow(float(level), 2.0) + 100.0 * float(level) - 140.0)
		4:
			n = pow(float(level), 3.0) * 5.0 / 4.0
	if growth_rate == 2:
		return int(floor(n))
	return int(floor(n * 0.325 + float(total_exp(level, 2)) * 0.675))


# 原 rX(level, growth_rate)：从 level 升到 level+1 的原经验差。
# 未知组 / level<1 = -1；已知且 level>=MAX_LEVEL（9999，实际不会到）= 0。
static func xp_needed(level: int, growth_rate: int) -> int:
	if level < 1 or not Species.EXP_TABLES.has(growth_rate):
		return UNKNOWN
	if level >= MAX_LEVEL:
		return 0
	return total_exp(level + 1, growth_rate) - total_exp(level, growth_rate)


# 按该物种唯一成长率查升级所需经验；未知物种返回 -1，**不套 MEDIUM_FAST 兜底**。
static func species_xp_needed(species_id: int, level: int) -> int:
	var growth := Species.growth_rate(species_id)
	if growth == UNKNOWN:
		return UNKNOWN
	return xp_needed(level, growth)
