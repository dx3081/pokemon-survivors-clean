extends RefCounted
# 携带道具（用户 2026-10-20：照原版先做一批）。效果、叠加上限、稀有度照原版 src/modifier/modifier.ts + modifier-type.ts（提交 c16a3bbf）：
#   吃剩的东西 LEFTOVERS   每回合回最大 HP 的 1/16 × 个数，最多 4（ROGUE 档）
#   贝壳之铃   SHELL_BELL  打出伤害的 1/8 × 个数回血，最多 4（ROGUE）
#   气势头带   FOCUS_BAND  每个 10% 几率挨致命一击时留 1 血，最多 5（ROGUE）
#   王者之证   KINGS_ROCK  打中时每个 10% 几率让对方畏缩，最多 3（ROGUE）
#   焦点镜     SCOPE_LENS  会心等级 +1，最多 1（ROGUE）
#   广角镜     WIDE_LENS   命中 +5 × 个数，最多 3（ULTRA）
#   安抚之铃   SOOTHE_BELL 好感获得 ×(1 + 0.5 × 个数)，最多 3（ROGUE）
#   属性强化   TYPE:<属性> 该属性招式威力 ×(1 + 0.2 × 个数)，最多 99（ULTRA；原版木炭 / 神秘水滴…）
# 本作改动：吃剩的东西不按原版每回合 1/16（换成秒太猛，叠 4 个等于不会死），改成吸血鬼幸存者式慢回血（用户 2026-10-20“太变态了”）：
#   每秒回最大血量的 LEFTOVERS_RATE × 个数，攒够 1 点才回（满 4 个约 1 分钟回满）。
# 第二批（用户 2026-10-20“剩下的特定携带道具开始做”，照原版 modifier.ts / modifier-type.ts c16a3bbf）：
#   进化奇石 EVIOLITE    还能进化时防御 / 特防 ×1.5，最多 1（ULTRA）
#   大葱 LEEK            大葱鸭 / 葱游兵 会心等级 +2，最多 1（ULTRA）
#   电气球 LIGHT_BALL    皮卡丘 攻击 / 特攻 ×2；粗骨头 THICK_CLUB 卡拉卡拉 / 嘎啦嘎啦 攻击 ×2；
#   金属粉 METAL_POWDER  百变怪 防御 ×2（都是最多 1，ULTRA；速度粉在本作速度不管用，没做）
#   幸运蛋 LUCKY_EGG     经验 ×(1 + 0.4 × 个数)，最多 99（ROGUE）
#   复活种子 REVIVER_SEED 倒下时以一半血复活并解除异常，用掉（买的那个真的没了），最多 1（ULTRA）
#   白色香草 WHITE_HERB  能力被降时全部恢复到 0，用掉一个，最多 2（ULTRA）
#   心之水滴 SOUL_DEW    性格效果加强：加的那项 +0.1 × 个数、减的那项 -0.1 × 个数，最多 10（ROGUE）
#   剧毒宝珠 / 火焰宝珠  没异常时自己中剧毒 / 灼伤（配毅力 / 飞毛腿 / 神奇鳞片 / 受热激升用），最多 1（ULTRA）；
#                        只有这一系有这些特性才在商店出现（原版也是条件出现）。
#   金蛋 GOLDEN_EGG      经验 ×(1 + 1.0 × 个数)，最多 99（原版大师档，本作定 1000 点一个）
#   黄金拳头 GOLDEN_PUNCH 原版打出伤害的 50% × 个数变成钱；本作没钱 → 变成局内点数（用户 2026-10-20“我们有点数啊”）：
#                        每个让击杀点数 +20%，最多 5（ULTRA）。原来是“打出伤害 × 0.005 × 个数”，后期伤害爆炸一局刷 88 万点，
#                        2026-10-25 用户让我封：改成直接按击杀点数加成（main/state.gd _points_award_kill）
#   穿透石板 STATUS_PIERCE（本作自己加的，用户 2026-10-21：“哪怕敌人免疫也可以强行施展”）：你给敌人上异常时无视免疫——
#                        属性免疫（毒 / 钢不中毒、电不麻痹、火不灼伤、冰不冰冻）、特性免疫（柔软、不眠、我行我素…）、
#                        草系不吃粉末招；敌人已经有异常的照旧上不了第二个。最多 1，Rogue 档 300 点。
# 没做：紧缠钩爪 / 接力棒 / 迷你黑洞（偷道具 / 换人，本作没有）。
# 局外商店“单只培养”按进化系买（和镜片一样，一系共用），价格按原稀有度档：ULTRA 100 点、ROGUE 300 点 / 个。

