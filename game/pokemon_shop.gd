extends RefCounted
#
# 本文件不建通用经济 / 背包 / 交易框架，也不碰 UI / 存档落盘（落盘在 game/pokemon_points.gd）：
#   1. 价格唯一表：按原 tier 五档 [10, 30, 100, 300, 1000]（COMMON..MASTER，索引 = 原 tier）。
#        EXP_CHARM       原 ULTRA(2) = 100 点
#        SUPER_EXP_CHARM 原 ROGUE(3) = 300 点
#        HEALING_CHARM   原 MASTER(4) = 1000 点
#        POTION / SUPER_POTION         原 COMMON(0) = 10 点
#        HYPER_POTION / MAX_POTION / FULL_RESTORE 原 GREAT(1) = 30 点
#   2. 原效果：
#      - 两种经验护符同第 2 段：boostPercent 25 / 60，maxStack 99 / 30；
#        apply: value = floor(value * (1 + stacks * boostPercent/100))，每种各 floor 一次，
#        按**首次获得顺序**依次执行（同种追加层数不换位置）。
#      - HEALING_CHARM 照原 HealingBoosterModifier：multiplier=1.1、maxStack=5，
#        组合 = 1+(1.1-1)*stacks（每层 +10%）。只作用于**一般治疗**与**药的固定回复分支**。
#          points  = 20 / 50 / 200 / 0 / 0
#          percent = 10 / 25 / 50 / 100 / 100
#          r   = floor(points * healingMultiplier)
#          pct = floor(percent*.01*maxHp)
#          amount = max(ceil(max(pct, r)), 1)，最终 HP 不超过 max
#        治愈护符只乘固定分支 r，**不乘 max 后的总量、也不乘百分比分支**。
#        FULL_RESTORE 额外 resetStatus：**只清主要异常，不清混乱**。
#
# 边界：后端只信商品 ID 重新查表（`purchase()` / `restore_amount()` / 球的 price/pack 只收 source_id），
# 不接受 UI 传入的价格 / 层数 / 数值；本段之外的商品（糖果 / 营养 / TM / 进化 / 携带 /
# EXP_SHARE / EXP_BALANCE / CANDY_JAR / RARER_CANDY 等）一律拒买。
# 五种伤药只在局内、只作用于当前上场那只；治愈护符只在城镇、对所有宝可梦与新局持久生效。
# 捕获第 2 段五球（POKEBALL/GREAT_BALL/ULTRA_BALL/ROGUE_BALL/MASTER_BALL）只在局内买，
# 库存上限 99、只在本局内存，由 main/state.gd 持有，不进 game/pokemon_points.gd 的持久档。

const Catalog := preload("res://data/pokemon_shop_catalog.gd")

const TIER_POINT_COSTS := [10, 30, 100, 300, 1000]

# 与 data/pokemon_shop_catalog.gd 原 enum 对齐（本文件用字面量避免 const 跨脚本初始化限制）。
const TIER_COMMON := 0
const TIER_GREAT := 1
const TIER_ULTRA := 2
const TIER_ROGUE := 3
const TIER_MASTER := 4

const EXP_CHARM := "EXP_CHARM"
const SUPER_EXP_CHARM := "SUPER_EXP_CHARM"
const HEALING_CHARM := "HEALING_CHARM"
const POTION := "POTION"
const SUPER_POTION := "SUPER_POTION"
const HYPER_POTION := "HYPER_POTION"
const MAX_POTION := "MAX_POTION"
const FULL_RESTORE := "FULL_RESTORE"
const FULL_HEAL := "FULL_HEAL"
# 局内药店只摆这两样（用户 2026-10-24：同价被完全盖过的合并掉、东西少一点）：伤药同价不如好伤药，
# 厉害伤药 / 全满药同价不如全复药，万灵药不如木子果。后台规则照旧（老检查还能买）。
const SHOWN_MEDICINES := ["SUPER_POTION", "FULL_RESTORE"]   # 万灵药：只解除主要异常，不回血（2026-10-18 用户：“局内商店没有卖异常解除”）

