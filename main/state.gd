extends Node3D
# 生产链：state → combat → arts（绿毛虫招式）→ enemies → cards → meta_flow → main。
const UNITS := preload("res://data/units.gd")
const MOVES := preload("res://data/pokemon_moves.gd")
const CARDS := preload("res://data/cards.gd")
const Stats := preload("res://game/stats.gd")
const Roster := preload("res://game/roster.gd")
const BattleReport := preload("res://game/battle_report.gd")
const EnemyMoves := preload("res://game/enemy_moves.gd")
const Waves := preload("res://game/waves.gd")
const WildEncounters := preload("res://game/pokemon_wild_encounters.gd")
const PokemonGrowth := preload("res://game/pokemon_growth.gd")
const PokemonDamage := preload("res://game/pokemon_damage.gd")
const PokemonStatus := preload("res://game/pokemon_status.gd")
const StatusClock := preload("res://game/pokemon_status_clock.gd")
const TypeChart := preload("res://data/pokemon_type_chart.gd")
const Pokedex := preload("res://data/pokedex.gd")
const Points := preload("res://game/pokemon_points.gd")
const SpecialForms := preload("res://game/pokemon_special_forms.gd")
const AB := preload("res://game/pokemon_abilities.gd")
const STARTER_PREFIX := "STARTER:"   # 商店商品 ID：STARTER:招式 id（把开局招留在家里 / 带上）
const SaveSlots := preload("res://game/save_slots.gd")
const TMRules := preload("res://game/pokemon_tm.gd")
const PokemonEvolution := preload("res://game/pokemon_evolution.gd")
const PokemonShop := preload("res://game/pokemon_shop.gd")
const PokemonBerries := preload("res://game/pokemon_berries.gd")
const PokemonMemory := preload("res://game/pokemon_memory.gd")
const PokemonLens := preload("res://game/pokemon_lens.gd")
const SpeciesCandy := preload("res://game/pokemon_species_candy.gd")
const HeldItems := preload("res://game/pokemon_held_items.gd")
const Fusion := preload("res://game/pokemon_fusion.gd")
const Capture := preload("res://game/pokemon_capture.gd")
const CaptureSpecies := preload("res://data/pokemon_capture_species.gd")
# 已验收的原捕获演出播放器（第 3 段接线只用它，不复制第二播放器 / 不生成素材）。
const CaptureFXScript := preload("res://fx/rogue_capture.gd")
const CapturePage := preload("res://ui/pokemon_capture.gd")
const TownPage := preload("res://ui/town.gd")
const Offer := preload("res://game/offer.gd")
const TitlePage := preload("res://ui/title.gd")
const RogueStarter := preload("res://ui/rogue_starter.gd")
# 选宠页：true = 原版 Pokémon Rogue 风格的新页面（ui/rogue_starter.gd，鼠标操作）；false = 旧的城镇页（ui/town.gd，旧检查还在用它）。
const USE_ROGUE_STARTER := true
const Hud := preload("res://ui/hud.gd")
const PausePage := preload("res://ui/pause.gd")
const PokemonChoice := preload("res://ui/pokemon_choice.gd")
const SPAWN_RADIUS := 20.0
const ENCIRCLE_RADIUS := 14.0
const SPAWN_PER_FRAME := 8
const MAX_ENEMIES := 120
const REROLLS := 2
const POTION_ELITE_CHANCE := 0.3
const POTION_HEAL := 0.15
const BALL_AIM_RADIUS := 3.0
# 捕获第 3 段：真实投球演出起点高度（玩家身边合理高度，世界单位）。这是本作 2.5D 适配值，
# 不是原世界尺度；落地 / catch 点高度由 fx/rogue_capture.gd::ground_height()/catch_height() 给。
const CAPTURE_THROW_HEIGHT := 0.6

# 敌人发出的弹药（用户 2026-10-17：远程招做成弹药，不再瞬间锁定）：朝发射时玩家所在位置直线飞，不追踪。
class Bolt:
    var node: Node3D
    var dir := Vector3.ZERO
    var left := 0.0
    var owner: Enemy
    var move := ""
    var age := 0.0
    var sprite := false   # true = 原特效图层弹体（RogueFX.make_projectile）；false = 色球


var bolts: Array = []
var impacts: Array = []   # 弹药命中特效：{node, move, age, life, sprite}


# 弹药清理占位（arts.gd 真正实现）：取消 / 放弃 / 结算 / 新局时清空场上弹药。
func _clear_bolts() -> void:
    pass


class Enemy:
    var node: Node3D
    # 敌人的近身招式池（game/enemy_moves.gd）和本次挥击选中的那一招。默认只有撞击（非野生模板 / 旧检查）。
    var moves: Array = ["tackle"]
    var cur_move := "tackle"
    # 闪光 / 神兽：特效节点、计时和“进入视野提示一次”的标记（fx/enemy_special.gd）。
    var shiny := false
    var shiny_variant := 0        # 闪光档位：0 普通闪光（金）/ 1 蓝闪 / 2 红闪；只有 shiny 为真才有意义
    var legendary := false
    var special_alerted := false
    var special_t := 0.0
    var sparkle: MeshInstance3D
    # 近身招（物理）与远程弹药招（特殊）：近身挥击只从 melee_moves 挑；弹药只从 ranged_moves 挑。
    var melee_moves: Array = ["tackle"]
    var ranged_moves: Array = []
    var debuff_moves: Array = []     # 降玩家能力的招（叫声 / 瞪眼 / 摇尾巴 / 泼沙…）
    var debuff_cd := 0.0
    var shoot_cd := 0.0      # 弹药冷却
    var shoot_wind := -1.0   # 前摇倒计时（>0 表示正在蓄力）
    var shoot_move := ""
    # 定身法：敌人上一次用的招；被封住的招和封到什么时候（run_clock 秒）。
    var last_move := ""
    var disabled_move := ""
    var disabled_until := 0.0
    # 特性（game/pokemon_abilities.gd）：野生个体出生时按物种掷一个栏位；头目 / 神兽 / 闪光必定隐藏特性并带被动。
    var ability := ""
    var ability_slot := 0
    # 第二批变化招（2026-10-20）：诅咒 / 恶梦 / 灭亡之歌 / 换属性 / 闪避 / 着迷 / 再来一次 / 撒菱类陷阱
    var cursed_until := 0.0
    var curse_next := 0.0
    var nightmare := false
    var perish_at := 0.0
    var type_override: Array = []   # 浸水 / 魔法粉 / 万圣夜…：换过属性就用这个
    var eva_stage := 0              # 闪避等级（甜甜香气 / 清除浓雾降它）
    var infatuated_until := 0.0     # 着迷：这段时间一半几率不出手
    var encore_until := 0.0         # 再来一次：这段时间只能用上一招
    var hazard_hit := {}            # 陷阱区 id -> true（每个陷阱区只踩一次）
    var ivs: Array = [0, 0, 0, 0, 0, 0]   # 野生个体的个体值（原版出生随机 0–31；只用于抓到时记最好值，不改敌人六维）
    var nature_id := 0   # 野生个体的性格（原版出生随机 25 种之一）；抓到时给这一系解锁这个性格
    var passive := ""
    var ab_intim := false         # 威吓已对它生效过 / 已威吓过玩家（走进威吓范围时触发一次，范围见 abilities.gd 的 AB_INTIMIDATE_RANGE）
    var ab_seen := false          # 第一次靠近玩家时触发“出场类”特性（威吓 / 场地制造者）只触发一次
    var heal_blocked_until := 0.0   # 回复封锁：到这个时刻（run_clock 秒）前敌人不能回复 HP
    var ap: AnimationPlayer
    var t: Dictionary
    var hp := 0.0
    var dying := -1.0
    var kb := Vector3.ZERO
    var atk_left := 0.0
    var hit_in := -1.0
    var attack_cd := 0.0
    var pulse := 0.0
    var slow_left := 0.0
    var slow := 0.0
    var speed_mult := 1.0
    # 原作能力等级：吐丝命中后速度等级 -2，每敌人独立累加并钳到 [-6,6]，整场存活期间保留。
    # 旧 slow / slow_left 字段保留占位但不再由三招写入，等后续迁移清理。
    var speed_stage := 0
    var aura_hit := {}   # 已经被哪些光环招降过（每只怪每种光环只降一次）
    var squad_fuse := -1.0         # 自爆小队：亮红圈后的倒计时（-1 = 还没点着）
    var squad_ring: MeshInstance3D = null
    var spared := false  # 打不死（最多剩 1 血）：教学关送的伊布
    # 平原头目分段：segments / index 每敌人独立（初始 index = segments-1），不写共享模板 t。
    # 破段强化给己方 ATK/DEF/SPATK/SPDEF/SPD 各一份独立阶段 [-6,6]；SPD 复用上面的 speed_stage，
    # 不再复制第二个 SPD 字段（吐丝 / 麻痹 / 破段走同一阶段）。
    var segments := 0
    var segment_index := -1
    var born_at := 0.0   # 出现的时刻（头目 60 秒后自己离开）
    var atk_stage := 0
    var def_stage := 0
    var spatk_stage := 0
    var spdef_stage := 0
    # 原作 ACC（命中）能力阶段：泼沙命中后目标 -1、每敌人独立累加钳 [-6,6]，整场存活期间保留。
    # 每个 Enemy 新实例默认 0（不写共享 unit_cache.t）：新局 / 新敌人 / 重载自然回 0，
    # 不进存档、不带到捕获解锁的下一局。玩家没有 ACC/EVA 阶段系统（当前 EVA 恒 0）。
    var acc_stage := 0
    # 气味侦测（原 ExposedTag / IGNORE_GHOST）：被识破后一般 / 格斗招对它的幽灵属性不再 0 倍。每敌人一份。
    var exposed_ghost := false
    var exposed_until := 0.0     # 气味侦测识破的失效时刻（run_clock 秒）
    # 畏缩（用户 2026-10-16）：flee_until 之前向反方向跑开、不攻击。
    var flee_until := 0.0
    var rock_ready_at := 0.0      # 王者之证：这只下一次能掷畏缩的时刻（每秒最多一次）
    var contact_ready_at := 0.0   # 接触特性（静电 / 火焰之躯…）：打这只时下一次能触发的时刻（每秒最多一次）
    # 寄生种子：seeded_until 之前每秒被吸 1/8 最大 HP 并回给玩家；seed_next 是下一次吸取时刻。
    var seeded_until := 0.0
    var seed_next := 0.0
    var trapped_until := 0.0   # 缠绕（紧束 / 绑紧 / 火焰旋涡…）：这之前原地不能移动、每秒被削 1/8 最大 HP（头目只掉血不定身）
    var trap_next := 0.0
    var yawn_at := 0.0   # 哈欠：到这个时刻目标睡着（0 = 没有）
    # 每个敌人各自一份异常状态 + 实时状态钟（不放进共享 unit_cache 的 t 字典：
    # t 是同一 key 的所有敌人共用的模板，状态必须一敌人一份）。玩家的是另一份，互不共用。
    var status: PokemonStatus = PokemonStatus.for_game()   # 持续伤害 4 秒一结算
    var clock: StatusClock = StatusClock.new()
    var status_key := ""   # 变化时才重画头顶标识，避免每帧建节点


# 原作能力等级倍率 max(2,2+stage)/max(2,2-stage)：0→1、-2→1/2、-4→1/3、-6→1/4、+2→2。
# 只用于实时移动速度，不把米/秒冒充原作速度能力值。
static func stat_stage_multiplier(stage: int) -> float:
    return maxf(2.0, 2.0 + stage) / maxf(2.0, 2.0 - stage)

var player: Node3D
var player_ap: AnimationPlayer
var player_unit: Dictionary
var cam: Camera3D
var sfx: Node
var scenery: Node3D
var hud: CanvasLayer
var town_page: CanvasLayer
var title_page: CanvasLayer
var pause_page: CanvasLayer
var shop_page: CanvasLayer
var enemies: Array[Enemy] = []
var gems: Array[MeshInstance3D] = []
var gem_mesh: SphereMesh
var gem_mat: StandardMaterial3D
var stats: Stats
var waves: Waves
# 本局真实野生抽样器（含本局一次 cycleOffset 与一颗 RNG）；每局 start_run 重建。
var wild: WildEncounters
var started := false
var choosing := false
var paused := false
var dead := false
var won := false
var time := 0.0
# 战斗报告：每次玩家掉血 / 治疗都记一条，死亡 / 通关结算时出报告（game/battle_report.gd）。
var battle_report := BattleReport.new()
var last_report_path := ""
var kills := 0
# 击杀点数：一份所有宝可梦共用的持久余额 + 一份本局获得计数（本局计数每次开局归零，余额进档）。
# points_path 可注入隔离路径供真实读写检查；默认路径下真实奖励照发，没有“测试关闭奖励”的开关。
var points_path := Points.DEFAULT_PATH
var points_wallet: Points = null
# 捕获第 2 段：球库存（索引 = 球 type 0..4；局内内存，购买 / 投球 / 局末存进钱包，跨局保留）+ 瞄准状态 + 捕获 HUD 节点。
# 注意：上面已有 `capture` 是旧的自动截图 / 调试模式，这里的球相关命名一律用 ball_ / capture_page 前缀。
var ball_counts: Array = PokemonShop.initial_ball_counts()
var ball_aiming := false
# 稀有宠物提示（用户 2026-10-17：遇到珍惜宠物方便我们抓）：捕获率 ≤ 45 且还没捕获过的物种，
# 出生时头顶挂金色「★ 稀有」，每种每局第一次出现弹一条横幅；抓到后同种头顶标记消失。
const RARE_CATCH_RATE := 45
const RARE_POOL_TIER := 2   # 刷怪表的“稀有”档（0 普通 1 少见 2 稀有 3 超稀有 4 究极稀有），这档及以上才标稀有
var rare_announced: Dictionary = {}
# 闪光（用户 2026-10-17：闪光 / 神兽宠要有特效和音效）：原作基础闪光率 64/65536 = 1/1024；
# 野生敌人出生时掷一次。`forceshiny` 启动参数让每只野生敌人都闪光，方便看特效 / 听声音。
const SHINY_CHANCE := 64.0 / 65536.0
var player_train_key := 0   # 本局开局选的那只的物种 ID：营养饮料努力值按它存取（进化后不变）
var shiny_force := false
var shiny_chance := SHINY_CHANCE
var player_shiny_variant := -1   # 这一局主角是不是闪光个体：-1 普通 / 0 金 / 1 蓝 / 2 红（选宠页开了“闪光个体”才有）
var start_shiny_variant := -1    # 选宠页传给 start_run 的闪光档位（start_run 读完就清回 -1）
var shiny_variant_force := -1   # 测试 / 调试用：>= 0 时闪光一律是这一档（0 金 / 1 蓝 / 2 红）；-1 = 按 60/30/10 随机
var special_sound_log: Array = []   # 提示音播放记录（路径），给检查用；不影响游戏
const EnemySpecial := preload("res://fx/enemy_special.gd")


# 刷新场上敌人的稀有标记占位（enemies.gd 真正实现）：抓到新物种后调。
func _refresh_rare_markers() -> void:
    pass
