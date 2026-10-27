extends RefCounted
#
# 本文件只做三件事，全部只读、无状态、无注册框架：
#   1. 按**现 84 物种原表**（data/pokemon_starter_species.gd，唯一事实）算某物种 form0 的
#      本作开局初始招：取原表等级 <= startLevel 的行（含 0 级进化招），保原顺序，先前 4 再去重。
#      这是源 starter UI 默认前 4 / 去重流程，只把源硬编码 `<= 5` 边界换成已定的 startLevel 1。
#      不补 9 级虫咬、不补低等级 / 蛋招、不把未实现招偷换成 Tackle，也不先过滤未实现再从后面凑 4。
#   2. 判定“准备好”：这份初始招**全部**有真实施放（data/pokemon_moves.gd::IMPLEMENTED），
#      且至少一招能造成伤害（物理 / 特殊）。否则已捕获也显示“招式准备中”、禁止出发。
#   3. 给城镇 / 出发 / 战斗查同一份准确物种资料（中文名 / 属性 / form0 六项 / 成长率 / 精灵图类型）。
#      资料优先全国图鉴（<=1025），图鉴没有的地区 ID（如 8128 PALDEA_TAUROS）走
#      data/pokemon_wild_species.gd 的准确 form0 资料，不用绿毛虫六维兜底、不合并 128。
#
#   + data/pokemon_starter_species.gd（84 原 DP 表 / 5 份 Ur 覆盖）+ data/pokemon_moves.gd（14 实现）。
# 适配说明见 game/POKEMON_STARTERS_SOURCE.md。

const Species := preload("res://data/pokemon_starter_species.gd")
const Moves := preload("res://data/pokemon_moves.gd")
const Pokedex := preload("res://data/pokedex.gd")
const WildSpecies := preload("res://data/pokemon_wild_species.gd")

# 本作既有开局等级（保留 1 级，不擅自换原 Rogue 5 级）。源 UI 的 `<=5` 边界只换成这里。
const START_LEVEL := 1
# 本段 default form0；不做形态切换 / 形态独立存档。
const FORM_INDEX := 0
# 源默认最多前 4 个初始招。
const MAX_INITIAL := 4
# 内置三形态（characters/caterpie.gd::SPECIES）；其余可上场物种走平原原图集。
const BUILTIN_SPECIES: Array[int] = [10, 11, 12]
# 默认可选物种：无需捕获即可出发（本作既有主角）。
const DEFAULT_SPECIES_ID := 10
const FALLBACK_DAMAGE_MOVE := "tackle"   # 开局没有能打人的招时补这个（铁甲蛹、鲤鱼王…）


# ================= 起始招式（源默认前 4 / 去重）=================

# 某物种某形态在 level 及以下的原表初始招 id（最多 4 个）。
# 顺序：原表顺序取 level<=level 的行（含 level 0 进化招）→ 先前 4 → 再去重（保首次出现）。
# 未知物种返回空数组；不改动 / 不返回 const 表本身的引用。
static func initial_moves(species_id: int, form_index := FORM_INDEX, level := START_LEVEL) -> Array:
	var out: Array = []
	if not Species.has_species(species_id):
		return out
	var rows := Species.learnset_rows(species_id, form_index)
	var picked: Array = []
	for row: Array in rows:
		if int(row[0]) > level:
			continue
		picked.append(str(row[1]))
		if picked.size() >= MAX_INITIAL:
			break
	for move_id in picked:
		if not out.has(move_id):
			out.append(move_id)
	# 本作补丁（用户 2026-10-24：“铁甲蛹只会变硬这种就给他加个撞击算了”）：开局招里没有能打人的（已开放的）招，
	# 就补一个撞击，这样每只抓到的宝可梦都能当首发。招满 4 个就顶掉最后一个。
	var playable_damage := false
	for move_id in out:
		if Moves.is_implemented(str(move_id)) and has_damage_move([move_id]):
			playable_damage = true
	if not playable_damage and not out.is_empty() and not out.has(FALLBACK_DAMAGE_MOVE) and species_id != DITTO_ID:
		if out.size() >= MAX_INITIAL:
			out.pop_back()
		out.append(FALLBACK_DAMAGE_MOVE)
	return out