# 捕获第 2 段五种可售球（源 PLAYER 奖励池优惠档 0..4；LUXURY=5 不卖）。
# source_id 与 data/pokemon_shop_catalog.gd 的原记录同名；本文件不复制目录，只按 ID 查表。
const POKEBALL := "POKEBALL"
const GREAT_BALL := "GREAT_BALL"
const ULTRA_BALL := "ULTRA_BALL"
const ROGUE_BALL := "ROGUE_BALL"
const MASTER_BALL := "MASTER_BALL"

# 商品种类：全体经验护符 / 全体治愈护符 / 局内伤药 / 局内精灵球。落盘只认 ID，不认分类。
const KIND_EXP := "exp_charm"
const KIND_GLOBAL := "global_charm"   # 第二批全体加成（用户 2026-10-20）：闪耀护符 / 特性护符 / 树果袋 / 糖果罐 / 地图 / 护身金币 / 学习装置
const KIND_HEAL := "heal_charm"
const KIND_MEDICINE := "medicine"
const KIND_BALL := "ball"
const KIND_STAT := "stat_drink"   # 营养饮料：局外按只、按项买，每颗这一项努力值 +10（原 BASE_STAT_BOOSTER，优秀档）
const STAT_NAMES := ["HP", "攻击", "防御", "特攻", "特防", "速度"]
const KIND_CANDY := "candy"   # 神奇糖果：局外按只买，开局 +1 级 / 颗（原 RARE_CANDY，普通档）
# 每只宝可梦最多买多少颗（本作自定的上限，和球的 99 一致；原作糖果本身没有上限，因为本作已去掉等级上限）。
const CANDY_CAP := 99

# 球枚举顺序（照源 PokeballType 0..4）与库存上限；每份数量照原工厂 count（前四球 5、大师球 1）。
const BALL_IDS := [POKEBALL, GREAT_BALL, ULTRA_BALL, ROGUE_BALL, MASTER_BALL]
const BALL_CAP := 99
# 原 new run 初始库存：普通球 5、其余 0（球只在本局内存，不进持久档）。
const INITIAL_BALL_COUNTS := [5, 0, 0, 0, 0]

