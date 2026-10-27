extends RefCounted
#
# 只覆盖当前真实存在的 84 个稳定 source_species_id：
#   - 当前平原有限 81 物种（data/pokemon_wild_species.gd 的原野生 + 亲缘闭包）；
#   - 当前玩家已接绿毛虫链 10 / 11 / 12。
# 不 dump 原作 1025 条，也不覆盖 data/pokemon_wild_species.gd 的原野生资料。
#
# stats 14..19 / baseExp 22 交叉核实。地区种 8128 用源 ID 原值。
#   10 CATERPIE=255 / 11 METAPOD=120 / 12 BUTTERFREE=45
#   113 CHANSEY=30 / 380 LATIAS=3
# 745 LYCANROC 的 midday / midnight / dusk 三形态共享同 species.catchRate=90，
# 本表按 species ID 存一份，不按形态名猜、不为每形态各存一条；
# forms 里的 baseExp / 其他数字都不是 catchRate。来源与边界见
# game/POKEMON_CAPTURE_SOURCE.md。

# 未知 / 无资料：明确返回 -1，不伪装成 0 概率。
const UNKNOWN := -1

# source_species_id -> species.catchRate（原 `new Y(...)` argIndex 20）。
const CATCH_RATES := {
	161: 255, # SENTRET
	162: 90, # FURRET
	734: 255, # YUNGOOS
	735: 127, # GUMSHOOS
	819: 255, # SKWOVET
	820: 90, # GREEDENT
	52: 255, # MEOWTH（含 G-Max form，同 rate）
	53: 90, # PERSIAN
	261: 255, # POOCHYENA
	262: 127, # MIGHTYENA
	41: 255, # ZUBAT
	42: 90, # GOLBAT
	263: 255, # ZIGZAGOON
	264: 90, # LINOONE
	399: 255, # BIDOOF
	400: 127, # BIBAREL
	915: 255, # LECHONK
	916: 100, # OINKOLOGNE（含 Male / Female form，同 rate）
	84: 190, # DODUO
	85: 45, # DODRIO
	396: 255, # STARLY
	397: 120, # STARAVIA
	398: 45, # STARAPTOR
	519: 255, # PIDOVE
	520: 120, # TRANQUILL
	521: 45, # UNFEZANT
	921: 190, # PAWMI
	922: 80, # PAWMO
	923: 45, # PAWMOT
	744: 190, # ROCKRUFF（含 Own Tempo form，同 rate）
	745: 90, # LYCANROC（midday / midnight / dusk 三形态共享）
	56: 190, # MANKEY
	57: 75, # PRIMEAPE
	979: 45, # ANNIHILAPE
	16: 255, # PIDGEY
	17: 120, # PIDGEOTTO
	18: 45, # PIDGEOT（含 Mega form，同 rate）
	21: 255, # SPEAROW
	22: 90, # FEAROW
	25: 190, # PIKACHU（含 G-Max form，同 rate）
	661: 255, # FLETCHLING
	662: 120, # FLETCHINDER
	663: 45, # TALONFLAME
	8128: 45, # PALDEA_TAUROS（源地区 ID）
	403: 235, # SHINX
	404: 120, # LUXIO
	405: 45, # LUXRAY
	63: 200, # ABRA
	64: 100, # KADABRA
	427: 190, # BUNEARY
	428: 60, # LOPUNNY（含 Mega form，同 rate）
	821: 255, # ROOKIDEE
	822: 120, # CORVISQUIRE
	823: 45, # CORVIKNIGHT（含 G-Max form，同 rate）
	83: 45, # FARFETCHD
	108: 45, # LICKITUNG
	113: 30, # CHANSEY
	133: 45, # EEVEE（含 G-Max form，同 rate）
	143: 25, # SNORLAX（含 G-Max form，同 rate）
	206: 190, # DUNSPARCE
	982: 45, # DUDUNSPARCE（含 Two / Three-Segment form，同 rate）
	132: 35, # DITTO
	380: 3, # LATIAS（含 Mega form，同 rate）
	381: 3, # LATIOS（含 Mega form，同 rate）
	463: 30, # LICKILICKY
	2026: 75, # ALOLA_RAICHU
	26: 75, # RAICHU
	700: 45, # SYLVEON
	196: 45, # ESPEON
	197: 45, # UMBREON
	134: 45, # VAPOREON
	135: 45, # JOLTEON
	136: 45, # FLAREON
	470: 45, # LEAFEON
	471: 45, # GLACEON
	65: 50, # ALAKAZAM（含 Mega form，同 rate）
	169: 90, # CROBAT
	242: 30, # BLISSEY
	172: 190, # PICHU（含 Spiky-Eared form，同 rate）
	440: 130, # HAPPINY
	446: 50, # MUNCHLAX
	10: 255, # CATERPIE（当前玩家进化链）
	11: 120, # METAPOD（当前玩家进化链）
	12: 45, # BUTTERFREE（含 G-Max form；同 rate，当前玩家进化链）
}


# 平原的 CATCH_RATES 保持不变（老检查对账用）；其它地区已接线物种的捕获率在 data/pokemon_biome_species.gd，下面的查询合并两边。
const Extras := preload("res://data/pokemon_biome_species.gd")


# 表内条目数（平原 + 其它地区已接线的）。
static func count() -> int:
	return CATCH_RATES.size() + Extras.catch_rates().size()


# 该稳定 source_species_id 本轮是否有捕获率资料。
static func has_species(source_species_id: int) -> bool:
	return CATCH_RATES.has(source_species_id) or Extras.catch_rates().has(source_species_id)


# 按稳定 source_species_id 查原始 catchRate；未知返回 UNKNOWN(-1)，不伪装 0。
static func catch_rate(source_species_id: int) -> int:
	if CATCH_RATES.has(source_species_id):
		return int(CATCH_RATES[source_species_id])
	return int(Extras.catch_rates().get(source_species_id, UNKNOWN))


# 平原那份的条目数 / ID（老检查对账用，不含其它地区）。
static func plains_count() -> int:
	return CATCH_RATES.size()


static func plains_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in CATCH_RATES.keys():
		ids.append(int(key))
	ids.sort()
	return ids


# 稳定升序 ID 列表（检查 / 未来选角用；不参与概率）。
static func source_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in CATCH_RATES.keys():
		ids.append(int(key))
	for key in Extras.catch_rates().keys():
		ids.append(int(key))
	ids.sort()
	return ids
