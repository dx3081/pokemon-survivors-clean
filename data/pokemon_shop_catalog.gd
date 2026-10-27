extends RefCounted
#
# 只读源（静态文本切片，不执行整包、不 eval 任何 source 表达式）：
#   SHA256 = d3d97fe1acedd66094c3801b1ed13381eb0fa5ae0f64fdb7febe581adeec955c
#     5 原块：tiers / factories / player_rewards / source_shop / pool_mapping
#     原 ModifierType / Modifier 类的 hash+offset 切片（含 apply / getMaxStackCount / value）。
#
# 本文件只做**原商品目录与纯查询**：76 个原 PLAYER 奖励池 occurrence（COMMON 10 / GREAT 20 /
# ULTRA 20 / ROGUE 19 / MASTER 7），保留原顺序、source ID、原 tier、工厂 raw、原 weight 与
# 出现条件原表达式（一律字符串，绝不 eval）。
#
# 本作 placement / category / availability 与原资料分开记录：
#   - 局内只上药 / 球（PLACE_IN_RUN）；
#   - 原“每波奖励的局中培养”接局外（PLACE_TOWN_POKEMON / PLACE_TOWN_GLOBAL）；
#   - 缺系统的条目如实标 PLACE_DEFERRED + 原因，不删源记录、不发明效果。
# 本段所有条目都只是目录：`purchasable` 一律 false，未接任何消费 / 存档 / 药效 / 捕捉。
# Rogue 原 money shop cost 不是本作 point cost：本文件不写任何点价，档位只留作以后点价依据。
#
# 完整来源、逐条依据、全局项 class 定位与待适配边界见 `data/POKEMON_SHOP_SOURCE.md`。

# 原稀有度枚举 `oe`（tiers 原块）：
#   COMMON=0 GREAT=1 ULTRA=2 ROGUE=3 MASTER=4 LUXURY=5
# PLAYER 奖励池 ah 只有 0..4 五档；LUXURY=5 在原 enum 里存在但没有该奖励档，本文件同样不加。
const TIER_COMMON := 0
const TIER_GREAT := 1
const TIER_ULTRA := 2
const TIER_ROGUE := 3
const TIER_MASTER := 4
const TIER_LUXURY := 5

const TIER_NAMES := {
	TIER_COMMON: "COMMON",
	TIER_GREAT: "GREAT",
	TIER_ULTRA: "ULTRA",
	TIER_ROGUE: "ROGUE",
	TIER_MASTER: "MASTER",
	TIER_LUXURY: "LUXURY",
}

const TIER_OCCURRENCE_COUNTS := {
	TIER_COMMON: 10,
	TIER_GREAT: 20,
	TIER_ULTRA: 20,
	TIER_ROGUE: 19,
	TIER_MASTER: 7,
}
const OCCURRENCE_TOTAL := 76

# ---- 本作落位（与原资料分开）----
const PLACE_IN_RUN := 0        # 局内商店（本作只药 / 球）
const PLACE_TOWN_POKEMON := 1  # 局外·单只培养
const PLACE_TOWN_GLOBAL := 2   # 局外·全体效果
const PLACE_DEFERRED := 3      # 缺适配系统，本段不接

const PLACE_NAMES := {
	PLACE_IN_RUN: "IN_RUN",
	PLACE_TOWN_POKEMON: "TOWN_POKEMON",
	PLACE_TOWN_GLOBAL: "TOWN_GLOBAL",
	PLACE_DEFERRED: "DEFERRED",
}

# ---- 上架状态（本段一律 purchasable=false）----
const SALE_PLANNED := 0             # 已有落位，等下一段接线
const SALE_ADAPTATION_PENDING := 1  # 原效果与本作需求不同，待适配，不能自造数值
const SALE_REMOVED_BY_USER := 2     # 用户明确删除（RARER_CANDY）
const SALE_DEFERRED := 3            # 缺系统 / 无适配

const SALE_NAMES := {
	SALE_PLANNED: "PLANNED",
	SALE_ADAPTATION_PENDING: "ADAPTATION_PENDING",
	SALE_REMOVED_BY_USER: "REMOVED_BY_USER",
	SALE_DEFERRED: "DEFERRED",
}

# ---- 原效果作用对象 ----
const SCOPE_RUN_CONSUMABLE := 0  # 这一局用掉的消耗品
const SCOPE_ONE_POKEMON := 1     # 只作用于某一只
const SCOPE_HELD_POKEMON := 2    # 单只携带道具（需持物系统）
const SCOPE_PARTY := 3           # 原作用于整队（本作不做队伍）
const SCOPE_ALL_POKEMON := 4     # 全局持久，对所有宝可梦生效
const SCOPE_SAVE_META := 5       # 存档 / 元进度
const SCOPE_MONEY := 6           # 原金钱
const SCOPE_UNSUPPORTED := 7     # 无对应系统

const SCOPE_NAMES := {
	SCOPE_RUN_CONSUMABLE: "RUN_CONSUMABLE",
	SCOPE_ONE_POKEMON: "ONE_POKEMON",
	SCOPE_HELD_POKEMON: "HELD_POKEMON",
	SCOPE_PARTY: "PARTY",
	SCOPE_ALL_POKEMON: "ALL_POKEMON",
	SCOPE_SAVE_META: "SAVE_META",
	SCOPE_MONEY: "MONEY",
	SCOPE_UNSUPPORTED: "UNSUPPORTED",
}