# 这份初始招里没有本作释放实现的招（原表事实，供显示 / 门槛 / 检查；不冒充已会）。
static func missing_initial_moves(species_id: int, form_index := FORM_INDEX, level := START_LEVEL) -> Array:
	var out: Array = []
	for move_id in initial_moves(species_id, form_index, level):
		if not Moves.is_implemented(str(move_id)):
			out.append(move_id)
	return out


# 是否至少一招能造成直接伤害（物理 / 特殊）。变化招（power -1）不算。
static func has_damage_move(moves: Array) -> bool:
	for move_id in moves:
		var row: Dictionary = Moves.MOVES.get(str(move_id), {})
		if row.is_empty():
			continue
		var category := str(row.get("category", ""))
		if category == "物理" or category == "特殊":
			return true
	return false


# 这份初始招里**已有真实释放**的招（会真的带进战斗的那些，保持原表顺序）。
# 封印规则（用户 2026-10-16 定）：没有释放实现的招式一律“封印”——宠物照常开放，
# 封印招只在技能页显示并标“未开放”，不入招式槽、不会放出来；开局四槽遇到封印招直接跳过，不顺延补位。
static func playable_initial_moves(species_id: int, form_index := FORM_INDEX, level := START_LEVEL) -> Array:
	var out: Array = []
	for move_id in initial_moves(species_id, form_index, level):
		if Moves.is_implemented(str(move_id)):
			out.append(move_id)
	return out


# 这份初始招里被封印的招（= 原表前 4 里没有释放实现的招），技能页用来标“未开放”。
static func sealed_initial_moves(species_id: int, form_index := FORM_INDEX, level := START_LEVEL) -> Array:
	return missing_initial_moves(species_id, form_index, level)


# 该准确 source_species_id 是否“准备好”上场：
#   - 必须在现 84 原表内（未知 / 84 外一律不开放）；
#   - 封印招不算缺招：只看真正会带进战斗的招里是否至少有一招能造成伤害。
# 2026-10-16 起（用户定“宠物照常开放、招式封印”）取代旧门槛“4 个初始招全部有实现”。
# 不能当首发的原因（能当就返回 ""）。选宠页 / 出发拒绝 / AI 接口共用（用户 2026-10-24：铁甲蛹灰着却不说为什么）。
static func not_ready_reason(species_id: int) -> String:
	if is_ready(species_id):
		return ""
	if not Species.has_species(species_id):
		return "这只本作还没做好，暂时只能在图鉴里看"
	var names: Array = []
	for m in playable_initial_moves(species_id):
		names.append(str(Moves.MOVES[str(m)]["name"]) if Moves.MOVES.has(str(m)) else str(m))
	return "开局会的招里没有能打人的（%s），当首发打不动怪，所以暂时不能出发；先用它的进化前 / 进化后形态吧" % ("、".join(names) if not names.is_empty() else "一个招都没有")


static func is_ready(species_id: int) -> bool:
	if not Species.has_species(species_id):
		return false
	if species_id == DITTO_ID:
		return true   # 百变怪：开局选“变成谁”，招式取被选物种的，所以自己不需要有可用招
	return has_damage_move(playable_initial_moves(species_id))


# ================= 百变怪（用户 2026-10-16 定，取代“战斗里自动放变身招”）=================
# 选百变怪开局多一步：选它变成谁（已开放地图——现在是平原——里的任意物种），开局就定、整局不变、下一局可重选。
# 变成后：外观 / 属性 / 开局招 / 升级学的招都照被选物种；六维种族值 = 被选物种 × 0.8（六项各自向下取整、最低 1；
# 理由：百变怪不用先捕捉就能变任何平原物种，打折是省掉解锁的代价；试玩觉得强了只调 DITTO_STAT_MULT）；
# 等级和经验曲线仍是百变怪自己的（MEDIUM_FAST）；不进化；没有“变身”这一招（原 TRANSFORM 永久不做）。
const DITTO_ID := 132
const DITTO_STAT_MULT := 0.8