# 暂停抓宠物模式（用户 2026-10-17）：战斗暂停 + 局内商店 B 区按钮进入；世界保持暂停，
# 左侧球面板显示出来，选球 → 点地面放圈 → 投出的同时恢复游戏。Esc / 返回按钮回商店。
var capture_pause_mode := false
var lens_support := 0   # 这一局的辅助多重镜等级（开局从钱包读）
var lens_attack := 0    # 这一局的进攻多重镜等级
var lens_capture := 0   # 这一局的捕捉镜等级（扔球捕获率再乘倍率）
var run_starter_id := 10   # 这一局开局选的宠物编号（技能机器学过的招按它查）
# 第二批变化招的玩家这边（2026-10-20）：效果时长按原版 5 回合 = 天气那 20 秒
var stockpile := 0              # 蓄力（最多 3 层，每层防御 / 特防 +1）
var safeguard_until := 0.0      # 神秘守护：不会陷入异常 / 混乱
var mist_until := 0.0           # 白雾：能力不会被降低
var lucky_chant_until := 0.0    # 幸运咒语：不会被会心一击
var water_sport_until := 0.0    # 玩水：火系伤害减半
var mud_sport_until := 0.0      # 玩泥巴：电系伤害减半
var gravity_until := 0.0        # 重力：命中 ×5/3
var laser_focus_next := false   # 磨砺：下一招必定会心
var destiny_bond_until := 0.0   # 同命：这段时间里被打倒，打倒你的那只一起倒下
var player_eva_stage := 0       # 影子分身 / 变小：玩家闪避等级
var hazards: Array = []         # 撒菱 / 隐形岩 / 毒菱 / 黏黏网：{"id", "kind", "pos", "radius", "until", "node"}
var hazard_seq := 0
var run_held := {}   # 这一局带着的携带道具 {道具 id: 个数}（开局从钱包按开局那只的进化系读；规则 game/pokemon_held_items.gd）
var leftovers_clock := 0.0
var leftovers_bank := 0.0
var run_forgotten: Array = []   # 这一局被新招换掉 / 忘掉的招（记忆蘑菇也能恢复；开局清空）
var berries := {"SITRUS": 0, "LUM": 0}   # 本局带的树果（文柚果 / 木子果），带着就自动吃；规则见 game/pokemon_berries.gd
var _berry_gap := 0.0                      # 距离下一次允许吃果子还要多少秒
var disabled_moves: Dictionary = {}   # 暂停抓宠界面里关掉的招（id → true）：关掉的招战斗里不自动放，方便抓宠物（用户 2026-10-18）
var _settings_from_capture := false   # 设置是从暂停抓宠界面右上角点开的：关掉设置后直接回到暂停抓宠界面
# 选球瞄准时的慢动作（用户 2026-10-17：5–10 秒）：实时战斗里进入瞄准就把 Engine.time_scale 降到 0.2，
# 最多持续 8 个**真实**秒（用 ticks_msec 算，不受 time_scale 影响）；投出 / 取消 / 超时 / 暂停都会恢复。
const BALL_SLOWMO_SCALE := 0.2
const BALL_SLOWMO_SECS := 8.0
# 抓到之后的短慢动作（用户 2026-10-21：“抓完宠物之后能有 1 秒左右的慢动作吗”）：真实时间 1 秒、0.35 倍
const CAPTURE_HP_CAP := 0.5   # 捕获时血量最多按这个比例算（满血当半血）
const CAPTURE_AFTER_SLOWMO_SECS := 0.6   # 用户 2026-10-23：1 秒“稍微有点长”
const CAPTURE_AFTER_SLOWMO_SCALE := 0.35
var ball_slowmo_scale := BALL_SLOWMO_SCALE   # 这一次慢动作用的倍率（结束时只在还是它的时候改回 1）
var ball_slowmo_active := false
var _slowmo_on_resume := false   # 暂停抓宠页里抓到的：点继续回到游戏时再慢 1 秒（暂停中开不了慢动作）
var ball_slowmo_end_ms := 0
var ball_aim_type := -1
var capture_page: Node = null
# capture_presenting 批次：主循环冻结战斗逻辑（main._process 门槛），原 FX 用真实 delta 自然播。
# 持久解锁仍在提交时立即落盘；捕获 XP / 头目推进延后到整批演出结束。只留轻量记录，不造事件框架。
var capture_presenting := false
var capture_fx = null                    # 已验收的原播放器实例（一部，懒创建，复播；untyped 供动态调用）
var _capture_batch: Array = []           # 活动播放记录：{id, captured, enemy, restored, visible?}
var _capture_rewards: Array = []         # 待奖励数组：{xp, boss, final, name}
# 失败恢复记录：每个失败目标一条记录（与 _capture_batch 里同一条字典，不是副本），
# 记录投球前的原 visible，恢复时原样还原；`restored` 保证幂等，不留重复恢复。
var _capture_restores: Array = []
var _capture_pending_banner := ""        # 演出结束后再报的结果横幅
# 捕获头目延迟回调 token：取消 / 重开 / 重复取消会 ++，晚到的 0.8s 回调据此幂等丢弃。
var _capture_boss_token := 0
var level := 1
var xp := 0.0
# 本轮升级 / 进化 / 换招接线：当前物种 + 原作六项 + 固定占位 IV / 性格。
# 属性公式和进化表在 game/pokemon_growth.gd；player_stats 顺序 [HP,ATK,DEF,SPATK,SPDEF,SPD]。
var player_species_id := 10
var player_fusion_id := 0
var player_shiny_bonus := -1   # 闪光给镜片加的级数；-1 = 按 player_shiny_variant 算（没融合），融合时 = 两只各自加级之和
var start_shiny_parts: Array = [-1, -1]
var player_shiny_borrowed := false   # 这一局的闪光是融合借来的：闪光配色 / 加成都有，但进化时不给主宠解锁闪光（用户 2026-10-21）
var start_shiny_borrowed := false   # 融合对象的当前物种（0 = 没融合；规则 game/pokemon_fusion.gd）
# 百变怪（game/pokemon_starters.gd）：开局选了变成谁时，player_species_id = 被选物种（外观 / 属性 / 招式 / 学习表），
# 这个标记让六维种族值 ×0.8、经验曲线用百变怪自己的、不进化。
var player_is_ditto := false
# 默认占位个体参数与 ui/town.gd 取同一个来源（game/pokemon_growth.gd 的常量 / 25 性格表）。
var player_ivs: Array = PokemonGrowth.DEFAULT_IVS.duplicate()
var player_nature_id := PokemonGrowth.DEFAULT_NATURE_ID
var player_nature: Array = [1, 1, 1, 1, 1, 1]
var player_stats: Array[int] = []
# 玩家临时防御等级：原作变硬 StatChangeAttr 给自身 DEF +1，范围 0..6（每次 +1）。
# 不写进基础六维 player_stats、不碰种族值 / 等级公式；只在受物理伤害时由 PokemonDamage
# 的 def_stage 参数换算等级倍率。进入新局 main.gd 重置 0；普通升级 / 进化重算六维不碰它。
var player_def_stage := 0
# 玩家其余能力等级（第二批招式：磨爪 / 龙之舞 / 高速移动 / 蓄能焰袭 / 近身战 / 钢翼等写自己）[-6,6]。
# atk / spatk 进玩家出招伤害公式的 atk_stage；acc 进玩家命中判定；spd 进移动速度；spdef 只记录
# （敌人目前没有特殊攻击）。进入新局重置 0；与 player_def_stage 同一套范围与规则。
var player_atk_stage := 0
var player_spatk_stage := 0
var player_spdef_stage := 0
var player_spd_stage := 0
var player_acc_stage := 0
# 聚气（原 CRIT_BOOST 标记）：自己会心阶段 +2，不叠加；进入新局重置。
var player_crit_boost := false
# 特性：玩家当前特性（起始页选的栏位，进化沿用栏位）与被动（糖果解锁后才生效，player_passive_on）。
var player_ability := ""
var player_ability_slot := 0
var player_passive := ""
var player_passive_on := false
var player_fire_boost_until := 0.0     # 引火：这之前自己的火属性招 ×1.5
var _ab_next := 0.0                    # 特性周期结算下一次时刻（run_clock 秒）
var _ab_moody_next := 0.0
var _ab_speed_next := 0.0
var _ab_shed_next := 0.0
var _ab_terrain_next := 0.0
var _last_crit := false                # 最近一次伤害公式有没有会心（狙击手 / 愤怒穴位读）
# 第三批 B 档的限时效果（时间用 run_clock，单位秒，只在 _attack_tick 里前进；进入新局重置）：
var run_clock := 0.0
var player_crit_boost_until := 0.0
var player_stage_until := {}          # 能力 → 该项能力等级消退的时刻（改动一次刷新一次 20 秒）
var player_screen_phys_until := 0.0   # 反射壁：物理伤害 ×0.5
var player_screen_spec_until := 0.0   # 光墙：特殊伤害 ×0.5
var player_charged_until := 0.0       # 充电：下一次电系招威力 ×2
var player_curled_until := 0.0        # 变圆：滚动威力 ×2
var rollout_count := 0                # 滚动已连续命中次数
var rollout_last := 0.0
var last_used_move := ""              # 模仿用：自己招式栏里上一个刚用过的招
# 受击记录（双倍奉还 / 恶意追击 / 以牙还牙 / 瞬间移动用，用户 2026-10-17：“受到攻击后下次攻击 2 倍”）：
# 每受一次伤害序号 +1；每个招各自记着“上次用掉的序号”，所以每挨一下每个招最多蓄到一次（窗口 6 秒）。
var hurt_serial := 0
var hurt_at := -1000.0
var hurt_phys_serial := 0       # 最近一次受到物理招伤害的序号 / 时刻 / 伤害 / 来源
var hurt_phys_at := -1000.0
var hurt_phys_dmg := 0.0
var hurt_phys_src = null
var hurt_used: Dictionary = {}
var _cast_power_mult := 1.0     # 这一次出招的威力倍率（受击蓄势招用）
# 亲密度（迁怒 / 报恩）：原版从物种基础亲密度起步，每打赢一场 +2；这里每过一波 +2，上限 255。
var player_friendship := 50
var player_shield := ""           # 月桂式护盾：""（没有）/ "protect"（挡下一次伤害）/ "endure"（挡下一次致命伤害，留 1 点血）
var shield_ready_at := 0.0        # 护盾破掉之后要到这个时刻才能再放
var player_semi_kind := ""      # 半隐身蓄力在哪：underground（挖洞）/ air（飞翔、弹跳）/ water（潜水）/ void（暗影潜袭）
var player_semi_until := 0.0
var player_protect_until := 0.0   # 护盾刚破的一小段缓冲：这之前敌人的伤害全挡（同一帧好几只怪一起打不会连破）
var consec_id := ""               # 连续命中加威力的招（连斩）：上次用的是哪招
var consec_count := 0             # 已连续命中几次
var weather := ""        # 天气："" / "rain" / "sun" / "sand" / "snow"（求雨 / 大晴天 / 沙暴 / 冰雹·雪景）；两边（玩家和敌人）共用
var weather_until := 0.0
var weather_next := 0.0  # 沙暴 / 冰雹下一次削血的时刻
var map_weather := ""    # 地图本身的天气（原版每场战斗按地区天气表掷，本作每分钟掷；招式召来的天气到期后回到它）
var map_weather_wave := -1
var weather_roll := Callable()   # 测试注入地图天气骰；默认随机
var terrain := ""        # 场地："" / "electric" / "grassy" / "misty" / "psychic"
var terrain_until := 0.0
var terrain_next := 0.0  # 青草场地下一次回血的时刻
var pending_strikes: Array = []   # 蓄力中的招：[{"id", "due", "target"}]，到点自动出击（挖洞 / 飞翔 / 弹跳 / 神鸟猛击 …）
var hurt_spec_serial := 0         # 最近一次受到特殊招伤害（镜面反射用）；hurt_any_* = 最近一次任何伤害（金属爆炸 / 复仇用）
var hurt_spec_at := -1000.0
var hurt_spec_dmg := 0.0
var hurt_spec_src = null
var hurt_any_dmg := 0.0
var hurt_any_src = null
var player_lock_on := false       # 锁定 / 心眼：下一次出招必中
var rest_until := 0.0             # 睡觉：这之前不能出招（回满血）
var regen_until := 0.0            # 水流环 / 扎根：这之前每秒回 1/16 最大 HP
var regen_next := 0.0
var float_until := 0.0            # 电磁飘浮：这之前免疫地面招
var player_shield_move := ""      # 当前护盾是哪一招放的（尖刺防守等破盾时反伤）
var game_speed := 1.0       # 游戏速度系数（设置页可调）：整个战斗世界的时间流速
var enemy_density := 1.0    # 敌人密度系数（设置页可调）：刷怪率和成群事件的数量倍率
var capture_ring_scale := 1.0   # 捕捉圈大小系数（设置页可调）：乘在 BALL_AIM_RADIUS 上
var shiny_hp_scale := 1.0       # 闪光宠物血量倍率（设置页可调，默认 2）：刷出闪光时血量 × 这个（和神兽倍率叠乘）
var legendary_hp_scale := 1.0   # 神兽血量倍率（设置页可调，默认 4）：刷出神兽时它的血量 × 这个，不然两下就打死、只能满血抓（用户 2026-10-18）
var attack_cd_scale := 1.0     # 攻击冷却系数（设置页可调）：乘在所有玩家招式的冷却上（1.0 = 原冷却，越小招放得越快）
var learn_plan: Array = []   # 学招计划（选宠页勾的，最多 4 个）：空 = 照旧每次问
var learn_plan_on := true   # 局里的“学招计划”开关（技能开关那排，有计划才显示；关掉 = 照旧每次问）
const PLAN_TOGGLE_ID := "__plan__"
# 招式按类型生效（用户 2026-10-24）：强化自己的招只生效一次不叠层；回血招血低于一定比例才自动放、冷却长；
# 天气 / 场地招冷却拉长（持续 20 秒、冷却 40 秒）。老检查要旧口径时把下面几个变量改回去。
const MOVE_SLOT_ITEM := "MOVE_SLOT"
var buff_once := true              # 强化自己的招（剑舞 / 高速移动…）这局只放一次
var buff_done := {}                # 已经放过的强化招
var _evo_declined := {}            # 暂缓过的进化：目标物种 → 暂缓时的等级（几级以内不再问）
var evo_decline_levels := 5        # 暂缓后几级内不再问（0 = 旧口径：每次升级都再问；老检查用）
var buff_base := {}                # 被动强化的“底子”：能力 → 等级（20 秒消退时回到这里而不是 0）
var heal_gate_ratio := 0.5         # 回血招：血量低于最大血量的这个比例才自动放（0 = 旧口径，随时放）
const HEAL_AUTO_CD := 40.0         # 回血招自动触发后的冷却（和 game/pokemon_move_roles.gd HEAL_CD 一致）
const FIELD_MOVE_MIN_CD := 40.0    # 天气 / 场地招的冷却下限（持续 20 秒 → 开着一半时间；同 FIELD_CD）
var field_cd_on := true
# 降能力的招改成光环（用户 2026-10-24“可以好评”）：带着就让标准攻击圈里的怪各降一次，不再自动放。
var aura_on := true
var _aura_clock := 0.0
const AURA_TICK := 0.25
# 护盾 / 减伤改成常驻被动（用户 2026-10-24：参考吸血鬼幸存者的护甲）：带着就一直减伤，但比原作减半弱。
var screens_passive := true
# 倍率在 game/pokemon_move_roles.gd：反射壁（物理）/ 光墙（特殊）×0.7，极光幕都 ×0.8
var spare_special := true   # 手下留情：开着时你的招打不死闪光 / 神兽（最多剩 1 血）；技能开关那排最后一块，暂停时点（用户 2026-10-24）
const SPARE_TOGGLE_ID := "__spare__"
var player_base_stats: Array = []   # 这局实际用的种族值（详情页六边形图）
var player_special_form: Dictionary = {}   # 这局买超级石 / 极巨菇变成的形态（空 = 普通；再进化就清掉，game/pokemon_special_forms.gd）
var amulet_active := -1   # 这局用几层护身金币（-1 = 全用；局里点图标调，不存档）
var points_rate_scale := 1.0    # 局内点数获取倍率（设置页可调）：击杀点数 × 它；小数部分攒着，攒够 1 点再给
var _points_frac := 0.0
var attack_range_scale := 1.0   # 攻击距离系数（设置页可调）：乘在所有玩家招式的射程上
var enemy_range_scale := 1.0    # 敌人攻击距离系数（设置页可调）：乘在敌人远程射程和贴身挥击距离上
var squad_on := false           # 设置里的“自爆小队”（用户 2026-10-25：会很折磨，弄个开关；默认关）
var newbie_tips := true          # 设置里的“新手提示”（默认开）
# 教学关（用户 2026-10-24 点子：“八大胡的巨大化进化扫图 2 分钟然后全指导”）：新存档第一次出发先玩 2 分钟，
# 主角是超极巨化的巴大蝶（绿毛虫进化到底的样子），按步骤教走位 / 技能开关 / 抓宠 / 商店 / 撤离，到时间自动收尾回选宠页。
var tutorial_mode := false
# 补给站（用户 2026-10-25）：撤离选好新地区后弹出，暂停，能买城镇那些培养道具，买了马上生效。
var supply_on := true      # 老检查关掉它，撤离后直接进新地区
var supply_open := false   # 补给站开着：购买入口当成“在城镇”，对象是这局的首发
const TUTORIAL_SPECIES := 12          # 巴大蝶
const TUTORIAL_LEVEL := 30
const TUTORIAL_SECS := 120.0
const TUTORIAL_RARE := 133            # 教学里送上门的稀有：伊布
var _tut_shown := {}
var _tut_rare = null                  # 教学刷出来的那只伊布（Enemy）
var _tut_finishing := false
var _tut_caught: Array = []           # 教学里抓到的（结尾告诉玩家）
var _tips_shown := {}            # 这一局已经提示过的（每局每条最多一次）
const NEWBIE_CAUGHT_MAX := 4     # 抓到的宝可梦不超过这么多只 = 新手（看存档进度，不另记）
var outline_uncaught := false   # 设置里的“没抓过的宝可梦描边”（用户 2026-10-24）
const UNCAUGHT_OUTLINE_COLOR := Color(0.45, 1.0, 0.45)   # 绿色，和闪光金 / 头目红 / 圈里青白区分
var show_ranges := false        # 设置里的“显示攻击范围”：画主角和附近敌人的范围圈
var xp_rate_pct := 100   # 经验护符加成实际生效百分比（设置页可调，0 = 原经验，100 = 买到的全部）
var candy_levels := 0    # 本局开局靠神奇糖果加的等级（敌人等级下限按“去掉糖果”的等级算）
var entry_wave := 0   # 入场波次（城镇选入场等级换算；0 = 地区带起点）
var endless := true   # 无尽波次：不再有 20 分钟终点，最终头目改成普通头目，只在倒下时结算
# 毕业（用户 2026-10-25：“设置 20 或者 30 分钟毕业，想继续那就是无限模式”，我定 30 分钟）：
# 局内时间到了先记一次通关，再问“毕业结算 / 继续无限模式”；继续就照常打到倒下。0 = 关（老检查用）。
var graduate_seconds := 1800.0
var graduated := false
var map_id := "plains"   # 本局当前地区（出发时按城镇选择；撤离后换成新地区）
const MAP_GRACE_SECS := 60.0   # 换图缓坡：撤离到新地区后多少秒内敌人降级
const MAP_GRACE_LEVELS := 5.0   # 刚进去时低几级（线性回到 0）
var map_time_start := 0.0   # 进当前地区时的局内时间（撤离后重算；等级带 / 撤离倒计时按“在这个地区待了多久”算）
var evac_ready := false     # 这个地区待满 EVAC_SECONDS，可以撤离了
const EVAC_SECONDS := 300.0   # 用户 2026-10-20：5 分钟后可以撤离去下一个地图
# 击杀经验系数（用户 2026-10-17：“我经常 10 分钟已经 90 多级了”）：原作一场战斗只打 1 只怪，本作 20 分钟要杀 2000+ 只，
# 每只都按原公式给满经验 → 10 分钟就 90 多级，一局里的高等级内容（等级带）根本用不上。拾取经验球时先乘这个系数，
# 已撤回 1.0（用户 2026-10-17）；这条通路只留给调试 / 老检查。
var kill_xp_scale := 1.0   # 经验系数撤掉（用户 2026-10-17）：节奏改由“敌人等级跟着玩家等级走”自然拉住
var battle_wave_scaling := true   # 等级带开关（false = 老口径：战斗波次 = 真实第几分钟；只给老检查用）
var _item_evolution_to := 0   # 局内商店买了进化道具后要进化成的物种（0 = 没有）；离开商店后由进化事件接着走
var friendship_wave := 1
# 事件型选择：同一时刻最多一个事件泵；_event_pending = 有一次真实升级待检查进化，
# _pending_learns = 排队等学习的招式（普通升级 / 进化后的原表学习 + 满四招换招请求），
# _learning_move = 当前已经取出、正在等玩家选择的那一个（防止已在等待的同招被重复排队）。
# _learn_floor = 本批升级“升级前等级 + 1”，即原 getLevelMoves(lastLevel+1) 的下界 t；0 = 无待处理批次。
# event_token 用于异步有效性校验。
var evolving := false
var _evolution_finished := false
# 当前在播的进化演出节点（没有就是 null）；取消 / 死亡 / 退出 / 重开时由 _cancel_events 释放。
var _evolution_fx: Node = null
var _event_pump_running := false
var _event_pending := false
var _pending_learns: Array[String] = []
var _learning_move := ""
var _learn_floor := 0
var event_token := 0
var choice_page: Node = null
# 当前实际掌握的招式（最多 MOVES.MAX_SLOTS 个）。arts 自动释放、HUD、结算都读它。
# move_lv 仍固定 1，学习 / 替换只换招式，不涨等级。
var active_moves: Array[String] = ["tackle", "string_shot"]
# 招式计时 / 释放计数（真现在 arts.gd 的 _attack_tick / _refresh_moves 里维护）。
# 在基类声明是因为 combat.gd 的异常阻断分支要读 / 写它，而 combat 在 arts 之上。
var move_timer := {"tackle": 0.2, "string_shot": 0.4}
var move_casts := {"tackle": 0, "string_shot": 0}
var player_hp := 0.0
const EARLY_SASH_SECS := 120.0   # 新手保护窗口：开局这么多秒内满血挨的第一下不致命
var early_sash_used := false
# 主角自己的异常状态 + 实时状态钟（与每个 Enemy 各一份、互不共用）。
# 状态马上可见：附加成功后由 arts 立刻刷新 HUD 标识与头顶反馈。
var player_status: PokemonStatus = PokemonStatus.for_game()   # 持续伤害 4 秒一结算
# 原版“每回合”按最大 HP 比例掉血 / 回血的效果几秒结算一次（用户 2026-10-22 定 4；中毒 / 灼伤 / 剧毒 / 天气 / 场地 / 水流环 / 寄生种子 / 缠绕）。
# 只测原版公式的老检查把它设回 1（= 每秒一回合）。
var residual_secs := 4.0
var _bell_pool := 0.0    # 贝壳之铃：这一秒攒的伤害
var _bell_clock := 0.0
var player_clock: StatusClock = StatusClock.new()
var player_status_blocked := false   # 当秒行动判定缓存：true = 这一秒不出招
# 当秒阻断是不是**主要异常**造成的（睡眠 / 冰冻 / 麻痹）。商店全复药只清主要异常，
# 清完只解除这部分缓存，不碰混乱造成的当秒阻断（混乱剩余时间与自身秒钟都保留）。
var player_status_blocked_major := false
var player_status_key := ""          # 变化时才重写 HUD 文本
var facing := Vector3(0, 0, 1)
var moving := false
var was_moving := false
var capture := false
var stress := 0
var debug_power := 1.0
var card_defs := {}
var card_lv := {}
var move_lv := {"tackle": 1, "string_shot": 1}
var player_portrait: Texture2D
var settled := false
var result_done := false

