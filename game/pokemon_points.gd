extends RefCounted
# 击杀点数 + 商店第 2 段最小存档扩展（2026-10-15）+ 捕获第 2 段持久物种解锁。
#
# 这个类只做四件事，不建通用经济 / 账户 / 背包框架：
#   2. 一份本局获得计数（begin_run() 每次开局归零，不入档）；
#   3. 商店全体护符（第 2 段两种原经验护符 + 第 3 段原治愈护符）的**已买层数 + 首次获得顺序**
#      （与余额同档、同一次原子写入）。
#   4. 捕获第 2 段：[collection] caught 数组（已捕获的**准确 source_species_id**，升序、不重复），
#      与余额 / 护符同一份 tmp/bak/正式快照一起保存和恢复；旧档缺这一节按空数组兼容。
# 第 3 段新增最小消费入口 spend()：局内伤药只扣持久余额、不加层、不减本局获得，失败同样回滚并丢 tmp。
#
# 边界（本任务明确要求）：
#   - 点数只和“真实击杀次数”有关：不乘经验 / 等级 / 物种 baseExp / 稀有度 / 事件 / 密度 / debug_power。
#   - 每次进账立即落盘，不等捡球 / 结算；最终头目那 1 点在 0.8 秒胜利回调前就已写入。
#   - 保存用「临时文件 + 改名替换」：临时写失败时原档一个字节都不动；替换前先把原档改成 .bak，
#     替换失败再把 .bak 改回来，避免半写覆盖。
#   - 替换过程在「原档 → .bak」和「.tmp → 正式档」之间会有一个正式档暂时不存在的瞬间（不是“没有窗口”）。
#     reload() 专门处理这个中断状态：正式档缺失时按 `bak`（最后一次完整保存）→ `tmp`（待提交值）顺序
#     恢复**同一份完整快照**（余额 + 护符层数 + 顺序一起恢复，不分开），绝不把这种残留当成 new 0 覆盖。
#   - 旧档只有 [points] balance、没有 [charms] 时按空加成兼容（ST_LOADED，不需用户迁移）。
#   - 坏档 / 负数 / 非整数余额：reload() 如实返回错误状态，不改原档；此后 save_balance() 拒绝写入
#     （corrupt_locked），不会静默把坏档覆盖成“看起来成功”的新档。游戏本体照常启动。
#   - 坏加成数据（负数 / 非整数 / 超 cap / 未知 ID / 重复顺序 / 层数与顺序不匹配）：同样锁定并保留原档，
#     不静默丢掉效果后覆盖。
#   - 残留文件里没有任何合法快照时也锁定（corrupt），保留文件当证据，不伪装成新档。
#   - 有未保存收入（award 写盘失败后留在内存）时禁止消费：purchase_product() 直接拒绝，
#     不能花“幽灵余额”；只有真正 save_balance() 成功才清 pending（不看可被覆盖的 last_status）。
#   - 一次有效购买扣款 + 加层用**同一份完整 ConfigFile 快照**写 tmp/bak/正式；写失败或替换失败
#     回滚内存里的余额 / 层数 / 顺序，磁盘原档保持，不出现半扣 / 半送。
#     没有“关闭真实奖励”的开关 —— 测试也必须走真实 +1 流程。
#   - 不读写旧武侠 save.json / settings.cfg，也不和别的项目共用档案。

const PokemonShop := preload("res://game/pokemon_shop.gd")
const PokemonBerries := preload("res://game/pokemon_berries.gd")
const PokemonLens := preload("res://game/pokemon_lens.gd")
const HeldItems := preload("res://game/pokemon_held_items.gd")
const WildSpeciesData := preload("res://data/pokemon_wild_species.gd")
const PokemonTM := preload("res://game/pokemon_tm.gd")
# 捕获第 2 段：合法 ID 只认当前 84 条有限捕获率表，不建通用仓库。
const Species := preload("res://data/pokemon_capture_species.gd")

const DEFAULT_PATH := "user://pokemon_points.cfg"
const SECTION := "points"
const KEY_BALANCE := "balance"
# 商店第 2 段：护符层数与首次获得顺序与余额同档，同一份快照。
const SECT_CHARMS := "charms"
const KEY_ORDER := "order"     # Array[String]：不同种护符的首次获得顺序
const KEY_STACKS := "stacks"   # Dictionary：id -> 已买层数
# 捕获第 2 段：已捕获物种的准确 source_species_id（升序、不重复），与余额 / 护符同一份快照。
const SECT_COLLECTION := "collection"
const KEY_CAUGHT := "caught"
const KEY_SHINY := "shiny_caught"   # 抓到过闪光的物种 ID（升序、不重复）
# 通关记录（用户 2026-10-18：图鉴格子要看得出通关过没有）：物种 ID -> 用它通关的次数。
const SECT_RECORDS := "records"
const KEY_WINS := "wins"
# 特性（2026-10-18）：每只开局宝可梦选用的特性栏位（0 = 特性1 / 1 = 特性2 / 2 = 隐藏）和“抓到过隐藏特性”的起始种 ID（解锁隐藏栏）。
const SECT_ABILITY := "abilities"
const KEY_SLOTS := "slots"
const KEY_HIDDEN := "hidden_caught"

# 精灵球库存跨局保留（用户 2026-10-17：买的球要传到以后，不然局内买球很奇怪）。
# 缺失 / 不合法的旧档按“没有存球”处理（不锁档）；新局起手 = 每种取 max(原初始库存, 存下的数量)。
const SECT_BERRIES := "berries"   # 跨局树果库存 {"SITRUS": n, "LUM": n}（用户 2026-10-18：树果跨局保留，和精灵球一样）
const SECT_BALLS := "balls"
const KEY_COUNTS := "counts"

# 每只宝可梦各存一个已买颗数，开局时等级 = 1 + 颗数。缺失 / 不合法的条目丢掉（不锁档）。
const SECT_DEX := "dex_extra"   # 个体值最好记录（按起始种）/ 最爱 / 起名（按图鉴编号）
const SECT_HELD := "held"   # 携带道具：按进化系记（记在这一系最前面那只名下）
const SECT_NATURE := "natures"   # 性格：每一系抓到过哪些性格 + 选用哪个（原版：抓到才解锁）
const SECT_MAPS := "maps"   # 解锁了的地区（原版：走到过才算；平原一直开）
const SECT_SPECIES_CANDY := "species_candy"   # 物种糖果 / 好感 / 被动解锁（按起始种记，规则见 game/pokemon_species_candy.gd）
const SECT_LENS := "lens"   # 多重镜等级：物种 ID -> [辅助级, 进攻级]
const SECT_CANDY := "candy"
const KEY_LEVELS := "levels"

# 营养饮料（局外成长，用户 2026-10-16 定）：每只宝可梦六项努力值，每颗 +10，单项上限 252，六项都能拉满（没有合计 510 限制）；
# 打怪不给努力值。存 物种 ID -> [HP, 攻击, 防御, 特攻, 特防, 速度]。缺失 / 不合法的条目丢掉（不锁档）。
# 技能机器（局外成长，用户 2026-10-17：开局前选、最多填满 4 个槽）：每只宝可梦各存“买过的机器”和“开局带着的机器”。
# 买一次永久拥有（原版机器是一次性消耗，这里是局外成长，买了就一直有）；带着的必须是买过的，且数量不超过空槽数（调用方传入）。
const SECT_TM := "tm"
const SECT_MOVES := "moves_learned"   # 每一系在局里学过的招（PP 提升剂只要学过就能买；用户 2026-10-20）
const KEY_OWNED := "owned"
const KEY_EQUIPPED := "equipped"
const KEY_BENCHED := "benched"   # 留在家里不带的开局招（物种 ID -> 招式 id 列表），给技能机器腾槽
const ST_ALREADY_OWNED := "already_owned"
const ST_LAST_MOVE := "last_move"   # 不能把最后一个带着的招也留下
const SECT_EV := "ev"
const KEY_VALUES := "values"
const EV_PER_DRINK := 10
const EV_CAP := 252
const KILL_POINTS := 1
const LEVEL_POINT_DIVISOR := 20   # 敌人每 20 级多 1 点
const BOSS_POINT_MULT := 20       # 头目 ×20（用户 2026-10-22 从 ×5 提高：头目加强了，奖励也要值）

# reload() / save_balance() 的结果状态。调用方读它们判断“到底成没成”，不靠 bool。
const ST_NEW := "new"                     # 真的什么档都没有：新档从 0
const ST_LOADED := "loaded"               # 正常读回正式档
const ST_RECOVERED := "recovered"         # 正式档缺失，从 bak / tmp 恢复了完整快照
const ST_RECOVER_FAILED := "recover_failed"  # 找到旧快照但改名回正式档失败，锁定并保留文件
const ST_CORRUPT := "corrupt"             # 档在，但读不出合法快照 / 残留里没有合法快照
const ST_SAVED := "saved"                 # 写盘 + 替换都成功
const ST_WRITE_FAILED := "write_failed"   # 临时文件写不进去，原档保持
const ST_REPLACE_FAILED := "replace_failed"  # 临时文件写成功但替换失败，原档已尽量还原
const ST_CORRUPT_LOCKED := "corrupt_locked"  # 坏档 / 恢复失败未处理，拒绝覆盖
const ST_INVALID_POINTS := "invalid_points"  # 收入不是正整数
const ST_INVALID_BALANCE := "invalid_balance"  # 内存余额为负，拒绝写盘
const ST_PURCHASED := "purchased"         # 购买成功（扣款 + 加层 + 落盘都成）
const ST_PENDING_INCOME := "pending_income"  # 有未保存收入，禁止消费
const ST_AT_MAX := "at_max"               # 该护符已到上限
const ST_INSUFFICIENT := "insufficient_points"  # 余额不足
const ST_INVALID_PRICE := "invalid_price"  # 后端查表出的价格 / 上限不合法
# 捕获第 2 段解锁结果。
const ST_UNLOCKED := "unlocked"                 # 新物种已持久化入档
const ST_ALREADY_UNLOCKED := "already_unlocked" # 重复解锁幂等（不再写盘、不重复数组）
const ST_INVALID_SPECIES := "invalid_species"   # 不在当前 84 条合法 ID 内

