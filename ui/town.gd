extends CanvasLayer
# 城镇准备页（2026-10-15 图鉴选角轮）：左窄栏从上到下 A 图片 / B 基础属性 / C 技能，
# 右侧大页签「图鉴 / 地图」，底部出发栏。样式沿用 ui/hud.gd 已移植的暖墨漆框。
#
# 本页只做展示、图鉴浏览和导航，不新建成长 / 解锁 / 存档系统：
#   - A 图片：绿毛虫用 setup 传入的真实 portrait；其他物种用既有 caterpie 视觉读原图集首帧，
#             读不到再退回 Pokedex.icon；缺图如实占位；
#   - B 属性：84 表内物种按 game/pokemon_growth.gd 的原作公式显示 1 级六项（IV0 / 中性性格占位），
#             并区分原作「速度」和本作移速 / 攻速；84 表外仍只读原作六种族值；
#   - C 技能：列出该物种**真正会带入**的原初始招（最多 4，源默认前 4 / 去重）；未实现的源表
#             初始招只作资料浏览并标「招式准备中」，不拿别的招冒充；
#   - D 图鉴：data/pokedex.gd 全 1025 行 + 8128 地区条目，图标 + 编号 + 中文名 + 状态，每页 40 项、
#             8 列，可按编号 / 中文名搜索、按世代筛选、翻页；点条目只更新左栏，不改战斗；
#   - 地图页沿用 data/biomes.gd 35 个地区（旧城镇页，正常窗口用 ui/rogue_starter.gd）；
#   - 出发：#0010 绿毛虫默认可选；其它必须准确 ID 已在钱包 [collection] 持久解锁且初始招已准备好
#     （game/pokemon_starters.gd::is_ready）。出发按钮和键盘 Enter / Space 都走同一个 can_depart()
#     校验；main.gd 出发接线会再独立读一次最新钱包校验，防止绕过 disabled / 缓存 caught。
#
# 用法：
#   page.setup(portrait_texture, unit_dict)   # unit_dict = data/units.gd 里主角那一行
#   page.set_collection(caught_ids)           # 钱包 [collection] caught 的深副本（只读）
#   page.depart_pressed.connect(...); page.title_pressed.connect(...)
#   page.open_skills() / page.open_overview() / page.open_map() / page.close()
#   page.selected_map_id() / page.selected_pokemon_id() / page.can_depart()
#   page.set_points(total)   右上角显示持久击杀点数（余额由 main 传入，本页不读档）

signal depart_pressed
signal title_pressed
signal shop_pressed     # 局外商店入口（商店页面由 main 打开，本页只发信号）

const Hud := preload("res://ui/hud.gd")
const PokemonMoves := preload("res://data/pokemon_moves.gd")
const Biomes := preload("res://data/biomes.gd")
# 图鉴数据由另一条并行任务产出（data/pokedex.gd）。本文件只按接口调用，不在此副本造 stub。
const Pokedex := preload("res://data/pokedex.gd")
const PokemonGrowth := preload("res://game/pokemon_growth.gd")
# 真实选角第一批：起始招 / 准备门槛 / 准确物种资料的唯一小 helper（只读 84 原表 + 14 实现）。
const PokemonStarters := preload("res://game/pokemon_starters.gd")
# 全国图鉴 1025 范围外的地区 ID（如 8128 肯泰罗帕底亚）用当前 WildSpecies 准确资料追加条目。
const WildSpecies := preload("res://data/pokemon_wild_species.gd")
# 只为借既有 set_species(10/11/12) / set_wild_species(id,0) / portrait_texture 读原图集；
# 不造图片加载器 / renderer / 新素材，实例取到 Texture 后立刻 free。
const CaterpieVisual := preload("res://characters/caterpie.gd")
# 本轮没有个体值 / 性格系统：城镇 B 展示 1 级六项时用 game/pokemon_growth.gd 的默认占位
# （IV 全 0、性格中性 id 0），和 main/state.gd 实际出发是同一来源，避免显示 / 实际两套数字。

# 设计尺寸：1280x720 的窗口里正好不缩放地放下；更小的窗口由 fit_page 整体等比缩放。
const DESIGN := Vector2(1280, 720)
const HERO_PANEL_WIDTH := 300
const HERO_PORTRAIT_HEIGHT := 132   # A 图片的固定上限高度，避免旧版无限 EXPAND 撑出巨型空白
const DEFAULT_POKEMON_ID := 10      # #0010 绿毛虫
# 全国图鉴 1025 范围外的地区条目：8128 PALDEA_TAUROS（肯泰罗帕底亚，原地区 ID，不并 128）。
const REGION_ENTRY_ID := 8128
const REGION_ENTRY_GENERATION := 9  # 原 newY 的世代依据：第 9 世代地区形态。
const PAGE_SIZE := 40               # 每页 40 项，避免一次造 1025 个节点
const GRID_COLUMNS := 8

const TYPE_COLORS := {
	"一般": Color(0.74, 0.72, 0.66, 1.0),
	"虫": Color(0.58, 0.80, 0.42, 1.0),
}
const CATEGORY_COLORS := {
	"物理": Color(0.82, 0.42, 0.34, 1.0),
	"变化": Color(0.50, 0.64, 0.88, 1.0),
}

