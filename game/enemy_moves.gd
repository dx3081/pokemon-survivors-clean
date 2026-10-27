extends RefCounted
# 敌人的招式（用户 2026-10-16：“先把 b 做完再做敌人的技能，就是要这样子才好玩”）· 第一步：近身攻击。
#
# 招式表：原作敌人按自己当前等级，从原学习表里取“等级 1..当前等级”的最后 4 个不同的招
# （data/rogue_upstream/level_moves.json，表本身按等级升序，所以最后 4 个 = 等级最高的 4 个）。
# 第一步只用其中**会造成直接伤害、本作已接战斗**的招来近身打：
#   - 威力、属性、物理 / 特殊、命中都按那一招算；
#   - 招式附带的异常状态 / 能力变化 / 吸血 / 反伤一律不用（用户：先别给敌人强控制，“会被控死”）；
#   - 没有远程必中（起风那种）；每次还是近身挥一下；
#   - 变威力 / 条件招（抓狂、嚣张、辅助力量、精神波、击掌奇袭、电电加速…）和随机 / 复制招先不用；
#   - 一个都挑不出来就退回撞击。
# 纯数据层：招式字典由调用方传入（data/pokemon_moves.gd::MOVES），本文件只做筛选。

const SPECIES_PATH := "res://data/rogue_upstream/species.json"
const LEVEL_MOVES_PATH := "res://data/rogue_upstream/level_moves.json"
const FALLBACK := "tackle"
const MOVESET_SIZE := 4

# 不上敌人身的招式字段：这些招要靠条件 / 变威力 / 随机，第一步不做。
const BLOCKED_FIELDS := ["condition", "random_move", "copy_last", "level_damage", "power_by_hp", "power_stages", "crit_only", "hurt_boost", "friendship_power", "counter"]

static var _legendary_ids: Dictionary = {}   # 神兽（legendary / mythical / subLegendary）的物种 ID 集合
static var _id_to_name: Dictionary = {}
static var _level_moves: Dictionary = {}
static var _cache: Dictionary = {}


static func _load() -> void:
	if not _id_to_name.is_empty():
		return
	var sf := FileAccess.open(SPECIES_PATH, FileAccess.READ)
	if sf != null:
		var parsed: Variant = JSON.parse_string(sf.get_as_text())
		if parsed is Dictionary:
			for key in parsed:
				var row: Dictionary = parsed[key]
				_id_to_name[int(row["id"])] = str(key)
				if bool(row.get("legendary", false)) or bool(row.get("mythical", false)) or bool(row.get("subLegendary", false)):
					_legendary_ids[int(row["id"])] = true
	var lf := FileAccess.open(LEVEL_MOVES_PATH, FileAccess.READ)
	if lf != null:
		var lp: Variant = JSON.parse_string(lf.get_as_text())
		if lp is Dictionary:
			_level_moves = lp["species"]


# 该物种在这个等级的招式表（最后 4 个不同的招，小写 id，按学习顺序）。未知物种返回空数组。
static func moveset(species_id: int, level: int) -> Array:
	_load()
	var name: String = _id_to_name.get(species_id, "")
	if name == "" or not _level_moves.has(name):
		return []
	var learned: Array = []
	for row in _level_moves[name]:
		var lv := int(row[0])
		if lv >= 1 and lv <= level:
			var mid := str(row[1]).to_lower()
			if learned.has(mid):
				learned.erase(mid)   # 重复招保留最后一次出现的位置
			learned.append(mid)
	var start := maxi(0, learned.size() - MOVESET_SIZE)
	return learned.slice(start)


# 能上敌人身的近身伤害招（第一步）：已接战斗、物理 / 特殊、威力 > 0、不带被禁字段。
static func is_enemy_melee(move_id: String, moves: Dictionary, implemented: Array) -> bool:
	if not implemented.has(move_id) or not moves.has(move_id):
		return false
	var m: Dictionary = moves[move_id]
	var category := str(m.get("category", ""))
	if category != "物理" and category != "特殊":
		return false
	if int(m.get("power", -1)) <= 0:
		return false
	for f in BLOCKED_FIELDS:
		if m.has(f):
			return false
	return true