func _shot(path: String) -> void:
    if DisplayServer.get_name() == "headless":
        return
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
    get_viewport().get_texture().get_image().save_png(path)
    print("SHOT ", ProjectSettings.globalize_path(path))

# combat 调用的上层实现。
func _drop_potion(_pos: Vector3) -> void:
    push_error("_drop_potion missing")
func _boss_reward(_final: bool, _boss_name := "") -> void:
    push_error("_boss_reward missing")

# ================= 击杀点数接线（唯一事实在 game/pokemon_points.gd）=================
# 每个新局 / 场景 reload 后都重新读同一份持久余额（不是只加载一次的全局单例），本局计数归零。
# 保存失败时内存里仍保留这次进账，但必须让玩家看见“未保存”，不把没落盘的余额冒充成已保存。
var points_unsaved := false        # HUD 上有“未保存”标记；成功落盘后清掉
var points_fail_announced := false # 同一段失败只弹一次横幅，不每一击刷通知
var _corrupt_announced := false    # 坏档提示一次会话只弹一次

func _points_begin_run() -> void:
    points_wallet = Points.new(points_path)
    points_wallet.begin_run()
    # 读到坏档 / 恢复失败时同样标成未保存：不能静默显示成“已成功持久化”。
    points_unsaved = points_wallet.is_corrupt()
    points_fail_announced = false
    if points_unsaved and not _corrupt_announced:
        _corrupt_announced = true   # 一次会话只提示一次
        var msg := "存档读不出来（%s），已停止写入，原档不动。每天的备份在 %s，可以拿一份改名成 %s 换回来。" % [
            points_wallet.last_error, ProjectSettings.globalize_path(points_wallet.backup_dir()), points_path.get_file()]
        push_warning(msg)
        if town_page != null and town_page.has_method("show_message"):
            town_page.show_message(msg)
        elif hud != null:
            hud.show_banner(msg)
    if hud != null and hud.has_method("set_points_unsaved"):
        hud.set_points_unsaved(points_unsaved)

# 一次性加点数（金珠）：也吃护身金币；返回实际加了几点。
func _points_award_flat(n: int) -> int:
    if points_wallet == null:
        _points_begin_run()
    var give := int(floorf(float(n) * (1.0 + 0.2 * _global_charm("AMULET_COIN"))))
    if give <= 0:
        return 0
    var result: Dictionary = points_wallet.award(give)
    points_unsaved = not bool(result.get("ok", false))
    if hud != null and hud.has_method("set_points_unsaved"):
        hud.set_points_unsaved(points_unsaved)
    return give


# combat._kill 在真正死亡（只一次）时调：+1 点并立即落盘，不等捡球 / 结算。
# 落盘成功 -> 清未保存标记；失败（写失败 / 坏档锁定）-> 标记 + 用现有横幅提示一次，内存保留进账。
func _points_award_kill(enemy_level := 0, boss := false) -> void:
    if points_wallet == null:
        _points_begin_run()
    # 生蛋：每打死一只，所有蛋 +1（不按时间按击杀，用户 2026-10-23）；孵出来的弹“蛋孵化了”卡片
    for egg: Dictionary in points_wallet.progress_eggs(1):
        var hid := int(egg["species"])
        if hud != null and hud.has_method("show_dex_entry"):
            hud.show_dex_entry(preload("res://ui/rogue_ui.gd").species_icon(hid, int(egg.get("shiny", -1)) >= 0), hid, str(call("_species_name", hid)), int(egg.get("shiny", -1)), "蛋孵化了！")

    var coin := 1.0 + 0.2 * _global_charm("AMULET_COIN")   # 护身金币：每层 +20%
    var punch := 1.0 + HeldItems.GOLDEN_PUNCH_KILL_BONUS * int(run_held.get("GOLDEN_PUNCH", 0))
    var base := float(Points.kill_points_for(enemy_level, boss)) * points_rate_scale * coin * punch + _points_frac
    var give := int(floorf(base))
    _points_frac = base - float(give)
    if give <= 0:
        return
    var result: Dictionary = points_wallet.award(give)
    if bool(result.get("ok", false)):
        points_unsaved = false
        points_fail_announced = false
        if hud != null and hud.has_method("set_points_unsaved"):
            hud.set_points_unsaved(false)
        return
    points_unsaved = true
    if hud != null and hud.has_method("set_points_unsaved"):
        hud.set_points_unsaved(true)
    if not points_fail_announced:
        points_fail_announced = true
        if hud != null:
            hud.show_banner("点数保存失败，本局点数暂未保存")

func _points_total() -> int:
    return points_wallet.balance if points_wallet != null else 0

func _points_run() -> int:
    return points_wallet.run_points if points_wallet != null else 0


# ================= 商店接线（唯一规则在 game/pokemon_shop.gd，落盘在 game/pokemon_points.gd）=================
# 后端只信商品 ID：地点 / 战斗状态由这里校验，价格 / 上限 / 药效全部重新查表；不接收 UI 传入的数值。
# 局内五种伤药只在「真实战斗 + 商店暂停」且当前上场那只活着 / 未死亡 / 未结算 / 未进化换招时购买即用；
# 城镇全体护符（两种经验 + 治愈）只在城镇购买：不能在战斗里买全体成长，也不能在城镇治伤。
func _shop_owned() -> Dictionary:
    if points_wallet == null:
        return {}
    return points_wallet.charm_stacks.duplicate()


# 本局球库存的可读快照（source_id -> 数量）；只给 UI 显示，后端永远读 ball_counts 本体。
func _shop_ball_counts() -> Dictionary:
    var out := {}
    for ball_type in range(ball_counts.size()):
        out[PokemonShop.ball_source_id(ball_type)] = int(ball_counts[ball_type])
    return out


func _shop_order() -> Array:
    if points_wallet == null:
        return []
    return points_wallet.charm_order.duplicate()


# 当前治愈护符层数 -> 原 HealingBoosterModifier 倍率（1 + 0.1*stacks）；无钱包 = 1.0。
func _healing_multiplier() -> float:
    if points_wallet == null:
        return 1.0
    return PokemonShop.healing_multiplier(points_wallet.owned_stacks(PokemonShop.HEALING_CHARM))


# 局外购买的场合：没开局，且城镇商店（mode == "town"）开着，或选宠页（town_page）开着（糖果 / 技能机器 / 开局招直接在选宠页里操作）。

func _in_town_context() -> bool:
    if supply_open:
        return true
    if started:
        return false
    if town_page != null and town_page.is_open():
        return true
    return shop_page != null and shop_page.has_method("mode") and str(shop_page.call("mode")) == "town"


# 购买入口：只认商品 ID。三分支：局内伤药 / 城镇全体护符 / 其余一律拒买。
func _shop_buy(source_id: String) -> Dictionary:
    if PokemonShop.exp_banned(str(source_id)):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)   # 经验加成已禁（2026-10-25）
    if PokemonShop.is_purchasable(source_id) and (shop_page == null or not shop_page.is_open()) and not _in_town_context(): return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if points_wallet == null:
        _points_begin_run()
    var sid := str(source_id)
    var result: Dictionary
    if sid.begins_with(STARTER_PREFIX):
        result = _shop_toggle_starter(sid)
    elif TMRules.is_product(sid):
        result = _shop_buy_tm(sid)
    elif PokemonBerries.is_product(sid):
        result = _shop_buy_berry(sid)
    elif PokemonMemory.is_product(sid):
        result = _shop_buy_memory(sid)
    elif PokemonLens.is_product(sid):
        result = _shop_buy_lens(sid)
    elif HeldItems.is_product(sid):
        result = _shop_buy_held(sid)
    elif sid.begins_with("EGGMOVE:"):
        result = _shop_toggle_egg_move(sid)
    elif SpecialForms.is_product(sid):
        result = _shop_buy_special_form(sid)
    elif PokemonEvolution.is_product(sid):
        result = _shop_buy_evolution_item(sid)
    elif PokemonShop.is_stat_drink(sid):
        result = _shop_buy_stat_drink(sid)
    elif PokemonShop.is_town_candy(sid):
        result = _shop_buy_candy(sid)
    elif PokemonShop.is_run_ball(sid):
        result = _shop_buy_ball(sid)
    elif PokemonShop.is_run_medicine(sid):
        result = _shop_buy_medicine(sid)
    elif PokemonShop.is_town_charm(sid):
        result = _shop_buy_town_charm(sid)
    else:
        result = PokemonShop.purchase(points_wallet, sid)
    _refresh_shop_candy()
    if shop_page != null and shop_page.has_method("update_state"):
        _push_shop_extras()
        shop_page.update_state(_points_total(), _points_run(), _shop_owned(), _shop_ball_counts())
        if shop_page.has_method("show_message"):
            shop_page.show_message(_shop_message(sid, result))
    if town_page != null and town_page.has_method("set_points"):
        town_page.set_points(_points_total())
    if started and stats != null:
        _hud_stats()
    return result


func _shop_reject(source_id: String, status: String) -> Dictionary:
    return {
        "ok": false, "status": status, "source_id": source_id,
        "price": PokemonShop.price(source_id), "balance": _points_total(),
        "run_points": _points_run(), "stacks": _shop_owned(), "order": _shop_order(),
    }


# 城镇全体护符（两种经验 + 治愈）：只在城镇（未出发）购买，扣款 + 加层用同一份完整快照。
# 神奇糖果的购买对象 = 城镇图鉴里当前选中的宝可梦（默认 #10 或已捕获的才能买，免得给没解锁的白花点数）。
func _candy_target() -> int:
    if supply_open:
        return run_starter_id
    if town_page != null and town_page.has_method("selected_pokemon_id"):
        return int(town_page.call("selected_pokemon_id"))
    return 10


func _candy_target_ok(sid: int) -> bool:
    return sid == 10 or (points_wallet != null and points_wallet.is_species_unlocked(sid))


# 物种名等资料（combat.gd 里有同一份 PokemonStarters；state.gd 在它的上游，这里单独取一次）。
func _starter_profile(sid: int) -> Dictionary:
    return preload("res://game/pokemon_starters.gd").profile(sid)


