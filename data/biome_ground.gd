extends RefCounted
# 贴图是 Lynocs 的手绘风格纹理包（CC0），512×512 可平铺，放在 assets/ground/<地区id>.png；来源见 assets/ground/SOURCES.md。
#   tex   = assets/ground/ 下的文件名（不带 .png）
#   tile  = 一张贴图铺多少米
#   tint  = 整体亮度（乘在贴图上；花哨的地面压暗一点，免得盖住宠物）
#   mix   = （可选）“代码底色 + 绘画细节”做法，有它就不用 tex：a / b 两个底色按噪声渐变（和平原同一套），
#           detail = assets/ground/detail/<名>.png 灰度细节图（中灰 = 不变，深浅按 dstr 叠上去），dtile = 细节图铺多少米
#   blend = （可选）混合多种材质：{"a": 主材质, "b": 副材质, "c": 第三种(可选), "tile_a/b/c": 各自铺多少米, "tint_a/b/c": 各自亮度,
#           "thr": 副材质占比阈值(0~1，越大副材质越少), "thr_c": 第三种的阈值(默认 thr + 0.08), "soft": 交界软边宽度, "vary": 整体深浅变化}。
#           材质图放 assets/ground/blend/<名>.png；a 铺满，b / c 按平原同款噪声一块块长出来，边界是软的。有 blend 就不用 tex。
#   vary  = （可选）用平原同款噪声给整张贴图加深浅变化，打散重复感（0 = 不加）
#   props = 地面上的物件：nature 树 / 灌木 / 草 / 花 / 石头；snow 只有松树和石头；rocks 只有石头和碎石；none 什么都不长
const GROUND := {
	"town": {"tex": "town", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "cobble_warm", "b": "dirt_brown", "c": "grass_olive", "tile_a": 6.0, "tile_b": 6.0, "tile_c": 6.0, "tint_a": 1.0, "tint_b": 1.10, "tint_c": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"grass": {"tex": "grass", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "grass_olive", "b": "dry_grass", "c": "dirt_brown", "tile_a": 7.0, "tile_b": 7.0, "tile_c": 7.0, "tint_a": 1.0, "tint_b": 0.80, "tint_c": 0.88, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"tall_grass": {"tex": "tall_grass", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "grass_olive", "b": "dry_grass", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"metropolis": {"tex": "metropolis", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "brick_pavers", "b": "concrete_worn", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 1.0, "tint_b": 0.90, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"forest": {"tex": "forest", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "leaf_ground", "b": "bamboo_floor", "c": "grass_olive", "tile_a": 7.0, "tile_b": 7.0, "tile_c": 7.0, "tint_a": 0.72, "tint_b": 0.77, "tint_c": 0.75, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"sea": {"tex": "sea", "tile": 8.0, "props": "none", "tint": 1.0,
		"mix": {"a": Color(0.20, 0.42, 0.58), "b": Color(0.16, 0.36, 0.53), "detail": "sea", "dtile": 9.0, "dstr": 1.3}},
	"swamp": {"tex": "swamp", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "swamp_mud", "b": "moss_green", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.90, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"beach": {"tex": "beach", "tile": 8.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "beach_base", "b": "wet_sand", "c": "gravel_grey", "tile_a": 8.0, "tile_b": 8.0, "tile_c": 8.0, "tint_a": 0.85, "tint_b": 1.06, "tint_c": 1.06, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"lake": {"tex": "lake", "tile": 8.0, "props": "none", "tint": 1.0,
		"mix": {"a": Color(0.36, 0.55, 0.60), "b": Color(0.31, 0.49, 0.55), "detail": "lake", "dtile": 7.0, "dstr": 1.3}},
	"seabed": {"tex": "seabed", "tile": 9.0, "props": "none", "tint": 1.0,
		"blend": {"a": "seabed_base", "b": "shallow_water", "tile_a": 9.0, "tile_b": 9.0, "tint_a": 1.0, "tint_b": 1.24, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"mountain": {"tex": "mountain", "tile": 7.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "gravel_grey", "b": "dark_rock", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"badlands": {"tex": "badlands", "tile": 8.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "dirt_brown", "b": "gobi", "tile_a": 8.0, "tile_b": 8.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"cave": {"tex": "cave", "tile": 7.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "dark_rock", "b": "gravel_grey", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"desert": {"tex": "desert", "tile": 9.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "sand_dune", "b": "gobi", "tile_a": 9.0, "tile_b": 9.0, "tint_a": 1.0, "tint_b": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"ice_cave": {"tex": "ice_cave", "tile": 9.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "ice_cave_base", "b": "ice", "tile_a": 9.0, "tile_b": 9.0, "tint_a": 1.0, "tint_b": 1.17, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"meadow": {"tex": "meadow", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "meadow_flowers", "b": "grass_olive", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 1.22, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"power_plant": {"tex": "power_plant", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "metal_plate", "b": "concrete_worn", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"volcano": {"tex": "volcano", "tile": 7.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "lava_rock", "b": "ash_ground", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"graveyard": {"tex": "graveyard", "tile": 8.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "graveyard_base", "b": "moss_green", "tile_a": 8.0, "tile_b": 8.0, "tint_a": 0.8, "tint_b": 1.00, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"dojo": {"tex": "dojo", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "wood_planks", "b": "cobble_warm", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 1.0, "tint_b": 0.82, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"factory": {"tex": "factory", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "metal_plate", "b": "concrete_worn", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 0.9, "tint_b": 0.72, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"ruins": {"tex": "ruins", "tile": 8.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "ruins_base", "b": "flagstone_mossy", "tile_a": 8.0, "tile_b": 8.0, "tint_a": 1.0, "tint_b": 0.96, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"wasteland": {"tex": "wasteland", "tile": 10.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "gobi", "b": "dry_grass", "tile_a": 10.0, "tile_b": 10.0, "tint_a": 0.8, "tint_b": 0.83, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"abyss": {"tex": "abyss", "tile": 7.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "dark_rock", "b": "void_stone", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 0.9, "tint_b": 1.12, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"space": {"tex": "space", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "metal_plate", "b": "void_stone", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 0.8, "tint_b": 1.00, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"construction_site": {"tex": "construction_site", "tile": 7.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "dirt_brown", "b": "gravel_grey", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.93, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"jungle": {"tex": "jungle", "tile": 7.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "bamboo_floor", "b": "mud_road", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 0.9, "tint_b": 1.04, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"fairy_cave": {"tex": "fairy_cave", "tile": 11.0, "props": "rocks", "tint": 1.0,
		"blend": {"a": "fairy_cave_base", "b": "crystal_stone", "tile_a": 11.0, "tile_b": 11.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"temple": {"tex": "temple", "tile": 10.0, "props": "none", "tint": 1.0,
		"blend": {"a": "temple_base", "b": "flagstone_mossy", "tile_a": 10.0, "tile_b": 10.0, "tint_a": 1.0, "tint_b": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"slum": {"tex": "slum", "tile": 7.0, "props": "none", "tint": 1.0,
		"blend": {"a": "asphalt_cracked", "b": "gravel_grey", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 1.0, "tint_b": 0.80, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"snowy_forest": {"tex": "snowy_forest", "tile": 8.0, "props": "snow", "tint": 1.0,
		"blend": {"a": "snowy_forest_base", "b": "ice", "tile_a": 8.0, "tile_b": 8.0, "tint_a": 1.0, "tint_b": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"island": {"tex": "island", "tile": 9.0, "props": "nature", "tint": 1.0,
		"blend": {"a": "sand_dune", "b": "grass_olive", "c": "wet_sand", "tile_a": 9.0, "tile_b": 9.0, "tile_c": 9.0, "tint_a": 1.0, "tint_b": 1.25, "tint_c": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"laboratory": {"tex": "laboratory", "tile": 6.0, "props": "none", "tint": 1.0,
		"blend": {"a": "concrete_worn", "b": "metal_plate", "tile_a": 6.0, "tile_b": 6.0, "tint_a": 1.0, "tint_b": 1.25, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
	"end": {"tex": "end", "tile": 7.0, "props": "none", "tint": 1.0,
		"blend": {"a": "void_stone", "b": "dark_rock", "tile_a": 7.0, "tile_b": 7.0, "tint_a": 0.9, "tint_b": 0.72, "thr": 0.56, "thr_c": 0.64, "soft": 0.05, "vary": 0.12}},
}


static func has(biome: String) -> bool:
	return GROUND.has(biome)


static func entry(biome: String) -> Dictionary:
	return GROUND.get(biome, {})


static func path_of(biome: String) -> String:
	return "res://assets/ground/%s.png" % str(entry(biome).get("tex", ""))


static func mix_of(biome: String) -> Dictionary:
	return entry(biome).get("mix", {})


static func detail_path(biome: String) -> String:
	return "res://assets/ground/detail/%s.png" % str(mix_of(biome).get("detail", ""))


static func blend_of(biome: String) -> Dictionary:
	return entry(biome).get("blend", {})


static func blend_path(name: String) -> String:
	return "res://assets/ground/blend/%s.png" % name
