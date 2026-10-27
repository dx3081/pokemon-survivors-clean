extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/construction_site/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	88: {
		"name": "GRIMER",
		"display": "臭泥",
		"stats": [80, 80, 50, 40, 50, 25],
		"types": ["毒"],
		"base_exp": 65,
		"base_total": 325,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 89, "pre_form_key": "", "evo_form_key": "", "level": 38, "item": 0, "wild_delay": 0},
		],
	},
	89: {
		"name": "MUK",
		"display": "臭臭泥",
		"stats": [105, 105, 75, 65, 100, 50],
		"types": ["毒"],
		"base_exp": 175,
		"base_total": 500,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	109: {
		"name": "KOFFING",
		"display": "瓦斯弹",
		"stats": [40, 65, 95, 60, 45, 35],
		"types": ["毒"],
		"base_exp": 68,
		"base_total": 340,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 4110, "pre_form_key": "", "evo_form_key": "", "level": 35, "item": 0, "wild_delay": 0},
			{"species_id": 110, "pre_form_key": "", "evo_form_key": "", "level": 35, "item": 0, "wild_delay": 0},
		],
	},
	110: {
		"name": "WEEZING",
		"display": "双弹瓦斯",
		"stats": [65, 90, 120, 85, 70, 60],
		"types": ["毒"],
		"base_exp": 172,
		"base_total": 490,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	638: {
		"name": "COBALION",
		"display": "勾帕路翁",
		"stats": [91, 90, 129, 90, 72, 108],
		"types": ["钢", "格斗"],
		"base_exp": 290,
		"base_total": 580,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	805: {
		"name": "STAKATAKA",
		"display": "垒磊石",
		"stats": [61, 131, 211, 53, 101, 13],
		"types": ["岩石", "钢"],
		"base_exp": 285,
		"base_total": 570,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	863: {
		"name": "PERRSERKER",
		"display": "喵头目",
		"stats": [70, 110, 100, 50, 60, 50],
		"types": ["钢"],
		"base_exp": 154,
		"base_total": 440,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	884: {
		"name": "DURALUDON",
		"display": "铝钢龙",
		"stats": [70, 95, 115, 120, 50, 85],
		"types": ["钢", "龙"],
		"base_exp": 187,
		"base_total": 535,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	1018: {
		"name": "ARCHALUDON",
		"display": "铝钢桥龙",
		"stats": [90, 105, 130, 125, 65, 85],
		"types": ["钢", "龙"],
		"base_exp": 300,
		"base_total": 600,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
}

const PREVOLUTIONS := {
	89: 88,
	110: 109,
	4110: 109,
}

const ATLAS := {
	88: {
		"": {
			"front": {"w": 73, "h": 42, "frames": 120},
			"back": {"w": 70, "h": 46, "frames": 120},
		},
	},
	89: {
		"": {
			"front": {"w": 94, "h": 68, "frames": 108},
			"back": {"w": 100, "h": 81, "frames": 108},
		},
	},
	109: {
		"": {
			"front": {"w": 91, "h": 59, "frames": 88},
			"back": {"w": 79, "h": 64, "frames": 88},
		},
	},
	110: {
		"": {
			"front": {"w": 86, "h": 67, "frames": 100},
			"back": {"w": 87, "h": 68, "frames": 100},
		},
	},
	638: {
		"": {
			"front": {"w": 57, "h": 79, "frames": 159},
			"back": {"w": 61, "h": 81, "frames": 159},
		},
	},
	805: {
		"": {
			"front": {"w": 94, "h": 92, "frames": 1},
			"back": {"w": 90, "h": 94, "frames": 1},
		},
	},
	863: {
		"": {
			"front": {"w": 49, "h": 60, "frames": 1},
			"back": {"w": 45, "h": 59, "frames": 1},
		},
	},
	884: {
		"": {
			"front": {"w": 61, "h": 75, "frames": 1},
			"back": {"w": 67, "h": 74, "frames": 1},
		},
	},
	1018: {
		"": {
			"front": {"w": 68, "h": 83, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	88: 190, # GRIMER
	89: 75, # MUK
	109: 190, # KOFFING
	110: 60, # WEEZING
	638: 3, # COBALION
	805: 30, # STAKATAKA
	863: 90, # PERRSERKER
	884: 45, # DURALUDON
	1018: 10, # ARCHALUDON
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	88: 2, # MEDIUM_FAST
	89: 2, # MEDIUM_FAST
	109: 2, # MEDIUM_FAST
	110: 2, # MEDIUM_FAST
	638: 4, # SLOW
	805: 4, # SLOW
	863: 2, # MEDIUM_FAST
	884: 2, # MEDIUM_FAST
	1018: 2, # MEDIUM_FAST
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	88: [ # GRIMER
		[1, "pound"],
		[1, "poison_gas"],
		[4, "harden"],
		[7, "mud_slap"],
		[12, "disable"],
		[15, "sludge"],
		[18, "mud_shot"],
		[21, "minimize"],
		[26, "toxic"],
		[29, "sludge_bomb"],
		[32, "sludge_wave"],
		[37, "screech"],
		[40, "gunk_shot"],
		[43, "acid_armor"],
		[46, "belch"],
		[48, "memento"],
	],
	89: [ # MUK
		[1, "pound"],
		[1, "harden"],
		[1, "poison_gas"],
		[1, "mud_slap"],
		[12, "disable"],
		[15, "sludge"],
		[18, "mud_shot"],
		[21, "minimize"],
		[26, "toxic"],
		[29, "sludge_bomb"],
		[32, "sludge_wave"],
		[37, "screech"],
		[40, "gunk_shot"],
		[46, "acid_armor"],
		[52, "belch"],
		[57, "memento"],
	],
	109: [ # KOFFING
		[1, "tackle"],
		[1, "poison_gas"],
		[4, "smog"],
		[8, "smokescreen"],
		[12, "clear_smog"],
		[16, "assurance"],
		[20, "sludge"],
		[24, "haze"],
		[28, "self_destruct"],
		[32, "sludge_bomb"],
		[36, "toxic"],
		[40, "belch"],
		[44, "explosion"],
		[48, "memento"],
		[52, "destiny_bond"],
	],
	110: [ # WEEZING
		[0, "double_hit"],
		[1, "tackle"],
		[1, "smokescreen"],
		[1, "smog"],
		[1, "poison_gas"],
		[1, "heat_wave"],
		[12, "clear_smog"],
		[16, "assurance"],
		[20, "sludge"],
		[24, "haze"],
		[28, "self_destruct"],
		[32, "sludge_bomb"],
		[38, "toxic"],
		[44, "belch"],
		[50, "explosion"],
		[56, "memento"],
		[62, "destiny_bond"],
	],
	638: [ # COBALION
		[1, "leer"],
		[1, "quick_attack"],
		[1, "helping_hand"],
		[1, "work_up"],
		[7, "metal_claw"],
		[14, "quick_guard"],
		[21, "double_kick"],
		[28, "retaliate"],
		[35, "metal_burst"],
		[42, "take_down"],
		[49, "sacred_sword"],
		[56, "swords_dance"],
		[63, "iron_head"],
		[70, "close_combat"],
	],
	805: [ # STAKATAKA
		[1, "tackle"],
		[1, "harden"],
		[5, "rock_throw"],
		[10, "protect"],
		[15, "stomp"],
		[20, "block"],
		[25, "rock_slide"],
		[30, "wide_guard"],
		[35, "autotomize"],
		[40, "rock_blast"],
		[45, "magnet_rise"],
		[50, "iron_defense"],
		[55, "iron_head"],
		[60, "take_down"],
		[65, "stealth_rock"],
		[70, "double_edge"],
	],
	863: [ # PERRSERKER
		[0, "iron_head"],
		[1, "scratch"],
		[1, "growl"],
		[1, "fake_out"],
		[1, "iron_defense"],
		[1, "metal_burst"],
		[1, "hone_claws"],
		[12, "pay_day"],
		[16, "metal_claw"],
		[20, "taunt"],
		[24, "swagger"],
		[31, "fury_swipes"],
		[36, "screech"],
		[42, "slash"],
		[48, "metal_sound"],
		[54, "thrash"],
	],
	884: [ # DURALUDON
		[1, "leer"],
		[1, "metal_claw"],
		[6, "rock_smash"],
		[12, "hone_claws"],
		[18, "metal_sound"],
		[24, "breaking_swipe"],
		[30, "dragon_tail"],
		[36, "iron_defense"],
		[42, "laser_focus"],
		[48, "dragon_claw"],
		[54, "flash_cannon"],
		[60, "metal_burst"],
		[66, "hyper_beam"],
	],
	1018: [ # ARCHALUDON
		[0, "electro_shot"],
		[1, "leer"],
		[1, "metal_claw"],
		[6, "rock_smash"],
		[12, "hone_claws"],
		[18, "metal_sound"],
		[24, "breaking_swipe"],
		[30, "dragon_tail"],
		[36, "iron_defense"],
		[42, "focus_energy"],
		[48, "dragon_claw"],
		[54, "flash_cannon"],
		[60, "metal_burst"],
		[66, "hyper_beam"],
	],
}