# 全体加成（城镇买的护符）这一种有几层；没钱包 = 0。
func _global_charm(id: String) -> int:
    var n := int(points_wallet.charm_stacks.get(id, 0)) if points_wallet != null else 0
    if id == "AMULET_COIN" and amulet_active >= 0:
        n = mini(n, amulet_active)   # 局里点左上角图标选的层数（用户 2026-10-23）
    return n


# 局里点左上角护身金币图标：左键 +1 层、右键 -1 层，在 0..买了的层数之间转。
func _cycle_amulet(step: int) -> void:
    var owned := int(points_wallet.charm_stacks.get("AMULET_COIN", 0)) if points_wallet != null else 0
    if owned <= 0:
        return
    var cur := _global_charm("AMULET_COIN")
    amulet_active = posmod(cur + step, owned + 1)
    if hud != null and hud.has_method("set_effects"):
        hud.set_effects(call("_run_effects"))


# 闪光给镜片加几级（融合时两只相加）。
func _shiny_lens_bonus() -> int:
    return player_shiny_bonus if player_shiny_bonus >= 0 else PokemonLens.shiny_bonus(player_shiny_variant)


# 刷新商店里神奇糖果那一行要显示的“为谁买 / 已买几颗”（只读，不改任何状态）。
func _refresh_shop_candy() -> void:
    _push_evolution_items()
    if shop_page != null and shop_page.has_method("set_lens_levels") and points_wallet != null:
        var lsid := _candy_target()
        shop_page.set_lens_levels({"support": points_wallet.lens_for(lsid, "support"), "attack": points_wallet.lens_for(lsid, "attack"), "capture": points_wallet.lens_for(lsid, "capture")})
        if shop_page.has_method("set_held_items"):
            var hrows: Array = []
            var neutral_nature := (PokemonGrowth.nature_multipliers(points_wallet.nature_pick_for(AB.root_of(lsid))) as Array).all(func(x): return is_equal_approx(float(x), 1.0))
            for it: String in HeldItems.shop_items(_starter_profile(lsid).get("types", []), lsid):
                if it == "SOUL_DEW" and neutral_nature:
                    continue   # 中性性格（默认勤奋）：心之水滴放大的是性格加减，没有加减就白买，不卖（2026-10-22 审查）
                hrows.append({"item": it, "count": points_wallet.held_for(lsid, it)})
            shop_page.set_held_items(hrows)
    if shop_page == null or not shop_page.has_method("set_candy_target"):
        return
    var sid := _candy_target()
    var nm := ""
    var prof: Dictionary = _starter_profile(sid)
    if not prof.is_empty():
        nm = str(prof.get("name", ""))
    var count := points_wallet.candy_for(sid) if points_wallet != null else 0
    var evs: Array = points_wallet.ev_for(sid) if points_wallet != null else [0, 0, 0, 0, 0, 0]
    var starter_rows: Array = []
    var benched_now: Array = points_wallet.tm_bench_for(sid) if points_wallet != null else []
    var carried_now := _carried_loadout(sid)
    for m in _starter_pool(sid):
        starter_rows.append({"id": str(m), "benched": benched_now.has(str(m)), "carried": carried_now.has(str(m))})
    var tm := {"learnable": TMRules.learnable_fused(sid, _fusion_of(sid)), "slots": _tm_slots(sid), "starters": starter_rows,
        "owned": _owned_tms(sid), "carried": carried_now, "move_slots": _move_slots(sid),
        "equipped": _equipped_tms(sid)}
    shop_page.call("set_candy_target", sid, nm, count, _candy_target_ok(sid), evs, tm)


# ================= 进化道具（局内商店，用户 2026-10-17：“局内还要有进化道具卖”）=================
# 当前上场的宝可梦现在能用的进化道具（石头 / 联系绳…，来自进化表的 item 项，目标物种本作有才列）。
# 普通进化道具 = 优秀档 30 点，稀有进化道具 = 究极档 100 点（原 EVOLUTION_ITEM / RARE_EVOLUTION_ITEM 档）。
func _evolution_item_rows() -> Array:
    var rows: Array = []
    if not started or player_is_ditto or dead:
        return rows
    for o: Dictionary in PokemonEvolution.shop_options(player_species_id, level):
        var to := int(o["to"])
        rows.append({"id": PokemonEvolution.product_id(str(o["item"]), to), "item": str(o["item"]),
            "name": PokemonEvolution.item_name(str(o["item"])), "to": to,
            "to_name": str(_starter_profile(to).get("name", str(to))),
            "price": PokemonEvolution.price(str(o["item"])), "rare": PokemonEvolution.is_rare_item(str(o["item"])),
            "note": str(o.get("note", ""))})
    return rows


func _push_evolution_items() -> void:
    if shop_page != null and shop_page.has_method("set_run_evolutions"):
        shop_page.call("set_run_evolutions", _evolution_item_rows() + _special_form_rows(), str(_starter_profile(player_species_id).get("name", "")), _item_evolution_to > 0)


# 局内商店的超级石 / 极巨菇：当前上场这只有的、还没变成的形态（百变怪不卖）。
func _special_form_rows() -> Array:
    var rows: Array = []
    if not started or player_is_ditto or dead:
        return rows
    var base_name := str(call("_species_name", player_species_id))
    for f: Dictionary in SpecialForms.forms_for(player_species_id):
        if str(player_special_form.get("form_key", "")) == str(f["form_key"]):
            continue
        rows.append({"id": SpecialForms.product_id(player_species_id, str(f["form_key"])), "form": str(f["form_key"]),
            "kind": str(f["kind"]), "name": SpecialForms.item_name(f), "to_name": SpecialForms.display_name(base_name, f),
            "price": SpecialForms.price(f), "rare": true, "item": str(f.get("item", "")), "note": _special_form_preview(f)})
    return rows


# 买之前的预览（用户 2026-10-24）：种族值怎么变、属性、特性。
func _special_form_preview(f: Dictionary) -> String:
    var cur: Array = player_base_stats
    var nxt: Array = f.get("stats", [])
    var labels := ["HP", "攻", "防", "特攻", "特防", "速"]
    var parts: Array = []
    for i in mini(6, mini(cur.size(), nxt.size())):
        var d := int(nxt[i]) - int(cur[i])
        parts.append("%s%d%s" % [labels[i], int(nxt[i]), "" if d == 0 else ("(+%d)" % d if d > 0 else "(%d)" % d)])
    var abil: Array = f.get("abilities", [])
    var ab := AB.name_of(str(abil[0])) if not abil.is_empty() else ""
    return "种族值 %s · 属性 %s · 特性 %s" % [" ".join(parts), "/".join(f.get("types", [])), ab]


# 局内买超级石 / 极巨菇：扣点数成功就立刻变身（在商店里就变，离开商店就是新形态）。
func _shop_buy_special_form(source_id: String) -> Dictionary:
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var info := SpecialForms.parse(source_id)
    var form := SpecialForms.form_of(int(info.get("species", 0)), str(info.get("form_key", "")))
    if form.is_empty() or int(info["species"]) != player_species_id or player_is_ditto or str(player_special_form.get("form_key", "")) == str(form["form_key"]):
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    var price := SpecialForms.price(form)
    var spend: Dictionary = points_wallet.spend(price)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = source_id
        spend["price"] = price
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    _apply_special_form(form)
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = source_id
    out["price"] = price
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


func _apply_special_form(form: Dictionary) -> void:
    player_special_form = form.duplicate(true)
    call("_recalculate_player_stats")
    call("_refresh_player_species_visual")
    if hud != null:
        hud.show_banner("%s！" % SpecialForms.display_name(str(call("_species_name", player_species_id)), form))
        if hud.has_method("set_effects"):
            hud.set_effects(call("_run_effects"))


# 局内买进化道具：扣点数成功后记下要进化成谁，离开商店（继续游戏）后由进化事件接着播；
# 同一时刻只留一个待进化目标。只在“真实战斗 + 商店暂停 run”时买，选项必须是现在这只宝可梦当前能用的。
# 局外买多重镜：给选中的那只宠物升一级（和买神奇糖果一样：只在城镇、要选一只已捕获的）。
func _shop_buy_lens(source_id: String) -> Dictionary:
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    if not _candy_target_ok(sid):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if points_wallet == null:
        _points_begin_run()
    var kind := PokemonLens.kind_of(source_id)
    var result: Dictionary = points_wallet.buy_lens(sid, kind)
    result["source_id"] = source_id
    result["species_id"] = sid
    result["kind"] = kind
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


# 局外买携带道具：给选中那只的这一系加一个（和镜片一样：只在城镇、要选一只已捕获的）。
func _shop_buy_held(source_id: String) -> Dictionary:
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    if not _candy_target_ok(sid):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if points_wallet == null:
        _points_begin_run()
    var item := HeldItems.item_of(source_id)
    var result: Dictionary = points_wallet.buy_held(sid, item)
    result["source_id"] = source_id
    result["species_id"] = sid
    result["item"] = item
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


# 记下一招被换掉了（记忆蘑菇能把它想起来）。
func _note_forgotten(move_id: String) -> void:
    if move_id != "" and not run_forgotten.has(move_id):
        run_forgotten.append(move_id)


# 记忆蘑菇能恢复的招：在城镇用技能机器学过但没带的 + 这一局被新招换掉的（用户 2026-10-19：“记忆蘑菇没有用处”）。
# 局内不卖技能机器，所以第一类只来自局外买的机器。
func _forgotten_tm_moves() -> Array:
    var out: Array = []
    if points_wallet != null:
        for m in _owned_tms(run_starter_id):   # 融合对象买的也算（2026-10-22 审查）
            var mid := str(m)
            if MOVES.is_implemented(mid) and not active_moves.has(mid) and not out.has(mid):
                out.append(mid)
    for m in run_forgotten:
        var fid := str(m)
        if MOVES.is_implemented(fid) and not active_moves.has(fid) and not out.has(fid):
            out.append(fid)
    # 原版记忆蘑菇（getLearnableLevelMoves）：现在这个形态学习表里、到当前等级为止能学的招全都算——
    # 含进化招（等级 0）和只能回忆的招（等级 -1），没带的都能想起来（用户 2026-10-20 复查“记忆蘑菇没有用处”）。
    for lm in MOVES.learnable_between(player_species_id, -1, level, true):
        var lid := str(lm)
        if not active_moves.has(lid) and not out.has(lid):
            out.append(lid)
    return out


# 给商店页看的：能恢复哪些招 + 现在带着哪几招（槽满时选替换谁）。每次打开 / 刷新商店前调一次。
func _push_shop_extras() -> void:
    if shop_page == null:
        return
    shop_page.set_berry_counts(berries)
    if shop_page.has_method("set_memory_info"):
        var forgotten: Array = []
        for mid: String in _forgotten_tm_moves():
            forgotten.append({"id": mid, "name": str(MOVES.MOVES[mid]["name"]), "info": _move_info(mid)})
        var current: Array = []
        for mid: String in active_moves:
            current.append({"id": mid, "name": str(MOVES.MOVES[mid]["name"]), "info": _move_info(mid)})
        shop_page.set_memory_info(forgotten, current, _move_slots())


# 局内买记忆蘑菇：恢复一招忘掉的技能机器招。只在真实战斗 + 局内商店暂停时买；
# 招必须是这只在城镇学过且现在没带的；槽满时必须指定替换第几招。先扣点成功才改招。
func _shop_buy_memory(source_id: String) -> Dictionary:
    var info := PokemonMemory.parse(source_id)
    var price := PokemonMemory.PRICE
    if info.is_empty():
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if shop_page == null or not shop_page.has_method("mode") or str(shop_page.call("mode")) != "run":
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var move := str(info["move"])
    var slot := int(info["slot"])
    if not _forgotten_tm_moves().has(move):
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    var full := active_moves.size() >= _move_slots()
    if full and (slot < 0 or slot >= active_moves.size()):
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    if not full and slot >= 0:
        slot = -1
    var spend: Dictionary = points_wallet.spend(price)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = source_id
        spend["price"] = price
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    var replaced := ""
    if slot >= 0:
        replaced = str(active_moves[slot])
        _note_forgotten(replaced)
        active_moves[slot] = move
    else:
        active_moves.append(move)
    disabled_moves.erase(move)
    _refresh_moves()
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = source_id
    out["price"] = price
    out["move"] = move
    out["replaced"] = replaced
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


# 局内买树果：只在真实战斗 + 局内商店暂停时买，每种最多 9 个；先扣点成功才加。
func _shop_buy_berry(source_id: String) -> Dictionary:
    var kind := PokemonBerries.kind_of(source_id)
    var price := PokemonBerries.PRICE
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if shop_page == null or not shop_page.has_method("mode") or str(shop_page.call("mode")) != "run":
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if int(berries.get(kind, 0)) >= PokemonBerries.CAP:
        return _shop_reject(source_id, PokemonShop.ST_AT_MAX)
    # 扣款 + 树果库存同一份快照落盘（树果跨局保留）；失败时钱包自己回滚，不加树果。
    var new_berries: Dictionary = berries.duplicate()
    new_berries[kind] = int(new_berries.get(kind, 0)) + 1
    var spend: Dictionary = points_wallet.spend(price, [], new_berries)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = source_id
        spend["price"] = price
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    berries[kind] = int(berries.get(kind, 0)) + 1
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = source_id
    out["price"] = price
    out["berry"] = kind
    out["berry_count"] = int(berries[kind])
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


func _shop_buy_evolution_item(source_id: String) -> Dictionary:
    var info := PokemonEvolution.parse(source_id)
    var price := PokemonEvolution.price(str(info.get("item", "")))
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if shop_page == null or not shop_page.has_method("mode") or str(shop_page.call("mode")) != "run":
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var valid := false
    for r: Dictionary in _evolution_item_rows():
        if str(r["id"]) == source_id:
            valid = true
    if not valid or _item_evolution_to > 0:
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    var spend: Dictionary = points_wallet.spend(price)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = source_id
        spend["price"] = price
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    _item_evolution_to = int(info["to"])
    _event_pending = true   # 离开商店后 _resume 会重新启动进化事件
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = source_id
    out["price"] = price
    out["evolve_to"] = _item_evolution_to
    out["item"] = str(info["item"])
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


# 城镇买神奇糖果：给选中的那只 +1 颗（开局 +1 级）；只在城镇商店里买。
func _shop_buy_candy(source_id: String) -> Dictionary:
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    if not _candy_target_ok(sid):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if points_wallet == null:
        _points_begin_run()
    var price := PokemonShop.price_at(source_id, points_wallet.candy_for(sid))   # 越买越贵
    var result: Dictionary = points_wallet.buy_candy(sid, price, PokemonShop.CANDY_CAP)
    result["source_id"] = source_id
    result["species_id"] = sid
    result["price"] = price
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


# 这只开局最多带几个技能机器：机器优先占槽（用户 2026-10-22：“买了的技能应该都带”），所以就是 4 个；
# 开局招排在机器后面填剩下的槽。
func _tm_slots(sid: int) -> int:
    return _move_slots(sid)


# 招式槽数：4 + 招式扩展器个数（最多 +2）。sid > 0 读存档里那一系带的道具（城镇 / 开局），否则读这局的 run_held。
func _move_slots(sid := 0) -> int:
    var n := 0
    if sid > 0:
        n = int(points_wallet.held_all(sid).get(MOVE_SLOT_ITEM, 0)) if points_wallet != null else 0
    else:
        n = int(run_held.get(MOVE_SLOT_ITEM, 0))
    return MOVES.MAX_SLOTS + clampi(n, 0, 2)


func _fusion_of(sid: int) -> int:
    return int(points_wallet.fusion_for(sid)) if points_wallet != null else 0


# 这只的开局招候选：融合了就把对象的开局招也算上（用户 2026-10-22：“融合怪物应该 2 个的技能都有”）。
func _starter_pool(sid: int) -> Array:
    return TMRules.starter_pool(sid, _fusion_of(sid))


# 这只能带的技能机器：自己买过的 + 融合对象买过的（用户 2026-10-22：“b 买过的，a+b 的池子里还是有，开局配置带不带”）。
func _owned_tms(sid: int) -> Array:
    if points_wallet == null:
        return []
    var out: Array = points_wallet.tm_owned_for(sid)
    var partner := _fusion_of(sid)
    for src in [sid, partner]:
        if int(src) <= 0:
            continue
        # 自己 / 融合对象买过的机器 + 蛋孵出来的遗传招（生蛋，2026-10-23）
        for m in (points_wallet.tm_owned_for(int(src)) if int(src) != sid else []) + points_wallet.egg_moves_for(int(src)):
            if not out.has(m):
                out.append(m)
    return out


