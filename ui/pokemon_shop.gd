extends CanvasLayer
# 商店页面（2026-10-15，商店第 2/3 段）：只负责**展示**和发信号，不自己扣点 / 不自己写档。
#
# 双入口：
#   - 局外·城镇：`open_town(total, owned)`，分「全体加成 / 单只培养」两栏，显示持久点数；
#     全体加成现在开放两种经验护符 + 原治愈护符（后两项的显示 / 购买按钮）。
#   - 局内·Esc：`open_run(total, run, owned, balls)`，只列药 / 球；五种伤药显示「购买并使用」，
#     捕获第 2 段五种球显示「购买」+ 每份数量与本局库存（上限 99）。
#
# 购买只发 `purchase_pressed(source_id)`；真正的价格 / 上限 / 地点校验 / 扣款 / 存档 / 药效 /
# 球库存由 main/state 调 game/pokemon_shop.gd + game/pokemon_points.gd + main/combat.gd 完成，
# 本页不接收也不显示“UI 传入的价格”。
# 糖果 / 营养 / TM / 进化 / 携带等仍禁售「尚未开放」；RARER_CANDY（用户删除）不上架。
# UI 只读 data/pokemon_shop_catalog.gd 的完整目录做展示。
#
# 用法：
#   page.purchase_pressed.connect(...); page.resume_pressed.connect(...)
#   page.settings_pressed.connect(...); page.abandon_pressed.connect(...); page.closed.connect(...)
#   page.open_town(total, owned) / page.open_run(total, run, owned) / page.update_state(...) / page.close()

signal purchase_pressed(source_id: String)
signal resume_pressed
signal back_pressed        # 局内商店“返回”（Esc）：回到暂停的抓宠界面（Esc 暂停 = 抓宠界面，商店从 B 区按钮进）
signal settings_pressed
signal abandon_pressed
signal ball_chosen(ball_type: int)   # 局内商店 A 区选了一种球：main 收起商店、进入暂停抓宠物（选圈、投出即恢复）
signal closed              # 局外商店关闭（回城镇）

const Hud := preload("res://ui/hud.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")   # 原版 Pokémon Rogue 的窗口 / 字体 / 字色（2026-10-18：商店也换成原生风格）
const PokemonMoves := preload("res://data/pokemon_moves.gd")
const Catalog := preload("res://data/pokemon_shop_catalog.gd")
const Shop := preload("res://game/pokemon_shop.gd")
const RogueAtlas := preload("res://ui/rogue_atlas.gd")
const MovePP := preload("res://game/pokemon_pp.gd")

const DESIGN := Vector2(1280, 720)
const BACKDROP := Color("14121c")   # 原版深紫黑底

# 玩家可读文案（产品页只写中文分类 / 稀有度 / 效果；源表达式、maxStack / apply / value 等
# 实现词只留在 data/POKEMON_SHOP_SOURCE.md 与 catalog 源数据里，不上界面）。
var show_all_medicines := false   # 老检查要测全部五种药时打开（游戏里只摆好伤药 / 全复药，2026-10-24）
const TIER_ZH := {
	0: "普通",
	1: "优秀",
	2: "究极",
	3: "传说",
	4: "大师",
	5: "豪华",
}
const CATEGORY_ZH := {
	"ball": "精灵球",
	"medicine": "伤药",
	"candy": "神奇糖果",
	"stat_training": "营养饮料",
	"tm": "技能机器",
	"mint": "薄荷",
	"evolution": "进化道具",
	"pp_up": "PP提升",
	"remember": "招式回忆",
	"global_candy": "全体糖果加成",
	"global_exp": "全体经验加成",
	"global_heal": "全体治疗加成",
}

# 局内五种药的实际原回复说明（照原 PokemonHpRestoreModifier 的 points / percent 写中文，
# 不露源表达式 / 内部字段）。显示名仍取目录里的中文名。
const MEDICINE_ZH := {
	"POTION": "回复 20 点，或最大 HP 的 10%，取较高者",
	"SUPER_POTION": "回复 50 点，或最大 HP 的 25%，取较高者",
	"HYPER_POTION": "回复 200 点，或最大 HP 的 50%，取较高者",
	"MAX_POTION": "回复全部 HP（最大 HP 的 100%）",
	"FULL_RESTORE": "回复全部 HP，并解除主要异常（不影响混乱）",
	"FULL_HEAL": "解除主要异常（麻痹 / 中毒 / 睡眠 / 冰冻 / 灼伤），不回血（不影响混乱）；买树果更划算（树果 20 点、自动吃）",
}

const Berries := preload("res://game/pokemon_berries.gd")
const Memory := preload("res://game/pokemon_memory.gd")
const Lens := preload("res://game/pokemon_lens.gd")
const Held := preload("res://game/pokemon_held_items.gd")

var _root: Control
var _berries: Dictionary = {"SITRUS": 0, "LUM": 0}   # 本局带着的树果数（open_run 时由 main 传进来）
var _holder: PanelContainer
var _title: Label
var _points_label: Label
var _sub_label: Label
var _tab_bar: HBoxContainer
var _run_tab_bar: HBoxContainer          # 局内商店的分页：球 / 回复 / 树果 / 进化
var _run_tab_buttons := {}
# 局外“单只培养”的小分页（用户 2026-10-21：“单只培养底下很多东西，要分类了”）：成长 / 招式 / 镜片 / 携带道具
var _single_tab_bar: HBoxContainer
var _single_tab_buttons := {}
var _single_tab := "grow"
var _run_tab := "ball"
var _memory_forgotten: Array = []         # 记忆蘑菇能恢复的招 [{id, name, info}]（main 打开 / 刷新商店前传进来）
var _memory_current: Array = []           # 现在带着的招 [{id, name}]（槽满时选替换谁）
var _memory_slots := 4
var _held_rows: Array = []   # 选中那只这一系能买的携带道具 [{item, count}]（main 传进来）
var _lens_levels := {"support": 0, "attack": 0, "capture": 0}   # 选中那只已买的多重镜 / 捕捉镜等级（main 传进来）
var _memory_pick := ""                    # 已选中要恢复的招，正在选换掉哪一招（空 = 没在选）
var _tab_buttons := {}
var _scroll: ScrollContainer
var _list: VBoxContainer
var _message_label: Label
var _close_btn: Button
var _resume_btn: Button
var _back_btn: Button
var _settings_btn: Button
var _abandon_btn: Button
# 神奇糖果那一行要显示的“为谁买”（main/state.gd::_refresh_shop_candy 推过来；UI 不自己算）。
var _candy_species := 0
var _candy_name := ""
var _candy_count := 0
var _candy_ok := false
var _candy_evs: Array = [0, 0, 0, 0, 0, 0]
var _tm_info: Dictionary = {"learnable": [], "slots": 0, "owned": [], "equipped": []}   # 技能机器：能学的 / 空槽数 / 买过的 / 带着的
var _town_bg: Control
var _dim: ColorRect
var _center: CenterContainer
var _ball_panel: PanelContainer     # A 区：局内商店左侧的球面板
var _ball_buttons := {}             # ball_type -> Button
# 展示用的按钮表：source_id -> Button（检查用 button_for 查同一批节点）。
var _buttons := {}