var _root: Control
var _content: VBoxContainer
var _tab_bar: HBoxContainer
var _tab_buttons := {}
var _hero_number: Label
var _hero_name: Label
var _hero_types: Label
var _portrait_rect: TextureRect
var _missing_label: Label
var _stat_head: Label
var _stat_grid: GridContainer
var _stat_note: Label
var _skills_scroll: ScrollContainer
var _skills_box: VBoxContainer
var _depart_btn: Button
var _back_btn: Button
var _shop_btn: Button
var _depart_target: Label
var _depart_selected: Label
# 城镇右上角显示的持久击杀点数（main.gd 从同一份余额 set_points 进来；本页只显示，不自己读档）。
var _points_label: Label
var _points_total := 0
var _selected_map_id := Biomes.DEFAULT_ID
var _map_buttons := {}
var _selected_entry_level := 0   # 入场等级（0 = 地区起点）；神奇糖果让开局等级很高时，从高等级的怪开始打
var _entry_option: OptionButton = null
var start_level_provider: Callable = Callable()   # 宠物 ID -> 开局等级（1 + 神奇糖果）；入场等级按它限制上限

var _unit: Dictionary = {}
var _portrait_tex: Texture2D
var _tab := "pokedex"
var _collected_labels: Array = []
# 已持久解锁（[collection] caught）的准确 source_species_id 集合，由 main 传入钱包深副本。
# 本页只读这份副本判断 D 状态；出发后端会再独立读一次最新档，不信这里。
var _collection := {}
# 原图集立绘缓存（id -> Texture2D 或 null）；用既有 caterpie 视觉实例读，不新造加载器。
var _portrait_cache := {}
var _region_entry_added := false

# 图鉴浏览状态（与地图选择相互独立，切页都保留）
var _pokedex_all: Array = []
var _pokedex_page := 0
var _pokedex_query := ""
var _pokedex_gen := 0              # 0 = 全部世代
var _pokedex_status := 0           # 0 全部 / 1 可用 / 2 可用·已捕获 / 3 可用·未捕获（用户 2026-10-17：看开发进度）
var _selected_pokemon_id := DEFAULT_POKEMON_ID
var _search_edit: LineEdit
var _gen_option: OptionButton
# 百变怪（#132）出发前多一步：选它变成谁（用户 2026-10-16 定）；只在选中百变怪时显示。
var _ditto_option: OptionButton
var _ditto_target := 0
var _status_option: OptionButton
var _page_label: Label
var _prev_btn: Button
var _next_btn: Button
var _dex_grid: GridContainer
var _dex_buttons := {}             # id:int -> {"btn": Button, "name": Label}
var _dex_normal: StyleBox
var _dex_lit: StyleBox


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_pokedex_all = Pokedex.list()
	_append_region_entries()
	_build()


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_page)
	_fit_page()


func _fit_page() -> void:
	Hud.fit_page(_root, get_viewport().get_visible_rect().size, DESIGN)


# ================= 对外接口 =================

# portrait：主角像素立绘；unit：data/units.gd 里主角那一行（用它的基础数值）
func setup(portrait: Texture2D, unit: Dictionary) -> void:
	_unit = unit
	_portrait_tex = portrait
	_refresh_hero()
	_refresh_depart_state()


# 已捕获准确 ID 集合（钱包 [collection] caught 的深副本）：只读判断 D 状态 / 出发按钮。
# 传入数组被复制进本页字典，之后调用方改原数组 / 钱包都不会影响本页已收下的副本。
func set_collection(caught_ids) -> void:
	_collection = {}
	if caught_ids != null:
		for id in caught_ids:
			_collection[int(id)] = true
	_refresh_dex_page()
	_refresh_hero()
	_refresh_depart_state()


# 开局带着的技能机器（钱包 [tm] equipped 的只读副本：物种 ID -> [招式 id]）：C 区在开局招后面列出来。
var _tm_equipped := {}


func set_tm_equipped(equipped: Dictionary) -> void:
	_tm_equipped = equipped.duplicate(true)
	_refresh_hero()


# 持久击杀点数（所有宝可梦共用的余额）：只显示 main 传进来的数，本页不读档、不自己算。
func set_points(total: int) -> void:
	_points_total = maxi(0, int(total))
	if _points_label != null:
		_points_label.text = "点数 %d" % _points_total


func points_total() -> int:
	return _points_total


# 兼容入口：旧的总览 / 技能入口现在都打开图鉴页。
func open_skills() -> void:
	open("pokedex")


func open_overview() -> void:
	open("pokedex")


func open_map() -> void:
	open("map")


func open(tab := "pokedex") -> void:
	_tab = "map" if tab == "map" else "pokedex"
	_show_tab()
	visible = true
	_fit_page()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func current_tab() -> String:
	return _tab


# main.gd 的出发接线路：出发信号不带参数，目的地和上场宝可梦用这三个 getter 读。
func selected_map_id() -> String:
	return _selected_map_id


func selected_entry_level() -> int:
	return _selected_entry_level


func selected_map_name() -> String:
	return Biomes.name_of(_selected_map_id)


func selected_pokemon_id() -> int:
	return _selected_pokemon_id


# 百变怪变成谁（物种 ID）；没选百变怪时没有意义（返回 0）。
func selected_ditto_target() -> int:
	return _ditto_target if _selected_pokemon_id == PokemonStarters.DITTO_ID else 0


# 能否从本页出发：#10 默认始终可选；其它必须准确 ID 已持久解锁且招式已准备好。
# 出发按钮 / 键盘 Enter / main 接线都查这里；main 后端还会再独立读一次最新档校验。
func can_depart() -> bool:
	return _can_depart_id(_selected_pokemon_id)


