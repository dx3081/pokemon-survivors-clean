extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/laboratory/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	150: {
		"name": "MEWTWO",
		"display": "超梦",
		"stats": [106, 110, 90, 154, 90, 130],
		"types": ["超能力"],
		"base_exp": 340,
		"base_total": 680,
		"sub_legendary": false,
		"legendary": true,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	718: {
		"name": "ZYGARDE",
		"display": "基格尔德",
		"stats": [108, 100, 121, 81, 95, 95],
		"types": ["龙", "地面"],
		"base_exp": 300,
		"base_total": 600,
		"sub_legendary": false,
		"legendary": true,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	772: {
		"name": "TYPE_NULL",
		"display": "属性：空",
		"stats": [95, 95, 95, 95, 95, 59],
		"types": ["一般"],
		"base_exp": 107,
		"base_total": 534,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 773, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 0},
		],
	},
	773: {
		"name": "SILVALLY",
		"display": "银伴战兽",
		"stats": [95, 95, 95, 95, 95, 95],
		"types": ["一般"],
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
	773: 772,
}

const ATLAS := {
	150: {
		"": {
			"front": {"w": 90, "h": 69, "frames": 134},
			"back": {"w": 95, "h": 70, "frames": 134},
		},
	},
	718: {
		"": {
			"front": {"w": 72, "h": 88, "frames": 1},
			"back": {"w": 72, "h": 88, "frames": 1},
		},
	},
	772: {
		"": {
			"front": {"w": 65, "h": 77, "frames": 1},
			"back": {"w": 67, "h": 77, "frames": 1},
		},
	},
	773: {
		"": {
			"front": {"w": 65, "h": 83, "frames": 1},
			"back": {"w": 63, "h": 85, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	150: 3, # MEWTWO
	718: 3, # ZYGARDE
	772: 3, # TYPE_NULL
	773: 3, # SILVALLY
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	150: 4, # SLOW
	718: 4, # SLOW
	772: 4, # SLOW
	773: 4, # SLOW
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	150: [ # MEWTWO
		[1, "disable"],
		[1, "confusion"],
		[1, "swift"],
		[1, "life_dew"],
		[8, "ancient_power"],
		[16, "psycho_cut"],
		[24, "safeguard"],
		[32, "amnesia"],
		[40, "aura_sphere"],
		[48, "psychic"],
		[56, "power_swap"],
		[56, "guard_swap"],
		[64, "mist"],
		[72, "psystrike"],
		[80, "recover"],
		[88, "future_sight"],
	],
	718: [ # ZYGARDE
		[1, "bind"],
		[1, "bite"],
		[1, "dragon_breath"],
		[1, "bulldoze"],
		[1, "thousand_arrows"],
		[1, "thousand_waves"],
		[1, "core_enforcer"],
		[8, "haze"],
		[16, "dig"],
		[24, "safeguard"],
		[32, "crunch"],
		[40, "dragon_pulse"],
		[48, "lands_wrath"],
		[56, "glare"],
		[64, "sandstorm"],
		[72, "coil"],
		[80, "earthquake"],
		[88, "outrage"],
	],
	772: [ # TYPE_NULL
		[1, "tackle"],
		[1, "imprison"],
		[5, "aerial_ace"],
		[10, "scary_face"],
		[15, "double_hit"],
		[20, "metal_sound"],
		[25, "crush_claw"],
		[30, "air_slash"],
		[35, "tri_attack"],
		[40, "x_scissor"],
		[45, "iron_head"],
		[50, "take_down"],
		[55, "double_edge"],
		[60, "heal_block"],
	],
	773: [ # SILVALLY
		[0, "multi_attack"],
		[1, "tackle"],
		[1, "bite"],
		[1, "explosion"],
		[1, "scary_face"],
		[1, "imprison"],
		[1, "poison_fang"],
		[1, "aerial_ace"],
		[1, "thunder_fang"],
		[1, "ice_fang"],
		[1, "fire_fang"],
		[1, "iron_head"],
		[1, "heal_block"],
		[15, "double_hit"],
		[20, "metal_sound"],
		[25, "crush_claw"],
		[30, "air_slash"],
		[35, "tri_attack"],
		[40, "x_scissor"],
		[45, "crunch"],
		[50, "take_down"],
		[55, "double_edge"],
		[60, "parting_shot"],
	],
}
