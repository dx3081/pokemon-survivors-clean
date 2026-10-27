extends RefCounted
# 物种糖果（原版 starterData.candyCount）和被动特性解锁（用户 2026-10-20：照原版“达成条件给糖果”，和升开局等级的神奇糖果不是一种）。
# 糖果按起始种（进化链最前面那只）记，全照原作，数据来自 data/rogue_upstream/starter_costs.json：
#   - 抓到一只：+1；闪光 ×5 / ×10 / ×20（金 / 蓝 / 红，原 5 × 2^variant）；头目再 ×2（原 game-data.ts setPokemonCaught）。
#     本作没有“一场一场”，按真实每过一分钟算一场（和局内亲密度同一个节拍）。上限按起始种费用：20 / 40 / 60 / 100 / 140 / 200 / 280 / 450 / 450 / 600。
#   - 解锁被动：按费用花 40 / 40 / 35 / 30 / 25 / 20 / 15 / 10 / 10 / 10 颗（原 starterCandyCosts[].passive）。
#   - 解锁后可以在选宠页关掉（原版“禁用被动”）。

const DATA_PATH := "res://data/rogue_upstream/starter_costs.json"
const FRIENDSHIP_PER_WAVE := 4

static var _data: Dictionary = {}


static func _ensure() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_data = parsed
	if _data.is_empty():
		_data = {"costs": {}, "passive_candy": [40, 40, 35, 30, 25, 20, 15, 10, 10, 10], "friendship_cap": [20, 40, 60, 100, 140, 200, 280, 450, 450, 600]}


# 起始种费用 1..10；表里没有的按 1 算（只会是本作自己加的东西）。
static func cost_of(root_id: int) -> int:
	_ensure()
	return clampi(int((_data["costs"] as Dictionary).get(str(root_id), 1)), 1, 10)


static func passive_cost(root_id: int) -> int:
	_ensure()
	return int((_data["passive_candy"] as Array)[cost_of(root_id) - 1])


static func friendship_cap(root_id: int) -> int:
	_ensure()
	return int((_data["friendship_cap"] as Array)[cost_of(root_id) - 1])


# 抓到一只给几颗：shiny_variant -1 普通 / 0 金 / 1 蓝 / 2 红。
static func catch_candy(shiny_variant: int, boss: bool) -> int:
	var n := 1 if shiny_variant < 0 else 5 * (1 << clampi(shiny_variant, 0, 2))
	return n * (2 if boss else 1)
