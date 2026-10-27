extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/slum/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	434: {
		"name": "STUNKY",
		"display": "臭鼬噗",
		"stats": [63, 63, 47, 41, 41, 74],
		"types": ["毒", "恶"],
		"base_exp": 66,
		"base_total": 329,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 435, "pre_form_key": "", "evo_form_key": "", "level": 34, "item": 0, "wild_delay": 0},
		],
	},
	435: {
		"name": "SKUNTANK",
		"display": "坦克臭鼬",
		"stats": [103, 93, 67, 71, 61, 84],
		"types": ["毒", "恶"],
		"base_exp": 168,
		"base_total": 479,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	568: {
		"name": "TRUBBISH",
		"display": "破破袋",
		"stats": [50, 50, 62, 40, 62, 65],
		"types": ["毒"],
		"base_exp": 66,
		"base_total": 329,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 569, "pre_form_key": "", "evo_form_key": "", "level": 36, "item": 0, "wild_delay": 0},
		],
	},
	569: {
		"name": "GARBODOR",
		"display": "灰尘山",
		"stats": [80, 95, 82, 60, 82, 75],
		"types": ["毒"],
		"base_exp": 166,
		"base_total": 474,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	799: {
		"name": "GUZZLORD",
		"display": "恶食大王",
		"stats": [223, 101, 53, 97, 53, 43],
		"types": ["恶", "龙"],
		"base_exp": 285,
		"base_total": 570,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	849: {
		"name": "TOXTRICITY",
		"display": "颤弦蝾螈",
		"stats": [75, 98, 70, 114, 70, 75],
		"types": ["电", "毒"],
		"base_exp": 176,
		"base_total": 502,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	862: {
		"name": "OBSTAGOON",
		"display": "堵拦熊",
		"stats": [93, 90, 101, 60, 81, 95],
		"types": ["恶", "一般"],
		"base_exp": 260,
		"base_total": 520,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
}

const PREVOLUTIONS := {
	435: 434,
	569: 568,
}

const ATLAS := {
	434: {
		"": {
			"front": {"w": 56, "h": 50, "frames": 96},
			"back": {"w": 57, "h": 52, "frames": 96},
		},
	},
	435: {
		"": {
			"front": {"w": 75, "h": 56, "frames": 96},
			"back": {"w": 79, "h": 63, "frames": 96},
		},
	},
	568: {
		"": {
			"front": {"w": 53, "h": 42, "frames": 204},
			"back": {"w": 59, "h": 44, "frames": 204},
		},
	},
	569: {
		"": {
			"front": {"w": 93, "h": 69, "frames": 136},
			"back": {"w": 102, "h": 83, "frames": 136},
		},
	},
	799: {
		"": {
			"front": {"w": 96, "h": 80, "frames": 1},
			"back": {"w": 96, "h": 76, "frames": 1},
		},
	},
	849: {
		"": {
			"front": {"w": 50, "h": 84, "frames": 1},
			"back": {"w": 51, "h": 84, "frames": 1},
		},
	},
	862: {
		"": {
			"front": {"w": 61, "h": 79, "frames": 1},
			"back": {"w": 55, "h": 74, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	434: 225, # STUNKY
	435: 60, # SKUNTANK
	568: 190, # TRUBBISH
	569: 60, # GARBODOR
	799: 45, # GUZZLORD
	849: 45, # TOXTRICITY
	862: 45, # OBSTAGOON
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	434: 2, # MEDIUM_FAST
	435: 2, # MEDIUM_FAST
	568: 2, # MEDIUM_FAST
	569: 2, # MEDIUM_FAST
	799: 4, # SLOW
	849: 3, # MEDIUM_SLOW
	862: 2, # MEDIUM_FAST
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	434: [ # STUNKY
		[1, "scratch"],
		[1, "poison_gas"],
		[3, "feint"],
		[6, "smokescreen"],
		[9, "acid_spray"],
		[12, "fury_swipes"],
		[15, "focus_energy"],
		[18, "bite"],
		[21, "venoshock"],
		[24, "screech"],
		[27, "toxic"],
		[30, "sucker_punch"],
		[33, "memento"],
		[36, "night_slash"],
		[39, "belch"],
		[42, "explosion"],
	],
	435: [ # SKUNTANK
		[0, "flamethrower"],
		[1, "scratch"],
		[1, "smokescreen"],
		[1, "poison_gas"],
		[1, "feint"],
		[12, "fury_swipes"],
		[15, "focus_energy"],
		[18, "bite"],
		[21, "venoshock"],
		[24, "screech"],
		[27, "toxic"],
		[30, "sucker_punch"],
		[33, "memento"],
		[38, "night_slash"],
		[43, "belch"],
		[48, "explosion"],
	],
	568: [ # TRUBBISH
		[1, "pound"],
		[1, "poison_gas"],
		[3, "recycle"],
		[6, "acid_spray"],
		[9, "amnesia"],
		[12, "clear_smog"],
		[15, "toxic_spikes"],
		[18, "sludge"],
		[21, "stockpile"],
		[21, "swallow"],
		[24, "take_down"],
		[27, "sludge_bomb"],
		[30, "toxic"],
		[33, "belch"],
		[37, "pain_split"],
		[39, "gunk_shot"],
		[42, "explosion"],
	],
	569: [ # GARBODOR
		[1, "pound"],
		[1, "take_down"],
		[1, "poison_gas"],
		[1, "metal_claw"],
		[1, "recycle"],
		[1, "acid_spray"],
		[9, "amnesia"],
		[12, "clear_smog"],
		[15, "toxic_spikes"],
		[18, "sludge"],
		[21, "stockpile"],
		[21, "swallow"],
		[24, "body_slam"],
		[27, "sludge_bomb"],
		[30, "toxic"],
		[33, "belch"],
		[39, "pain_split"],
		[43, "gunk_shot"],
		[48, "explosion"],
	],
	799: [ # GUZZLORD
		[1, "bite"],
		[1, "dragon_tail"],
		[5, "stockpile"],
		[5, "swallow"],
		[10, "knock_off"],
		[15, "stomp"],
		[20, "stomping_tantrum"],
		[25, "wide_guard"],
		[30, "crunch"],
		[35, "body_slam"],
		[40, "gastro_acid"],
		[45, "hammer_arm"],
		[50, "heavy_slam"],
		[55, "dragon_rush"],
		[60, "belch"],
		[65, "thrash"],
		[70, "giga_impact"],
	],
	849: [ # TOXTRICITY
		[0, "spark"],
		[1, "leer"],
		[1, "growl"],
		[1, "acid"],
		[1, "thunder_shock"],
		[1, "flail"],
		[1, "acid_spray"],
		[1, "belch"],
		[1, "noble_roar"],
		[1, "nuzzle"],
		[1, "tearful_look"],
		[4, "charge"],
		[8, "shock_wave"],
		[12, "scary_face"],
		[16, "taunt"],
		[24, "screech"],
		[28, "swagger"],
		[32, "toxic"],
		[36, "discharge"],
		[40, "poison_jab"],
		[44, "overdrive"],
		[48, "boomburst"],
		[52, "shift_gear"],
	],
	862: [ # OBSTAGOON
		[0, "obstruct"],
		[1, "sand_attack"],
		[1, "tackle"],
		[1, "pin_missile"],
		[1, "leer"],
		[1, "submission"],
		[1, "lick"],
		[1, "cross_chop"],
		[1, "night_slash"],
		[1, "switcheroo"],
		[1, "baby_doll_eyes"],
		[9, "snarl"],
		[12, "headbutt"],
		[15, "hone_claws"],
		[18, "fury_swipes"],
		[23, "rest"],
		[28, "take_down"],
		[35, "scary_face"],
		[42, "counter"],
		[49, "taunt"],
		[56, "double_edge"],
	],
}
