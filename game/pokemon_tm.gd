extends RefCounted
# 技能机器（TM）规则 · 局外成长（用户 2026-10-16 定“让宝可梦一开局就会某个招式；只能学它在 Rogue 学习器表里能学的招式；
# 价格按 Rogue 原有的招式分档”，2026-10-17 定“开局前选，最多填满 4 个槽”）。
#
#   tiers   招式 → 档位（COMMON / GREAT / ULTRA）；species 招式 → 能学的物种。
# 本作只列**已接战斗**（data/pokemon_moves.gd::IMPLEMENTED）的招；价格取原档位的点价（普通 10 / 优秀 30 / 究极 100，
# 和 game/pokemon_shop.gd::TIER_POINT_COSTS 同一张表）。

const Moves := preload("res://data/pokemon_moves.gd")
const PATH := "res://data/rogue_upstream/tms.json"
const TIER_COST := {"COMMON": 10, "GREAT": 30, "ULTRA": 100}
const TIER_ZH := {"COMMON": "普通", "GREAT": "优秀", "ULTRA": "究极"}
const PREFIX := "TM:"            # 商店商品 ID：TM:招式小写 id，如 TM:psychic
const MAX_SLOTS := 4

static var _loaded := false
static var _tiers: Dictionary = {}      # 小写招式 id -> 档位
static var _species: Dictionary = {}    # 小写招式 id -> {物种 id: true}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for m in parsed["tiers"]:
		_tiers[str(m).to_lower()] = str(parsed["tiers"][m])
	for m in parsed["species"]:
		var set := {}
		for e in parsed["species"][m]:
			set[int(e[0]) if e is Array else int(e)] = true
		_species[str(m).to_lower()] = set


# 这个招式是不是本作的技能机器（已接战斗 + 原版有这个机器）。
static func is_tm(move_id: String) -> bool:
	_load()
	return _tiers.has(move_id) and Moves.is_implemented(move_id)


# 本作改的档（用户 2026-10-24：聚气改成被动常驻会心 1/2 以后，原版普通档 10 点太便宜）。
const TIER_OVERRIDE := {"focus_energy": "ULTRA"}


static func tier_of(move_id: String) -> String:
	_load()
	if TIER_OVERRIDE.has(move_id) and _tiers.has(move_id):
		return str(TIER_OVERRIDE[move_id])
	return str(_tiers.get(move_id, ""))


static func price(move_id: String) -> int:
	if not is_tm(move_id):
		return -1
	return int(TIER_COST[tier_of(move_id)])


static func can_learn(species_id: int, move_id: String) -> bool:
	_load()
	return is_tm(move_id) and (_species.get(move_id, {}) as Dictionary).has(species_id)


# 这只宝可梦能学的（本作已接战斗的）技能机器：按档位（普通 → 优秀 → 究极）再按招式 id 排，列表稳定。
static func learnable(species_id: int) -> Array:
	_load()
	var out: Array = []
	for m in _tiers:
		if is_tm(str(m)) and (_species.get(m, {}) as Dictionary).has(species_id):
			out.append(str(m))
	out.sort_custom(func(a, b):
		var ra := int(TIER_COST[_tiers[a]])
		var rb := int(TIER_COST[_tiers[b]])
		return ra < rb or (ra == rb and str(a) < str(b)))
	return out


# 商店商品 ID ↔ 招式 id。
static func product_id(move_id: String) -> String:
	return PREFIX + move_id


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX) and is_tm(source_id.substr(PREFIX.length()))


static func move_of(source_id: String) -> String:
	return source_id.substr(PREFIX.length()) if source_id.begins_with(PREFIX) else ""


# 开局最多还能带几个机器：4 个槽 − 这只的开局招数（开局招是封印过滤后的可用招）。
static func capacity(initial_move_count: int) -> int:
	return maxi(0, MAX_SLOTS - initial_move_count)