const PP := preload("res://game/pokemon_pp.gd")

const PREFIX := "HELD:"
# PP 提升剂（原版 PP_UP，究极档）：按招买，"PP_UP:<招式 id>"，每招最多 3 个，每个 +20% PP（冷却跟着缩短，规则 game/pokemon_pp.gd）。
const PP_UP_PREFIX := "PP_UP:"
const LEFTOVERS_SECONDS := 1.0
const LEFTOVERS_RATE := 0.004
const TIER_PRICE := {"ULTRA": 100, "ROGUE": 300, "MASTER": 1000}

const ITEMS := {
	"LEFTOVERS": {"zh": "吃剩的东西", "icon": "leftovers", "tier": "ROGUE", "max": 4, "desc": "每秒慢慢回血：最大血量的 0.4%（每个）"},
	"SHELL_BELL": {"zh": "贝壳之铃", "icon": "shell_bell", "tier": "ROGUE", "max": 4, "desc": "打出伤害的 1/8 回血（每个）"},
	"FOCUS_BAND": {"zh": "气势头带", "icon": "focus_band", "tier": "ROGUE", "max": 5, "desc": "挨致命一击时 10% 几率留 1 血（每个）"},
	"KINGS_ROCK": {"zh": "王者之证", "icon": "kings_rock", "tier": "ROGUE", "max": 3, "desc": "打中时 10% 几率让对方畏缩（每个）"},
	"SCOPE_LENS": {"zh": "焦点镜", "icon": "scope_lens", "tier": "ROGUE", "max": 1, "desc": "会心等级 +1"},
	"WIDE_LENS": {"zh": "广角镜", "icon": "wide_lens", "tier": "ULTRA", "max": 3, "desc": "招式命中 +5（每个）"},
	"SOOTHE_BELL": {"zh": "安抚之铃", "icon": "soothe_bell", "tier": "ROGUE", "max": 3, "desc": "好感获得 +50%（每个），物种糖果来得更快"},
	"EVIOLITE": {"zh": "进化奇石", "icon": "eviolite", "tier": "ULTRA", "max": 1, "desc": "还能进化的时候防御、特防 ×1.5（进化到底就没用了）"},
	"LEEK": {"zh": "大葱", "icon": "leek", "tier": "ULTRA", "max": 1, "desc": "大葱鸭 / 葱游兵专用：会心等级 +2"},
	"LIGHT_BALL": {"zh": "电气球", "icon": "light_ball", "tier": "ULTRA", "max": 1, "desc": "皮卡丘专用：攻击、特攻 ×2"},
	"THICK_CLUB": {"zh": "粗骨头", "icon": "thick_club", "tier": "ULTRA", "max": 1, "desc": "卡拉卡拉 / 嘎啦嘎啦专用：攻击 ×2"},
	"METAL_POWDER": {"zh": "金属粉", "icon": "metal_powder", "tier": "ULTRA", "max": 1, "desc": "百变怪专用：防御 ×2"},
	"LUCKY_EGG": {"zh": "幸运蛋", "icon": "lucky_egg", "tier": "ROGUE", "max": 99, "desc": "经验 +40%（每个）"},
	"GOLDEN_EGG": {"zh": "金蛋", "icon": "golden_egg", "tier": "MASTER", "max": 99, "desc": "经验 +100%（每个；和幸运蛋分开乘）"},
	"GOLDEN_PUNCH": {"zh": "黄金拳头", "icon": "golden_punch", "tier": "ULTRA", "max": 5, "desc": "击杀点数 +20%（每个，最多 5 个）"},
	"REVIVER_SEED": {"zh": "复活种子", "icon": "reviver_seed", "tier": "ULTRA", "max": 1, "desc": "倒下时以一半血复活、解除异常；用掉就没了，要再买"},
	"WHITE_HERB": {"zh": "白色香草", "icon": "white_herb", "tier": "ULTRA", "max": 2, "desc": "能力被降低时全部恢复，用掉一个"},
	"SOUL_DEW": {"zh": "心之水滴", "icon": "soul_dew", "tier": "ROGUE", "max": 10, "desc": "性格效果加强：加的那项多 +10%、减的那项多 -10%（每个）"},
	"STATUS_PIERCE": {"zh": "穿透石板", "icon": "toxic_plate", "tier": "ROGUE", "max": 1, "desc": "你给敌人上异常时无视免疫：毒 / 钢也能中毒、电系也能麻痹、草系也吃粉末招、不眠也能睡着（本作自己加的道具）"},
	"TOXIC_ORB": {"zh": "剧毒宝珠", "icon": "toxic_orb", "tier": "ULTRA", "max": 1, "desc": "没异常时自己中剧毒（配毅力 / 飞毛腿 / 神奇鳞片用）"},
	"MOVE_SLOT": {"zh": "招式扩展器", "icon": "ability_capsule", "tier": "MASTER", "max": 2, "desc": "多一个招式槽（每个）：1 个带 5 招、2 个带 6 招（本作自己加的道具，用户 2026-10-24）"},
	"FLAME_ORB": {"zh": "火焰宝珠", "icon": "flame_orb", "tier": "ULTRA", "max": 1, "desc": "没异常时自己灼伤（配毅力 / 飞毛腿 / 受热激升用）"},
}
const ALWAYS_EXTRA := ["MOVE_SLOT", "LUCKY_EGG", "GOLDEN_EGG", "GOLDEN_PUNCH", "REVIVER_SEED", "WHITE_HERB", "SOUL_DEW", "STATUS_PIERCE"]
const GOLDEN_EGG_BOOST := 1.0
const GOLDEN_PUNCH_RATE := 0.005   # 旧算法（按伤害），已不用
const GOLDEN_PUNCH_KILL_BONUS := 0.2   # 每个黄金拳头：击杀点数 +20%
# 专用道具：哪些物种能用（原版 SpeciesStatBooster / SpeciesCritBooster 的物种表；大葱鸭的伽勒尔形态同编号）
const SPECIES_ONLY := {"LEEK": [83, 865], "LIGHT_BALL": [25], "THICK_CLUB": [104, 105], "METAL_POWDER": [132]}
const TOXIC_ORB_ABILITIES := ["GUTS", "QUICK_FEET", "MARVEL_SCALE", "POISON_HEAL", "TOXIC_BOOST"]
const FLAME_ORB_ABILITIES := ["GUTS", "QUICK_FEET", "MARVEL_SCALE", "FLARE_BOOST"]
const LUCKY_EGG_BOOST := 0.4
const SOUL_DEW_STEP := 0.1
const EVIOLITE_MULT := 1.5
const SPECIES_STAT_MULT := 2.0
const BASIC_ORDER := ["LEFTOVERS", "SHELL_BELL", "FOCUS_BAND", "KINGS_ROCK", "SCOPE_LENS", "WIDE_LENS", "SOOTHE_BELL"]

