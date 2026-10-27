extends RefCounted
# 宝可梦特性 · 纯规则层（用户 2026-10-18：“口袋妖怪特性都做了吗？……继续做特性”）。
#
#   data/rogue_upstream/abilities.json          311 个特性：简体中文名 / 说明 / 原作效果链
#   data/rogue_upstream/species_abilities.json  物种 -> 特性1 / 特性2 / 隐藏特性 / 被动特性
#   data/rogue_upstream/move_flags.json         招式标记（拳 / 咬 / 切割 / 声音 / 波动 / 反作用力 …）
# 本文件只算“规则”，不碰战斗场景：伤害倍率、属性吸收、状态免疫、能力保护、速度倍率……全是静态函数，
# 战斗接线在 main/arts.gd / combat.gd / enemies.gd（调用处都写着“特性”）。
#
# 本作是实时生存者玩法：没有换人 / 队友 / 道具栏 / 性别 / 回合，依赖这些的特性（逃跑、拾取、自然回复、友情防守、治愈之心…）
# 如实标“本作暂无效果”（RULES 里没有它们，is_active() 为假），不假装做了。

const ABILITIES_PATH := "res://data/rogue_upstream/abilities.json"
const SPECIES_PATH := "res://data/rogue_upstream/species_abilities.json"
const FLAGS_PATH := "res://data/rogue_upstream/move_flags.json"
const Evolutions := preload("res://data/pokemon_evolutions.gd")

const NONE := "NONE"
const HIDDEN_ENEMY_CHANCE := 0.05     # 野生个体抓到隐藏特性的几率（头目 / 神兽 / 闪光 = 必定隐藏特性）
const SLOT_NAMES := ["特性1", "特性2", "隐藏特性"]

static var _ab: Dictionary = {}
static var _sp: Dictionary = {}
static var _flags: Dictionary = {}
static var _loaded := false
static var _pre: Dictionary = {}     # 物种 -> 直接前进化（由进化表反查）