# ================= 融合 + 带招（用户 2026-10-22：“融合怪物应该 2 个的技能都有，买了的技能应该都带”；槽数现阶段还是 4）=================

# 开局招候选：自己的可用开局招 + 融合对象的（去重，自己的在前）。partner = 0 就是没融合。
static func starter_pool(species_id: int, partner := 0) -> Array:
	var Starters := load("res://game/pokemon_starters.gd")
	var out: Array = []
	for m in Starters.playable_initial_moves(species_id):
		out.append(str(m))
	if partner > 0:
		for m in Starters.playable_initial_moves(partner):
			if not out.has(str(m)):
				out.append(str(m))
	return out


# 融合了：两只能学的技能机器合在一起（顺序同 learnable：档位 → 招式 id）。
static func learnable_fused(species_id: int, partner := 0) -> Array:
	var out := learnable(species_id)
	if partner <= 0:
		return out
	for m in learnable(partner):
		if not out.has(m):
			out.append(m)
	out.sort_custom(func(a, b):
		var ra := int(TIER_COST[_tiers[a]])
		var rb := int(TIER_COST[_tiers[b]])
		return ra < rb or (ra == rb and str(a) < str(b)))
	return out


static func can_learn_fused(species_id: int, move_id: String, partner := 0) -> bool:
	return can_learn(species_id, move_id) or (partner > 0 and can_learn(partner, move_id))


# 开局真正带的招：买的机器优先（带着的，最多 4 个），剩下的槽按顺序放没留在家里的开局招。
# 顺序：开局招在前、机器在后（和战斗里招式栏一致）。
# 自由选择（用户 2026-10-24：“他好像是按照序列走的，按理来说应该是自由选择的”）：
# saved = 玩家在“管理招式”里点出来的清单（按点的顺序）；只留现在还能带的（开局招 / 融合招 / 买过的机器 / 遗传招）。
# 没选过（空）或者清单里一个能打人的都没有 → 用默认配法（下面的 carried）。
static func resolve_loadout(saved: Array, starters: Array, benched: Array, owned: Array, equipped: Array, slots := MAX_SLOTS) -> Array:
	if saved.is_empty():
		return carried(starters, benched, equipped, slots)
	var out: Array = []
	for m in saved:
		var id := str(m)
		if out.size() >= slots:
			break
		if out.has(id) or not Moves.is_implemented(id):
			continue
		if starters.has(id) or owned.has(id):
			out.append(id)
	var Starters := load("res://game/pokemon_starters.gd")
	if out.is_empty() or not Starters.has_damage_move(out):
		return carried(starters, benched, equipped, slots)
	return out


static func carried(starters: Array, benched: Array, equipped: Array, slots := MAX_SLOTS) -> Array:
	var tms: Array = []
	for m in equipped:
		if tms.size() >= slots:
			break
		if Moves.is_implemented(str(m)) and not tms.has(str(m)):
			tms.append(str(m))
	var out: Array = []
	for m in starters:
		if out.size() + tms.size() >= slots:
			break
		if not benched.has(str(m)) and not tms.has(str(m)):
			out.append(str(m))
	# 至少要有一个能打人的招：全是变化招时，把最后一个机器换成第一个能伤害的开局招（先找没留在家里的）。
	# 选宠页 / 商店 / 开局都走这里，显示和实际一致（2026-10-22 审查发现开局兜底和预览不一样）。
	var Starters := load("res://game/pokemon_starters.gd")
	if not Starters.has_damage_move(out + tms):
		var pick := ""
		for pass_benched in [false, true]:
			for m in starters:
				if pick == "" and benched.has(str(m)) == pass_benched and Starters.has_damage_move([str(m)]):
					pick = str(m)
		if pick != "":
			if out.size() + tms.size() >= slots:
				if not tms.is_empty():
					tms.pop_back()
				else:
					out.pop_back()
			out.append(pick)
	return out + tms