# 唯一可购买表：source_id -> 原效果参数 + 原 tier。
# boost_percent / max_stacks 来自已验收的 effects fixture；points / percent / heal_status 来自
const PRODUCTS := {
	EXP_CHARM: {"kind": KIND_EXP, "boost_percent": 25, "max_stacks": 99, "tier": TIER_ULTRA, "zh": "经验护符"},
	SUPER_EXP_CHARM: {"kind": KIND_EXP, "boost_percent": 60, "max_stacks": 30, "tier": TIER_ROGUE, "zh": "超级经验护符"},
	HEALING_CHARM: {"kind": KIND_HEAL, "per_stack": 1.1, "max_stacks": 5, "tier": TIER_MASTER, "zh": "治愈护符"},
	# 第二批全体加成（原 tier / 上限照原版；效果在本作的对应处，见 GLOBAL_DESC）。
	"SHINY_CHARM": {"kind": KIND_GLOBAL, "max_stacks": 20, "tier": TIER_MASTER, "zh": "闪耀护符"},
	"ABILITY_CHARM": {"kind": KIND_GLOBAL, "max_stacks": 4, "tier": TIER_ROGUE, "zh": "特性护符"},
	"BERRY_POUCH": {"kind": KIND_GLOBAL, "max_stacks": 3, "tier": TIER_ROGUE, "zh": "树果袋"},
	"CANDY_JAR": {"kind": KIND_GLOBAL, "max_stacks": 99, "tier": TIER_ULTRA, "zh": "糖果罐"},
	"MAP": {"kind": KIND_GLOBAL, "max_stacks": 1, "tier": TIER_GREAT, "zh": "地图"},
	"AMULET_COIN": {"kind": KIND_GLOBAL, "max_stacks": 10, "tier": TIER_ULTRA, "zh": "护身金币"},   # 用户 2026-10-23：接替设置里的点数滑块，上限 5 → 10（买满 ×3）
	"EXP_SHARE": {"kind": KIND_GLOBAL, "max_stacks": 5, "tier": TIER_ULTRA, "zh": "学习装置"},
	POTION: {"kind": KIND_MEDICINE, "points": 20, "percent": 10, "heal_status": false, "tier": TIER_COMMON, "zh": "伤药"},
	SUPER_POTION: {"kind": KIND_MEDICINE, "points": 50, "percent": 25, "heal_status": false, "tier": TIER_COMMON, "zh": "好伤药"},
	HYPER_POTION: {"kind": KIND_MEDICINE, "points": 200, "percent": 50, "heal_status": false, "tier": TIER_GREAT, "zh": "厉害伤药"},
	MAX_POTION: {"kind": KIND_MEDICINE, "points": 0, "percent": 100, "heal_status": false, "tier": TIER_GREAT, "zh": "全满药"},
	FULL_RESTORE: {"kind": KIND_MEDICINE, "points": 0, "percent": 100, "heal_status": true, "tier": TIER_GREAT, "zh": "全复药"},
	FULL_HEAL: {"kind": KIND_MEDICINE, "points": 0, "percent": 0, "heal_status": true, "status_only": true, "tier": TIER_GREAT, "zh": "万灵药"},
	# 捕获第 2 段：五球原包数 / 原 tier（档位索引就是点价索引，0..4 -> 10/30/100/300/1000）。
	POKEBALL: {"kind": KIND_BALL, "ball_type": 0, "pack": 5, "tier": TIER_COMMON, "zh": "精灵球"},
	GREAT_BALL: {"kind": KIND_BALL, "ball_type": 1, "pack": 5, "tier": TIER_GREAT, "zh": "超级球"},
	ULTRA_BALL: {"kind": KIND_BALL, "ball_type": 2, "pack": 5, "tier": TIER_ULTRA, "zh": "高级球"},
	ROGUE_BALL: {"kind": KIND_BALL, "ball_type": 3, "pack": 5, "tier": TIER_ROGUE, "zh": "Rogue 球"},
	MASTER_BALL: {"kind": KIND_BALL, "ball_type": 4, "pack": 1, "tier": TIER_MASTER, "zh": "大师球"},
	# 局外成长：神奇糖果（原 RARE_CANDY：普通档，每颗 +1 级）；价格取普通档点价。高级神奇糖果（金色那档）用户定直接去掉。
	"RARE_CANDY": {"kind": KIND_CANDY, "levels": 1, "tier": TIER_COMMON, "zh": "神奇糖果"},
	# 局外成长：营养饮料（原 BASE_STAT_BOOSTER 是随机一项 +10%；用户定的是每颗某一项努力值 +10，所以做成六项各一个商品）。
	"STAT_DRINK_0": {"kind": KIND_STAT, "stat": 0, "tier": TIER_GREAT, "zh": "营养饮料·HP"},
	"STAT_DRINK_1": {"kind": KIND_STAT, "stat": 1, "tier": TIER_GREAT, "zh": "营养饮料·攻击"},
	"STAT_DRINK_2": {"kind": KIND_STAT, "stat": 2, "tier": TIER_GREAT, "zh": "营养饮料·防御"},
	"STAT_DRINK_3": {"kind": KIND_STAT, "stat": 3, "tier": TIER_GREAT, "zh": "营养饮料·特攻"},
	"STAT_DRINK_4": {"kind": KIND_STAT, "stat": 4, "tier": TIER_GREAT, "zh": "营养饮料·特防"},
	"STAT_DRINK_5": {"kind": KIND_STAT, "stat": 5, "tier": TIER_GREAT, "zh": "营养饮料·速度"},
}