var _mode := "town"          # town / run
var _track := "global"       # 局外栏：global（全体加成）/ single（单只培养）
var _total := 0
var _run := 0
var _owned: Dictionary = {}
# 本局球库存（source_id -> 数量，只读展示；真实库存在 main/state.gd 内存里）。
var _balls: Dictionary = {}


func _init() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_page)
	_fit_page()


func _fit_page() -> void:
	if _root != null:
		Hud.fit_page(_root, get_viewport().get_visible_rect().size, DESIGN)
		_avoid_ball_panel()


# ================= 对外接口 =================

func open_town(total: int, owned: Dictionary) -> void:
	_mode = "town"
	_total = maxi(0, int(total))
	_run = 0
	_owned = owned.duplicate()
	_message_label.text = ""
	_refresh()
	visible = true
	_fit_page()


func open_run(total: int, run: int, owned: Dictionary, balls: Dictionary = {}) -> void:
	_mode = "run"
	_total = maxi(0, int(total))
	_run = maxi(0, int(run))
	_owned = owned.duplicate()
	_balls = balls.duplicate()
	_message_label.text = ""
	_refresh()
	visible = true
	_fit_page()


# 购买成功 / 点数变化后刷新（分数与已买层数来自后端，不由 UI 自算）。
# 本局带着的树果数（main 在每次打开 / 刷新商店前传进来）。
func set_berry_counts(counts: Dictionary) -> void:
	_berries = counts.duplicate()


func update_state(total: int, run: int, owned: Dictionary, balls: Dictionary = {}) -> void:
	_total = maxi(0, int(total))
	_run = maxi(0, int(run))
	_owned = owned.duplicate()
	_balls = balls.duplicate()
	_refresh()


func set_candy_target(species_id: int, species_name: String, count: int, can_buy: bool, evs: Array = [], tm: Dictionary = {}) -> void:
	if not tm.is_empty():
		_tm_info = tm.duplicate(true)
	_candy_species = species_id
	_candy_name = species_name
	_candy_count = count
	_candy_ok = can_buy
	_candy_evs = evs.duplicate() if evs.size() == 6 else [0, 0, 0, 0, 0, 0]
	if _mode == "town" and _track == "single":
		_rebuild_list()


# 局内商店的进化道具行（main/state.gd::_evolution_item_rows 推来的）：rows 每项 {id, item, name, to, to_name, price, rare}。
var _evo_rows: Array = []
var _evo_who := ""
var _evo_pending := false


func set_run_evolutions(rows: Array, who: String, pending: bool) -> void:
	_evo_rows = rows.duplicate(true)
	_evo_who = who
	_evo_pending = pending
	if _mode == "run" and visible:
		_rebuild_list()


# 记忆蘑菇（回复页最后）：恢复在城镇用技能机器学过、现在没带的招（局内不卖技能机器）。
# 有空槽：点买直接学；槽满：先点要恢复的招，再选换掉现在哪一招（用同一页的另一组按钮）。
func _add_memory_rows() -> void:
	_list.add_child(_section_note("记忆蘑菇：想起没带着的招——到现在等级为止能学的招、这一局被换掉的招、城镇用技能机器学过的招；买一个恢复一招，%d 点。" % Memory.PRICE))
	var base: Dictionary = {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_IN_RUN):
		if Shop.is_run_medicine(str(rec["source_id"])):
			base = rec
			break
	if base.is_empty():
		return
	if _memory_forgotten.is_empty():
		var none: Dictionary = base.duplicate()
		none["source_id"] = "MEMORY:none"
		none["name_zh"] = "记忆蘑菇"
		none["tag_zh"] = ""
		_list.add_child(_make_row(none, false, "现在没有可恢复的招：到这个等级能学的招都带在身上了。", "没有可恢复的"))
		return
	var slots_full := _memory_current.size() >= _memory_slots
	if _memory_pick != "":
		var picked_name := _memory_pick
		var picked_info := ""
		for f: Dictionary in _memory_forgotten:
			if str(f["id"]) == _memory_pick:
				picked_name = str(f["name"])
				picked_info = str(f.get("info", ""))
		_list.add_child(_section_note("要恢复「%s」，招式槽满了：选一个现在的招换掉。" % picked_name))
		# 用户 2026-10-20：换招时要看得到两边的招式说明——先放要恢复的招，下面每行是现在带着的招
		var want: Dictionary = base.duplicate()
		want["source_id"] = "MEMORY:want"
		want["name_zh"] = "要恢复「%s」" % picked_name
		want["tag_zh"] = "记忆蘑菇"
		want["info"] = picked_info
		_list.add_child(_make_row(want, false, "下面选一个现在带着的招换掉它。", "新招"))
		for i in _memory_current.size():
			var rep: Dictionary = base.duplicate()
			rep["source_id"] = Memory.product_id(_memory_pick, i)
			rep["name_zh"] = "换掉「%s」" % str(_memory_current[i]["name"])
			rep["tag_zh"] = "现在带着"
			rep["info"] = str(_memory_current[i].get("info", ""))
			_list.add_child(_make_row(rep, true, "恢复「%s」，%d 点" % [picked_name, Memory.PRICE], "确认（%d 点）" % Memory.PRICE))
		var back: Dictionary = base.duplicate()
		back["source_id"] = "MEMORY:cancel"
		back["name_zh"] = "先不换了"
		back["tag_zh"] = ""
		var back_row := _make_row(back, true, "回到上一步，重新选。", "取消")
		_list.add_child(back_row)
		var back_btn: Button = _buttons.get("MEMORY:cancel", null)
		if back_btn != null:
			for c in back_btn.pressed.get_connections():
				back_btn.pressed.disconnect(c["callable"])
			back_btn.pressed.connect(func():
				_memory_pick = ""
				_rebuild_list())
		return
	for f: Dictionary in _memory_forgotten:
		var row: Dictionary = base.duplicate()
		var fid := str(f["id"])
		row["source_id"] = Memory.product_id(fid, "free")
		row["name_zh"] = "记忆蘑菇·恢复「%s」" % str(f["name"])
		row["tag_zh"] = ""
		row["info"] = str(f["info"])
		var detail := "%d 点/个 · %s" % [Memory.PRICE, "招式槽满了，买的时候要选换掉哪一招" if slots_full else "有空槽，直接学会"]
		_list.add_child(_make_row(row, true, detail, "购买（%d 点）" % Memory.PRICE))
		if slots_full:
			# 槽满：这一行的按钮改成“先选换谁”，不立刻扣点
			var btn: Button = _buttons.get(str(row["source_id"]), null)
			if btn != null:
				for c in btn.pressed.get_connections():
					btn.pressed.disconnect(c["callable"])
				btn.text = "选择换掉哪一招"
				btn.pressed.connect(func():
					_memory_pick = fid
					_rebuild_list())


