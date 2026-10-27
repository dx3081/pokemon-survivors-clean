extends RefCounted
# 本作当前只有绿毛虫；普通、精英和四个头目共用同一套像素素材。
# 主角的 hp/attack/defence 是 1 级原作公式占位（IV0 / 中性性格）：绿毛虫 [11,5,5]；
# speed/aspd/magnet 是本作实时战斗参数（移速 6 米/秒、攻速倍率 1.0、吸附 3 米）。
# 局内成长由 game/pokemon_growth.gd 按等级重算，见 game/POKEMON_GROWTH_SOURCE.md。
#
# 敌人模板不再写死 hp / attack / defence：只留 species_id + rank 外形 / 实时移动参数，
# 六项由 game/roster.gd 按 Pokedex 种族值 + 实际 level + 默认 IV0 / 中性性格走
# PokemonGrowth.calculate_stats 现算（普通 / 精英 / 四个头目同物种同等级同一套原能力值）。
# 击倒经验也不再用固定掉落值：基础经验查下表，按实际 level 现算（roster.gd）。
const PLAYER := "player"
const SCENE := "res://characters/caterpie.tscn"
# 已接入物种的基础经验（原作 baseExp）：仅 #0010 绿毛虫 39。
# 来源与公式见 game/POKEMON_GROWTH_SOURCE.md；不扩 1025 物种架构。
const SPECIES_BASE_EXP := {
    10: 39,   # 绿毛虫（原作 new Y(CATERPIE,...255,50,39,k.MEDIUM_FAST,...)）
}
const UNITS := {
    "player": {"name": "绿毛虫", "hp": 11.0, "attack": 5.0, "defence": 5.0, "speed": 4.8, "aspd": 1.0,
        "magnet": 3.0, "body_radius": 0.3, "block": 1.0, "scene": SCENE, "billboard": true,
        "anims": {"idle": "idle", "walk": "move", "attack": "attack", "death": "death"}},
    "caterpie": {"name": "绿毛虫", "species_id": 10, "speed": 3.4,
        "scale": 0.85, "radius": 0.38},
    "caterpie_boss_1": {"name": "绿毛虫头目", "species_id": 10, "speed": 3.5,
        "rank": "boss", "scale": 1.65, "radius": 0.38},
    "caterpie_boss_2": {"name": "绿毛虫头目", "species_id": 10, "speed": 3.6,
        "rank": "boss", "scale": 1.8, "radius": 0.38},
    "caterpie_boss_3": {"name": "绿毛虫头目", "species_id": 10, "speed": 3.7,
        "rank": "boss", "scale": 1.95, "radius": 0.38},
    "caterpie_boss_4": {"name": "巨型绿毛虫", "species_id": 10, "speed": 3.8,
        "rank": "boss", "final": true, "scale": 2.2, "radius": 0.38},
}
static func enemy_ids() -> Array[String]:
    var out: Array[String] = []
    for id: String in UNITS:
        if id != PLAYER:
            out.append(id)
    return out