# 购买 / 使用结果状态（调用方按它展示明确中文提示）。
const ST_PURCHASED := "purchased"
const ST_NOT_PURCHASABLE := "not_purchasable"
const ST_AT_MAX := "at_max"
const ST_INSUFFICIENT := "insufficient_points"
const ST_PENDING_INCOME := "pending_income"
const ST_CORRUPT_LOCKED := "corrupt_locked"
const ST_SAVE_FAILED := "save_failed"
const ST_WRONG_PLACE := "wrong_place"      # 地点 / 战斗状态不允许（局内药在城镇、全体护符在战斗）
const ST_NO_EFFECT := "no_effect"          # 满 HP 的普通药 / 满 HP 只有混乱的全复药 / 0 HP


static func product_ids() -> Array:
	var out: Array = []
	for id in PRODUCTS:
		out.append(str(id))
	out.sort()
	return out


static func is_known(source_id: String) -> bool:
	return PRODUCTS.has(source_id)


# 本段所有上架商品都可买；真正的地点 / 状态校验在 main/state.gd 的购买路由里。
static func is_purchasable(source_id: String) -> bool:
	return PRODUCTS.has(source_id) and not exp_banned(source_id)


# 14 分钟 +258 级，把中后期整段跳过）。商店 / 补给站不卖，已经买过的也不生效（main/combat.gd _gain_xp）。
# exp_boosts_on = true 回到原样（测原版经验公式的老检查用）。
const EXP_BANNED := ["EXP_CHARM", "SUPER_EXP_CHARM", "EXP_SHARE", "LUCKY_EGG", "GOLDEN_EGG"]
static var exp_boosts_on := false


static func exp_banned(source_id: String) -> bool:
	if exp_boosts_on:
		return false
	for b: String in EXP_BANNED:
		if source_id == b or source_id.ends_with(":" + b):
			return true
	return false


static func _kind(source_id: String) -> String:
	if not PRODUCTS.has(source_id):
		return ""
	return str(PRODUCTS[source_id]["kind"])


# 城镇「全体加成」：两种原经验护符 + 原治愈护符 + 第二批（KIND_GLOBAL）。
static func is_town_charm(source_id: String) -> bool:
	var k := _kind(source_id)
	return k == KIND_EXP or k == KIND_HEAL or k == KIND_GLOBAL


static func is_global_charm(source_id: String) -> bool:
	return _kind(source_id) == KIND_GLOBAL


# 第二批全体加成：商店显示的一句话（原版效果 → 本作怎么用）。
const GLOBAL_ORDER := ["EXP_SHARE", "CANDY_JAR", "AMULET_COIN", "BERRY_POUCH", "MAP", "ABILITY_CHARM", "SHINY_CHARM"]
const GLOBAL_DESC := {
	"SHINY_CHARM": "野生宝可梦出闪光的几率每层 +40%（20 层 ×9，约 110 只出一只；本作改：原版 1 层就 ×8，我们一局刷的怪多得多）。越买越贵：第 1 层 300 点，每层多 100",
	"ABILITY_CHARM": "野生宝可梦带隐藏特性的几率 ×2^(1+层数)（原版特性护符；1 层 ×4）",
	"BERRY_POUCH": "每层 1/3 几率吃树果不消耗（原版树果袋）",
	"CANDY_JAR": "每颗神奇糖果多加 1 级（每层；原版糖果罐让神奇糖果多升级）",
	"MAP": "撤离时能去的地区全部列出来，不用掷（原版地图）",
	"AMULET_COIN": "击杀点数 / 金珠 +20%（每层，最多 10 层 = ×3；局里点左上角图标可以少用几层）",
	"EXP_SHARE": "经验 +20%（每层；原版学习装置给全队分经验，本作不做队伍，直接加给上场那只）",
}