var path: String
var balance := 0
var run_points := 0
# 护符：`charm_order` 是不同种的首次获得顺序（同种追加层数不换位置）；`charm_stacks` 是 id -> 层数。
var charm_order: Array = []
var charm_stacks: Dictionary = {}
# 捕获第 2 段：已捕获物种的准确 source_species_id（升序、不重复）。与余额 / 护符同一份快照，
# 旧档缺 [collection] 时按空数组兼容；球库存不在这里，只在 main/state.gd 本局内存。
var caught: Array = []
var shiny_caught: Array = []       # 抓到过闪光的物种（⊆ caught 的 ID，升序）
var shiny_best: Dictionary = {}    # 物种 ID(int) -> 抓到过的最高闪光档位（0 金 / 1 蓝 / 2 红）
var shiny_tiers: Dictionary = {}   # 物种 ID(int) -> 抓到过的闪光档位 Array（升序；选宠页只能选这些档。旧档没有这项时只认最高档）
var wins: Dictionary = {}          # 物种 ID(int) -> 用它通关的次数
var ability_slots: Dictionary = {} # 起始种 ID(int) -> 选用的特性栏位 0..2
var hidden_caught: Array = []      # 抓到过隐藏特性个体的起始种 ID（升序），解锁隐藏栏
var balls: Array = []   # 跨局球库存（5 个整数 0..BALL_CAP）；空 = 没存过
var berries: Dictionary = {}   # 跨局树果库存（种类 -> 个数 0..CAP）；空 = 没有
var candy: Dictionary = {}   # 物种 ID(int) -> 已买神奇糖果颗数(int > 0)
var ivs_best: Dictionary = {}      # 起始种 ID(int) -> 抓到过的每项最高个体值 [6]（原版：抓到更好的就记下，开局用它）
var favorites: Array = []          # 标了最爱的图鉴编号
var cakes := 0                      # 蛋糕（局里打怪掉，生蛋用；game/pokemon_eggs.gd）
var eggs: Array = []                # 正在孵的蛋，每颗 {species, parents, need, done, shiny, ivs, nature, hidden, move}
var hatch_log: Array = []           # 最近孵出来的（新的在前，最多 HATCH_LOG_MAX 条）：这颗蛋到底给了什么（用户 2026-10-24：“刚弄了一个完全不知道啥情况”）
const HATCH_LOG_MAX := 8
var egg_moves: Dictionary = {}      # 这一系最前面那只(int) -> 蛋孵出来带的遗传招 Array[String]（开局能选带）
var fusion: Dictionary = {}        # 主宠编号(int) -> 融合对象编号(int)（选宠页“融合”；规则 game/pokemon_fusion.gd）
var nicknames: Dictionary = {}     # 图鉴编号(int) -> 起的名字
var learn_plans: Dictionary = {}   # 图鉴编号(int) -> 学招计划（招式 id，最多 4 个）
var loadouts: Dictionary = {}      # 图鉴编号(int) -> 开局带哪几个招（管理招式里点出来的清单，最多 6 个）
var held: Dictionary = {}          # 起始种 ID(int) -> {道具 id: 个数}
var natures: Dictionary = {}       # 起始种 ID(int) -> 抓到过的性格 id Array（升序；没记的只有 0 勤奋）
var nature_pick: Dictionary = {}   # 起始种 ID(int) -> 开局用的性格 id
var maps_unlocked: Array = []   # 撤离走到过的地区 id（平原不用记，一直开）
var species_candy: Dictionary = {}   # 起始种 ID(int) -> 物种糖果颗数（原版 candyCount，和神奇糖果不是一种）
var friendship: Dictionary = {}      # 起始种 ID(int) -> 好感（攒满上限给 1 颗糖果后清零）
var passive_unlocked: Array = []     # 解锁了被动特性的起始种 ID（升序）
var passive_off: Array = []          # 解锁了但在选宠页关掉的起始种 ID（原版“禁用被动”）
var lens: Dictionary = {}    # 物种 ID(int) -> {"support": 级, "attack": 级}（至少一项 > 0 才存）
var ev: Dictionary = {}      # 物种 ID(int) -> 六项努力值 Array[int]（至少有一项 > 0 才存）
var moves_learned: Dictionary = {}   # 这一系最前面那只(int) -> 局里学过的招 Array[String]（只用来决定能不能买 PP 提升剂，不改开局能选哪些招）
var tm_owned: Dictionary = {}      # 物种 ID(int) -> 买过的技能机器 Array[String]（小写招式 id）
var tm_bench: Dictionary = {}      # 物种 ID(int) -> 留在家里的开局招 Array[String]（腾槽给技能机器）
var tm_equipped: Dictionary = {}   # 物种 ID(int) -> 开局带着的技能机器 Array[String]（⊆ tm_owned）
var last_status := ST_NEW
var last_error := ""
# 读到坏档 / 恢复失败 / 残留不可用后置真：保留磁盘文件，save_balance() 不再覆盖它
# （要修档由上层明确处理，不静默丢用户数据）。
var _locked_by_corrupt := false
# award 写盘失败后内存里还留着这次进账（击杀不白打）时置真；真正保存成功才清。
# 有它时禁止购买，不能拿没落盘的余额消费。
var _pending_income := false


func _init(save_path := DEFAULT_PATH) -> void:
	path = str(save_path)


# 从磁盘读回持久快照（余额 + 护符层数 + 顺序）。run_points 归 begin_run 管，这里不动。
# 返回 ST_NEW / ST_LOADED / ST_RECOVERED / ST_CORRUPT / ST_RECOVER_FAILED。
func reload() -> String:
	balance = 0
	charm_order = []
	charm_stacks = {}
	caught = []
	shiny_caught = []
	shiny_best = {}
	shiny_tiers = {}
	wins = {}
	ability_slots = {}
	hidden_caught = []
	balls = []
	berries = {}
	candy = {}
	species_candy = {}
	maps_unlocked = []
	natures = {}
	nature_pick = {}
	held = {}
	ivs_best = {}
	favorites = []
	nicknames = {}
	learn_plans = {}
	loadouts = {}
	fusion = {}
	cakes = 0
	eggs = []
	hatch_log = []
	egg_moves = {}
	friendship = {}
	passive_unlocked = []
	passive_off = []
	lens = {}
	ev = {}
	tm_owned = {}
	moves_learned = {}
	tm_equipped = {}
	tm_bench = {}
	_locked_by_corrupt = false
	_pending_income = false
	last_error = ""
	# 1) 正式档在就是唯一事实。有效快照就读回；损坏 / 负数 / 非整数 / 坏加成则锁定，绝不改原档。
	if FileAccess.file_exists(path):
		var formal := _read_snapshot(path)
		if bool(formal["ok"]) and int(formal.get("version", 0)) > SAVE_VERSION:
			# 存档比这个版本的游戏新：读得出也不能写，旧代码会把新字段丢掉
			_locked_by_corrupt = true
			last_status = ST_CORRUPT
			last_error = "newer_save_version_%d" % int(formal["version"])
			return last_status
		if bool(formal["ok"]):
			_daily_backup()   # 采用之前先备份今天的（每天一份）
			_adopt(formal)
			last_status = ST_LOADED
			return last_status
		_locked_by_corrupt = true
		last_status = ST_CORRUPT
		last_error = str(formal["reason"])
		return last_status
	# 2) 正式档不在：上次保存可能在「原档 → .bak」与「.tmp → 正式档」之间中断。
	#    先找回已保存的旧快照，不能当新档从 0 覆盖。顺序：有效 bak（最后一次完整保存）→ 有效 tmp（待提交值）。
	var bak := path + ".bak"
	var tmp := path + ".tmp"
	var has_bak := FileAccess.file_exists(bak)
	var has_tmp := FileAccess.file_exists(tmp)
	var bak_snap: Dictionary = _read_snapshot(bak) if has_bak else {"ok": false}
	var tmp_snap: Dictionary = _read_snapshot(tmp) if has_tmp else {"ok": false}
	if bool(bak_snap["ok"]):
		return _recover_from(bak, bak_snap, "bak")
	if bool(tmp_snap["ok"]):
		return _recover_from(tmp, tmp_snap, "tmp")
	# 3) 有残留但没有任何合法快照：锁定并保留证据，不伪装成新档。
	if has_bak or has_tmp:
		_locked_by_corrupt = true
		last_status = ST_CORRUPT
		last_error = "unusable_remnants"
		return last_status
	last_status = ST_NEW
	return last_status


# 把 bak / tmp 改名回正式档并采用它的完整快照。改名失败就锁定、保留文件、如实报错（不落到 new 0）。
func _recover_from(source: String, snap: Dictionary, label: String) -> String:
	_adopt(snap)
	if not _rename(source, path):
		_locked_by_corrupt = true
		last_status = ST_RECOVER_FAILED
		last_error = "restore_%s_failed" % label
		return last_status
	last_status = ST_RECOVERED
	return last_status


# 每次真正开新局（或场景 reload 后重新进场）调一次：本局计数归零，再从同一个文件读回总余额与护符。
func begin_run() -> String:
	run_points = 0
	return reload()


# 真实击杀进账：points 必须是正整数。合法则立即 + 余额 / + 本局，并马上尝试落盘。
# 返回 {"ok": bool, "status": String, "balance": int, "run_points": int}。
# 写盘失败时内存里仍记着这次进账（击杀不会白打），status 明确报出失败、原档不动；
# 下一次 save_balance() 会带着累计值重试。调用方（state.gd）负责把失败显示给玩家。
func award(points: int) -> Dictionary:
	if typeof(points) != TYPE_INT or points <= 0:
		last_status = ST_INVALID_POINTS
		last_error = "points=%s" % str(points)
		return {"ok": false, "status": last_status, "balance": balance, "run_points": run_points}
	balance += points
	run_points += points
	var status := save_balance()
	if status != ST_SAVED:
		_pending_income = true
	return {"ok": status == ST_SAVED, "status": status, "balance": balance, "run_points": run_points}


# 生产击杀入口：一只敌人一次。无参 = 固定 1 点（老口径）；带敌人等级时按等级给（用户 2026-10-17：“高等级的怪给的点数一样吗？……对”）。
func add_kill(enemy_level := 0, boss := false) -> Dictionary:
	return award(kill_points_for(enemy_level, boss))


# 每只点数 = 1 + 敌人等级 ÷ 20（向下取整，最低 1 点），头目 ×5。Lv.60 → 4，Lv.300 → 16，Lv.1000 → 51。
static func kill_points_for(enemy_level: int, boss := false) -> int:
	var base := KILL_POINTS + maxi(0, enemy_level) / LEVEL_POINT_DIVISOR
	return base * (BOSS_POINT_MULT if boss else 1)


func is_corrupt() -> bool:
	return _locked_by_corrupt


# 有未保存收入（award 失败留在内存）时为真；购买前必须查它。
func has_pending_income() -> bool:
	return _pending_income


func owned_stacks(source_id: String) -> int:
	return int(charm_stacks.get(source_id, 0))


# 把当前余额 + 护符层数 / 顺序写进 path（同一份完整快照）。先写 path + ".tmp"，成功后替换正式档。
# 失败返回明确状态，并尽量保证正式档还是原来那份；绝不返回“成功”来掩盖失败。
# ================= 存档保护（用户 2026-10-23：“感觉已经基本完工了”，做存档保护）=================
# 1) 版本号：写在 [meta] version。读到比本版本新的存档（用旧版游戏打开新存档）→ 锁住不写，免得旧代码把新字段丢掉。
#    以后改存档格式：SAVE_VERSION +1，在 _migrate() 里把旧格式升上来，不要直接丢数据。
# 2) 每日备份：每天第一次读档时，把当时的存档复制到同目录 backups/<文件名>_<日期>.cfg，留最近 BACKUP_KEEP 份。
#    防的是“文件没坏、但被 bug 改错了”（例如 10-22 融合机器读档被删）：可以手动拿前几天的那份换回来。
# 3) 坏档 / 读不出来：照旧锁住、不写（保护原档），由 main 提示玩家备份在哪。
const SAVE_VERSION := 1
const SECT_META := "meta"
const BACKUP_DIR := "backups"
const BACKUP_KEEP := 10


func backup_dir() -> String:
	return path.get_base_dir().path_join(BACKUP_DIR)


# 每天第一次读到正式档时备份一份（今天已经有就不重复）；只多留 BACKUP_KEEP 份，最老的删掉。
func _daily_backup() -> void:
	if not FileAccess.file_exists(path):
		return
	var dir_path := backup_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var stem := path.get_file().get_basename()
	var d := Time.get_date_dict_from_system()
	var target := dir_path.path_join("%s_%04d%02d%02d.cfg" % [stem, int(d["year"]), int(d["month"]), int(d["day"])])
	if not FileAccess.file_exists(target):
		DirAccess.copy_absolute(path, target)
	var mine: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with(stem + "_") and f.ends_with(".cfg"):
			mine.append(f)
	mine.sort()
	while mine.size() > BACKUP_KEEP:
		dir.remove(str(mine.pop_front()))