func _can_depart_id(id: int) -> bool:
	if id == DEFAULT_POKEMON_ID:
		return true
	return _collection.has(id) and PokemonStarters.is_ready(id)


# D 每项 / 出发栏共用的中文状态：#10 默认、未知未开放、未捕获、已捕获但招式准备中、可上场。
func _entry_state(id: int) -> Dictionary:
	if id == DEFAULT_POKEMON_ID:
		return {"text": "默认", "color": Hud.TOWN_JADE}
	if not PokemonStarters.is_known(id):
		return {"text": "未开放", "color": Hud.TOWN_MUTED}
	if not _collection.has(id):
		return {"text": "未捕获", "color": Hud.TOWN_MUTED}
	if not PokemonStarters.is_ready(id):
		return {"text": "招式准备中", "color": Hud.TOWN_MUTED}
	return {"text": "可上场", "color": Hud.TOWN_JADE}


# 技能页（现为左栏 C 区）列出的技能名（按 data/pokemon_moves.gd 的顺序）
func skill_names() -> Array:
	var out: Array = []
	for m: Dictionary in PokemonMoves.list():
		out.append(str(m["name"]))
	return out


# 当前可见界面上的所有 Label / Button 文字，验收时用来核对没有旧武侠词
func visible_labels() -> Array:
	_collected_labels = []
	_collect_labels(_root)
	return _collected_labels


func _collect_labels(node: Node) -> void:
	if node is Label or node is Button:
		if (node as CanvasItem).is_visible_in_tree():
			_collected_labels.append((node as Control).text)
	for c in node.get_children():
		_collect_labels(c)


# ================= 搭界面 =================

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_child(Hud.town_background())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_root.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)

	layout.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(body)
	body.add_child(_build_hero_panel())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	right.add_child(_build_tabs())

	_dex_normal = Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE, 1, 4, 6)
	_dex_lit = Hud.town_box(Hud.TOWN_GOLD, Hud.TOWN_GOLD, 2, 4, 6)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_content)

	layout.add_child(_build_departure_bar())


func _build_header() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(Hud.town_label("城镇", 30, Hud.TOWN_GOLD))
	var hint := Hud.town_label("选好上场的宝可梦和目的地，再出发。", 14, Hud.TOWN_MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	hint.clip_text = true
	head.add_child(hint)
	# 持久击杀点数：右上角一行，不占图鉴 / 地图 / 出发栏的位置。
	_points_label = Hud.town_label("点数 0", 18, Hud.TOWN_GOLD)
	_points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_points_label)
	return head


# 左窄栏：A 图片（固定高度上限）、B 基础属性、C 技能（小范围滚动），三区始终显示。
func _build_hero_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(HERO_PANEL_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Hud.town_box(Hud.TOWN_PANEL, Hud.TOWN_LINE, 1, 4, 12))
	# 左栏内容比 720 高（立绘 + B + C）：整栏套一层竖向滚动，保证底部出发栏（商店 / 返回标题 /
	# 开始冒险）在 1280x720 里完整可点，A / B / C 结构与内容都不动。
	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_scroll.custom_minimum_size = Vector2(0, 160)
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(hero_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	hero_scroll.add_child(box)

	# ---- A 图片 ----
	box.add_child(_section_title("A · 图片"))
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, HERO_PORTRAIT_HEIGHT)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 不再 EXPAND，杜绝巨型空白
	frame.add_theme_stylebox_override("panel", Hud.town_box(Color(0.07, 0.065, 0.06, 1.0), Hud.TOWN_LINE, 1, 4, 6))
	box.add_child(frame)
	_portrait_rect = TextureRect.new()
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_portrait_rect)
	_missing_label = Hud.town_label("（缺图）", 14, Hud.TOWN_MUTED)
	_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(_missing_label)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_number = Hud.town_label("#----", 14, Hud.TOWN_GOLD)
	_hero_number.custom_minimum_size = Vector2(52, 0)
	name_row.add_child(_hero_number)
	_hero_name = Hud.town_label("绿毛虫", 19, Hud.TOWN_PAPER)
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_name.clip_text = true
	name_row.add_child(_hero_name)
	box.add_child(name_row)
	_hero_types = Hud.town_label("", 12, Hud.TOWN_MUTED)
	box.add_child(_hero_types)

	# ---- B 基础属性 ----
	box.add_child(_section_title("B · 基础属性"))
	_stat_head = Hud.town_label("本作单位表", 12, Hud.TOWN_MUTED)
	box.add_child(_stat_head)
	_stat_grid = GridContainer.new()
	_stat_grid.columns = 2
	_stat_grid.add_theme_constant_override("h_separation", 6)
	_stat_grid.add_theme_constant_override("v_separation", 4)
	_stat_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_stat_grid)
	_stat_note = Hud.town_label("", 11, Hud.TOWN_MUTED, true)
	box.add_child(_stat_note)

	# ---- C 技能 ----
	box.add_child(_section_title("C · 技能"))
	_skills_scroll = ScrollContainer.new()
	_skills_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_scroll.custom_minimum_size = Vector2(0, 72)
	_skills_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_skills_scroll)
	_skills_box = VBoxContainer.new()
	_skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_box.add_theme_constant_override("separation", 6)
	_skills_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skills_scroll.add_child(_skills_box)
	return panel


func _build_tabs() -> Control:
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for tab in ["pokedex", "map"]:
		var label := "图鉴" if tab == "pokedex" else "地图"
		var b := Hud.hanb_button(label, 18, Vector2(140, 42), false, Hud.TOWN_GOLD)
		b.pressed.connect(_on_tab.bind(tab))
		_tab_bar.add_child(b)
		_tab_buttons[tab] = b
	return _tab_bar