static func global_desc(source_id: String) -> String:
	return str(GLOBAL_DESC.get(source_id, ""))


# 闪耀护符：几率倍率；特性护符：隐藏特性几率倍率；护身金币 / 学习装置：每层 +20%。
# 闪耀护符（用户 2026-10-24：“弄成 10、20 层，每层就一丢丢”）：每层在基础几率上加 40%，最多 20 层 ×9。
const SHINY_CHARM_MAX := 20
const SHINY_CHARM_STEP := 0.4


static func shiny_charm_mult(n: int) -> float:
	return 1.0 + SHINY_CHARM_STEP * float(clampi(n, 0, SHINY_CHARM_MAX))


static func ability_charm_mult(n: int) -> float:
	return pow(2.0, 1 + n) if n > 0 else 1.0


# 局内「药」：五种原 HP 恢复药，只作用于当前上场那只、购买即用。
static func is_stat_drink(source_id: String) -> bool:
	return _kind(source_id) == KIND_STAT


static func stat_index(source_id: String) -> int:
	if not is_stat_drink(source_id):
		return -1
	return int(PRODUCTS[source_id]["stat"])


static func is_town_candy(source_id: String) -> bool:
	return _kind(source_id) == KIND_CANDY


static func is_run_medicine(source_id: String) -> bool:
	return _kind(source_id) == KIND_MEDICINE


static func is_exp_charm(source_id: String) -> bool:
	return _kind(source_id) == KIND_EXP


static func is_healing_charm(source_id: String) -> bool:
	return _kind(source_id) == KIND_HEAL


# 局内「球」：捕获第 2 段五种可售球，购买后进本局内存库存（不写钱包、不占护符层数）。
static func is_run_ball(source_id: String) -> bool:
	return _kind(source_id) == KIND_BALL


# 球枚举 0..4（照源 PokeballType 前五档）；非法返回 -1。
static func ball_type(source_id: String) -> int:
	if not is_run_ball(source_id):
		return -1
	return int(PRODUCTS[source_id]["ball_type"])


# 每份数量：前四球 5、大师球 1（照原 AddPokeballModifier 工厂 count）。
static func ball_pack(source_id: String) -> int:
	if not is_run_ball(source_id):
		return 0
	return int(PRODUCTS[source_id]["pack"])


static func is_ball_type(ball_type_id: int) -> bool:
	return ball_type_id >= 0 and ball_type_id < BALL_IDS.size()


static func ball_source_id(ball_type_id: int) -> String:
	if not is_ball_type(ball_type_id):
		return ""
	return str(BALL_IDS[ball_type_id])


# 原 new run 初始库存（普通球 5 / 其余 0）；每次 start_run 重置回这份值。
static func initial_ball_counts() -> Array[int]:
	var out: Array[int] = []
	for value in INITIAL_BALL_COUNTS:
		out.append(int(value))
	return out


static func boost_percent(source_id: String) -> int:
	if not is_exp_charm(source_id):
		return 0
	return int(PRODUCTS[source_id]["boost_percent"])


static func max_stacks(source_id: String) -> int:
	if not PRODUCTS.has(source_id):
		return 0
	return int(PRODUCTS[source_id].get("max_stacks", 0))


# 只有治愈护符有 per_stack 原始倍率；其余返回 0（调用方不用它）。
static func per_stack(source_id: String) -> float:
	if not is_healing_charm(source_id):
		return 0.0
	return float(PRODUCTS[source_id]["per_stack"])


# 原 HealingBoosterModifier.apply：value *= 1+(multiplier-1)*stackCount()。
# multiplier = 1.1，所以组合 = 1 + 0.1*stacks；stacks 只来自已校验的存档层数。
static func healing_multiplier(stacks: int) -> float:
	var n := clampi(stacks, 0, 5)
	return 1.0 + (per_stack(HEALING_CHARM) - 1.0) * float(n)