# 原 PLAYER 奖励池 76 个 occurrence，顺序 = 原块 `ah` 里 COMMON→GREAT→ULTRA→ROGUE→MASTER 的
# 出现顺序。每条：
#   [source_id, tier, weight_expr, condition_expr, max_weight_expr, source_expr]
# 其中 `weight_expr` 是 `new Ge(工厂, weight, maxWeight)` 的静态 weight（函数时为 ""），
# `condition_expr` 是动态 weight 函数原文（静态时为 ""），`max_weight_expr` 是第三参原文，
# `source_expr` 是原 reward 条目的完整表达式。全部按源字符串保留，不执行。
const OCCURRENCES := [
	["POKEBALL", TIER_COMMON, "6", "", "", "new Ge(Te.POKEBALL,6)"],
	["RARE_CANDY", TIER_COMMON, "2", "", "", "new Ge(Te.RARE_CANDY,2)"],
	["POTION", TIER_COMMON, "", "i=>Math.min(i.filter(n=>(n.getInverseHp()>=10||n.getHpRatio()<=.875)&&!n.isFainted()).length,3)*3", "9", "new Ge(Te.POTION,i=>Math.min(i.filter(n=>(n.getInverseHp()>=10||n.getHpRatio()<=.875)&&!n.isFainted()).length,3)*3,9)"],
	["SUPER_POTION", TIER_COMMON, "", "i=>Math.min(i.filter(n=>(n.getInverseHp()>=25||n.getHpRatio()<=.75)&&!n.isFainted()).length,3)", "3", "new Ge(Te.SUPER_POTION,i=>Math.min(i.filter(n=>(n.getInverseHp()>=25||n.getHpRatio()<=.75)&&!n.isFainted()).length,3),3)"],
	["ETHER", TIER_COMMON, "", "i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)*3", "9", "new Ge(Te.ETHER,i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)*3,9)"],
	["MAX_ETHER", TIER_COMMON, "", "i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)", "3", "new Ge(Te.MAX_ETHER,i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3),3)"],
	["LURE", TIER_COMMON, "2", "", "", "new Ge(Te.LURE,2)"],
	["TEMP_STAT_BOOSTER", TIER_COMMON, "4", "", "", "new Ge(Te.TEMP_STAT_BOOSTER,4)"],
	["BERRY", TIER_COMMON, "2", "", "", "new Ge(Te.BERRY,2)"],
	["TM_COMMON", TIER_COMMON, "1", "", "", "new Ge(Te.TM_COMMON,1)"],
	["GREAT_BALL", TIER_GREAT, "6", "", "", "new Ge(Te.GREAT_BALL,6)"],
	["FULL_HEAL", TIER_GREAT, "", "i=>Math.min(i.filter(n=>n.hp&&!!n.status).length,3)*6", "18", "new Ge(Te.FULL_HEAL,i=>Math.min(i.filter(n=>n.hp&&!!n.status).length,3)*6,18)"],
	["REVIVE", TIER_GREAT, "", "i=>Math.min(i.filter(n=>n.isFainted()).length,3)*9", "27", "new Ge(Te.REVIVE,i=>Math.min(i.filter(n=>n.isFainted()).length,3)*9,27)"],
	["MAX_REVIVE", TIER_GREAT, "", "i=>Math.min(i.filter(n=>n.isFainted()).length,3)*3", "9", "new Ge(Te.MAX_REVIVE,i=>Math.min(i.filter(n=>n.isFainted()).length,3)*3,9)"],
	["SACRED_ASH", TIER_GREAT, "", "i=>i.filter(t=>t.isFainted()).length>=Math.ceil(i.length/2)?1:0", "1", "new Ge(Te.SACRED_ASH,i=>i.filter(t=>t.isFainted()).length>=Math.ceil(i.length/2)?1:0,1)"],
	["HYPER_POTION", TIER_GREAT, "", "i=>Math.min(i.filter(n=>(n.getInverseHp()>=100||n.getHpRatio()<=.625)&&!n.isFainted()).length,3)*3", "9", "new Ge(Te.HYPER_POTION,i=>Math.min(i.filter(n=>(n.getInverseHp()>=100||n.getHpRatio()<=.625)&&!n.isFainted()).length,3)*3,9)"],
	["MAX_POTION", TIER_GREAT, "", "i=>Math.min(i.filter(n=>(n.getInverseHp()>=150||n.getHpRatio()<=.5)&&!n.isFainted()).length,3)", "3", "new Ge(Te.MAX_POTION,i=>Math.min(i.filter(n=>(n.getInverseHp()>=150||n.getHpRatio()<=.5)&&!n.isFainted()).length,3),3)"],
	["FULL_RESTORE", TIER_GREAT, "", "i=>{const t=Math.min(i.filter(r=>r.hp&&!!r.status).length,3);return Math.floor((Math.min(i.filter(r=>(r.getInverseHp()>=150||r.getHpRatio()<=.5)&&!r.isFainted()).length,3)+t)/2)}", "3", "new Ge(Te.FULL_RESTORE,i=>{const t=Math.min(i.filter(r=>r.hp&&!!r.status).length,3);return Math.floor((Math.min(i.filter(r=>(r.getInverseHp()>=150||r.getHpRatio()<=.5)&&!r.isFainted()).length,3)+t)/2)},3)"],
	["ELIXIR", TIER_GREAT, "", "i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)*3", "9", "new Ge(Te.ELIXIR,i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)*3,9)"],
	["MAX_ELIXIR", TIER_GREAT, "", "i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3)", "3", "new Ge(Te.MAX_ELIXIR,i=>Math.min(i.filter(n=>n.hp&&n.getMoveset().filter(r=>r.getMovePp()-r.ppUsed<=5).length).length,3),3)"],
	["DIRE_HIT", TIER_GREAT, "4", "", "", "new Ge(Te.DIRE_HIT,4)"],
	["SUPER_LURE", TIER_GREAT, "4", "", "", "new Ge(Te.SUPER_LURE,4)"],
	["NUGGET", TIER_GREAT, "5", "", "", "new Ge(Te.NUGGET,5)"],
	["EVOLUTION_ITEM", TIER_GREAT, "", "i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/15),8)", "8", "new Ge(Te.EVOLUTION_ITEM,i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/15),8),8)"],
	["MAP", TIER_GREAT, "", "i=>i[0].scene.gameMode.isClassic?1:0", "1", "new Ge(Te.MAP,i=>i[0].scene.gameMode.isClassic?1:0,1)"],
	["TM_GREAT", TIER_GREAT, "2", "", "", "new Ge(Te.TM_GREAT,2)"],
	["MEMORY_MUSHROOM", TIER_GREAT, "", "i=>{if(!i.find(n=>n.getLearnableLevelMoves().length))return 0;const t=i.map(n=>n.level).reduce((n,r)=>Math.max(n,r),1);return Math.min(Math.ceil(t/20),4)}", "4", "new Ge(Te.MEMORY_MUSHROOM,i=>{if(!i.find(n=>n.getLearnableLevelMoves().length))return 0;const t=i.map(n=>n.level).reduce((n,r)=>Math.max(n,r),1);return Math.min(Math.ceil(t/20),4)},4)"],
	["BASE_STAT_BOOSTER", TIER_GREAT, "3", "", "", "new Ge(Te.BASE_STAT_BOOSTER,3)"],
	["TERA_SHARD", TIER_GREAT, "1", "", "", "new Ge(Te.TERA_SHARD,1)"],
	["DNA_SPLICERS", TIER_GREAT, "", "i=>i[0].scene.gameMode.isSplicedOnly&&i.filter(t=>!t.fusionSpecies).length>1?4:0", "", "new Ge(Te.DNA_SPLICERS,i=>i[0].scene.gameMode.isSplicedOnly&&i.filter(t=>!t.fusionSpecies).length>1?4:0)"],
	["ULTRA_BALL", TIER_ULTRA, "24", "", "", "new Ge(Te.ULTRA_BALL,24)"],
	["MAX_LURE", TIER_ULTRA, "4", "", "", "new Ge(Te.MAX_LURE,4)"],
	["BIG_NUGGET", TIER_ULTRA, "12", "", "", "new Ge(Te.BIG_NUGGET,12)"],
	["PP_UP", TIER_ULTRA, "9", "", "", "new Ge(Te.PP_UP,9)"],
	["PP_MAX", TIER_ULTRA, "3", "", "", "new Ge(Te.PP_MAX,3)"],
	["MINT", TIER_ULTRA, "4", "", "", "new Ge(Te.MINT,4)"],
	["RARE_EVOLUTION_ITEM", TIER_ULTRA, "", "i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/15)*4,32)", "32", "new Ge(Te.RARE_EVOLUTION_ITEM,i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/15)*4,32),32)"],
	["AMULET_COIN", TIER_ULTRA, "3", "", "", "new Ge(Te.AMULET_COIN,3)"],
	["REVIVER_SEED", TIER_ULTRA, "4", "", "", "new Ge(Te.REVIVER_SEED,4)"],
	["CANDY_JAR", TIER_ULTRA, "5", "", "", "new Ge(Te.CANDY_JAR,5)"],
	["ATTACK_TYPE_BOOSTER", TIER_ULTRA, "10", "", "", "new Ge(Te.ATTACK_TYPE_BOOSTER,10)"],
	["TM_ULTRA", TIER_ULTRA, "8", "", "", "new Ge(Te.TM_ULTRA,8)"],
	["RARER_CANDY", TIER_ULTRA, "4", "", "", "new Ge(Te.RARER_CANDY,4)"],
	["GOLDEN_PUNCH", TIER_ULTRA, "2", "", "", "new Ge(Te.GOLDEN_PUNCH,2)"],
	["IV_SCANNER", TIER_ULTRA, "4", "", "", "new Ge(Te.IV_SCANNER,4)"],
	["EXP_CHARM", TIER_ULTRA, "8", "", "", "new Ge(Te.EXP_CHARM,8)"],
	["EXP_SHARE", TIER_ULTRA, "12", "", "", "new Ge(Te.EXP_SHARE,12)"],
	["EXP_BALANCE", TIER_ULTRA, "4", "", "", "new Ge(Te.EXP_BALANCE,4)"],
	["TERA_ORB", TIER_ULTRA, "", "i=>Math.min(Math.max(Math.floor(i[0].scene.currentBattle.waveIndex/50)*2,1),4)", "4", "new Ge(Te.TERA_ORB,i=>Math.min(Math.max(Math.floor(i[0].scene.currentBattle.waveIndex/50)*2,1),4),4)"],
	["VOUCHER", TIER_ULTRA, "", "(i,t)=>i[0].scene.gameMode.isDaily?0:Math.max(3-t,0)", "3", "new Ge(Te.VOUCHER,(i,t)=>i[0].scene.gameMode.isDaily?0:Math.max(3-t,0),3)"],
	["ROGUE_BALL", TIER_ROGUE, "24", "", "", "new Ge(Te.ROGUE_BALL,24)"],
	["RELIC_GOLD", TIER_ROGUE, "2", "", "", "new Ge(Te.RELIC_GOLD,2)"],
	["LEFTOVERS", TIER_ROGUE, "3", "", "", "new Ge(Te.LEFTOVERS,3)"],
	["SHELL_BELL", TIER_ROGUE, "3", "", "", "new Ge(Te.SHELL_BELL,3)"],
	["BERRY_POUCH", TIER_ROGUE, "4", "", "", "new Ge(Te.BERRY_POUCH,4)"],
	["GRIP_CLAW", TIER_ROGUE, "5", "", "", "new Ge(Te.GRIP_CLAW,5)"],
	["WIDE_LENS", TIER_ROGUE, "4", "", "", "new Ge(Te.WIDE_LENS,4)"],
	["BATON", TIER_ROGUE, "2", "", "", "new Ge(Te.BATON,2)"],
	["SOUL_DEW", TIER_ROGUE, "8", "", "", "new Ge(Te.SOUL_DEW,8)"],
	["SOOTHE_BELL", TIER_ROGUE, "4", "", "", "new Ge(Te.SOOTHE_BELL,4)"],
	["ABILITY_CHARM", TIER_ROGUE, "6", "", "", "new Ge(Te.ABILITY_CHARM,6)"],
	["FOCUS_BAND", TIER_ROGUE, "5", "", "", "new Ge(Te.FOCUS_BAND,5)"],
	["QUICK_CLAW", TIER_ROGUE, "3", "", "", "new Ge(Te.QUICK_CLAW,3)"],
	["KINGS_ROCK", TIER_ROGUE, "3", "", "", "new Ge(Te.KINGS_ROCK,3)"],
	["LOCK_CAPSULE", TIER_ROGUE, "3", "", "", "new Ge(Te.LOCK_CAPSULE,3)"],
	["SUPER_EXP_CHARM", TIER_ROGUE, "10", "", "", "new Ge(Te.SUPER_EXP_CHARM,10)"],
	["FORM_CHANGE_ITEM", TIER_ROGUE, "18", "", "", "new Ge(Te.FORM_CHANGE_ITEM,18)"],
	["MEGA_BRACELET", TIER_ROGUE, "", "i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/50),4)*8", "32", "new Ge(Te.MEGA_BRACELET,i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/50),4)*8,32)"],
	["DYNAMAX_BAND", TIER_ROGUE, "", "i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/50),4)*8", "32", "new Ge(Te.DYNAMAX_BAND,i=>Math.min(Math.ceil(i[0].scene.currentBattle.waveIndex/50),4)*8,32)"],
	["MASTER_BALL", TIER_MASTER, "24", "", "", "new Ge(Te.MASTER_BALL,24)"],
	["SHINY_CHARM", TIER_MASTER, "14", "", "", "new Ge(Te.SHINY_CHARM,14)"],
	["HEALING_CHARM", TIER_MASTER, "18", "", "", "new Ge(Te.HEALING_CHARM,18)"],
	["MULTI_LENS", TIER_MASTER, "18", "", "", "new Ge(Te.MULTI_LENS,18)"],
	["VOUCHER_PLUS", TIER_MASTER, "", "(i,t)=>i[0].scene.gameMode.isDaily?0:Math.max(9-t*3,0)", "9", "new Ge(Te.VOUCHER_PLUS,(i,t)=>i[0].scene.gameMode.isDaily?0:Math.max(9-t*3,0),9)"],
	["DNA_SPLICERS", TIER_MASTER, "", "i=>!i[0].scene.gameMode.isSplicedOnly&&i.filter(t=>!t.fusionSpecies).length>1?24:0", "24", "new Ge(Te.DNA_SPLICERS,i=>!i[0].scene.gameMode.isSplicedOnly&&i.filter(t=>!t.fusionSpecies).length>1?24:0,24)"],
	["MINI_BLACK_HOLE", TIER_MASTER, "", "i=>i[0].scene.gameData.unlocks[Qn.MINI_BLACK_HOLE]?1:0", "1", "new Ge(Te.MINI_BLACK_HOLE,i=>i[0].scene.gameData.unlocks[Qn.MINI_BLACK_HOLE]?1:0,1)"],
]

