extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/island/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	779: {
		"name": "BRUXISH",
		"display": "磨牙彩皮鱼",
		"stats": [68, 105, 70, 70, 70, 92],
		"types": ["水", "超能力"],
		"base_exp": 166,
		"base_total": 475,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	806: {
		"name": "BLACEPHALON",
		"display": "砰头小丑",
		"stats": [53, 127, 53, 151, 79, 107],
		"types": ["火", "幽灵"],
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
	779: {
		"": {
			"front": {"w": 51, "h": 36, "frames": 1},
			"back": {"w": 52, "h": 38, "frames": 1},
		},
	},
	806: {
		"": {
			"front": {"w": 65, "h": 75, "frames": 1},
			"back": {"w": 60, "h": 75, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	779: 80, # BRUXISH
	806: 30, # BLACEPHALON
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	779: 2, # MEDIUM_FAST
	806: 4, # SLOW
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	779: [ # BRUXISH
		[1, "water_gun"],
		[4, "astonish"],
		[9, "confusion"],
		[12, "bite"],
		[17, "aqua_jet"],
		[20, "disable"],
		[25, "psyshock"],
		[28, "crunch"],
		[33, "aqua_tail"],
		[36, "screech"],
		[41, "psychic_fangs"],
		[44, "wave_crash"],
	],
	806: [ # BLACEPHALON
		[1, "fire_spin"],
		[1, "astonish"],
		[5, "light_screen"],
		[10, "ember"],
		[15, "night_shade"],
		[20, "confuse_ray"],
		[25, "magic_coat"],
		[30, "incinerate"],
		[35, "hypnosis"],
		[40, "mystical_fire"],
		[45, "shadow_ball"],
		[50, "calm_mind"],
		[55, "will_o_wisp"],
		[60, "trick"],
		[65, "fire_blast"],
		[70, "mind_blown"],
	],
}
