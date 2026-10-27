extends RefCounted
# 地图天气表（照原版 src/data/weather.ts getRandomWeatherType，提交 c16a3bbf）：每个地区一张 [天气, 权重] 表；
# 标 true 的那项只在白天（原版 hasSun = 黎明 / 白天）才进表。表里没列的地区原版就是没天气。
# 原版在每一场战斗开始时掷一次（EncounterPhase）；本作一分钟算一场，所以每过一分钟重掷一次。
# 天气名：rain 雨 / sun 晴 / sand 沙暴 / snow 雪 / hail 冰雹 / fog 雾 / "" 无。

const POOLS := {
	"grass": [["", 7, false], ["sun", 3, true]],
	"tall_grass": [["", 8, false], ["rain", 5, false], ["sun", 8, true]],
	"forest": [["", 8, false], ["rain", 5, false]],
	"sea": [["", 3, false], ["rain", 12, false]],
	"swamp": [["", 3, false], ["rain", 4, false], ["fog", 1, false]],
	"beach": [["", 8, false], ["rain", 3, false], ["sun", 5, true]],
	"lake": [["", 10, false], ["rain", 5, false], ["fog", 1, false]],
	"seabed": [["rain", 1, false]],
	"badlands": [["", 8, false], ["sand", 2, false], ["sun", 5, true]],
	"desert": [["sand", 2, false], ["sun", 2, true]],
	"ice_cave": [["", 3, false], ["snow", 4, false], ["hail", 1, false]],
	"meadow": [["", 2, false], ["sun", 2, true]],
	"volcano": [["sun", 1, true], ["", 1, false]],   # 原版：白天晴、晚上无（同一项二选一，这里拆成两项、晚上晴那项不进表）
	"graveyard": [["", 3, false], ["fog", 1, false]],
	"jungle": [["", 8, false], ["rain", 2, false]],
	"snowy_forest": [["snow", 7, false], ["hail", 1, false]],
	"island": [["", 5, false], ["rain", 1, false], ["sun", 2, true]],
}


# 掷一次：has_sun = 现在是黎明 / 白天。roll = Callable(总权重) -> 0..总权重-1（测试注入；默认随机）。
static func roll(map_id: String, has_sun: bool, roll_fn: Callable = Callable()) -> String:
	var pool: Array = []
	for e: Array in POOLS.get(map_id, []):
		if bool(e[2]) and not has_sun:
			continue
		if map_id == "volcano" and str(e[0]) == "" and has_sun:
			continue   # 火山白天只有晴
		pool.append(e)
	if pool.is_empty():
		return ""
	var total := 0
	for e: Array in pool:
		total += int(e[1])
	var r := int(roll_fn.call(total)) if roll_fn.is_valid() else randi() % total
	for e: Array in pool:
		r -= int(e[1])
		if r < 0:
			return str(e[0])
	return str(pool[0][0])
