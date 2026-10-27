extends RefCounted
# 平原之外已接线的地区物种资料（用户 2026-10-17：“地图改开始做了，先复用平原的素材”）。
# SPECIES / ATLAS / PREVOLUTIONS + 捕获率 / 成长率 / 学习表），图集在 assets/pokemon/<地区>/。
# 平原那份（data/pokemon_wild_species.gd 的 SPECIES / ATLAS）保持不变；这里只补平原没有的物种，
# 查询统一走 data/pokemon_wild_species.gd 的 row / has_species / atlas_dir，不要直接读这里。
# 新地区接线 = 在 MODULES 里加一行（生成器会跳过已有物种，所以各地区物种互不重复）。

const MODULES: Array[Dictionary] = [
	{"biome": "grass", "dir": "grass", "data": preload("res://data/pokemon_wild_species_grass.gd")},
	{"biome": "tall_grass", "dir": "tall_grass", "data": preload("res://data/pokemon_wild_species_tall_grass.gd")},
	{"biome": "metropolis", "dir": "metropolis", "data": preload("res://data/pokemon_wild_species_metropolis.gd")},
	{"biome": "forest", "dir": "forest", "data": preload("res://data/pokemon_wild_species_forest.gd")},
	{"biome": "sea", "dir": "sea", "data": preload("res://data/pokemon_wild_species_sea.gd")},
	{"biome": "swamp", "dir": "swamp", "data": preload("res://data/pokemon_wild_species_swamp.gd")},
	{"biome": "beach", "dir": "beach", "data": preload("res://data/pokemon_wild_species_beach.gd")},
	{"biome": "lake", "dir": "lake", "data": preload("res://data/pokemon_wild_species_lake.gd")},
	{"biome": "seabed", "dir": "seabed", "data": preload("res://data/pokemon_wild_species_seabed.gd")},
	{"biome": "mountain", "dir": "mountain", "data": preload("res://data/pokemon_wild_species_mountain.gd")},
	{"biome": "badlands", "dir": "badlands", "data": preload("res://data/pokemon_wild_species_badlands.gd")},
	{"biome": "cave", "dir": "cave", "data": preload("res://data/pokemon_wild_species_cave.gd")},
	{"biome": "desert", "dir": "desert", "data": preload("res://data/pokemon_wild_species_desert.gd")},
	{"biome": "ice_cave", "dir": "ice_cave", "data": preload("res://data/pokemon_wild_species_ice_cave.gd")},
	{"biome": "meadow", "dir": "meadow", "data": preload("res://data/pokemon_wild_species_meadow.gd")},
	{"biome": "power_plant", "dir": "power_plant", "data": preload("res://data/pokemon_wild_species_power_plant.gd")},
	{"biome": "volcano", "dir": "volcano", "data": preload("res://data/pokemon_wild_species_volcano.gd")},
	{"biome": "graveyard", "dir": "graveyard", "data": preload("res://data/pokemon_wild_species_graveyard.gd")},
	{"biome": "dojo", "dir": "dojo", "data": preload("res://data/pokemon_wild_species_dojo.gd")},
	{"biome": "factory", "dir": "factory", "data": preload("res://data/pokemon_wild_species_factory.gd")},
	{"biome": "ruins", "dir": "ruins", "data": preload("res://data/pokemon_wild_species_ruins.gd")},
	{"biome": "wasteland", "dir": "wasteland", "data": preload("res://data/pokemon_wild_species_wasteland.gd")},
	{"biome": "abyss", "dir": "abyss", "data": preload("res://data/pokemon_wild_species_abyss.gd")},
	{"biome": "space", "dir": "space", "data": preload("res://data/pokemon_wild_species_space.gd")},
	{"biome": "construction_site", "dir": "construction_site", "data": preload("res://data/pokemon_wild_species_construction_site.gd")},
	{"biome": "jungle", "dir": "jungle", "data": preload("res://data/pokemon_wild_species_jungle.gd")},
	{"biome": "fairy_cave", "dir": "fairy_cave", "data": preload("res://data/pokemon_wild_species_fairy_cave.gd")},
	{"biome": "temple", "dir": "temple", "data": preload("res://data/pokemon_wild_species_temple.gd")},
	{"biome": "slum", "dir": "slum", "data": preload("res://data/pokemon_wild_species_slum.gd")},
	{"biome": "snowy_forest", "dir": "snowy_forest", "data": preload("res://data/pokemon_wild_species_snowy_forest.gd")},
	{"biome": "island", "dir": "island", "data": preload("res://data/pokemon_wild_species_island.gd")},
	{"biome": "laboratory", "dir": "laboratory", "data": preload("res://data/pokemon_wild_species_laboratory.gd")},
	{"biome": "end", "dir": "end", "data": preload("res://data/pokemon_wild_species_end.gd")},
]


static func module_of(species_id: int) -> Dictionary:
	_ensure()
	return MODULES[int(_by_id[species_id])] if _by_id.has(species_id) else {}


static func has(species_id: int) -> bool:
	return not module_of(species_id).is_empty()


static func row(species_id: int) -> Dictionary:
	var m := module_of(species_id)
	return {} if m.is_empty() else (m["data"].SPECIES as Dictionary)[species_id]


static func atlas_dir(species_id: int) -> String:
	var m := module_of(species_id)
	return "" if m.is_empty() else str(m["dir"])


static func atlas(species_id: int) -> Dictionary:
	var m := module_of(species_id)
	return {} if m.is_empty() else (m["data"].ATLAS as Dictionary).get(species_id, {})


static func prevolution(species_id: int) -> int:
	for m: Dictionary in MODULES:
		var pre: Dictionary = m["data"].PREVOLUTIONS
		if pre.has(species_id):
			return int(pre[species_id])
	return -1


static func ids() -> Array[int]:
	var out: Array[int] = []
	for m: Dictionary in MODULES:
		for k in (m["data"].SPECIES as Dictionary).keys():
			out.append(int(k))
	out.sort()
	return out


static var _catch: Dictionary = {}
static var _growth: Dictionary = {}
static var _learn: Dictionary = {}
static var _by_id: Dictionary = {}   # 物种 ID -> 模块下标（查得快）


static func _ensure() -> void:
	if not _by_id.is_empty():
		return
	for i in MODULES.size():
		var d = MODULES[i]["data"]
		for k in (d.SPECIES as Dictionary).keys():
			if not _by_id.has(int(k)):
				_by_id[int(k)] = i
		_catch.merge(d.CATCH_RATES)
		_growth.merge(d.GROWTH_RATES)
		_learn.merge(d.LEARNSETS)


static func catch_rates() -> Dictionary:
	_ensure()
	return _catch


static func growth_rates() -> Dictionary:
	_ensure()
	return _growth


static func learnsets() -> Dictionary:
	_ensure()
	return _learn