# 选宠页“管理招式”里点遗传招：带上 / 取下（和机器同一份“带着的招”，商品 ID = EGGMOVE:招式）。
func _shop_toggle_egg_move(source_id: String) -> Dictionary:
    var move := source_id.substr("EGGMOVE:".length())
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    var owned := _owned_tms(sid)
    if not _candy_target_ok(sid) or not owned.has(move):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    var result: Dictionary = _toggle_loadout(sid, move)   # 自由选择：点一下带上 / 取下（2026-10-24）
    result["source_id"] = source_id
    result["price"] = 0
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


# 选了要带的机器里现在真能带的（解除融合后对象那边的不算；存档里留着，再融合回来还在）。
func _equipped_tms(sid: int) -> Array:
    var owned := _owned_tms(sid)
    var out: Array = []
    if points_wallet != null:
        for m in points_wallet.tm_equipped_for(sid):
            if owned.has(m):
                out.append(m)
    return out


# 这只开局真正带着的招（开局招 + 机器，最多 4 个；机器优先；没融合时对象那边的机器不算）。
func _carried_loadout(sid: int) -> Array:
    var benched: Array = points_wallet.tm_bench_for(sid) if points_wallet != null else []
    var saved: Array = points_wallet.loadout_for(sid) if points_wallet != null else []
    return TMRules.resolve_loadout(saved, _starter_pool(sid), benched, _owned_tms(sid), _equipped_tms(sid), _move_slots(sid))


# 管理招式里点一下：带着就取下，没带就带上（满了提示、不自动补位；至少留一个能打人的招）。
func _toggle_loadout(sid: int, move: String) -> Dictionary:
    var Starters := preload("res://game/pokemon_starters.gd")
    var cur := _carried_loadout(sid)
    var removing := cur.has(move)
    if removing:
        var rest := cur.duplicate()
        rest.erase(move)
        if rest.is_empty() or not Starters.has_damage_move(rest):
            return {"status": Points.ST_LAST_MOVE, "move": move, "benched": false, "equipped": true}
        cur = rest
    else:
        if cur.size() >= _move_slots(sid):
            return {"status": PokemonShop.ST_AT_MAX, "move": move, "benched": true, "equipped": false}
        cur.append(move)
    if not points_wallet.set_loadout(sid, cur):
        return {"status": "save_failed", "move": move}
    return {"status": Points.ST_SAVED, "move": move, "benched": removing, "equipped": not removing}


# 万一留下 / 换掉之后一个能打人的招都没有（比如存档被改过）：把留在家里的开局招按顺序补回来，直到有能伤害的为止。
func _ensure_damage_move(sid: int) -> void:
    var Starters := preload("res://game/pokemon_starters.gd")
    if player_is_ditto or Starters.has_damage_move(active_moves):
        return
    for m in _starter_pool(sid):
        if active_moves.has(str(m)) or not Starters.has_damage_move([str(m)]):
            continue   # 只补能打人的；已经带着的不重复（原来先弹后判重，可能白丢一个机器）
        if active_moves.size() >= _move_slots(sid):
            active_moves.pop_back()   # 满了（四个都是变化招的机器）：把最后一个让出来
        if not active_moves.has(str(m)):
            active_moves.append(str(m))
            if Starters.has_damage_move(active_moves):
                return


# 城镇：把一个开局招留在家里 / 带上（商品 ID = "STARTER:招式 id"，免费）。
func _shop_toggle_starter(source_id: String) -> Dictionary:
    var move := source_id.substr(STARTER_PREFIX.length())
    var result := {"status": PokemonShop.ST_WRONG_PLACE, "source_id": source_id, "price": 0, "move": move}
    if not _in_town_context():
        return result
    var sid := _candy_target()
    if not _candy_target_ok(sid):
        result["status"] = PokemonShop.ST_NOT_PURCHASABLE
        return result
    if points_wallet == null:
        _points_begin_run()
    if not _starter_pool(sid).has(move):
        result["status"] = PokemonShop.ST_NOT_PURCHASABLE
        return result
    var r := _toggle_loadout(sid, move)   # 自由选择：点一下带上 / 取下（2026-10-24）
    result["status"] = r.get("status", "")
    result["benched"] = r.get("benched", false)
    result["species_id"] = sid
    return result


# 城镇技能机器：没买过 = 买（扣款 + 永久拥有，有空槽自动带上）；买过 = 带上 / 取下切换（不花点数）。
func _shop_buy_tm(source_id: String) -> Dictionary:
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    var move := TMRules.move_of(source_id)
    if not _candy_target_ok(sid) or not TMRules.can_learn_fused(sid, move, _fusion_of(sid)):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if points_wallet == null:
        _points_begin_run()
    var price := TMRules.price(move)
    var slots := _tm_slots(sid)
    var result: Dictionary
    var owned := _owned_tms(sid)
    for old in points_wallet.tm_equipped_for(sid):
        if not owned.has(old):
            points_wallet.set_tm_equipped(sid, str(old), false, slots)   # 解除融合留下的：清掉，不占位（2026-10-22 审查）
    var toggled := owned.has(move)
    if toggled:
        result = _toggle_loadout(sid, move)   # 自由选择：点一下带上 / 取下（2026-10-24）
        price = 0
    else:
        var before := _carried_loadout(sid)
        # 统一按“自选清单”走（2026-10-25）：没调过招的先把现在带的记成清单，免得旧规则在栏满时偷偷顶掉最早的招
        if points_wallet.loadout_for(sid).is_empty():
            points_wallet.set_loadout(sid, before)
        var owned_before := _owned_tms(sid)
        result = points_wallet.buy_tm(sid, move, price, slots)
        # 刚买的机器：有空槽就带上；满了就顶掉最前面一个开局招（机器优先，2026-10-22）；带的全是机器就先放着
        if str(result.get("status", "")) == PokemonShop.ST_PURCHASED and not before.has(move):
            if before.size() < _move_slots(sid):
                before.append(move)
                points_wallet.set_loadout(sid, before)
            else:
                for m in before:
                    if not owned_before.has(m):
                        before.erase(m)
                        before.append(move)
                        points_wallet.set_loadout(sid, before)
                        break
    if not toggled:
        result["equipped"] = _carried_loadout(sid).has(move)
    result["toggled"] = toggled
    result["source_id"] = source_id
    result["species_id"] = sid
    result["move"] = move
    result["price"] = price
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


# 开局招式栏：开局招（融合了两只的都算）+ 带着的技能机器，最多 4 个，机器优先（TMRules.carried）。
func _equip_tm_moves(sid: int) -> void:
    if points_wallet == null:
        return
    active_moves.clear()
    for m in _carried_loadout(sid):
        active_moves.append(str(m))


# 城镇买营养饮料：给选中的那只的这一项努力值 +10（最多 252）；只在城镇商店里买。
func _shop_buy_stat_drink(source_id: String) -> Dictionary:
    if not _in_town_context():
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    var sid := _candy_target()
    if not _candy_target_ok(sid):
        return _shop_reject(source_id, PokemonShop.ST_NOT_PURCHASABLE)
    if points_wallet == null:
        _points_begin_run()
    var price := PokemonShop.price(source_id)
    var result: Dictionary = points_wallet.buy_ev(sid, PokemonShop.stat_index(source_id), price)
    result["source_id"] = source_id
    result["species_id"] = sid
    result["price"] = price
    result["balance"] = _points_total()
    result["run_points"] = _points_run()
    result["stacks"] = _shop_owned()
    result["order"] = _shop_order()
    return result


func _shop_buy_town_charm(source_id: String) -> Dictionary:
    if started:
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    return PokemonShop.purchase(points_wallet, source_id)


# 局内伤药：先校验地点 / 战斗状态 / 是否有实际效果，再真实扣款保存成功，最后才精确治疗；
# 任何一步不满足都不扣不治。药效按原固定 / 百分比分支算好的结果直接落到 HP，
# 不再经过普通 heal 的护符倍率二次乘。
func _shop_buy_medicine(source_id: String) -> Dictionary:
    var price := PokemonShop.price(source_id)
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if shop_page == null or not shop_page.has_method("mode") or str(shop_page.call("mode")) != "run":
        return _shop_reject(source_id, PokemonShop.ST_WRONG_PLACE)
    if player_hp <= 0.0:
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    var max_hp := maxf(1.0, stats.value("hp_max")) if stats != null else 1.0
    var heals_status := PokemonShop.medicine_heals_status(source_id)
    var status_only := PokemonShop.medicine_status_only(source_id)
    var amount := 0 if status_only else PokemonShop.restore_amount(source_id, max_hp, _healing_multiplier())
    var has_major := player_status != null and player_status.has_major()
    var at_full := player_hp >= max_hp
    # 万灵药只解异常：没有主要异常就拒买（不扣点）。
    if status_only and not has_major:
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    # 普通药满 HP 拒买；全复药满 HP 但有主要异常可用；满 HP 仅混乱 / 无主要异常拒买。
    if at_full and not (heals_status and has_major):
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    if not heals_status and amount <= 0:
        return _shop_reject(source_id, PokemonShop.ST_NO_EFFECT)
    var spend: Dictionary = points_wallet.spend(price)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = source_id
        spend["price"] = price
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    # 扣款 + 保存成功后才应用：精确回复（不走 heal 二次倍率），全复药只清主要异常。
    var hp_before := player_hp
    if amount > 0:
        heal_item(amount)
    var healed := int(round(player_hp - hp_before))
    var cured := false
    if heals_status:
        cured = clear_major_status_item()
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = source_id
    out["price"] = price
    out["healed"] = healed
    out["cured_status"] = cured
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


# 捕获第 2 段：局内买球。只认商品 ID，价格 / 每份数量重新查表；只在「真实战斗 + 商店暂停 run」
# 时购买，先 wallet.spend 成功落盘，再把实际补入数量（cap 99，98 买 5 只补 1）加到本局内存库存。
# 满 99 / 余额不足 / 坏档 / 未保存收入 / 写盘失败都不扣不加，失败候选 tmp 由钱包自己丢掉。
func _shop_buy_ball(source_id: String) -> Dictionary:
    var sid := str(source_id)
    var ball_type := PokemonShop.ball_type(sid)
    if ball_type < 0:
        return _shop_reject(sid, PokemonShop.ST_NOT_PURCHASABLE)
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return _shop_reject(sid, PokemonShop.ST_WRONG_PLACE)
    if shop_page == null or not shop_page.has_method("mode") or str(shop_page.call("mode")) != "run":
        return _shop_reject(sid, PokemonShop.ST_WRONG_PLACE)
    var price := PokemonShop.price(sid)
    var pack := PokemonShop.ball_pack(sid)
    var current := _ball_count(ball_type)
    if current >= PokemonShop.BALL_CAP:
        var full := _shop_reject(sid, PokemonShop.ST_AT_MAX)
        full["ball_type"] = ball_type
        full["ball_count"] = current
        full["added"] = 0
        full["pack"] = pack
        return full
    var added := mini(pack, PokemonShop.BALL_CAP - current)
    if points_wallet == null:
        _points_begin_run()
    # 扣款和新球库存同一份快照落盘（球跨局保留）；失败时钱包自己回滚，不加球。
    var new_counts: Array = ball_counts.duplicate()
    new_counts[ball_type] = current + added
    var spend: Dictionary = points_wallet.spend(price, new_counts)
    if not bool(spend.get("ok", false)):
        spend["source_id"] = sid
        spend["price"] = price
        spend["ball_type"] = ball_type
        spend["ball_count"] = current
        spend["added"] = 0
        spend["pack"] = pack
        spend["balance"] = _points_total()
        spend["run_points"] = _points_run()
        spend["stacks"] = _shop_owned()
        spend["order"] = _shop_order()
        return spend
    ball_counts[ball_type] = current + added
    var out: Dictionary = spend.duplicate()
    out["ok"] = true
    out["status"] = PokemonShop.ST_PURCHASED
    out["source_id"] = sid
    out["price"] = price
    out["ball_type"] = ball_type
    out["added"] = added
    out["pack"] = pack
    out["ball_count"] = current + added
    out["balance"] = _points_total()
    out["run_points"] = _points_run()
    out["stacks"] = _shop_owned()
    out["order"] = _shop_order()
    return out


