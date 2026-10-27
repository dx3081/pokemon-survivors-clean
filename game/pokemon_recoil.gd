extends RefCounted
# 原 RecoilAttr（猛撞 / 舍身冲撞）在 useHp=false 时的反伤金额纯运算。来源见 POKEMON_RECOIL_SOURCE.md。
# 只算金额：不改 HP、不查特性、不调用、不演出、不注册招式。

static func amount(damage_dealt: float, ratio: float = 0.25) -> int:
	return maxi(int(floor(damage_dealt * ratio)), 1 if damage_dealt != 0.0 else 0)