func save_balance() -> String:
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		return last_status
	if balance < 0:
		last_status = ST_INVALID_BALANCE
		return last_status
	# 内存里的加成数据必须也可信，否则拒绝写盘（先锁定，保留原档，不静默丢效果）。
	var own_err := PokemonShop.owned_error(charm_order, charm_stacks)
	if own_err != "":
		_locked_by_corrupt = true
		last_status = ST_CORRUPT_LOCKED
		last_error = own_err
		return last_status
	# 捕获集合也必须可信（合法 ID / 整数 / 不重复），否则拒绝写盘、保留原档。
	var caught_err := _caught_error(caught)
	if caught_err != "":
		_locked_by_corrupt = true
		last_status = ST_CORRUPT_LOCKED
		last_error = caught_err
		return last_status
	var cfg := ConfigFile.new()
	cfg.set_value(SECT_META, "version", SAVE_VERSION)
	cfg.set_value(SECTION, KEY_BALANCE, balance)
	cfg.set_value(SECT_CHARMS, KEY_ORDER, charm_order)
	cfg.set_value(SECT_CHARMS, KEY_STACKS, charm_stacks)
	cfg.set_value(SECT_COLLECTION, KEY_CAUGHT, caught)
	cfg.set_value(SECT_COLLECTION, KEY_SHINY, shiny_caught)
	cfg.set_value(SECT_COLLECTION, "shiny_best", _shiny_best_to_save())
	cfg.set_value(SECT_COLLECTION, "shiny_tiers", _shiny_tiers_to_save())
	cfg.set_value(SECT_RECORDS, KEY_WINS, _wins_to_save())
	cfg.set_value(SECT_ABILITY, KEY_SLOTS, _slots_to_save())
	cfg.set_value(SECT_ABILITY, KEY_HIDDEN, hidden_caught)
	cfg.set_value(SECT_BALLS, KEY_COUNTS, balls)
	cfg.set_value(SECT_BERRIES, KEY_COUNTS, berries)
	cfg.set_value(SECT_CANDY, KEY_LEVELS, _candy_to_save())
	cfg.set_value(SECT_LENS, KEY_LEVELS, _lens_to_save())
	cfg.set_value(SECT_MAPS, "unlocked", maps_unlocked)
	cfg.set_value(SECT_HELD, "items", _held_to_save())
	cfg.set_value(SECT_DEX, "ivs", _shiny_tiers_to_save_generic(ivs_best))
	cfg.set_value(SECT_DEX, "favorites", favorites)
	cfg.set_value(SECT_DEX, "nicknames", _nick_to_save())
	cfg.set_value(SECT_DEX, "learn_plans", _plans_to_save())
	cfg.set_value(SECT_DEX, "loadouts", _loadouts_to_save())
	cfg.set_value(SECT_DEX, "fusion", _int_map_to_save_any(fusion))
	cfg.set_value("eggs", "cakes", cakes)
	cfg.set_value("eggs", "list", eggs)
	cfg.set_value("eggs", "hatched", hatch_log)
	cfg.set_value("eggs", "moves", _tm_to_save(egg_moves))
	cfg.set_value(SECT_NATURE, "caught", _shiny_tiers_to_save_generic(natures))
	cfg.set_value(SECT_NATURE, "pick", _int_map_to_save_any(nature_pick))
	cfg.set_value(SECT_SPECIES_CANDY, "candy", _int_map_to_save(species_candy))
	cfg.set_value(SECT_SPECIES_CANDY, "friendship", _int_map_to_save(friendship))
	cfg.set_value(SECT_SPECIES_CANDY, "passive", passive_unlocked)
	cfg.set_value(SECT_SPECIES_CANDY, "passive_off", passive_off)
	cfg.set_value(SECT_EV, KEY_VALUES, _ev_to_save())
	cfg.set_value(SECT_TM, KEY_OWNED, _tm_to_save(tm_owned))
	cfg.set_value(SECT_MOVES, "by_line", _tm_to_save(moves_learned))
	cfg.set_value(SECT_TM, KEY_EQUIPPED, _tm_to_save(tm_equipped))
	cfg.set_value(SECT_TM, KEY_BENCHED, _bench_to_save())
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		last_status = ST_WRITE_FAILED
		last_error = "tmp_save_error_%d" % err
		return last_status
	if not _replace_with_tmp(tmp):
		last_status = ST_REPLACE_FAILED
		last_error = "replace_failed"
		return last_status
	last_status = ST_SAVED
	_pending_income = false
	return last_status


# 可信购买落盘：只由 game/pokemon_shop.gd 在校验商品 ID 后调用（价格 / 上限由 shop 查表传入）。
# 前提：无坏档锁定、无未保存收入、未满层、余额足够。
# 扣款 + 加层用同一份快照写盘；任一步失败就回滚余额 / 层数 / 顺序，磁盘原档保持。
func purchase_product(source_id: String, price: int, max_stacks: int) -> Dictionary:
	var out := {
		"ok": false, "status": ST_INVALID_PRICE, "source_id": str(source_id),
		"price": int(price), "balance": balance, "run_points": run_points,
	}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if price < 0 or max_stacks <= 0:
		last_status = ST_INVALID_PRICE
		return out
	var owned := owned_stacks(source_id)
	if owned >= max_stacks:
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_order: Array = charm_order.duplicate()
	var old_stacks: Dictionary = charm_stacks.duplicate()
	balance -= price
	# 首次获得才进顺序表；同种追加层数保持在原位（不换位置）。
	if not charm_order.has(source_id):
		charm_order.append(source_id)
	charm_stacks[source_id] = owned + 1
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		charm_order = old_order
		charm_stacks = old_stacks
		# 失败购买的 tmp 是**未提交候选**，必须丢掉：否则下次 reload 在正式档缺失时会把它
		# 当成“待提交的成功购买”恢复回来，出现 UI 说未扣款、重开却已扣款且护符生效。
		# 只丢 tmp；`.bak` 是上一份**已提交**快照，必须留给 reload 的既有恢复顺序。
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		out["run_points"] = run_points
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["run_points"] = run_points
	return out


# 商店第 3 段：局内伤药的最小消费入口（只扣持久余额，不加护符层数、不动本局获得计数）。
# 与 purchase_product 用同一份完整快照 / 同一套原子替换与失败回滚：扣款 + 保存成功才算成功；
# 有未保存收入、坏档锁定、余额不足、价格非法都拒绝；写盘 / 替换失败回滚内存并丢掉未提交 tmp。
# 返回 {"ok": bool, "status": String, "price": int, "balance": int, "run_points": int}。
func spend(price: int, new_balls := [], new_berries := {}) -> Dictionary:
	var out := {
		"ok": false, "status": ST_INVALID_PRICE, "price": int(price),
		"balance": balance, "run_points": run_points,
	}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if price < 0:
		last_status = ST_INVALID_PRICE
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_balls: Array = balls
	var old_berries: Dictionary = berries
	balance -= price
	if not (new_balls as Array).is_empty():
		balls = normalize_balls(new_balls)   # 买球：扣款 + 球库存同一份快照落盘
	if not (new_berries as Dictionary).is_empty():
		berries = normalize_berries(new_berries)   # 买树果：同理
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		balls = old_balls
		berries = old_berries
		# 与失败购买同一条处理：未提交 tmp 必须丢掉，否则下次 reload 会把它当成功扣款恢复。
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		out["run_points"] = run_points
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["run_points"] = run_points
	return out


# 树果库存规范化：只认已知种类，个数夹到 0..CAP；不是字典 = 空。
static func normalize_berries(value) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for kind: String in PokemonBerries.KINDS:
		var v = (value as Dictionary).get(kind, 0)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[kind] = clampi(int(v), 0, PokemonBerries.CAP)
	return out


# 球库存规范化：只取前 5 个整数，夹到 0..BALL_CAP；不够 5 个 / 不是数组 = 空（没存过）。
static func normalize_balls(value) -> Array:
	var out: Array = []
	if not (value is Array) or (value as Array).size() < PokemonShop.BALL_IDS.size():
		return out
	for i in PokemonShop.BALL_IDS.size():
		var v = value[i]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return []
		out.append(clampi(int(v), 0, PokemonShop.BALL_CAP))
	return out