func _on_tab(tab: String) -> void:
	if tab == _tab:
		return
	_tab = "map" if tab == "map" else "pokedex"
	_show_tab()


func _show_tab() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	for tab: String in _tab_buttons:
		var on: bool = tab == _tab
		var b: Button = _tab_buttons[tab]
		b.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_GOLD if on else Hud.TOWN_PANEL_RAISED, Hud.TOWN_GOLD, 1, 4, 8))
		b.add_theme_color_override("font_color", Hud.TOWN_INK if on else Hud.TOWN_GOLD.lightened(0.15))
		b.add_theme_color_override("font_hover_color", Hud.TOWN_INK if on else Hud.TOWN_PAPER)
		b.add_theme_stylebox_override("hover", Hud.town_box(Hud.TOWN_GOLD.lightened(0.12) if on else Hud.TOWN_GOLD.darkened(0.55), Hud.TOWN_GOLD.lightened(0.2), 1, 4, 8))
	if _tab == "map":
		_build_map()
	else:
		_build_pokedex()


func _section_title(title: String, note := "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Hud.town_label(title, 16, Hud.TOWN_GOLD))
	if note != "":
		var n := Hud.town_label(note, 12, Hud.TOWN_MUTED)
		n.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(n)
	return row


# ================= 左栏 A / B / C 刷新 =================

func _refresh_hero() -> void:
	var id := _selected_pokemon_id
	var prof := PokemonStarters.profile(id)
	var entry := Pokedex.entry(id)
	var display_name := str(prof.get("name", "")) if not prof.is_empty() else ""
	if display_name == "":
		display_name = str(entry.get("name", ""))
	if display_name == "" and id == DEFAULT_POKEMON_ID:
		display_name = str(_unit.get("name", "绿毛虫"))
	if display_name == "":
		display_name = "未知"
	_hero_number.text = "#%04d" % id
	_hero_name.text = display_name
	var types: Array = prof.get("types", []) if not prof.is_empty() else entry.get("types", [])
	var type_text := "属性：" + " / ".join(types) if not types.is_empty() else ""
	_hero_types.text = type_text
	_hero_types.visible = type_text != ""

	# A 图片：优先读原图集（内置 10/11/12 或平原原图集）；没有再退回图鉴缩略图；都没有就占位。
	var tex: Texture2D = _portrait_for(id)
	_portrait_rect.texture = tex
	_portrait_rect.visible = tex != null
	_missing_label.visible = tex == null

	_refresh_stats(prof, entry)
	_refresh_skills(prof)


# A 区立绘：绿毛虫沿用 setup 传入的真实 portrait；其余用既有 caterpie 视觉实例读原图集，
# 读不到再退回 Pokedex.icon；未知物种不碰 sprite 加载（避免断言 / ERROR）。
func _portrait_for(id: int) -> Texture2D:
	if id == DEFAULT_POKEMON_ID and _portrait_tex != null:
		return _portrait_tex
	var atlas := _atlas_portrait(id)
	if atlas != null:
		return atlas
	return Pokedex.icon(id)


# 用既有 characters/caterpie.gd 读某物种 front 首帧（原图集）；没有该图集返回 null。
# 实例只用来取 Texture，取完立刻 free；不新增图片加载器 / renderer / 素材。
func _atlas_portrait(id: int) -> Texture2D:
	if _portrait_cache.has(id):
		return _portrait_cache[id]
	var tex: Texture2D = null
	var prof := PokemonStarters.profile(id)
	var mode := str(prof.get("sprite", "none")) if not prof.is_empty() else "none"
	if mode == "builtin" or mode == "wild":
		var vis = CaterpieVisual.new()
		if vis != null:
			if mode == "builtin":
				vis.set_species(id)
			elif _wild_atlas_ready(id):
				vis.set_wild_species(id, 0)
			tex = vis.portrait_texture()
			vis.free()
	_portrait_cache[id] = tex
	return tex


func _wild_atlas_ready(id: int) -> bool:
	if not WildSpecies.has_species(id):
		return false
	var form := WildSpecies.form_at(id, 0)
	var key := str(form.get("sprite_key", ""))
	return not WildSpecies.atlas_entry(id, key, "front").is_empty() \
		and not WildSpecies.atlas_entry(id, key, "back").is_empty()


# D 网格缩略图：图鉴缩略图优先（<=1025），没有再用原图集（8128 地区条目）。
func _dex_icon(id: int) -> Texture2D:
	var tex := Pokedex.icon(id)
	if tex != null:
		return tex
	return _atlas_portrait(id)


func _refresh_stats(prof: Dictionary, entry: Dictionary) -> void:
	for child in _stat_grid.get_children():
		_stat_grid.remove_child(child)
		child.queue_free()
	# 已知可上场物种（84 表内）：B 预览与实际出发同一原公式、同默认 IV0 / 中性性格、1 级六项。
	if not prof.is_empty():
		_stat_head.text = "属性（按 1 级计算）"
		var nature: Array = PokemonGrowth.nature_multipliers(PokemonGrowth.DEFAULT_NATURE_ID)
		var six: Array = PokemonGrowth.calculate_stats(prof.get("base_stats", []), 1,
			PokemonGrowth.DEFAULT_IVS, nature)
		var captions := ["生命", "攻击", "防御", "特攻", "特防", "速度（原作属性）"]
		for i in captions.size():
			var value := str(six[i]) if i < six.size() else "—"
			_stat_grid.add_child(_stat_cell(captions[i], value))
		_stat_note.text = "属性按 1 级计算；个体值 0、性格中性。第六项是原作速度属性，本作移速 %s 米/秒、攻速 %s。" % [_num(_unit.get("speed", 0.0)), _num(_unit.get("aspd", 0.0))]
		return
	_stat_head.text = "原作种族值（图鉴资料）"
	var captions := ["生命", "攻击", "防御", "特攻", "特防", "速度"]
	var stats: Array = entry.get("stats", [])
	for i in captions.size():
		var value := "—"
		if i < stats.size():
			value = str(int(stats[i]))
		_stat_grid.add_child(_stat_cell(captions[i], value))
	_stat_note.text = "这只宝可梦还没开放上场，这里只显示图鉴资料。"


func _refresh_skills(prof: Dictionary) -> void:
	for child in _skills_box.get_children():
		_skills_box.remove_child(child)
		child.queue_free()
	# 84 表外（未知 / 未开放）：只说明尚未开放，不套绿毛虫招式、不露内部键。
	if prof.is_empty():
		_skills_box.add_child(Hud.town_label("尚未开放", 15, Hud.TOWN_MUTED))
		_skills_box.add_child(Hud.town_label("这只宝可梦还没开放上场。", 12, Hud.TOWN_MUTED, true))
		return
	# C 区列出**真正会带入**的原初始招（最多 4，源默认前 4 / 去重）。
	var before: Array = prof.get("initial_moves", [])
	if before.is_empty():
		_skills_box.add_child(Hud.town_label("这只宝可梦还没有可带入的初始招。", 13, Hud.TOWN_MUTED, true))
		return
	for move_id in before:
		var mid := str(move_id)
		var row: Dictionary = PokemonMoves.MOVES.get(mid, {})
		if row.is_empty() or PokemonMoves.is_sealed(mid):
			_skills_box.add_child(_sealed_skill_card(mid))
		else:
			_skills_box.add_child(_make_skill_card(row))
	# 局外商店买的技能机器：开局招后面再列带着的（开局招式槽 4 个 = 开局招 + 带着的机器）。
	var carried: Array = _tm_equipped.get(_selected_pokemon_id, [])
	if not carried.is_empty():
		_skills_box.add_child(Hud.town_label("带着的技能机器", 13, Hud.TOWN_GOLD))
		for move_id in carried:
			var trow: Dictionary = PokemonMoves.MOVES.get(str(move_id), {})
			if not trow.is_empty():
				_skills_box.add_child(_make_skill_card(trow))
	if not bool(prof.get("ready", false)):
		_skills_box.add_child(Hud.town_label("招式准备中：可用的初始招里还没有能造成伤害的招式，暂时不能上场。", 12, Hud.TOWN_MUTED, true))


# 封印招：原表初始招里有、本作暂时没有释放实现的招——显示它的官方中文名和“未开放”，
# 不能选进招式槽、开局不带；宠物本身照常开放（用户 2026-10-16 定）。
func _sealed_skill_card(move_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE.darkened(0.3), 1, 4, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(Hud.town_label(PokemonMoves.display_name(move_id), 15, Hud.TOWN_MUTED))
	top.add_child(_pill("未开放", Hud.TOWN_MUTED))
	col.add_child(Hud.town_label("这招暂时还没做，开局不会带上。", 12, Hud.TOWN_MUTED, true))
	return card


func _make_skill_card(move: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE, 1, 4, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(Hud.town_label(str(move["name"]), 15, Hud.TOWN_GOLD))
	top.add_child(_pill(str(move["type"]), TYPE_COLORS.get(str(move["type"]), Hud.TOWN_MUTED)))
	top.add_child(_pill(str(move["category"]), CATEGORY_COLORS.get(str(move["category"]), Hud.TOWN_MUTED)))
	# 原作招式数据：威力变化招显示“—”；命中 / PP 照原作值（PP 仅展示，本作不消耗）。
	col.add_child(Hud.town_label("威力 %s · 命中 %s · PP %d" % [
		PokemonMoves.power_text(move), PokemonMoves.accuracy_text(move), int(move["pp"])], 11, Hud.TOWN_MUTED))
	col.add_child(Hud.town_label(str(move["desc"]), 12, Hud.TOWN_PAPER, true))
	return card


func _stat_cell(caption: String, value: String) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_stylebox_override("panel", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE.darkened(0.25), 1, 3, 5))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row)
	var cap := Hud.town_label(caption, 12, Hud.TOWN_MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	row.add_child(Hud.town_label(value, 13, Hud.TOWN_PAPER))
	return cell


# ================= D 图鉴页 =================

func _build_pokedex() -> void:
	_content.add_child(_section_title("D · 图鉴", "共 %d 只；选一只查看左栏" % _pokedex_all.size()))

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(controls)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "搜索编号 / 中文名"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.add_theme_font_size_override("font_size", 14)
	_search_edit.add_theme_color_override("font_color", Hud.TOWN_PAPER)
	_search_edit.add_theme_color_override("font_placeholder_color", Hud.TOWN_MUTED)
	_search_edit.add_theme_color_override("caret_color", Hud.TOWN_GOLD)
	_search_edit.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE, 1, 4, 6))
	_search_edit.add_theme_stylebox_override("focus", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_GOLD, 1, 4, 6))
	_search_edit.text_changed.connect(_on_search_changed)
	controls.add_child(_search_edit)

	_gen_option = OptionButton.new()
	_gen_option.add_theme_font_size_override("font_size", 14)
	_gen_option.add_theme_color_override("font_color", Hud.TOWN_PAPER)
	_gen_option.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE, 1, 4, 6))
	_gen_option.add_theme_stylebox_override("hover", Hud.town_box(Hud.TOWN_GOLD.darkened(0.55), Hud.TOWN_GOLD, 1, 4, 6))
	_gen_option.add_item("全部世代")
	for g in range(1, 10):
		_gen_option.add_item("第 %d 世代" % g)
	_gen_option.item_selected.connect(_on_gen_changed)
	controls.add_child(_gen_option)

	_status_option = OptionButton.new()
	_status_option.add_theme_font_size_override("font_size", 14)
	_status_option.add_theme_color_override("font_color", Hud.TOWN_PAPER)
	_status_option.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_LINE, 1, 4, 6))
	_status_option.add_theme_stylebox_override("hover", Hud.town_box(Hud.TOWN_GOLD.darkened(0.55), Hud.TOWN_GOLD, 1, 4, 6))
	for label in ["全部状态", "可用", "可用·已捕获", "可用·未捕获"]:
		_status_option.add_item(label)
	_status_option.item_selected.connect(_on_status_changed)
	controls.add_child(_status_option)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	_dex_grid = GridContainer.new()
	_dex_grid.columns = GRID_COLUMNS
	_dex_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dex_grid.add_theme_constant_override("h_separation", 8)
	_dex_grid.add_theme_constant_override("v_separation", 6)
	_dex_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_dex_grid)

	var page_row := HBoxContainer.new()
	page_row.add_theme_constant_override("separation", 10)
	page_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(page_row)
	_prev_btn = Hud.hanb_button("上一页", 14, Vector2(104, 34))
	_prev_btn.pressed.connect(func(): _change_page(-1))
	page_row.add_child(_prev_btn)
	_page_label = Hud.town_label("", 13, Hud.TOWN_PAPER)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_row.add_child(_page_label)
	_next_btn = Hud.hanb_button("下一页", 14, Vector2(104, 34))
	_next_btn.pressed.connect(func(): _change_page(1))
	page_row.add_child(_next_btn)

	_refresh_dex_page()