# 原工厂 `Te` 的 raw body（仅 PLAYER 池用到的 75 个 source ID）。
const FACTORIES := {
	"POKEBALL": '()=>new iu("pb",ya.POKEBALL,5)',
	"RARE_CANDY": '()=>new qP("modifierType:ModifierType.RARE_CANDY","rare_candy")',
	"POTION": '()=>new il("modifierType:ModifierType.POTION","potion",20,10)',
	"SUPER_POTION": '()=>new il("modifierType:ModifierType.SUPER_POTION","super_potion",50,25)',
	"ETHER": '()=>new gR("modifierType:ModifierType.ETHER","ether",10)',
	"MAX_ETHER": '()=>new gR("modifierType:ModifierType.MAX_ETHER","max_ether",-1)',
	"LURE": '()=>new kc("modifierType:ModifierType.LURE","lure",5)',
	"TEMP_STAT_BOOSTER": '()=>new Rn((i,t)=>{if(t)return new Vc(t[0]);const n=Ze(6);return new Vc(n)})',
	"BERRY": '()=>new Rn((i,t)=>{if(t)return new OL(t[0]);const n=xt(Al);let r,l=Ze(12);return l<2?r=Al.SITRUS:l<4?r=Al.LUM:l<6?r=Al.LEPPA:r=n[Ze(n.length-3)+2],new OL(r)})',
	"TM_COMMON": '()=>new Xc(oe.COMMON)',
	"GREAT_BALL": '()=>new iu("gb",ya.GREAT_BALL,5)',
	"FULL_HEAL": '()=>new JP("modifierType:ModifierType.FULL_HEAL","full_heal")',
	"REVIVE": '()=>new EL("modifierType:ModifierType.REVIVE","revive",50)',
	"MAX_REVIVE": '()=>new EL("modifierType:ModifierType.MAX_REVIVE","max_revive",100)',
	"SACRED_ASH": '()=>new tD("modifierType:ModifierType.SACRED_ASH","sacred_ash")',
	"HYPER_POTION": '()=>new il("modifierType:ModifierType.HYPER_POTION","hyper_potion",200,50)',
	"MAX_POTION": '()=>new il("modifierType:ModifierType.MAX_POTION","max_potion",0,100)',
	"FULL_RESTORE": '()=>new il("modifierType:ModifierType.FULL_RESTORE","full_restore",0,100,!0)',
	"ELIXIR": '()=>new cL("modifierType:ModifierType.ELIXIR","elixir",10)',
	"MAX_ELIXIR": '()=>new cL("modifierType:ModifierType.MAX_ELIXIR","max_elixir",-1)',
	"DIRE_HIT": '()=>new Vc($p.CRIT)',
	"SUPER_LURE": '()=>new kc("modifierType:ModifierType.SUPER_LURE","super_lure",10)',
	"NUGGET": '()=>new zc("modifierType:ModifierType.NUGGET","nugget",1,"modifierType:ModifierType.MoneyRewardModifierType.extra.small")',
	"EVOLUTION_ITEM": '()=>new NL(!1)',
	"MAP": '()=>new bt("modifierType:ModifierType.MAP","map",(i,t)=>new HR(i))',
	"TM_GREAT": '()=>new Xc(oe.GREAT)',
	"MEMORY_MUSHROOM": '()=>new RL("modifierType:ModifierType.MEMORY_MUSHROOM","big_mushroom")',
	"BASE_STAT_BOOSTER": '()=>new Rn((i,t)=>{if(t){const r=t[0];return new IL(a7(r),r)}const n=Ze(6);return new IL(a7(n),n)})',
	"TERA_SHARD": '()=>new Rn((i,t)=>{if(t)return new pL(t[0]);if(!i[0].scene.getModifiers(FR).length)return null;let n;if(Ze(3))n=Ze(64)?Ze(18):S.STELLAR;else{const r=i.map(l=>l.getTypes(!1,!1,!0)).flat();n=Pi(r)}return new pL(n)})',
	"DNA_SPLICERS": '()=>new mL("modifierType:ModifierType.DNA_SPLICERS","dna_splicers")',
	"ULTRA_BALL": '()=>new iu("ub",ya.ULTRA_BALL,5)',
	"MAX_LURE": '()=>new kc("modifierType:ModifierType.MAX_LURE","max_lure",25)',
	"BIG_NUGGET": '()=>new zc("modifierType:ModifierType.BIG_NUGGET","big_nugget",2.5,"modifierType:ModifierType.MoneyRewardModifierType.extra.moderate")',
	"PP_UP": '()=>new PR("modifierType:ModifierType.PP_UP","pp_up",1)',
	"PP_MAX": '()=>new PR("modifierType:ModifierType.PP_MAX","pp_max",3)',
	"MINT": '()=>new Rn((i,t)=>t?new dL(t[0]):new dL(Ze(xt(jt).length)))',
	"RARE_EVOLUTION_ITEM": '()=>new NL(!0)',
	"AMULET_COIN": '()=>new bt("modifierType:ModifierType.AMULET_COIN","amulet_coin",(i,t)=>new Cl(i))',
	"REVIVER_SEED": '()=>new za("modifierType:ModifierType.REVIVER_SEED","reviver_seed",(i,t)=>new VR(i,t[0].id))',
	"CANDY_JAR": '()=>new bt("modifierType:ModifierType.CANDY_JAR","candy_jar",(i,t)=>new YR(i))',
	"ATTACK_TYPE_BOOSTER": '()=>new sD',
	"TM_ULTRA": '()=>new Xc(oe.ULTRA)',
	"RARER_CANDY": '()=>new jP("modifierType:ModifierType.RARER_CANDY","rarer_candy")',
	"GOLDEN_PUNCH": '()=>new za("modifierType:ModifierType.GOLDEN_PUNCH","golden_punch",(i,t)=>new tO(i,t[0].id))',
	"IV_SCANNER": '()=>new bt("modifierType:ModifierType.IV_SCANNER","scanner",(i,t)=>new oO(i))',
	"EXP_CHARM": '()=>new Zc("modifierType:ModifierType.EXP_CHARM","exp_charm",25)',
	"EXP_SHARE": '()=>new bt("modifierType:ModifierType.EXP_SHARE","exp_share",(i,t)=>new JR(i))',
	"EXP_BALANCE": '()=>new bt("modifierType:ModifierType.EXP_BALANCE","exp_balance",(i,t)=>new qR(i))',
	"TERA_ORB": '()=>new bt("modifierType:ModifierType.TERA_ORB","tera_orb",(i,t)=>new FR(i))',
	"VOUCHER": '()=>new Yc(va.REGULAR,-1)',
	"ROGUE_BALL": '()=>new iu("rb",ya.ROGUE_BALL,5)',
	"RELIC_GOLD": '()=>new zc("modifierType:ModifierType.RELIC_GOLD","relic_gold",10,"modifierType:ModifierType.MoneyRewardModifierType.extra.large")',
	"LEFTOVERS": '()=>new za("modifierType:ModifierType.LEFTOVERS","leftovers",(i,t)=>new KR(i,t[0].id))',
	"SHELL_BELL": '()=>new za("modifierType:ModifierType.SHELL_BELL","shell_bell",(i,t)=>new WR(i,t[0].id))',
	"BERRY_POUCH": '()=>new bt("modifierType:ModifierType.BERRY_POUCH","berry_pouch",(i,t)=>new kR(i))',
	"GRIP_CLAW": '()=>new oD("modifierType:ModifierType.GRIP_CLAW","grip_claw",10)',
	"WIDE_LENS": '()=>new iD("modifierType:ModifierType.WIDE_LENS","wide_lens",5)',
	"BATON": '()=>new za("modifierType:ModifierType.BATON","stick",(i,t)=>new dl(i,t[0].id))',
	"SOUL_DEW": '()=>new za("modifierType:ModifierType.SOUL_DEW","soul_dew",(i,t)=>new jR(i,t[0].id))',
	"SOOTHE_BELL": '()=>new aD("modifierType:ModifierType.SOOTHE_BELL","soothe_bell")',
	"ABILITY_CHARM": '()=>new bt("modifierType:ModifierType.ABILITY_CHARM","ability_charm",(i,t)=>new Vh(i))',
	"FOCUS_BAND": '()=>new za("modifierType:ModifierType.FOCUS_BAND","focus_band",(i,t)=>new wR(i,t[0].id))',
	"QUICK_CLAW": '()=>new za("modifierType:ModifierType.QUICK_CLAW","quick_claw",(i,t)=>new bR(i,t[0].id))',
	"KINGS_ROCK": '()=>new za("modifierType:ModifierType.KINGS_ROCK","kings_rock",(i,t)=>new Wu(i,t[0].id))',
	"LOCK_CAPSULE": '()=>new bt("modifierType:ModifierType.LOCK_CAPSULE","lock_capsule",(i,t)=>new nO(i))',
	"SUPER_EXP_CHARM": '()=>new Zc("modifierType:ModifierType.SUPER_EXP_CHARM","super_exp_charm",60)',
	"FORM_CHANGE_ITEM": '()=>new rD',
	"MEGA_BRACELET": '()=>new bt("modifierType:ModifierType.MEGA_BRACELET","mega_bracelet",(i,t)=>new BR(i))',
	"DYNAMAX_BAND": '()=>new bt("modifierType:ModifierType.DYNAMAX_BAND","dynamax_band",(i,t)=>new yR(i))',
	"MASTER_BALL": '()=>new iu("mb",ya.MASTER_BALL,1)',
	"SHINY_CHARM": '()=>new bt("modifierType:ModifierType.SHINY_CHARM","shiny_charm",(i,t)=>new iO(i))',
	"HEALING_CHARM": '()=>new bt("modifierType:ModifierType.HEALING_CHARM","healing_charm",(i,t)=>new Wh(i,1.1))',
	"MULTI_LENS": '()=>new nD("modifierType:ModifierType.MULTI_LENS","zoom_lens")',
	"VOUCHER_PLUS": '()=>new Yc(va.PLUS,-1)',
	"MINI_BLACK_HOLE": '()=>new lD("modifierType:ModifierType.MINI_BLACK_HOLE","mini_black_hole")',
}