# 每个“已实现”的特性一条规则；字段含义见下面各函数。属性名用游戏里的汉字。
const RULES := {
	# ---- 神奇守护（用户 2026-10-21：“完全还原”）：原版 NonSuperEffectiveImmunityAbAttr——不是效果绝佳的伤害招打不伤；
	# 变化招、中毒 / 灼伤、天气、反伤照样伤。带这个特性的宝可梦最大 HP 恒为 1（原版 calculateStats：hasAbility(WONDER_GUARD) → HP = 1，融合也一样）。
	"WONDER_GUARD": {"wonder_guard": true},
	# ---- 伤害：自己出招 ----
	"ADAPTABILITY": {"stab": 2.0},
	"TECHNICIAN": {"low_power": 1.5},                 # 威力 ≤ 60 的招 ×1.5
	"IRON_FIST": {"flag": {"punch": 1.2}},
	"STRONG_JAW": {"flag": {"bite": 1.5}},
	"TOUGH_CLAWS": {"contact": 1.3},
	"RECKLESS": {"flag": {"reckless": 1.2}},
	"TRANSISTOR": {"atk_type": {"电": 1.5}},
	"ROCKY_PAYLOAD": {"atk_type": {"岩石": 1.5}},
	"PIXILATE": {"skin": ["一般", "妖精", 1.2]},
	"TINTED_LENS": {"tinted": true},
	"SNIPER": {"crit_mult": 1.5},
	"SUPER_LUCK": {"crit_stage": 1},
	"GUTS": {"guts": 1.5},
	"FLARE_BOOST": {"flare": 1.5},
	"PARENTAL_BOND": {"bonus_strike": 0.25},
	"COMPOUND_EYES": {"acc_mult": 1.3},
	"SERENE_GRACE": {"chance_mult": 2.0},
	"UNAWARE": {"ignore_stages": true},
	"SIMPLE": {"stage_mult": 2},
	# ---- 伤害：挨打 ----
	"THICK_FAT": {"def_type": {"火": 0.5, "冰": 0.5}},
	"FUR_COAT": {"def_cat": {"物理": 0.5}},
	"PRISM_ARMOR": {"super_eff": 0.75},
	"LEVITATE": {"immune": {"地面": "none"}},
	"VOLT_ABSORB": {"immune": {"电": "heal"}},
	"WATER_ABSORB": {"immune": {"水": "heal"}},
	"LIGHTNING_ROD": {"immune": {"电": "spatk"}},
	"SAP_SIPPER": {"immune": {"草": "atk"}},
	"FLASH_FIRE": {"immune": {"火": "fire_boost"}},
	"MAGIC_GUARD": {"no_indirect": true},
	"CLOUD_NINE": {"no_weather": true},
	# ---- 接触反击 ----
	"STATIC": {"contact_status": ["paralysis", 30]},
	"FLAME_BODY": {"contact_status": ["burn", 30]},
	# 孢子（用户 2026-10-23 截图）：被接触攻击 30% 让对方中毒 / 麻痹 / 睡眠（原版 EFFECT_SPORE：三选一）；草系和防尘不吃（原版）
	"EFFECT_SPORE": {"contact_status": ["effect_spore", 30]},
	"IRON_BARBS": {"contact_dmg": 8},
	# ---- 状态 / 能力保护 ----
	"LIMBER": {"status_immune": ["paralysis"]},
	"VITAL_SPIRIT": {"status_immune": ["sleep"]},
	"IMMUNITY": {"status_immune": ["poison", "toxic"]},
	"OWN_TEMPO": {"status_immune": ["confusion"], "intimidate_immune": true},
	"INNER_FOCUS": {"flinch_immune": true, "intimidate_immune": true},
	"OBLIVIOUS": {"intimidate_immune": true},
	"LEAF_GUARD": {"sun_status_immune": true},
	"SHIELD_DUST": {"shield_dust": true},
	"KEEN_EYE": {"protect": ["acc"]},
	"BIG_PECKS": {"protect": ["def"]},
	"MAGIC_BOUNCE": {"bounce": true},
	"MIRROR_ARMOR": {"bounce": true},
	# ---- 速度 / 闪避 ----
	"CHLOROPHYLL": {"speed_weather": ["sun", 2.0]},
	"SAND_RUSH": {"speed_weather": ["sand", 2.0]},
	"SURGE_SURFER": {"speed_terrain": ["electric", 2.0]},
	"QUICK_FEET": {"speed_status": 1.5},
	"SNOW_CLOAK": {"evade_weather": ["snow", 1.2]},
	"TANGLED_FEET": {"evade_confused": 2.0},
	# ---- 随时间 / 事件 ----
	"SPEED_BOOST": {"tick_stage": ["spd", 1, 6.0]},
	"MOODY": {"moody": 6.0},
	"ICE_BODY": {"weather_heal": ["snow", 16]},
	"HYDRATION": {"weather_cure": "rain"},
	"SHED_SKIN": {"shed_skin": 0.33},
	"MOXIE": {"on_kill": ["atk", 1]},
	"INTIMIDATE": {"intimidate": true},
	"DEFIANT": {"on_drop": ["atk", 2]},
	"RATTLED": {"rattled": true},
	"ANGER_POINT": {"on_crit": ["atk", 6]},
	"STEADFAST": {"on_flinch": ["spd", 1]},
	"PRESSURE": {"pressure": 1.5},   # 原版 PP 消耗翻倍 → 本作敌人三种出手冷却都 ×1.5（用户 2026-10-22 定）
	"OVERCOAT": {"overcoat": true},   # 防尘：沙暴 / 冰雹不扣血、粉末招无效（原版 BlockWeatherDamageAttr + 粉末免疫）
	"SYNCHRONIZE": {"synchronize": true},
	"PSYCHIC_SURGE": {"surge": "psychic"},
	"ELECTRIC_SURGE": {"surge": "electric"},
	"GRASSY_SURGE": {"surge": "grassy"},
	"MISTY_SURGE": {"surge": "misty"},
}

# 本作没有对应系统（换人 / 队友 / 道具 / 性别）的特性，说明后面加这句。
const NO_EFFECT_NOTE := "（本作暂无效果）"


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_ab = _read(ABILITIES_PATH)
	_sp = _read(SPECIES_PATH)
	_flags = _read(FLAGS_PATH)
	for from in Evolutions.EVOLUTIONS:
		for e: Dictionary in Evolutions.EVOLUTIONS[from]:
			if not _pre.has(int(e["to"])):
				_pre[int(e["to"])] = int(from)


static func prevolution_of(species_id: int) -> int:
	_load()
	return int(_pre.get(species_id, -1))


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


# ================= 数据查询 =================
static func is_real(key: String) -> bool:
	_load()
	return key != "" and key != NONE and _ab.has(key)


static func name_of(key: String) -> String:
	_load()
	return str((_ab.get(key, {}) as Dictionary).get("name", "")) if is_real(key) else ""


static func key_of_name(zh: String) -> String:
	_load()
	for k in _ab:
		if str((_ab[k] as Dictionary).get("name", "")) == zh:
			return str(k)
	return ""


static func desc_of(key: String) -> String:
	_load()
	return str((_ab.get(key, {}) as Dictionary).get("desc", "")) if is_real(key) else ""


# 本作是否真的有这个特性的效果。
static func is_active(key: String) -> bool:
	return RULES.has(key)


static func rule(key: String) -> Dictionary:
	return RULES.get(key, {})