# 这只敌人能用的近身伤害招；挑不出来就只有撞击。按 (物种, 等级) 缓存。
static func pool(species_id: int, level: int, moves: Dictionary, implemented: Array) -> Array:
	var key := "%d_%d" % [species_id, level]
	if _cache.has(key):
		return (_cache[key] as Array).duplicate()
	var out: Array = []
	for mid in moveset(species_id, level):
		if is_enemy_melee(str(mid), moves, implemented):
			out.append(str(mid))
	if out.is_empty():
		out.append(FALLBACK)
	_cache[key] = out
	return out.duplicate()


# 把招式池拆成近身（物理，贴身挥击）和远程（特殊，发射弹药）两组。
# 用户 2026-10-17：远程招不再瞬间锁定，做成弹药；近身还是原来的挥击。
# 近身一个都没有时退回撞击（只会远程的怪贴身了也能打）。
static func split(pool_moves: Array, moves: Dictionary) -> Dictionary:
	var melee: Array = []
	var ranged: Array = []
	for mid in pool_moves:
		if moves.has(mid) and str(moves[mid].get("category", "")) == "特殊":
			ranged.append(str(mid))
		else:
			melee.append(str(mid))
	if melee.is_empty():
		melee.append(FALLBACK)
	return {"melee": melee, "ranged": ranged}


# 神兽：原作物种表里 legendary / mythical / subLegendary 任一为真（用户 2026-10-17：闪光 / 神兽要有特效和音效）。
static func is_legendary(species_id: int) -> bool:
	_load()
	return _legendary_ids.has(species_id)


# ---- 第三步：降玩家能力的招（用户 2026-10-17：“能做的就推进”；“之后再加：降玩家能力的招”）----
# 只收“变化”招里**只降目标一项能力、不带别的效果**的：攻击 / 防御 / 特攻 / 特防 / 命中。
# 速度（吐丝 / 惊吓…）会让玩家被拖慢，算轻度控制，先不上；异常状态 / 睡眠 / 麻痹 / 中毒 / 混乱一律不上（用户：别给敌人强控制）。
const DEBUFF_STAT_ABBR := {"attack": "atk", "defence": "def", "spatk": "spatk", "spdef": "spdef", "accuracy": "acc",
	"atk": "atk", "def": "def", "acc": "acc"}


# 这个招能不能当敌人的削弱招；能就返回 {"stat": "atk|def|spatk|spdef|acc", "stages": 负数}，不能返回空字典。
static func debuff_of(move_id: String, moves: Dictionary, implemented: Array) -> Dictionary:
	if not implemented.has(move_id) or not moves.has(move_id):
		return {}
	var m: Dictionary = moves[move_id]
	if str(m.get("category", "")) != "变化":
		return {}
	var effects: Array = m.get("effects", [])
	if effects.size() != 1:
		return {}
	var eff: Dictionary = effects[0]
	if str(eff.get("kind", "")) != "stat" or str(eff.get("who", "target")) == "self" or bool(eff.get("self", false)):
		return {}
	if int(eff.get("stages", 0)) >= 0:
		return {}
	var abbr := str(DEBUFF_STAT_ABBR.get(str(eff.get("stat", "")), ""))
	if abbr == "":
		return {}   # 速度等其它项不上
	return {"stat": abbr, "stages": int(eff["stages"])}


# 这只敌人能用的削弱招（按 (物种, 等级) 的最后 4 个招里挑）。
static func debuff_pool(species_id: int, level: int, moves: Dictionary, implemented: Array) -> Array:
	var out: Array = []
	for mid in moveset(species_id, level):
		if not debuff_of(str(mid), moves, implemented).is_empty():
			out.append(str(mid))
	return out