func _shop_message(source_id: String, result: Dictionary) -> String:
    var id := str(source_id)
    if id.begins_with(STARTER_PREFIX):
        var mv := str(result.get("move", ""))
        var mn := str(MOVES.MOVES[mv]["name"]) if MOVES.MOVES.has(mv) else mv
        match str(result.get("status", "")):
            Points.ST_SAVED:
                return ("开局把「%s」留在家里，腾出一个槽。" if bool(result.get("benched", false)) else "开局带上「%s」。") % mn
            Points.ST_LAST_MOVE:
                return "至少要带一个能打人的招出门，这个不能取下。"
            PokemonShop.ST_AT_MAX:
                return "招式槽满了（最多 %d 个）：先点一个带着的招取下，再带上「%s」。" % [_move_slots(_candy_target()), mn]
            PokemonShop.ST_WRONG_PLACE:
                return "只能在城镇商店里安排开局招。"
            PokemonShop.ST_NOT_PURCHASABLE:
                return "先在图鉴里选一只已捕获的宝可梦。"
            _:
                return "没改成（%s）。" % str(result.get("status", ""))
    var name := PokemonShop.display_name(id)
    if not PokemonShop.is_known(id):
        name = id
    if PokemonLens.is_product(id):
        var lkind := PokemonLens.kind_of(id)
        var lname := str(PokemonLens.NAMES.get(lkind, lkind))
        var lwho := str(_starter_profile(int(result.get("species_id", 0))).get("name", ""))
        match str(result.get("status", "")):
            PokemonShop.ST_PURCHASED:
                return "已为「%s」买下「%s」第 %d 级，花费 %d 点，现有点数 %d。" % [lwho, lname, int(result.get("level", 0)), int(result.get("price", 0)), _points_total()]
            PokemonShop.ST_AT_MAX:
                return "「%s」已经到 %d 级了；未扣款。" % [lname, PokemonLens.MAX_LEVEL]
            PokemonShop.ST_WRONG_PLACE:
                return "「%s」只能在城镇商店买；未扣款。" % lname
            PokemonShop.ST_NOT_PURCHASABLE:
                return "先在图鉴里选一只已捕获的宝可梦，再买「%s」；未扣款。" % lname
    if HeldItems.is_product(id):
        var hitem := HeldItems.item_of(id)
        var hname := HeldItems.name_of(hitem)
        var hwho := str(_starter_profile(int(result.get("species_id", 0))).get("name", ""))
        match str(result.get("status", "")):
            PokemonShop.ST_PURCHASED:
                return "已给「%s」这一系带上「%s」（现在 %d 个），花费 %d 点，现有点数 %d。" % [hwho, hname, int(result.get("count", 0)), int(result.get("price", 0)), _points_total()]
            PokemonShop.ST_AT_MAX:
                return "「%s」已经带满 %d 个了；未扣款。" % [hname, HeldItems.max_stacks(hitem)]
            PokemonShop.ST_WRONG_PLACE:
                return "「%s」只能在城镇商店买；未扣款。" % hname
            PokemonShop.ST_NOT_PURCHASABLE:
                return "先在图鉴里选一只已捕获的宝可梦，再买「%s」；未扣款。" % hname
    if PokemonMemory.is_product(id):
        var mmove := str(result.get("move", PokemonMemory.parse(id).get("move", "")))
        var mzh := str(MOVES.MOVES[mmove]["name"]) if MOVES.MOVES.has(mmove) else mmove
        match str(result.get("status", "")):
            PokemonShop.ST_PURCHASED:
                var rep := str(result.get("replaced", ""))
                var rzh := str(MOVES.MOVES[rep]["name"]) if rep != "" and MOVES.MOVES.has(rep) else ""
                return "吃下记忆蘑菇，想起了「%s」%s，花费 %d 点，现有点数 %d。" % [mzh, ("（替换了「%s」）" % rzh) if rzh != "" else "", int(result.get("price", 0)), _points_total()]
            PokemonShop.ST_NO_EFFECT:
                return "现在不能恢复「%s」（已经带着了 / 不是技能机器学过的招）；未扣款。" % mzh
            PokemonShop.ST_WRONG_PLACE:
                return "只能在局内战斗的商店暂停时买记忆蘑菇；未扣款。"
    if PokemonBerries.is_product(id):
        var bname := PokemonBerries.display_name(PokemonBerries.kind_of(id))
        match str(result.get("status", "")):
            PokemonShop.ST_PURCHASED:
                return "已买下「%s」×1（带着 %d/%d，会自动吃），花费 %d 点，现有点数 %d。" % [bname, int(result.get("berry_count", 0)), PokemonBerries.CAP, int(result.get("price", 0)), _points_total()]
            PokemonShop.ST_AT_MAX:
                return "「%s」已带满 %d 个；未扣款。" % [bname, PokemonBerries.CAP]
            PokemonShop.ST_WRONG_PLACE:
                return "只能在局内战斗的商店暂停时购买「%s」；未扣款。" % bname
    var status := str(result.get("status", ""))
    var price := int(result.get("price", -1))
    match status:
        PokemonShop.ST_PURCHASED:
            if PokemonEvolution.is_product(id):
                return "已买下「%s」，花费 %d 点，现有点数 %d；离开商店（继续游戏）后 %s 会进化成 %s。" % [
                    PokemonEvolution.item_name(str(result.get("item", ""))), price, _points_total(),
                    str(_starter_profile(player_species_id).get("name", "")), str(_starter_profile(int(result.get("evolve_to", 0))).get("name", ""))]
            if TMRules.is_product(id):
                var who3 := str(_starter_profile(int(result.get("species_id", 0))).get("name", ""))
                var mname := str(MOVES.MOVES[str(result.get("move", ""))]["name"]) if MOVES.MOVES.has(str(result.get("move", ""))) else str(result.get("move", ""))
                var tail := "，开局带着" if bool(result.get("equipped", false)) else "，没有空槽没带上（可以在这里「带上」）"
                return "已为「%s」买下「技能机器·%s」（%s档）%s；花费 %d 点，现有点数 %d。" % [
                    who3, mname, str(TMRules.TIER_ZH.get(TMRules.tier_of(str(result.get("move", ""))), "")), tail, price, _points_total()]
            if PokemonShop.is_stat_drink(id):
                var who2 := str(_starter_profile(int(result.get("species_id", 0))).get("name", ""))
                var evrow: Array = result.get("ev", [])
                var now := int(evrow[PokemonShop.stat_index(id)]) if evrow.size() == 6 else 0
                return "已为「%s」喝下「%s」：努力值 %d/%d，花费 %d 点，现有点数 %d。" % [
                    who2, name, now, Points.EV_CAP, price, _points_total()]
            if PokemonShop.is_town_candy(id):
                var who := str(_starter_profile(int(result.get("species_id", 0))).get("name", ""))
                return "已为「%s」买下「%s」×1（共 %d 颗，开局 +%d 级），花费 %d 点，现有点数 %d。" % [
                    who, name, int(result.get("count", 0)), int(result.get("count", 0)), price, _points_total()]
            if PokemonShop.is_run_ball(id):
                var added := int(result.get("added", 0))
                var have := int(result.get("ball_count", 0))
                return "已购买「%s」×%d 个（实际补入 %d，现有 %d/%d），花费 %d 点，现有点数 %d。" % [
                    name, int(result.get("pack", added)), added, have,
                    PokemonShop.BALL_CAP, price, _points_total()]
            if PokemonShop.is_run_medicine(id):
                var healed := int(result.get("healed", 0))
                var cured := bool(result.get("cured_status", false))
                if healed > 0 and cured:
                    return "已购买并使用「%s」，回复 %d 点并解除了主要异常，花费 %d 点，现有点数 %d。" % [name, healed, price, _points_total()]
                if healed > 0:
                    return "已购买并使用「%s」，回复 %d 点，花费 %d 点，现有点数 %d。" % [name, healed, price, _points_total()]
                return "已购买并使用「%s」，解除了主要异常，花费 %d 点，现有点数 %d。" % [name, price, _points_total()]
            return "已购买「%s」×1，花费 %d 点，现有点数 %d。" % [name, price, _points_total()]
        PokemonShop.ST_INSUFFICIENT:
            return "点数不足：「%s」需要 %d 点，现有 %d 点；未扣款。" % [name, price, _points_total()]
        Points.ST_LAST_MOVE:
            return "至少要带一个能打人的招出门，这个不能取下。"
        Points.ST_SAVED:
            if TMRules.is_product(id):
                var mn := str(MOVES.MOVES[str(result.get("move", ""))]["name"]) if MOVES.MOVES.has(str(result.get("move", ""))) else ""
                return ("开局会带上「技能机器·%s」。" if bool(result.get("equipped", false)) else "开局不再带「技能机器·%s」。") % mn
            return "购买失败（%s），未扣款。" % status
        PokemonShop.ST_AT_MAX:
            if TMRules.is_product(id):
                return "招式槽满了（最多 %d 个）：先点一个带着的招取下，再带上；未扣款。" % _move_slots(_candy_target())
            if PokemonShop.is_stat_drink(id):
                return "这只宝可梦的这一项努力值已经 %d；未扣款。" % Points.EV_CAP
            if PokemonShop.is_town_candy(id):
                return "这只宝可梦的「%s」已达上限 %d 颗；未扣款。" % [name, PokemonShop.CANDY_CAP]
            if PokemonShop.is_run_ball(id):
                return "「%s」库存已达上限 %d；未扣款。" % [name, PokemonShop.BALL_CAP]
            return "「%s」已达层数上限；未扣款。" % name
        PokemonShop.ST_PENDING_INCOME:
            return "有未保存的点数收入，保存成功后才能购买；本次未扣款。"
        PokemonShop.ST_NOT_PURCHASABLE:
            if TMRules.is_product(id):
                return "这只宝可梦学不了这个技能机器（或还没捕获）；未扣款。"
            if PokemonShop.is_town_candy(id) or PokemonShop.is_stat_drink(id):
                return "先在图鉴里选一只已捕获的宝可梦，再买「%s」；未扣款。" % name
            return "「%s」尚未开放；未扣款。" % name
        PokemonShop.ST_WRONG_PLACE:
            if TMRules.is_product(id) or PokemonShop.is_town_candy(id) or PokemonShop.is_stat_drink(id):
                return "「%s」只能在城镇商店买；未扣款。" % name
            if PokemonShop.is_run_ball(id):
                return "只能在局内战斗的商店暂停时购买「%s」；未扣款。" % name
            if PokemonShop.is_run_medicine(id):
                return "只能在局内战斗的商店暂停时使用「%s」；未扣款。" % name
            return "只能在城镇购买「%s」；未扣款。" % name
        PokemonShop.ST_NO_EFFECT:
            return "「%s」当前没有效果（HP 已满或没有可解除的主要异常）；未扣款。" % name
        PokemonShop.ST_CORRUPT_LOCKED:
            return "点数档损坏已锁定，不能购买；原档已保留。"
        _:
            return "购买失败（%s），未扣款。" % status


# ================= 捕获第 2 段（五球库存 / 地面选圈 / 逐只真捕获 + 持久解锁）=================
# 唯一概率规则在 game/pokemon_capture.gd（第 1 段已验收，不改公式 / 三摇 / 球倍率）；
# 持久解锁在 game/pokemon_points.gd::unlock_species。这里只做「本局内存库存 + 地点 / 状态校验 +
# 圈内选目标 + 逐只独立提交 + 成功后的移除 / 原经验 / 头目推进」，不生成假 Rogue 演出、不做队伍。

# 新局：原 new run 初始库存 5/0/0/0/0 与钱包里存下的球库存取大；点数与解锁也由钱包保留。
# 起手库存：钱包里存过球就原样带过来（用光就是用光）；从没存过（第一局 / 旧档）才给原初始 5/0/0/0/0，
# 并立刻存下，所以初始 5 个只在第一局给一次（用户 2026-10-17）。
func _reset_ball_run() -> void:
    ball_counts = PokemonShop.initial_ball_counts()
    if points_wallet != null and not points_wallet.balls.is_empty():
        for i in range(ball_counts.size()):
            ball_counts[i] = int(points_wallet.balls[i])
    else:
        _persist_balls()
    # 树果也跨局保留：开局从钱包读（没存过就是 0 个）。
    lens_support = points_wallet.lens_for(run_starter_id, "support") if points_wallet != null else 0
    lens_attack = points_wallet.lens_for(run_starter_id, "attack") if points_wallet != null else 0
    lens_capture = points_wallet.lens_for(run_starter_id, "capture") if points_wallet != null else 0
    berries = {"SITRUS": 0, "LUM": 0}
    if points_wallet != null:
        for kind: String in PokemonBerries.KINDS:
            berries[kind] = int(points_wallet.berries.get(kind, 0))
    capture_pause_mode = false
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("set_pause_mode"):
        capture_page.call("set_pause_mode", false)
    _cancel_ball_aim()
    _cancel_capture_presentation()


# 把当前球库存存进钱包并落盘（投球 / 局末 / 放弃 / 关窗）；失败不影响战斗，下次保存会带上。
func _persist_berries() -> void:
    if points_wallet == null:
        return
    points_wallet.set_berries(berries, not points_wallet.has_pending_income())


func _persist_balls() -> void:
    if points_wallet == null:
        return
    # 有未保存的点数收入时只更新内存（落盘留给以后的保存）：不能借球库存的保存把“未保存收入”标记悄悄清掉，
    # 否则购买 / 解锁的“有未保存收入先拒绝”保护会失效。
    points_wallet.set_balls(ball_counts, not points_wallet.has_pending_income())


# 瞄准时圈里的怪高光（用户 2026-10-18：“捕捉的时候高光捕捉的怪物”）：进圈变亮黄，出圈 / 取消 / 投出后还原。
var _ball_hl: Array = []


func _ball_highlight_tick() -> void:
    var want: Array = []
    if ball_aiming and capture_page != null and is_instance_valid(capture_page) and bool(capture_page.call("has_aim")):
        var c: Vector3 = capture_page.call("aim_position")
        var r := _ball_radius()
        for e in enemies:
            if e.dying >= 0.0 or e.node == null or not is_instance_valid(e.node):
                continue
            var dx: float = e.node.position.x - c.x
            var dz: float = e.node.position.z - c.z
            if dx * dx + dz * dz <= r * r:
                want.append(e)
    if want.is_empty() and _ball_hl.is_empty():
        return
    _ball_hl = _ball_hl.filter(func(x): return is_instance_valid(x.node) if x != null else false)
    for e in _ball_hl:
        if not want.has(e):
            _set_ball_highlight(e, false)
    for e in want:
        if not _ball_hl.has(e):
            _set_ball_highlight(e, true)
    _ball_hl = want
    _ball_highlight_pulse()


const BALL_HL_COLOR := Color(0.35, 1.0, 1.0)   # 圈里的怪：青白描边 + 脚下光圈 + 呼吸闪（和闪光 / 神兽的金色描边区分开）


# 新手提示（用户 2026-10-24：“新存档需要有 AI / 人类指导，要不然他们都不是很会玩”）。
# 不另存进度：看存档——抓到的宝可梦少 / 没去过别的地区就提示；抓多了、去过了自然不再出现。每局每条最多一次。
func _is_newbie(kind := "caught") -> bool:
    if not newbie_tips or points_wallet == null:
        return false
    if kind == "maps":
        return (points_wallet.maps_unlocked as Array).size() <= 1
    return (points_wallet.caught as Array).size() <= NEWBIE_CAUGHT_MAX


func _tip(key: String, text: String, kind := "caught") -> void:
    if tutorial_mode or _tips_shown.has(key) or not _is_newbie(kind) or hud == null or not hud.has_method("show_tip"):
        return
    _tips_shown[key] = true
    hud.show_tip(text)


func _tips_tick() -> void:
    if tutorial_mode:
        _tutorial_tick()
        return
    if not started or dead:
        return
    if time >= 1.0:
        _tip("start", "这一局的目标：活过 5 分钟就能撤离、去新地区（4:30 会来头目，打倒它或等它走）。招式会自动放，你只管走位躲怪。右上角「商店」能买药和精灵球。")
    if time >= 45.0 and time < 60.0:
        _tip("surge", "快到 1 分钟了：之后怪会一下子多起来。血不多就先去商店买药，别站在怪堆里。")


func _tut_tip(key: String, text: String, secs := 12.0) -> void:
    if _tut_shown.has(key) or hud == null or not hud.has_method("show_tip"):
        return
    _tut_shown[key] = true
    hud.show_tip(text, secs)


# 每个存档第一次出发都问一次要不要玩教学关（用户 2026-10-24）；玩了或跳过都记在这个存档名下，之后不再问。
func _tutorial_key() -> String:
    return "tutorial_done_" + str(points_path).md5_text()


func _tutorial_wanted() -> bool:
    return points_wallet != null and not PausePage.saved_flag(_tutorial_key())


func _mark_tutorial_done() -> void:
    PausePage.set_flag(_tutorial_key(), true)


func _tutorial_tick() -> void:
    if not started:
        return
    if dead:
        _finish_tutorial()
        return
    if time >= 1.0:
        _tut_tip("intro", "教学关（2 分钟）：这是绿毛虫进化到底（巴大蝶）再超极巨化的样子，先感受一下！WASD / 方向键走位，招式会自动放。按 Esc 可以随时暂停。", 13.0)
    if time >= 15.0:
        _tut_tip("toggles", "左下是你的招式。按 Esc 暂停后点它们可以开 / 关：抓宠物的时候把攻击招关掉，就不会把目标打死。")
    if time >= 28.0 and _tut_rare == null and not _tut_shown.has("rare"):
        _tut_shown["rare"] = true
        var ang := randf() * TAU
        var t: Dictionary = Roster.wild_enemy(TUTORIAL_RARE, 0, 5, 1.0)
        if not t.is_empty():
            call("_spawn", t, player.position + Vector3(cos(ang), 0, sin(ang)) * 6.0)   # _spawn 在子脚本 enemies.gd
            _tut_rare = enemies[enemies.size() - 1]
            _tut_rare.spared = true
        var paused_now := bool(call("_open_pause_screen")) if not paused else false
        _tut_tip("catch", ("游戏已经帮你暂停了：" if paused_now else "按 Esc 暂停，然后：") + "左下选精灵球 → 点伊布脚下放圈，就扔出去了（这只伊布在教学里打不死，放心扔；被打残了更容易进）。抓到的宝可梦下一局就能当首发。", 18.0)
    var rare_gone: bool = _tut_rare != null and (not is_instance_valid(_tut_rare.node) or _tut_rare.dying >= 0.0 or not enemies.has(_tut_rare))
    if (rare_gone and time >= 35.0) or time >= 75.0:
        _tut_tip("shop", "右上角「商店」：局里能买药、精灵球、进化道具（暂停时也能开）。点数靠打怪、捡金珠攒；回到选宠页还能买糖果、携带道具、技能机器。")
    if time >= 92.0:
        _tut_tip("evac", "平时一局：活过 5 分钟就能撤离、去新的地区（等级、宠物都带走）；4:30 会来头目。剩下半分钟随便打吧！")
    if time >= TUTORIAL_SECS:
        _finish_tutorial()


# 教学收尾：记下“玩过了”，弹框说清抓到了谁、攒了多少点，点“回到选宠页”才离开（不再突然跳走）。
func _finish_tutorial() -> void:
    if _tut_finishing:
        return
    _tut_finishing = true
    _mark_tutorial_done()
    var got := "这次抓到：%s，下一局就能选它们出发。" % "、".join(_tut_caught) if not _tut_caught.is_empty() \
        else "这次没抓到也没关系：正式开局里稀有宝可梦还会出现，按 Esc 暂停就能扔球。"
    var msg := "%s刚才那只就是你的绿毛虫进化到底、再超极巨化的样子。\n%s\n打怪攒了 %d 点，已经存进存档（回到选宠页能买糖果、道具）。" % [
        "" if not dead else "倒下了也没关系。", got, int(call("_points_run"))]
    await call("_ask_choice", "教学结束", msg, ["回到选宠页"], "", event_token)
    tutorial_mode = false
    call("_abandon")


func _tip_catch() -> void:
    _tip("catch", "想抓它：按 Esc 暂停 → 左下选精灵球 → 点它脚下放圈就扔出去。先把它打到一半血以下更容易进；怕把它打死，可以在技能栏把攻击招关掉（暂停时点）。抓到的下一局能当首发。")


# 平时的描边：闪光 / 神兽金色、头目红色、（开了设置）没抓过的绿色，否则不描边。
func _apply_base_outline(e) -> void:
    if e.node == null or not is_instance_valid(e.node) or not e.node.has_method("set_outline"):
        return
    if e.shiny or e.legendary:
        e.node.call("set_outline", EnemySpecial.OUTLINE_COLOR)
    elif bool(e.t.get("boss", false)):
        e.node.call("set_outline", EnemySpecial.BOSS_OUTLINE_COLOR)
    elif _outline_uncaught_for(e):
        e.node.call("set_outline", UNCAUGHT_OUTLINE_COLOR)
    elif e.node.has_method("clear_outline"):
        e.node.call("clear_outline")