# 属性强化道具：属性（汉字）-> [道具名, 图标]（原版 AttackTypeBoosterItem 对应表）
const TYPE_BOOSTERS := {
	"一般": ["丝绸围巾", "silk_scarf"], "格斗": ["黑带", "black_belt"], "飞行": ["锐利鸟嘴", "sharp_beak"],
	"毒": ["毒针", "poison_barb"], "地面": ["柔软沙子", "soft_sand"], "岩石": ["硬石头", "hard_stone"],
	"虫": ["银粉", "silver_powder"], "幽灵": ["诅咒之符", "spell_tag"], "钢": ["金属膜", "metal_coat"],
	"火": ["木炭", "charcoal"], "水": ["神秘水滴", "mystic_water"], "草": ["奇迹种子", "miracle_seed"],
	"电": ["磁铁", "magnet"], "超能力": ["弯曲的汤匙", "twisted_spoon"], "冰": ["不融冰", "never_melt_ice"],
	"龙": ["龙之牙", "dragon_fang"], "恶": ["黑色眼镜", "black_glasses"], "妖精": ["妖精之羽", "fairy_feather"],
}
const TYPE_BOOSTER_MAX := 99


static func product_id(item: String) -> String:
	return PREFIX + item


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX) and is_item(source_id.trim_prefix(PREFIX))