# 全国图鉴 1025 范围外的地区 ID：用当前 WildSpecies 准确资料追加一个地区条目（8128
# 肯泰罗帕底亚 / 格斗），不改 data/pokedex.json、不把 8128 合并成 128。元数据 generation 9 有原
# newY 依据；六维 / 属性和战斗取同一份 PokemonStarters.profile。
func _append_region_entries() -> void:
	if _region_entry_added:
		return
	_region_entry_added = true
	var prof := PokemonStarters.profile(REGION_ENTRY_ID)
	if prof.is_empty():
		return
	_pokedex_all.append({
		"id": REGION_ENTRY_ID,
		"name": str(prof.get("name", "")),
		"generation": REGION_ENTRY_GENERATION,
		"types": prof.get("types", []),
		"stats": prof.get("base_stats", []),
		"icon": "",
		"regional": true,
	})


func _filtered_pokedex() -> Array:
	var q := _pokedex_query.strip_edges()
	if q.begins_with("#"):
		q = q.substr(1)
	var out: Array = []
	for row: Dictionary in _pokedex_all:
		if _pokedex_gen > 0 and int(row.get("generation", 0)) != _pokedex_gen:
			continue
		if q != "" and not _pokedex_match(row, q):
			continue
		if not _status_match(int(row.get("id", 0))):
			continue
		out.append(row)
	return out