# 树果（局内商店最后加两行：文柚果 / 木子果）：买了就带着，自动吃，规则见 game/pokemon_berries.gd。
func _add_berry_rows() -> void:
	_list.add_child(_section_note("树果：买了就带着，条件到了自动吃，不用点（每种最多带 %d 个，本局有效；画面右边会显示还剩几个）。" % Berries.CAP))
	var base: Dictionary = {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_IN_RUN):
		if Shop.is_run_medicine(str(rec["source_id"])):
			base = rec
			break
	if base.is_empty():
		return
	for kind: String in Berries.KINDS:
		var row: Dictionary = base.duplicate()
		row["source_id"] = Berries.product_id(kind)
		row["name_zh"] = Berries.display_name(kind)
		row["tag_zh"] = "树果"
		var have := int(_berries.get(kind, 0))
		var can := have < Berries.CAP
		var detail := "%s · %d 点/个 · 现有 %d/%d" % [Berries.describe(kind), Berries.PRICE, have, Berries.CAP]
		_list.add_child(_make_row(row, can, detail, ("购买（%d 点）" % Berries.PRICE) if can else "已带满"))


func _add_evolution_rows() -> void:
	if _evo_rows.is_empty():
		return
	_list.add_child(_section_note("特殊进化（给「%s」用，靠进化道具进化：石头 / 联系绳 / 进化契机（原作要亲密度 / 会某招 / 特殊条件的）；买了离开商店后播进化；普通 30 点 / 稀有 100 点，进化后新形态记进图鉴）" % _evo_who))
	var base_common := {}
	var base_rare := {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_TOWN_POKEMON):
		if str(rec["source_id"]) == "EVOLUTION_ITEM":
			base_common = rec
		elif str(rec["source_id"]) == "RARE_EVOLUTION_ITEM":
			base_rare = rec
	for r: Dictionary in _evo_rows:
		var base: Dictionary = (base_rare if bool(r["rare"]) else base_common).duplicate()
		if base.is_empty():
			continue
		base["source_id"] = str(r["id"])
		if r.has("form"):
			# 超级石 / 极巨菇（用户 2026-10-23）：买了立刻变身，这一局一直保持
			base["name_zh"] = "%s·%s" % ["超极巨化" if str(r.get("kind", "")) == "gmax" else "超级进化", str(r["name"])]
			var fdetail := "%s → %s · %d 点（买了立刻变身，这一局一直保持；再进化会变回普通形态）%s" % [_evo_who, str(r["to_name"]), int(r["price"]), ("\n" + str(r["note"])) if str(r.get("note", "")) != "" else ""]
			_list.add_child(_make_row(base, true, fdetail, "购买（%d 点）" % int(r["price"])))
			continue
		base["name_zh"] = "进化道具·%s" % str(r["name"])
		var detail := "%s → %s · %d 点（%s）%s" % [_evo_who, str(r["to_name"]), int(r["price"]), "稀有" if bool(r["rare"]) else "普通", (" · " + str(r["note"])) if str(r.get("note", "")) != "" else ""]
		var can := not _evo_pending
		_list.add_child(_make_row(base, can, detail if can else "已经买了一个，先离开商店进化", ("购买（%d 点）" % int(r["price"])) if can else "待进化"))


func show_message(text: String) -> void:
	if _message_label != null:
		_message_label.text = str(text)


func close() -> void:
	visible = false


# 暂停抓宠物：只收起商店页面，模式 / 暂停状态不变（main 之后会 open_run 回来或恢复游戏）。
func hide_for_capture() -> void:
	visible = false


# 窗口宽到不会压住球面板就严格居中（offset 0）；窄了才右移刚好够的距离。
func _avoid_ball_panel() -> void:
	_center.offset_left = 0.0
	if _mode != "run" or _root == null:
		return
	var hw := maxf(_holder.get_combined_minimum_size().x, _holder.custom_minimum_size.x)
	var left := (_root.size.x - hw) * 0.5
	var need := _ball_panel.offset_left + _ball_panel.get_combined_minimum_size().x + 12.0
	_center.offset_left = maxf(0.0, 2.0 * (need - left))


# A 区球面板：和暂停抓宠时一样（用户 2026-10-20）——只有五个原版球图标竖排，左上键号、右下库存，
# 悬停看名字；库存 0 的灰掉；点一个 / 按数字键发 ball_chosen。位置也和抓宠界面对齐（16, 100）。
var _ball_counts := {}   # ball_type -> 右下角库存数字