static func item_of(source_id: String) -> String:
	return source_id.trim_prefix(PREFIX) if is_product(source_id) else ""


static func type_item(type_zh: String) -> String:
	return "TYPE:" + type_zh


static func pp_up_item(move_id: String) -> String:
	return PP_UP_PREFIX + move_id


static func is_pp_up(item: String) -> bool:
	return item.begins_with(PP_UP_PREFIX) and PP.base_pp(item.trim_prefix(PP_UP_PREFIX)) > 0


static func pp_up_move(item: String) -> String:
	return item.trim_prefix(PP_UP_PREFIX) if is_pp_up(item) else ""


static func is_item(item: String) -> bool:
	return ITEMS.has(item) or (item.begins_with("TYPE:") and TYPE_BOOSTERS.has(item.trim_prefix("TYPE:"))) or is_pp_up(item)


static func max_stacks(item: String) -> int:
	if ITEMS.has(item):
		return int(ITEMS[item]["max"])
	if is_pp_up(item):
		return PP.MAX_UPS
	return TYPE_BOOSTER_MAX if is_item(item) else 0


static func price(item: String) -> int:
	if ITEMS.has(item):
		return int(TIER_PRICE[str(ITEMS[item]["tier"])])
	return int(TIER_PRICE["ULTRA"]) if is_item(item) else -1


static func name_of(item: String) -> String:
	if ITEMS.has(item):
		return str(ITEMS[item]["zh"])
	if is_pp_up(item):
		return "PP提升剂·%s" % str(PP.PokemonMoves.MOVES[pp_up_move(item)].get("name", ""))
	if is_item(item):
		return str(TYPE_BOOSTERS[item.trim_prefix("TYPE:")][0])
	return item


static func icon_of(item: String) -> String:
	if ITEMS.has(item):
		return str(ITEMS[item]["icon"])
	if is_pp_up(item):
		return "pp_up"
	if is_item(item):
		return str(TYPE_BOOSTERS[item.trim_prefix("TYPE:")][1])
	return ""


static func desc_of(item: String, have: int = 0) -> String:
	if ITEMS.has(item):
		return str(ITEMS[item]["desc"])
	if is_pp_up(item):
		var mid := pp_up_move(item)
		var s := "这招 PP +20%%（每个），PP 越高冷却越短：现在 PP %d、冷却 %.1f 秒" % [PP.move_pp(mid, have), PP.move_cd(mid, have)]
		if have < PP.MAX_UPS:
			s += "，再买一个 PP %d、冷却 %.1f 秒" % [PP.move_pp(mid, have + 1), PP.move_cd(mid, have + 1)]
		return s
	if is_item(item):
		return "%s属性招式威力 +20%%（每个）" % item.trim_prefix("TYPE:")
	return ""