# 状态筛选：“可用”= 物种已开放且招式就绪（可上场的前提，不看是否捕获；默认 #10 算可用 + 已捕获）。
func _status_match(id: int) -> bool:
	if _pokedex_status == 0:
		return true
	var usable := id == DEFAULT_POKEMON_ID or (PokemonStarters.is_known(id) and PokemonStarters.is_ready(id))
	if not usable:
		return false
	var caught := id == DEFAULT_POKEMON_ID or _collection.has(id)
	match _pokedex_status:
		2:
			return caught
		3:
			return not caught
	return true


func _pokedex_match(row: Dictionary, q: String) -> bool:
	var id := int(row.get("id", 0))
	var num := str(id)
	var padded := "%04d" % id
	if q.is_valid_int():
		return num.begins_with(q) or padded.begins_with(q)
	var name := str(row.get("name", ""))
	return name.findn(q) >= 0 or num.begins_with(q)


func _page_count(total: int) -> int:
	return maxi(1, int(ceil(float(total) / float(PAGE_SIZE))))


func _change_page(delta: int) -> void:
	_pokedex_page = clampi(_pokedex_page + delta, 0, _page_count(_filtered_pokedex().size()) - 1)
	_refresh_dex_page()


func _on_search_changed(text: String) -> void:
	_pokedex_query = text
	_pokedex_page = 0
	_refresh_dex_page()


func _on_status_changed(index: int) -> void:
	_pokedex_status = index
	_pokedex_page = 0
	_refresh_dex_page()


func _on_gen_changed(index: int) -> void:
	_pokedex_gen = index
	_pokedex_page = 0
	_refresh_dex_page()