func _build_ball_panel() -> void:
	_ball_panel = PanelContainer.new()
	_ball_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ball_panel.offset_left = 16
	_ball_panel.offset_top = 100
	_ball_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(_ball_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball_panel.add_child(column)
	var icons := ["pb", "gb", "ub", "rb", "mb"]
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.12)
	hover.set_corner_radius_all(6)
	for ball_type in Shop.BALL_IDS.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", hover)
		button.add_child(RogueSkin.outlined_icon(RogueAtlas.frame("icons/items", str(icons[ball_type])), 52))
		var key := RogueSkin.label(str(int(ball_type) + 1), RogueSkin.SIZE_SMALL, "summary_gold")
		key.position = Vector2(2, 0)
		key.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
		key.add_theme_constant_override("outline_size", 6)
		button.add_child(key)
		var cnt := RogueSkin.label("0", RogueSkin.SIZE_SMALL, "window")
		cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cnt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		cnt.offset_right = -2
		cnt.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
		cnt.add_theme_constant_override("outline_size", 6)
		button.add_child(cnt)
		button.pressed.connect(_on_ball_button.bind(int(ball_type)))
		column.add_child(button)
		_ball_buttons[int(ball_type)] = button
		_ball_counts[int(ball_type)] = cnt


func _refresh_ball_buttons() -> void:
	for ball_type in _ball_buttons:
		var sid := Shop.ball_source_id(int(ball_type))
		var have := int(_balls.get(sid, 0))
		var button: Button = _ball_buttons[ball_type]
		button.tooltip_text = "[%d] %s %d/%d" % [int(ball_type) + 1, Shop.display_name(sid), have, Shop.BALL_CAP]
		(_ball_counts[ball_type] as Label).text = str(have)
		button.disabled = have <= 0
		button.modulate = Color(0.45, 0.45, 0.5, 0.8) if have <= 0 else Color.WHITE


func _on_ball_button(ball_type: int) -> void:
	if _mode != "run":
		return
	var sid := Shop.ball_source_id(ball_type)
	if int(_balls.get(sid, 0)) <= 0:
		show_message("「%s」用完了，可以在下面买。" % Shop.display_name(sid))
		return
	ball_chosen.emit(ball_type)


func ball_button_for(ball_type: int) -> Button:
	return _ball_buttons.get(ball_type, null)


func is_open() -> bool:
	return visible


func mode() -> String:
	return _mode


func track() -> String:
	return _track


func points_total() -> int:
	return _total


# 展示用只读查询：检查按 ID 找同一批真实按钮。
func button_for(source_id: String) -> Button:
	if _mode != "run" and _track == "single" and not _buttons.has(source_id):
		var stab := _single_tab_of(source_id)
		if stab != _single_tab:
			_single_tab = stab
			_refresh()
	if _mode == "run" and not _buttons.has(source_id):
		var want := _run_tab_of(source_id)
		if want != _run_tab:
			_run_tab = want
			_memory_pick = ""
			_refresh()
	return _buttons.get(source_id, null)


func visible_row_ids() -> Array:
	var out: Array = []
	for id in _buttons:
		out.append(str(id))
	return out


# ================= 刷新 / 搭行 =================

func _refresh() -> void:
	if _root == null:
		return
	if _mode == "run":
		_title.text = "商店 · 局内"
		_points_label.text = "点数 %d · 本局 %d" % [_total, _run]
		_sub_label.text = "局内消耗品：伤药购买即用；精灵球按份购买、用不完的会带到以后的局；想抓宠物就在左边选球（或按数字键 1–5），选好直接去战场上放圈。"
		_tab_bar.visible = false
		_run_tab_bar.visible = true
		_single_tab_bar.visible = false
		_refresh_run_tabs()
	else:
		_run_tab_bar.visible = false
		_title.text = "商店 · 局外"
		_points_label.text = "点数 %d" % _total
		_sub_label.text = "点数所有宝可梦共用；全体加成对所有宝可梦和新开的局都生效。"
		_tab_bar.visible = true
		_single_tab_bar.visible = _track == "single"
		_refresh_tab_buttons()
		_refresh_single_tabs()
	_refresh_footer()
	_rebuild_list()


func _refresh_footer() -> void:
	var run_mode := _mode == "run"
	# 局内商店：背景透出暂停中的游戏画面（看到想抓的宠物可以停下来）；局外仍是城镇底图。
	_town_bg.visible = not run_mode
	_dim.color = Color(BACKDROP, 0.55 if run_mode else 0.92)
	_ball_panel.visible = run_mode
	# 局内：商店窗口在整个屏幕正中（用户 2026-10-17：“不居中”）；只有窗口窄到会压住左边的球面板时，
	# 才往右让开刚好够的一点（_avoid_ball_panel）；局外仍居中 1060。
	_holder.custom_minimum_size = Vector2(940, 640) if run_mode else Vector2(1060, 640)
	_avoid_ball_panel()
	_back_btn.visible = run_mode
	_resume_btn.visible = run_mode
	_settings_btn.visible = run_mode
	_abandon_btn.visible = run_mode
	_close_btn.visible = not run_mode


# 局内商店的分页：精灵球 / 回复（伤药 + 万灵药 + 记忆蘑菇）/ 树果 / 进化（只有这只有可进化的才出现）。
func _on_run_tab(tab: String) -> void:
	if tab == _run_tab:
		return
	_run_tab = tab
	_memory_pick = ""
	_refresh()


