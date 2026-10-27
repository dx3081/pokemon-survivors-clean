extends RefCounted
# 地区之间怎么走（原版 biomeLinks，src/data/balance/biomes.ts，提交 c16a3bbf；照抄，不改）。
# 用户 2026-10-20：“5 分钟之后可以撤离去下一个地图，然后按照原游戏解锁地图”。
# 每项 [下一个地区, n]：n = 1 一定出现；n > 1 是原版的 [Biome, n]，撤离时每次有 1/n 的机会出现在选项里。
# 一个都没掷中时退回第一个必出的（原版也保证至少有一个）。城镇 → 平原。“???”（end）原版要打满 200 波才去，这里不连。

const LINKS := {
	"town": [["plains", 1]],
	"plains": [["grass", 1], ["metropolis", 1], ["lake", 1]],
	"grass": [["tall_grass", 1]],
	"tall_grass": [["forest", 1], ["cave", 1]],
	"slum": [["construction_site", 1], ["swamp", 2]],
	"forest": [["jungle", 1], ["meadow", 1]],
	"sea": [["seabed", 1], ["ice_cave", 1]],
	"swamp": [["graveyard", 1], ["tall_grass", 1]],
	"beach": [["sea", 1], ["island", 2]],
	"lake": [["beach", 1], ["swamp", 1], ["construction_site", 1]],
	"seabed": [["cave", 1], ["volcano", 3]],
	"mountain": [["volcano", 1], ["wasteland", 2], ["space", 3]],
	"badlands": [["desert", 1], ["mountain", 1]],
	"cave": [["badlands", 1], ["lake", 1], ["laboratory", 2]],
	"desert": [["ruins", 1], ["construction_site", 2]],
	"ice_cave": [["snowy_forest", 1]],
	"meadow": [["plains", 1], ["fairy_cave", 1]],
	"power_plant": [["factory", 1]],
	"volcano": [["beach", 1], ["ice_cave", 3]],
	"graveyard": [["abyss", 1]],
	"dojo": [["plains", 1], ["jungle", 2], ["temple", 2]],
	"factory": [["plains", 1], ["laboratory", 2]],
	"ruins": [["mountain", 1], ["forest", 2]],
	"wasteland": [["badlands", 1]],
	"abyss": [["cave", 1], ["space", 2], ["wasteland", 2]],
	"space": [["ruins", 1]],
	"construction_site": [["power_plant", 1], ["dojo", 2]],
	"jungle": [["temple", 1]],
	"fairy_cave": [["ice_cave", 1], ["space", 2]],
	"temple": [["desert", 1], ["swamp", 2], ["ruins", 2]],
	"metropolis": [["slum", 1]],
	"snowy_forest": [["forest", 1], ["mountain", 2], ["lake", 2]],
	"island": [["sea", 1]],
	"laboratory": [["construction_site", 1]],
}


# 有地图（原版 MAP）：能去的全部列出。
static func all_options(from_id: String) -> Array[String]:
	var out: Array[String] = []
	for l: Array in LINKS.get(from_id, []):
		out.append(str(l[0]))
	return out


# 这次撤离能去哪：按原版掷一次。roll = Callable(n) -> 0..n-1 的整数（测试注入；默认随机）。
static func roll_options(from_id: String, roll: Callable = Callable()) -> Array[String]:
	var out: Array[String] = []
	var links: Array = LINKS.get(from_id, [])
	for l: Array in links:
		var n := int(l[1])
		var hit := true
		if n > 1:
			hit = (int(roll.call(n)) if roll.is_valid() else randi() % n) == 0
		if hit:
			out.append(str(l[0]))
	if out.is_empty() and not links.is_empty():
		out.append(str(links[0][0]))
	return out