func _refresh_dex_page() -> void:
	if _dex_grid == null:
		return
	var rows := _filtered_pokedex()
	var pages := _page_count(rows.size())
	_pokedex_page = clampi(_pokedex_page, 0, pages - 1)
	for child in _dex_grid.get_children():
		_dex_grid.remove_child(child)
		child.queue_free()
	_dex_buttons = {}
	var start := _pokedex_page * PAGE_SIZE
	var end := mini(start + PAGE_SIZE, rows.size())
	for i in range(start, end):
		_dex_grid.add_child(_make_dex_entry(rows[i]))
	_page_label.text = "第 %d / %d 页 · 筛选 %d 只" % [_pokedex_page + 1, pages, rows.size()]
	_prev_btn.disabled = _pokedex_page <= 0
	_next_btn.disabled = _pokedex_page >= pages - 1
	_refresh_dex_highlight()


func _make_dex_entry(row: Dictionary) -> Control:
	var id := int(row.get("id", 0))
	var state := _entry_state(id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 50)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _dex_normal)
	btn.add_theme_stylebox_override("hover", _dex_lit)
	btn.add_theme_stylebox_override("pressed", _dex_lit)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_pokemon_pick.bind(id))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	btn.add_child(margin)
	var entry_box := HBoxContainer.new()
	entry_box.add_theme_constant_override("separation", 6)
	entry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(entry_box)

	var icon_tex := _dex_icon(id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_box.add_child(icon)
	else:
		var missing := Hud.town_label("缺图", 11, Hud.TOWN_MUTED)
		missing.custom_minimum_size = Vector2(36, 0)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		entry_box.add_child(missing)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_box.add_child(col)
	col.add_child(Hud.town_label("#%04d" % id, 10, Hud.TOWN_MUTED))
	var display_name := str(row.get("name", ""))
	if bool(row.get("regional", false)):
		display_name += "（地区）"
	var name_label := Hud.town_label(display_name, 13, Hud.TOWN_PAPER)
	name_label.clip_text = true
	col.add_child(name_label)
	var status := Hud.town_label(str(state["text"]), 9, state["color"])
	status.clip_text = true
	col.add_child(status)

	_dex_buttons[id] = {"btn": btn, "name": name_label}
	return btn


func _refresh_dex_highlight() -> void:
	for id: int in _dex_buttons:
		var ref: Dictionary = _dex_buttons[id]
		var on: bool = id == _selected_pokemon_id
		var btn: Button = ref["btn"]
		btn.add_theme_stylebox_override("normal", _dex_lit if on else _dex_normal)
		ref["name"].add_theme_color_override("font_color", Hud.TOWN_INK if on else Hud.TOWN_PAPER)


func _on_pokemon_pick(id: int) -> void:
	_selected_pokemon_id = id
	_refresh_entry_options()
	_refresh_dex_highlight()
	_refresh_hero()
	_refresh_depart_state()


# ================= 地图页（沿用上一轮功能）=================

func _build_map() -> void:
	var opened_n := 0
	for b0: Dictionary in Biomes.list():
		if bool(b0["opened"]):
			opened_n += 1
	_content.add_child(_section_title("选择地图", "共 %d 个地区；当前开放 %d 个（新地区先用平原的地面，素材到了再换）" % [Biomes.list().size(), opened_n]))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_map_buttons = {}
	for b: Dictionary in Biomes.list():
		var id := str(b["id"])
		var opened := bool(b["opened"])
		var btn := Hud.hanb_button(_map_button_text(b), 14, Vector2(0, 42))
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = not opened
		if opened:
			btn.pressed.connect(_on_map_pick.bind(id))
		grid.add_child(btn)
		_map_buttons[id] = btn
	_refresh_map_highlight()
	_content.add_child(_build_entry_row())
	_content.add_child(Hud.town_label("只有开放的地区能选中；未开放的地区暂不能进入。", 13, Hud.TOWN_MUTED))


# 入场等级：波次无尽，从哪个等级的怪开始打由这里选（默认 = 地区起点；高等级起手配神奇糖果）。
func _build_entry_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Hud.town_label("入场等级", 14, Hud.TOWN_PAPER))
	_entry_option = OptionButton.new()
	_entry_option.custom_minimum_size = Vector2(220, 40)
	_entry_option.add_theme_font_size_override("font_size", 14)
	_entry_option.add_theme_color_override("font_color", Hud.TOWN_PAPER)
	_entry_option.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_JADE, 1, 4, 6))
	_entry_option.add_theme_stylebox_override("hover", Hud.town_box(Hud.TOWN_GOLD.darkened(0.55), Hud.TOWN_GOLD, 1, 4, 6))
	_entry_option.item_selected.connect(_on_entry_pick)
	row.add_child(_entry_option)
	_refresh_entry_options()
	row.add_child(Hud.town_label("波次无尽：时间越久怪越强；敌人等级不会低于你等级的 70%", 13, Hud.TOWN_MUTED))
	return row


func _refresh_entry_options() -> void:
	if _entry_option == null or not is_instance_valid(_entry_option):
		return
	var start_level := int(start_level_provider.call(_selected_pokemon_id)) if start_level_provider.is_valid() else 0
	var levels: Array[int] = Biomes.entry_levels(_selected_map_id, start_level)
	if not levels.has(_selected_entry_level):
		_selected_entry_level = 0
	_entry_option.clear()
	for lv: int in levels:
		_entry_option.add_item("地区起点" if lv == 0 else "Lv.%d 的怪起手" % lv, lv)
		if lv == _selected_entry_level:
			_entry_option.select(_entry_option.item_count - 1)


func _on_entry_pick(index: int) -> void:
	_selected_entry_level = _entry_option.get_item_id(index)


func _map_button_text(biome: Dictionary) -> String:
	var biome_name := str(biome["name"])
	return biome_name if bool(biome["opened"]) else "%s（未开放）" % biome_name