func _outline_uncaught_for(e) -> bool:
    var sid := int(e.t.get("species_id", 0))
    return outline_uncaught and sid > 0 and points_wallet != null and not points_wallet.is_species_unlocked(sid)


# 开关改了：场上所有怪重画一遍描边；刚抓到新物种：只重画这一种（sid > 0），别动圈里正高亮的别的怪。
func _refresh_base_outlines(sid := 0) -> void:
    for e in enemies:
        if e.dying < 0.0 and (sid <= 0 or int(e.t.get("species_id", 0)) == sid):
            _apply_base_outline(e)


func _set_ball_highlight(e, on: bool) -> void:
    if e.node == null or not is_instance_valid(e.node):
        return
    var sprite = e.node.get_node_or_null("Sprite")
    if sprite is Sprite3D:
        sprite.modulate = Color(1.6, 1.45, 0.7) if on else Color.WHITE
    if e.node.has_method("set_outline"):
        if on:
            e.node.call("set_outline", BALL_HL_COLOR)
        else:
            _apply_base_outline(e)   # 还原：闪光 / 神兽金、头目红、没抓过绿，或者不描边
    var mark = e.node.get_node_or_null("BallMark")
    if on and mark == null:
        mark = MeshInstance3D.new()
        mark.name = "BallMark"
        var ring := TorusMesh.new()
        ring.inner_radius = 0.52
        ring.outer_radius = 0.66
        mark.mesh = ring
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.albedo_color = BALL_HL_COLOR
        mat.no_depth_test = true
        mat.render_priority = 10
        mark.material_override = mat
        mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mark.position = Vector3(0, 0.05, 0)
        e.node.add_child(mark)
    elif not on and mark != null:
        e.node.remove_child(mark)
        mark.queue_free()


# 圈里的怪每帧呼吸闪（亮度在 1.3..2.2 之间），一眼能看出哪些在圈里。
func _ball_highlight_pulse() -> void:
    if _ball_hl.is_empty():
        return
    var k := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
    for e in _ball_hl:
        if e.node == null or not is_instance_valid(e.node):
            continue
        var sprite = e.node.get_node_or_null("Sprite")
        if sprite is Sprite3D:
            var b := lerpf(1.3, 2.2, k)
            sprite.modulate = Color(b, b * 0.95, b * 0.6)
        var mark = e.node.get_node_or_null("BallMark")
        if mark != null:
            mark.scale = Vector3.ONE * lerpf(0.9, 1.15, k)


# 捕捉圈实际半径 = 基础半径 × 设置里的系数。
func _ball_radius() -> float:
    return BALL_AIM_RADIUS * capture_ring_scale


func _ball_count(ball_type: int) -> int:
    if not PokemonShop.is_ball_type(ball_type):
        return 0
    return int(ball_counts[ball_type])


# 投球 / 买球共同的合法战斗门槛：已出发、活着、未结算、未在选招 / 进化、未暂停、玩家未倒下，
# 且当前没有捕获演出批次（播放期间不接受第二次投球 / 进入瞄准）。
# 预约下一球（用户 2026-10-24）：上一球的动画还在播时也能选球、放圈，动画一播完马上扔出去。
# 动画期间战斗是冻住的，怪不会走，所以预约时圈的位置到时候还准。只存一个，再预约就换掉。
var _queued_throw: Dictionary = {}


func _ball_queue_allowed() -> bool:
    return capture_presenting and started and not dead and not settled and not choosing and not evolving         and (not paused or capture_pause_mode) and player_hp > 0.0


func _queue_throw(world_pos: Vector3) -> bool:
    if not _ball_queue_allowed() or not ball_aiming or not PokemonShop.is_ball_type(ball_aim_type) or _ball_count(ball_aim_type) <= 0:
        return false
    _queued_throw = {"pos": world_pos, "ball": ball_aim_type}
    _cancel_ball_aim()
    if hud != null:
        hud.show_banner("下一球已预约：这只的动画一结束马上扔")
    return true


# 动画结束：有预约就照原来的投球入口扔出去（耗球、掷骰都和手动扔一样）。
func _fire_queued_throw() -> void:
    if _queued_throw.is_empty():
        return
    var q := _queued_throw
    _queued_throw = {}
    if not _ball_aim_allowed() or _ball_count(int(q["ball"])) <= 0:
        return
    ball_aiming = true
    ball_aim_type = int(q["ball"])
    var result: Dictionary = _throw_ball_at(q["pos"])
    if has_method("_capture_feedback"):
        call("_capture_feedback", result)
    if ball_aiming:
        _cancel_ball_aim()


func _ball_aim_allowed() -> bool:
    return started and not dead and not settled and not choosing and not evolving \
        and (not paused or capture_pause_mode) and not capture_presenting and player_hp > 0.0


# 真实投球入口第一步：校验库存 / 球枚举 / 战斗状态，然后让捕获 HUD 进入地面选圈。
func _begin_ball_aim(ball_type: int) -> bool:
    if not (_ball_aim_allowed() or _ball_queue_allowed()):
        return false
    if not PokemonShop.is_ball_type(ball_type):
        return false
    if _ball_count(ball_type) <= 0:
        return false
    ball_aiming = true
    ball_aim_type = ball_type
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("show_aim"):
        capture_page.call("show_aim", ball_type, _ball_radius())
    _start_ball_slowmo()
    return true


# 慢动作只在实时战斗里开（暂停抓宠物本来就是静止的）；切换球不重新计时。
func _start_ball_slowmo(secs := BALL_SLOWMO_SECS, scale := BALL_SLOWMO_SCALE) -> void:
    if ball_slowmo_active or paused or capture_pause_mode:
        return
    ball_slowmo_active = true
    ball_slowmo_scale = scale
    ball_slowmo_end_ms = Time.get_ticks_msec() + int(secs * 1000.0)
    Engine.time_scale = scale


# 捕获时用的血量：最多按一半算（满血当半血，用户 2026-10-21 选 b）。
static func capture_hp_for(hp: float, max_hp: int) -> float:
    return minf(hp, float(max_hp) * CAPTURE_HP_CAP)


# 只有时间速度还是我们设的慢速才改回 1.0，不覆盖商店暂停 / 结算等别处设的值。
func _end_ball_slowmo() -> void:
    if not ball_slowmo_active:
        return
    ball_slowmo_active = false
    if is_equal_approx(Engine.time_scale, ball_slowmo_scale):
        Engine.time_scale = 1.0


# 每帧检查慢动作是否到时（主循环 _process 最前面调用；瞄准本身不取消，只是回到正常速度）。
func _ball_slowmo_tick() -> void:
    if ball_slowmo_active and Time.get_ticks_msec() >= ball_slowmo_end_ms:
        _end_ball_slowmo()


# 取消 / 清圈：右键、Esc、右键菜单、死亡、暂停、选择 / 进化、取消 / 放弃 / reload / 退出都走这里。
# 只清临时瞄准状态与圈，不动球库存、不掷骰、不改 time_scale。
func _cancel_ball_aim() -> void:
    ball_aiming = false
    ball_aim_type = -1
    _end_ball_slowmo()
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("hide_aim"):
        capture_page.call("hide_aim")


# 暂停抓宠界面（用户 2026-10-17：Esc 暂停 = 抓宠界面，商店从右上角 B 区按钮进）：
# 世界保持暂停，球面板出来，选球 → 点地面放圈 → 投出（耗球）即恢复游戏。
func _enter_capture_pause() -> void:
    capture_pause_mode = true
    _refresh_special_marks()   # 暂停抓宠时给没捕获过的怪头上加「未捕获」
    if shop_page != null:
        shop_page.close()
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("set_pause_mode"):
        capture_page.call("set_pause_mode", true)


# 抓宠界面 B 区“商店”按钮：收起抓宠界面、打开局内商店（仍暂停）。
func _on_capture_shop_pressed() -> void:
    if not (capture_pause_mode and started and not dead and not settled):
        return
    _cancel_ball_aim()
    capture_pause_mode = false
    _refresh_special_marks()
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("set_pause_mode"):
        capture_page.call("set_pause_mode", false)
    _push_evolution_items()
    _push_shop_extras()
    shop_page.open_run(_points_total(), _points_run(), _shop_owned(), _shop_ball_counts())


# 局内商店左边（A 区）选了一种球：收起商店、进入抓宠界面并直接开始瞄准这种球（没库存的球不进）。
func _on_shop_ball_chosen(ball_type: int) -> void:
    if not (started and not dead and not settled and not evolving and not choosing and paused):
        return
    if shop_page == null or not shop_page.is_open() or str(shop_page.call("mode")) != "run":
        return
    if not PokemonShop.is_ball_type(ball_type) or _ball_count(ball_type) <= 0:
        return
    _cancel_ball_aim()
    _enter_capture_pause()
    _begin_ball_aim(ball_type)


# 商店“返回抓宠”（Esc）：回到暂停的抓宠界面。
func _shop_back_to_capture() -> void:
    if not (started and not dead and not settled and paused):
        return
    _enter_capture_pause()


# 捕获 HUD 每帧自取的状态（可用性 + 各球库存）：主循环暂停 / 选择 / 进化时也不漏刷新。
func _capture_hud_state() -> Dictionary:
    return {"available": _ball_aim_allowed(), "counts": ball_counts.duplicate()}


# 稳定真实入口：只有真实瞄准中且合法战斗才提交。
# 返回至少 ok / consumed / targets / captured / broke_free，另有 blocked / persist_failed / results。
# 确认路径（HUD 点击 -> 信号 -> 这里）与直接调用完全同一条代码路径；注入 rng 只是把原 Capture
# 所需 Callable 原样透传，默认生产 Godot 随机，没有关奖励 / 关落盘的测试开关。
func _throw_ball_at(world_pos: Vector3, rng: Callable = Callable()) -> Dictionary:
    var out := {
        "ok": false, "consumed": false, "targets": 0, "captured": 0, "broke_free": 0,
        "blocked": 0, "persist_failed": 0, "ball_type": -1, "reason": "", "results": [],
    }
    if not ball_aiming:
        out["reason"] = "not_aiming"
        return out
    if not _ball_aim_allowed():
        out["reason"] = "not_allowed"
        _cancel_ball_aim()
        return out
    var ball_type := ball_aim_type
    if not PokemonShop.is_ball_type(ball_type):
        out["reason"] = "bad_ball"
        _cancel_ball_aim()
        return out
    if _ball_count(ball_type) <= 0:
        out["reason"] = "empty"
        _cancel_ball_aim()
        return out
    if not world_pos.is_finite():
        # 非有限地面位置：入口拒绝且不改动（球没耗、圈还在、不掷骰）。
        out["reason"] = "bad_position"
        return out
    out["ball_type"] = ball_type
    # 圈内有效目标：活敌人 + 有效节点 + 真实正 HP + XZ 距离 <= 半径 + 有捕获率资料。
    var targets: Array = []
    var blocked := 0
    for e in enemies:
        if e.dying >= 0.0:
            continue
        if e.node == null or not is_instance_valid(e.node):
            continue
        # 圈内“活目标”必须在**消耗球之前**排除：hp<=0（含 0 与负数）以及非有限 hp / maxHP
        # 都直接无效、不掷骰、不计入 blocked、不耗球；只有这些时就是空圈语义。
        # 不改原 Capture 纯规则（FAINTED 仍只属于真正进入 attempt 的调用）。
        if not is_finite(e.hp) or e.hp <= 0.0:
            continue
        var raw_max = e.t.get("hp", e.hp)
        var max_hp_value := float(raw_max)
        if not is_finite(max_hp_value) or max_hp_value <= 0.0:
            continue
        var dx := e.node.position.x - world_pos.x
        var dz := e.node.position.z - world_pos.z
        if dx * dx + dz * dz > _ball_radius() * _ball_radius():
            continue
        var sid := int(e.t.get("species_id", -1))
        if CaptureSpecies.catch_rate(sid) == CaptureSpecies.UNKNOWN:
            continue
        # 头目的分段捕捉保护已去掉（用户 2026-10-18：“boss 的捕捉保护去掉，这个很难控血，boss 要是神兽的话就太难受了”）：
        # 任何时候都能对头目扔球，成功率照原捕获公式吃它当前的血量 / 状态 / 球种；破段强化等其它头目规则不动。
        targets.append(e)
    out["blocked"] = blocked
    if targets.is_empty():
        # 空圈 / 全被挡：不耗球、不掷骰、不改动，圈保留给玩家重新选位置。
        out["reason"] = "no_targets"
        return out
    # 锁住这次点击、先清圈，再执行逐只判定与奖励，绝不重复消费。
    ball_counts[ball_type] = _ball_count(ball_type) - 1
    _persist_balls()
    out["consumed"] = true
    out["targets"] = targets.size()
    ball_aiming = false
    ball_aim_type = -1
    _end_ball_slowmo()
    if capture_page != null and is_instance_valid(capture_page) and capture_page.has_method("hide_aim"):
        capture_page.call("hide_aim")
    if points_wallet == null:
        _points_begin_run()
    # 逐只独立原判定（每只各自 RNG 序列）；只有原规则判定成功、且持久解锁真的落盘，
    # 才进成功路径：先读只读快照（必须在 queue_free 之前），立即移除 actor，XP / 头目推进延后。
    var capture_engine := Capture.new()
    var fx = _capture_fx_player()
    var from := _capture_throw_origin()
    var batch: Array = []
    var rewards: Array = []
    var restores: Array = []
    for e in targets:
        var sid := int(e.t.get("species_id", -1))
        var status_effect := 0
        if e.status != null:
            status_effect = int(e.status.major_effect)
        var max_hp := int(round(float(e.t.get("hp", e.hp))))
        # 本作改动（用户 2026-10-21 选 b）：这游戏基本满血直接扔，原版“血越少越好抓”让满血吃最低档。
        # 血量最多按一半算——高于半血一律当半血（约等于满血概率 ×2），低于半血照原版更好抓；原公式本身不动。
        var capture_hp := capture_hp_for(e.hp, max_hp)
        var result: Dictionary = capture_engine.attempt_by_species(sid, max_hp, capture_hp, ball_type, status_effect, rng, PokemonLens.capture_mult(PokemonLens.effective_level_bonus(lens_capture, _shiny_lens_bonus())))
        var record := {
            "species_id": sid, "hp": e.hp, "max_hp": max_hp, "status": status_effect,
            "captured": bool(result.get("captured", false)),
            "rolls": int(result.get("rolls", 0)),
            "shakes": int(result.get("shakes", 0)),
            "result": int(result.get("result", -1)),
        }
        if bool(result.get("captured", false)):
            var unlock: Dictionary = points_wallet.unlock_species(sid)
            record["unlock"] = str(unlock.get("status", ""))
            if bool(unlock.get("ok", false)):
                var new_species := bool(unlock.get("added", false))
                if tutorial_mode:
                    _tut_caught.append(str(e.t.get("name", "")))
                if new_species and outline_uncaught:
                    _refresh_base_outlines(sid)   # 抓到了：同种的其他怪不再描“没抓过”的绿边
                var portrait: Texture2D = e.node.portrait_texture() if e.node != null and is_instance_valid(e.node) and e.node.has_method("portrait_texture") else null
                if new_species and hud != null and hud.has_method("show_dex_entry"):
                    # 第一次抓到这个物种：右下角弹“新登记”卡片（原版“图鉴登录”的意思），不暂停
                    hud.show_dex_entry(portrait, sid, str(e.t.get("name", "")), int(e.shiny_variant) if bool(e.shiny) else -1)
                _refresh_rare_markers()   # 抓到新物种：场上同种的稀有标记消失
                out["captured"] = int(out["captured"]) + 1
                if bool(e.shiny):
                    var new_tier: bool = points_wallet.mark_shiny_caught(sid, int(e.shiny_variant))   # 图鉴格子要看得出闪光抓到过（记最高档位）
                    if new_tier and not new_species and hud != null and hud.has_method("show_dex_entry"):
                        # 物种早就有了，但这一档闪光是第一次：也弹一张（用户 2026-10-21）
                        hud.show_dex_entry(portrait, sid, str(e.t.get("name", "")), int(e.shiny_variant), "新闪光！")
                points_wallet.unlock_nature(AB.root_of(sid), int(e.nature_id))
                points_wallet.record_ivs(AB.root_of(sid), e.ivs)   # 个体值：每项记这一系抓到过的最高值   # 性格：抓到这个性格就给这一系解锁
                if int(e.ability_slot) == 2 and AB.species_slots(sid)[2] != AB.NONE:
                    points_wallet.mark_hidden_ability(AB.root_of(sid))   # 抓到隐藏特性的个体：解锁起始页的隐藏栏
                # 物种糖果（原版）：记在起始种上，1 颗；闪光 5 / 10 / 20；头目 ×2
                var candy_n := SpeciesCandy.catch_candy(int(e.shiny_variant) if bool(e.shiny) else -1, bool(e.t.get("boss", false)))
                if points_wallet.add_species_candy(AB.root_of(sid), candy_n):
                    out["candy"] = int(out.get("candy", 0)) + candy_n
                # 快照 / 落点在释放 actor 之前取好；FX 只持只读 Sprite3D 副本，成功移除后照样播完。
                var to_ok := _capture_target_point(e)
                var snap_ok: Dictionary = CaptureFXScript.snapshot_actor(e.node)
                var reward := {
                    "xp": float(e.t.get("xp", 0.0)),
                    "boss": bool(e.t.get("boss", false)),
                    "final": bool(e.t.get("final", false)),
                    "name": str(e.t.get("name", "")),
                }
                _capture_remove_target(e)
                var ok_id := -1
                if fx != null and not snap_ok.is_empty():
                    ok_id = int(fx.play(ball_type, from, to_ok, result, snap_ok, true))
                if ok_id >= 0:
                    batch.append({"id": ok_id, "captured": true, "enemy": null, "restored": true})
                    rewards.append(reward)
                else:
                    # 没有可演播放：不伪造成演出，立刻发这次原奖励（不吞 XP、不挂住批次）。
                    _capture_grant_reward(reward)
            else:
                # 捕获保存失败 / pending / 坏档：不移除敌人、不发捕获 XP、不报已解锁，
                # 也不给这个目标建捕获 FX（不能把落盘失败伪装成概率失败）；仍耗了这 1 球。
                out["persist_failed"] = int(out["persist_failed"]) + 1
        else:
            out["broke_free"] = int(out["broke_free"]) + 1
            # 失败目标留在 enemies：真实 HP / 主要状态 / 钟余数 / 排队攻击计时全不改；
            # 只临时隐藏实际 node 显示，用原快照吸入 / 挣脱，不让原怪与快照重叠。
            var to_fail := _capture_target_point(e)
            var snap_fail: Dictionary = CaptureFXScript.snapshot_actor(e.node)
            var fail_id := -1
            if fx != null and not snap_fail.is_empty():
                fail_id = int(fx.play(ball_type, from, to_fail, result, snap_fail, true))
            if fail_id >= 0:
                # 记下**投球前**的真实 visible 再隐藏：演出结束 / 取消时按原值还原，
                # 不能硬设 true（投球前本就隐藏的目标不能被演出点亮），也不硬设 false。
                var was_visible := true
                if e.node != null and is_instance_valid(e.node):
                    was_visible = bool(e.node.visible)
                    e.node.visible = false
                var fail_rec := {
                    "id": fail_id, "captured": false, "enemy": e, "restored": false,
                    "visible": was_visible,
                }
                batch.append(fail_rec)
                restores.append(fail_rec)
        out["results"].append(record)
    out["ok"] = true
    if not batch.is_empty():
        _capture_batch = batch
        _capture_rewards = rewards
        _capture_restores = restores
        capture_presenting = true
        # 立刻跑同一 tick：正常情况播放刚开始；边界（全部同帧结束）也能及时收尾，不挂住。
        _capture_presentation_tick()
    else:
        _capture_batch = []
        _capture_rewards = []
        _capture_restores = []
    return out


