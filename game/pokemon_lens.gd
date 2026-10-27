extends RefCounted
# 多重镜（用户 2026-10-18）：局外商店“单只培养”里按宠物买，买了之后这只的单体招能同时波及更多目标。
# 两种、各 3 级，每升一级多波及 1 个目标（1 级打 2 只、2 级 3 只、3 级 4 只）：
#   辅助多重镜 support：管变化类单体招（麻痹 / 催眠 / 混乱 / 降属性这些控场和削弱招），没有折扣。
#   进攻多重镜 attack：管有伤害的单体招，打到的每个目标伤害都打折（1 级 ×0.8、2 级 ×0.7、3 级 ×0.6）。
# 不生效：强化自己的招（变硬 / 回血 / 提升属性）、本来就是群体的招（放电 / 暗黑洞）、蓄力 / 连斩 / 反击这类特殊流程的招。
# 捕捉镜 capture（用户 2026-10-18：没有暴击 / 命中的镜，改成加精灵球捕捉率的）：这只宠物扔出去的所有球，捕获率再乘 ×1.2 / ×1.5 / ×2.0，
# 算在球倍率之外、和异常状态加成一起叠乘（原公式不改，只多一个倍率入口）。
# 价格（用户 2026-10-19“太贵了”）：三种都是 500 / 1000 / 1500。
# 闪光开局加级（用户 2026-10-19）：主角是闪光个体时三种镜都白加等级——金闪 +1、蓝闪 +2、红闪 +3（没买也加），最高算到 6 级；融合时两只的闪光加级相加，最高 9 级（MAX_EFFECTIVE，2026-10-21）。

const PREFIX := "LENS:"
const KINDS := ["support", "attack", "capture"]
const MAX_LEVEL := 3
const MAX_EFFECTIVE := 9   # 买满 3 级 + 融合两只红闪 3 + 3 级（用户 2026-10-21：融合闪光加级相加）
const PRICES := {
	"support": [500, 1000, 1500],
	"attack": [500, 1000, 1500],
	"capture": [500, 1000, 1500],
}
const ATTACK_DAMAGE_MULT := [1.0, 0.8, 0.7, 0.6, 0.55, 0.5, 0.45, 0.42, 0.4, 0.38]   # 下标 = 实际等级（4 级起只有闪光加级才到得了，7–9 级要融合两只闪光）
const CAPTURE_MULT := [1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]   # 下标 = 捕捉镜实际等级
const NAMES := {"support": "辅助多重镜", "attack": "进攻多重镜", "capture": "捕捉镜"}
const DESC := {
	"support": "变化类单体招（麻痹 / 催眠 / 混乱 / 降属性）同时波及更多目标：每级多 1 个，每个目标各自判命中；没有折扣",
	"attack": "有伤害的单体招同时打到更多目标：每级多 1 个，但打到的每个目标伤害都降低（1 级 ×0.8 / 2 级 ×0.7 / 3 级 ×0.6）",
	"capture": "这只宠物扔出去的所有球，捕获率再乘一个倍率：1 级 ×1.2 / 2 级 ×1.5 / 3 级 ×2.0（和球、异常状态的加成叠乘）",
}
const SHINY_NOTE := "闪光开局另加等级：金闪 +1 / 蓝闪 +2 / 红闪 +3（融合时两只的加级相加，最高 9 级；买只能到 3 级，再高靠刷闪光）"


# 闪光开局白加的等级：shiny_variant -1 普通 / 0 金 / 1 蓝 / 2 红。
static func shiny_bonus(shiny_variant: int) -> int:
	return clampi(shiny_variant + 1, 0, 3)


# 这一局实际生效的等级 = 买的等级 + 闪光加级，最高 MAX_EFFECTIVE。
static func effective_level(bought: int, shiny_variant: int) -> int:
	return clampi(bought + shiny_bonus(shiny_variant), 0, MAX_EFFECTIVE)


# 同上，但闪光加级直接给（融合时是两只的加级之和，用户 2026-10-21：蓝 + 蓝 = +4、金 + 红 = +4）。
static func effective_level_bonus(bought: int, bonus: int) -> int:
	return clampi(bought + maxi(0, bonus), 0, MAX_EFFECTIVE)
# 带这些效果的招走特殊流程（蓄力 / 连斩 / 延迟 / 反击…），不套多重镜。
const EXCLUDED_EFFECTS := ["charge", "frenzy", "delay", "delayed", "semi_invulnerable", "teleport", "counter", "rollout", "self_ko"]


static func product_id(kind: String) -> String:
	return PREFIX + kind


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX) and PRICES.has(source_id.trim_prefix(PREFIX))


static func kind_of(source_id: String) -> String:
	return source_id.trim_prefix(PREFIX) if is_product(source_id) else ""


# 买下一级要多少点；已满级返回 -1。level = 现在的等级（0..3）。
static func next_price(kind: String, level: int) -> int:
	if not PRICES.has(kind) or level >= MAX_LEVEL or level < 0:
		return -1
	return int((PRICES[kind] as Array)[level])


static func capture_mult(level: int) -> float:
	return float(CAPTURE_MULT[clampi(level, 0, MAX_EFFECTIVE)])


static func damage_mult(kind: String, level: int) -> float:
	if kind != "attack":
		return 1.0
	return float(ATTACK_DAMAGE_MULT[clampi(level, 0, MAX_EFFECTIVE)])