func _on_map_pick(id: String) -> void:
	if not Biomes.is_opened(id):
		return
	_selected_map_id = id
	_refresh_map_highlight()
	_refresh_entry_options()
	_refresh_depart_target()


func _refresh_map_highlight() -> void:
	for id: String in _map_buttons:
		var btn: Button = _map_buttons[id]
		if btn.disabled:
			continue
		var on: bool = id == _selected_map_id
		btn.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_GOLD if on else Hud.TOWN_PANEL_RAISED, Hud.TOWN_GOLD, 2 if on else 1, 4, 8))
		btn.add_theme_color_override("font_color", Hud.TOWN_INK if on else Hud.TOWN_GOLD.lightened(0.15))
		btn.add_theme_color_override("font_hover_color", Hud.TOWN_INK if on else Hud.TOWN_PAPER)


func _refresh_depart_target() -> void:
	if _depart_target != null:
		_depart_target.text = "目的地：%s" % selected_map_name()


# 底部：当前选择的宝可梦 + 目的地平原；只有默认可选 / 已解锁且 ready 的物种能按出发。
func _refresh_depart_state() -> void:
	var id := _selected_pokemon_id
	var playable := can_depart()
	var state := _entry_state(id)
	var prof := PokemonStarters.profile(id)
	var entry := Pokedex.entry(id)
	var display_name := str(prof.get("name", "")) if not prof.is_empty() else str(entry.get("name", ""))
	if display_name == "" and id == DEFAULT_POKEMON_ID:
		display_name = str(_unit.get("name", "绿毛虫"))
	if display_name == "":
		display_name = "未知"
	if _depart_selected != null:
		_depart_selected.text = "宝可梦：#%04d %s · %s" % [id, display_name, str(state["text"])]
	if _ditto_option != null:
		_ditto_option.visible = id == PokemonStarters.DITTO_ID
	if _depart_btn != null:
		_depart_btn.disabled = not playable
		_depart_btn.text = "开始冒险" if playable else str(state["text"])


func _build_departure_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", Hud.town_box(Hud.TOWN_PANEL, Hud.TOWN_LINE, 1, 4, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var target := VBoxContainer.new()
	target.custom_minimum_size = Vector2(300, 0)
	target.add_theme_constant_override("separation", 2)
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(Hud.town_label("出发", 12, Hud.TOWN_MUTED))
	_depart_target = Hud.town_label("目的地：%s" % selected_map_name(), 18, Hud.TOWN_GOLD)
	_depart_target.clip_text = true
	target.add_child(_depart_target)
	row.add_child(target)

	_depart_selected = Hud.town_label("", 14, Hud.TOWN_PAPER)
	_depart_selected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depart_selected.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_depart_selected.clip_text = true
	row.add_child(_depart_selected)

	# 百变怪：变成谁（平原已准备好的物种；选好开局就定，整局不变）。
	_ditto_option = OptionButton.new()
	_ditto_option.custom_minimum_size = Vector2(200, 46)
	_ditto_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ditto_option.add_theme_font_size_override("font_size", 14)
	_ditto_option.add_theme_color_override("font_color", Hud.TOWN_PAPER)
	_ditto_option.add_theme_stylebox_override("normal", Hud.town_box(Hud.TOWN_PANEL_RAISED, Hud.TOWN_JADE, 1, 4, 6))
	_ditto_option.add_theme_stylebox_override("hover", Hud.town_box(Hud.TOWN_GOLD.darkened(0.55), Hud.TOWN_GOLD, 1, 4, 6))
	for tid in PokemonStarters.ditto_targets():
		var tprof := PokemonStarters.profile(int(tid))
		_ditto_option.add_item("变成：%s" % str(tprof.get("name", "#%d" % int(tid))), int(tid))
	if _ditto_option.item_count > 0:
		_ditto_target = _ditto_option.get_item_id(0)
	_ditto_option.item_selected.connect(func(index: int): _ditto_target = _ditto_option.get_item_id(index))
	_ditto_option.visible = false
	row.add_child(_ditto_option)

	var back := Hud.hanb_button("返回标题", 16, Vector2(130, 46))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): title_pressed.emit())
	row.add_child(back)
	_back_btn = back

	# 商店入口：不占图鉴 / 地图 / 左 ABC，放在出发栏；点开是独立的 ui/pokemon_shop.gd 局外商店。
	var shop := Hud.hanb_button("商店", 16, Vector2(110, 46), false, Hud.TOWN_JADE)
	shop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop.pressed.connect(func(): shop_pressed.emit())
	row.add_child(shop)
	_shop_btn = shop

	var depart := Hud.hanb_button("开始冒险", 20, Vector2(190, 48), true, Hud.TOWN_JADE)
	depart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	depart.pressed.connect(func(): depart_pressed.emit())
	row.add_child(depart)
	_depart_btn = depart
	return bar


func _pill(text: String, color: Color) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Hud.town_box(Color(color.r * 0.22, color.g * 0.22, color.b * 0.22, 0.92), color.darkened(0.25), 1, 3, 3, true)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	pill.add_theme_stylebox_override("panel", sb)
	pill.add_child(Hud.town_label(text, 13, color.lightened(0.2)))
	return pill


func _num(v) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, round(f)) else "%.2f" % f


# 键盘 Enter / Space 出发，但必须先过 can_depart()；搜索框有焦点时不抢键。
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if is_instance_valid(_search_edit) and _search_edit.has_focus():
		return
	if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		if can_depart():
			depart_pressed.emit()
