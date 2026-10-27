extends RefCounted
# 只加新文件、**还没接线**：生产还只读 data/pokemon_wild_species.gd（平原）；等地面素材到了再把这份并进去。
# 格式同平原那份：SPECIES / ATLAS / PREVOLUTIONS；六项顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]。
# 图集在 assets/pokemon/temple/（front / back，帧名已按数值排序重编号成 1..N），来源与哈希见该目录 SOURCES.md。

const SPECIES := {
	358: {
		"name": "CHIMECHO",
		"display": "风铃铃",
		"stats": [75, 50, 80, 95, 90, 65],
		"types": ["超能力"],
		"base_exp": 159,
		"base_total": 455,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	433: {
		"name": "CHINGLING",
		"display": "铃铛响",
		"stats": [45, 30, 50, 65, 50, 45],
		"types": ["超能力"],
		"base_exp": 57,
		"base_total": 285,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 358, "pre_form_key": "", "evo_form_key": "", "level": 1, "item": 0, "wild_delay": 0},
		],
	},
	486: {
		"name": "REGIGIGAS",
		"display": "雷吉奇卡斯",
		"stats": [110, 160, 110, 80, 110, 100],
		"types": ["一般"],
		"base_exp": 335,
		"base_total": 670,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	622: {
		"name": "GOLETT",
		"display": "泥偶小人",
		"stats": [59, 74, 50, 35, 50, 35],
		"types": ["地面", "幽灵"],
		"base_exp": 61,
		"base_total": 303,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 623, "pre_form_key": "", "evo_form_key": "", "level": 43, "item": 0, "wild_delay": 0},
		],
	},
	623: {
		"name": "GOLURK",
		"display": "泥偶巨人",
		"stats": [89, 124, 80, 55, 80, 55],
		"types": ["地面", "幽灵"],
		"base_exp": 169,
		"base_total": 483,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	679: {
		"name": "HONEDGE",
		"display": "独剑鞘",
		"stats": [45, 80, 100, 35, 37, 28],
		"types": ["钢", "幽灵"],
		"base_exp": 65,
		"base_total": 325,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [
			{"species_id": 680, "pre_form_key": "", "evo_form_key": "", "level": 35, "item": 0, "wild_delay": 0},
		],
	},
	680: {
		"name": "DOUBLADE",
		"display": "双剑鞘",
		"stats": [59, 110, 150, 45, 49, 35],
		"types": ["钢", "幽灵"],
		"base_exp": 157,
		"base_total": 448,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	681: {
		"name": "AEGISLASH",
		"display": "坚盾剑怪",
		"stats": [60, 50, 140, 50, 140, 60],
		"types": ["钢", "幽灵"],
		"base_exp": 250,
		"base_total": 500,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	720: {
		"name": "HOOPA",
		"display": "胡帕",
		"stats": [80, 110, 60, 150, 130, 70],
		"types": ["超能力", "幽灵"],
		"base_exp": 270,
		"base_total": 600,
		"sub_legendary": false,
		"legendary": false,
		"mythical": true,
		"forms": [],
		"evolutions": [],
	},
	785: {
		"name": "TAPU_KOKO",
		"display": "卡璞・鸣鸣",
		"stats": [70, 115, 85, 95, 75, 130],
		"types": ["电", "妖精"],
		"base_exp": 285,
		"base_total": 570,
		"sub_legendary": true,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	999: {
		"name": "GIMMIGHOUL",
		"display": "索财灵",
		"stats": [45, 30, 70, 75, 70, 10],
		"types": ["幽灵"],
		"base_exp": 60,
		"base_total": 300,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
	1000: {
		"name": "GHOLDENGO",
		"display": "赛富豪",
		"stats": [87, 60, 95, 133, 91, 84],
		"types": ["钢", "幽灵"],
		"base_exp": 275,
		"base_total": 550,
		"sub_legendary": false,
		"legendary": false,
		"mythical": false,
		"forms": [],
		"evolutions": [],
	},
}

const PREVOLUTIONS := {
	358: 433,
	623: 622,
	680: 679,
}

const ATLAS := {
	358: {
		"": {
			"front": {"w": 34, "h": 66, "frames": 108},
			"back": {"w": 35, "h": 66, "frames": 108},
		},
	},
	433: {
		"": {
			"front": {"w": 37, "h": 58, "frames": 168},
			"back": {"w": 42, "h": 60, "frames": 168},
		},
	},
	486: {
		"": {
			"front": {"w": 87, "h": 69, "frames": 156},
			"back": {"w": 93, "h": 71, "frames": 156},
		},
	},
	622: {
		"": {
			"front": {"w": 58, "h": 56, "frames": 86},
			"back": {"w": 56, "h": 59, "frames": 86},
		},
	},
	623: {
		"": {
			"front": {"w": 83, "h": 80, "frames": 170},
			"back": {"w": 78, "h": 80, "frames": 170},
		},
	},
	679: {
		"": {
			"front": {"w": 47, "h": 52, "frames": 1},
			"back": {"w": 47, "h": 55, "frames": 1},
		},
	},
	680: {
		"": {
			"front": {"w": 64, "h": 49, "frames": 1},
			"back": {"w": 80, "h": 58, "frames": 1},
		},
	},
	681: {
		"": {
			"front": {"w": 59, "h": 73, "frames": 1},
			"back": {"w": 53, "h": 70, "frames": 1},
		},
	},
	720: {
		"": {
			"front": {"w": 48, "h": 42, "frames": 1},
			"back": {"w": 49, "h": 44, "frames": 1},
		},
	},
	785: {
		"": {
			"front": {"w": 77, "h": 68, "frames": 1},
			"back": {"w": 69, "h": 67, "frames": 1},
		},
	},
	999: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
	1000: {
		"": {
			"front": {"w": 96, "h": 96, "frames": 1},
			"back": {"w": 96, "h": 96, "frames": 1},
		},
	},
}

# 捕获率（species.json catchRate；接线时并进 data/pokemon_capture_species.gd 的 CATCH_RATES）。
const CATCH_RATES := {
	358: 45, # CHIMECHO
	433: 120, # CHINGLING
	486: 3, # REGIGIGAS
	622: 190, # GOLETT
	623: 90, # GOLURK
	679: 180, # HONEDGE
	680: 90, # DOUBLADE
	681: 45, # AEGISLASH
	720: 3, # HOOPA
	785: 3, # TAPU_KOKO
	999: 45, # GIMMIGHOUL
	1000: 45, # GHOLDENGO
}

# 成长率（原枚举：ERRATIC=0 / FAST=1 / MEDIUM_FAST=2 / MEDIUM_SLOW=3 / SLOW=4 / FLUCTUATING=5；
# 游戏现在只有 1..4 的经验表，0 / 5 要先补表再接线）。
const GROWTH_RATES := {
	358: 1, # FAST
	433: 1, # FAST
	486: 4, # SLOW
	622: 2, # MEDIUM_FAST
	623: 2, # MEDIUM_FAST
	679: 2, # MEDIUM_FAST
	680: 2, # MEDIUM_FAST
	681: 2, # MEDIUM_FAST
	720: 4, # SLOW
	785: 4, # SLOW
	999: 4, # SLOW
	1000: 4, # SLOW
}

# 原学习表（level_moves.json；[等级, 招式小写 id]）。
const LEARNSETS := {
	358: [ # CHIMECHO
		[1, "healing_wish"],
		[1, "wrap"],
		[1, "growl"],
		[1, "astonish"],
		[1, "confusion"],
		[1, "synchronoise"],
		[13, "yawn"],
		[16, "stored_power"],
		[19, "take_down"],
		[22, "extrasensory"],
		[27, "heal_bell"],
		[32, "uproar"],
		[37, "safeguard"],
		[42, "double_edge"],
		[47, "heal_pulse"],
	],
	433: [ # CHINGLING
		[1, "wrap"],
		[1, "psywave"],
		[4, "growl"],
		[7, "astonish"],
		[10, "confusion"],
		[13, "yawn"],
		[16, "last_resort"],
		[19, "entrainment"],
		[32, "uproar"],
	],
	486: [ # REGIGIGAS
		[1, "pound"],
		[1, "confuse_ray"],
		[1, "dizzy_punch"],
		[1, "foresight"],
		[6, "payback"],
		[12, "revenge"],
		[18, "stomp"],
		[24, "protect"],
		[30, "knock_off"],
		[36, "mega_punch"],
		[42, "body_press"],
		[48, "wide_guard"],
		[54, "zen_headbutt"],
		[60, "heavy_slam"],
		[66, "hammer_arm"],
		[72, "giga_impact"],
		[78, "crush_grip"],
	],
	622: [ # GOLETT
		[1, "mud_slap"],
		[1, "astonish"],
		[4, "defense_curl"],
		[8, "pound"],
		[12, "shadow_punch"],
		[16, "curse"],
		[20, "night_shade"],
		[24, "stomping_tantrum"],
		[28, "iron_defense"],
		[32, "mega_punch"],
		[36, "shadow_ball"],
		[40, "heavy_slam"],
		[44, "phantom_force"],
		[48, "hammer_arm"],
		[52, "earthquake"],
		[56, "dynamic_punch"],
	],
	623: [ # GOLURK
		[-1, "mud_slap"],
		[-1, "focus_punch"],
		[1, "pound"],
		[1, "defense_curl"],
		[1, "astonish"],
		[1, "high_horsepower"],
		[12, "shadow_punch"],
		[16, "curse"],
		[20, "night_shade"],
		[24, "stomping_tantrum"],
		[28, "iron_defense"],
		[32, "mega_punch"],
		[36, "shadow_ball"],
		[40, "heavy_slam"],
		[46, "phantom_force"],
		[52, "hammer_arm"],
		[58, "earthquake"],
		[64, "dynamic_punch"],
	],
	679: [ # HONEDGE
		[1, "tackle"],
		[1, "fury_cutter"],
		[4, "shadow_sneak"],
		[8, "autotomize"],
		[12, "aerial_ace"],
		[16, "metal_sound"],
		[20, "slash"],
		[24, "night_slash"],
		[28, "retaliate"],
		[32, "iron_defense"],
		[36, "iron_head"],
		[40, "power_trick"],
		[44, "swords_dance"],
		[48, "sacred_sword"],
	],
	680: [ # DOUBLADE
		[1, "tackle"],
		[1, "fury_cutter"],
		[1, "shadow_sneak"],
		[1, "autotomize"],
		[12, "aerial_ace"],
		[16, "metal_sound"],
		[20, "slash"],
		[24, "night_slash"],
		[28, "retaliate"],
		[32, "iron_defense"],
		[38, "iron_head"],
		[44, "power_trick"],
		[50, "swords_dance"],
		[56, "sacred_sword"],
	],
	681: [ # AEGISLASH
		[0, "kings_shield"],
		[1, "swords_dance"],
		[1, "pursuit"],
		[1, "tackle"],
		[1, "slash"],
		[1, "fury_cutter"],
		[1, "metal_sound"],
		[1, "aerial_ace"],
		[1, "iron_defense"],
		[1, "power_trick"],
		[1, "night_slash"],
		[1, "shadow_sneak"],
		[1, "iron_head"],
		[1, "head_smash"],
		[1, "autotomize"],
		[1, "retaliate"],
		[1, "sacred_sword"],
	],
	720: [ # HOOPA
		[1, "confusion"],
		[1, "destiny_bond"],
		[1, "ally_switch"],
		[6, "astonish"],
		[10, "trick"],
		[15, "light_screen"],
		[19, "psybeam"],
		[25, "skill_swap"],
		[29, "guard_split"],
		[29, "power_split"],
		[35, "phantom_force"],
		[46, "zen_headbutt"],
		[50, "trick_room"],
		[50, "wonder_room"],
		[55, "shadow_ball"],
		[68, "nasty_plot"],
		[75, "psychic"],
		[85, "hyperspace_hole"],
	],
	785: [ # TAPU_KOKO
		[1, "thunder_shock"],
		[1, "quick_attack"],
		[5, "withdraw"],
		[10, "fairy_wind"],
		[15, "false_swipe"],
		[20, "spark"],
		[25, "shock_wave"],
		[30, "charge"],
		[35, "agility"],
		[40, "screech"],
		[45, "discharge"],
		[50, "mean_look"],
		[55, "natures_madness"],
		[60, "wild_charge"],
		[65, "brave_bird"],
		[70, "power_swap"],
		[75, "electric_terrain"],
	],
	999: [ # GIMMIGHOUL
		[1, "tackle"],
		[1, "astonish"],
	],
	1000: [ # GHOLDENGO
		[1, "tackle"],
		[1, "astonish"],
		[7, "night_shade"],
		[14, "confuse_ray"],
		[21, "substitute"],
		[28, "metal_sound"],
		[35, "shadow_ball"],
		[42, "recover"],
		[49, "power_gem"],
		[56, "make_it_rain"],
		[63, "nasty_plot"],
		[70, "memento"],
	],
}
