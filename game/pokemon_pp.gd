extends RefCounted
# PP 和冷却挂钩（用户 2026-10-20：“pp 和冷却挂钩，pp 越低冷却越长；然后可以卖增加 pp 的东西”）。
# 本作仍不消耗 PP；PP 只决定冷却下限：
#   冷却 = max(这招原来定的冷却, CD_PER_PP / 有效 PP)
#   有效 PP = 原版 getMovePp()：基础 PP + 提升次数 × max(floor(基础 PP / 5), 1)（PP 提升剂每个 +20%，最多 3 个）
# CD_PER_PP = 30（用户 2026-10-22 从 20 拉长：PP 少的强招放得慢一点）→ PP 30 及以上基本不变，
# PP 20 = 1.5 秒，PP 15 = 2 秒，PP 10 = 3 秒，PP 5 = 6 秒。
# 原来就更长的（蓄力招 3 秒、花瓣舞 6 秒、回血招 20 秒下限）不受影响。
# PP 提升剂按进化系、按招记在携带道具里（道具 id "PP_UP:<招式 id>"，见 game/pokemon_held_items.gd）。

const PokemonMoves := preload("res://data/pokemon_moves.gd")

const CD_PER_PP := 30.0
const MAX_UPS := 3


static func base_pp(move_id: String) -> int:
	return int((PokemonMoves.MOVES.get(move_id, {}) as Dictionary).get("pp", 0))


static func move_pp(move_id: String, ups: int) -> int:
	var pp := base_pp(move_id)
	if pp <= 0:
		return 0
	return pp + clampi(ups, 0, MAX_UPS) * maxi(pp / 5, 1)


# 这招的基础冷却（还没乘出招速度 / 设置里的冷却系数）。
static func move_cd(move_id: String, ups: int = 0) -> float:
	var m: Dictionary = PokemonMoves.MOVES.get(move_id, {})
	var cd := float(m.get("cd", 1.0))
	var pp := move_pp(move_id, ups)
	if pp > 0:
		cd = maxf(cd, CD_PER_PP / float(pp))
	return cd