# 百变怪能变成的物种：平原野生物种（data/pokemon_wild_species.gd）里已准备好的（有可用的开局伤害招），去掉百变怪自己；升序。
static func ditto_targets() -> Array[int]:
	var out: Array[int] = []
	for id in Species.species_ids():
		if int(id) != DITTO_ID and WildSpecies.has_species(int(id)) and is_ready(int(id)):
			out.append(int(id))
	return out


static func is_ditto_target(species_id: int) -> bool:
	return ditto_targets().has(species_id)


# 变成某物种时的六维种族值：被选物种 × DITTO_STAT_MULT，向下取整，最低 1。
static func ditto_base_stats(target_id: int) -> Array:
	var prof := profile(target_id)
	var out: Array = []
	for v in prof.get("base_stats", []):
		out.append(maxi(1, int(floor(float(v) * DITTO_STAT_MULT))))
	return out


# 旧门槛（2026-10-16 封印规则之前）：4 个初始招必须全部有真实施放，且至少一招能造成伤害。
static func is_ready_strict(species_id: int) -> bool:
	if not Species.has_species(species_id):
		return false
	var moves := initial_moves(species_id)
	if moves.is_empty() or not missing_initial_moves(species_id).is_empty():
		return false
	return has_damage_move(moves)


static func ready_ids_strict() -> Array[int]:
	var out: Array[int] = []
	for species_id in Species.species_ids():
		if is_ready_strict(species_id):
			out.append(species_id)
	return out


# 当前准备好的全部准确 ID（84 表升序）。
static func ready_ids() -> Array[int]:
	var out: Array[int] = []
	for species_id in Species.species_ids():
		if is_ready(species_id):
			out.append(species_id)
	return out


# ================= 准确物种资料 =================

static func is_known(species_id: int) -> bool:
	return Species.has_species(species_id)


# 某物种 form0 的准确资料（城镇 A/B/C、出发、战斗都取这里，避免显示 / 实玩两套数字）：
#   id / form_index / name（中文）/ source_name（原大写下划线）/ types / base_stats（[HP,ATK,DEF,SPATK,SPDEF,SPD]）
#   / growth_rate / sprite（"builtin" 内置三形态、"wild" 平原原图集、"none" 无图）
#   / initial_moves / missing_initial / ready。
# 不暴露 base_exp：本段选角不用它，而图鉴内物种没有同一处准确原值；宁可不给，也不把 0 冒充资料。
# 未知 / 84 外返回 {}。返回的数组都是副本，调用方改不到 const 表。
static func profile(species_id: int, form_index := FORM_INDEX) -> Dictionary:
	if not Species.has_species(species_id):
		return {}
	var name := ""
	var types: Array = []
	var base_stats: Array = []
	var dex := Pokedex.entry(species_id)
	var dex_stats: Array = dex.get("stats", []) if not dex.is_empty() else []
	if dex_stats.size() >= 6:
		name = str(dex.get("name", ""))
		types = (dex.get("types", []) as Array).duplicate()
		base_stats = dex_stats.duplicate()
	elif WildSpecies.has_species(species_id):
		# 全国图鉴 1025 范围外的地区 ID（如 8128）：用当前 WildSpecies 准确 form0 资料，
		# 不回退到绿毛虫六维、也不合并到 128。
		var row: Dictionary = WildSpecies.row_of(species_id)
		var form := WildSpecies.form_at(species_id, form_index)
		name = str(row.get("display", row.get("name", "")))
		types = (form.get("types", []) as Array).duplicate()
		base_stats = (form.get("stats", []) as Array).duplicate()
	else:
		return {}
	if base_stats.size() < 6:
		return {}
	var sprite := "none"
	if BUILTIN_SPECIES.has(species_id):
		sprite = "builtin"
	elif WildSpecies.has_species(species_id):
		sprite = "wild"
	return {
		"id": species_id,
		"form_index": form_index,
		"name": name,
		"source_name": Species.species_name(species_id),
		"types": types,
		"base_stats": base_stats,
		"growth_rate": Species.growth_rate(species_id),
		"sprite": sprite,
		"initial_moves": initial_moves(species_id, form_index),
		"missing_initial": missing_initial_moves(species_id, form_index),
		"sealed_initial": sealed_initial_moves(species_id, form_index),
		"playable_initial": playable_initial_moves(species_id, form_index),
		"ready": is_ready(species_id),
	}
