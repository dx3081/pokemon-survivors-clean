extends RefCounted
#
# 只覆盖本任务 81 个有限亲缘物种（原 65 池物种 + 16 个保守亲缘补全）。生产只读本文件，
#
# 属性已按项目 TypeChart 的中文标签保存；`name` 保留源枚举名，地区 ID 用明确中文名。
# 采样算法在 game/pokemon_wild_encounters.gd；来源与边界见 data/POKEMON_PLAINS_SOURCE.md。
#
# 六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]（同原作 / 本作图鉴）。
# forms 顺序即原作 formIndex；sprite_key 决定原图集文件（id 或 id-spriteKey）。
# 图集只列 81 默认形态 + 745 midday/midnight/dusk；未列形态本段不启用、不冒充。

const SPECIES := {
	161: {
		"name": "SENTRET",
		"display": "尾立",
		"stats": [35, 46, 34, 35, 45, 20],
		"types": ["一般"],
		"base_exp": 43,
		"base_total": 215,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 162, "pre_form_key": "", "evo_form_key": "", "level": 15, "item": 0, "wild_delay": 0},
		],
	},
	162: {
		"name": "FURRET",
		"display": "大尾立",
		"stats": [85, 76, 64, 45, 55, 90],
		"types": ["一般"],
		"base_exp": 145,
		"base_total": 415,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	734: {
		"name": "YUNGOOS",
		"display": "猫鼬少",
		"stats": [48, 70, 30, 30, 30, 45],
		"types": ["一般"],
		"base_exp": 51,
		"base_total": 253,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 735, "pre_form_key": "", "evo_form_key": "", "level": 20, "item": 0, "wild_delay": 1},
		],
	},
	735: {
		"name": "GUMSHOOS",
		"display": "猫鼬探长",
		"stats": [88, 110, 60, 55, 60, 45],
		"types": ["一般"],
		"base_exp": 146,
		"base_total": 418,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	819: {
		"name": "SKWOVET",
		"display": "贪心栗鼠",
		"stats": [70, 55, 55, 35, 35, 25],
		"types": ["一般"],
		"base_exp": 55,
		"base_total": 275,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 820, "pre_form_key": "", "evo_form_key": "", "level": 24, "item": 0, "wild_delay": 0},
		],
	},
	820: {
		"name": "GREEDENT",
		"display": "藏饱栗鼠",
		"stats": [120, 95, 95, 55, 75, 20],
		"types": ["一般"],
		"base_exp": 161,
		"base_total": 460,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	52: {
		"name": "MEOWTH",
		"display": "喵喵",
		"stats": [40, 45, 35, 40, 40, 90],
		"types": ["一般"],
		"base_exp": 58,
		"base_total": 290,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [40, 45, 35, 40, 40, 90], "types": ["一般"], "base_exp": 58, "base_total": 290},
			{"form_key": "gigantamax", "form_name": "G-Max", "sprite_key": "gigantamax", "stats": [50, 85, 60, 70, 50, 75], "types": ["一般"], "base_exp": 58, "base_total": 390},
		],
		"evolutions": [
			{"species_id": 53, "pre_form_key": "", "evo_form_key": "", "level": 28, "item": 0, "wild_delay": 0},
		],
	},
	53: {
		"name": "PERSIAN",
		"display": "猫老大",
		"stats": [65, 70, 60, 65, 65, 115],
		"types": ["一般"],
		"base_exp": 154,
		"base_total": 440,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	261: {
		"name": "POOCHYENA",
		"display": "土狼犬",
		"stats": [35, 55, 35, 30, 30, 35],
		"types": ["恶"],
		"base_exp": 56,
		"base_total": 220,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 262, "pre_form_key": "", "evo_form_key": "", "level": 18, "item": 0, "wild_delay": 0},
		],
	},
	262: {
		"name": "MIGHTYENA",
		"display": "大狼犬",
		"stats": [70, 90, 70, 60, 60, 70],
		"types": ["恶"],
		"base_exp": 147,
		"base_total": 420,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	41: {
		"name": "ZUBAT",
		"display": "超音蝠",
		"stats": [40, 45, 35, 30, 40, 55],
		"types": ["毒", "飞行"],
		"base_exp": 49,
		"base_total": 245,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 42, "pre_form_key": "", "evo_form_key": "", "level": 22, "item": 0, "wild_delay": 0},
		],
	},
	42: {
		"name": "GOLBAT",
		"display": "大嘴蝠",
		"stats": [75, 80, 70, 65, 75, 90],
		"types": ["毒", "飞行"],
		"base_exp": 159,
		"base_total": 455,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 169, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 4},
		],
	},
	263: {
		"name": "ZIGZAGOON",
		"display": "蛇纹熊",
		"stats": [38, 30, 41, 30, 41, 60],
		"types": ["一般"],
		"base_exp": 56,
		"base_total": 240,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 264, "pre_form_key": "", "evo_form_key": "", "level": 20, "item": 0, "wild_delay": 0},
		],
	},
	264: {
		"name": "LINOONE",
		"display": "直冲熊",
		"stats": [78, 70, 61, 50, 61, 100],
		"types": ["一般"],
		"base_exp": 147,
		"base_total": 420,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	399: {
		"name": "BIDOOF",
		"display": "大牙狸",
		"stats": [59, 45, 40, 35, 40, 31],
		"types": ["一般"],
		"base_exp": 50,
		"base_total": 250,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 400, "pre_form_key": "", "evo_form_key": "", "level": 15, "item": 0, "wild_delay": 0},
		],
	},
	400: {
		"name": "BIBAREL",
		"display": "大尾狸",
		"stats": [79, 85, 60, 55, 60, 71],
		"types": ["一般", "水"],
		"base_exp": 144,
		"base_total": 410,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	915: {
		"name": "LECHONK",
		"display": "爱吃豚",
		"stats": [54, 45, 40, 35, 45, 35],
		"types": ["一般"],
		"base_exp": 51,
		"base_total": 254,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 916, "pre_form_key": "", "evo_form_key": "female", "level": 18, "item": 0, "wild_delay": 0},
			{"species_id": 916, "pre_form_key": "", "evo_form_key": "", "level": 18, "item": 0, "wild_delay": 0},
		],
	},
	916: {
		"name": "OINKOLOGNE",
		"display": "飘香豚",
		"stats": [110, 100, 75, 59, 80, 65],
		"types": ["一般"],
		"base_exp": 171,
		"base_total": 489,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "male", "form_name": "Male", "sprite_key": "", "stats": [110, 100, 75, 59, 80, 65], "types": ["一般"], "base_exp": 171, "base_total": 489},
			{"form_key": "female", "form_name": "Female", "sprite_key": "female", "stats": [115, 90, 70, 59, 90, 65], "types": ["一般"], "base_exp": 171, "base_total": 489},
		],
		"evolutions": [],
	},
	84: {
		"name": "DODUO",
		"display": "嘟嘟",
		"stats": [35, 85, 45, 35, 35, 75],
		"types": ["一般", "飞行"],
		"base_exp": 62,
		"base_total": 310,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 85, "pre_form_key": "", "evo_form_key": "", "level": 31, "item": 0, "wild_delay": 0},
		],
	},
	85: {
		"name": "DODRIO",
		"display": "嘟嘟利",
		"stats": [60, 110, 70, 60, 60, 110],
		"types": ["一般", "飞行"],
		"base_exp": 165,
		"base_total": 470,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	396: {
		"name": "STARLY",
		"display": "姆克儿",
		"stats": [40, 55, 30, 30, 30, 60],
		"types": ["一般", "飞行"],
		"base_exp": 49,
		"base_total": 245,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 397, "pre_form_key": "", "evo_form_key": "", "level": 14, "item": 0, "wild_delay": 0},
		],
	},
	397: {
		"name": "STARAVIA",
		"display": "姆克鸟",
		"stats": [55, 75, 50, 40, 40, 80],
		"types": ["一般", "飞行"],
		"base_exp": 119,
		"base_total": 340,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 398, "pre_form_key": "", "evo_form_key": "", "level": 34, "item": 0, "wild_delay": 0},
		],
	},
	398: {
		"name": "STARAPTOR",
		"display": "姆克鹰",
		"stats": [85, 120, 70, 50, 60, 100],
		"types": ["一般", "飞行"],
		"base_exp": 218,
		"base_total": 485,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	519: {
		"name": "PIDOVE",
		"display": "豆豆鸽",
		"stats": [50, 55, 50, 36, 30, 43],
		"types": ["一般", "飞行"],
		"base_exp": 53,
		"base_total": 264,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 520, "pre_form_key": "", "evo_form_key": "", "level": 21, "item": 0, "wild_delay": 0},
		],
	},
	520: {
		"name": "TRANQUILL",
		"display": "咕咕鸽",
		"stats": [62, 77, 62, 50, 42, 65],
		"types": ["一般", "飞行"],
		"base_exp": 125,
		"base_total": 358,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 521, "pre_form_key": "", "evo_form_key": "", "level": 32, "item": 0, "wild_delay": 0},
		],
	},
	521: {
		"name": "UNFEZANT",
		"display": "高傲雉鸡",
		"stats": [80, 115, 80, 65, 55, 93],
		"types": ["一般", "飞行"],
		"base_exp": 244,
		"base_total": 488,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	921: {
		"name": "PAWMI",
		"display": "布拨",
		"stats": [45, 50, 20, 40, 25, 60],
		"types": ["电"],
		"base_exp": 48,
		"base_total": 240,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 922, "pre_form_key": "", "evo_form_key": "", "level": 18, "item": 0, "wild_delay": 0},
		],
	},
	922: {
		"name": "PAWMO",
		"display": "布土拨",
		"stats": [60, 75, 40, 50, 40, 85],
		"types": ["电", "格斗"],
		"base_exp": 123,
		"base_total": 350,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 923, "pre_form_key": "", "evo_form_key": "", "level": 32, "item": 0, "wild_delay": 0},
		],
	},
	923: {
		"name": "PAWMOT",
		"display": "巴布土拨",
		"stats": [70, 115, 70, 70, 60, 105],
		"types": ["电", "格斗"],
		"base_exp": 245,
		"base_total": 490,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	744: {
		"name": "ROCKRUFF",
		"display": "岩狗狗",
		"stats": [45, 65, 40, 30, 40, 60],
		"types": ["岩石"],
		"base_exp": 56,
		"base_total": 280,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [45, 65, 40, 30, 40, 60], "types": ["岩石"], "base_exp": 56, "base_total": 280},
			{"form_key": "own-tempo", "form_name": "Own Tempo", "sprite_key": "", "stats": [45, 65, 40, 30, 40, 60], "types": ["岩石"], "base_exp": 56, "base_total": 280},
		],
		"evolutions": [
			{"species_id": 745, "pre_form_key": "", "evo_form_key": "midday", "level": 25, "item": 0, "wild_delay": 0},
			{"species_id": 745, "pre_form_key": "", "evo_form_key": "dusk", "level": 25, "item": 0, "wild_delay": 0},
			{"species_id": 745, "pre_form_key": "", "evo_form_key": "midnight", "level": 25, "item": 0, "wild_delay": 0},
		],
	},
	745: {
		"name": "LYCANROC",
		"display": "鬃岩狼人",
		"stats": [75, 115, 65, 55, 65, 112],
		"types": ["岩石"],
		"base_exp": 170,
		"base_total": 487,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "midday", "form_name": "Midday Form", "sprite_key": "", "stats": [75, 115, 65, 55, 65, 112], "types": ["岩石"], "base_exp": 170, "base_total": 487},
			{"form_key": "midnight", "form_name": "Midnight Form", "sprite_key": "midnight", "stats": [85, 115, 75, 55, 75, 82], "types": ["岩石"], "base_exp": 170, "base_total": 487},
			{"form_key": "dusk", "form_name": "Dusk Form", "sprite_key": "dusk", "stats": [75, 117, 65, 55, 65, 110], "types": ["岩石"], "base_exp": 170, "base_total": 487},
		],
		"evolutions": [],
	},
	56: {
		"name": "MANKEY",
		"display": "猴怪",
		"stats": [40, 80, 35, 35, 45, 70],
		"types": ["格斗"],
		"base_exp": 61,
		"base_total": 305,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 57, "pre_form_key": "", "evo_form_key": "", "level": 28, "item": 0, "wild_delay": 0},
		],
	},
	57: {
		"name": "PRIMEAPE",
		"display": "火暴猴",
		"stats": [65, 105, 60, 60, 70, 95],
		"types": ["格斗"],
		"base_exp": 159,
		"base_total": 455,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 979, "pre_form_key": "", "evo_form_key": "", "level": 35, "item": 0, "wild_delay": 4},
		],
	},
	979: {
		"name": "ANNIHILAPE",
		"display": "弃世猴",
		"stats": [110, 115, 80, 50, 90, 90],
		"types": ["格斗", "幽灵"],
		"base_exp": 268,
		"base_total": 535,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	16: {
		"name": "PIDGEY",
		"display": "波波",
		"stats": [40, 45, 40, 35, 35, 56],
		"types": ["一般", "飞行"],
		"base_exp": 50,
		"base_total": 251,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 17, "pre_form_key": "", "evo_form_key": "", "level": 18, "item": 0, "wild_delay": 0},
		],
	},
	17: {
		"name": "PIDGEOTTO",
		"display": "比比鸟",
		"stats": [63, 60, 55, 50, 50, 71],
		"types": ["一般", "飞行"],
		"base_exp": 122,
		"base_total": 349,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 18, "pre_form_key": "", "evo_form_key": "", "level": 36, "item": 0, "wild_delay": 0},
		],
	},
	18: {
		"name": "PIDGEOT",
		"display": "大比鸟",
		"stats": [83, 80, 75, 70, 70, 101],
		"types": ["一般", "飞行"],
		"base_exp": 216,
		"base_total": 479,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [83, 80, 75, 70, 70, 101], "types": ["一般", "飞行"], "base_exp": 216, "base_total": 479},
			{"form_key": "mega", "form_name": "Mega", "sprite_key": "mega", "stats": [83, 80, 80, 135, 80, 121], "types": ["一般", "飞行"], "base_exp": 216, "base_total": 579},
		],
		"evolutions": [],
	},
	21: {
		"name": "SPEAROW",
		"display": "烈雀",
		"stats": [40, 60, 30, 31, 31, 70],
		"types": ["一般", "飞行"],
		"base_exp": 52,
		"base_total": 262,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 22, "pre_form_key": "", "evo_form_key": "", "level": 20, "item": 0, "wild_delay": 0},
		],
	},
	22: {
		"name": "FEAROW",
		"display": "大嘴雀",
		"stats": [65, 90, 65, 61, 61, 100],
		"types": ["一般", "飞行"],
		"base_exp": 155,
		"base_total": 442,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	25: {
		"name": "PIKACHU",
		"display": "皮卡丘",
		"stats": [35, 55, 40, 50, 50, 90],
		"types": ["电"],
		"base_exp": 112,
		"base_total": 320,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [35, 55, 40, 50, 50, 90], "types": ["电"], "base_exp": 112, "base_total": 320},
			{"form_key": "gigantamax", "form_name": "G-Max", "sprite_key": "gigantamax", "stats": [45, 60, 65, 100, 75, 75], "types": ["电"], "base_exp": 112, "base_total": 420},
		],
		"evolutions": [
			{"species_id": 2026, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 7, "wild_delay": 3},
			{"species_id": 26, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 7, "wild_delay": 3},
		],
	},
	661: {
		"name": "FLETCHLING",
		"display": "小箭雀",
		"stats": [45, 50, 43, 40, 38, 62],
		"types": ["一般", "飞行"],
		"base_exp": 56,
		"base_total": 278,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 662, "pre_form_key": "", "evo_form_key": "", "level": 17, "item": 0, "wild_delay": 0},
		],
	},
	662: {
		"name": "FLETCHINDER",
		"display": "火箭雀",
		"stats": [62, 73, 55, 56, 52, 84],
		"types": ["火", "飞行"],
		"base_exp": 134,
		"base_total": 382,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 663, "pre_form_key": "", "evo_form_key": "", "level": 35, "item": 0, "wild_delay": 0},
		],
	},
	663: {
		"name": "TALONFLAME",
		"display": "烈箭鹰",
		"stats": [78, 81, 71, 74, 69, 126],
		"types": ["火", "飞行"],
		"base_exp": 175,
		"base_total": 499,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	8128: {
		"name": "PALDEA_TAUROS",
		"display": "肯泰罗帕底亚",
		"stats": [75, 110, 105, 30, 70, 100],
		"types": ["格斗"],
		"base_exp": 172,
		"base_total": 490,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "combat", "form_name": "Combat Breed", "sprite_key": "", "stats": [75, 110, 105, 30, 70, 100], "types": ["格斗"], "base_exp": 172, "base_total": 490},
			{"form_key": "blaze", "form_name": "Blaze Breed", "sprite_key": "blaze", "stats": [75, 110, 105, 30, 70, 100], "types": ["格斗", "火"], "base_exp": 172, "base_total": 490},
			{"form_key": "aqua", "form_name": "Aqua Breed", "sprite_key": "aqua", "stats": [75, 110, 105, 30, 70, 100], "types": ["格斗", "水"], "base_exp": 172, "base_total": 490},
		],
		"evolutions": [],
	},
	403: {
		"name": "SHINX",
		"display": "小猫怪",
		"stats": [45, 65, 34, 40, 34, 45],
		"types": ["电"],
		"base_exp": 53,
		"base_total": 263,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 404, "pre_form_key": "", "evo_form_key": "", "level": 15, "item": 0, "wild_delay": 0},
		],
	},
	404: {
		"name": "LUXIO",
		"display": "勒克猫",
		"stats": [60, 85, 49, 60, 49, 60],
		"types": ["电"],
		"base_exp": 127,
		"base_total": 363,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 405, "pre_form_key": "", "evo_form_key": "", "level": 30, "item": 0, "wild_delay": 0},
		],
	},
	405: {
		"name": "LUXRAY",
		"display": "伦琴猫",
		"stats": [80, 120, 79, 95, 79, 70],
		"types": ["电"],
		"base_exp": 262,
		"base_total": 523,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	63: {
		"name": "ABRA",
		"display": "凯西",
		"stats": [25, 20, 15, 105, 55, 90],
		"types": ["超能力"],
		"base_exp": 62,
		"base_total": 310,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 64, "pre_form_key": "", "evo_form_key": "", "level": 16, "item": 0, "wild_delay": 0},
		],
	},
	64: {
		"name": "KADABRA",
		"display": "勇基拉",
		"stats": [40, 35, 30, 120, 70, 105],
		"types": ["超能力"],
		"base_exp": 140,
		"base_total": 400,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 65, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 1, "wild_delay": 4},
		],
	},
	427: {
		"name": "BUNEARY",
		"display": "卷卷耳",
		"stats": [55, 66, 44, 44, 56, 85],
		"types": ["一般"],
		"base_exp": 70,
		"base_total": 350,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 428, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 2},
		],
	},
	428: {
		"name": "LOPUNNY",
		"display": "长耳兔",
		"stats": [65, 76, 84, 54, 96, 105],
		"types": ["一般"],
		"base_exp": 168,
		"base_total": 480,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [65, 76, 84, 54, 96, 105], "types": ["一般"], "base_exp": 168, "base_total": 480},
			{"form_key": "mega", "form_name": "Mega", "sprite_key": "mega", "stats": [65, 136, 94, 54, 96, 135], "types": ["一般", "格斗"], "base_exp": 168, "base_total": 580},
		],
		"evolutions": [],
	},
	821: {
		"name": "ROOKIDEE",
		"display": "稚山雀",
		"stats": [38, 47, 35, 33, 35, 57],
		"types": ["飞行"],
		"base_exp": 49,
		"base_total": 245,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 822, "pre_form_key": "", "evo_form_key": "", "level": 18, "item": 0, "wild_delay": 0},
		],
	},
	822: {
		"name": "CORVISQUIRE",
		"display": "蓝鸦",
		"stats": [68, 67, 55, 43, 55, 77],
		"types": ["飞行"],
		"base_exp": 128,
		"base_total": 365,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 823, "pre_form_key": "", "evo_form_key": "", "level": 38, "item": 0, "wild_delay": 0},
		],
	},
	823: {
		"name": "CORVIKNIGHT",
		"display": "钢铠鸦",
		"stats": [98, 87, 105, 53, 85, 67],
		"types": ["飞行", "钢"],
		"base_exp": 248,
		"base_total": 495,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [98, 87, 105, 53, 85, 67], "types": ["飞行", "钢"], "base_exp": 248, "base_total": 495},
			{"form_key": "gigantamax", "form_name": "G-Max", "sprite_key": "gigantamax", "stats": [125, 100, 135, 60, 95, 80], "types": ["飞行", "钢"], "base_exp": 248, "base_total": 595},
		],
		"evolutions": [],
	},
	83: {
		"name": "FARFETCHD",
		"display": "大葱鸭",
		"stats": [52, 90, 55, 58, 62, 60],
		"types": ["一般", "飞行"],
		"base_exp": 132,
		"base_total": 377,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	108: {
		"name": "LICKITUNG",
		"display": "大舌头",
		"stats": [90, 55, 75, 60, 75, 30],
		"types": ["一般"],
		"base_exp": 77,
		"base_total": 385,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 463, "pre_form_key": "", "evo_form_key": "", "level": 32, "item": 0, "wild_delay": 3},
		],
	},
	113: {
		"name": "CHANSEY",
		"display": "吉利蛋",
		"stats": [250, 5, 5, 35, 105, 50],
		"types": ["一般"],
		"base_exp": 395,
		"base_total": 450,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 242, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 3},
		],
	},
	133: {
		"name": "EEVEE",
		"display": "伊布",
		"stats": [55, 55, 50, 45, 65, 55],
		"types": ["一般"],
		"base_exp": 65,
		"base_total": 325,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [55, 55, 50, 45, 65, 55], "types": ["一般"], "base_exp": 65, "base_total": 325},
			{"form_key": "gigantamax", "form_name": "G-Max", "sprite_key": "gigantamax", "stats": [70, 75, 80, 60, 95, 45], "types": ["一般"], "base_exp": 65, "base_total": 425},
		],
		"evolutions": [
			{"species_id": 700, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 3},
			{"species_id": 196, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 3},
			{"species_id": 197, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 3},
			{"species_id": 134, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 6, "wild_delay": 3},
			{"species_id": 135, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 7, "wild_delay": 3},
			{"species_id": 136, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 5, "wild_delay": 3},
			{"species_id": 470, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 4, "wild_delay": 3},
			{"species_id": 471, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 8, "wild_delay": 3},
		],
	},
	143: {
		"name": "SNORLAX",
		"display": "卡比兽",
		"stats": [160, 110, 65, 65, 110, 30],
		"types": ["一般"],
		"base_exp": 189,
		"base_total": 540,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [160, 110, 65, 65, 110, 30], "types": ["一般"], "base_exp": 189, "base_total": 540},
			{"form_key": "gigantamax", "form_name": "G-Max", "sprite_key": "gigantamax", "stats": [200, 130, 85, 75, 130, 20], "types": ["一般"], "base_exp": 189, "base_total": 640},
		],
		"evolutions": [],
	},
	206: {
		"name": "DUNSPARCE",
		"display": "土龙弟弟",
		"stats": [100, 70, 70, 65, 65, 45],
		"types": ["一般"],
		"base_exp": 145,
		"base_total": 415,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 982, "pre_form_key": "", "evo_form_key": "three-segment", "level": 32, "item": 0, "wild_delay": 4},
			{"species_id": 982, "pre_form_key": "", "evo_form_key": "", "level": 32, "item": 0, "wild_delay": 4},
		],
	},
	982: {
		"name": "DUDUNSPARCE",
		"display": "土龙节节",
		"stats": [125, 100, 80, 85, 75, 55],
		"types": ["一般"],
		"base_exp": 182,
		"base_total": 520,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "two-segment", "form_name": "Two-Segment Form", "sprite_key": "", "stats": [125, 100, 80, 85, 75, 55], "types": ["一般"], "base_exp": 182, "base_total": 520},
			{"form_key": "three-segment", "form_name": "Three-Segment Form", "sprite_key": "three-segment", "stats": [125, 100, 80, 85, 75, 55], "types": ["一般"], "base_exp": 182, "base_total": 520},
		],
		"evolutions": [],
	},
	132: {
		"name": "DITTO",
		"display": "百变怪",
		"stats": [48, 48, 48, 48, 48, 48],
		"types": ["一般"],
		"base_exp": 101,
		"base_total": 288,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	380: {
		"name": "LATIAS",
		"display": "拉帝亚斯",
		"stats": [80, 80, 90, 110, 130, 110],
		"types": ["龙", "超能力"],
		"base_exp": 300,
		"base_total": 600,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [80, 80, 90, 110, 130, 110], "types": ["龙", "超能力"], "base_exp": 300, "base_total": 600},
			{"form_key": "mega", "form_name": "Mega", "sprite_key": "mega", "stats": [80, 100, 120, 140, 150, 110], "types": ["龙", "超能力"], "base_exp": 300, "base_total": 700},
		],
		"evolutions": [],
	},
	381: {
		"name": "LATIOS",
		"display": "拉帝欧斯",
		"stats": [80, 90, 80, 130, 110, 110],
		"types": ["龙", "超能力"],
		"base_exp": 300,
		"base_total": 600,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [80, 90, 80, 130, 110, 110], "types": ["龙", "超能力"], "base_exp": 300, "base_total": 600},
			{"form_key": "mega", "form_name": "Mega", "sprite_key": "mega", "stats": [80, 130, 100, 160, 120, 110], "types": ["龙", "超能力"], "base_exp": 300, "base_total": 700},
		],
		"evolutions": [],
	},
	463: {
		"name": "LICKILICKY",
		"display": "大舌舔",
		"stats": [110, 85, 95, 80, 95, 50],
		"types": ["一般"],
		"base_exp": 180,
		"base_total": 515,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	2026: {
		"name": "ALOLA_RAICHU",
		"display": "阿罗拉雷丘",
		"stats": [60, 85, 50, 95, 85, 110],
		"types": ["电", "超能力"],
		"base_exp": 243,
		"base_total": 485,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	26: {
		"name": "RAICHU",
		"display": "雷丘",
		"stats": [60, 90, 55, 90, 80, 110],
		"types": ["电"],
		"base_exp": 243,
		"base_total": 485,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	700: {
		"name": "SYLVEON",
		"display": "仙子伊布",
		"stats": [95, 65, 65, 110, 130, 60],
		"types": ["妖精"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	196: {
		"name": "ESPEON",
		"display": "太阳伊布",
		"stats": [65, 65, 60, 130, 95, 110],
		"types": ["超能力"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	197: {
		"name": "UMBREON",
		"display": "月亮伊布",
		"stats": [95, 65, 110, 60, 130, 65],
		"types": ["恶"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	134: {
		"name": "VAPOREON",
		"display": "水伊布",
		"stats": [130, 65, 60, 110, 95, 65],
		"types": ["水"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	135: {
		"name": "JOLTEON",
		"display": "雷伊布",
		"stats": [65, 65, 60, 110, 95, 130],
		"types": ["电"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	136: {
		"name": "FLAREON",
		"display": "火伊布",
		"stats": [65, 130, 60, 95, 110, 65],
		"types": ["火"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	470: {
		"name": "LEAFEON",
		"display": "叶伊布",
		"stats": [65, 110, 130, 60, 65, 95],
		"types": ["草"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	471: {
		"name": "GLACEON",
		"display": "冰伊布",
		"stats": [65, 60, 110, 130, 95, 65],
		"types": ["冰"],
		"base_exp": 184,
		"base_total": 525,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	65: {
		"name": "ALAKAZAM",
		"display": "胡地",
		"stats": [55, 50, 45, 135, 95, 120],
		"types": ["超能力"],
		"base_exp": 250,
		"base_total": 500,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [55, 50, 45, 135, 95, 120], "types": ["超能力"], "base_exp": 250, "base_total": 500},
			{"form_key": "mega", "form_name": "Mega", "sprite_key": "mega", "stats": [55, 50, 65, 175, 105, 150], "types": ["超能力"], "base_exp": 250, "base_total": 600},
		],
		"evolutions": [],
	},
	169: {
		"name": "CROBAT",
		"display": "叉字蝠",
		"stats": [85, 90, 80, 70, 80, 130],
		"types": ["毒", "飞行"],
		"base_exp": 268,
		"base_total": 535,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	242: {
		"name": "BLISSEY",
		"display": "幸福蛋",
		"stats": [255, 10, 10, 75, 135, 55],
		"types": ["一般"],
		"base_exp": 635,
		"base_total": 540,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	172: {
		"name": "PICHU",
		"display": "皮丘",
		"stats": [20, 40, 15, 35, 35, 60],
		"types": ["电"],
		"base_exp": 41,
		"base_total": 205,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [
			{"form_key": "", "form_name": "Normal", "sprite_key": "", "stats": [20, 40, 15, 35, 35, 60], "types": ["电"], "base_exp": 41, "base_total": 205},
			{"form_key": "spiky", "form_name": "Spiky-Eared", "sprite_key": "spiky", "stats": [20, 40, 15, 35, 35, 60], "types": ["电"], "base_exp": 41, "base_total": 205},
		],
		"evolutions": [
			{"species_id": 25, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 1},
		],
	},
	440: {
		"name": "HAPPINY",
		"display": "小福蛋",
		"stats": [100, 5, 5, 15, 65, 30],
		"types": ["一般"],
		"base_exp": 110,
		"base_total": 220,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 113, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 1},
		],
	},
	446: {
		"name": "MUNCHLAX",
		"display": "小卡比兽",
		"stats": [135, 85, 40, 40, 85, 5],
		"types": ["一般"],
		"base_exp": 78,
		"base_total": 390,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 143, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 3},
		],
	},
}

# 物种 ID -> 直接前进化物种 ID（原作 getSpeciesForLevel 里的 `la` 映射）。
const PREVOLUTIONS := {
	17: 16,
	18: 17,
	22: 21,
	25: 172,
	26: 25,
	42: 41,
	53: 52,
	57: 56,
	64: 63,
	65: 64,
	85: 84,
	113: 440,
	134: 133,
	135: 133,
	136: 133,
	143: 446,
	162: 161,
	169: 42,
	196: 133,
	197: 133,
	242: 113,
	262: 261,
	264: 263,
	397: 396,
	398: 397,
	400: 399,
	404: 403,
	405: 404,
	428: 427,
	463: 108,
	470: 133,
	471: 133,
	520: 519,
	521: 520,
	662: 661,
	663: 662,
	700: 133,
	735: 734,
	745: 744,
	820: 819,
	822: 821,
	823: 822,
	916: 915,
	922: 921,
	923: 922,
	979: 57,
	982: 206,
	2026: 25,
}

# 原图集尺度：ATLAS[物种][sprite_key][view] = {"w","h","frames"}（w/h = 该视角全部帧最大 sourceSize）。
# 脚底锚点 = (w/2, h)，由显示组件按此现算；fps 与像素比例沿用现有 12fps / pixel_size。
const ATLAS := {
	16: {
		"": {
			"front": {"w": 43, "h": 48, "frames": 87},
			"back": {"w": 45, "h": 47, "frames": 87},
		},
	},
	17: {
		"": {
			"front": {"w": 82, "h": 116, "frames": 36},
			"back": {"w": 95, "h": 96, "frames": 36},
		},
	},
	18: {
		"": {
			"front": {"w": 58, "h": 68, "frames": 72},
			"back": {"w": 68, "h": 66, "frames": 72},
		},
	},
	21: {
		"": {
			"front": {"w": 33, "h": 39, "frames": 64},
			"back": {"w": 35, "h": 40, "frames": 64},
		},
	},
	22: {
		"": {
			"front": {"w": 82, "h": 105, "frames": 22},
			"back": {"w": 79, "h": 112, "frames": 22},
		},
	},
	25: {
		"": {
			"front": {"w": 50, "h": 46, "frames": 116},
			"back": {"w": 41, "h": 47, "frames": 116},
		},
	},
	26: {
		"": {
			"front": {"w": 74, "h": 73, "frames": 168},
			"back": {"w": 76, "h": 72, "frames": 168},
		},
	},
	41: {
		"": {
			"front": {"w": 53, "h": 46, "frames": 54},
			"back": {"w": 49, "h": 59, "frames": 54},
		},
	},
	42: {
		"": {
			"front": {"w": 111, "h": 83, "frames": 16},
			"back": {"w": 95, "h": 84, "frames": 16},
		},
	},
	52: {
		"": {
			"front": {"w": 48, "h": 65, "frames": 140},
			"back": {"w": 58, "h": 64, "frames": 140},
		},
	},
	53: {
		"": {
			"front": {"w": 73, "h": 62, "frames": 108},
			"back": {"w": 78, "h": 56, "frames": 108},
		},
	},
	56: {
		"": {
			"front": {"w": 66, "h": 61, "frames": 120},
			"back": {"w": 62, "h": 59, "frames": 120},
		},
	},
	57: {
		"": {
			"front": {"w": 66, "h": 60, "frames": 56},
			"back": {"w": 72, "h": 58, "frames": 56},
		},
	},
	63: {
		"": {
			"front": {"w": 63, "h": 53, "frames": 114},
			"back": {"w": 71, "h": 56, "frames": 112},
		},
	},
	64: {
		"": {
			"front": {"w": 79, "h": 60, "frames": 136},
			"back": {"w": 80, "h": 66, "frames": 136},
		},
	},
	65: {
		"": {
			"front": {"w": 93, "h": 70, "frames": 114},
			"back": {"w": 82, "h": 67, "frames": 114},
		},
	},
	83: {
		"": {
			"front": {"w": 45, "h": 48, "frames": 82},
			"back": {"w": 46, "h": 50, "frames": 82},
		},
	},
	84: {
		"": {
			"front": {"w": 60, "h": 53, "frames": 204},
			"back": {"w": 61, "h": 56, "frames": 204},
		},
	},
	85: {
		"": {
			"front": {"w": 70, "h": 76, "frames": 156},
			"back": {"w": 72, "h": 76, "frames": 156},
		},
	},
	108: {
		"": {
			"front": {"w": 69, "h": 52, "frames": 72},
			"back": {"w": 77, "h": 53, "frames": 72},
		},
	},
	113: {
		"": {
			"front": {"w": 61, "h": 47, "frames": 120},
			"back": {"w": 67, "h": 47, "frames": 120},
		},
	},
	132: {
		"": {
			"front": {"w": 47, "h": 32, "frames": 80},
			"back": {"w": 47, "h": 32, "frames": 80},
		},
	},
	133: {
		"": {
			"front": {"w": 49, "h": 47, "frames": 134},
			"back": {"w": 49, "h": 50, "frames": 134},
		},
	},
	134: {
		"": {
			"front": {"w": 50, "h": 59, "frames": 162},
			"back": {"w": 50, "h": 56, "frames": 162},
		},
	},
	135: {
		"": {
			"front": {"w": 48, "h": 49, "frames": 100},
			"back": {"w": 49, "h": 48, "frames": 100},
		},
	},
	136: {
		"": {
			"front": {"w": 66, "h": 60, "frames": 120},
			"back": {"w": 70, "h": 59, "frames": 120},
		},
	},
	143: {
		"": {
			"front": {"w": 75, "h": 74, "frames": 180},
			"back": {"w": 75, "h": 71, "frames": 180},
		},
	},
	161: {
		"": {
			"front": {"w": 50, "h": 67, "frames": 76},
			"back": {"w": 47, "h": 64, "frames": 76},
		},
	},
	162: {
		"": {
			"front": {"w": 55, "h": 58, "frames": 112},
			"back": {"w": 62, "h": 60, "frames": 112},
		},
	},
	169: {
		"": {
			"front": {"w": 106, "h": 72, "frames": 96},
			"back": {"w": 107, "h": 63, "frames": 96},
		},
	},
	172: {
		"": {
			"front": {"w": 44, "h": 49, "frames": 116},
			"back": {"w": 44, "h": 49, "frames": 116},
		},
	},
	196: {
		"": {
			"front": {"w": 62, "h": 58, "frames": 152},
			"back": {"w": 61, "h": 55, "frames": 152},
		},
	},
	197: {
		"": {
			"front": {"w": 44, "h": 51, "frames": 72},
			"back": {"w": 50, "h": 51, "frames": 72},
		},
	},
	206: {
		"": {
			"front": {"w": 41, "h": 45, "frames": 96},
			"back": {"w": 58, "h": 32, "frames": 96},
		},
	},
	242: {
		"": {
			"front": {"w": 61, "h": 58, "frames": 96},
			"back": {"w": 58, "h": 58, "frames": 96},
		},
	},
	261: {
		"": {
			"front": {"w": 52, "h": 44, "frames": 96},
			"back": {"w": 53, "h": 43, "frames": 96},
		},
	},
	262: {
		"": {
			"front": {"w": 73, "h": 64, "frames": 96},
			"back": {"w": 78, "h": 65, "frames": 120},
		},
	},
	263: {
		"": {
			"front": {"w": 58, "h": 42, "frames": 126},
			"back": {"w": 59, "h": 39, "frames": 126},
		},
	},
	264: {
		"": {
			"front": {"w": 81, "h": 41, "frames": 124},
			"back": {"w": 78, "h": 53, "frames": 124},
		},
	},
	380: {
		"": {
			"front": {"w": 93, "h": 65, "frames": 128},
			"back": {"w": 94, "h": 69, "frames": 128},
		},
	},
	381: {
		"": {
			"front": {"w": 95, "h": 84, "frames": 94},
			"back": {"w": 97, "h": 84, "frames": 94},
		},
	},
	396: {
		"": {
			"front": {"w": 38, "h": 40, "frames": 108},
			"back": {"w": 38, "h": 41, "frames": 108},
		},
	},
	397: {
		"": {
			"front": {"w": 46, "h": 53, "frames": 147},
			"back": {"w": 48, "h": 52, "frames": 147},
		},
	},
	398: {
		"": {
			"front": {"w": 69, "h": 68, "frames": 133},
			"back": {"w": 73, "h": 67, "frames": 133},
		},
	},
	399: {
		"": {
			"front": {"w": 49, "h": 45, "frames": 114},
			"back": {"w": 51, "h": 45, "frames": 114},
		},
	},
	400: {
		"": {
			"front": {"w": 71, "h": 56, "frames": 196},
			"back": {"w": 68, "h": 58, "frames": 196},
		},
	},
	403: {
		"": {
			"front": {"w": 51, "h": 38, "frames": 128},
			"back": {"w": 55, "h": 39, "frames": 128},
		},
	},
	404: {
		"": {
			"front": {"w": 67, "h": 49, "frames": 192},
			"back": {"w": 63, "h": 53, "frames": 192},
		},
	},
	405: {
		"": {
			"front": {"w": 77, "h": 62, "frames": 172},
			"back": {"w": 73, "h": 66, "frames": 172},
		},
	},
	427: {
		"": {
			"front": {"w": 40, "h": 68, "frames": 184},
			"back": {"w": 44, "h": 66, "frames": 184},
		},
	},
	428: {
		"": {
			"front": {"w": 72, "h": 62, "frames": 134},
			"back": {"w": 73, "h": 63, "frames": 134},
		},
	},
	440: {
		"": {
			"front": {"w": 30, "h": 50, "frames": 114},
			"back": {"w": 29, "h": 51, "frames": 114},
		},
	},
	446: {
		"": {
			"front": {"w": 46, "h": 48, "frames": 203},
			"back": {"w": 45, "h": 50, "frames": 203},
		},
	},
	463: {
		"": {
			"front": {"w": 71, "h": 78, "frames": 132},
			"back": {"w": 79, "h": 81, "frames": 132},
		},
	},
	470: {
		"": {
			"front": {"w": 62, "h": 59, "frames": 155},
			"back": {"w": 77, "h": 61, "frames": 155},
		},
	},
	471: {
		"": {
			"front": {"w": 77, "h": 53, "frames": 172},
			"back": {"w": 70, "h": 54, "frames": 172},
		},
	},
	519: {
		"": {
			"front": {"w": 36, "h": 37, "frames": 119},
			"back": {"w": 37, "h": 39, "frames": 119},
		},
	},
	520: {
		"": {
			"front": {"w": 59, "h": 58, "frames": 160},
			"back": {"w": 58, "h": 60, "frames": 160},
		},
	},
	521: {
		"": {
			"front": {"w": 69, "h": 75, "frames": 161},
			"back": {"w": 77, "h": 78, "frames": 161},
		},
	},
	661: {
		"": {
			"front": {"w": 32, "h": 39, "frames": 1},
			"back": {"w": 33, "h": 36, "frames": 1},
		},
	},
	662: {
		"": {
			"front": {"w": 56, "h": 59, "frames": 1},
			"back": {"w": 56, "h": 50, "frames": 1},
		},
	},
	663: {
		"": {
			"front": {"w": 90, "h": 89, "frames": 1},
			"back": {"w": 90, "h": 91, "frames": 1},
		},
	},
	700: {
		"": {
			"front": {"w": 43, "h": 58, "frames": 1},
			"back": {"w": 46, "h": 59, "frames": 1},
		},
	},
	734: {
		"": {
			"front": {"w": 61, "h": 35, "frames": 1},
			"back": {"w": 65, "h": 36, "frames": 1},
		},
	},
	735: {
		"": {
			"front": {"w": 68, "h": 62, "frames": 1},
			"back": {"w": 66, "h": 61, "frames": 1},
		},
	},
	744: {
		"": {
			"front": {"w": 41, "h": 42, "frames": 1},
			"back": {"w": 41, "h": 42, "frames": 1},
		},
	},
	745: {
		"": {
			"front": {"w": 60, "h": 58, "frames": 1},
			"back": {"w": 73, "h": 58, "frames": 1},
		},
		"dusk": {
			"front": {"w": 60, "h": 64, "frames": 1},
			"back": {"w": 75, "h": 62, "frames": 1},
		},
		"midnight": {
			"front": {"w": 66, "h": 74, "frames": 1},
			"back": {"w": 60, "h": 71, "frames": 1},
		},
	},
	819: {
		"": {
			"front": {"w": 42, "h": 49, "frames": 1},
			"back": {"w": 42, "h": 48, "frames": 1},
		},
	},
	820: {
		"": {
			"front": {"w": 67, "h": 74, "frames": 1},
			"back": {"w": 67, "h": 72, "frames": 1},
		},
	},
	821: {
		"": {
			"front": {"w": 38, "h": 37, "frames": 1},
			"back": {"w": 46, "h": 38, "frames": 1},
		},
	},
	822: {
		"": {
			"front": {"w": 78, "h": 67, "frames": 1},
			"back": {"w": 78, "h": 65, "frames": 1},
		},
	},
	823: {
		"": {
			"front": {"w": 51, "h": 68, "frames": 1},
			"back": {"w": 60, "h": 65, "frames": 1},
		},
	},
	915: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	916: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	921: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	922: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	923: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	979: {
		"": {
			"front": {"w": 70, "h": 73, "frames": 1},
			"back": {"w": 79, "h": 78, "frames": 1},
		},
	},
	982: {
		"": {
			"front": {"w": 72, "h": 53, "frames": 1},
			"back": {"w": 66, "h": 35, "frames": 1},
		},
	},
	2026: {
		"": {
			"front": {"w": 68, "h": 70, "frames": 1},
			"back": {"w": 67, "h": 70, "frames": 1},
		},
	},
	8128: {
		"": {
			"front": {"w": 69, "h": 56, "frames": 1},
			"back": {"w": 70, "h": 50, "frames": 1},
		},
	},
}

# ===== 多地区合并查询（2026-10-17 起）=====
# SPECIES / ATLAS / PREVOLUTIONS 仍只是平原那份（老检查对账用）；游戏里所有查询走下面这几个，
# 平原没有的物种再查 data/pokemon_biome_species.gd 里已接线的其它地区（草地…）。
const Extras := preload("res://data/pokemon_biome_species.gd")


static func row_of(species_id: int) -> Dictionary:
	if SPECIES.has(species_id):
		return SPECIES[species_id]
	return Extras.row(species_id)


static func has_species(species_id: int) -> bool:
	return SPECIES.has(species_id) or Extras.has(species_id)


# 全部物种 ID（平原 + 其它地区，升序）。
static func all_ids() -> Array[int]:
	var out: Array[int] = []
	for k in SPECIES.keys():
		out.append(int(k))
	for k in Extras.ids():
		out.append(k)
	out.sort()
	return out


# 图集所在目录名（assets/pokemon/<目录>/front|back）：平原物种 "plains"，其它地区看它来自哪个地区；未知返回 ""。
static func atlas_dir(species_id: int) -> String:
	if SPECIES.has(species_id):
		return "plains"
	return Extras.atlas_dir(species_id)


# 直接前进化（原 `la` 映射）；没有返回 -1。
static func prevolution_of(species_id: int) -> int:
	if PREVOLUTIONS.has(species_id):
		return int(PREVOLUTIONS[species_id])
	return Extras.prevolution(species_id)


# 该物种的形态数组；无形态返回空数组（对应原作 forms.length === 0）。
static func forms_of(species_id: int) -> Array:
	var info: Dictionary = row_of(species_id)
	return info.get("forms", []) if not info.is_empty() else []

# 默认形态（form_index 0）的战斗资料：stats / types / base_exp。
static func default_form(species_id: int) -> Dictionary:
	var info: Dictionary = row_of(species_id)
	if info.is_empty():
		return {}
	var forms: Array = info.get("forms", [])
	if forms.is_empty():
		return {"form_key": "", "sprite_key": "", "stats": info["stats"], "types": info["types"], "base_exp": info["base_exp"], "base_total": info["base_total"]}
	return forms[0]

# 指定 form_index 的形态；越界回退默认形态（不静默换物种）。
static func form_at(species_id: int, form_index: int) -> Dictionary:
	var forms: Array = forms_of(species_id)
	if forms.is_empty():
		return default_form(species_id)
	return forms[clampi(form_index, 0, forms.size() - 1)]

# 该物种某形态的原图集条目；缺失返回 {}（调用方必须显式处理，不许冒充其它物种）。
static func atlas_entry(species_id: int, sprite_key: String, view: String) -> Dictionary:
	var by_form: Dictionary = ATLAS.get(species_id, {}) if ATLAS.has(species_id) else Extras.atlas(species_id)
	var by_view: Dictionary = by_form.get(sprite_key, {})
	return by_view.get(view, {})

static func file_base(species_id: int, sprite_key: String) -> String:
	return str(species_id) if sprite_key == "" else "%d-%s" % [species_id, sprite_key]

static func has_evolution(species_id: int) -> bool:
	var r: Dictionary = row_of(species_id)
	return not r.is_empty() and not (r["evolutions"] as Array).is_empty()

static func evolution_level(from_species: int, to_species: int) -> int:
	for e: Dictionary in row_of(from_species).get("evolutions", []):
		if int(e["species_id"]) == to_species:
			return int(e["level"])
	return 0

static func is_regional(species_id: int) -> bool:
	return int(floor(float(species_id) / 2000.0)) > 0

static func is_rare_regional(species_id: int) -> bool:
	return int(floor(float(species_id) / 2000.0)) == 3
