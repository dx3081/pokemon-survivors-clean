extends RefCounted
# 各地区的野生物种池（2026-10-17，用户：“地图改开始做了”）：运行时把 data/rogue_upstream/biome_pools.json
#   tier(0..8) -> time(-1 全天 / 0 黎明 / 1 白天 / 2 黄昏 / 3 夜晚) -> 条目数组；
#   条目 = 物种 ID（int）或 { 门槛等级(int): [候选物种 ID…] }。
# 平原继续用 data/pokemon_plains.gd 里已对账的那份（pool("plains") 直接返回它），其它地区读 JSON。

const Plains := preload("res://data/pokemon_plains.gd")
const WildSpecies := preload("res://data/pokemon_wild_species.gd")
const JSON_PATH := "res://data/rogue_upstream/biome_pools.json"

const TIER_KEYS := {"COMMON": 0, "UNCOMMON": 1, "RARE": 2, "SUPER_RARE": 3, "ULTRA_RARE": 4,
	"BOSS": 5, "BOSS_RARE": 6, "BOSS_SUPER_RARE": 7, "BOSS_ULTRA_RARE": 8}
const TIME_KEYS := {"DAWN": 0, "DAY": 1, "DUSK": 2, "NIGHT": 3, "ALL": -1}

static var _raw: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if not _raw.is_empty():
		return
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_raw = (parsed as Dictionary)["biomes"]


# 某地区的池（biome_id 是 data/biomes.gd 里的小写 id，如 "grass"）；未知地区返回空字典。
static func pool(biome_id: String) -> Dictionary:
	if biome_id == "plains":
		return Plains.PLAINS
	if _cache.has(biome_id):
		return _cache[biome_id]
	_load()
	var key := biome_id.to_upper()
	if not _raw.has(key):
		return {}
	var out := {}
	for tier_name: String in (_raw[key] as Dictionary):
		var tier: int = int(TIER_KEYS[tier_name])
		var by_time := {}
		for time_name: String in (_raw[key][tier_name] as Dictionary):
			var entries: Array = []
			for e in (_raw[key][tier_name][time_name] as Array):
				if e is Dictionary:
					var conv := {}
					for th in (e as Dictionary):
						var ids: Array = []
						for sid in (e[th] as Array):
							if WildSpecies.has_species(int(sid)):   # 本作没资料 / 没图集的物种（源码里就没有图的）不进池
								ids.append(int(sid))
						if not ids.is_empty():
							conv[int(th)] = ids
					if not conv.is_empty():
						entries.append(conv)
				elif WildSpecies.has_species(int(e)):
					entries.append(int(e))
			by_time[int(TIME_KEYS[time_name])] = entries
		out[tier] = by_time
	_cache[biome_id] = out
	return out


# 该地区池里出现的全部物种 ID（含进化门槛里的），升序去重；接线 / 检查用。
static func species_in(biome_id: String) -> Array[int]:
	var seen := {}
	for tier in pool(biome_id):
		for time in pool(biome_id)[tier]:
			for e in pool(biome_id)[tier][time]:
				if e is Dictionary:
					for th in e:
						for sid in e[th]:
							seen[int(sid)] = true
				else:
					seen[int(e)] = true
	var out: Array[int] = []
	for k in seen.keys():
		out.append(int(k))
	out.sort()
	return out