# 每个 source ID 的原工厂 class / 原 ModifierType / 原生成 Modifier class / 本作落位。
const SOURCE_INFO := {
	"POKEBALL": {"zh": "精灵球", "i18n": "", "factory_class": "iu", "type_class": "AddPokeballModifierType", "modifier_class": "AddPokeballModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "ball", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "count=5", "adaptation": "", "deferred": ""},
	"RARE_CANDY": {"zh": "神奇糖果", "i18n": "modifierType:ModifierType.RARE_CANDY", "factory_class": "qP", "type_class": "PokemonLevelIncrementModifierType", "modifier_class": "PokemonLevelIncrementModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_POKEMON, "category": "candy", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "level+1", "adaptation": "原作用：对选中的一只 +1 级（并经 CANDY_JAR 的 LevelIncrementBoosterModifier 加值）；用户要的是局外给该物种开局加等级，等价关系未定，不能自造倍率。", "deferred": ""},
	"POTION": {"zh": "伤药", "i18n": "modifierType:ModifierType.POTION", "factory_class": "il", "type_class": "PokemonHpRestoreModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "restorePoints=20, restorePercent=10", "adaptation": "", "deferred": ""},
	"SUPER_POTION": {"zh": "好伤药", "i18n": "modifierType:ModifierType.SUPER_POTION", "factory_class": "il", "type_class": "PokemonHpRestoreModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "restorePoints=50, restorePercent=25", "adaptation": "", "deferred": ""},
	"ETHER": {"zh": "PP单项小补剂", "i18n": "modifierType:ModifierType.ETHER", "factory_class": "gR", "type_class": "PokemonPpRestoreModifierType", "modifier_class": "PokemonPpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "pp_restore", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePoints=10", "adaptation": "", "deferred": "用户本作局内商店只上药 / 球；原 PP 回复消耗品暂无货架。"},
	"MAX_ETHER": {"zh": "PP单项全补剂", "i18n": "modifierType:ModifierType.MAX_ETHER", "factory_class": "gR", "type_class": "PokemonPpRestoreModifierType", "modifier_class": "PokemonPpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "pp_restore", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePoints=-1 (fully)", "adaptation": "", "deferred": "同上：局内只药 / 球，原 PP 全补无货架。"},
	"LURE": {"zh": "引虫香水", "i18n": "modifierType:ModifierType.LURE", "factory_class": "kc", "type_class": "DoubleBattleChanceBoosterModifierType", "modifier_class": "DoubleBattleChanceBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "lure", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "battles=5", "adaptation": "", "deferred": "原作用是把双打概率减半（value=ceil(value/2)）；本作不做双打，无适配系统。"},
	"TEMP_STAT_BOOSTER": {"zh": "战斗增强（随机）", "i18n": "", "factory_class": "Rn", "type_class": "TempBattleStatBoosterModifierType", "modifier_class": "TempBattleStatBoosterModifier", "generator": true, "generates": "TempBattleStatBoosterModifierType (random of 6 temp battle stats)", "placement": PLACE_DEFERRED, "category": "temp_battle", "scope": SCOPE_ONE_POKEMON, "sale": SALE_DEFERRED, "value": "temp stat +1, battles=5", "adaptation": "", "deferred": "原作是回合制里的临时战斗能力等级；本作实时制没有对应回合窗口。"},
	"BERRY": {"zh": "树果（随机）", "i18n": "", "factory_class": "Rn", "type_class": "BerryModifierType", "modifier_class": "BerryModifier", "generator": true, "generates": "BerryModifierType (random berry, SITRUS/LUM/LEPPA weighted)", "placement": PLACE_DEFERRED, "category": "berry", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "random berry", "adaptation": "", "deferred": "携带道具 / 树果系统未实现（list.md“携带道具·以后再说”）。"},
	"TM_COMMON": {"zh": "技能机器（普通档）", "i18n": "", "factory_class": "Xc", "type_class": "TmModifierTypeGenerator", "modifier_class": "TmModifierType", "generator": true, "generates": "TmModifierType for one compatible unlearned TM of tier COMMON", "placement": PLACE_TOWN_POKEMON, "category": "tm", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "tier=COMMON", "adaptation": "原 TM 三档（COMMON/GREAT/ULTRA）按原分档保留；只留分档与生成器，兼容性与真正学招留后项。", "deferred": ""},
	"GREAT_BALL": {"zh": "超级球", "i18n": "", "factory_class": "iu", "type_class": "AddPokeballModifierType", "modifier_class": "AddPokeballModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "ball", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "count=5", "adaptation": "", "deferred": ""},
	"FULL_HEAL": {"zh": "万灵药", "i18n": "modifierType:ModifierType.FULL_HEAL", "factory_class": "JP", "type_class": "PokemonStatusHealModifierType", "modifier_class": "PokemonStatusHealModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "heal status", "adaptation": "", "deferred": ""},
	"REVIVE": {"zh": "活力碎片", "i18n": "modifierType:ModifierType.REVIVE", "factory_class": "EL", "type_class": "PokemonReviveModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "revive", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePercent=50", "adaptation": "", "deferred": "原作复活队员需要队伍 / 濒死系统，本作不做队伍。"},
	"MAX_REVIVE": {"zh": "活力块", "i18n": "modifierType:ModifierType.MAX_REVIVE", "factory_class": "EL", "type_class": "PokemonReviveModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "revive", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePercent=100", "adaptation": "", "deferred": "同上：不做队伍 / 复活队友。"},
	"SACRED_ASH": {"zh": "圣灰", "i18n": "modifierType:ModifierType.SACRED_ASH", "factory_class": "tD", "type_class": "AllPokemonFullReviveModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "revive", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "all fainted party, restorePercent=100 (pokemonId=-1)", "adaptation": "", "deferred": "原作用是全队复活；本作不做队伍，无适配系统。"},
	"HYPER_POTION": {"zh": "厉害伤药", "i18n": "modifierType:ModifierType.HYPER_POTION", "factory_class": "il", "type_class": "PokemonHpRestoreModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "restorePoints=200, restorePercent=50", "adaptation": "", "deferred": ""},
	"MAX_POTION": {"zh": "全满药", "i18n": "modifierType:ModifierType.MAX_POTION", "factory_class": "il", "type_class": "PokemonHpRestoreModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "restorePoints=0, restorePercent=100", "adaptation": "", "deferred": ""},
	"FULL_RESTORE": {"zh": "全复药", "i18n": "modifierType:ModifierType.FULL_RESTORE", "factory_class": "il", "type_class": "PokemonHpRestoreModifierType", "modifier_class": "PokemonHpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "medicine", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "restorePoints=0, restorePercent=100, healStatus=true", "adaptation": "", "deferred": ""},
	"ELIXIR": {"zh": "PP多项小补剂", "i18n": "modifierType:ModifierType.ELIXIR", "factory_class": "cL", "type_class": "PokemonAllMovePpRestoreModifierType", "modifier_class": "PokemonAllMovePpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "pp_restore", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePoints=10 (all moves)", "adaptation": "", "deferred": "局内只药 / 球；原 PP 回复消耗品暂无货架。"},
	"MAX_ELIXIR": {"zh": "PP多项全补剂", "i18n": "modifierType:ModifierType.MAX_ELIXIR", "factory_class": "cL", "type_class": "PokemonAllMovePpRestoreModifierType", "modifier_class": "PokemonAllMovePpRestoreModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "pp_restore", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "restorePoints=-1 (all moves, fully)", "adaptation": "", "deferred": "同上：局内只药 / 球。"},
	"DIRE_HIT": {"zh": "要害攻击", "i18n": "", "factory_class": "Vc", "type_class": "TempBattleStatBoosterModifierType", "modifier_class": "TempBattleStatBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "temp_battle", "scope": SCOPE_ONE_POKEMON, "sale": SALE_DEFERRED, "value": "tempBattleStat=CRIT, battles=5", "adaptation": "", "deferred": "原作为回合制临时要害等级，本作实时制无对应窗口。"},
	"SUPER_LURE": {"zh": "白银香水", "i18n": "modifierType:ModifierType.SUPER_LURE", "factory_class": "kc", "type_class": "DoubleBattleChanceBoosterModifierType", "modifier_class": "DoubleBattleChanceBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "lure", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "battles=10", "adaptation": "", "deferred": "本作不做双打，无适配系统。"},
	"NUGGET": {"zh": "金珠", "i18n": "modifierType:ModifierType.NUGGET", "factory_class": "zc", "type_class": "MoneyRewardModifierType", "modifier_class": "MoneyRewardModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "money", "scope": SCOPE_MONEY, "sale": SALE_DEFERRED, "value": "moneyMultiplier=1", "adaptation": "", "deferred": "原作金钱系统本作没有；本作点数不是原 money，不做等价换算。"},
	"EVOLUTION_ITEM": {"zh": "进化石（随机）", "i18n": "", "factory_class": "NL", "type_class": "EvolutionItemModifierTypeGenerator", "modifier_class": "EvolutionItemModifierType", "generator": true, "generates": "EvolutionItemModifierType (random evolution item usable by party)", "placement": PLACE_TOWN_POKEMON, "category": "evolution", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "weight=min(ceil(waveIndex/15),8)", "adaptation": "用户局外要进化道具；本作现行只有等级进化，道具进化入口待接。", "deferred": ""},
	"MAP": {"zh": "地图", "i18n": "modifierType:ModifierType.MAP", "factory_class": "bt", "type_class": "MapModifier", "modifier_class": "MapModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "map", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=1 (classic only)", "adaptation": "", "deferred": "原作地图 / 路线系统本作未做（当前只有平原）。"},
	"TM_GREAT": {"zh": "技能机器（优秀档）", "i18n": "", "factory_class": "Xc", "type_class": "TmModifierTypeGenerator", "modifier_class": "TmModifierType", "generator": true, "generates": "TmModifierType for one compatible unlearned TM of tier GREAT", "placement": PLACE_TOWN_POKEMON, "category": "tm", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "tier=GREAT", "adaptation": "原 TM 三档保留；兼容性与真正学招留后项。", "deferred": ""},
	"MEMORY_MUSHROOM": {"zh": "大蘑菇", "i18n": "modifierType:ModifierType.MEMORY_MUSHROOM", "factory_class": "RL", "type_class": "RememberMoveModifierType", "modifier_class": "RememberMoveModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_POKEMON, "category": "remember", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "relearn one learnable level move (weight scales with max party level /20 cap 4)", "adaptation": "本作已有学招 / 换招流程，但记忆蘑菇道具入口待接。", "deferred": ""},
	"BASE_STAT_BOOSTER": {"zh": "营养饮料（随机）", "i18n": "", "factory_class": "Rn", "type_class": "PokemonBaseStatBoosterModifierType", "modifier_class": "PokemonBaseStatModifier", "generator": true, "generates": "PokemonBaseStatBoosterModifierType (random of 6 stats)", "placement": PLACE_TOWN_POKEMON, "category": "stat_training", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "each stack: stat = min(floor(stat*(1+stacks*0.1)),999999); max held stacks = pokemon IV of that stat", "adaptation": "用户要的是努力值每颗 +10、单项上限 252、六项都能拉满且没有 510 合计；与原作 +10% 且上限=个体值不同，按用户 EV 方案实现，source 保留。", "deferred": ""},
	"TERA_SHARD": {"zh": "太晶碎块", "i18n": "", "factory_class": "Rn", "type_class": "TerastallizeModifierType", "modifier_class": "TerastallizeModifier", "generator": true, "generates": "TerastallizeModifierType (random tera type)", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "tera type random", "adaptation": "", "deferred": "太晶 / 携带道具系统本作未实现。"},
	"DNA_SPLICERS": {"zh": "基因之楔", "i18n": "modifierType:ModifierType.DNA_SPLICERS", "factory_class": "mL", "type_class": "FusePokemonModifierType", "modifier_class": "FusePokemonModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "fusion", "scope": SCOPE_ONE_POKEMON, "sale": SALE_DEFERRED, "value": "fuse two party pokemon", "adaptation": "", "deferred": "原作融合 / 孵蛋系统本作不做；GREAT 与 MASTER 两条出现条件不同，都保留。"},
	"ULTRA_BALL": {"zh": "高级球", "i18n": "", "factory_class": "iu", "type_class": "AddPokeballModifierType", "modifier_class": "AddPokeballModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "ball", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "count=5", "adaptation": "", "deferred": ""},
	"MAX_LURE": {"zh": "黄金香水", "i18n": "modifierType:ModifierType.MAX_LURE", "factory_class": "kc", "type_class": "DoubleBattleChanceBoosterModifierType", "modifier_class": "DoubleBattleChanceBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "lure", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_DEFERRED, "value": "battles=25", "adaptation": "", "deferred": "本作不做双打。"},
	"BIG_NUGGET": {"zh": "大金珠", "i18n": "modifierType:ModifierType.BIG_NUGGET", "factory_class": "zc", "type_class": "MoneyRewardModifierType", "modifier_class": "MoneyRewardModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "money", "scope": SCOPE_MONEY, "sale": SALE_DEFERRED, "value": "moneyMultiplier=2.5", "adaptation": "", "deferred": "原作金钱系统本作没有。"},
	"PP_UP": {"zh": "PP提升剂", "i18n": "modifierType:ModifierType.PP_UP", "factory_class": "PR", "type_class": "PokemonPpUpModifierType", "modifier_class": "PokemonPpUpModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_POKEMON, "category": "pp_up", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "upPoints=1, per-move ppUp cap 3", "adaptation": "用户已定 PP 决定冷却；PP 提升与冷却接线是后续独立任务。", "deferred": ""},
	"PP_MAX": {"zh": "PP极限提升剂", "i18n": "modifierType:ModifierType.PP_MAX", "factory_class": "PR", "type_class": "PokemonPpUpModifierType", "modifier_class": "PokemonPpUpModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_POKEMON, "category": "pp_up", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "upPoints=3, per-move ppUp cap 3", "adaptation": "同上，PP / 冷却接线留后项。", "deferred": ""},
	"MINT": {"zh": "薄荷（随机）", "i18n": "", "factory_class": "Rn", "type_class": "PokemonNatureChangeModifierType", "modifier_class": "PokemonNatureChangeModifier", "generator": true, "generates": "PokemonNatureChangeModifierType (random non-neutral mint)", "placement": PLACE_TOWN_POKEMON, "category": "mint", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "natureOverride change", "adaptation": "本作 25 性格表已验；薄荷道具入口待接。", "deferred": ""},
	"RARE_EVOLUTION_ITEM": {"zh": "稀有进化石（随机）", "i18n": "", "factory_class": "NL", "type_class": "EvolutionItemModifierTypeGenerator", "modifier_class": "EvolutionItemModifierType", "generator": true, "generates": "EvolutionItemModifierType (random rare evolution item, item>50)", "placement": PLACE_TOWN_POKEMON, "category": "evolution", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "weight=min(ceil(waveIndex/15)*4,32)", "adaptation": "用户局外要进化道具；本作现行只有等级进化，道具进化待接。", "deferred": ""},
	"AMULET_COIN": {"zh": "护身金币", "i18n": "modifierType:ModifierType.AMULET_COIN", "factory_class": "bt", "type_class": "MoneyMultiplierModifier", "modifier_class": "MoneyMultiplierModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_money", "scope": SCOPE_MONEY, "sale": SALE_DEFERRED, "value": "value += floor(value*0.2*stacks); maxStack=5", "adaptation": "", "deferred": "原作金钱系统本作没有；点数是本作规则不是原 money。"},
	"REVIVER_SEED": {"zh": "复活种子", "i18n": "modifierType:ModifierType.REVIVER_SEED", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "PokemonInstantReviveModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "revive at max(floor(maxHp/2),1); max held 1", "adaptation": "", "deferred": "携带道具 + 全队濒死系统本作未实现。"},
	"CANDY_JAR": {"zh": "糖果罐", "i18n": "modifierType:ModifierType.CANDY_JAR", "factory_class": "bt", "type_class": "LevelIncrementBoosterModifier", "modifier_class": "LevelIncrementBoosterModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_candy", "scope": SCOPE_ALL_POKEMON, "sale": SALE_PLANNED, "value": "value += stacks on level-up candy count; maxStack=99", "adaptation": "", "deferred": ""},
	"ATTACK_TYPE_BOOSTER": {"zh": "属性增强道具（随机）", "i18n": "", "factory_class": "sD", "type_class": "AttackTypeBoosterModifierTypeGenerator", "modifier_class": "AttackTypeBoosterModifier", "generator": true, "generates": "AttackTypeBoosterModifierType (random move type held item, 20)", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "type boost value=20", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"TM_ULTRA": {"zh": "技能机器（究极档）", "i18n": "", "factory_class": "Xc", "type_class": "TmModifierTypeGenerator", "modifier_class": "TmModifierType", "generator": true, "generates": "TmModifierType for one compatible unlearned TM of tier ULTRA", "placement": PLACE_TOWN_POKEMON, "category": "tm", "scope": SCOPE_ONE_POKEMON, "sale": SALE_ADAPTATION_PENDING, "value": "tier=ULTRA", "adaptation": "原 TM 三档保留；兼容性与真正学招留后项。", "deferred": ""},
	"RARER_CANDY": {"zh": "高级神奇糖果", "i18n": "modifierType:ModifierType.RARER_CANDY", "factory_class": "jP", "type_class": "AllPokemonLevelIncrementModifierType", "modifier_class": "PokemonLevelIncrementModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_POKEMON, "category": "candy", "scope": SCOPE_PARTY, "sale": SALE_REMOVED_BY_USER, "value": "all party level+1 (pokemonId=-1)", "adaptation": "用户明确删除此项；原池 tier 是 ULTRA(2)，不是 MASTER 金色档，来源如实保留、不可售。", "deferred": ""},
	"GOLDEN_PUNCH": {"zh": "黄金拳", "i18n": "modifierType:ModifierType.GOLDEN_PUNCH", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "DamageMoneyRewardModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "money += floor(damage*0.5*stacks); max held 5", "adaptation": "", "deferred": "携带道具 + 原金钱系统本作没有。"},
	"IV_SCANNER": {"zh": "个体值扫描器", "i18n": "modifierType:ModifierType.IV_SCANNER", "factory_class": "bt", "type_class": "IvScannerModifier", "modifier_class": "IvScannerModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_meta", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=3; apply() has no numeric effect (scan UI)", "adaptation": "", "deferred": "个体值展示 / 扫描本作未接（当前 IV 固定占位 0）。"},
	"EXP_CHARM": {"zh": "经验护符", "i18n": "modifierType:ModifierType.EXP_CHARM", "factory_class": "Zc", "type_class": "ExpBoosterModifierType", "modifier_class": "ExpBoosterModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_exp", "scope": SCOPE_ALL_POKEMON, "sale": SALE_PLANNED, "value": "boostPercent=25 -> boostMultiplier=0.25; value=floor(value*(1+stacks*0.25)); maxStack=99", "adaptation": "", "deferred": ""},
	"EXP_SHARE": {"zh": "学习装置", "i18n": "modifierType:ModifierType.EXP_SHARE", "factory_class": "bt", "type_class": "ExpShareModifier", "modifier_class": "ExpShareModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_exp", "scope": SCOPE_PARTY, "sale": SALE_ADAPTATION_PENDING, "value": "maxStack=5; apply() returns true, real logic is in party exp phases", "adaptation": "用户方向：不做队伍，经验直接提升上场单只；原作按队伍分配，没有等价标量，待适配，不自造倍率。", "deferred": ""},
	"EXP_BALANCE": {"zh": "经验平衡器", "i18n": "modifierType:ModifierType.EXP_BALANCE", "factory_class": "bt", "type_class": "ExpBalanceModifier", "modifier_class": "ExpBalanceModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_exp", "scope": SCOPE_PARTY, "sale": SALE_ADAPTATION_PENDING, "value": "maxStack=5; apply() returns true, real logic is in party exp phases", "adaptation": "同上：原作平衡全队经验，本作无队伍、无等价标量，待适配，不自造倍率。", "deferred": ""},
	"TERA_ORB": {"zh": "太晶珠", "i18n": "modifierType:ModifierType.TERA_ORB", "factory_class": "bt", "type_class": "TerastallizeAccessModifier", "modifier_class": "TerastallizeAccessModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_access", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=1; access flag, no numeric apply", "adaptation": "", "deferred": "太晶系统本作未实现。"},
	"VOUCHER": {"zh": "兑换券", "i18n": "", "factory_class": "Yc", "type_class": "AddVoucherModifierType", "modifier_class": "AddVoucherModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "voucher", "scope": SCOPE_SAVE_META, "sale": SALE_DEFERRED, "value": "voucherType=REGULAR, count=-1 (default 1)", "adaptation": "", "deferred": "券 / 元进度系统本作没有。"},
	"ROGUE_BALL": {"zh": "Rogue 球", "i18n": "", "factory_class": "iu", "type_class": "AddPokeballModifierType", "modifier_class": "AddPokeballModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "ball", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "count=5", "adaptation": "", "deferred": ""},
	"RELIC_GOLD": {"zh": "古代金币", "i18n": "modifierType:ModifierType.RELIC_GOLD", "factory_class": "zc", "type_class": "MoneyRewardModifierType", "modifier_class": "MoneyRewardModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "money", "scope": SCOPE_MONEY, "sale": SALE_DEFERRED, "value": "moneyMultiplier=10", "adaptation": "", "deferred": "原作金钱系统本作没有。"},
	"LEFTOVERS": {"zh": "吃剩的东西", "i18n": "modifierType:ModifierType.LEFTOVERS", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "TurnHealModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "heal max(floor(maxHp/16)*stacks,1) per turn; max held 4", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"SHELL_BELL": {"zh": "贝壳之铃", "i18n": "modifierType:ModifierType.SHELL_BELL", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "HitHealModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "heal max(floor(damageDealt/8)*stacks,1); max held 4", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"BERRY_POUCH": {"zh": "树果袋", "i18n": "modifierType:ModifierType.BERRY_POUCH", "factory_class": "bt", "type_class": "PreserveBerryModifier", "modifier_class": "PreserveBerryModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_meta", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "randSeedInt(3)<stacks preserves berry; maxStack=3", "adaptation": "", "deferred": "树果 / 携带道具系统本作未实现。"},
	"GRIP_CLAW": {"zh": "紧缠钩爪", "i18n": "modifierType:ModifierType.GRIP_CLAW", "factory_class": "oD", "type_class": "ContactHeldItemTransferChanceModifierType", "modifier_class": "HeldItemTransferModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "contact held-item transfer chance=10", "adaptation": "", "deferred": "携带道具 / 转移系统本作未实现。"},
	"WIDE_LENS": {"zh": "广角镜", "i18n": "modifierType:ModifierType.WIDE_LENS", "factory_class": "iD", "type_class": "PokemonMoveAccuracyBoosterModifierType", "modifier_class": "PokemonMoveAccuracyBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "accuracy booster value=5", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"BATON": {"zh": "接力棒", "i18n": "modifierType:ModifierType.BATON", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "SwitchEffectTransferModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "switch effect transfer; max held 1", "adaptation": "", "deferred": "携带道具 / 换人转移系统本作未实现。"},
	"SOUL_DEW": {"zh": "心之水滴", "i18n": "modifierType:ModifierType.SOUL_DEW", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "PokemonNatureWeightModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "nature weight += 0.1*stacks*(sign); max held 10", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"SOOTHE_BELL": {"zh": "安抚之铃", "i18n": "modifierType:ModifierType.SOOTHE_BELL", "factory_class": "aD", "type_class": "PokemonFriendshipBoosterModifierType", "modifier_class": "PokemonFriendshipBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "friendship boost", "adaptation": "", "deferred": "亲密度 / 携带道具系统本作未实现。"},
	"ABILITY_CHARM": {"zh": "特性护符", "i18n": "modifierType:ModifierType.ABILITY_CHARM", "factory_class": "bt", "type_class": "HiddenAbilityRateBoosterModifier", "modifier_class": "HiddenAbilityRateBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_meta", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "value *= 2^(-1-stacks); maxStack=4", "adaptation": "", "deferred": "特性系统本作未实现（list.md“特性·以后再说”）。"},
	"FOCUS_BAND": {"zh": "气势头带", "i18n": "modifierType:ModifierType.FOCUS_BAND", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "SurviveDamageModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "randSeedInt(10)<stacks survive; max held 5", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"QUICK_CLAW": {"zh": "先制之爪", "i18n": "modifierType:ModifierType.QUICK_CLAW", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "BypassSpeedChanceModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "randSeedInt(10)<stacks bypass speed; max held 3", "adaptation": "", "deferred": "携带道具 / 速度先制系统本作未实现。"},
	"KINGS_ROCK": {"zh": "王者之证", "i18n": "modifierType:ModifierType.KINGS_ROCK", "factory_class": "za", "type_class": "PokemonHeldItemModifierType", "modifier_class": "FlinchChanceModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "randSeedInt(10)<stacks flinch; max held 3", "adaptation": "", "deferred": "携带道具 / 退缩系统本作未实现。"},
	"LOCK_CAPSULE": {"zh": "锁定胶囊", "i18n": "modifierType:ModifierType.LOCK_CAPSULE", "factory_class": "bt", "type_class": "LockModifierTiersModifier", "modifier_class": "LockModifierTiersModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_meta", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=1; locks reward modifier tiers", "adaptation": "", "deferred": "本作没有原奖励档位生成系统可锁。"},
	"SUPER_EXP_CHARM": {"zh": "超级经验护符", "i18n": "modifierType:ModifierType.SUPER_EXP_CHARM", "factory_class": "Zc", "type_class": "ExpBoosterModifierType", "modifier_class": "ExpBoosterModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_exp", "scope": SCOPE_ALL_POKEMON, "sale": SALE_PLANNED, "value": "boostPercent=60 -> boostMultiplier=0.6; maxStack=30", "adaptation": "", "deferred": ""},
	"FORM_CHANGE_ITEM": {"zh": "形态变化道具（随机）", "i18n": "", "factory_class": "rD", "type_class": "FormChangeItemModifierTypeGenerator", "modifier_class": "PokemonFormChangeItemModifier", "generator": true, "generates": "FormChangeItemModifierType (random form change item)", "placement": PLACE_DEFERRED, "category": "form", "scope": SCOPE_ONE_POKEMON, "sale": SALE_DEFERRED, "value": "random form change item", "adaptation": "", "deferred": "形态变化道具系统本作未实现（现有进化 / 形态是另一套）。"},
	"MEGA_BRACELET": {"zh": "超级手镯", "i18n": "modifierType:ModifierType.MEGA_BRACELET", "factory_class": "bt", "type_class": "MegaEvolutionAccessModifier", "modifier_class": "MegaEvolutionAccessModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_access", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=1; access flag, no numeric apply", "adaptation": "", "deferred": "Mega 进化系统本作未实现。"},
	"DYNAMAX_BAND": {"zh": "极巨化手环", "i18n": "modifierType:ModifierType.DYNAMAX_BAND", "factory_class": "bt", "type_class": "GigantamaxAccessModifier", "modifier_class": "GigantamaxAccessModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_access", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "maxStack=1; access flag, no numeric apply", "adaptation": "", "deferred": "极巨化系统本作未实现。"},
	"MASTER_BALL": {"zh": "大师球", "i18n": "", "factory_class": "iu", "type_class": "AddPokeballModifierType", "modifier_class": "AddPokeballModifier", "generator": false, "generates": "", "placement": PLACE_IN_RUN, "category": "ball", "scope": SCOPE_RUN_CONSUMABLE, "sale": SALE_PLANNED, "value": "count=1", "adaptation": "", "deferred": ""},
	"SHINY_CHARM": {"zh": "闪耀护符", "i18n": "modifierType:ModifierType.SHINY_CHARM", "factory_class": "bt", "type_class": "ShinyRateBoosterModifier", "modifier_class": "ShinyRateBoosterModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "global_meta", "scope": SCOPE_ALL_POKEMON, "sale": SALE_DEFERRED, "value": "value *= 2^(2+stacks); maxStack=4", "adaptation": "", "deferred": "闪光系统本作未实现。"},
	"HEALING_CHARM": {"zh": "治愈护符", "i18n": "modifierType:ModifierType.HEALING_CHARM", "factory_class": "bt", "type_class": "HealingBoosterModifier", "modifier_class": "HealingBoosterModifier", "generator": false, "generates": "", "placement": PLACE_TOWN_GLOBAL, "category": "global_heal", "scope": SCOPE_ALL_POKEMON, "sale": SALE_PLANNED, "value": "multiplier=1.1; value *= 1+(1.1-1)*stacks; maxStack=5", "adaptation": "", "deferred": ""},
	"MULTI_LENS": {"zh": "多重镜", "i18n": "modifierType:ModifierType.MULTI_LENS", "factory_class": "nD", "type_class": "PokemonMultiHitModifierType", "modifier_class": "PokemonMultiHitModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "hits *= stacks+1; damage *= .4/.25/.175; max held 3", "adaptation": "", "deferred": "携带道具系统本作未实现。"},
	"VOUCHER_PLUS": {"zh": "兑换券+", "i18n": "", "factory_class": "Yc", "type_class": "AddVoucherModifierType", "modifier_class": "AddVoucherModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "voucher", "scope": SCOPE_SAVE_META, "sale": SALE_DEFERRED, "value": "voucherType=PLUS, count=-1 (default 1)", "adaptation": "", "deferred": "券 / 元进度系统本作没有。"},
	"MINI_BLACK_HOLE": {"zh": "迷你黑洞", "i18n": "modifierType:ModifierType.MINI_BLACK_HOLE", "factory_class": "lD", "type_class": "TurnHeldItemTransferModifierType", "modifier_class": "HeldItemTransferModifier", "generator": false, "generates": "", "placement": PLACE_DEFERRED, "category": "held_item", "scope": SCOPE_HELD_POKEMON, "sale": SALE_DEFERRED, "value": "turn held-item transfer; unlock-gated", "adaptation": "", "deferred": "携带道具 / 转移系统本作未实现。"},
}

# ================= 纯查询 =================
# 所有查询都返回新建的 Dictionary / Array，调用方改写返回值不会污染上面的常量表。


static func occurrence_count() -> int:
	return OCCURRENCES.size()


static func tier_name(tier: int) -> String:
	return str(TIER_NAMES.get(tier, ""))


static func placement_name(placement: int) -> String:
	return str(PLACE_NAMES.get(placement, ""))


static func sale_status_name(status: int) -> String:
	return str(SALE_NAMES.get(status, ""))


static func scope_name(scope: int) -> String:
	return str(SCOPE_NAMES.get(scope, ""))


static func is_known_id(source_id: String) -> bool:
	return SOURCE_INFO.has(source_id)


# 永远 false：本段所有条目都只是目录，没有接任何可购买功能。
static func is_purchasable(source_id: String) -> bool:
	return false


static func source_ids() -> Array:
	var out: Array = []
	for row in OCCURRENCES:
		var id := str(row[0])
		if not out.has(id):
			out.append(id)
	return out


static func all() -> Array:
	var out: Array = []
	for i in OCCURRENCES.size():
		out.append(_record(i))
	return out


static func by_tier(tier: int) -> Array:
	var out: Array = []
	if not TIER_NAMES.has(tier):
		return out
	for i in OCCURRENCES.size():
		if int(OCCURRENCES[i][1]) == tier:
			out.append(_record(i))
	return out


# DNA_SPLICERS 在 GREAT / MASTER 各有一条，返回值按原顺序（GREAT 在前），按 tier 稳定区分。
static func by_source_id(source_id: String) -> Array:
	var out: Array = []
	if not SOURCE_INFO.has(source_id):
		return out
	for i in OCCURRENCES.size():
		if str(OCCURRENCES[i][0]) == source_id:
			out.append(_record(i))
	return out


static func by_placement(placement: int) -> Array:
	var out: Array = []
	if not PLACE_NAMES.has(placement):
		return out
	for i in OCCURRENCES.size():
		var id := str(OCCURRENCES[i][0])
		if int(SOURCE_INFO[id]["placement"]) == placement:
			out.append(_record(i))
	return out


static func by_sale_status(status: int) -> Array:
	var out: Array = []
	if not SALE_NAMES.has(status):
		return out
	for i in OCCURRENCES.size():
		var id := str(OCCURRENCES[i][0])
		if int(SOURCE_INFO[id]["sale"]) == status:
			out.append(_record(i))
	return out


static func by_category(category: String) -> Array:
	var out: Array = []
	if category.is_empty():
		return out
	for i in OCCURRENCES.size():
		var id := str(OCCURRENCES[i][0])
		if str(SOURCE_INFO[id]["category"]) == category:
			out.append(_record(i))
	return out


static func occurrence_in_tier_counts() -> Dictionary:
	var out := {}
	for tier in TIER_NAMES.keys():
		out[tier] = 0
	for row in OCCURRENCES:
		out[int(row[1])] = int(out[int(row[1])]) + 1
	return out


# ================= 内部 =================


static func _record(index: int) -> Dictionary:
	var row: Array = OCCURRENCES[index]
	var id := str(row[0])
	var tier := int(row[1])
	var info: Dictionary = SOURCE_INFO[id]
	var occ_in_tier := 0
	for i in index:
		if int(OCCURRENCES[i][1]) == tier:
			occ_in_tier += 1
	var placement := int(info["placement"])
	var sale := int(info["sale"])
	var scope := int(info["scope"])
	return {
		"occurrence": index,
		"occurrence_in_tier": occ_in_tier,
		"source_id": id,
		"name_zh": str(info["zh"]),
		"i18n_key": str(info["i18n"]),
		"tier": tier,
		"tier_name": tier_name(tier),
		"weight_expr": str(row[2]),
		"condition_expr": str(row[3]),
		"max_weight_expr": str(row[4]),
		"source_expr": str(row[5]),
		"factory_expr": str(FACTORIES[id]),
		"factory_class": str(info["factory_class"]),
		"source_type_class": str(info["type_class"]),
		"source_modifier_class": str(info["modifier_class"]),
		"generator": bool(info["generator"]),
		"generates": str(info["generates"]),
		"placement": placement,
		"placement_name": placement_name(placement),
		"category": str(info["category"]),
		"scope": scope,
		"scope_name": scope_name(scope),
		"sale_status": sale,
		"sale_status_name": sale_status_name(sale),
		"source_value": str(info["value"]),
		"adaptation": str(info["adaptation"]),
		"deferred_reason": str(info["deferred"]),
		"purchasable": false,
	}
