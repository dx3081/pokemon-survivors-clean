extends RefCounted
# 生蛋（用户 2026-10-23：“生蛋！幻兽帕鲁是吃蛋糕生蛋吧”“蛋糕可以是游戏里面爆的，单独记多少个；不按时间算，按击杀怪物算孵化”“蛋糕类似金珠”）。
#
# 规则：
#   蛋糕：局里打怪掉（普通怪 CAKE_CHANCE，头目必掉一块），会被吸过来，捡到存档里 +1。
#   生蛋：选宠页选两只抓到过的（神兽 / 幻之 / 准神兽不能生，照原版），花一块蛋糕生一颗蛋；同时最多 MAX_EGGS 颗。
#   孵化：之后每局每打死一只怪，所有蛋都 +1；攒够 kills_needed 自动孵出来。
#     kills_needed = KILLS_PER_COST × 这一系的原版选宠点数（1–10 档：普通 100～300 只，最稀有 1000 只）。
#   孵出来的是“第一只亲代”那一系最前面那只（巴大蝶生的蛋孵出绿毛虫），生蛋那一刻就把继承定好：
#     闪光：同一系的亲代闪光 SHINY_INHERIT（25%）、别的物种的亲代闪光 SHINY_INHERIT_OTHER（10%）继承那一档——这是“闪光往前走”的正路
#           （用户 10-21：抓到闪光巴大蝶不能直接解锁绿毛虫的闪光）；
#     个体值：每一项取两只亲代那一系里高的；性格：两只亲代当前选的性格随机一个；
#     隐藏特性：HIDDEN_CHANCE 几率解锁这一系的隐藏栏；
#     遗传招：EGG_MOVE_CHANCE 几率从第二只亲代会的招里带一个（第一只这一系本来不会的），开局可以选带。

const PokemonMoves := preload("res://data/pokemon_moves.gd")
const Starters := preload("res://game/pokemon_starters.gd")
const AB := preload("res://game/pokemon_abilities.gd")
const SpeciesCandy := preload("res://game/pokemon_species_candy.gd")
const EnemyMoves := preload("res://game/enemy_moves.gd")

const CAKE_CHANCE := 0.001        # 普通怪 0.1%（用户 2026-10-23：原来 0.5% + 头目必掉太多）
const BOSS_CAKE_CHANCE := 0.25
const MAX_EGGS := 3
const KILLS_PER_COST := 100
const SHINY_INHERIT := 0.25        # 同一系的亲代（第一只，或第二只正好同系）是闪光
const SHINY_INHERIT_OTHER := 0.10  # 别的物种的亲代是闪光：传给这一系的几率低一些（用户 2026-10-23 先说 5%，又调成 10%：“口袋妖怪异色多，1000 多只要刷死”）
const HIDDEN_CHANCE := 0.125
const EGG_MOVE_CHANCE := 0.5
const EGG_MOVE_MAX_LEVEL := 50


static func can_breed(species_id: int) -> bool:
	return species_id > 0 and not EnemyMoves.is_legendary(species_id)


static func kills_needed(root_id: int) -> int:
	return KILLS_PER_COST * SpeciesCandy.cost_of(root_id)


# 第二只亲代能带过来的遗传招：它会的（开局招 + 50 级以内的升级招，本作接了战斗的），第一只那一系开局 / 升级学不到的。
static func egg_move_candidates(child_root: int, other: int) -> Array:
	var own: Array = []
	for m in Starters.playable_initial_moves(child_root):
		own.append(str(m))
	for m in PokemonMoves.learnable_between(child_root, 1, EGG_MOVE_MAX_LEVEL, true):
		own.append(str(m))
	var pool: Array = []
	for m in Starters.playable_initial_moves(other) + PokemonMoves.learnable_between(other, 1, EGG_MOVE_MAX_LEVEL, true):
		var mid := str(m)
		if PokemonMoves.is_implemented(mid) and not own.has(mid) and not pool.has(mid):
			pool.append(mid)
	return pool


# 生一颗蛋：把孵出来的样子定好（rng 由调用方给，测试可注入）。
# parent_shiny = [第一只抓到过的最高闪光档, 第二只的]（-1 = 没有）；parent_ivs = 两只那一系的个体值；parent_natures = 两只当前性格。
static func make_egg(a: int, b: int, parent_shiny: Array, parent_ivs: Array, parent_natures: Array, rng: RandomNumberGenerator) -> Dictionary:
	var root := AB.root_of(a)
	# 两只亲代各掷一次：同一系的 25%，别的物种 10%（SHINY_INHERIT_OTHER）；都中取高的那档
	var shiny := -1
	for i in 2:
		var tier := int(parent_shiny[i])
		if tier < 0:
			continue
		var same_line := i == 0 or AB.root_of(b) == root
		if rng.randf() < (SHINY_INHERIT if same_line else SHINY_INHERIT_OTHER):
			shiny = maxi(shiny, tier)
	var ivs: Array = []
	for i in 6:
		ivs.append(maxi(int((parent_ivs[0] as Array)[i]) if (parent_ivs[0] as Array).size() > i else 0,
			int((parent_ivs[1] as Array)[i]) if (parent_ivs[1] as Array).size() > i else 0))
	var nature := int(parent_natures[rng.randi_range(0, 1)])
	var move := ""
	if rng.randf() < EGG_MOVE_CHANCE:
		var pool := egg_move_candidates(root, b)
		if not pool.is_empty():
			move = str(pool[rng.randi_range(0, pool.size() - 1)])
	return {"species": root, "parents": [a, b], "need": kills_needed(root), "done": 0, "shiny": shiny,
		"ivs": ivs, "nature": nature, "hidden": rng.randf() < HIDDEN_CHANCE, "move": move}