# ================= 捕获演出第 3 段（真实投球 → 原 FX 批次）=================
# 状态集中在 capture_presenting；主循环门槛在 main._process，FX 用自己的 _process 走真实 delta。
# 演出期间：不掷第二次骰 / 不重复消费 / 不收第二位玩家输入 / 不推进战斗 / 不提前结算 XP 与头目。

# 懒创建唯一一部原播放器（fx/rogue_capture.gd）；缺脚本时返回 null，不造第二实现。
# 不写返回类型：调用点要按原播放器方法（play / advance / play_count / is_active / set_paused）动态调。
func _capture_fx_player():
    if capture_fx != null and is_instance_valid(capture_fx):
        return capture_fx
    var script: GDScript = CaptureFXScript
    if script == null or not script.can_instantiate():
        return null
    var raw: Object = script.new()
    if not (raw is Node3D):
        if raw is Node:
            (raw as Node).queue_free()
        return null
    var fx := raw as Node3D
    add_child(fx)
    fx.call("setup", cam)
    capture_fx = fx
    return fx


# 实际投球起点：玩家身边合理高度（本作 2.5D 适配值，不是原世界尺度）。FX 不再额外加 64px。
func _capture_throw_origin() -> Vector3:
    if player == null or not is_instance_valid(player):
        return Vector3(0.0, CAPTURE_THROW_HEIGHT, 0.0)
    return player.position + Vector3(0.0, CAPTURE_THROW_HEIGHT, 0.0)


# 实际 catch/open 点：目标脚下 XZ + catch_height()（落点 origin 再高 56*PX）。
func _capture_target_point(e) -> Vector3:
    var base := Vector3.ZERO
    if e != null and e.node != null and is_instance_valid(e.node):
        base = e.node.position
    return Vector3(base.x, CaptureFXScript.catch_height(), base.z)


# 成功持久化后的立即移除：清状态 / 停钟 / 标 dying / 移出 enemies / 释放 node。
# 真实 XP 与头目推进不在这里（延后到整批演出结束，见 _capture_grant_reward）。
func _capture_remove_target(e) -> void:
    if e == null:
        return
    if e.status != null:
        e.status.reset_all()
    if e.clock != null:
        e.clock.stop()
    e.hit_in = -1.0
    e.atk_left = 0.0
    e.kb = Vector3.ZERO
    # 先标 dying：使已捕获对象不能再被 _damage / _kill 打死发奖，也让破段强化 FX 立刻收尾。
    e.dying = 0.0
    var idx := enemies.find(e)
    if idx >= 0:
        enemies.remove_at(idx)
    if e.node != null and is_instance_valid(e.node):
        e.node.queue_free()


# 生产每帧检查：main._process 在 capture_presenting 时调用（暂停 / 设置时也调用，播放保持原样）。
#   - 失败目标那一份 FX 一结束就按记录的原 visible 恢复（即使同批次其它成功 FX 还在播）；
#   - 整批没有活动播放才结束批次：发延后奖励、恢复、刷新 HUD、放行战斗与事件泵。
func _capture_presentation_tick() -> void:
    if not capture_presenting:
        return
    if capture_fx == null or not is_instance_valid(capture_fx):
        _finish_capture_presentation()
        return
    for rec in _capture_restores:
        if bool(rec.get("restored", false)):
            continue
        if not bool(capture_fx.is_active(int(rec["id"]))):
            _restore_capture_record(rec)
    if int(capture_fx.play_count()) <= 0:
        _finish_capture_presentation()


# 整批结束：先收临时视觉 / 按原 visible 恢复失败目标，再每只分别给原 XP（护符 floor 顺序保留，
# 不合并），头目推进用现有 0.8s 回调但在演出之后才排；最后刷新 HUD 并放行被推迟的进化 / 换招事件泵。
func _finish_capture_presentation() -> void:
    if not capture_presenting and _capture_batch.is_empty() and _capture_rewards.is_empty():
        return
    capture_presenting = false
    # 收临时视觉：按记录的原 visible 原样恢复仍活的失败目标（幂等，只走一条记录）。
    for rec in _capture_restores:
        _restore_capture_record(rec)
    if capture_fx != null and is_instance_valid(capture_fx) and capture_fx.has_method("set_paused"):
        capture_fx.call("set_paused", false)
    var rewards := _capture_rewards.duplicate()
    if not rewards.is_empty() and not dead:
        if paused or capture_pause_mode:
            _slowmo_on_resume = true   # 在暂停抓宠页里抓的：等点继续（2026-10-22 审查发现这条路径没慢动作）
        else:
            _start_ball_slowmo(CAPTURE_AFTER_SLOWMO_SECS, CAPTURE_AFTER_SLOWMO_SCALE)   # 抓到了：游戏恢复时先慢 0.6 秒
    _capture_batch.clear()
    _capture_rewards.clear()
    _capture_restores.clear()
    for r in rewards:
        _capture_grant_reward(r)
    if _capture_pending_banner != "" and hud != null:
        hud.show_banner(_capture_pending_banner)
    _capture_pending_banner = ""
    if hud != null:
        _hud_stats()
    # 捕获期间被推迟的进化 / 换招在此继续（额外 XP 已在上面的 _gain_xp 里重新排过）。
    if _event_pending or not _pending_learns.is_empty():
        _start_event_pump()
    _fire_queued_throw()   # 预约的下一球：动画一完马上扔


# 每只成功目标各自的延后奖励：一次 _gain_xp（原 e.t["xp"]，护符在 _gain_xp 入口逐种 floor），
# 头目复用现有 0.8s 推进；不走 _kill、不加 kills / 点数 / 本局收入、不掉药 / 第二份 XP 球。
func _capture_grant_reward(r: Dictionary) -> void:
    if r == null or r.is_empty():
        return
    _gain_xp(float(r.get("xp", 0.0)) * kill_xp_scale)   # 捕获和击杀同一个经验系数（用户：一直用精灵球抓怪就能快速刷等级）
    if bool(r.get("boss", false)):
        _capture_schedule_boss(bool(r.get("final", false)), str(r.get("name", "")))


# 捕获头目延迟回调：token 在取消 / 重开 / 重复取消时 ++，晚到的回调据此幂等丢弃（不发胜利 / 不复活）。
func _capture_schedule_boss(final: bool, boss_name: String) -> void:
    var token := _capture_boss_token
    get_tree().create_timer(0.8, false).timeout.connect(_capture_boss_fire.bind(final, boss_name, token))


func _capture_boss_fire(final: bool, boss_name: String, token: int) -> void:
    if token != _capture_boss_token:
        return
    if not is_inside_tree():
        return
    _boss_reward(final, boss_name)


# 按失败记录恢复显示：只还原该目标投球前记录的原 visible，幂等；不重置 HP / 状态 / 钟 / 攻击计时。
func _restore_capture_record(rec) -> void:
    if rec == null or not (rec is Dictionary):
        return
    if bool(rec.get("restored", false)):
        return
    rec["restored"] = true
    var e = rec.get("enemy")
    if e == null or not (e is Object) or not is_instance_valid(e):
        return
    if e.node != null and is_instance_valid(e.node):
        e.node.visible = bool(rec.get("visible", true))


# 配对 FX 暂停（Esc 商店 / 设置 → Engine.time_scale=0 时冻结 FX 时间与自有音频）。
func _set_capture_fx_paused(value: bool) -> void:
    if capture_fx != null and is_instance_valid(capture_fx) and capture_fx.has_method("set_paused"):
        capture_fx.call("set_paused", value)


# 取消当前捕获演出批次：幂等。清原 FX 与自有音频、按记录的原 visible 恢复仍活的失败目标显示，
# 清 presenting / 待奖励 / 失败恢复 / 延迟头目 token。已成功落盘解锁保留；
# 未发的局内 XP / 头目按本作适配丢弃。不 late-callback 发 XP / 复活 / 重复结算。
func _cancel_capture_presentation() -> void:
    _capture_boss_token += 1
    capture_presenting = false
    _capture_pending_banner = ""
    for rec in _capture_restores:
        _restore_capture_record(rec)
    _capture_batch.clear()
    _capture_rewards.clear()
    _capture_restores.clear()
    if capture_fx != null and is_instance_valid(capture_fx):
        if capture_fx.has_method("set_paused"):
            capture_fx.call("set_paused", false)
        capture_fx.call("clear")


# 下层调用的上层函数占位：combat / arts 在继承链下层，解析时看不到派生脚本里的实现。
# 真实现分别在 arts.gd（_refresh_moves）和 cards.gd（_show_moves），这里是空占位、不改变玩法。
func _refresh_moves() -> void:
    pass
func _show_moves() -> void:
    pass
# 暂停抓宠界面里给“还没捕获的野生宠物”头上加 / 去掉「未捕获」标记（真实现在 enemies.gd）。
func _refresh_special_marks() -> void:
    pass
func _move_info(_id: String) -> String:
    return ""
# 捕获奖励要按原值走已有经验入口（真实现在 main/combat.gd，继承链上层）。基类留同名空占位，
# 保证 state.gd 自己的捕获结算能解析通过；纯基类实例下静默、不发经验。
func _gain_xp(_amount: float) -> void:
    pass
# 护盾（arts.gd 实现）：combat._hurt 在护盾挡伤害时调；基类留占位保证继承链解析通过。
func _break_shield(_source = null) -> void:
    pass
# 事件泵（combat.gd 实现）在捕获演出期间被推迟；整批结束后由本类 _finish_capture_presentation 重新放行。
# 基类留同名空占位，保证 state.gd 自己的捕获结算能解析通过。
func _start_event_pump() -> void:
    pass
# main.gd 每帧刷新 HUD；商店购买后 state 也要立即让 HUD 余额一致（继承链上层实现，这里占位）。
func _hud_stats() -> void:
    pass
# 局内伤药的真实治疗 / 清状态实现都在 main/combat.gd（继承链上层）。state 的购买路由在
# 扣款保存成功后调它们；基类留同名占位，保证整条链解析通过，纯基类实例下静默。
func heal_item(_amount: int) -> void:
    pass
func clear_major_status_item() -> bool:
    return false
# arts.gd 里的实现：招式数据查询。combat.gd 的异常接线要读它们，所以基类先留占位。
# 一个单位当前生效的特性：[特性, 被动?]。unit == null = 玩家。
func _ab_keys(unit) -> Array:
    var out: Array = []
    if unit == null:
        if player_ability != "":
            out.append(player_ability)
        if player_passive_on and player_passive != "":
            out.append(player_passive)
    else:
        if str(unit.ability) != "":
            out.append(str(unit.ability))
        if str(unit.passive) != "":
            out.append(str(unit.passive))
    return out


func _ab_has(unit, key: String) -> bool:
    return _ab_keys(unit).has(key)


func _ab_name(unit) -> String:
    var keys := _ab_keys(unit)
    return AB.name_of(str(keys[0])) if not keys.is_empty() else ""


func _player_types() -> Array:
    return []
func _enemy_types(_e) -> Array:
    return []
func _cd(_id: String) -> float:
    return 1.0

# ================= 异常状态接线占位（本类声明，combat / arts 里才有实现）=================
# game/pokemon_status_clock.gd 完全走闭包（update(status, on_tick, delta)），不需要宿主实现任何
# 方法；这里只留「下层 combat 用到、而实现可能在更上层」的查询占位，不改变无状态路径的行为。
func _has_actor_status() -> bool:
    return false

# 异常通用发动动画入口占位：实现在 arts.gd（那里持有 fx/rogue_moves.gd 播放器），
# combat.gd 的附加入口与每秒 tick（获得 / 阻断 / DoT / 混乱 lapse）都要调它。
# unit == null 表示玩家；空占位只在纯基类实例下静默，不改玩法。
func _play_common_fx(_common_id: String, _unit) -> void:
    pass

# 原作 StatChangePhase 的强化演出入口占位：实现在 arts.gd（那里持有 fx/rogue_stat_change.gd 播放器）。
# combat.gd 的破段强化结算要调它。unit == null 表示玩家；stat_ids 是本批聚合后的单项 / 多项统计。
# 空占位只在纯基类实例下静默，不改玩法。
func _play_stat_change_fx(_stat_ids: Array, _unit) -> void:
    pass

# 状态反馈横幅入口占位：实现在 arts.gd（走 HUD 的 show_banner）。combat.gd 的敌人
# 治愈 / 混乱解除反馈（每秒 tick）要调它；没有 HUD 时实现里静默。
func _show_status_feedback(_text: String) -> void:
    pass

# 临时原招 / common 播放清理入口占位：实现在 arts.gd（调用 fx/rogue_moves.gd::clear）。
# combat.gd 的 `_cancel_events`（真实取消 / 放弃 / 结算）要调它；必须能处理没有播放器 /
# 已释放 / 重复调用 / 退出树中调用，且不阻止之后重新创建播放器。
func _clear_status_fx() -> void:
    pass
