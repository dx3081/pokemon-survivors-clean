extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/snowy_forest/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	866: {
		"name": "MR_RIME",
		"display": "踏冰人偶",
		"stats": [80, 85, 75, 110, 100, 70],
		"types": ["冰", "超能力"],
		"base_exp": 182,
		"base_total": 520,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	881: {
		"name": "ARCTOZOLT",
		"display": "雷鸟海兽",
		"stats": [90, 100, 90, 90, 80, 55],
		"types": ["电", "冰"],
		"base_exp": 177,
		"base_total": 505,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	888: {
		"name": "ZACIAN",
		"display": "苍响",
		"stats": [92, 120, 115, 80, 115, 138],
		"types": ["妖精"],
		"base_exp": 335,
		"base_total": 660,
		"sub_legendary": false,
		"legendary": true,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	896: {
		"name": "GLASTRIER",
		"display": "雪暴马",
		"stats": [100, 145, 130, 65, 110, 30],
		"types": ["冰"],
		"base_exp": 290,
		"base_total": 580,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	901: {
		"name": "URSALUNA",
		"display": "月月熊",
		"stats": [130, 140, 105, 45, 80, 50],
		"types": ["地面", "一般"],
		"base_exp": 275,
		"base_total": 550,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	903: {
		"name": "SNEASLER",
		"display": "大狃拉",
		"stats": [80, 130, 60, 40, 80, 120],
		"types": ["格斗", "毒"],
		"base_exp": 102,
		"base_total": 510,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	1002: {
		"name": "CHIEN_PAO",
		"display": "古剑豹",
		"stats": [80, 120, 80, 90, 65, 135],
		"types": ["恶", "冰"],
		"base_exp": 285,
		"base_total": 570,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
}

const PREVOLUTIONS := {
}

const ATLAS := {
	866: {
		"": {
			"front": {"w": 52, "h": 57, "frames": 1},
			"back": {"w": 50, "h": 54, "frames": 1},
		},
	},
	881: {
		"": {
			"front": {"w": 69, "h": 81, "frames": 1},
			"back": {"w": 66, "h": 80, "frames": 1},
		},
	},
	888: {
		"": {
			"front": {"w": 82, "h": 76, "frames": 1},
			"back": {"w": 85, "h": 75, "frames": 1},
		},
	},
	896: {
		"": {
			"front": {"w": 60, "h": 83, "frames": 1},
			"back": {"w": 67, "h": 82, "frames": 1},
		},
	},
	901: {
		"": {
			"front": {"w": 76, "h": 65, "frames": 1},
			"back": {"w": 81, "h": 67, "frames": 1},
		},
	},
	903: {
		"": {
			"front": {"w": 60, "h": 71, "frames": 1},
			"back": {"w": 60, "h": 71, "frames": 1},
		},
	},
	1002: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	866: 45, # MR_RIME
	881: 45, # ARCTOZOLT
	888: 10, # ZACIAN
	896: 3, # GLASTRIER
	901: 75, # URSALUNA
	903: 135, # SNEASLER
	1002: 6, # CHIEN_PAO
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	866: 2, # MEDIUM_FAST
	881: 4, # SLOW
	888: 4, # SLOW
	896: 4, # SLOW
	901: 2, # MEDIUM_FAST
	903: 3, # MEDIUM_SLOW
	1002: 4, # SLOW
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	866: [ # MR_RIME
		[1, "pound"],
		[1, "mimic"],
		[1, "light_screen"],
		[1, "reflect"],
		[1, "protect"],
		[1, "safeguard"],
		[1, "baton_pass"],
		[1, "encore"],
		[1, "rapid_spin"],
		[1, "role_play"],
		[1, "recycle"],
		[1, "slack_off"],
		[1, "fake_tears"],
		[1, "block"],
		[1, "copycat"],
		[1, "ice_shard"],
		[1, "after_you"],
		[1, "misty_terrain"],
		[1, "dazzling_gleam"],
		[12, "confusion"],
		[16, "ally_switch"],
		[20, "icy_wind"],
		[24, "double_kick"],
		[28, "psybeam"],
		[32, "hypnosis"],
		[36, "mirror_coat"],
		[40, "sucker_punch"],
		[44, "freeze_dry"],
		[48, "psychic"],
		[52, "teeter_dance"],
	],
	881: [ # ARCTOZOLT
		[1, "thunder_shock"],
		[1, "powder_snow"],
		[7, "charge"],
		[14, "echoed_voice"],
		[21, "ancient_power"],
		[28, "pluck"],
		[35, "avalanche"],
		[42, "freeze_dry"],
		[49, "slam"],
		[56, "discharge"],
		[63, "bolt_beak"],
		[70, "icicle_crash"],
		[77, "blizzard"],
	],
	888: [ # ZACIAN
		[1, "bite"],
		[1, "quick_attack"],
		[1, "metal_claw"],
		[1, "howl"],
		[1, "quick_guard"],
		[1, "sacred_sword"],
		[11, "slash"],
		[22, "swords_dance"],
		[33, "iron_head"],
		[44, "noble_roar"],
		[55, "crunch"],
		[66, "moonblast"],
		[77, "close_combat"],
		[88, "giga_impact"],
	],
	896: [ # GLASTRIER
		[1, "tackle"],
		[1, "tail_whip"],
		[6, "double_kick"],
		[12, "avalanche"],
		[18, "stomp"],
		[24, "torment"],
		[30, "mist"],
		[36, "icicle_crash"],
		[42, "take_down"],
		[48, "iron_defense"],
		[54, "thrash"],
		[60, "taunt"],
		[66, "double_edge"],
		[72, "swords_dance"],
	],
	901: [ # URSALUNA
		[0, "headlong_rush"],
		[1, "scratch"],
		[1, "leer"],
		[1, "lick"],
		[1, "fake_tears"],
		[1, "covet"],
		[8, "fury_swipes"],
		[13, "payback"],
		[17, "sweet_scent"],
		[22, "slash"],
		[25, "play_nice"],
		[29, "play_rough"],
		[35, "scary_face"],
		[41, "rest"],
		[41, "snore"],
		[48, "high_horsepower"],
		[56, "thrash"],
		[64, "hammer_arm"],
	],
	903: [ # SNEASLER
		[0, "dire_claw"],
		[1, "scratch"],
		[1, "leer"],
		[1, "rock_smash"],
		[1, "fling"],
		[6, "taunt"],
		[12, "quick_attack"],
		[18, "metal_claw"],
		[24, "poison_jab"],
		[30, "brick_break"],
		[36, "hone_claws"],
		[42, "slash"],
		[48, "agility"],
		[54, "screech"],
		[60, "close_combat"],
	],
	1002: [ # CHIEN_PAO
		[1, "spite"],
		[1, "powder_snow"],
		[1, "mean_look"],
		[5, "icy_wind"],
		[10, "payback"],
		[15, "mist"],
		[15, "haze"],
		[20, "ice_shard"],
		[25, "swords_dance"],
		[30, "snowscape"],
		[35, "night_slash"],
		[40, "dark_pulse"],
		[45, "icicle_crash"],
		[50, "ruination"],
		[55, "sucker_punch"],
		[60, "sacred_sword"],
		[65, "recover"],
		[70, "throat_chop"],
		[75, "sheer_cold"],
	],
}