# [特性1, 特性2, 隐藏] 的枚举名；没有的是 "NONE"。
static func species_slots(species_id: int) -> Array:
	_load()
	var r: Dictionary = _sp.get(str(species_id), {})
	if r.is_empty():
		return [NONE, NONE, NONE]
	return [str(r.get("a1", NONE)), str(r.get("a2", NONE)), str(r.get("hidden", NONE))]


# 某栏位的特性：特性2 / 隐藏为空时回退到特性1（原作 abilityIndex 的口径）。
static func slot_ability(species_id: int, slot: int) -> String:
	var s := species_slots(species_id)
	var key: String = s[clampi(slot, 0, 2)]
	if key == NONE:
		key = s[0]
	return key if key != NONE else ""


# 起始页可选的栏位：[{slot, key, name, desc, hidden}]；特性2 / 隐藏为空的不列，特性重复的只列第一次。
static func slot_choices(species_id: int) -> Array:
	var s := species_slots(species_id)
	var out: Array = []
	var seen: Array = []
	for i in 3:
		var key: String = s[i]
		if key == NONE or seen.has(key):
			continue
		seen.append(key)
		out.append({"slot": i, "key": key, "name": name_of(key), "desc": desc_of(key), "hidden": i == 2})
	return out


# 被动特性按起始种登记，进化后沿用：顺着进化链回到起始种再查。
static func passive_of(species_id: int) -> String:
	_load()
	var sid := species_id
	var guard := 0
	while guard < 8:
		var r: Dictionary = _sp.get(str(sid), {})
		var p := str(r.get("passive", NONE))
		if p != NONE:
			return p
		var pre := prevolution_of(sid)
		if pre <= 0 or pre == sid:
			break
		sid = pre
		guard += 1
	return ""


static func root_of(species_id: int) -> int:
	var sid := species_id
	var guard := 0
	while guard < 8:
		var pre := prevolution_of(sid)
		if pre <= 0 or pre == sid:
			break
		sid = pre
		guard += 1
	return sid


# 野生个体的特性：特殊个体（头目 / 神兽 / 闪光）必定隐藏特性（没有就回退）；其余按栏位随机，隐藏特性 5%。
static func roll_enemy(species_id: int, special: bool, rng_a: float, rng_b: float) -> Dictionary:
	var s := species_slots(species_id)
	var slot := 0
	if special and s[2] != NONE:
		slot = 2
	elif rng_a < HIDDEN_ENEMY_CHANCE and s[2] != NONE:
		slot = 2
	elif s[1] != NONE and rng_b < 0.5:
		slot = 1
	return {"slot": slot, "key": slot_ability(species_id, slot)}


# 被动：头目 / 神兽带被动，普通野怪不带（原作野怪也没有被动）。
static func enemy_passive(species_id: int, special: bool) -> String:
	return passive_of(species_id) if special else ""


# ================= 招式标记 =================
static func move_has_flag(move_id: String, flag: String) -> bool:
	_load()
	return (_flags.get(flag, []) as Array).has(move_id)


# ================= 伤害倍率 =================
# 出招方的特性对这一招伤害的总倍率。ctx：move_id / move_type / category / power / eff / contact / stab（本系）/ status（出招方有主要异常）/ burned。
static func attack_mult(key: String, ctx: Dictionary) -> float:
	var r := rule(key)
	if r.is_empty():
		return 1.0
	var m := 1.0
	var mt := str(ctx.get("move_type", ""))
	if r.has("stab") and bool(ctx.get("stab", false)):
		m *= float(r["stab"]) / 1.5   # 适应力：本系 1.5 -> 2.0
	if r.has("low_power") and int(ctx.get("power", 100)) <= 60:
		m *= float(r["low_power"])
	if r.has("flag"):
		for f in r["flag"]:
			if move_has_flag(str(ctx.get("move_id", "")), str(f)):
				m *= float(r["flag"][f])
	if r.has("contact") and bool(ctx.get("contact", false)):
		m *= float(r["contact"])
	if r.has("atk_type") and (r["atk_type"] as Dictionary).has(mt):
		m *= float(r["atk_type"][mt])
	if r.has("skin") and mt == str(r["skin"][0]):
		m *= float(r["skin"][2])   # 一般招威力 ×1.2（属性本身不改写，克制仍按一般算）
	if r.has("tinted") and float(ctx.get("eff", 1.0)) < 1.0 and float(ctx.get("eff", 1.0)) > 0.0:
		m *= 2.0
	if r.has("guts") and bool(ctx.get("status", false)) and str(ctx.get("category", "")) == "物理":
		m *= float(r["guts"])
		if bool(ctx.get("burned", false)):
			m *= 2.0   # 毅力无视灼伤的攻击减半
	if r.has("flare") and bool(ctx.get("burned", false)) and str(ctx.get("category", "")) == "特殊":
		m *= float(r["flare"])
	if r.has("bonus_strike"):
		m *= 1.0 + float(r["bonus_strike"])
	return m


