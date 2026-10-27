extends RefCounted
# 记忆蘑菇（用户 2026-10-18）：局内商店里买，恢复宠物“忘掉”的技能。
# 能恢复两类招（局内不卖技能机器：胡地被恶系追杀没辙就去局外买机器学）：
#   1. 在城镇用技能机器学过、但现在没带的（开局没带、被新招替换掉、留在家里都算）；
#   2. 这一局被新招换掉 / 忘掉的招（run_forgotten；原版记忆蘑菇就是想起忘掉过的招，用户 2026-10-19）；
#   3. 原版规则：现在这个形态到当前等级为止学习表里的招（含进化招、只能回忆的招），没带着的都算（用户 2026-10-20）。
# 买一个恢复一招：有空槽直接学；槽满要选换掉哪一招。商品 ID 写成 "MEMORY:招式id:槽位"（槽位 free = 空槽，0..3 = 替换第几招）。

const PREFIX := "MEMORY:"
const PRICE := 30


static func product_id(move_id: String, slot) -> String:
	return "%s%s:%s" % [PREFIX, move_id, str(slot)]


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX) and source_id.split(":").size() == 3


# 返回 {"move": 招式 id, "slot": -1（空槽）或 0..3}；不合法返回空字典。
static func parse(source_id: String) -> Dictionary:
	if not is_product(source_id):
		return {}
	var parts := source_id.split(":")
	var slot_text := str(parts[2])
	if slot_text == "free":
		return {"move": str(parts[1]), "slot": -1}
	if slot_text.is_valid_int() and int(slot_text) >= 0:
		return {"move": str(parts[1]), "slot": int(slot_text)}
	return {}
