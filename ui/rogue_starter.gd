extends CanvasLayer
# 选宠页（原版 Pokémon Rogue 的 starter-select，鼠标操作版）。用户 2026-10-18: “他所有 UI 都是口袋妖怪原生的……
# 我们是可以鼠标选择的，其实比他的容易得多”“可以看到有没有抓到过、闪光抓没抓到各方面的信息”。
# 布局数字照原版 src/ui/starter-select-ui-handler.ts / starter-container.ts（原版逻辑像素，ui/rogue_ui.gd 统一 ×2 画到 640×360 的设计画布）。
#
# 对外接口和旧的城镇页（ui/town.gd）一致，main.gd 直接换用: 
#   signal depart_pressed / title_pressed / shop_pressed
#   setup(portrait, unit) / open() / open_skills() / open_overview() / close() / is_open() / current_tab()
#   set_points(total) / set_collection(ids) / set_tm_equipped(dict) / refresh_from(wallet)
#   selected_pokemon_id() / selected_map_id() / selected_entry_level() / selected_ditto_target() / can_depart()
#   start_level_provider: Callable（物种 ID -> 开局等级）
# 另有: signal buy_requested(product_id)（使用糖果）、signal move_toggle_requested(product_id)（管理招式: STARTER: / TM: 商品 ID，main 走同一条 _shop_buy）。
#
# 鼠标: 悬停 = 左边显示这只的信息；左键 = 选为首发（队伍栏出现它）；右键 = 菜单（选为首发 / 管理招式 / 使用糖果 / 取消 …）；滚轮 = 翻格子。
# 格子上一眼能看到: 米色圆底 = 已捕获（没抓到的是黑色剪影）、红星 = 抓到过闪光、徽章 = 用它通关过（先封掉，SHOW_WINS）、糖果 = 有糖果加成、左上数字 = 开局等级。

signal depart_pressed
signal title_pressed
signal shop_pressed
signal refresh_requested   # 打开 / 需要最新存档数据时发，main 调 refresh_from(钱包)
signal buy_requested(product_id: String)
signal move_toggle_requested(product_id: String)
signal ability_slot_requested(root_id: int, slot: int)   # 起始页点特性 / 按 E：换成下一个可用栏位（main 写存档并回显说明）
signal favorite_requested(species_id: int, on: bool)   # 添加 / 取消最爱
signal nickname_requested(species_id: int, nick: String)
signal learn_plan_requested(species_id: int, move_id: String)   # 学招计划：勾 / 取消（"" = 清空）   # 起名（空 = 去掉名字）
signal fusion_requested(species_id: int, partner_id: int)
signal breed_requested(species_id: int, partner_id: int)   # 生蛋：第一只亲代 + 第二只亲代（game/pokemon_eggs.gd）   # 融合：选对象（0 = 不融合）
signal nature_requested(root_id: int, nature_id: int)   # 性格那一处 / 按 N：换成下一个抓到过的性格（main 写存档）
signal passive_requested(root_id: int, action: String)   # 被动那一行 / 按 P："unlock" 花物种糖果解锁、"toggle" 开关（main 写存档并回显）

const RogueUI := preload("res://ui/rogue_ui.gd")
const MovePP := preload("res://game/pokemon_pp.gd")
const HeldItems := preload("res://game/pokemon_held_items.gd")
const Fusion := preload("res://game/pokemon_fusion.gd")
const Eggs := preload("res://game/pokemon_eggs.gd")
const RogueScreen := preload("res://ui/rogue_screen.gd")
const Atlas := preload("res://ui/rogue_atlas.gd")
const Biomes := preload("res://data/biomes.gd")
const Pokedex := preload("res://data/pokedex.gd")
const PokemonStarters := preload("res://game/pokemon_starters.gd")
const CaptureSpecies := preload("res://data/pokemon_capture_species.gd")
const WildSpecies := preload("res://data/pokemon_wild_species.gd")
const ShinyData := preload("res://data/pokemon_shiny_variants.gd")
const PokemonMoves := preload("res://data/pokemon_moves.gd")
const PokemonShop := preload("res://game/pokemon_shop.gd")
const CaterpieVisual := preload("res://characters/caterpie.gd")
const TMRules := preload("res://game/pokemon_tm.gd")
const AB := preload("res://game/pokemon_abilities.gd")
const SpeciesCandy := preload("res://game/pokemon_species_candy.gd")
const Growth := preload("res://game/pokemon_growth.gd")
const Evolution := preload("res://game/pokemon_evolution.gd")

const DEFAULT_POKEMON_ID := 10
const GRID_COLS := 9
const GRID_ROW_H := 17.0
const GRID_X := 115.0     # 格子容器（原 speciesContainerX + 6）
const GRID_Y := 9.0
const GRID_VISIBLE_ROWS := 8
const GROWTH_ZH := {0: "不规则", 1: "快", 2: "较快", 3: "较慢", 4: "慢", 5: "波动"}
const FILTERS := ["世代", "属性", "捕获", "解锁", "神兽", "排序"]   # “混合”一直没开放，用户 2026-10-23：改成神兽
const TYPES_ZH := ["一般", "火", "水", "电", "草", "冰", "格斗", "毒", "地面", "飞行", "超能力", "虫", "岩石", "幽灵", "龙", "恶", "钢", "妖精"]

var start_level_provider: Callable = Callable()
var _depart_btn := Button.new()   # main 的调试参数会按这个按钮（兼容旧城镇页），本页不显示

var _screen: Control
var _c: Control                    # 640×360 设计画布
var _grid: Control                 # 格子层（裁剪）
var _info: Control                 # 左边信息层（悬停 / 选中时重建）
var _team: Control                 # 右边队伍栏
var _popup: Control                # 弹出菜单层
var _ids: Array[int] = []
var _view: Array[int] = []
var _scroll := 0
var _selected := DEFAULT_POKEMON_ID
var _hover := 0
var _map := Biomes.DEFAULT_ID
var _entry_level := 0
var _filter := {"gen": 0, "type": "", "caught": 0, "unlock": 0, "legend": 0, "sort": 0}
# 神兽分类（原版物种表 legendary / mythical / subLegendary）：物种 → 1 神兽 / 2 幻之 / 3 准神兽
static var _legend_class := {}