static func medicine_points(source_id: String) -> int:
	if not is_run_medicine(source_id):
		return -1
	return int(PRODUCTS[source_id]["points"])


static func medicine_percent(source_id: String) -> int:
	if not is_run_medicine(source_id):
		return -1
	return int(PRODUCTS[source_id]["percent"])


# 万灵药这种只解异常、不回血的药。
static func medicine_status_only(source_id: String) -> bool:
	if not is_run_medicine(source_id):
		return false
	return bool(PRODUCTS[source_id].get("status_only", false))


static func medicine_heals_status(source_id: String) -> bool:
	if not is_run_medicine(source_id):
		return false
	return bool(PRODUCTS[source_id]["heal_status"])


# 原 PokemonHpRestoreModifier.apply 的纯计算（不 eval 源表达式）：
#   r   = floor(points * healingMultiplier)
#   pct = floor(percent*.01*maxHp)
#   amount = max(ceil(max(pct, r)), 1)
# 只算「回复多少」，是否封顶到 max 由调用方按当前 HP 做。非药返回 0。
static func restore_amount(source_id: String, max_hp: float, heal_mult: float) -> int:
	if not is_run_medicine(source_id):
		return 0
	var mult := maxf(0.0, heal_mult)
	var r := floorf(float(medicine_points(source_id)) * mult)
	var pct := floorf(float(medicine_percent(source_id)) * 0.01 * maxf(0.0, max_hp))
	return maxi(int(ceilf(maxf(pct, r))), 1)


# 只信 ID 重新查表：未知 / 未开放 ID 返回 -1，绝不接受 UI 传来的价格。
static func price(source_id: String) -> int:
	if not PRODUCTS.has(source_id):
		return -1
	var tier := int(PRODUCTS[source_id]["tier"])
	if tier < 0 or tier >= TIER_POINT_COSTS.size():
		return -1
	return int(TIER_POINT_COSTS[tier])


# 越买越贵（用户 2026-10-22：“10 点确实有点少”）：神奇糖果 / 糖果罐每买满 10 个，单价翻一倍。
# 糖果：1–10 颗 10 点、11–20 颗 20 点、21–30 颗 40 点…；糖果罐：1–10 层 100 点、11–20 层 200 点…
# 商品 → 每买满几个单价翻倍（护身金币每 5 层，用户 2026-10-23）
const ESCALATING := {"RARE_CANDY": 10, "CANDY_JAR": 10, "AMULET_COIN": 5}
# 线性涨价：商品 → [第 1 个的价格, 之后每个多多少]（闪耀护符 300、400、500…，20 层一共约 2.5 万点）
const LINEAR_PRICE := {"SHINY_CHARM": [300, 100]}


# owned = 已经买了几个；返回买下一个的价格。
static func price_at(source_id: String, owned: int) -> int:
	var p := price(source_id)
	if p >= 0 and LINEAR_PRICE.has(source_id):
		return int(LINEAR_PRICE[source_id][0]) + int(LINEAR_PRICE[source_id][1]) * maxi(owned, 0)
	if p < 0 or not ESCALATING.has(source_id):
		return p
	return p * int(pow(2.0, float(maxi(owned, 0) / int(ESCALATING[source_id]))))


static func tier_of(source_id: String) -> int:
	if not PRODUCTS.has(source_id):
		return -1
	return int(PRODUCTS[source_id]["tier"])


static func display_name(source_id: String) -> String:
	if not PRODUCTS.has(source_id):
		return str(source_id)
	return str(PRODUCTS[source_id]["zh"])