# 神奇糖果存档规范化：只收“物种 ID → 正整数颗数”，键可以是整数或数字字符串；其它条目丢掉。
static func normalize_candy(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var v = value[k]
		if sid <= 0 or (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT):
			continue
		var n := clampi(int(v), 0, PokemonShop.CANDY_CAP)
		if n > 0:
			out[sid] = n
	return out


# 努力值存档规范化：键 = 物种 ID（整数 / 数字串），值 = 恰好 6 个数字（夹到 0..EV_CAP）；不合法的条目丢掉，全 0 的不存。
static func normalize_ev(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var arr = value[k]
		if sid <= 0 or not (arr is Array) or (arr as Array).size() != 6:
			continue
		var row: Array = []
		var ok := true
		var any := false
		for x in arr:
			if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
				ok = false
				break
			var n := clampi(int(x), 0, EV_CAP)
			row.append(n)
			any = any or n > 0
		if ok and any:
			out[sid] = row
	return out


# 技能机器存档规范化：键 = 物种 ID，值 = 不重复的小写招式 id 数组，且必须是本作的技能机器（PokemonTM.is_tm）；其它丢掉。
# 学过的招：{一系(int): [招式 id…]}，只留本作有 PP 的招（能买 PP 提升剂的）。
static func normalize_learned(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := int(str(k)) if str(k).is_valid_int() else -1
		var arr = value[k]
		if sid <= 0 or not (arr is Array):
			continue
		var row: Array = []
		for m in arr:
			if typeof(m) == TYPE_STRING and HeldItems.is_item(HeldItems.pp_up_item(str(m))) and not row.has(str(m)):
				row.append(str(m))
		if not row.is_empty():
			out[sid] = row
	return out


# 这一系学过的招（进化前后共用，记在 lens_root 名下）。
func moves_learned_for(species_id: int) -> Array:
	return (moves_learned.get(lens_root(species_id), []) as Array).duplicate()


# 局里学会新招时记一笔（已记过的不重复写盘）。返回有没有新记。
func note_moves_learned(species_id: int, move_ids: Array) -> bool:
	if _locked_by_corrupt or int(species_id) <= 0:
		return false
	var root := lens_root(int(species_id))
	var row: Array = (moves_learned.get(root, []) as Array).duplicate()
	var added := false
	for m in move_ids:
		var mid := str(m)
		if HeldItems.is_item(HeldItems.pp_up_item(mid)) and not row.has(mid):
			row.append(mid)
			added = true
	if not added:
		return false
	var old: Dictionary = moves_learned.duplicate(true)
	moves_learned[root] = row
	if save_balance() != ST_SAVED:
		moves_learned = old
		_discard_purchase_candidate()
		return false
	return true


static func normalize_tm(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var arr = value[k]
		if sid <= 0 or not (arr is Array):
			continue
		var row: Array = []
		for m in arr:
			if typeof(m) == TYPE_STRING and PokemonTM.is_tm(str(m)) and not row.has(str(m)):
				row.append(str(m))
		if not row.is_empty():
			out[sid] = row
	return out


# 留在家里的开局招：物种 ID -> 招式 id 字符串列表（不查招式表，只清掉坏条目 / 重复）。缺失 / 坏条目丢掉，不锁档。
static func normalize_bench(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var arr = value[k]
		if sid <= 0 or not (arr is Array):
			continue
		var row: Array = []
		for m in arr:
			if typeof(m) == TYPE_STRING and (m as String) != "" and not row.has(str(m)):
				row.append(str(m))
		if not row.is_empty():
			out[sid] = row
	return out


func _bench_to_save() -> Dictionary:
	var out := {}
	for sid in tm_bench:
		out[str(sid)] = (tm_bench[sid] as Array).duplicate()
	return out


# 通关次数：缺失 / 坏条目丢掉（不锁档）。
static func normalize_wins(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var n = value[k]
		if sid > 0 and (typeof(n) == TYPE_INT or typeof(n) == TYPE_FLOAT) and int(n) > 0:
			out[sid] = int(n)
	return out


func _wins_to_save() -> Dictionary:
	var out := {}
	for sid in wins:
		out[str(sid)] = int(wins[sid])
	return out


# 特性栏位：缺失 / 越界的条目丢掉（不锁档）。
static func normalize_slots(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var n = value[k]
		if sid > 0 and (typeof(n) == TYPE_INT or typeof(n) == TYPE_FLOAT) and int(n) >= 0 and int(n) <= 2:
			out[sid] = int(n)
	return out


func _slots_to_save() -> Dictionary:
	var out := {}
	for sid in ability_slots:
		out[str(sid)] = int(ability_slots[sid])
	return out


func ability_slot_for(species_id: int) -> int:
	return int(ability_slots.get(int(species_id), 0))


func has_hidden_ability(species_id: int) -> bool:
	return hidden_caught.has(int(species_id))


# 选用特性栏位并立即落盘；写盘失败回滚内存。
func set_ability_slot(species_id: int, slot: int) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0 or slot < 0 or slot > 2:
		return false
	var old: Dictionary = ability_slots.duplicate()
	ability_slots[sid] = slot
	if save_balance() != ST_SAVED:
		ability_slots = old
		_discard_purchase_candidate()
		return false
	return true


# 抓到了带隐藏特性的个体：解锁该起始种的隐藏栏。
func mark_hidden_ability(species_id: int) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0 or hidden_caught.has(sid):
		return false
	var old: Array = hidden_caught.duplicate()
	hidden_caught.append(sid)
	hidden_caught.sort()
	if save_balance() != ST_SAVED:
		hidden_caught = old
		_discard_purchase_candidate()
		return false
	return true


func wins_for(species_id: int) -> int:
	return int(wins.get(int(species_id), 0))


func has_shiny(species_id: int) -> bool:
	return shiny_caught.has(int(species_id))


# 记一次“抓到了闪光”：只记已经在 caught 里的物种（捕获成功后调用）；已记过就不重复写盘。
func mark_shiny_caught(species_id: int, variant := 0) -> bool:
	var sid := int(species_id)
	var v := clampi(int(variant), 0, 2)
	if _locked_by_corrupt or not caught.has(sid):
		return false
	var already := shiny_caught.has(sid)
	if already and shiny_tiers_for(sid).has(v):
		return false   # 这一档早就记过
	var old: Array = shiny_caught.duplicate()
	var old_best: Dictionary = shiny_best.duplicate()
	var old_tiers: Dictionary = shiny_tiers.duplicate(true)
	var tiers := shiny_tiers_for(sid)   # 先取（还没把 sid 加进 shiny_caught 时是空的），免得新物种被算出一个假的金闪档
	if not already:
		shiny_caught.append(sid)
		shiny_caught.sort()
	tiers.append(v)
	tiers.sort()
	shiny_tiers[sid] = tiers
	shiny_best[sid] = maxi(v, int(shiny_best.get(sid, v)))
	if save_balance() != ST_SAVED:
		shiny_caught = old
		shiny_best = old_best
		shiny_tiers = old_tiers
		_discard_purchase_candidate()
		return false
	return true


func _shiny_best_to_save() -> Dictionary:
	var out := {}
	for sid in shiny_best:
		out[str(sid)] = int(shiny_best[sid])
	return out


# 抓到过的闪光档位（升序）；旧档没记分档的只认最高档。
func shiny_tiers_for(species_id: int) -> Array:
	var sid := int(species_id)
	if not shiny_caught.has(sid):
		return []
	if shiny_tiers.has(sid):
		return (shiny_tiers[sid] as Array).duplicate()
	return [int(shiny_best.get(sid, 0))]


func _shiny_tiers_to_save() -> Dictionary:
	var out := {}
	for sid in shiny_tiers:
		out[str(sid)] = (shiny_tiers[sid] as Array).duplicate()
	return out


static func normalize_shiny_tiers(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := int(str(k)) if str(k).is_valid_int() else -1
		var arr: Array = []
		if value[k] is Array:
			for x in value[k]:
				if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and int(x) >= 0 and int(x) <= 2 and not arr.has(int(x)):
					arr.append(int(x))
		arr.sort()
		if sid > 0 and not arr.is_empty():
			out[sid] = arr
	return out


# 抓到过的这只的最高闪光档位；没抓到过闪光返回 -1。
func shiny_best_for(species_id: int) -> int:
	if not shiny_caught.has(int(species_id)):
		return -1
	return int(shiny_best.get(int(species_id), 0))


static func normalize_shiny_best(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var v = value[k]
		if sid > 0 and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			out[sid] = clampi(int(v), 0, 2)
	return out


# 记一次通关（用开局选的那只）。写盘失败回滚内存。
func add_win(species_id: int) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0:
		return false
	var old: Dictionary = wins.duplicate()
	wins[sid] = int(wins.get(sid, 0)) + 1
	if save_balance() != ST_SAVED:
		wins = old
		_discard_purchase_candidate()
		return false
	return true


func tm_bench_for(species_id: int) -> Array:
	return (tm_bench.get(int(species_id), []) as Array).duplicate()


# 把一个开局招留在家里 / 带上（不花点数）。starters = 这只的可用开局招；max_total = 招式槽总数（4）。
# 留下：至少还要剩一个招带着（开局招 + 机器）；带上：总数不能超过 max_total。
# 返回 {"ok","status","benched"(bool 现在是否留在家里)}。
func set_starter_benched(species_id: int, move_id: String, benched: bool, starters: Array, max_total: int) -> Dictionary:
	var sid := int(species_id)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "benched": tm_bench_for(sid).has(move_id)}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if not starters.has(move_id):
		last_status = ST_INVALID_PRICE
		return out
	var old_bench: Dictionary = tm_bench.duplicate(true)
	var row: Array = tm_bench_for(sid)
	if benched == row.has(move_id):
		out["ok"] = true
		out["status"] = ST_SAVED
		return out
	var equipped_n := tm_equipped_for(sid).size()
	if benched:
		row.append(move_id)
	else:
		row.erase(move_id)
	var carried := 0
	for m in starters:
		if not row.has(m):
			carried += 1
	carried += equipped_n
	if benched and carried < 1:
		last_status = ST_LAST_MOVE
		out["status"] = last_status
		return out
	if not benched and carried > max_total:
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if row.is_empty():
		tm_bench.erase(sid)
	else:
		tm_bench[sid] = row
	var status := save_balance()
	if status != ST_SAVED:
		tm_bench = old_bench
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_SAVED
	out["benched"] = benched
	return out


func _tm_to_save(src: Dictionary) -> Dictionary:
	var out := {}
	for sid in src:
		out[str(sid)] = (src[sid] as Array).duplicate()
	return out


# 进化前的各形态编号（近的在前）：绿毛虫线内置 10 → 11 → 12，其余查进化表。
static func line_ancestors(species_id: int) -> Array:
	var out: Array = []
	var cur := int(species_id)
	for _i in 6:
		var pre := -1
		if cur == 11:
			pre = 10
		elif cur == 12:
			pre = 11
		else:
			pre = int(WildSpeciesData.prevolution_of(cur))
		if pre <= 0 or out.has(pre):
			break
		out.append(pre)
		cur = pre
	return out


# 这只宝可梦的技能机器：自己买的 + 进化前买的（用户 2026-10-18：绿毛虫买了机器，铁甲蛹和巴大蝶也该能用）。
func tm_owned_for(species_id: int) -> Array:
	var out: Array = (tm_owned.get(int(species_id), []) as Array).duplicate()
	for pre in line_ancestors(int(species_id)):
		for m in (tm_owned.get(int(pre), []) as Array):
			if not out.has(m):
				out.append(m)
	return out


# 只算这只自己名下买的（写档 / 购买判断用，不含从进化前继承来的）。
func tm_owned_own(species_id: int) -> Array:
	return (tm_owned.get(int(species_id), []) as Array).duplicate()


func tm_equipped_for(species_id: int) -> Array:
	return (tm_equipped.get(int(species_id), []) as Array).duplicate()


# 买一个技能机器（永久拥有）：已有的拒买；扣款 + 拥有同一份快照落盘；买到后如果还有空槽（free_slots > 0）自动带上；写盘失败回滚。
# 返回 {"ok","status","price","balance","run_points","equipped"(bool)}。能不能学 / 价格由调用方（PokemonTM）算好传进来。
func buy_tm(species_id: int, move_id: String, price: int, free_slots: int) -> Dictionary:
	var sid := int(species_id)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "price": int(price), "balance": balance,
		"run_points": run_points, "equipped": false}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if price < 0 or sid <= 0 or move_id == "":
		last_status = ST_INVALID_PRICE
		return out
	if tm_owned_for(sid).has(move_id):
		last_status = ST_ALREADY_OWNED
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_owned: Dictionary = tm_owned.duplicate(true)
	var old_eq: Dictionary = tm_equipped.duplicate(true)
	balance -= price
	var owned: Array = tm_owned_own(sid)
	owned.append(move_id)
	tm_owned[sid] = owned
	# 买了就带上（用户 2026-10-22：“买了的技能应该都带”）；机器已经带满了，就把最早带上的那个换下来
	var auto := free_slots > 0
	if auto:
		var eq: Array = tm_equipped_for(sid)
		while eq.size() >= free_slots:
			eq.pop_front()
		eq.append(move_id)
		tm_equipped[sid] = eq
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		tm_owned = old_owned
		tm_equipped = old_eq
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["equipped"] = auto
	return out


# 带上 / 取下已买过的机器（不花点数）：带上要求有空槽（slots = 这只开局最多带几个机器）。返回 {"ok","status","equipped"(bool)}。
# extra_owned：融合对象那边买过的机器，融合后也能带（用户 2026-10-22）。
func set_tm_equipped(species_id: int, move_id: String, on: bool, slots: int, extra_owned: Array = []) -> Dictionary:
	var sid := int(species_id)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "equipped": tm_equipped_for(sid).has(move_id)}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if not tm_owned_for(sid).has(move_id) and not (on == false or extra_owned.has(move_id)):
		last_status = ST_INVALID_PRICE
		return out
	var old_eq: Dictionary = tm_equipped.duplicate(true)
	var eq: Array = tm_equipped_for(sid)
	if on:
		if eq.has(move_id):
			out["ok"] = true
			out["status"] = ST_SAVED
			return out
		if slots <= 0:
			last_status = ST_AT_MAX
			out["status"] = last_status
			return out
		while eq.size() >= slots:
			eq.pop_front()   # 满了：换下最早带上的那个
		eq.append(move_id)
	else:
		eq.erase(move_id)
	if eq.is_empty():
		tm_equipped.erase(sid)
	else:
		tm_equipped[sid] = eq
	var status := save_balance()
	if status != ST_SAVED:
		tm_equipped = old_eq
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_SAVED
	out["equipped"] = on
	return out


func _ev_to_save() -> Dictionary:
	var out := {}
	for sid in ev:
		out[str(sid)] = (ev[sid] as Array).duplicate()
	return out


# 这只宝可梦的六项努力值（没买过 = 全 0）。
func ev_for(species_id: int) -> Array:
	if ev.has(int(species_id)):
		return (ev[int(species_id)] as Array).duplicate()
	return [0, 0, 0, 0, 0, 0]


# 买一颗营养饮料：这只宝可梦的第 stat_index 项（0..5 = HP / 攻击 / 防御 / 特攻 / 特防 / 速度）努力值 +10（最多到 252），
# 扣款 + 努力值同一份快照落盘；已经 252 拒买；写盘失败回滚。返回 {"ok","status","price","balance","run_points","ev"}。
func buy_ev(species_id: int, stat_index: int, price: int) -> Dictionary:
	var sid := int(species_id)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "price": int(price), "balance": balance,
		"run_points": run_points, "ev": ev_for(sid)}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if price < 0 or sid <= 0 or stat_index < 0 or stat_index > 5:
		last_status = ST_INVALID_PRICE
		return out
	var row: Array = ev_for(sid)
	if int(row[stat_index]) >= EV_CAP:
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_ev: Dictionary = ev.duplicate(true)
	balance -= price
	row[stat_index] = mini(EV_CAP, int(row[stat_index]) + EV_PER_DRINK)
	ev[sid] = row
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		ev = old_ev
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		out["ev"] = ev_for(sid)
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["ev"] = row.duplicate()
	return out


func _lens_to_save() -> Dictionary:
	var out := {}
	for sid in lens:
		var d: Dictionary = lens[sid]
		var row := {}
		for kind: String in PokemonLens.KINDS:
			row[kind] = int(d.get(kind, 0))
		out[str(sid)] = row
	return out


# 多重镜等级规范化：物种 ID -> {support, attack}，各夹到 0..MAX_LEVEL，全 0 的丢掉。
static func normalize_lens(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := -1
		if typeof(k) == TYPE_INT:
			sid = int(k)
		elif typeof(k) == TYPE_STRING and (k as String).is_valid_int():
			sid = int(k)
		var v = value[k]
		if sid <= 0 or not (v is Dictionary):
			continue
		var levels := {}
		var any := false
		for kind: String in PokemonLens.KINDS:
			var n := 0
			if typeof((v as Dictionary).get(kind, 0)) in [TYPE_INT, TYPE_FLOAT]:
				n = clampi(int((v as Dictionary).get(kind, 0)), 0, PokemonLens.MAX_LEVEL)
			levels[kind] = n
			any = any or n > 0
		if any:
			out[sid] = levels
	return out


# ================= 个体值 / 最爱 / 起名（选宠页那几项，照原版） =================

# 这一系抓到过的每项最高个体值；没记过是全 0（和以前的默认一样）。
func ivs_for(root_id: int) -> Array:
	return (ivs_best.get(int(root_id), [0, 0, 0, 0, 0, 0]) as Array).duplicate()


# 抓到一只时调用：每项取更高的记下；没变就不写盘。返回有没有变好。
func record_ivs(root_id: int, ivs: Array) -> bool:
	var sid := int(root_id)
	if _locked_by_corrupt or sid <= 0 or ivs.size() != 6:
		return false
	var cur := ivs_for(sid)
	var better := false
	for i in 6:
		var v := clampi(int(ivs[i]), 0, 31)
		if v > int(cur[i]):
			cur[i] = v
			better = true
	if not better:
		return false
	var old: Dictionary = ivs_best.duplicate(true)
	ivs_best[sid] = cur
	if save_balance() != ST_SAVED:
		ivs_best = old
		_discard_purchase_candidate()
		return false
	return true


func is_favorite(species_id: int) -> bool:
	return favorites.has(int(species_id))


func set_favorite(species_id: int, on: bool) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0 or on == is_favorite(sid):
		return false
	var old: Array = favorites.duplicate()
	if on:
		favorites.append(sid)
	else:
		favorites.erase(sid)
	if save_balance() != ST_SAVED:
		favorites = old
		_discard_purchase_candidate()
		return false
	return true


# 融合对象（0 = 不融合）。只认抓到过的、不是自己的。
# ================= 生蛋（game/pokemon_eggs.gd）=================
func add_cake(n := 1) -> bool:
	if _locked_by_corrupt or n <= 0:
		return false
	cakes += n
	return save_balance() == ST_SAVED


# 生一颗蛋：扣一块蛋糕，最多 max_eggs 颗。返回 ok。
func lay_egg(egg: Dictionary, max_eggs: int) -> bool:
	if _locked_by_corrupt or cakes <= 0 or eggs.size() >= max_eggs:
		return false
	cakes -= 1
	eggs.append(egg.duplicate(true))
	if save_balance() != ST_SAVED:
		cakes += 1
		eggs.pop_back()
		return false
	return true


# 每打死一只怪：所有蛋 +n；够数的孵出来（解锁 / 闪光 / 个体值 / 性格 / 隐藏特性 / 遗传招），返回孵出来的蛋。
# 不单独存盘：击杀进账那次 save 会一起写进去；孵出来时才立刻存。
func progress_eggs(n := 1) -> Array:
	var hatched: Array = []
	if _locked_by_corrupt or eggs.is_empty():
		return hatched
	var keep: Array = []
	for e: Dictionary in eggs:
		e["done"] = int(e.get("done", 0)) + n
		if int(e["done"]) >= int(e["need"]):
			hatched.append(e)
		else:
			keep.append(e)
	if hatched.is_empty():
		return hatched
	eggs = keep
	for e: Dictionary in hatched:
		_hatch(e)
	save_balance()
	return hatched


func _hatch(e: Dictionary) -> void:
	var sid := int(e["species"])
	var rec := _hatch_record(e)   # 先记下“这颗蛋给了什么”（和孵之前比）
	hatch_log.insert(0, rec)
	if hatch_log.size() > HATCH_LOG_MAX:
		hatch_log.resize(HATCH_LOG_MAX)
	if not caught.has(sid):
		caught.append(sid)
		caught.sort()
	var root := lens_root(sid)
	if int(e.get("shiny", -1)) >= 0:
		mark_shiny_caught(sid, int(e["shiny"]))   # 和抓到闪光同一条路（记分档 / 最高档）
	var cur: Array = ivs_best.get(root, [0, 0, 0, 0, 0, 0])
	var ivs: Array = e.get("ivs", [])
	var merged: Array = []
	for i in 6:
		merged.append(maxi(int(cur[i]) if cur.size() > i else 0, int(ivs[i]) if ivs.size() > i else 0))
	ivs_best[root] = merged
	var nat: Array = natures.get(root, [])
	if not nat.has(int(e.get("nature", 0))):
		nat.append(int(e.get("nature", 0)))
		natures[root] = nat
	if bool(e.get("hidden", false)) and not hidden_caught.has(root):
		hidden_caught.append(root)
	var mv := str(e.get("move", ""))
	if mv != "":
		var row: Array = egg_moves.get(root, [])
		if not row.has(mv):
			row.append(mv)
			egg_moves[root] = row


const IV_NAMES := ["HP", "攻击", "防御", "特攻", "特防", "速度"]


# 孵化记录：和孵之前的存档比，这颗蛋带来了什么（新物种 / 闪光档 / 哪几项个体值变高 / 新性格 / 隐藏特性 / 遗传招）。
func _hatch_record(e: Dictionary) -> Dictionary:
	var sid := int(e["species"])
	var root := lens_root(sid)
	var cur: Array = ivs_best.get(root, [0, 0, 0, 0, 0, 0])
	var ivs: Array = e.get("ivs", [])
	var up: Array = []
	for i in 6:
		var old := int(cur[i]) if cur.size() > i else 0
		var nv := int(ivs[i]) if ivs.size() > i else 0
		if nv > old:
			up.append("%s %d→%d" % [IV_NAMES[i], old, nv])
	var nat := int(e.get("nature", 0))
	var mv := str(e.get("move", ""))
	return {"species": sid, "new_species": not caught.has(sid), "shiny": int(e.get("shiny", -1)),
		"iv_up": up, "nature": nat, "nature_new": not (natures.get(root, []) as Array).has(nat),
		"hidden": bool(e.get("hidden", false)), "hidden_new": bool(e.get("hidden", false)) and not hidden_caught.has(root),
		"move": mv, "move_new": mv != "" and not (egg_moves.get(root, []) as Array).has(mv),
		"at": int(Time.get_unix_time_from_system())}


func egg_moves_for(species_id: int) -> Array:
	return (egg_moves.get(lens_root(species_id), []) as Array).duplicate()


func fusion_for(species_id: int) -> int:
	var f := int(fusion.get(int(species_id), 0))
	return f if f > 0 and f != int(species_id) and is_species_unlocked(f) else 0


func set_fusion(species_id: int, partner_id: int) -> bool:
	var sid := int(species_id)
	var pid := int(partner_id)
	if _locked_by_corrupt or sid <= 0 or pid == sid or (pid > 0 and not is_species_unlocked(pid)):
		return false
	var old: Dictionary = fusion.duplicate()
	if pid <= 0:
		fusion.erase(sid)
	else:
		fusion[sid] = pid
	if save_balance() != ST_SAVED:
		fusion = old
		_discard_purchase_candidate()
		return false
	return true


func nickname_for(species_id: int) -> String:
	return str(nicknames.get(int(species_id), ""))


# 起名（最多 12 个字）；空字符串 = 去掉名字。
func set_nickname(species_id: int, nick: String) -> bool:
	var sid := int(species_id)
	var n := nick.strip_edges().left(12)
	if _locked_by_corrupt or sid <= 0 or n == nickname_for(sid):
		return false
	var old: Dictionary = nicknames.duplicate()
	if n == "":
		nicknames.erase(sid)
	else:
		nicknames[sid] = n
	if save_balance() != ST_SAVED:
		nicknames = old
		_discard_purchase_candidate()
		return false
	return true


const LEARN_PLAN_MAX := 4


func learn_plan_for(species_id: int) -> Array:
	return (learn_plans.get(int(species_id), []) as Array).duplicate()


# 学招计划：勾 / 取消一个招（最多 4 个）。返回 {ok, reason}。
func toggle_learn_plan(species_id: int, move_id: String) -> Dictionary:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0 or move_id == "":
		return {"ok": false, "reason": "locked"}
	var old: Dictionary = learn_plans.duplicate(true)
	var arr := learn_plan_for(sid)
	if arr.has(move_id):
		arr.erase(move_id)
	elif arr.size() >= LEARN_PLAN_MAX:
		return {"ok": false, "reason": "full"}
	else:
		arr.append(move_id)
	if arr.is_empty():
		learn_plans.erase(sid)
	else:
		learn_plans[sid] = arr
	if save_balance() != ST_SAVED:
		learn_plans = old
		_discard_purchase_candidate()
		return {"ok": false, "reason": "save"}
	return {"ok": true, "reason": ""}


func clear_learn_plan(species_id: int) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or not learn_plans.has(sid):
		return false
	var old: Dictionary = learn_plans.duplicate(true)
	learn_plans.erase(sid)
	if save_balance() != ST_SAVED:
		learn_plans = old
		_discard_purchase_candidate()
		return false
	return true


func loadout_for(species_id: int) -> Array:
	return (loadouts.get(int(species_id), []) as Array).duplicate()


func set_loadout(species_id: int, moves: Array) -> bool:
	var sid := int(species_id)
	if _locked_by_corrupt or sid <= 0:
		return false
	var old: Dictionary = loadouts.duplicate(true)
	var arr: Array = []
	for m in moves:
		if not arr.has(str(m)) and arr.size() < 6:
			arr.append(str(m))
	if arr.is_empty():
		loadouts.erase(sid)
	else:
		loadouts[sid] = arr
	if save_balance() != ST_SAVED:
		loadouts = old
		_discard_purchase_candidate()
		return false
	return true


func _loadouts_to_save() -> Dictionary:
	var out := {}
	for k in loadouts:
		out[str(k)] = (loadouts[k] as Array).duplicate()
	return out


func _plans_to_save() -> Dictionary:
	var out := {}
	for k in learn_plans:
		out[str(k)] = (learn_plans[k] as Array).duplicate()
	return out


func _nick_to_save() -> Dictionary:
	var out := {}
	for k in nicknames:
		out[str(k)] = str(nicknames[k])
	return out


# ================= 携带道具（按进化系共用，记在 lens_root 名下；规则见 game/pokemon_held_items.gd） =================

func held_for(species_id: int, item: String) -> int:
	return int((held.get(lens_root(species_id), {}) as Dictionary).get(item, 0))


# 这一系带着的全部道具 {道具 id: 个数}（开局读一次）。
func held_all(species_id: int) -> Dictionary:
	return (held.get(lens_root(species_id), {}) as Dictionary).duplicate()


# 买一个：扣款 + 个数 +1 同一份快照落盘；满了 / 钱不够 / 坏档都拒绝，写盘失败回滚。
func buy_held(species_id: int, item: String) -> Dictionary:
	var sid := int(species_id)
	var have := held_for(sid, item)
	var price := HeldItems.price(item)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "price": price, "balance": balance,
		"run_points": run_points, "count": have}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if sid <= 0 or not HeldItems.is_item(item) or price < 0:
		last_status = ST_INVALID_PRICE
		return out
	if have >= HeldItems.max_stacks(item):
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_held: Dictionary = held.duplicate(true)
	balance -= price
	var root := lens_root(sid)
	var one: Dictionary = (held.get(root, {}) as Dictionary).duplicate()
	one[item] = have + 1
	held[root] = one
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		held = old_held
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["count"] = have + 1
	return out


# 用掉一个（复活种子 / 白色香草，原版用完就从身上拿掉）：个数 -1 落盘；没有 / 坏档返回 false。
func consume_held(species_id: int, item: String) -> bool:
	var have := held_for(int(species_id), item)
	if _locked_by_corrupt or have <= 0:
		return false
	var old: Dictionary = held.duplicate(true)
	var root := lens_root(int(species_id))
	var one: Dictionary = (held.get(root, {}) as Dictionary).duplicate()
	if have - 1 > 0:
		one[item] = have - 1
	else:
		one.erase(item)
	held[root] = one
	if save_balance() != ST_SAVED:
		held = old
		_discard_purchase_candidate()
		return false
	return true


func _held_to_save() -> Dictionary:
	var out := {}
	for k in held:
		var one := {}
		for it in held[k]:
			one[str(it)] = int(held[k][it])
		out[str(k)] = one
	return out


# ================= 性格（原版：抓到过这个性格的才能选；按起始种记，0 勤奋一直有） =================

func natures_for(root_id: int) -> Array:
	var out: Array = (natures.get(int(root_id), []) as Array).duplicate()
	if not out.has(0):
		out.append(0)
	out.sort()
	return out


# 抓到一只时调用：这一系多一个能选的性格。已有不重复写盘。
func unlock_nature(root_id: int, nature_id: int) -> bool:
	var sid := int(root_id)
	var n := int(nature_id)
	if _locked_by_corrupt or sid <= 0 or n < 0 or n > 24 or natures_for(sid).has(n):
		return false
	var old: Dictionary = natures.duplicate(true)
	var lst: Array = (natures.get(sid, []) as Array).duplicate()
	lst.append(n)
	lst.sort()
	natures[sid] = lst
	if save_balance() != ST_SAVED:
		natures = old
		_discard_purchase_candidate()
		return false
	return true


# 开局用的性格（没选过 / 选的没解锁 → 0 勤奋）。
func nature_pick_for(root_id: int) -> int:
	var n := int(nature_pick.get(int(root_id), 0))
	return n if natures_for(root_id).has(n) else 0


func set_nature_pick(root_id: int, nature_id: int) -> bool:
	var sid := int(root_id)
	if _locked_by_corrupt or not natures_for(sid).has(int(nature_id)):
		return false
	var old: Dictionary = nature_pick.duplicate()
	nature_pick[sid] = int(nature_id)
	if save_balance() != ST_SAVED:
		nature_pick = old
		_discard_purchase_candidate()
		return false
	return true


func _shiny_tiers_to_save_generic(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[str(k)] = (m[k] as Array).duplicate()
	return out


func _int_map_to_save_any(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		out[str(k)] = int(m[k])
	return out


static func normalize_id_lists(value, lo: int, hi: int) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := int(str(k)) if str(k).is_valid_int() else -1
		var arr: Array = []
		if value[k] is Array:
			for x in value[k]:
				if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and int(x) >= lo and int(x) <= hi and not arr.has(int(x)):
					arr.append(int(x))
		arr.sort()
		if sid > 0 and not arr.is_empty():
			out[sid] = arr
	return out


# ================= 地区解锁（原版：撤离走到过的地区才能直接选；平原一直开） =================

func is_map_unlocked(map_id: String) -> bool:
	return map_id == "plains" or maps_unlocked.has(map_id)


# 走到一个新地区时调用；已解锁不重复写盘。写盘失败回滚、返回 false。
func unlock_map(map_id: String) -> bool:
	if _locked_by_corrupt or map_id == "" or is_map_unlocked(map_id):
		return false
	var old: Array = maps_unlocked.duplicate()
	maps_unlocked.append(map_id)
	if save_balance() != ST_SAVED:
		maps_unlocked = old
		_discard_purchase_candidate()
		return false
	return true


# ================= 物种糖果 / 好感 / 被动（规则见 game/pokemon_species_candy.gd；sid 都是起始种 ID） =================

func species_candy_for(root_id: int) -> int:
	return int(species_candy.get(int(root_id), 0))


func friendship_for(root_id: int) -> int:
	return int(friendship.get(int(root_id), 0))


func is_passive_unlocked(root_id: int) -> bool:
	return passive_unlocked.has(int(root_id))


# 被动这一局生效吗：解锁了、而且没在选宠页关掉。
func is_passive_on(root_id: int) -> bool:
	return is_passive_unlocked(root_id) and not passive_off.has(int(root_id))


# 加糖果（抓到时调用）。写盘失败回滚、返回 false。
func add_species_candy(root_id: int, n: int) -> bool:
	var sid := int(root_id)
	if _locked_by_corrupt or sid <= 0 or n <= 0:
		return false
	var old: Dictionary = species_candy.duplicate()
	species_candy[sid] = species_candy_for(sid) + n
	if save_balance() != ST_SAVED:
		species_candy = old
		_discard_purchase_candidate()
		return false
	return true


# 加好感（局内每过一分钟调用）：满 cap 给 1 颗糖果、清零。返回这次得到几颗（写盘失败回滚、返回 -1）。
func add_friendship(root_id: int, amount: int, cap: int) -> int:
	var sid := int(root_id)
	if _locked_by_corrupt or sid <= 0 or amount <= 0 or cap <= 0:
		return 0
	var old_f: Dictionary = friendship.duplicate()
	var old_c: Dictionary = species_candy.duplicate()
	var f := friendship_for(sid) + amount
	var got := 0
	while f >= cap:   # 原版一次只给 1 颗、清零；一次加很多时照样每满一次给一颗
		f -= cap
		got += 1
	friendship[sid] = f
	if got > 0:
		species_candy[sid] = species_candy_for(sid) + got
	if save_balance() != ST_SAVED:
		friendship = old_f
		species_candy = old_c
		_discard_purchase_candidate()
		return -1
	return got


# 花糖果解锁被动：{"ok", "reason"}；reason = locked / already / not_enough / save_failed。
func unlock_passive(root_id: int, cost: int) -> Dictionary:
	var sid := int(root_id)
	if _locked_by_corrupt or sid <= 0:
		return {"ok": false, "reason": "locked"}
	if is_passive_unlocked(sid):
		return {"ok": false, "reason": "already"}
	if species_candy_for(sid) < cost:
		return {"ok": false, "reason": "not_enough"}
	var old_c: Dictionary = species_candy.duplicate()
	var old_p: Array = passive_unlocked.duplicate()
	species_candy[sid] = species_candy_for(sid) - cost
	passive_unlocked.append(sid)
	passive_unlocked.sort()
	if save_balance() != ST_SAVED:
		species_candy = old_c
		passive_unlocked = old_p
		_discard_purchase_candidate()
		return {"ok": false, "reason": "save_failed"}
	return {"ok": true, "reason": ""}


# 选宠页的“禁用被动”开关。
func set_passive_enabled(root_id: int, on: bool) -> bool:
	var sid := int(root_id)
	if _locked_by_corrupt or not is_passive_unlocked(sid) or on == not passive_off.has(sid):
		return false
	var old: Array = passive_off.duplicate()
	if on:
		passive_off.erase(sid)
	else:
		passive_off.append(sid)
		passive_off.sort()
	if save_balance() != ST_SAVED:
		passive_off = old
		_discard_purchase_candidate()
		return false
	return true


func _int_map_to_save(m: Dictionary) -> Dictionary:
	var out := {}
	for k in m:
		if int(m[k]) > 0:
			out[str(k)] = int(m[k])
	return out


static func normalize_int_map(value) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		return out
	for k in value:
		var sid := int(str(k)) if str(k).is_valid_int() else -1
		var v = value[k]
		if sid > 0 and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) > 0:
			out[sid] = int(v)
	return out


static func normalize_id_list(value) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for v in value:
		if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and int(v) > 0 and not out.has(int(v)):
			out.append(int(v))
	out.sort()
	return out


# 镜片按进化系共用（用户 2026-10-20：“同进化系的都要有”）：一系里给谁买都算整系的，记在这一系最前面那只名下。
static func lens_root(species_id: int) -> int:
	var anc := line_ancestors(int(species_id))
	return int(anc.back()) if not anc.is_empty() else int(species_id)


# 这只宝可梦某种多重镜的等级：整条进化系里取最高（旧档里记在进化后那只名下的也算）。
func lens_for(species_id: int, kind: String) -> int:
	var root := lens_root(species_id)
	var best := 0
	for k in lens:
		if lens_root(int(k)) == root:
			best = maxi(best, int((lens[k] as Dictionary).get(kind, 0)))
	return best


# 买一级多重镜：扣款 + 等级 +1 同一份快照落盘；逻辑和 buy_candy 一样（写盘失败回滚并丢掉未提交 tmp）。
func buy_lens(species_id: int, kind: String) -> Dictionary:
	var sid := int(species_id)
	var level := lens_for(sid, kind)
	var price := PokemonLens.next_price(kind, level)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "price": price, "balance": balance,
		"run_points": run_points, "level": level}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if sid <= 0 or not PokemonLens.KINDS.has(kind):
		last_status = ST_INVALID_PRICE
		return out
	if price < 0:
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_lens: Dictionary = lens.duplicate(true)
	balance -= price
	# 整系合到最前面那只名下（顺手把旧档记在别的形态名下的并过来），再升一级
	var root := lens_root(sid)
	var cur := {}
	for k2: String in PokemonLens.KINDS:
		cur[k2] = lens_for(sid, k2)
	for k in lens.keys():
		if lens_root(int(k)) == root:
			lens.erase(k)
	cur[kind] = level + 1
	lens[root] = cur
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		lens = old_lens
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		out["level"] = lens_for(sid, kind)
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["level"] = level + 1
	return out


func _candy_to_save() -> Dictionary:
	var out := {}
	for sid in candy:
		out[str(sid)] = int(candy[sid])
	return out


# 这只宝可梦已买的神奇糖果颗数（开局 +这么多级）。
func candy_for(species_id: int) -> int:
	return int(candy.get(int(species_id), 0))


# 买一颗神奇糖果：扣款 + 颗数 +1 同一份快照落盘；无存档锁定 / 无未保存收入 / 没到上限 / 余额够才成功；
# 写盘失败回滚余额和颗数并丢掉未提交 tmp。返回 {"ok", "status", "price", "balance", "run_points", "count"}。
func buy_candy(species_id: int, price: int, cap: int) -> Dictionary:
	var sid := int(species_id)
	var out := {"ok": false, "status": ST_INVALID_PRICE, "price": int(price), "balance": balance,
		"run_points": run_points, "count": candy_for(sid)}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if price < 0 or cap <= 0 or sid <= 0:
		last_status = ST_INVALID_PRICE
		return out
	var owned := candy_for(sid)
	if owned >= cap:
		last_status = ST_AT_MAX
		out["status"] = last_status
		return out
	if balance < price:
		last_status = ST_INSUFFICIENT
		out["status"] = last_status
		return out
	var old_balance := balance
	var old_candy: Dictionary = candy.duplicate()
	balance -= price
	candy[sid] = owned + 1
	var status := save_balance()
	if status != ST_SAVED:
		balance = old_balance
		candy = old_candy
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["balance"] = balance
		out["count"] = candy_for(sid)
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["status"] = ST_PURCHASED
	out["balance"] = balance
	out["count"] = owned + 1
	return out


# 把本局树果库存存进钱包；persist = true 时同时落盘（失败只返回状态，不影响战斗）。
func set_berries(counts: Dictionary, persist := false) -> String:
	berries = normalize_berries(counts)
	if persist:
		return save_balance()
	return last_status


# 把本局球库存存进钱包；persist = true 时同时落盘（失败只返回状态，不影响战斗）。
func set_balls(counts: Array, persist := false) -> String:
	balls = normalize_balls(counts)
	if persist:
		return save_balance()
	return last_status


# 捕获第 2 段：把一个准确的 source_species_id 持久化进 [collection] caught。
#   - 只接受当前 84 条合法 ID；其余 ST_INVALID_SPECIES，不写盘。
#   - 重复解锁幂等：OK / already_unlocked，不重复追加、不写盘。
#   - 坏档锁定 / 有未保存收入（pending_income）拒绝解锁，不冒充成功。
#   - 写入与余额 / 护符同一份完整快照（tmp -> bak -> 正式）；失败回滚内存集合并丢掉未提交 tmp。
# 返回 {"ok": bool, "status": String, "species_id": int, "added": bool, "balance": int,
#       "run_points": int, "caught": Array}。
func unlock_species(source_species_id: int) -> Dictionary:
	var sid := int(source_species_id)
	var out := {
		"ok": false, "status": ST_INVALID_SPECIES, "species_id": sid, "added": false,
		"balance": balance, "run_points": run_points, "caught": caught.duplicate(),
	}
	last_error = ""
	if _locked_by_corrupt:
		last_status = ST_CORRUPT_LOCKED
		out["status"] = last_status
		return out
	if _pending_income:
		last_status = ST_PENDING_INCOME
		out["status"] = last_status
		return out
	if not Species.has_species(sid):
		last_status = ST_INVALID_SPECIES
		return out
	if caught.has(sid):
		last_status = ST_ALREADY_UNLOCKED
		out["ok"] = true
		out["added"] = false
		out["status"] = last_status
		return out
	var old_caught: Array = caught.duplicate()
	caught.append(sid)
	caught.sort()
	var status := save_balance()
	if status != ST_SAVED:
		caught = old_caught
		# 与失败购买同一条处理：未提交 tmp 必须丢掉，否则 reload 会把这次解锁当成功恢复。
		_discard_purchase_candidate()
		last_status = status
		out["status"] = status
		out["caught"] = caught.duplicate()
		return out
	last_status = ST_SAVED
	out["ok"] = true
	out["added"] = true
	out["status"] = ST_UNLOCKED
	out["caught"] = caught.duplicate()
	return out


# 图鉴 / 选角后续只读查询：该准确 source_species_id 是否已持久解锁。
func is_species_unlocked(source_species_id: int) -> bool:
	return caught.has(int(source_species_id))


# 丢掉失败购买 / 失败解锁留下的未提交 tmp 候选（只删普通文件；tmp 位被目录占着时不动它，
# 那种情况本来就恢复不出合法快照，会由 reload 的“残留无合法快照”分支锁定）。
func _discard_purchase_candidate() -> void:
	var tmp := path + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)


# 临时文件 → 正式档。正式档存在时先改成 .bak 再改名，失败就把 .bak 改回来。
# 两步改名之间正式档会短暂缺失；那正是 reload() 的 bak/tmp 恢复分支要兜的中断状态。
func _replace_with_tmp(tmp: String) -> bool:
	var base := path.get_base_dir()
	var dir := DirAccess.open(base)
	if dir == null:
		return false
	if not dir.file_exists(path):
		return dir.rename(tmp, path) == OK
	var bak := path + ".bak"
	if dir.file_exists(bak):
		dir.remove(bak)
	if dir.rename(path, bak) != OK:
		return false
	if dir.rename(tmp, path) != OK:
		dir.rename(bak, path)   # 还原：宁可留下旧余额，也不留一个空档
		return false
	dir.remove(bak)
	return true


# 读一个 cfg 文件的完整快照（余额 + 护符层数 / 顺序 + 已捕获集合），只读判断，不修改任何文件。
# 返回 {"ok": bool, "reason": String, "balance": int, "order": Array, "stacks": Dictionary, "caught": Array}。
# 旧档只有 [points] balance 时 order / stacks / caught 为空，照样合法（空加成 / 空图鉴兼容）。
func _read_snapshot(p: String) -> Dictionary:
	var out := {"ok": false, "reason": "missing", "balance": -1, "order": [], "stacks": {}, "caught": [], "balls": [], "berries": {}, "shiny_best": {}, "shiny_tiers": {}, "candy": {}, "maps": [], "natures": {}, "held": {}, "ivs": {}, "favorites": [], "nicknames": {}, "fusion": {}, "nature_pick": {}, "species_candy": {}, "friendship": {}, "passive": [], "passive_off": [], "lens": {}, "ev": {}, "tm_owned": {}, "moves_learned": {}, "tm_equipped": {}, "tm_bench": {}, "shiny_caught": [], "wins": {}, "ability_slots": {}, "hidden_caught": []}
	if not FileAccess.file_exists(p):
		return out
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		out["reason"] = "load_failed"
		return out
	if not cfg.has_section_key(SECTION, KEY_BALANCE):
		out["reason"] = "balance_missing"
		return out
	var raw = cfg.get_value(SECTION, KEY_BALANCE)
	if typeof(raw) != TYPE_INT or int(raw) < 0:
		out["reason"] = "balance_invalid"
		return out
	out["version"] = int(cfg.get_value(SECT_META, "version", 0)) if typeof(cfg.get_value(SECT_META, "version", 0)) == TYPE_INT else 0   # 没写版本的旧档 = 0
	var has_order := cfg.has_section_key(SECT_CHARMS, KEY_ORDER)
	var has_stacks := cfg.has_section_key(SECT_CHARMS, KEY_STACKS)
	var order: Array = []
	var stacks: Dictionary = {}
	if has_order or has_stacks:
		if not (has_order and has_stacks):
			out["reason"] = "charms_partial"
			return out
		var order_v = cfg.get_value(SECT_CHARMS, KEY_ORDER)
		var stacks_v = cfg.get_value(SECT_CHARMS, KEY_STACKS)
		if not (order_v is Array) or not (stacks_v is Dictionary):
			out["reason"] = "charms_type"
			return out
		var norm := _normalize_charms(order_v, stacks_v)
		if norm.is_empty():
			out["reason"] = "charms_invalid"
			return out
		order = norm["order"]
		stacks = norm["stacks"]
	# 捕获集合：缺失 = 旧档兼容空；存在但不合法（非数组 / 未知 ID / 非整数 / 重复）锁定原档。
	var caught_ids: Array = []
	if cfg.has_section_key(SECT_COLLECTION, KEY_CAUGHT):
		var caught_v = cfg.get_value(SECT_COLLECTION, KEY_CAUGHT)
		var cnorm := _normalize_caught(caught_v)
		if not bool(cnorm["ok"]):
			out["reason"] = str(cnorm["reason"])
			return out
		caught_ids = cnorm["ids"]
	if cfg.has_section_key(SECT_BALLS, KEY_COUNTS):
		out["balls"] = normalize_balls(cfg.get_value(SECT_BALLS, KEY_COUNTS))
	if cfg.has_section_key(SECT_BERRIES, KEY_COUNTS):
		out["berries"] = normalize_berries(cfg.get_value(SECT_BERRIES, KEY_COUNTS))
	if cfg.has_section_key(SECT_CANDY, KEY_LEVELS):
		out["candy"] = normalize_candy(cfg.get_value(SECT_CANDY, KEY_LEVELS))
	if cfg.has_section_key(SECT_LENS, KEY_LEVELS):
		out["lens"] = normalize_lens(cfg.get_value(SECT_LENS, KEY_LEVELS))
	if cfg.has_section_key(SECT_DEX, "ivs"):
		var iv := {}
		var ivv = cfg.get_value(SECT_DEX, "ivs")
		if ivv is Dictionary:
			for k in ivv:
				if str(k).is_valid_int() and ivv[k] is Array and (ivv[k] as Array).size() == 6:
					var six: Array = []
					for x in ivv[k]:
						six.append(clampi(int(x), 0, 31) if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) else 0)
					iv[int(str(k))] = six
		out["ivs"] = iv
	if cfg.has_section_key(SECT_DEX, "favorites"):
		var fv: Array = []
		var fvv = cfg.get_value(SECT_DEX, "favorites")
		if fvv is Array:
			for x in fvv:
				if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and int(x) > 0 and not fv.has(int(x)):
					fv.append(int(x))
		out["favorites"] = fv
	if cfg.has_section_key("eggs", "cakes"):
		var cv = cfg.get_value("eggs", "cakes")
		out["cakes"] = maxi(0, int(cv)) if (typeof(cv) == TYPE_INT or typeof(cv) == TYPE_FLOAT) else 0
	if cfg.has_section_key("eggs", "list"):
		var el = cfg.get_value("eggs", "list")
		var good: Array = []
		if el is Array:
			for e in el:
				if e is Dictionary and int(e.get("species", 0)) > 0 and int(e.get("need", 0)) > 0:
					good.append((e as Dictionary).duplicate(true))
		out["eggs"] = good
	if cfg.has_section_key("eggs", "moves"):
		out["egg_moves"] = normalize_tm(cfg.get_value("eggs", "moves"))
	if cfg.has_section_key("eggs", "hatched"):
		var hl = cfg.get_value("eggs", "hatched")
		var hgood: Array = []
		if hl is Array:
			for h in hl:
				if h is Dictionary and int(h.get("species", 0)) > 0 and hgood.size() < HATCH_LOG_MAX:
					hgood.append((h as Dictionary).duplicate(true))
		out["hatch_log"] = hgood
	if cfg.has_section_key(SECT_DEX, "fusion"):
		var fu := {}
		var fv = cfg.get_value(SECT_DEX, "fusion")
		if fv is Dictionary:
			for k in fv:
				if str(k).is_valid_int() and (typeof(fv[k]) == TYPE_INT or typeof(fv[k]) == TYPE_FLOAT) and int(fv[k]) > 0 and int(str(k)) > 0:
					fu[int(str(k))] = int(fv[k])
		out["fusion"] = fu
	if cfg.has_section_key(SECT_DEX, "nicknames"):
		var nk := {}
		var nkv = cfg.get_value(SECT_DEX, "nicknames")
		if nkv is Dictionary:
			for k in nkv:
				if str(k).is_valid_int() and typeof(nkv[k]) == TYPE_STRING and str(nkv[k]).strip_edges() != "":
					nk[int(str(k))] = str(nkv[k]).strip_edges().left(12)
		out["nicknames"] = nk
	if cfg.has_section_key(SECT_DEX, "learn_plans"):
		var lp := {}
		var lpv = cfg.get_value(SECT_DEX, "learn_plans")
		if lpv is Dictionary:
			for k in lpv:
				if str(k).is_valid_int() and lpv[k] is Array:
					var arr: Array = []
					for m in lpv[k]:
						if typeof(m) == TYPE_STRING and not arr.has(str(m)) and arr.size() < LEARN_PLAN_MAX:
							arr.append(str(m))
					if not arr.is_empty():
						lp[int(str(k))] = arr
		out["learn_plans"] = lp
	if cfg.has_section_key(SECT_DEX, "loadouts"):
		var lo := {}
		var lov = cfg.get_value(SECT_DEX, "loadouts")
		if lov is Dictionary:
			for k in lov:
				if str(k).is_valid_int() and lov[k] is Array:
					var arr: Array = []
					for m in lov[k]:
						if typeof(m) == TYPE_STRING and not arr.has(str(m)) and arr.size() < 6:
							arr.append(str(m))
					if not arr.is_empty():
						lo[int(str(k))] = arr
		out["loadouts"] = lo
	if cfg.has_section_key(SECT_HELD, "items"):
		var hd := {}
		var hv = cfg.get_value(SECT_HELD, "items")
		if hv is Dictionary:
			for k in hv:
				if not str(k).is_valid_int() or not (hv[k] is Dictionary):
					continue
				var one := {}
				for it in hv[k]:
					var nn = hv[k][it]
					if HeldItems.is_item(str(it)) and (typeof(nn) == TYPE_INT or typeof(nn) == TYPE_FLOAT) and int(nn) > 0:
						one[str(it)] = mini(int(nn), HeldItems.max_stacks(str(it)))
				if not one.is_empty():
					hd[int(str(k))] = one
		out["held"] = hd
	if cfg.has_section_key(SECT_NATURE, "caught"):
		out["natures"] = normalize_id_lists(cfg.get_value(SECT_NATURE, "caught"), 0, 24)
	if cfg.has_section_key(SECT_NATURE, "pick"):
		var pk := {}
		var pv = cfg.get_value(SECT_NATURE, "pick")
		if pv is Dictionary:
			for k in pv:
				if str(k).is_valid_int() and (typeof(pv[k]) == TYPE_INT or typeof(pv[k]) == TYPE_FLOAT) and int(pv[k]) >= 0 and int(pv[k]) <= 24:
					pk[int(str(k))] = int(pv[k])
		out["nature_pick"] = pk
	if cfg.has_section_key(SECT_MAPS, "unlocked"):
		var ml: Array = []
		var mv = cfg.get_value(SECT_MAPS, "unlocked")
		if mv is Array:
			for x in mv:
				if typeof(x) == TYPE_STRING and not ml.has(x):
					ml.append(x)
		out["maps"] = ml
	if cfg.has_section_key(SECT_SPECIES_CANDY, "candy"):
		out["species_candy"] = normalize_int_map(cfg.get_value(SECT_SPECIES_CANDY, "candy"))
	if cfg.has_section_key(SECT_SPECIES_CANDY, "friendship"):
		out["friendship"] = normalize_int_map(cfg.get_value(SECT_SPECIES_CANDY, "friendship"))
	if cfg.has_section_key(SECT_SPECIES_CANDY, "passive"):
		out["passive"] = normalize_id_list(cfg.get_value(SECT_SPECIES_CANDY, "passive"))
	if cfg.has_section_key(SECT_SPECIES_CANDY, "passive_off"):
		out["passive_off"] = normalize_id_list(cfg.get_value(SECT_SPECIES_CANDY, "passive_off"))
	if cfg.has_section_key(SECT_EV, KEY_VALUES):
		out["ev"] = normalize_ev(cfg.get_value(SECT_EV, KEY_VALUES))
	if cfg.has_section_key(SECT_TM, KEY_OWNED):
		out["tm_owned"] = normalize_tm(cfg.get_value(SECT_TM, KEY_OWNED))
	if cfg.has_section_key(SECT_MOVES, "by_line"):
		out["moves_learned"] = normalize_learned(cfg.get_value(SECT_MOVES, "by_line"))
	if cfg.has_section_key(SECT_TM, KEY_EQUIPPED):
		out["tm_equipped"] = normalize_tm(cfg.get_value(SECT_TM, KEY_EQUIPPED))
		# 读档不再按“自己买过的”删：融合对象 / 进化前那只买的也能带（用户 2026-10-22 电磁波带不进去）。
		# 能不能真带由开局时 main/state.gd::_carried_loadout 按“自己 + 进化前 + 融合对象买过的”过滤。
	if cfg.has_section_key(SECT_COLLECTION, KEY_SHINY):
		var sv = cfg.get_value(SECT_COLLECTION, KEY_SHINY)
		var sl: Array = []
		if sv is Array:
			for x in sv:
				if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and int(x) > 0 and not sl.has(int(x)):
					sl.append(int(x))
		sl.sort()
		out["shiny_caught"] = sl
	if cfg.has_section_key(SECT_COLLECTION, "shiny_best"):
		out["shiny_best"] = normalize_shiny_best(cfg.get_value(SECT_COLLECTION, "shiny_best"))
	if cfg.has_section_key(SECT_COLLECTION, "shiny_tiers"):
		out["shiny_tiers"] = normalize_shiny_tiers(cfg.get_value(SECT_COLLECTION, "shiny_tiers"))
	if cfg.has_section_key(SECT_RECORDS, KEY_WINS):
		out["wins"] = normalize_wins(cfg.get_value(SECT_RECORDS, KEY_WINS))
	if cfg.has_section_key(SECT_ABILITY, KEY_SLOTS):
		out["ability_slots"] = normalize_slots(cfg.get_value(SECT_ABILITY, KEY_SLOTS))
	if cfg.has_section_key(SECT_ABILITY, KEY_HIDDEN):
		var hv = cfg.get_value(SECT_ABILITY, KEY_HIDDEN)
		var hl: Array = []
		if hv is Array:
			for x in hv:
				if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and int(x) > 0 and not hl.has(int(x)):
					hl.append(int(x))
		hl.sort()
		out["hidden_caught"] = hl
	if cfg.has_section_key(SECT_TM, KEY_BENCHED):
		out["tm_bench"] = normalize_bench(cfg.get_value(SECT_TM, KEY_BENCHED))
	out["ok"] = true
	out["reason"] = ""
	out["balance"] = int(raw)
	out["order"] = order
	out["stacks"] = stacks
	out["caught"] = caught_ids
	return out


# 校验并规范化护符层数 / 顺序；不合法返回 {}（调用方据此锁定）。
func _normalize_charms(order_v: Array, stacks_v: Dictionary) -> Dictionary:
	if PokemonShop.owned_error(order_v, stacks_v) != "":
		return {}
	var norm_stacks := {}
	for id in order_v:
		norm_stacks[str(id)] = int(PokemonShop._stack_int(stacks_v[str(id)]))
	return {"order": order_v.duplicate(), "stacks": norm_stacks}


# 校验并规范化已捕获集合：必须是 Array，条目是整数、属于当前 84 条合法 ID、且不重复。
# 不合法返回 {"ok": false, "reason": ...}，调用方据此锁定原档（不静默丢用户图鉴）。
func _normalize_caught(value) -> Dictionary:
	if not (value is Array):
		return {"ok": false, "reason": "collection_type"}
	var seen := {}
	var ids: Array = []
	for entry in value:
		if typeof(entry) != TYPE_INT:
			return {"ok": false, "reason": "collection_entry"}
		var id := int(entry)
		if not Species.has_species(id):
			return {"ok": false, "reason": "collection_unknown"}
		if seen.has(id):
			return {"ok": false, "reason": "collection_duplicate"}
		seen[id] = true
		ids.append(id)
	return {"ok": true, "reason": "", "ids": ids}


# 写盘前校验内存里的捕获集合；返回 "" 表示合法，否则返回错误码（锁定原档）。
func _caught_error(value) -> String:
	if not (value is Array):
		return "collection_type"
	var seen := {}
	for entry in value:
		if typeof(entry) != TYPE_INT:
			return "collection_entry"
		var id := int(entry)
		if not Species.has_species(id):
			return "collection_unknown"
		if seen.has(id):
			return "collection_duplicate"
		seen[id] = true
	return ""


# 采用一份完整快照（余额 + 护符 + 已捕获集合一起），不分开恢复。
func _adopt(snap: Dictionary) -> void:
	balance = int(snap["balance"])
	charm_order = (snap["order"] as Array).duplicate()
	charm_stacks = (snap["stacks"] as Dictionary).duplicate()
	caught = (snap.get("caught", []) as Array).duplicate()
	balls = (snap.get("balls", []) as Array).duplicate()
	berries = (snap.get("berries", {}) as Dictionary).duplicate()
	candy = (snap.get("candy", {}) as Dictionary).duplicate()
	lens = (snap.get("lens", {}) as Dictionary).duplicate(true)
	species_candy = (snap.get("species_candy", {}) as Dictionary).duplicate()
	maps_unlocked = (snap.get("maps", []) as Array).duplicate()
	natures = (snap.get("natures", {}) as Dictionary).duplicate(true)
	held = (snap.get("held", {}) as Dictionary).duplicate(true)
	ivs_best = (snap.get("ivs", {}) as Dictionary).duplicate(true)
	favorites = (snap.get("favorites", []) as Array).duplicate()
	nicknames = (snap.get("nicknames", {}) as Dictionary).duplicate()
	learn_plans = (snap.get("learn_plans", {}) as Dictionary).duplicate(true)
	loadouts = (snap.get("loadouts", {}) as Dictionary).duplicate(true)
	fusion = (snap.get("fusion", {}) as Dictionary).duplicate()
	cakes = int(snap.get("cakes", 0))
	eggs = (snap.get("eggs", []) as Array).duplicate(true)
	hatch_log = (snap.get("hatch_log", []) as Array).duplicate(true)
	egg_moves = (snap.get("egg_moves", {}) as Dictionary).duplicate(true)
	nature_pick = (snap.get("nature_pick", {}) as Dictionary).duplicate()
	friendship = (snap.get("friendship", {}) as Dictionary).duplicate()
	passive_unlocked = (snap.get("passive", []) as Array).duplicate()
	passive_off = (snap.get("passive_off", []) as Array).duplicate()
	ev = (snap.get("ev", {}) as Dictionary).duplicate(true)
	tm_owned = (snap.get("tm_owned", {}) as Dictionary).duplicate(true)
	moves_learned = (snap.get("moves_learned", {}) as Dictionary).duplicate(true)
	tm_equipped = (snap.get("tm_equipped", {}) as Dictionary).duplicate(true)
	tm_bench = (snap.get("tm_bench", {}) as Dictionary).duplicate(true)
	shiny_caught = (snap.get("shiny_caught", []) as Array).duplicate()
	shiny_best = (snap.get("shiny_best", {}) as Dictionary).duplicate()
	shiny_tiers = (snap.get("shiny_tiers", {}) as Dictionary).duplicate(true)
	wins = (snap.get("wins", {}) as Dictionary).duplicate()
	ability_slots = (snap.get("ability_slots", {}) as Dictionary).duplicate()
	hidden_caught = (snap.get("hidden_caught", []) as Array).duplicate()


# 同目录改名（恢复用）。目标已存在 / 不可写时返回 false，调用方据此锁定并保留文件。
func _rename(from: String, to: String) -> bool:
	var dir := DirAccess.open(from.get_base_dir())
	if dir == null:
		return false
	return dir.rename(from, to) == OK