static func legend_class(id: int) -> int:
	if _legend_class.is_empty():
		var f := FileAccess.open("res://data/rogue_upstream/species.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for key in parsed:
					var row: Dictionary = parsed[key]
					var c := 1 if bool(row.get("legendary", false)) else (2 if bool(row.get("mythical", false)) else (3 if bool(row.get("subLegendary", false)) else 0))
					if c > 0:
						_legend_class[int(row["id"])] = c
		_legend_class[-1] = 0   # 读过了的标记
	return int(_legend_class.get(id, 0))
var _opened := false
var _tab := "pokedex"
var _points := 0
var _caught := {}
var _shiny := {}
var _shiny_best := {}      # 物种 -> 抓到过的最高闪光档位（0 金 / 1 蓝 / 2 红）
var _shiny_tiers := {}     # 物种 -> 抓到过的闪光档位 Array（选宠页只能轮这些档）
var _shiny_on := {}        # 物种 -> 这次开局用哪档闪光（-1 关 / 0 金 / 1 蓝 / 2 红；选宠页开关，S 键轮换）
var _wins := {}
# 通关徽章 / “通关 N 次” / “通关过”筛选：2026-10-23 先封掉（无尽模式没有通关）；2026-10-25 有了“30 分钟毕业”，重新打开。
const SHOW_WINS := true
var _candy := {}
var _tm_owned := {}
var _wallet = null          # 钱包（只读：PP 提升剂个数 / 这一系学过的招）
var _moves_page := 0        # 管理招式窗口的页（一页 16 招）
# 左边信息栏翻页（用户 2026-10-24：“这里有 2 个 button 然后可以左右点，有些内容可以放去下一页”）：
# 0 形象（原样）/ 1 能力（六边形图：种族值 + 个体值）。V 键 = 下一页。（详情页做过，用户 2026-10-24 说没必要，去掉了）
var _info_page := 0
const INFO_PAGES := ["形象", "能力"]
const HD := preload("res://ui/hd_text.gd")
const StatRadarDual := preload("res://ui/stat_radar_dual.gd")
var _tm_equipped := {}
var _tm_bench := {}
var _ab_slots := {}      # 起始种 ID -> 选用的特性栏位
var _sp_candy := {}      # 起始种 ID -> 物种糖果（原版的糖果，抓到 / 好感满给；和神奇糖果不是一种）
var _passive_unlocked := {}   # 起始种 ID -> true
var _passive_off := {}        # 起始种 ID -> true（解锁了但关掉）
var _ivs := {}           # 起始种 ID -> 每项最好个体值 [6]
var _favorites := {}     # 图鉴编号 -> true
var _nicks := {}         # 图鉴编号 -> 起的名字
var _natures := {}       # 起始种 ID -> 抓到过的性格 id Array（含 0 勤奋）
var _nature_pick := {}   # 起始种 ID -> 选用的性格 id
var _maps_unlocked := {"plains": true}   # 能选的地区（原版：撤离走到过才算；平原一直开）
var _ab_hidden := {}     # 起始种 ID -> true（抓到过隐藏特性，隐藏栏已解锁）
var _portrait_cache := {}
var _name_of := {}


func _init() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# 列表是完整图鉴（全国 1025 + 地区条目），和换成原版界面之前一样都能翻（用户 2026-10-18：“没有换 ui 之前我们所有的宠物都可以看到”）。
	# 能上场 / 能捕获的只有捕获率表里的那些（平原 81 + 绿毛虫三形态 + 已接线地区）；其余只当图鉴看：没抓到永远是剪影，出发键灰着。
	for row: Dictionary in Pokedex.list():
		_ids.append(int(row["id"]))
	for id in CaptureSpecies.CATCH_RATES.keys():
		if not _ids.has(int(id)):
			_ids.append(int(id))
	_ids.sort()
	_screen = RogueScreen.new()
	add_child(_screen)
	_c = _screen.canvas
	_build_static()
	_apply_filter()


# ================= 对外接口（兼容旧城镇页）=================

func setup(_portrait: Texture2D, _unit: Dictionary) -> void:
	pass


func open(tab := "pokedex") -> void:
	_tab = tab
	_opened = true
	visible = true
	_close_popup()
	refresh_requested.emit()
	_refresh_all()


func open_skills() -> void:
	open("skills")


func open_overview() -> void:
	open("overview")


func close() -> void:
	_opened = false
	visible = false
	_close_popup()


func is_open() -> bool:
	return visible


func current_tab() -> String:
	return _tab


func set_points(total: int) -> void:
	_points = maxi(0, int(total))


func set_collection(caught_ids) -> void:
	_caught = {}
	if caught_ids != null:
		for id in caught_ids:
			_caught[int(id)] = true
	if visible:
		_refresh_all()


func set_tm_equipped(equipped: Dictionary) -> void:
	_tm_equipped = equipped.duplicate(true)
	if visible:
		_refresh_info(_shown_id())


# 从钱包一次性读全部要显示的东西（图鉴 / 闪光 / 通关 / 糖果 / 技能机器 / 开局招留下名单 / 点数）。
func refresh_from(w) -> void:
	if w == null:
		return
	_caught = {}
	for id in w.caught:
		_caught[int(id)] = true
	_shiny = {}
	for id in w.shiny_caught:
		_shiny[int(id)] = true
	_shiny_best = w.shiny_best.duplicate()
	_shiny_tiers = {}
	for sid in _shiny:
		_shiny_tiers[sid] = w.shiny_tiers_for(sid)
	_wins = w.wins.duplicate()
	_candy = w.candy.duplicate()
	_tm_owned = w.tm_owned.duplicate(true)
	_wallet = w
	_tm_equipped = w.tm_equipped.duplicate(true)
	_tm_bench = w.tm_bench.duplicate(true)
	_ab_slots = w.ability_slots.duplicate()
	_sp_candy = w.species_candy.duplicate()
	_passive_unlocked = {}
	for pid in w.passive_unlocked:
		_passive_unlocked[int(pid)] = true
	_passive_off = {}
	for pid in w.passive_off:
		_passive_off[int(pid)] = true
	_ivs = w.ivs_best.duplicate(true)
	_favorites = {}
	for fid in w.favorites:
		_favorites[int(fid)] = true
	_nicks = w.nicknames.duplicate()
	_natures = {}
	_nature_pick = {}
	for nid in _caught.keys() + [DEFAULT_POKEMON_ID]:
		var nroot := AB.root_of(int(nid))
		_natures[nroot] = w.natures_for(nroot)
		_nature_pick[nroot] = w.nature_pick_for(nroot)
	_maps_unlocked = {"plains": true}
	for mid in w.maps_unlocked:
		_maps_unlocked[str(mid)] = true
	if not _maps_unlocked.has(_map):
		_map = Biomes.DEFAULT_ID
	_ab_hidden = {}
	for hid in w.hidden_caught:
		_ab_hidden[int(hid)] = true
	_points = int(w.balance)
	if visible:
		_refresh_all()


func selected_map_id() -> String:
	return _map


func selected_entry_level() -> int:
	return _entry_level


func selected_pokemon_id() -> int:
	return _selected


# 选中的这只开局用闪光个体的话返回档位（0 金 / 1 蓝 / 2 红），否则 -1。要抓到过闪光、开关打开、而且能出发。
func selected_shiny_variant() -> int:
	if can_depart():
		return _start_shiny_tier(_selected)
	return -1


# 这只现在选的闪光档位（-1 = 关）；不会超过抓到过的最高档。
func _shiny_tier_on(id: int) -> int:
	var tiers := _tiers_of(id)
	# 没手动切过：默认开抓到过的最高档（用户 2026-10-23：“如果有闪光默认开最高级别闪光”）；按 S 关掉的记成 -1
	var t := int(_shiny_on[id]) if _shiny_on.has(id) else (int(tiers.max()) if not tiers.is_empty() else -1)
	return t if tiers.has(t) else -1


# 这只抓到过的闪光档位（升序）；测试直接塞 _shiny_best 时没有分档记录，就只认最高档。
func _tiers_of(id: int) -> Array:
	if _shiny_tiers.has(id):
		return _shiny_tiers[id]
	return [int(_shiny_best.get(id, 0))] if _shiny.has(id) else []


# 能不能自己闪光开局（自己抓到过闪光才有开关）。
func _shiny_ok(id: int) -> bool:
	return not _tiers_of(id).is_empty()


# 融合借来的闪光（用户 2026-10-21：“一只正常的融合了闪光就带闪光特效，但不会解锁闪光”；原版两只里有一只闪光就算闪光）：
# 融合对象抓到过的最高闪光档，换成主宠自己有的配色档（主宠没有那档蓝 / 红闪就往下落）；没有返回 -1。
func _fusion_shiny_tier(id: int) -> int:
	var partner := int(_wallet.fusion_for(id)) if _wallet != null else 0
	if partner <= 0 or _tiers_of(partner).is_empty():
		return -1
	var v := int((_tiers_of(partner) as Array).max())
	var form: Dictionary = WildSpecies.form_at(id, 0)
	var key := WildSpecies.file_base(id, str(form.get("sprite_key", "")))
	while v > 0 and not ShinyData.has_variant(key, v):
		v -= 1
	return v


# 出发时实际的闪光档：自己开的档和融合借来的档取高的（原版 getVariant 取两只里高的）。
func _start_shiny_tier(id: int) -> int:
	return maxi(_shiny_tier_on(id), _fusion_shiny_tier(id))


# 闪光加级用的两半：[主宠自己开的档, 融合对象抓到过的最高档]（-1 = 没有）。对象那半用它真实的档，不按主宠配色往下落。
func selected_shiny_parts() -> Array:
	if not can_depart():
		return [-1, -1]
	var partner := int(_wallet.fusion_for(_selected)) if _wallet != null else 0
	var pt := int((_tiers_of(partner) as Array).max()) if partner > 0 and not _tiers_of(partner).is_empty() else -1
	return [_shiny_tier_on(_selected), pt]


# 这一局的闪光是不是融合借来的（借来的不解锁主宠的闪光）。
func selected_shiny_from_fusion() -> bool:
	return can_depart() and _fusion_shiny_tier(_selected) > _shiny_tier_on(_selected)


func _toggle_shiny(id: int) -> void:
	if not _shiny_ok(id):
		return
	# 轮换：关 → 抓到过的最高档 → 下一档抓到过的 … → 关；没抓到过的档不出现（用户 2026-10-20）
	var tiers: Array = _tiers_of(id).duplicate()
	tiers.sort()
	tiers.reverse()   # 高档在前
	var cur := _shiny_tier_on(id)
	var i := tiers.find(cur)
	_shiny_on[id] = int(tiers[0]) if cur < 0 else (int(tiers[i + 1]) if i + 1 < tiers.size() else -1)
	_refresh_info(id)
	_rebuild_grid()   # 格子 / 队伍栏的小图标跟着闪光开关换
	_refresh_team()


func selected_ditto_target() -> int:
	return 0


func can_depart() -> bool:
	return (_selected == DEFAULT_POKEMON_ID or _caught.has(_selected)) and PokemonStarters.is_ready(_selected)


# 底部一条提示（原版消息框的位置和样式）: 购买结果 / 拒绝原因，3 秒后收起。
var _msg_layer: Control = null
var _msg_token := 0


func show_message(text: String, sticky := false) -> void:
	if _msg_layer == null:
		_msg_layer = Control.new()
		_msg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_c.add_child(_msg_layer)
	for ch in _msg_layer.get_children():
		_msg_layer.remove_child(ch)
		ch.queue_free()
	RogueUI.window(_msg_layer, 4, 146, 276, 32)
	RogueUI.label(_msg_layer, text, 10, 151, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 264, true)
	_msg_token += 1
	var token := _msg_token
	if sticky:
		return   # 一直留着，直到下一条消息或 clear_message()
	get_tree().create_timer(3.5).timeout.connect(func():
		if token == _msg_token and _msg_layer != null:
			for ch in _msg_layer.get_children():
				_msg_layer.remove_child(ch)
				ch.queue_free())


func clear_message() -> void:
	_msg_token += 1
	if _msg_layer != null:
		for ch in _msg_layer.get_children():
			_msg_layer.remove_child(ch)
			ch.queue_free()


# ================= 数据小工具 =================

func _display_name(id: int) -> String:
	if not _name_of.has(id):
		var prof := PokemonStarters.profile(id)
		var nm := str(prof.get("name", ""))
		if nm == "":
			nm = str(Pokedex.entry(id).get("name", "???"))
		_name_of[id] = nm
	return str(_name_of[id])


# 开局最大血量：种族值（融合取平均）+ 开局等级 + 抓到过的最好个体值 + 选的性格（努力值不算）。
func _start_hp(id: int) -> int:
	var bs: Array = (PokemonStarters.profile(id).get("base_stats", []) as Array).duplicate()
	var partner := int(_wallet.fusion_for(id)) if _wallet != null else 0
	if partner > 0:
		bs = Fusion.base_stats(bs, PokemonStarters.profile(partner).get("base_stats", []))
	if bs.size() < 6:
		return 0
	var root := AB.root_of(id)
	var ivs: Array = _wallet.ivs_best.get(root, []) if _wallet != null else []
	var nature: Array = Growth.nature_multipliers(int(_wallet.nature_pick_for(root))) if _wallet != null else []
	return int(Growth.calculate_stats(bs, _start_level(id), ivs, nature)[0])


func _has_group_move(id: int) -> bool:
	for m in _carried_moves(id):
		if bool((PokemonMoves.MOVES.get(str(m), {}) as Dictionary).get("group", false)):
			return true
	return false


func _start_level(id: int) -> int:
	if start_level_provider.is_valid():
		return int(start_level_provider.call(id))
	return 1 + int(_candy.get(id, 0))


func _is_caught(id: int) -> bool:
	return id == DEFAULT_POKEMON_ID or _caught.has(id)


# shiny = -1 普通配色 / 0 金 / 1 蓝 / 2 红（真闪光配色，和出发后的主角一样）。
func _portrait(id: int, shiny := -1) -> Texture2D:
	var cache_key := "%d:%d" % [id, shiny]
	if _portrait_cache.has(cache_key):
		return _portrait_cache[cache_key]
	var tex: Texture2D = null
	var prof := PokemonStarters.profile(id)
	var mode := str(prof.get("sprite", "none")) if not prof.is_empty() else "none"
	if mode == "builtin" or mode == "wild":
		var vis = CaterpieVisual.new()
		if vis != null:
			if mode == "builtin":
				vis.set_species(id, shiny)
			elif _wild_atlas_ready(id):
				vis.set_wild_species(id, 0, shiny)
			tex = vis.portrait_texture()
			vis.free()
	_portrait_cache[cache_key] = tex
	return tex


func _wild_atlas_ready(id: int) -> bool:
	if not WildSpecies.has_species(id):
		return false
	var form := WildSpecies.form_at(id, 0)
	var key := str(form.get("sprite_key", ""))
	return not WildSpecies.atlas_entry(id, key, "front").is_empty() \
		and not WildSpecies.atlas_entry(id, key, "back").is_empty()


# 开局招候选：融合了就把对象的也算上（用户 2026-10-22），和 main/state.gd::_starter_pool 同一口径。
func _starter_pool(id: int) -> Array:
	return TMRules.starter_pool(id, int(_wallet.fusion_for(id)) if _wallet != null else 0)


# 能带的机器：自己买过的 + 融合对象买过的（和 main/state.gd::_owned_tms 同一口径）。
func _owned_tms(id: int) -> Array:
	var out: Array = (_tm_owned.get(id, []) as Array).duplicate()
	if _wallet == null:
		return out
	for m in _wallet.tm_owned_for(id) + _wallet.egg_moves_for(id):
		if not out.has(m):
			out.append(m)
	var partner := int(_wallet.fusion_for(id))
	if partner > 0:
		for m in _wallet.tm_owned_for(partner) + _wallet.egg_moves_for(partner):
			if not out.has(m):
				out.append(m)
	return out


func _carried_moves(id: int) -> Array:
	var owned := _owned_tms(id)
	var equipped: Array = []
	for m in _tm_equipped.get(id, []):
		if owned.has(m):
			equipped.append(m)
	var saved: Array = _wallet.loadout_for(id) if _wallet != null and _wallet.has_method("loadout_for") else []
	return TMRules.resolve_loadout(saved, _starter_pool(id), _tm_bench.get(id, []), owned, equipped, _slots_for(id))


# 招式槽数：4 + 这一系带的招式扩展器（最多 +2）。
func _slots_for(id: int) -> int:
	var n := int(_wallet.held_all(id).get("MOVE_SLOT", 0)) if _wallet != null else 0
	return TMRules.MAX_SLOTS + clampi(n, 0, 2)


func _shown_id() -> int:
	return _hover if _hover > 0 else _selected


# ================= 静态部分 =================

func _build_static() -> void:
	RogueUI.fill(_c, 0, 0, 320, 180, Color("006860"))
	var bg := Atlas.texture("ui/starter_select_bg.png")
	if bg != null:
		RogueUI.image(_c, bg, 0, 0)
	# 右边: 格子窗口 / 队伍窗口 / 开始窗口 / 顶栏
	RogueUI.window(_c, 109, 18, 175, 161)
	var cbg := Atlas.texture("ui/starter_container_bg.png")
	if cbg != null:
		RogueUI.image(_c, cbg, 110, 19)
	RogueUI.window(_c, 285, 18, 34, 132)
	RogueUI.window(_c, 285, 145, 34, 34)
	RogueUI.window(_c, 109, 1, 175, 17)
	# 顶栏六个筛选 / 排序标签（点开是下拉）
	for i in FILTERS.size():
		var lab := RogueUI.label(_c, FILTERS[i], 109 + 175.0 / FILTERS.size() * i, 2, "window", 16, HORIZONTAL_ALIGNMENT_CENTER, 175.0 / FILTERS.size())
		lab.name = "Filter%d" % i
		var hit := _hit_area(Rect2(109 + 175.0 / FILTERS.size() * i, 1, 175.0 / FILTERS.size(), 17))
		hit.gui_input.connect(_on_filter_input.bind(i))
		hit.mouse_entered.connect(func(): lab.add_theme_color_override("font_color", Color("e8e8a8")))
		hit.mouse_exited.connect(func(): lab.add_theme_color_override("font_color", RogueUI.STYLES["window"][1]))
	# 随机 / 商店
	RogueUI.window(_c, 285, 1, 34, 17)
	RogueUI.label(_c, "随机", 285, 2, "window", 16, HORIZONTAL_ALIGNMENT_CENTER, 34)
	_hit_area(Rect2(285, 1, 34, 17)).gui_input.connect(func(e): if _is_left_click(e): _pick_random())
	# 开始
	RogueUI.label(_c, "开始", 285, 160, "tooltip", 16, HORIZONTAL_ALIGNMENT_CENTER, 34)
	_hit_area(Rect2(285, 145, 34, 34)).gui_input.connect(func(e): if _is_left_click(e): _on_start())
	# 左下角小按钮: 商店 / 返回
	var shop := RogueUI.label(_c, "商店", 6, 162, "summary", 16)
	_hit_area(Rect2(6, 162, 40, 16)).gui_input.connect(func(e): if _is_left_click(e): shop_pressed.emit())
	var back := RogueUI.label(_c, "返回", 58, 162, "summary", 16)
	_hit_area(Rect2(58, 162, 40, 16)).gui_input.connect(func(e): if _is_left_click(e): title_pressed.emit())
	# 收集进度（用户 2026-10-20：喜欢收集这一块）：点开看图鉴 / 闪光 / 各地区抓了几成
	RogueUI.label(_c, "收集", 84, 162, "summary_gold", 16)
	_hit_area(Rect2(82, 162, 24, 16)).gui_input.connect(func(e): if _is_left_click(e): _open_collection())
	_grid = Control.new()
	_grid.position = Vector2(110, 19) * RogueUI.K
	_grid.size = Vector2(173, 159) * RogueUI.K
	_grid.clip_contents = true
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.gui_input.connect(_on_grid_input)
	_c.add_child(_grid)
	_info = Control.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.add_child(_info)
	_team = Control.new()
	_team.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.add_child(_team)
	_popup = Control.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.add_child(_popup)


func _hit_area(r: Rect2) -> Control:
	var h := Control.new()
	h.position = r.position * RogueUI.K
	h.size = r.size * RogueUI.K
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	_c.add_child(h)
	return h


func _is_left_click(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


# ================= 刷新 =================

func _refresh_all() -> void:
	_apply_filter()
	_rebuild_grid()
	_refresh_info(_shown_id())
	_refresh_team()


func _apply_filter() -> void:
	_view = []
	for id in _ids:
		var entry := Pokedex.entry(id)
		var gen := int(entry.get("generation", 0))
		if int(_filter["gen"]) > 0 and gen != int(_filter["gen"]):
			continue
		var tname := str(_filter["type"])
		if tname != "":
			var types: Array = PokemonStarters.profile(id).get("types", [])
			if not types.has(tname):
				continue
		match int(_filter["caught"]):
			1:
				if not _is_caught(id):
					continue
			2:
				if _is_caught(id):
					continue
			3:
				if not _shiny.has(id):
					continue
			4:
				if int(_wins.get(id, 0)) <= 0:
					continue
			5:
				if not _favorites.has(id):
					continue
		var lf := int(_filter.get("legend", 0))
		if lf == 4 and legend_class(id) != 0:
			continue
		if lf > 0 and lf < 4 and legend_class(id) != lf:
			continue
		if lf == 5 and legend_class(id) == 0:
			continue
		match int(_filter["unlock"]):
			1:
				if int(_candy.get(id, 0)) <= 0:
					continue
			2:
				if int(_candy.get(id, 0)) > 0:
					continue
		_view.append(id)
	match int(_filter["sort"]):
		1:
			_view.sort_custom(func(a, b): return _display_name(a) < _display_name(b))
		2:
			_view.sort_custom(func(a, b): return _start_level(a) > _start_level(b) or (_start_level(a) == _start_level(b) and a < b))
		3:
			_view.sort_custom(func(a, b): return (1 if _is_caught(a) else 0) > (1 if _is_caught(b) else 0) or ((1 if _is_caught(a) else 0) == (1 if _is_caught(b) else 0) and a < b))
	var max_scroll := maxi(0, ceili(float(_view.size()) / GRID_COLS) - GRID_VISIBLE_ROWS)
	_scroll = clampi(_scroll, 0, max_scroll)


func _cell_pos(index: int) -> Vector2:
	return Vector2((index % GRID_COLS) * 18.0, 13.0 + (floorf(float(index) / GRID_COLS) - _scroll) * GRID_ROW_H)


func _rebuild_grid() -> void:
	for ch in _grid.get_children():
		_grid.remove_child(ch)
		ch.queue_free()
	var origin := Vector2(GRID_X - 110.0, GRID_Y - 19.0)   # 相对格子窗口内侧
	for i in _view.size():
		var row := int(floorf(float(i) / GRID_COLS)) - _scroll
		if row < -1 or row > GRID_VISIBLE_ROWS:
			continue
		var id := _view[i]
		var cell := Control.new()
		var p := origin + _cell_pos(i)
		cell.position = p * RogueUI.K
		cell.size = Vector2(18, 17) * RogueUI.K
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_entered.connect(_on_cell_hover.bind(id))
		cell.mouse_exited.connect(_on_cell_exit.bind(id))
		cell.gui_input.connect(_on_cell_input.bind(id))
		_grid.add_child(cell)
		_fill_cell(cell, id)


# 一个格子里的东西（原版 StarterContainer）: 图标 / 左上开局等级 / 右上闪光星 / 圆底 / 徽章 / 糖果。
func _fill_cell(cell: Control, id: int) -> void:
	var caught := _is_caught(id)
	# 原版格子里的圆底（passive_bg）是“被动特性已解锁”的标记，不是“已捕获”。
	if caught and _passive_unlocked.has(AB.root_of(id)):
		var pbg := Atlas.texture("ui/passive_bg.png")
		if pbg != null:
			RogueUI.image(cell, pbg, 1, 0.5)
	var icon := RogueUI.species_icon(id, _start_shiny_tier(id) >= 0)   # 闪光开着（含融合借来的）就用闪光小图标（用户 2026-10-23）
	var ir := RogueUI.fit_icon(cell, icon, 9.0, 8.5, 16.0, 15.0)
	if not caught:
		ir.modulate = Color(0, 0, 0, 1)
	if caught:
		var lv := _start_level(id)
		var n := RogueUI.label(cell, str(lv), 1, 2, "window", 16)
		if int(_candy.get(id, 0)) > 0:
			n.add_theme_color_override("font_color", Color("40c8f8"))
		if _shiny.has(id):
			var star := Atlas.texture("ui/shiny_small.png")
			if star != null:
				RogueUI.image(cell, star, 12, 2, 0.5)
		if _favorites.has(id):
			var fav := Atlas.texture("ui/favorite.png")
			if fav != null:
				RogueUI.image(cell, fav, 0, 6)
		if SHOW_WINS and int(_wins.get(id, 0)) > 0:
			var rib := Atlas.texture("ui/champion_ribbon.png")
			if rib != null:
				RogueUI.image(cell, rib, 0, 12, 0.5)
		if int(_candy.get(id, 0)) > 0:
			var cd := Atlas.texture("ui/candy.png")
			if cd != null:
				RogueUI.image(cell, cd, 12, 12, 0.25)
		if _wallet != null and int(_wallet.fusion_for(id)) > 0:
			# 融合了：右边中间挂原版“基因之楔”小图标（用户 2026-10-22：融合要标识出来）
			var dna := Atlas.frame("icons/items", "dna_splicers")
			if dna != null:
				_outlined_image(cell, dna, 10.5, 4.5, 0.25)   # 只描边不垫底（用户 2026-10-22）
	if id == _selected:
		var cur := Atlas.texture("ui/select_cursor_highlight.png")
		if cur != null:
			RogueUI.image(cell, cur, -1, 1)


func _on_cell_hover(id: int) -> void:
	_hover = id
	_refresh_info(id)


func _on_cell_exit(id: int) -> void:
	if _hover == id:
		_hover = 0
		_refresh_info(_selected)


func _on_cell_input(e: InputEvent, id: int) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	if _fusing_for > 0 and e.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_fusion_pick()
		return
	if _breeding_for > 0 and e.button_index == MOUSE_BUTTON_RIGHT:
		_breeding_for = 0
		clear_message()
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		if _fusion_pick_click(id):
			return
		if _breed_pick_click(id):
			return
		_select(id)
	elif e.button_index == MOUSE_BUTTON_RIGHT:
		_select(id)
		_open_menu(id)
	elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_by(-1)
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_by(1)


func _on_grid_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(1)


func _scroll_by(d: int) -> void:
	var max_scroll := maxi(0, ceili(float(_view.size()) / GRID_COLS) - GRID_VISIBLE_ROWS)
	var ns := clampi(_scroll + d, 0, max_scroll)
	if ns != _scroll:
		_scroll = ns
		_rebuild_grid()


func _select(id: int) -> void:
	_selected = id
	_entry_level = 0
	_rebuild_grid()
	_refresh_info(id)
	_refresh_team()


func _pick_random() -> void:
	var pool: Array = []
	for id in _view:
		if _is_caught(id):
			pool.append(id)
	if pool.is_empty():
		return
	_select(int(pool[randi() % pool.size()]))


# ================= 左边信息（原版 starter-select 的左半）=================

func _refresh_info(id: int) -> void:
	for ch in _info.get_children():
		_info.remove_child(ch)
		ch.queue_free()
	if id <= 0:
		return
	var caught := _is_caught(id)
	var page := _info_page if caught else 0
	RogueUI.label(_info, "%04d" % id, 24, 2, "summary", 24)
	var tex := _portrait(id, _start_shiny_tier(id) if caught else -1)
	if tex != null and page == 0:
		var sp := RogueUI.image(_info, tex, 53.0 - tex.get_width() * 0.5, 63.0 - tex.get_height() * 0.5)
		if not caught:
			sp.modulate = Color(0, 0, 0, 1)
	if page == 0:   # 翻到“能力 / 详情”页时不画，免得和图 / 文字叠在一起
		# 糖果数
		var cd := Atlas.texture("ui/candy.png")
		if cd != null:
			RogueUI.image(_info, cd, 4.5, 18, 0.5)
		var co := Atlas.texture("ui/candy_overlay.png")
		if co != null:
			RogueUI.image(_info, co, 4.5, 18, 0.5)
		# 原版这里是物种糖果（抓到 / 好感满给，攒着解锁被动）；神奇糖果体现在开局等级上
		RogueUI.label(_info, "x%d" % int(_sp_candy.get(AB.root_of(id), 0)), 14, 18, "window", 16)
		# 抓到 / 闪光 / 通关
		var pb := Atlas.frame("icons/items", "pb")
		if pb != null:
			RogueUI.image(_info, pb, 3, 25, 0.375)
		RogueUI.label(_info, "已捕获" if caught else "未捕获", 13, 25, "summary_gray" if not caught else "window", 16)
		var wins := int(_wins.get(id, 0))
		if caught:
			if _shiny_ok(id):
				var sh := Atlas.texture("ui/shiny_small.png")
				if sh != null:
					RogueUI.image(_info, sh, 4, 33, 0.5)
				# 闪光开局开关（S 键或点这一行轮换档位）：开了大图和出发后都用真闪光配色，最大血量小幅加成（金 +10% / 蓝 +15% / 红 +20%）
				# 一行写完（以前“红闪 闪光开局：开”两段太长，被右边招式栏挡住）
				var on_tier := _shiny_tier_on(id)
				var tier_name: String = ["闪光", "蓝闪", "红闪"][maxi(on_tier, 0)]
				RogueUI.label(_info, ("%s：开" % tier_name) if on_tier >= 0 else "闪光：关", 13, 33, "summary_red" if on_tier >= 0 else "summary_gray", 16)
				var hit := Control.new()
				hit.position = Vector2(3, 32) * RogueUI.K
				hit.size = Vector2(48, 9) * RogueUI.K
				hit.mouse_filter = Control.MOUSE_FILTER_STOP
				_info.add_child(hit)
				hit.gui_input.connect(func(e): if _is_left_click(e): _toggle_shiny(id))
			elif _fusion_shiny_tier(id) >= 0:
				# 自己没闪光、融合对象是闪光：这一局借来的闪光（不能开关、不解锁）
				var sh2 := Atlas.texture("ui/shiny_small.png")
				if sh2 != null:
					RogueUI.image(_info, sh2, 4, 33, 0.5)
				RogueUI.label(_info, "融合%s" % ["闪光", "蓝闪", "红闪"][_fusion_shiny_tier(id)], 13, 33, "summary_red", 16)
			if SHOW_WINS and wins > 0:
				var rb := Atlas.texture("ui/champion_ribbon.png")
				if rb != null:
					RogueUI.image(_info, rb, 3, 41, 0.5)
				RogueUI.label(_info, "通关 %d 次" % wins, 13, 41, "window", 16)
	var prof := PokemonStarters.profile(id)
	if page == 0:
		var types: Array = prof.get("types", [])
		for i in mini(2, types.size()):
			var ti := RogueUI.type_icon(str(types[i]))
			if ti != null:
				RogueUI.image(_info, ti, 8.0 + 18.0 * i, 91, 0.5)
		RogueUI.label(_info, "成长速度: ", 8, 99, "small_alt", 16)
		RogueUI.label(_info, str(GROWTH_ZH.get(int(prof.get("growth_rate", 2)), "较快")), 40, 99, "summary_blue", 16)
	var fuse_partner := int(_wallet.fusion_for(id)) if _wallet != null and caught else 0
	var shown_name := _display_name(id)
	if fuse_partner > 0:
		shown_name = Fusion.name_of(_display_name(id), _display_name(fuse_partner))   # 融合后的名字
	if fuse_partner > 0 and page == 0:
		# 大图左边：基因之楔 + 融合对象的小头像
		var dna := Atlas.frame("icons/items", "dna_splicers")
		if dna != null:
			_outlined_image(_info, dna, 3, 49, 0.3)
		var pic := RogueUI.species_icon(fuse_partner, false)
		if pic != null:
			RogueUI.fit_icon(_info, pic, 14.0, 66.0, 18.0, 17.0)
	RogueUI.label(_info, str(_nicks.get(id, "")) if str(_nicks.get(id, "")) != "" else shown_name, 6, 111, "summary", 24)   # 起了名字就显示名字
	if caught:
		_page_buttons(id)
	if page == 1:
		_info_page_stats(id, prof, fuse_partner)
		return
	# 下面白框里: 开局等级 / 特性 / 性格（特性还没做，如实写未开放）
	RogueUI.label(_info, "开局等级: ", 6, 127, "summary_alt", 16)
	RogueUI.label(_info, "Lv.%d" % _start_level(id), 44, 127, "summary_alt", 16)

	_nature_row(id, caught)
	RogueUI.label(_info, "特性: ", 6, 136, "summary_alt", 16)
	_ability_row(id, caught)
	# 性格还没做（一直是“坦率”占位），这一行先给被动用（白框只放得下三行）
	RogueUI.label(_info, "被动: ", 6, 145, "summary_alt", 16)
	_passive_row(id, caught)
	# 招式条（开局招 + 带着的机器）
	var moves := _carried_moves(id) if caught else []
	for m in 4:
		var y := 16.0 + 8.5 * m
		var bar := _move_bar(_info, 56, y, 46, 8.0)
		var text := "-"
		var tname := ""
		if not caught:
			text = "???"
		elif m < moves.size():
			var mv: Dictionary = PokemonMoves.MOVES.get(str(moves[m]), {})
			text = str(mv.get("name", str(moves[m])))
			tname = str(mv.get("type", ""))
		_set_bar_type(bar, tname)
		var lab := RogueUI.label(_info, text, 56, y - 0.5, "party", 16, HORIZONTAL_ALIGNMENT_CENTER, 46)
		lab.add_theme_constant_override("shadow_offset_y", 1)
	var extra := maxi(0, moves.size() - 4)
	if extra > 0:
		RogueUI.label(_info, "(+%d)" % extra, 56, 51, "party", 16, HORIZONTAL_ALIGNMENT_CENTER, 46)


# ◁ 1/3 ▷：名字那一行右边（原来“血 / 群攻”的位置）。
func _page_buttons(id: int) -> void:
	HD.label(_info, "◀", 59, 99.5, 14, HD.BLUE)
	HD.label(_info, "%s %d/%d" % [INFO_PAGES[_info_page], _info_page + 1, INFO_PAGES.size()], 65, 100.5, 11, HD.DARK, 26, false, HORIZONTAL_ALIGNMENT_CENTER)
	HD.label(_info, "▶", 92, 99.5, 14, HD.BLUE)
	for spec in [[57, -1], [90, 1]]:
		var hit := Control.new()
		hit.position = Vector2(float(spec[0]), 98.0) * RogueUI.K
		hit.size = Vector2(9, 10) * RogueUI.K
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_info.add_child(hit)
		var step := int(spec[1])
		hit.gui_input.connect(func(e): if _is_left_click(e): _flip_info_page(id, step))


func _flip_info_page(id: int, step: int) -> void:
	_info_page = posmod(_info_page + step, INFO_PAGES.size())
	_refresh_info(id)


# 第 2 页：六边形图（蓝 = 种族值，金 = 个体值）+ 白框里写合计和不同等级的血量（能比出谁肉）。
func _info_page_stats(id: int, prof: Dictionary, partner: int) -> void:
	var bs: Array = (prof.get("base_stats", []) as Array).duplicate()
	if partner > 0:
		bs = Fusion.base_stats(bs, PokemonStarters.profile(partner).get("base_stats", []))
	var root := AB.root_of(id)
	var ivs: Array = (_wallet.ivs_best.get(root, [0, 0, 0, 0, 0, 0]) as Array) if _wallet != null else [0, 0, 0, 0, 0, 0]
	var radar := StatRadarDual.new()
	radar.base = bs
	radar.ivs = ivs
	radar.position = Vector2(8, 21) * RogueUI.K   # 四周留边（用户 2026-10-24：太贴边）
	radar.size = Vector2(90, 66) * RogueUI.K
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(radar)
	var base_sum := 0
	var iv_sum := 0
	for i in mini(6, bs.size()):
		base_sum += int(bs[i])
	for i in mini(6, ivs.size()):
		iv_sum += int(ivs[i])
	var nature: Array = Growth.nature_multipliers(int(_wallet.nature_pick_for(root))) if _wallet != null else []
	var lv := _start_level(id)
	var hp_at := func(level: int) -> int: return int(Growth.calculate_stats(bs, level, ivs, nature)[0]) if bs.size() >= 6 else 0
	HD.label(_info, "■ 种族值 %d" % base_sum, 9, 127, 11, HD.BLUE)
	HD.label(_info, "■ 个体值 %d/186" % iv_sum, 52, 127, 11, HD.GOLD)
	HD.label(_info, "最大血量　开局 Lv%d：%d" % [lv, hp_at.call(lv)], 9, 136, 11, HD.DARK)
	HD.label(_info, "Lv20：%d　Lv50：%d" % [hp_at.call(20), hp_at.call(50)], 9, 145, 11, HD.DARK)


# 起始页上能选的特性栏位（特性2 / 隐藏为空的不列；隐藏栏要抓到过隐藏特性才开放）。
# 特性看谁：融合了就是融合对象（原版融合特性取对象的，用户 2026-10-22：“特性我想要细胞的第二个”），否则就是自己。
# 栏位也记在对象那一系名下，主宠自己不融合时选的栏位不受影响。
func _ability_subject(id: int) -> int:
	var partner := int(_wallet.fusion_for(id)) if _wallet != null else 0
	return partner if partner > 0 else id


func _ability_choices(id: int) -> Array:
	var out: Array = []
	id = _ability_subject(id)
	var root := AB.root_of(id)
	for c: Dictionary in AB.slot_choices(id):
		if bool(c["hidden"]) and not _ab_hidden.has(root):
			continue
		out.append(c)
	return out


func ability_slot_of(id: int) -> int:
	var root := AB.root_of(_ability_subject(id))
	var want := int(_ab_slots.get(root, 0))
	for c: Dictionary in _ability_choices(id):
		if int(c["slot"]) == want:
			return want
	var first := _ability_choices(id)
	return int(first[0]["slot"]) if not first.is_empty() else 0


func _ability_row(id: int, caught: bool) -> void:
	var choices := _ability_choices(id)
	if choices.is_empty():
		RogueUI.label(_info, "无", 31, 136, "summary_gray", 16)
		return
	if not caught:
		RogueUI.label(_info, "???", 31, 136, "summary_gray", 16)
		return
	var slot := ability_slot_of(id)
	var key := AB.slot_ability(_ability_subject(id), slot)
	var style := "summary_gold" if slot == 2 else "summary_alt"
	if not AB.is_active(key):
		style = "summary_gray"
	var lab := RogueUI.label(_info, AB.name_of(key), 31, 136, style, 16)
	if choices.size() > 1:
		RogueUI.label(_info, "[E]", 31.0 + 6.0 * AB.name_of(key).length() + 3.0, 136, "small_alt", 16)
	var hit := Control.new()
	hit.position = Vector2(6, 135) * RogueUI.K
	hit.size = Vector2(100, 9) * RogueUI.K
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.add_child(hit)
	hit.gui_input.connect(func(e): if _is_left_click(e): _cycle_ability(id))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 性格（白框第一行右边）：抓到过的性格里选，点一下或按 N 换下一个；悬停看加减哪项。没抓到的宠物不显示。
func _nature_row(id: int, caught: bool) -> void:
	if not caught:
		return
	var root := AB.root_of(id)
	var cur := int(_nature_pick.get(root, 0))
	var count := (_natures.get(root, [0]) as Array).size()
	var lab := RogueUI.label(_info, "性格:" + Growth.nature_name(cur), 66, 127, "summary_blue" if count > 1 else "summary_alt", 16)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Control.new()
	hit.position = Vector2(64, 126) * RogueUI.K
	hit.size = Vector2(40, 9) * RogueUI.K
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	# 不用悬停提示：会压在底部消息框上，和点了以后的消息叠在一起（用户 2026-10-24“有点乱”）。点一下的消息里写全
	_info.add_child(hit)
	hit.gui_input.connect(func(e): if _is_left_click(e): _cycle_nature(id))


func _cycle_nature(id: int) -> void:
	if not _is_caught(id):
		return
	var root := AB.root_of(id)
	var lst: Array = _natures.get(root, [0])
	if lst.size() <= 1:
		show_message("这一系只抓到过「%s」性格；抓到别的性格就能换" % Growth.nature_label(int(_nature_pick.get(root, 0))))
		return
	var i := lst.find(int(_nature_pick.get(root, 0)))
	var nxt := int(lst[(i + 1) % lst.size()])
	_nature_pick[root] = nxt
	nature_requested.emit(root, nxt)
	_refresh_info(id)


# 被动那一行：没解锁写“N 糖果解锁”（够了金色可点），解锁了写名字 + 开 / 关（点一下或按 P 切）。
func _passive_row(id: int, caught: bool) -> void:
	var key := AB.passive_of(id)
	if key == "" or key == AB.NONE:
		RogueUI.label(_info, "无", 31, 145, "summary_gray", 16)
		return
	if not caught:
		RogueUI.label(_info, "???", 31, 145, "summary_gray", 16)
		return
	var root := AB.root_of(id)
	var nm := AB.name_of(key)
	var text := nm
	var style := "summary_alt"
	if not _passive_unlocked.has(root):
		var cost := SpeciesCandy.passive_cost(root)
		var have := int(_sp_candy.get(root, 0))
		text = nm   # 锁着灰色、糖果够了金色；糖果进度在“详情”页（用户 2026-10-24：长了冒出白框）
		style = "summary_gold" if have >= cost else "summary_gray"
	elif _passive_off.has(root):
		text = nm + "（关）"
		style = "summary_gray"
	else:
		text = nm + "（开）[P]"
	RogueUI.label(_info, text, 31, 145, style, 16)
	var hit := Control.new()
	hit.position = Vector2(6, 144) * RogueUI.K
	hit.size = Vector2(100, 9) * RogueUI.K
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_info.add_child(hit)
	hit.gui_input.connect(func(e): if _is_left_click(e): _passive_action(id))


func _passive_action(id: int) -> void:
	if not _is_caught(id):
		return
	var key := AB.passive_of(id)
	if key == "" or key == AB.NONE:
		return
	var root := AB.root_of(id)
	passive_requested.emit(root, "toggle" if _passive_unlocked.has(root) else "unlock")


func _cycle_ability(id: int) -> void:
	if not _is_caught(id):
		return
	var choices := _ability_choices(id)
	var cur := ability_slot_of(id)
	var next := int(choices[0]["slot"]) if not choices.is_empty() else 0
	for i in choices.size():
		if int(choices[i]["slot"]) == cur:
			next = int(choices[(i + 1) % choices.size()]["slot"])
	var root := AB.root_of(_ability_subject(id))
	if choices.size() <= 1:
		var k := AB.slot_ability(_ability_subject(id), cur)
		if k != "":
			show_message(AB.summary(k))
		return
	_ab_slots[root] = next
	_refresh_info(id)
	ability_slot_requested.emit(root, next)


func _move_bar(parent: Node, x: float, y: float, w: float, h: float) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.patch_margin_left = 2
	n.patch_margin_right = 2
	n.patch_margin_top = 2
	n.patch_margin_bottom = 2
	n.position = Vector2(x, y) * RogueUI.K
	n.size = Vector2(w, h) * RogueUI.K
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(n)
	return n


func _set_bar_type(bar: NinePatchRect, zh_type: String) -> void:
	var key := str(RogueUI.TYPE_EN.get(zh_type, "unknown")) if zh_type != "" else "unknown"
	var fr := Atlas.frame("ui/type_bgs", key)
	if fr == null:
		fr = Atlas.frame("ui/type_bgs", "unknown")
	if fr != null:
		bar.texture = fr.atlas
		bar.region_rect = fr.region


# ================= 右边队伍栏 =================

func _refresh_team() -> void:
	for ch in _team.get_children():
		_team.remove_child(ch)
		ch.queue_free()
	# 本作一局只带一只: 第一格是选中的首发，后面是问号
	# 选中的这只本作不能出发（没抓到 / 本作没接）时不摆进队伍栏：第一格也是问号，右下角写 0/1（用户 2026-10-18：“这个不能选的不应该出现”）
	var ready := can_depart()
	var icon: AtlasTexture = RogueUI.species_icon(_selected, _start_shiny_tier(_selected) >= 0) if ready else Atlas.frame("icons/pokemon_icons_0", "unknown")
	RogueUI.fit_icon(_team, icon, 302, 29, 20.0, 18.0, 1.0 if ready else 0.5)
	var unknown := Atlas.frame("icons/pokemon_icons_0", "unknown")
	for i in range(1, 6):
		if unknown != null:
			RogueUI.fit_icon(_team, unknown, 302, 29 + 21.0 * i, 20.0, 18.0, 0.5)
	RogueUI.label(_team, "1/1" if ready else "0/1", 285, 149, "tooltip", 16, HORIZONTAL_ALIGNMENT_CENTER, 34)


func _on_start() -> void:
	if not can_depart():
		if _caught.has(_selected):
			show_message(_display_name(_selected) + "：" + PokemonStarters.not_ready_reason(_selected))   # 抓到了却不能出发：说清为什么
		return
	_open_depart_menu()


# ================= 顶栏下拉 =================

func _on_filter_input(e: InputEvent, index: int) -> void:
	if not _is_left_click(e):
		return
	_close_popup()
	var opts: Array = []   # [标签, 值]
	var key := ""
	match index:
		0:
			key = "gen"
			opts.append(["全部", 0])
			for g in range(1, 10):
				opts.append(["第%d代" % g, g])
		1:
			key = "type"
			opts.append(["全部", ""])
			for t in TYPES_ZH:
				opts.append([t, t])
		2:
			key = "caught"
			opts = [["全部", 0], ["已捕获", 1], ["未捕获", 2], ["闪光", 3], ["通关过", 4], ["最爱", 5]] if SHOW_WINS else [["全部", 0], ["已捕获", 1], ["未捕获", 2], ["闪光", 3], ["最爱", 5]]
		3:
			key = "unlock"
			opts = [["全部", 0], ["有糖果加成", 1], ["没有", 2]]
		4:
			key = "legend"
			opts = [["全部", 0], ["所有神兽", 5], ["传说", 1], ["幻之", 2], ["准神兽", 3], ["普通", 4]]
		5:
			key = "sort"
			opts = [["编号", 0], ["名称", 1], ["开局等级", 2], ["已捕获优先", 3]]
	var x := 109.0 + 175.0 / FILTERS.size() * index
	_open_list(x, 18, 56, opts, func(v) -> void:
		if key != "" and int(v if v is int else 0) != -1:
			_filter[key] = v
			_scroll = 0
			_apply_filter()
			_rebuild_grid()
			_refresh_info(_shown_id()))


# ================= 弹出菜单 =================

func _close_popup() -> void:
	for ch in _popup.get_children():
		_popup.remove_child(ch)
		ch.queue_free()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE


# 点空白处关闭的遮罩（透明）。
func _popup_shield() -> void:
	_close_popup()
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Control.new()
	sh.size = RogueUI.DESIGN
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	# 只有左 / 右键点空白处才关；滚轮不算（用户 2026-10-24：收集进度一滚滚轮就关了）
	sh.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _close_popup())
	_popup.add_child(sh)


# 通用选项窗口: opts = [[标签, 值, 可选: 是否灰（true = 不可点）]]，点了调 cb(值)。行高 12 原版像素。
func _open_list(x: float, y: float, w: float, opts: Array, cb: Callable, row_h := 12.0, style := "window") -> void:
	_popup_shield()
	var h := row_h * opts.size() + 8.0
	var win := RogueUI.window(_popup, x, y, w, h, "", 1)
	for i in opts.size():
		var row_y := y + 4.0 + row_h * i
		var disabled: bool = opts[i].size() > 2 and bool(opts[i][2])
		var lab := RogueUI.label(_popup, str(opts[i][0]), x + 8, row_y, "summary_gray" if disabled else style, 16, HORIZONTAL_ALIGNMENT_LEFT, w - 10)
		var hit := Control.new()
		hit.position = Vector2(x + 2, row_y) * RogueUI.K
		hit.size = Vector2(w - 4, row_h) * RogueUI.K
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(hit)
		if disabled:
			continue
		var cur := Atlas.texture("ui/cursor.png")
		var arrow: TextureRect = null
		if cur != null:
			arrow = RogueUI.image(_popup, cur, x + 2, row_y + 2, 0.5)
			arrow.visible = false
		hit.mouse_entered.connect(func():
			lab.add_theme_color_override("font_color", Color("e8e8a8"))
			if arrow != null:
				arrow.visible = true)
		hit.mouse_exited.connect(func():
			lab.add_theme_color_override("font_color", RogueUI.STYLES[style][1])
			if arrow != null:
				arrow.visible = false)
		var value = opts[i][1]
		hit.gui_input.connect(func(e):
			if _is_left_click(e):
				_close_popup()
				cb.call(value))


func _open_menu(id: int) -> void:
	var caught := _is_caught(id)
	var opts := [
		["选为首发", "pick", not can_depart()],
		["显示个体", "iv", not caught],
		["管理招式", "moves", not caught],
		["学招计划", "plan", not caught],
		["换性格（N）", "nature", not caught],
		[_passive_menu_text(id), "passive", not caught or AB.passive_of(id) in ["", AB.NONE]],
		["取消最爱" if _favorites.has(id) else "添加到最爱", "fav", not caught],
		["起名", "nick", not caught],
		[_fusion_menu_text(id), "fusion", not caught or id == PokemonStarters.DITTO_ID],
		["取消融合", "unfuse", _wallet == null or int(_wallet.fusion_for(id)) <= 0],
		["生蛋（蛋糕 %d）" % (_wallet.cakes if _wallet != null else 0), "breed", not caught or _wallet == null or _wallet.cakes <= 0 or _wallet.eggs.size() >= Eggs.MAX_EGGS or not Eggs.can_breed(id)],
		["看蛋（%d/%d）" % [_wallet.eggs.size() if _wallet != null else 0, Eggs.MAX_EGGS], "eggs", _wallet == null or (_wallet.eggs.is_empty() and _wallet.hatch_log.is_empty())],
		["宝可梦图鉴", "dex", false],
		["使用糖果", "candy", not caught],
		["取消", "cancel"],
	]
	_open_list(213, 4, 104, opts, _on_menu_pick.bind(id), 16.0)


func _on_menu_pick(v, id: int) -> void:
	match str(v):
		"pick":
			_select(id)
		"moves":
			_open_moves(id)
		"plan":
			_moves_page = 0
			_open_plan(id)
		"candy":
			_open_candy(id)
		"passive":
			_passive_action(id)
		"nature":
			_cycle_nature(id)
		"iv":
			_open_ivs(id)
		"fav":
			var on := not _favorites.has(id)
			if on:
				_favorites[id] = true
			else:
				_favorites.erase(id)
			favorite_requested.emit(id, on)
			_rebuild_grid()
		"nick":
			_open_nickname(id)
		"fusion":
			_begin_fusion_pick(id)
		"unfuse":
			fusion_requested.emit(id, 0)
		"breed":
			_breeding_for = id
			show_message("生蛋：在格子里点第二只亲代（抓到过、不是神兽）；孵出来是「%s」这一系最前面那只 · 右键或 Esc 取消" % _display_name(id), true)
		"eggs":
			_open_eggs()
		"dex":
			_open_dex(id)


# ================= 融合（用户 2026-10-20；规则 game/pokemon_fusion.gd） =================
# 选对象就在选宠页的格子里点（用户 2026-10-21：“可以回到第一个界面融合”，不另开列表）：
# 菜单点“融合” → 进入选对象状态（底下提示一直留着）→ 左键点一只抓到过的就定，主宠仍是原来那只；
# 右键 / Esc 取消。已经融合的，菜单里“取消融合”。
var _fusing_for := 0   # 正在给这只选融合对象（0 = 没在选）
var _breeding_for := 0  # 正在给这只选生蛋的第二只亲代（0 = 没在选）


# 生蛋选第二只亲代：点格子；返回 true 表示这次点击被用掉了。
func _breed_pick_click(id: int) -> bool:
	if _breeding_for <= 0:
		return false
	var a := _breeding_for
	if not _caught.has(id):
		show_message("「%s」还没抓到过，选一只抓到过的（右键或 Esc 取消）" % _display_name(id), true)
		return true
	if not Eggs.can_breed(id):
		show_message("神兽 / 幻之 / 准神兽不能生蛋，换一只（右键或 Esc 取消）", true)
		return true
	_breeding_for = 0
	clear_message()
	breed_requested.emit(a, id)
	_select(a)
	return true


# 看蛋：每颗蛋孵出来是谁、还差多少击杀（不剧透闪光）；下面是最近孵出的几只各给了什么。
func _open_eggs() -> void:
	var opts: Array = []
	if _wallet != null:
		for e: Dictionary in _wallet.eggs:
			opts.append(["%s的蛋 · 击杀 %d/%d" % [_display_name(int(e["species"])), int(e.get("done", 0)), int(e["need"])], "info", true])
	opts.append(["每打死一只怪，所有蛋都 +1；蛋糕局里打怪掉", "info", true])
	# 孵化记录（用户 2026-10-24）：最近孵出的几只，各给了什么
	if _wallet != null and not _wallet.hatch_log.is_empty():
		opts.append(["—— 最近孵出 ——", "info", true])
		for h: Dictionary in _wallet.hatch_log.slice(0, 4):
			var head := _display_name(int(h["species"]))
			if bool(h.get("new_species", false)):
				head += " · 新物种！"
			if int(h.get("shiny", -1)) >= 0:
				head += " · %s闪光" % ["金", "蓝", "红"][clampi(int(h["shiny"]), 0, 2)]
			opts.append([head, "info", true])
			var parts: Array = []
			var up: Array = h.get("iv_up", [])
			parts.append(("个体值↑ " + "、".join(up)) if not up.is_empty() else "个体值没变高")
			parts.append("性格 %s%s" % [Growth.nature_label(int(h.get("nature", 0))), "（新）" if bool(h.get("nature_new", false)) else ""])
			opts.append(["  " + " · ".join(parts), "info", true])
			var extra: Array = []
			if bool(h.get("hidden_new", false)):
				extra.append("解锁隐藏特性")
			if str(h.get("move", "")) != "":
				var mid := str(h["move"])
				extra.append("遗传招 %s%s" % [str(PokemonMoves.MOVES[mid]["name"]) if PokemonMoves.MOVES.has(mid) else mid, "（新）" if bool(h.get("move_new", false)) else ""])
			if not extra.is_empty():
				opts.append(["  " + " · ".join(extra), "info", true])
	opts.append(["关闭", "cancel"])
	_open_list(110, 8, 210, opts, func(_v): pass, 12.0)


func _fusion_menu_text(id: int) -> String:
	var f := int(_wallet.fusion_for(id)) if _wallet != null else 0
	return "融合：%s" % _display_name(f) if f > 0 else "融合"


func _begin_fusion_pick(id: int) -> void:
	_fusing_for = id
	show_message("选融合对象：在格子里点一只抓到过的（不能选「%s」自己）· 右键或 Esc 取消" % _display_name(id), true)


func _cancel_fusion_pick() -> void:
	if _fusing_for <= 0:
		return
	var main_id := _fusing_for
	_fusing_for = 0
	clear_message()
	_select(main_id)


# 选对象状态下点格子：抓到过、不是自己就定下来；返回 true 表示这次点击被选对象用掉了。
func _fusion_pick_click(id: int) -> bool:
	if _fusing_for <= 0:
		return false
	var main_id := _fusing_for
	if id == main_id:
		show_message("不能和自己融合，换一只（右键或 Esc 取消）", true)
		return true
	if not _caught.has(id):
		show_message("「%s」还没抓到过，选一只抓到过的（右键或 Esc 取消）" % _display_name(id), true)
		return true
	_fusing_for = 0
	clear_message()
	fusion_requested.emit(main_id, id)
	_select(main_id)
	return true


# ================= 显示个体 / 起名 / 图鉴（原版选宠页菜单那几项） =================
const IV_STAT_NAMES := ["HP", "攻击", "防御", "特攻", "特防", "速度"]


# 个体值：这一系抓到过的每项最高值（0–31），开局按它算六维。
func _open_ivs(id: int) -> void:
	_popup_shield()
	var root := AB.root_of(id)
	var ivs: Array = _ivs.get(root, [0, 0, 0, 0, 0, 0])
	RogueUI.window(_popup, 120, 30, 150, 104)
	RogueUI.label(_popup, "个体值（%s 这一系抓到过的最好值）" % _display_name(root), 126, 34, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 140)
	for i in 6:
		var y := 46.0 + 11.0 * i
		var v := int(ivs[i])
		RogueUI.label(_popup, IV_STAT_NAMES[i], 128, y, "window", 16)
		RogueUI.fill(_popup, 156, y + 2, 80, 5, Color("404040"))
		RogueUI.fill(_popup, 156, y + 2, 80.0 * v / 31.0, 5, Color("f8c020") if v == 31 else Color("40c8f8"))
		RogueUI.label(_popup, str(v), 240, y, "summary_gold" if v == 31 else "window", 16)
	RogueUI.label(_popup, "抓到个体值更高的同系宝可梦就会更新", 126, 116, "summary_gray", 16, HORIZONTAL_ALIGNMENT_LEFT, 140)


# 起名：最多 12 个字；空着点确定 = 去掉名字。
func _open_nickname(id: int) -> void:
	_popup_shield()
	RogueUI.window(_popup, 90, 50, 150, 60)
	RogueUI.label(_popup, "给「%s」起名（最多 12 个字）" % str(PokemonStarters.profile(id).get("name", _display_name(id))), 96, 54, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 140)
	var edit := LineEdit.new()
	edit.position = Vector2(96, 66) * RogueUI.K
	edit.size = Vector2(138, 14) * RogueUI.K
	edit.max_length = 12
	edit.text = str(_nicks.get(id, ""))
	edit.add_theme_font_override("font", RogueUI.font())
	edit.add_theme_font_size_override("font_size", 16)
	_popup.add_child(edit)
	edit.grab_focus.call_deferred()
	var commit := func(_t := ""):
		var n := edit.text.strip_edges().left(12)
		if n == "":
			_nicks.erase(id)
		else:
			_nicks[id] = n
		nickname_requested.emit(id, n)
		_close_popup()
		_refresh_info(id)
	edit.text_submitted.connect(commit)
	RogueUI.label(_popup, "确定（回车）", 96, 94, "summary_gold", 16)
	var ok_hit := Control.new()
	ok_hit.position = Vector2(96, 93) * RogueUI.K
	ok_hit.size = Vector2(60, 10) * RogueUI.K
	ok_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(ok_hit)
	ok_hit.gui_input.connect(func(e): if _is_left_click(e): commit.call())
	RogueUI.label(_popup, "取消", 200, 94, "window", 16)
	var cancel_hit := Control.new()
	cancel_hit.position = Vector2(196, 93) * RogueUI.K
	cancel_hit.size = Vector2(36, 10) * RogueUI.K
	cancel_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(cancel_hit)
	cancel_hit.gui_input.connect(func(e): if _is_left_click(e): _close_popup())


# 这一系的进化链（从最前面那只往后，按进化表走；分支都列出来）。
func _evo_chain(id: int) -> Array:
	var out: Array = []
	var queue: Array = [AB.root_of(id)]
	while not queue.is_empty() and out.size() < 12:
		var cur := int(queue.pop_front())
		if out.has(cur):
			continue
		out.append(cur)
		for e: Dictionary in Evolution.entries(cur):
			queue.append(int(e["to"]))
	return out


# 图鉴：属性、种族值、特性（含隐藏 / 被动）、成长速度、捕获率、进化链。
func _open_dex(id: int) -> void:
	_popup_shield()
	var prof := PokemonStarters.profile(id)
	RogueUI.window(_popup, 16, 8, 288, 160)
	RogueUI.label(_popup, "No.%04d  %s" % [id, str(prof.get("name", _display_name(id)))], 24, 12, "summary_gold", 16)
	var types: Array = prof.get("types", [])
	for i in mini(2, types.size()):
		var ti := RogueUI.type_icon(str(types[i]))
		if ti != null:
			RogueUI.image(_popup, ti, 130.0 + 18.0 * i, 14, 0.5)
	var bs: Array = prof.get("base_stats", [])
	var total := 0
	for i in mini(6, bs.size()):
		var y := 26.0 + 10.0 * i
		var v := int(bs[i])
		total += v
		RogueUI.label(_popup, IV_STAT_NAMES[i], 24, y, "window", 16)
		RogueUI.fill(_popup, 52, y + 2, 70.0 * minf(v, 200.0) / 200.0, 5, Color("f8c020") if v >= 100 else Color("40c8f8"))
		RogueUI.label(_popup, str(v), 126, y, "window", 16)
	RogueUI.label(_popup, "合计 %d" % total, 24, 88, "summary_gold", 16)
	var ax := 156.0
	var fuse_with := int(_wallet.fusion_for(id)) if _wallet != null else 0
	# 这页是物种资料（种族值也是它自己的）；融合了在标题上说清楚实际用谁的特性（2026-10-22 审查）
	RogueUI.label(_popup, "特性（融合后用%s的）" % _display_name(fuse_with) if fuse_with > 0 else "特性", ax, 26, "summary_gold", 16)
	var ay := 35.0
	for c: Dictionary in AB.slot_choices(id):
		RogueUI.label(_popup, "%s%s" % [AB.name_of(str(c["key"])), "（隐藏）" if bool(c["hidden"]) else ""], ax, ay, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 140)
		ay += 9.0
	var pk := AB.passive_of(id)
	if pk != "" and pk != AB.NONE:
		RogueUI.label(_popup, "被动：%s" % AB.name_of(pk), ax, ay, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 140)
		ay += 9.0
	RogueUI.label(_popup, "成长速度：%s" % str(GROWTH_ZH.get(int(prof.get("growth_rate", 2)), "较快")), ax, ay + 4, "window", 16)
	var cr := CaptureSpecies.catch_rate(id)
	RogueUI.label(_popup, "捕获率：%s" % (str(cr) if cr >= 0 else "—"), ax, ay + 13, "window", 16)
	var chain := _evo_chain(id)
	var names: Array = []
	for cid in chain:
		names.append(str(PokemonStarters.profile(int(cid)).get("name", _display_name(int(cid)))))
	RogueUI.label(_popup, "进化：" + " → ".join(names) if names.size() > 1 else "进化：不进化", 24, 100, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 270, true)


# ================= 收集进度 =================
const BiomePools := preload("res://data/pokemon_biome_pools.gd")


# 收集统计（只读本页已有的存档快照）：{caught, total, shiny, tiers[3], passive, perfect, favorites, regions[[名字, 抓到, 总数, 解锁]]}
func collection_stats() -> Dictionary:
	var caught := 0
	for id in _ids:
		if _is_caught(int(id)):
			caught += 1
	var tiers := [0, 0, 0]
	for sid in _shiny:
		for t in _tiers_of(int(sid)):
			tiers[clampi(int(t), 0, 2)] += 1
	var perfect := 0
	for root in _ivs:
		var six: Array = _ivs[root]
		if six.size() == 6 and six.min() >= 31:
			perfect += 1
	var regions: Array = []
	for b in Biomes.list():
		var bid := str(b["id"])
		if bid == "town":
			continue
		var sp: Array = BiomePools.species_in(bid)
		var got := 0
		for sid in sp:
			if _is_caught(int(sid)):
				got += 1
		regions.append([str(b.get("name", bid)), got, sp.size(), _maps_unlocked.has(bid)])
	return {"caught": caught, "total": _ids.size(), "shiny": _shiny.size(), "tiers": tiers,
		"passive": _passive_unlocked.size(), "perfect": perfect, "favorites": _favorites.size(), "regions": regions}


func _open_collection() -> void:
	_popup_shield()
	var st := collection_stats()
	RogueUI.window(_popup, 8, 4, 304, 170)
	RogueUI.label(_popup, "收集进度", 16, 8, "summary_gold", 16)
	var pct := 100.0 * float(st["caught"]) / maxf(1.0, float(st["total"]))
	RogueUI.label(_popup, "图鉴：抓到 %d / %d（%.1f%%）" % [st["caught"], st["total"], pct], 16, 19, "window", 16)
	var tiers: Array = st["tiers"]
	RogueUI.label(_popup, "闪光：%d 种（金 %d · 蓝 %d · 红 %d）" % [st["shiny"], tiers[0], tiers[1], tiers[2]], 16, 28, "window", 16)
	RogueUI.label(_popup, "被动解锁 %d 系 · 个体值全满 %d 系 · 最爱 %d 只" % [st["passive"], st["perfect"], st["favorites"]], 16, 37, "window", 16)
	RogueUI.label(_popup, "各地区（抓到 / 这里会出现的）", 16, 49, "summary_gold", 16)
	var regions: Array = st["regions"]
	for i in regions.size():
		var r: Array = regions[i]
		var col := i % 4
		var rw := int(floor(float(i) / 4.0))
		var x := 16.0 + col * 73.0
		var y := 58.0 + rw * 12.0
		if not bool(r[3]):
			RogueUI.label(_popup, "？？？", x, y, "summary_gray", 16, HORIZONTAL_ALIGNMENT_LEFT, 72)
			continue
		var done := int(r[2]) > 0 and int(r[1]) >= int(r[2])
		RogueUI.label(_popup, "%s %d/%d" % [r[0], r[1], r[2]], x, y, "summary_gold" if done else "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 72)


func _passive_menu_text(id: int) -> String:
	var root := AB.root_of(id)
	if not _passive_unlocked.has(root):
		return "解锁被动（%d 糖果）" % SpeciesCandy.passive_cost(root)
	return "启用被动" if _passive_off.has(root) else "禁用被动"


func _open_candy(id: int) -> void:
	var have := int(_candy.get(id, 0))
	var price := PokemonShop.price_at("RARE_CANDY", have)   # 每 10 颗单价翻倍
	var opts := [
		["神奇糖果 +1 级（%d 点）" % price, "buy", _points < price],
		["已用 %d 颗 · 点数 %d" % [have, _points], "info", true],
		["去商店买别的", "shop"],
		["取消", "cancel"],
	]
	_open_list(137, 54, 180, opts, _on_candy_pick, 16.0)


func _on_candy_pick(v) -> void:
	match str(v):
		"buy":
			buy_requested.emit("RARE_CANDY")
		"shop":
			shop_pressed.emit()


# 管理招式: 列出开局招（点一下留在家里 / 带上）和买过的技能机器（点一下带上 / 取下），悬停看招式资料。
# 用户 2026-10-20：每行右边“PP+n”点一下买 PP 提升剂（100 点，每招最多 3 个）；局里学过的招也列出来，
# 只能加 PP、不能带（不改开局能选哪些招）。
const MOVES_PER_PAGE := 16


func _pp_ups(id: int, move_id: String) -> int:
	return int(_wallet.held_for(id, HeldItems.pp_up_item(move_id))) if _wallet != null else 0


func _move_rows(id: int) -> Array:
	var rows: Array = []   # [招式 id, 标签, 商品 ID（"" = 不能带）, 带着没]
	var seen: Array = []
	var carried := _carried_moves(id)
	var own: Array = PokemonStarters.playable_initial_moves(id)
	for m in _starter_pool(id):
		rows.append([str(m), "开局招" if own.has(m) else "融合招", "STARTER:" + str(m), carried.has(str(m))])
		seen.append(str(m))
	var eggm: Array = (_wallet.egg_moves_for(id) + (_wallet.egg_moves_for(int(_wallet.fusion_for(id))) if int(_wallet.fusion_for(id)) > 0 else [])) if _wallet != null else []
	for m in _owned_tms(id):
		if seen.has(str(m)):
			continue
		if eggm.has(str(m)) and not TMRules.is_tm(str(m)):
			rows.append([str(m), "遗传招", "EGGMOVE:" + str(m), carried.has(str(m))])   # 蛋孵出来带的（生蛋，2026-10-23）
		else:
			rows.append([str(m), "技能机器", TMRules.product_id(str(m)), carried.has(str(m))])
		seen.append(str(m))
	if _wallet != null:
		for m in _wallet.moves_learned_for(id):
			if seen.has(str(m)) or not PokemonMoves.MOVES.has(str(m)):
				continue
			rows.append([str(m), "学过", "", false])
			seen.append(str(m))
	return rows


# 学招计划：这只（和融合对象）升级能学的招，按等级排；勾最多 4 个，局里只学这几个。
func _plan_rows(id: int) -> Array:
	var rows: Array = []   # [招式 id, 等级]
	var seen: Array = []
	var ids: Array = [id]
	if _wallet != null and int(_wallet.fusion_for(id)) > 0:
		ids.append(int(_wallet.fusion_for(id)))
	for lv in range(1, 101):
		for sid in ids:
			for m in PokemonMoves.learnable_between(int(sid), lv, lv, false):
				if not seen.has(str(m)):
					seen.append(str(m))
					rows.append([str(m), lv])
	return rows


func _open_plan(id: int) -> void:
	_popup_shield()
	RogueUI.window(_popup, 8, 16, 300, 148)
	RogueUI.label(_popup, "学招计划: 勾最多 4 个想学的招", 14, 20, "window", 16)
	var plan: Array = _wallet.learn_plan_for(id) if _wallet != null and _wallet.has_method("learn_plan_for") else []
	var all_rows := _plan_rows(id)
	var pages := maxi(1, int(ceil(float(all_rows.size()) / float(MOVES_PER_PAGE))))
	_moves_page = clampi(_moves_page, 0, pages - 1)
	var rows: Array = all_rows.slice(_moves_page * MOVES_PER_PAGE, (_moves_page + 1) * MOVES_PER_PAGE)
	var help := "勾了：局里升级只学计划里的招，并自动顶掉不在计划里的招；别的招不弹窗直接跳过（记忆蘑菇能找回）。一个都不勾 = 照旧每次问。已勾 %d/4。" % plan.size()
	var detail := RogueUI.label(_popup, help, 14, 138, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 288, true)
	for i in rows.size():
		var col := i % 2
		var rw := int(floor(float(i) / 2.0))
		var rx := 14.0 + col * 146.0
		var ry := 34.0 + rw * 13.0
		var mid := str(rows[i][0])
		var mv: Dictionary = PokemonMoves.MOVES.get(mid, {})
		var on := plan.has(mid)
		var bar := _move_bar(_popup, rx, ry, 140, 12)
		_set_bar_type(bar, str(mv.get("type", "")))
		bar.modulate = Color(1, 1, 1, 1) if on else Color(0.45, 0.45, 0.45, 1)
		RogueUI.label(_popup, "%sLv%d %s" % ["✓ " if on else "", int(rows[i][1]), str(mv.get("name", mid))], rx + 3, ry - 1, "party", 16, HORIZONTAL_ALIGNMENT_LEFT, 136)
		var info := _move_info(mid, _pp_ups(id, mid))
		var hit := Control.new()
		hit.position = Vector2(rx, ry) * RogueUI.K
		hit.size = Vector2(140, 12) * RogueUI.K
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_popup.add_child(hit)
		hit.mouse_entered.connect(func(): detail.text = info)
		hit.mouse_exited.connect(func(): detail.text = help)
		hit.gui_input.connect(func(e):
			if _is_left_click(e):
				if not on and plan.size() >= 4:
					detail.text = "已经勾满 4 个了，先取消一个。"
					return
				learn_plan_requested.emit(id, mid)
				_close_popup()
				_open_plan(id))
	if pages > 1:
		RogueUI.label(_popup, "第 %d/%d 页 ▶" % [_moves_page + 1, pages], 220, 126, "summary_gold", 16)
		var nhit := Control.new()
		nhit.position = Vector2(218, 124) * RogueUI.K
		nhit.size = Vector2(80, 12) * RogueUI.K
		nhit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(nhit)
		nhit.gui_input.connect(func(e):
			if _is_left_click(e):
				_moves_page = (_moves_page + 1) % pages
				_close_popup()
				_open_plan(id))
	if not plan.is_empty():
		RogueUI.label(_popup, "清空", 236, 20, "summary_gold", 16)
		var chit := Control.new()
		chit.position = Vector2(232, 18) * RogueUI.K
		chit.size = Vector2(30, 12) * RogueUI.K
		chit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(chit)
		chit.gui_input.connect(func(e):
			if _is_left_click(e):
				learn_plan_requested.emit(id, "")
				_close_popup()
				_open_plan(id))
	RogueUI.label(_popup, "完成", 270, 20, "summary_gold", 16)
	var dhit := Control.new()
	dhit.position = Vector2(266, 18) * RogueUI.K
	dhit.size = Vector2(36, 12) * RogueUI.K
	dhit.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(dhit)
	dhit.gui_input.connect(func(e): if _is_left_click(e): _close_popup())


func _open_moves(id: int) -> void:
	_popup_shield()
	RogueUI.window(_popup, 8, 16, 300, 148)
	RogueUI.label(_popup, "管理招式: 点一下带上、再点取下（最多带 %d 个），点右边 PP 加 PP" % _slots_for(id), 14, 20, "window", 16)
	var all_rows := _move_rows(id)
	var pages := maxi(1, int(ceil(float(all_rows.size()) / float(MOVES_PER_PAGE))))
	_moves_page = clampi(_moves_page, 0, pages - 1)
	var rows: Array = all_rows.slice(_moves_page * MOVES_PER_PAGE, (_moves_page + 1) * MOVES_PER_PAGE)
	var detail := RogueUI.label(_popup, "把鼠标移到某个招式上看资料；学过的招只能加 PP、不能带。", 14, 138, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 288, true)
	for i in rows.size():
		var col := i % 2
		var rw := int(floor(float(i) / 2.0))
		var rx := 14.0 + col * 146.0
		var ry := 34.0 + rw * 13.0
		var mid := str(rows[i][0])
		var mv: Dictionary = PokemonMoves.MOVES.get(mid, {})
		var on := bool(rows[i][3])
		var pid := str(rows[i][2])
		var bar := _move_bar(_popup, rx, ry, 140, 12)
		_set_bar_type(bar, str(mv.get("type", "")))
		bar.modulate = Color(1, 1, 1, 1) if on else Color(0.45, 0.45, 0.45, 1)
		RogueUI.label(_popup, "%s%s  [%s]" % ["✓ " if on else "", str(mv.get("name", mid)), str(rows[i][1])], rx + 3, ry - 1, "party", 16, HORIZONTAL_ALIGNMENT_LEFT, 110)
		var ups := _pp_ups(id, mid)
		# PP 已经高到冷却到底（PP≥20 那批）：再买冷却也不变，按钮灰掉不卖（2026-10-22 审查：撞击 / 吐丝买了白买）
		var pp_useless := ups < MovePP.MAX_UPS and is_equal_approx(MovePP.move_cd(mid, ups), MovePP.move_cd(mid, MovePP.MAX_UPS))
		var pp_label := RogueUI.label(_popup, ("PP够" if pp_useless else "PP+%d" % ups) if ups < MovePP.MAX_UPS else "PP满", rx + 112, ry - 1, "summary_gold", 16, HORIZONTAL_ALIGNMENT_LEFT, 28)
		if pp_useless:
			pp_label.modulate = Color(0.6, 0.6, 0.6, 1)
		var info := _move_info(mid, ups)
		# 左边：带上 / 留下（学过的招没有）
		var hit := Control.new()
		hit.position = Vector2(rx, ry) * RogueUI.K
		hit.size = Vector2(110, 12) * RogueUI.K
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(hit)
		var squeezed := false   # 2026-10-24 起自由选择：哪个都能点（满了会提示先取下一个）
		hit.mouse_entered.connect(func(): detail.text = info)
		if pid != "" and not squeezed:
			hit.gui_input.connect(func(e):
				if _is_left_click(e):
					move_toggle_requested.emit(pid)
					_close_popup()
					_open_moves(id))
		# 右边：买 PP 提升剂
		var pp_hit := Control.new()
		pp_hit.position = Vector2(rx + 110, ry) * RogueUI.K
		pp_hit.size = Vector2(30, 12) * RogueUI.K
		pp_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		pp_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_popup.add_child(pp_hit)
		var item := HeldItems.pp_up_item(mid)
		var pp_text := "PP 提升剂 %d 点（这一系共用，%d/%d）：%s" % [HeldItems.price(item), ups, MovePP.MAX_UPS, HeldItems.desc_of(item, ups)]
		if pp_useless:
			pp_text = "这招 PP 够高，冷却已经是最短（%.1f 秒），买 PP 提升剂也不会更快，所以不卖。" % MovePP.move_cd(mid, ups)
		pp_hit.mouse_entered.connect(func(): detail.text = pp_text)
		pp_hit.gui_input.connect(func(e):
			if _is_left_click(e) and ups < MovePP.MAX_UPS and not pp_useless:
				buy_requested.emit(HeldItems.product_id(item))
				_close_popup()
				_open_moves(id))
	if pages > 1:
		RogueUI.label(_popup, "第 %d/%d 页 ▶" % [_moves_page + 1, pages], 220, 126, "summary_gold", 16)
		var nhit := Control.new()
		nhit.position = Vector2(218, 124) * RogueUI.K
		nhit.size = Vector2(80, 12) * RogueUI.K
		nhit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(nhit)
		nhit.gui_input.connect(func(e):
			if _is_left_click(e):
				_moves_page = (_moves_page + 1) % pages
				_close_popup()
				_open_moves(id))
	var done := RogueUI.label(_popup, "完成", 270, 20, "summary_gold", 16)
	var dhit := Control.new()
	dhit.position = Vector2(266, 18) * RogueUI.K
	dhit.size = Vector2(36, 12) * RogueUI.K
	dhit.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(dhit)
	dhit.gui_input.connect(func(e): if _is_left_click(e): _close_popup())


func _move_info(move_id: String, ups: int = 0) -> String:
	var m: Dictionary = PokemonMoves.MOVES.get(move_id, {})
	if m.is_empty():
		return ""
	var power := int(m.get("power", 0))
	var acc := int(m.get("accuracy", 100))
	return "%s · %s · %s　威力 %s　命中 %s　PP %d　冷却 %.1f 秒\n%s" % [str(m.get("type", "")), str(m.get("category", "")), PokemonMoves.target_text(m), str(power) if power > 0 else "—", str(acc) if acc > 0 else "必中", MovePP.move_pp(move_id, ups), MovePP.move_cd(move_id, ups), preload("res://game/pokemon_move_roles.gd").desc_with_note(move_id)]


# ================= 出发设置: 地区 + 入场等级 =================

func _open_depart_menu() -> void:
	_popup_shield()
	RogueUI.window(_popup, 16, 8, 288, 134)
	RogueUI.label(_popup, "出发: 选地区和入场等级", 24, 12, "window", 16)
	var shown: Array = []
	for b in Biomes.list():
		if str(b["id"]) != "town":
			shown.append(b)
	for i in shown.size():
		var col := i % 4
		var rw := int(floor(float(i) / 4.0))
		var bx := 24.0 + col * 70.0
		var by := 24.0 + rw * 9.0
		var bid := str(shown[i]["id"])
		# 没走到过的地区：灰字“？？？”，点不了（撤离时走到就解锁）
		if not _maps_unlocked.has(bid):
			RogueUI.label(_popup, "？？？", bx, by - 1, "summary_gray", 16, HORIZONTAL_ALIGNMENT_LEFT, 68)
			continue
		RogueUI.label(_popup, str(shown[i].get("name", bid)), bx, by - 1, "summary_gold" if bid == _map else "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 68)
		var hit := Control.new()
		hit.position = Vector2(bx, by) * RogueUI.K
		hit.size = Vector2(68, 9) * RogueUI.K
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(hit)
		hit.gui_input.connect(func(e):
			if _is_left_click(e):
				_map = bid
				_entry_level = 0
				_open_depart_menu())
	var start_level := _start_level(_selected)
	var levels: Array[int] = Biomes.entry_levels(_map, start_level)
	if not levels.has(_entry_level):
		_entry_level = 0
	RogueUI.label(_popup, "入场等级:", 24, 113, "window", 16)
	# 说明（用户 2026-10-23：“把这个标示明白点”）：糖果加的等级不算进敌人等级；高一档 = 自己加难度换更多点数 / 经验
	var entry_note := "敌人从 1 级开始（糖果加的等级不算进敌人等级）" if _entry_level <= 0 		else "敌人从 %d 级开始：更难，但每只给的点数 / 经验更多" % _entry_level
	RogueUI.label(_popup, entry_note, 24, 123, "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 188, true)
	for i in mini(levels.size(), 7):
		var lv := levels[i]
		var lx := 66.0 + i * 34.0
		RogueUI.label(_popup, "起点" if lv == 0 else "Lv%d" % lv, lx, 113, "summary_gold" if lv == _entry_level else "window", 16, HORIZONTAL_ALIGNMENT_LEFT, 32)
		var hit2 := Control.new()
		hit2.position = Vector2(lx, 113) * RogueUI.K
		hit2.size = Vector2(32, 9) * RogueUI.K
		hit2.mouse_filter = Control.MOUSE_FILTER_STOP
		_popup.add_child(hit2)
		hit2.gui_input.connect(func(e):
			if _is_left_click(e):
				_entry_level = lv
				_open_depart_menu())
	RogueUI.window(_popup, 216, 122, 80, 16)
	RogueUI.label(_popup, "出发!", 216, 125, "summary_gold", 16, HORIZONTAL_ALIGNMENT_CENTER, 80)
	var go := Control.new()
	go.position = Vector2(216, 122) * RogueUI.K
	go.size = Vector2(80, 16) * RogueUI.K
	go.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.add_child(go)
	go.gui_input.connect(func(e):
		if _is_left_click(e):
			_close_popup()
			depart_pressed.emit())


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _popup.get_child_count() > 0:
			_close_popup()
		elif _fusing_for > 0:
			_cancel_fusion_pick()
		elif _breeding_for > 0:
			_breeding_for = 0
			clear_message()
		else:
			title_pressed.emit()
	elif event.physical_keycode == KEY_S and _popup.get_child_count() == 0 and _shiny_ok(_shown_id()):
		get_viewport().set_input_as_handled()
		_toggle_shiny(_shown_id())
	elif event.physical_keycode == KEY_V and _popup.get_child_count() == 0 and _is_caught(_shown_id()):
		get_viewport().set_input_as_handled()
		_flip_info_page(_shown_id(), 1)
	elif event.physical_keycode == KEY_N and _popup.get_child_count() == 0:
		get_viewport().set_input_as_handled()
		_cycle_nature(_shown_id())
	elif event.physical_keycode == KEY_P and _popup.get_child_count() == 0:
		get_viewport().set_input_as_handled()
		_passive_action(_shown_id())
	elif event.physical_keycode == KEY_E and _popup.get_child_count() == 0:
		get_viewport().set_input_as_handled()
		_cycle_ability(_shown_id())
	elif event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and _popup.get_child_count() == 0:
		get_viewport().set_input_as_handled()
		_on_start()


# 小图标描一圈深色边（八个方向各垫一张深色的，再盖原图），和树果 / 球的描边一个颜色。
func _outlined_image(parent: Node, tex: Texture2D, x: float, y: float, scale: float) -> void:
	var d := 0.5   # 一个屏幕像素（RogueUI.K = 2）
	for off in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]:
		var t := RogueUI.image(parent, tex, x + off.x, y + off.y, scale)
		t.modulate = Color(0.08, 0.06, 0.12, 1.0)   # 同 RogueSkin.OUTLINE_COLOR
	RogueUI.image(parent, tex, x, y, scale)