# 原效果纯计算：order 是不同种护符的**首次获得顺序**；stacks 是 id -> 已买层数。
# 只有两种经验护符参与；治愈护符即使排在 order 里也跳过（不吃经验、不报缺字段）。
# 每种 floor(value*(1+stacks*percent/100))，按 order 依次执行（同种多买不换位置）。
# 没有可作用护符时原样返回 floor(base)（原 XP 行为完全保留）。
static func apply_exp(base: float, order: Array, stacks: Dictionary) -> float:
	var value := floorf(base)
	for id_v in order:
		var id := str(id_v)
		if not is_exp_charm(id):
			continue
		var n := int(stacks.get(id, 0))
		if n <= 0:
			continue
		var pct := float(boost_percent(id))
		value = floorf(value * (1.0 + float(n) * pct / 100.0))
	return value


# 校验磁盘上读回的层数 / 顺序是否可信（坏数据要锁定原档，不能静默丢效果后覆盖）。
# 返回 "" 表示合法；否则返回错误码。治愈护符也是合法 ID（maxStacks=5）。
static func owned_error(order_v, stacks_v) -> String:
	if not (order_v is Array):
		return "charms_order_type"
	if not (stacks_v is Dictionary):
		return "charms_stacks_type"
	var order: Array = order_v
	var stacks: Dictionary = stacks_v
	var seen := {}
	for i in order.size():
		var id_v = order[i]
		if typeof(id_v) != TYPE_STRING:
			return "charms_order_entry"
		var id := str(id_v)
		if seen.has(id):
			return "charms_order_duplicate"
		seen[id] = true
		if not PRODUCTS.has(id):
			return "charms_unknown_id"
		# 球只在本局内存；混进护符层数 / 顺序一律锁定，不许当成护符保存。
		if _kind(id) == KIND_BALL:
			return "charms_ball_id"
	if stacks.size() != order.size():
		return "charms_stack_mismatch"
	for key_v in stacks:
		if typeof(key_v) != TYPE_STRING:
			return "charms_stack_key"
		var key := str(key_v)
		if not seen.has(key):
			return "charms_stack_unknown"
		var n := _stack_int(stacks[key_v])
		if n <= 0:
			return "charms_stack_value"
		if n > max_stacks(key):
			return "charms_stack_over_cap"
	return ""


# 把合法层数规范化成 int（ConfigFile 里手写的 3.0 也归一成 3）；
# 不合法返回 -1。只做判断，不改任何文件。
static func _stack_int(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var f := float(value)
		if f == floorf(f):
			return int(f)
	return -1


# 城镇全体护符的可信购买入口：只收商品 ID，价格 / 上限 / 效果全部重新查表；
# 真实扣款 + 加层由钱包（game/pokemon_points.gd::purchase_product）用同一份完整快照原子完成。
# 五种局内伤药不走这里（它们由 main/state.gd 路由到 wallet.spend + 精确治疗）。
# 返回 {"ok": bool, "status": String, "source_id": String, "price": int,
#       "balance": int, "run_points": int, "stacks": Dictionary, "order": Array}。
static func purchase(wallet, source_id: String) -> Dictionary:
	var sid := str(source_id)
	var base := {
		"ok": false, "status": ST_NOT_PURCHASABLE, "source_id": sid, "price": -1,
		"balance": 0, "run_points": 0, "stacks": {}, "order": [],
	}
	if wallet == null:
		return base
	base["balance"] = int(wallet.balance)
	base["run_points"] = int(wallet.run_points)
	base["stacks"] = wallet.charm_stacks.duplicate()
	base["order"] = wallet.charm_order.duplicate()
	if not is_town_charm(sid):
		return base
	var p := price_at(sid, int(wallet.charm_stacks.get(sid, 0)))   # 糖果罐越买越贵
	var cap := max_stacks(sid)
	base["price"] = p
	var result: Dictionary = wallet.purchase_product(sid, p, cap)
	base["ok"] = bool(result.get("ok", false))
	base["status"] = str(result.get("status", ST_SAVE_FAILED))
	base["balance"] = int(wallet.balance)
	base["run_points"] = int(wallet.run_points)
	base["stacks"] = wallet.charm_stacks.duplicate()
	base["order"] = wallet.charm_order.duplicate()
	return base