func _refresh_run_tabs() -> void:
	if _run_tab == "evo" and _evo_rows.is_empty():
		_run_tab = "ball"
	for key: String in _run_tab_buttons:
		var b: Button = _run_tab_buttons[key]
		b.visible = key != "evo" or not _evo_rows.is_empty()
		var on: bool = key == _run_tab
		b.add_theme_stylebox_override("normal", RogueSkin.box(4 if on else 2, "_thin", 6))
		var on_color := RogueSkin.KIT_BTN_TEXT_DARK if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")
		b.add_theme_color_override("font_color", on_color if on else (RogueSkin.KIT_BTN_TEXT if RogueSkin.USE_KIT else RogueSkin.style_color("window")))
		b.add_theme_color_override("font_hover_color", on_color if on else (Color("FFE29A") if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")))


func _on_single_tab(tab: String) -> void:
	if tab == _single_tab:
		return
	_single_tab = tab
	_refresh()


func _refresh_single_tabs() -> void:
	for key: String in _single_tab_buttons:
		var b: Button = _single_tab_buttons[key]
		var on: bool = key == _single_tab
		b.add_theme_stylebox_override("normal", RogueSkin.box(4 if on else 2, "_thin", 6))
		var on_color := RogueSkin.KIT_BTN_TEXT_DARK if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")
		b.add_theme_color_override("font_color", on_color if on else (RogueSkin.KIT_BTN_TEXT if RogueSkin.USE_KIT else RogueSkin.style_color("window")))
		b.add_theme_color_override("font_hover_color", on_color if on else (Color("FFE29A") if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")))


# 单只培养的商品在哪个小分页（测试 / 外部按 ID 找按钮时用）。
func _single_tab_of(id: String) -> String:
	if id.begins_with("TM:") or id.begins_with("STARTER:"):
		return "moves"
	if Lens.is_product(id):
		return "lens"
	if Held.is_product(id):
		return "held"
	return "grow"


# 这个商品属于局内商店的哪一页（测试 / 外部按 ID 找按钮时用）。
func _run_tab_of(id: String) -> String:
	if Shop.is_run_ball(id):
		return "ball"
	if Berries.is_product(id):
		return "berry"
	if id.begins_with(Memory.PREFIX):
		return "memory"
	if id.begins_with("EVO"):
		return "evo"
	return "heal"


func set_held_items(rows: Array) -> void:
	_held_rows = rows.duplicate(true)


# 携带道具（单只培养最后）：原版效果，按进化系共用；价格按原稀有度档（究极 100 / Rogue 300 点一个）。
func _add_held_rows() -> void:
	_list.add_child(_section_note("携带道具（照原版；给选中的宠物这一系买，进化前后都带着；每样能叠几个照原版）："))
	var base: Dictionary = {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_TOWN_POKEMON):
		if Shop.is_town_candy(str(rec["source_id"])):
			base = rec
			break
	if base.is_empty():
		return
	var who := _candy_name if _candy_name != "" else "选中的宠物"
	for hr: Dictionary in _held_rows:
		var item := str(hr["item"])
		var have := int(hr["count"])
		var cap := Held.max_stacks(item)
		var price := Held.price(item)
		var row: Dictionary = base.duplicate()
		row["source_id"] = Held.product_id(item)
		row["name_zh"] = Held.name_of(item)
		row["tag_zh"] = "携带道具 · %s" % {"ULTRA": "究极", "ROGUE": "Rogue", "MASTER": "大师"}.get(str(Held.ITEMS.get(item, {}).get("tier", "ULTRA")), "究极")
		var detail := "为「%s」这一系买：%s · 现在 %d/%d 个 · %d 点/个" % [who, Held.desc_of(item, have), have, cap, price]
		if not _candy_ok:
			detail = "先在图鉴里选一只已捕获的宝可梦，再来买"
		var can := _candy_ok and have < cap
		_list.add_child(_make_row(row, can, detail, ("购买（%d 点）" % price) if can else ("已带满" if _candy_ok else "先选宠物")))


func set_lens_levels(levels: Dictionary) -> void:
	_lens_levels = {"support": int(levels.get("support", 0)), "attack": int(levels.get("attack", 0)), "capture": int(levels.get("capture", 0))}


# 多重镜 / 捕捉镜（单只培养最后几行）：每只宠物各买各的，每种 3 级，第二级起更贵。规则见 game/pokemon_lens.gd。
func _add_lens_rows() -> void:
	_list.add_child(_section_note("镜片（给选中的宠物买，每种最多买到 3 级，越往后越贵；闪光开局 / 融合闪光还能再往上加，最高 9 级——想要更高就去刷闪光）：多重镜让单体招同时波及更多目标；捕捉镜提高这只扔球的捕获率。"))
	var base: Dictionary = {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_TOWN_POKEMON):
		if Shop.is_town_candy(str(rec["source_id"])):
			base = rec
			break
	if base.is_empty():
		return
	var who := _candy_name if _candy_name != "" else "选中的宠物"
	for kind: String in Lens.KINDS:
		var row: Dictionary = base.duplicate()
		row["source_id"] = Lens.product_id(kind)
		row["name_zh"] = str(Lens.NAMES[kind])
		row["tag_zh"] = "镜片"
		var level := int(_lens_levels.get(kind, 0))
		var price := Lens.next_price(kind, level)
		var detail := "为「%s」这一系买（进化前后都算）：%s；%s · 现在 %d/%d 级" % [who, Lens.DESC[kind], Lens.SHINY_NOTE, level, Lens.MAX_LEVEL]
		if price > 0:
			detail += " · 下一级 %d 点" % price
		if not _candy_ok:
			detail = "先在图鉴里选一只已捕获的宝可梦，再来买"
		var can := _candy_ok and price > 0
		_list.add_child(_make_row(row, can, detail, ("购买（%d 点）" % price) if can else ("已满级" if _candy_ok else "先选宠物")))


func set_memory_info(forgotten: Array, current: Array, slots: int) -> void:
	_memory_forgotten = forgotten.duplicate(true)
	_memory_current = current.duplicate(true)
	_memory_slots = maxi(1, slots)
	_memory_pick = ""


func _refresh_tab_buttons() -> void:
	for key: String in _tab_buttons:
		var on: bool = key == _track
		var b: Button = _tab_buttons[key]
		b.add_theme_stylebox_override("normal", RogueSkin.box(4 if on else 2, "_thin", 6))
		var on_color := RogueSkin.KIT_BTN_TEXT_DARK if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")   # 素材包选中页签是奶白底，字用深色
		b.add_theme_color_override("font_color", on_color if on else (RogueSkin.KIT_BTN_TEXT if RogueSkin.USE_KIT else RogueSkin.style_color("window")))
		b.add_theme_color_override("font_hover_color", on_color if on else (Color("FFE29A") if RogueSkin.USE_KIT else RogueSkin.style_color("summary_gold")))


func _rebuild_list() -> void:
	_refresh_ball_buttons()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_buttons = {}
	if _mode == "run":
		match _run_tab:
			"ball":
				_list.add_child(_section_note("精灵球按份购买、用不完的会带到以后的局；想抓宠物就在左边选球（或按数字键 1–5），选好直接去战场上放圈。"))
				for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_IN_RUN):
					var bid := str(rec["source_id"])
					if Shop.is_run_ball(bid):
						var ball_price := Shop.price(bid)
						var pack := Shop.ball_pack(bid)
						var have := int(_balls.get(bid, 0))
						var bdetail := "每份 %d 个 · %d 点/份 · 本局现有 %d/%d" % [pack, ball_price, have, Shop.BALL_CAP]
						var can_buy := have < Shop.BALL_CAP
						_list.add_child(_make_row(rec, can_buy, bdetail,
							("购买（%d 点）" % ball_price) if can_buy else "已达上限"))
			"heal":
				_list.add_child(_section_note("回复：买了立刻对当前上场的宝可梦使用。（想省点数：买树果更划算，自动吃。）"))
				for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_IN_RUN):
					var id := str(rec["source_id"])
					if Shop.is_run_medicine(id) and not Shop.SHOWN_MEDICINES.has(id) and not show_all_medicines:
						continue   # 同价被盖过的药不摆（2026-10-24）
					if Shop.is_run_medicine(id):
						var price := Shop.price(id)
						var detail := "%s · %d 点/个" % [MEDICINE_ZH.get(id, "恢复 HP"), price]
						_list.add_child(_make_row(rec, true, detail, "购买并使用（%d 点）" % price))
			"memory":
				_add_memory_rows()
			"berry":
				_add_berry_rows()
			"evo":
				_add_evolution_rows()
		return
	if _track == "single":
		match _single_tab:
			"lens":
				_add_lens_rows()
				return
			"held":
				_add_held_rows()
				return
			"moves":
				_add_tm_rows()   # 开局招 + 三档技能机器合成“按招式一行”的列表（只列选中宝可梦能学、本作已接战斗的）
				return
		_list.add_child(_section_note("成长：神奇糖果（开局 +1 级 / 颗）、营养饮料（某一项努力值 +10 / 颗，上限 252），都买给图鉴里选中的那只；进化道具在局内商店买。招式、镜片、携带道具在上面另外几页。"))
		for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_TOWN_POKEMON):
			if int(rec["sale_status"]) == Catalog.SALE_REMOVED_BY_USER:
				continue   # 用户删除的 RARER_CANDY 不上架
			var cid := str(rec["source_id"])
			if cid == "TM_COMMON" or cid == "TM_GREAT" or cid == "TM_ULTRA":
				continue   # 在“招式”页
			if Shop.is_town_candy(cid):
				var cprice := Shop.price_at(cid, _candy_count)   # 每 10 颗单价翻倍
				var who := _candy_name if _candy_name != "" else "选中的宝可梦"
				var cdetail := "为「%s」买：开局每颗 +1 级 · %d 点/颗 · 已买 %d/%d 颗" % [who, cprice, _candy_count, Shop.CANDY_CAP]
				if not _candy_ok:
					cdetail = "先在图鉴里选一只已捕获的宝可梦，再来买（现在选中的还没捕获）"
				var can := _candy_ok and _candy_count < Shop.CANDY_CAP
				_list.add_child(_make_row(rec, can, cdetail, ("购买（%d 点）" % cprice) if can else ("已达上限" if _candy_ok else "先选宝可梦")))
				continue
			if cid == "BASE_STAT_BOOSTER":
				# 营养饮料：六项各一行（每颗这一项努力值 +10，上限 252，六项都能拉满）。
				for stat in 6:
					var did := "STAT_DRINK_%d" % stat
					var drec: Dictionary = rec.duplicate()
					drec["source_id"] = did
					drec["name_zh"] = str(Shop.display_name(did))
					var dprice := Shop.price(did)
					var have := int(_candy_evs[stat])
					var dwho := _candy_name if _candy_name != "" else "选中的宝可梦"
					var ddetail := "为「%s」买：%s 努力值 +10 · %d 点/颗 · 现在 %d/%d" % [dwho, str(Shop.STAT_NAMES[stat]), dprice, have, 252]
					if not _candy_ok:
						ddetail = "先在图鉴里选一只已捕获的宝可梦，再来买"
					var dcan := _candy_ok and have < 252
					_list.add_child(_make_row(drec, dcan, ddetail, ("购买（%d 点）" % dprice) if dcan else ("已满 252" if _candy_ok else "先选宝可梦")))
				continue
			_list.add_child(_make_row(rec, false, "尚未开放", "尚未开放"))
		return
	_list.add_child(_section_note("全体加成对所有宝可梦和新开的局都生效（照原版护符 / 道具）。"))
	var global_recs: Array = Catalog.by_placement(Catalog.PLACE_TOWN_GLOBAL)
	var listed := {}
	for rec: Dictionary in global_recs:
		listed[str(rec["source_id"])] = true
	for gid: String in Shop.GLOBAL_ORDER:   # 原目录里放在“以后再说”的几样，这里补进来
		if not listed.has(gid) and not Catalog.by_source_id(gid).is_empty():
			global_recs.append(Catalog.by_source_id(gid)[0])
	for rec: Dictionary in global_recs:
		var id := str(rec["source_id"])
		if Shop.exp_banned(id):
			continue   # 经验加成已禁（2026-10-25），整行不显示
		if Shop.is_purchasable(id):
			var cap := Shop.max_stacks(id)
			var owned := int(_owned.get(id, 0))
			var price := Shop.price_at(id, owned)   # 糖果罐每 10 层单价翻倍
			var detail: String
			if Shop.is_global_charm(id):
				detail = "%s · 已买 %d/%d · %d 点/层" % [Shop.global_desc(id), owned, cap, price]
			elif Shop.is_healing_charm(id):
				detail = "每层 +10%%：普通回血按原一般治疗取整；伤药只加固定回复分支，不乘百分比分支 · 已买 %d/%d · %d 点/层" % [owned, cap, price]
			else:
				detail = "每层 +%d%% 经验 · 已买 %d/%d · %d 点/层" % [Shop.boost_percent(id), owned, cap, price]
			var can_buy := owned < cap
			var text := ("购买（%d 点）" % price) if can_buy else "已满级"
			_list.add_child(_make_row(rec, can_buy, detail, text))
		else:
			_list.add_child(_make_row(rec, false, "尚未开放", "尚未开放"))


# 中文分类 + 稀有度；分类没有中文名时只显示稀有度，绝不回退成英文 slug。
func _tag_text(rec: Dictionary) -> String:
	if rec.has("tag_zh"):   # 借伤药底板的行（记忆蘑菇 / 树果…）自己给标签，不显示“伤药”
		return str(rec["tag_zh"])
	var parts: Array = []
	var cat := str(CATEGORY_ZH.get(str(rec["category"]), ""))
	if cat != "":
		parts.append(cat)
	var tier := str(TIER_ZH.get(int(rec["tier"]), ""))
	if tier != "":
		parts.append(tier)
	return " · ".join(parts)


func _section_note(text: String) -> Control:
	var label := RogueSkin.label(text, RogueSkin.SIZE_SMALL, "summary_gray", true)
	label.custom_minimum_size = Vector2(0, 24)
	return label


func _make_row(rec: Dictionary, enabled: bool, detail: String, button_text: String) -> Control:
	var id := str(rec["source_id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 76)
	card.add_theme_stylebox_override("panel", RogueSkin.box(2 if enabled else 5, "_thin", 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(RogueSkin.label(str(rec["name_zh"]), RogueSkin.SIZE_BODY, "summary_gold"))
	name_row.add_child(RogueSkin.label(_tag_text(rec), RogueSkin.SIZE_SMALL, "summary_gray"))
	col.add_child(name_row)
	var det := RogueSkin.label(detail, RogueSkin.SIZE_SMALL, "window" if enabled else "summary_gray", true)
	col.add_child(det)
	# 招式行：属性 / 分类 / 威力 / 命中 / 冷却 + 招式说明（rec["info"]，没有就不画）。
	var info := str(rec.get("info", ""))
	if info != "":
		col.add_child(RogueSkin.label(info, RogueSkin.SIZE_SMALL, "summary_blue", true))

	var btn := RogueSkin.button(button_text, RogueSkin.SIZE_SMALL, Vector2(200, 48), enabled, "gold" if enabled else "teal")
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not enabled
	if enabled:
		btn.pressed.connect(func(): purchase_pressed.emit(id))
	row.add_child(btn)
	_buttons[id] = btn
	return card


# 招式的详细说明（商店 / 起始页共用）：属性·分类 / 威力 / 命中 / 冷却，下面接原作的招式描述。
static func move_info(move_id: String) -> String:
	var m: Dictionary = PokemonMoves.MOVES.get(move_id, {})
	if m.is_empty():
		return ""
	var power := int(m.get("power", 0))
	var acc := int(m.get("accuracy", 100))
	return "%s · %s · %s　威力 %s　命中 %s　PP %d　冷却 %.1f 秒\n%s" % [str(m.get("type", "")), str(m.get("category", "")), PokemonMoves.target_text(m), str(power) if power > 0 else "—", str(acc) if acc > 0 else "必中", MovePP.move_pp(move_id, 0), MovePP.move_cd(move_id, 0), preload("res://game/pokemon_move_roles.gd").desc_with_note(move_id)]


# 技能机器：选中宝可梦能学的招（按档位 → 招式 id 排）各一行。没买 = 购买（原档位点价）；买过 = 带上 / 取下（免费，
# 开局招式槽 4 个 = 开局招 + 带着的机器）。
func _add_tm_rows() -> void:
	var TM := preload("res://game/pokemon_tm.gd")
	var Moves := preload("res://data/pokemon_moves.gd")
	var learnable: Array = _tm_info.get("learnable", [])
	var owned: Array = _tm_info.get("owned", [])
	var equipped: Array = _tm_info.get("equipped", [])
	var move_slots := int(_tm_info.get("move_slots", 4))
	var who := _candy_name if _candy_name != "" else "选中的宝可梦"
	_list.add_child(_section_note("技能机器（买给「%s」，买一次永久拥有；开局最多带 %d 个招，开局招和机器一起算，点一下带上 / 取下；有空位时买了就带上）" % [who, move_slots]))
	_add_starter_rows()
	if learnable.is_empty():
		_list.add_child(_section_note("「%s」在本作已接战斗的招里没有能学的技能机器。" % who))
		return
	var tier_rec := {}
	for rec: Dictionary in Catalog.by_placement(Catalog.PLACE_TOWN_POKEMON):
		tier_rec[str(rec["source_id"])] = rec
	for mv in learnable:
		var move := str(mv)
		var tier := TM.tier_of(move)
		var base_rec: Dictionary = (tier_rec.get("TM_" + tier, {}) as Dictionary).duplicate()
		if base_rec.is_empty():
			continue
		var pid := TM.product_id(move)
		var mname := str(Moves.MOVES[move]["name"]) if Moves.MOVES.has(move) else move
		base_rec["source_id"] = pid
		base_rec["name_zh"] = "技能机器·%s" % mname
		base_rec["info"] = move_info(move)
		var cost := TM.price(move)
		var is_owned := owned.has(move)
		# 带没带只看开局真正带的招（carried）；旧的机器装备表（equipped）会和它对不上——显示“选了带”开局却没带（2026-10-25）
		var carried_list: Array = _tm_info.get("carried", equipped)
		var full := carried_list.size() >= move_slots
		var is_on := carried_list.has(move)
		var detail: String
		var btn_text: String
		var can: bool
		if not _candy_ok:
			detail = "先在图鉴里选一只已捕获的宝可梦，再来买"
			btn_text = "先选宝可梦"
			can = false
		elif not is_owned:
			var bump := ""   # 栏满时会被顶掉的开局招（机器优先）
			for cm in carried_list:
				if not owned.has(cm):
					bump = str(Moves.MOVES[str(cm)]["name"]) if Moves.MOVES.has(str(cm)) else str(cm)
					break
			var how := " · 有空位，买了就带上"
			if full:
				how = (" · 买了就带上，换下开局招「%s」" % bump) if bump != "" else " · 招式栏满了：买了先放着，取下一招再带上"
			detail = "%s档 · %d 点（买一次永久拥有）%s" % [str(TM.TIER_ZH.get(tier, "")), cost, how]
			btn_text = "购买（%d 点）" % cost
			can = true
		elif is_on:
			detail = "已拥有 · 开局带着"
			btn_text = "取下"
			can = true
		else:
			detail = "已拥有 · 开局没带" + ("" if not full else "（招式栏满了，先取下一招）")
			btn_text = "带上"
			can = not full
		_list.add_child(_make_row(base_rec, can, detail, btn_text))


# 开局招：每个一行，点一下留在家里 / 带上（免费）。留在家里的招开局不带，腾出的槽可以带技能机器。
func _add_starter_rows() -> void:
	var Moves := preload("res://data/pokemon_moves.gd")
	var starters: Array = _tm_info.get("starters", [])
	if starters.is_empty() or not _candy_ok:
		return
	_list.add_child(_section_note("开局招（融合了两只的都算；按顺序填机器剩下的槽，点「留在家里」就跳过它、让后面的上）"))
	for st: Dictionary in starters:
		var move := str(st["id"])
		var benched := bool(st.get("benched", false))
		var rec := {"source_id": "STARTER:" + move, "name_zh": "开局招·%s" % (str(Moves.MOVES[move]["name"]) if Moves.MOVES.has(move) else move), "category": "tm", "tier": -1, "info": move_info(move)}
		var detail := "留在家里，开局不带" if benched else ("开局带着" if bool(st.get("carried", true)) else "槽满了，这次没带上")
		_list.add_child(_make_row(rec, true, detail, "带上" if benched else "留在家里"))


# ================= 搭界面 =================

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_town_bg = bg
	_root.add_child(_town_bg)

	var dim := ColorRect.new()
	dim.color = Color(BACKDROP, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_dim = dim

	# A 区（左侧，用户 2026-10-17）：局内商店里放我们的球，点一种就收起商店去选区域、投出即恢复游戏。
	_build_ball_panel()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_center = center

	_holder = PanelContainer.new()
	_holder.custom_minimum_size = Vector2(1060, 640)
	_holder.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 10))
	center.add_child(_holder)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(header)
	_title = RogueSkin.label("商店", RogueSkin.SIZE_TITLE, "summary_gold")
	header.add_child(_title)
	_points_label = RogueSkin.label("点数 0", RogueSkin.SIZE_BODY, "summary_gold")
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_points_label)

	_sub_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "summary_gray", true)
	col.add_child(_sub_label)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tab_bar)
	for spec in [["global", "全体加成"], ["single", "单只培养"]]:
		var b := RogueSkin.button(str(spec[1]), RogueSkin.SIZE_BODY, Vector2(180, 48))
		b.pressed.connect(_on_track.bind(str(spec[0])))
		_tab_bar.add_child(b)
		_tab_buttons[str(spec[0])] = b

	_run_tab_bar = HBoxContainer.new()
	_run_tab_bar.add_theme_constant_override("separation", 6)
	_run_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_run_tab_bar)
	for spec in [["ball", "精灵球"], ["heal", "回复"], ["berry", "树果"], ["memory", "记忆蘑菇"], ["evo", "进化"]]:   # 记忆蘑菇单开一页（用户 2026-10-21）
		var rb := RogueSkin.button(str(spec[1]), RogueSkin.SIZE_BODY, Vector2(150, 48))
		rb.pressed.connect(_on_run_tab.bind(str(spec[0])))
		_run_tab_bar.add_child(rb)
		_run_tab_buttons[str(spec[0])] = rb

	_single_tab_bar = HBoxContainer.new()
	_single_tab_bar.add_theme_constant_override("separation", 6)
	_single_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_single_tab_bar)
	for spec in [["grow", "成长"], ["moves", "招式"], ["lens", "镜片"], ["held", "携带道具"]]:
		var sb := RogueSkin.button(str(spec[1]), RogueSkin.SIZE_SMALL, Vector2(130, 40))
		sb.pressed.connect(_on_single_tab.bind(str(spec[0])))
		_single_tab_bar.add_child(sb)
		_single_tab_buttons[str(spec[0])] = sb

	_message_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "summary_blue", true)
	_message_label.custom_minimum_size = Vector2(0, 24)
	col.add_child(_message_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(footer)
	_close_btn = RogueSkin.button("关闭（Esc）", RogueSkin.SIZE_BODY, Vector2(220, 52))
	_close_btn.pressed.connect(_on_close)
	footer.add_child(_close_btn)
	_back_btn = RogueSkin.button("返回抓宠（Esc）", RogueSkin.SIZE_BODY, Vector2(260, 52), true, "gold")
	_back_btn.pressed.connect(func(): back_pressed.emit())
	footer.add_child(_back_btn)
	_resume_btn = RogueSkin.button("继续游戏", RogueSkin.SIZE_BODY, Vector2(180, 52))
	_resume_btn.pressed.connect(func(): resume_pressed.emit())
	footer.add_child(_resume_btn)
	_settings_btn = RogueSkin.button("设置", RogueSkin.SIZE_BODY, Vector2(120, 52))
	_settings_btn.pressed.connect(func(): settings_pressed.emit())
	footer.add_child(_settings_btn)
	_abandon_btn = RogueSkin.button("放弃这一局（已保存点数保留）", RogueSkin.SIZE_SMALL, Vector2(340, 52), true, "red")
	_abandon_btn.pressed.connect(func(): abandon_pressed.emit())
	footer.add_child(_abandon_btn)


func _on_track(track: String) -> void:
	var next := "single" if track == "single" else "global"
	if next == _track:
		return
	_track = next
	_refresh()


func _on_close() -> void:
	close()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _mode == "run":
		var hot: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5].find(event.physical_keycode)
		if hot < 0:
			hot = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5].find(event.physical_keycode)
		if hot >= 0:
			get_viewport().set_input_as_handled()
			_on_ball_button(hot)
			return
	if event.physical_keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _mode == "run":
		back_pressed.emit()
	else:
		_on_close()
