extends RefCounted
# 进化规则 · 纯计算层（用户 2026-10-17：“做的时候一定要做进化，局内还要有进化道具卖，进化后要在图鉴里解锁”）。
#
#   自动进化   纯等级进化（原 SpeciesEvolution 无条件；时间 / 性别 / 形态条件本作没有昼夜 / 性别，宽松当等级进化）：等级到了就弹进化；
#   特殊进化   其余一律在局内商店买“进化道具”来进化（用户 2026-10-17：“特殊进化一律在商店显示可买的东西，靠这个物品进化”）：
#     item        原作的进化道具（石头 / 联系绳…）；
#     move        原作要会某招的（大舌头 → 滚动…）→ 同上；
#     special     其它条件（地点 / 随机…，如阿罗拉雷丘）→ 同上。
# 商店行的要求：等级到了该条目的 level；买了就进化（离开商店后播进化），不再看亲密度 / 招式。
# 目标物种本作还没接的（Species.has_species 为假）一律不出现：以后加地图 / 物种，进化自动跟着开。

const Table := preload("res://data/pokemon_evolutions.gd")
const Species := preload("res://data/pokemon_starter_species.gd")
const Moves := preload("res://data/pokemon_moves.gd")

# 商店档位：原 EvolutionItem 枚举 <= 50 是普通进化道具（EVOLUTION_ITEM，优秀档），> 50 是稀有进化道具（RARE_EVOLUTION_ITEM，究极档）。
const TIER_COMMON_ITEM := "EVOLUTION_ITEM"
const TIER_RARE_ITEM := "RARE_EVOLUTION_ITEM"
const PREFIX := "EVO:"   # 商店商品 ID：EVO:道具枚举名:目标物种 ID，如 EVO:WATER_STONE:134 / EVO:SPECIAL:169
const SPECIAL := "SPECIAL"   # 亲密度 / 招式 / 其它条件的特殊进化统一的道具名（商店里叫「进化契机」）


static func entries(species_id: int) -> Array:
	return Table.EVOLUTIONS.get(species_id, [])


# 自动进化目标（只有纯等级进化；特殊进化走商店，见 shop_options）。亲密度 / 招式参数保留只是为了老调用兼容，不再参与判断。
static func level_targets(species_id: int, level: int, _friendship := 0, _move_ids: Array = []) -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in entries(species_id):
		if str(e["kind"]) != "level":
			continue
		var to := int(e["to"])
		if out.has(to) or not Species.has_species(to) or level < int(e["level"]):
			continue
		out.append(to)
	return out


# 现在能在商店买的特殊进化：[{item, to, kind, note}]（等级到了该条目的 level、目标物种本作有；同一目标 + 同一道具只留一条）。
# item = 原进化道具枚举名；亲密度 / 招式 / 其它条件的特殊进化统一用 "SPECIAL"（商店里叫「进化契机」），note 写原条件。
static func shop_options(species_id: int, level: int) -> Array:
	var out: Array = []
	for e: Dictionary in entries(species_id):
		var kind := str(e["kind"])
		if kind == "level":
			continue
		var to := int(e["to"])
		if level < int(e["level"]) or not Species.has_species(to):
			continue
		var item := str(e["item"]) if kind == "item" else SPECIAL
		var dup := false
		for o: Dictionary in out:
			if int(o["to"]) == to and str(o["item"]) == item:
				dup = true
		if dup:
			continue
		out.append({"item": item, "to": to, "kind": kind, "note": _note_of(e)})
	return out


# 老名字（局内商店 / 检查沿用）。
static func item_options(species_id: int, level: int) -> Array:
	return shop_options(species_id, level)


static func _note_of(e: Dictionary) -> String:
	match str(e["kind"]):
		"friendship":
			var t := "原作：亲密度 ≥ %d" % int(e["friendship"])
			if e.has("needs_type"):
				t += "且会%s属性招" % str(e["needs_type"])
			if e.has("time"):
				t += "（%s）" % ("白天" if str(e["time"]) == "day" else "夜晚")
			return t
		"move":
			var m := str(e["move"])
			return "原作：会「%s」" % str(Moves.MOVES[m]["name"]) if Moves.MOVES.has(m) else "原作：会 %s" % m
		"special":
			return "原作：特殊条件（地点 / 随机等）"
	return ""


static func item_name(item: String) -> String:
	return str(Table.ITEM_ZH.get(item, item))


static func is_rare_item(item: String) -> bool:
	return Table.RARE_ITEMS.has(item)


# 商店档位：普通进化道具 = 优秀档（30 点），稀有进化道具 = 究极档（100 点）；点价沿用 game/pokemon_shop.gd 的原档位点价表。
static func price(item: String) -> int:
	var Shop := preload("res://game/pokemon_shop.gd")
	return int(Shop.TIER_POINT_COSTS[Shop.TIER_ULTRA if is_rare_item(item) else Shop.TIER_GREAT])


static func product_id(item: String, to: int) -> String:
	return "%s%s:%d" % [PREFIX, item, to]


static func is_product(source_id: String) -> bool:
	return parse(source_id).size() > 0


# 解析商品 ID -> {item, to}；不是进化道具商品返回空字典。
static func parse(source_id: String) -> Dictionary:
	if not source_id.begins_with(PREFIX):
		return {}
	var parts := source_id.substr(PREFIX.length()).split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	var item := str(parts[0])
	if not Table.ITEM_ZH.has(item):
		return {}
	return {"item": item, "to": int(parts[1])}


static func _has_move_of_type(move_ids: Array, type_zh: String) -> bool:
	for m in move_ids:
		if Moves.MOVES.has(str(m)) and str(Moves.MOVES[str(m)]["type"]) == type_zh:
			return true
	return false