# 挨打方的特性对这一击的倍率。ctx：move_type / category / eff。
static func defend_mult(key: String, ctx: Dictionary) -> float:
	var r := rule(key)
	if r.is_empty():
		return 1.0
	var m := 1.0
	var mt := str(ctx.get("move_type", ""))
	if r.has("def_type") and (r["def_type"] as Dictionary).has(mt):
		m *= float(r["def_type"][mt])
	if r.has("def_cat") and (r["def_cat"] as Dictionary).has(str(ctx.get("category", ""))):
		m *= float(r["def_cat"][str(ctx.get("category", ""))])
	if r.has("super_eff") and float(ctx.get("eff", 1.0)) > 1.0:
		m *= float(r["super_eff"])
	return m


# 属性吸收 / 免疫：返回 ""（不吸收）/ "none"（单纯免疫）/ "heal" / "spatk" / "atk" / "fire_boost"。
static func wonder_guard(key: String) -> bool:
	return bool(rule(key).get("wonder_guard", false))


static func absorb_kind(key: String, move_type: String) -> String:
	var r := rule(key)
	if r.has("immune") and (r["immune"] as Dictionary).has(move_type):
		return str(r["immune"][move_type])
	return ""


static func crit_stage_bonus(key: String) -> int:
	return int(rule(key).get("crit_stage", 0))


static func crit_mult(key: String) -> float:
	return float(rule(key).get("crit_mult", 1.0))


static func accuracy_mult(key: String) -> float:
	return float(rule(key).get("acc_mult", 1.0))


# 对手的闪避（雪隐 / 蹒跚）让我方命中变成多少倍。
static func evade_divisor(key: String, weather: String, confused: bool) -> float:
	var r := rule(key)
	var d := 1.0
	if r.has("evade_weather") and weather == str(r["evade_weather"][0]):
		d *= float(r["evade_weather"][1])
	if r.has("evade_confused") and confused:
		d *= float(r["evade_confused"])
	return d


static func chance_mult(key: String) -> float:
	return float(rule(key).get("chance_mult", 1.0))


static func ignores_stages(key: String) -> bool:
	return bool(rule(key).get("ignore_stages", false))


static func stage_multiplier(key: String) -> int:
	return int(rule(key).get("stage_mult", 1))


# ================= 状态 / 能力保护 =================
# status：paralysis / burn / poison / toxic / sleep / freeze / confusion。
static func blocks_status(key: String, status: String, weather: String) -> bool:
	var r := rule(key)
	if r.has("status_immune") and (r["status_immune"] as Array).has(status):
		return true
	if r.has("sun_status_immune") and weather == "sun":
		return true
	return false


static func blocks_intimidate(key: String) -> bool:
	return bool(rule(key).get("intimidate_immune", false))


static func blocks_flinch(key: String) -> bool:
	return bool(rule(key).get("flinch_immune", false))


static func protects_stat(key: String, stat: String) -> bool:
	return rule(key).has("protect") and (rule(key)["protect"] as Array).has(stat)


static func ignores_secondary(key: String) -> bool:
	return bool(rule(key).get("shield_dust", false))


static func bounces(key: String) -> bool:
	return bool(rule(key).get("bounce", false))


static func blocks_indirect(key: String) -> bool:
	return bool(rule(key).get("no_indirect", false))


static func suppresses_weather(key: String) -> bool:
	return bool(rule(key).get("no_weather", false))


# ================= 速度 =================
static func speed_mult(key: String, weather: String, terrain: String, has_status: bool) -> float:
	var r := rule(key)
	var m := 1.0
	if r.has("speed_weather") and weather == str(r["speed_weather"][0]):
		m *= float(r["speed_weather"][1])
	if r.has("speed_terrain") and terrain == str(r["speed_terrain"][0]):
		m *= float(r["speed_terrain"][1])
	if r.has("speed_status") and has_status:
		m *= float(r["speed_status"])
	return m


# ================= 接触反击 =================
# 返回 {status, chance, dmg_div}；没有就是空字典。
static func contact_effect(key: String) -> Dictionary:
	var r := rule(key)
	var out := {}
	if r.has("contact_status"):
		out["status"] = str(r["contact_status"][0])
		out["chance"] = int(r["contact_status"][1])
	if r.has("contact_dmg"):
		out["dmg_div"] = int(r["contact_dmg"])
	return out


# ================= 简述 =================
# 起始页 / 信息框用的一行说明：特性名 + 说明 + 是否有效果。
static func summary(key: String) -> String:
	if not is_real(key):
		return ""
	var s := "%s：%s" % [name_of(key), desc_of(key)]
	if not is_active(key):
		s += NO_EFFECT_NOTE
	return s
