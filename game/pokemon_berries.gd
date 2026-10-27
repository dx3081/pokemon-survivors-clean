extends RefCounted
# 树果（用户 2026-10-18：“树果就是自动回血、自动去除异常”）。
# 局内商店买，每种最多带 9 个，本局有效；带着就会自动吃，不用点：
#   文柚果 SITRUS：血量降到 25% 以下自动吃（原版一半；用户 2026-10-24：比回血招的 50% 低，招先放、果子保命），回最大 HP 的 25%（吃一个之后隔 SITRUS_GAP 秒才吃下一个）。
#   木子果 LUM：一中主要异常（麻痹 / 中毒 / 睡眠 / 冰冻 / 灼伤）或混乱就自动吃，当场全解除（用户 2026-10-18：混乱也管）。
# 数值（价钱 20、上限 9、一半血、25%、文柚果隔 8 秒）是实现时先定的，用户试玩后再调。
# 这里只放常量和纯函数；吃的时机在 main/combat.gd 的 _berry_tick，买在 main/state.gd 的 _shop_buy_berry。

const PREFIX := "BERRY:"
const KINDS := ["SITRUS", "LUM"]
const CAP := 9
const PRICE := 20   # 比万灵药（30 点、买了立刻用）便宜、还自动吃（用户：买树果更划算）
const SITRUS_TRIGGER := 0.25   # 血量比例 ≤ 这个才吃（低于回血招的 50%）
const SITRUS_HEAL := 0.25     # 回最大 HP 的这个比例
const SITRUS_GAP := 8.0       # 吃完一个文柚果后，隔这么多秒（真实战斗时间）才吃下一个（用户：冷却久一点，不然死不了）
const LUM_GAP := 1.0          # 木子果的间隔：异常要马上解，只隔 1 秒
const LUM_GUARD := 5.0        # 吃下木子果后这么多秒内不会再中异常（用户 2026-10-20：做成持续一段时间；借神秘守护的计时）

const INFO := {
	"SITRUS": {"name": "文柚果", "icon": "sitrus_berry", "desc": "血量降到 25% 以下时自动吃掉，回复最大 HP 的 25%（吃完隔 8 秒才吃下一个；比回血招晚触发，留着保命）"},
	"LUM": {"name": "木子果", "icon": "lum_berry", "desc": "中了异常（麻痹 / 中毒 / 睡眠 / 冰冻 / 灼伤 / 混乱）时自动吃掉，当场全部解除，之后 5 秒不会再中异常"},
}


static func product_id(kind: String) -> String:
	return PREFIX + kind


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX) and INFO.has(source_id.trim_prefix(PREFIX))


static func kind_of(source_id: String) -> String:
	return source_id.trim_prefix(PREFIX) if is_product(source_id) else ""


static func display_name(kind: String) -> String:
	return str((INFO.get(kind, {}) as Dictionary).get("name", kind))


static func icon_name(kind: String) -> String:
	return str((INFO.get(kind, {}) as Dictionary).get("icon", ""))


static func describe(kind: String) -> String:
	return str((INFO.get(kind, {}) as Dictionary).get("desc", ""))


static func sitrus_amount(max_hp: float) -> int:
	return maxi(1, int(floorf(maxf(0.0, max_hp) * SITRUS_HEAL)))