# 这只宠物在商店里能买哪些：七件基础的 + 它自己属性的强化道具（原版生成器按队伍招式属性出，这里按本系属性）
# + 第二批通用的 + 这一系用得上的专用道具 / 宝珠（species_id = 选中的那只；0 = 不加第二批的条件项）。
static func shop_items(types: Array, species_id: int = 0) -> Array:
	var out: Array = BASIC_ORDER.duplicate()
	for t in types:
		if TYPE_BOOSTERS.has(str(t)):
			out.append(type_item(str(t)))
	var Shop = load("res://game/pokemon_shop.gd")
	for it: String in ALWAYS_EXTRA:
		if not Shop.exp_banned(it):   # 幸运蛋 / 金蛋：经验加成已禁（2026-10-25）
			out.append(it)
	if species_id > 0:
		var AB = load("res://game/pokemon_abilities.gd")
		var Evo = load("res://game/pokemon_evolution.gd")
		var root: int = AB.root_of(species_id)
		# 只卖选中这只用得上的（2026-10-22 审查：巴大蝶买进化奇石、雷丘买电气球都是白买）：
		# 进化奇石要它自己还能进化；专用道具要它自己或它以后会进化成的那只在表里（皮丘开局买电气球，进化成皮卡丘就生效）。
		if not Evo.entries(species_id).is_empty():
			out.append("EVIOLITE")
		for it: String in SPECIES_ONLY:
			for s in SPECIES_ONLY[it]:
				if _is_self_or_ancestor(species_id, int(s), AB):
					out.append(it)
					break
		var ab_keys: Array = AB.species_slots(species_id).duplicate()
		ab_keys.append(AB.passive_of(root))
		var toxic := false
		var flame := false
		for a in ab_keys:
			toxic = toxic or TOXIC_ORB_ABILITIES.has(str(a))
			flame = flame or FLAME_ORB_ABILITIES.has(str(a))
		if toxic:
			out.append("TOXIC_ORB")
		if flame:
			out.append("FLAME_ORB")
	return out


# 专用道具对这只（当前形态）管不管用。
static func species_ok(item: String, species_id: int) -> bool:
	return (SPECIES_ONLY.get(item, []) as Array).has(int(species_id))


# 心之水滴：性格倍率往远离 1 的方向推（原版 PokemonNatureWeightModifier），最低 0.1。
static func soul_dew_nature(mult: Array, n: int) -> Array:
	var out: Array = mult.duplicate()
	if n <= 0:
		return out
	for i in out.size():
		var m := float(out[i])
		if m > 1.0:
			out[i] = m + SOUL_DEW_STEP * n
		elif m < 1.0:
			out[i] = maxf(0.1, m - SOUL_DEW_STEP * n)
	return out


static func lucky_egg_mult(n: int) -> float:
	return 1.0 + LUCKY_EGG_BOOST * maxi(0, n)


# ===== 效果数字（运行时用） =====
static func leftovers_heal(max_hp: float, n: int) -> float:
	return max_hp * LEFTOVERS_RATE * n if n > 0 else 0.0


static func shell_bell_heal(damage_dealt: float, n: int) -> float:
	return floorf(damage_dealt / 8.0) * n if n > 0 else 0.0


static func focus_band_survives(n: int, roll10: int) -> bool:
	return n > 0 and roll10 < n   # 原版 randSeedInt(10) < 个数


static func kings_rock_flinches(n: int, roll10: int) -> bool:
	return n > 0 and roll10 < n


static func type_power_mult(n: int) -> float:
	return 1.0 + 0.2 * n


static func friendship_mult(n: int) -> float:
	return 1.0 + 0.5 * n


# a 是不是 b 自己或者 b 的进化前（沿着 prevolution 往上找）。
static func _is_self_or_ancestor(a: int, b: int, AB) -> bool:
	var cur := b
	for i in 8:
		if cur == a:
			return true
		cur = int(AB.prevolution_of(cur))
		if cur <= 0:
			return false
	return false
