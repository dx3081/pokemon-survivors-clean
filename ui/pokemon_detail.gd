extends CanvasLayer
# 宠物详情页（用户 2026-10-18：“暂停界面放个技能的开关，这样子可以详细看精灵”）：暂停抓宠界面里点“宠物详情”打开，
# 看当前上场宠物的六维 / 特性 / 性格 / 每个招式的属性·分类·威力·命中·冷却和说明。只读展示，数据由 main 打包传进来。
# 样式用原版 Pokémon Rogue 的窗口 / 字体（ui/rogue_skin.gd）。Esc 或“关闭”收起，回到暂停抓宠界面。
signal closed

const Hud := preload("res://ui/hud.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")
const RogueUI := preload("res://ui/rogue_ui.gd")

const DESIGN := Vector2(1280, 720)
const BACKDROP := Color("14121c")
const STAT_NAMES := ["HP", "攻击", "防御", "特攻", "特防", "速度"]

var _root: Control
var _holder: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _close_btn: Button


func _init() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(BACKDROP, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_holder = PanelContainer.new()
	_holder.custom_minimum_size = Vector2(1060, 640)
	_holder.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 10))
	center.add_child(_holder)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_holder.add_child(col)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_close_btn = RogueSkin.button("关闭（Esc）", RogueSkin.SIZE_BODY, Vector2(220, 52))
	_close_btn.pressed.connect(close)
	col.add_child(_close_btn)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit_page)
	_fit_page()


func _fit_page() -> void:
	if _root != null:
		Hud.fit_page(_root, get_viewport().get_visible_rect().size, DESIGN)


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# data：name / level / types(Array) / portrait(Texture2D 或 null) / hp / hp_max / stats(Array 6) / stages(Array 6，没有就空) /
#       nature / ability{name, desc, slot} / status / moves[{name, info, level}]
func open(data: Dictionary) -> void:
	for ch in _body.get_children():
		_body.remove_child(ch)
		ch.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_body.add_child(head)
	var tex = data.get("portrait", null)
	if tex is Texture2D:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.custom_minimum_size = Vector2(96, 96)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		head.add_child(pic)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	title.add_child(RogueSkin.label("%s　Lv.%d" % [str(data.get("name", "")), int(data.get("level", 1))], RogueSkin.SIZE_TITLE, "summary_gold"))
	var line := "属性：%s　性格：%s　HP %d/%d" % [" / ".join(PackedStringArray(data.get("types", []))), str(data.get("nature", "—")), int(data.get("hp", 0)), int(data.get("hp_max", 0))]
	if str(data.get("status", "")) != "":
		line += "　状态：%s" % str(data["status"])
	title.add_child(RogueSkin.label(line, RogueSkin.SIZE_SMALL, "window", true))
	# 六边形能力图（用户 2026-10-23：“原界面有个 6 维图”）：画种族值，一眼看出偏哪边；下面的格子是当前实际数值
	var base: Array = data.get("base_stats", [])
	if base.size() >= 6:
		var radar := StatRadar.new()
		radar.values = base.duplicate()
		radar.custom_minimum_size = Vector2(190, 150)
		head.add_child(radar)
	# 六维
	var stats: Array = data.get("stats", [])
	var stages: Array = data.get("stages", [])
	if stats.size() >= 6:
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 10)
		_body.add_child(grid)
		for i in 6:
			var cell := PanelContainer.new()
			cell.add_theme_stylebox_override("panel", RogueSkin.box(3, "_thin", 4))
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var txt := "%s　%d" % [STAT_NAMES[i], int(stats[i])]
			if i < stages.size() and i > 0 and int(stages[i]) != 0:
				txt += "（%+d 级）" % int(stages[i])
			cell.add_child(RogueSkin.label(txt, RogueSkin.SIZE_SMALL, "window"))
			grid.add_child(cell)
	# 特性
	var ab: Dictionary = data.get("ability", {})
	var ab_box := PanelContainer.new()
	ab_box.add_theme_stylebox_override("panel", RogueSkin.box(3 if RogueSkin.USE_KIT else 4, "_thin", 6))   # 素材包里 4 号是奶白底，白字看不见，改用凹槽栏
	_body.add_child(ab_box)
	var ab_text := "特性：无"
	if not ab.is_empty() and str(ab.get("name", "")) != "":
		ab_text = "特性：%s（%s）\n%s" % [str(ab["name"]), str(ab.get("slot", "")), str(ab.get("desc", ""))]
	if str(data.get("fusion", "")) != "":
		ab_text = "融合：%s（特性用后者的）\n%s" % [str(data["fusion"]), ab_text]
	ab_box.add_child(RogueSkin.label(ab_text, RogueSkin.SIZE_SMALL, "window", true))
	# 招式
	_body.add_child(RogueSkin.label("招式", RogueSkin.SIZE_BODY, "summary_gold"))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	_scroll.add_child(list)
	for mv: Dictionary in data.get("moves", []):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", RogueSkin.box(2, "_thin", 6))
		var c := VBoxContainer.new()
		card.add_child(c)
		var nr := HBoxContainer.new()
		nr.add_theme_constant_override("separation", 10)
		c.add_child(nr)
		nr.add_child(RogueSkin.label(str(mv.get("name", "")), RogueSkin.SIZE_BODY, "summary_gold"))
		if int(mv.get("level", 0)) > 0:
			nr.add_child(RogueSkin.label("Lv.%d" % int(mv["level"]), RogueSkin.SIZE_SMALL, "summary_gray"))
		c.add_child(RogueSkin.label(str(mv.get("info", "")), RogueSkin.SIZE_SMALL, "summary_blue", true))
		list.add_child(card)
	if (data.get("moves", []) as Array).is_empty():
		list.add_child(RogueSkin.label("还没有招式。", RogueSkin.SIZE_SMALL, "summary_gray"))
	visible = true
	_fit_page()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# 六边形能力图：HP 在上，顺时针 攻击 / 防御 / 速度 / 特防 / 特攻（原版选宠页的排法）；满格 = 种族值 180。
class StatRadar extends Control:
	const ORDER := [0, 1, 2, 5, 4, 3]   # 六维下标 [HP, 攻, 防, 特攻, 特防, 速] → 画的顺序
	const LABELS := ["HP", "攻击", "防御", "速度", "特防", "特攻"]
	const FULL := 180.0
	var values: Array = []

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, 4)
		var r := minf(size.x * 0.5 - 34.0, size.y * 0.5 - 16.0)
		var pts: Array[Vector2] = []
		for i in 6:
			var ang := -PI / 2.0 + TAU * float(i) / 6.0
			pts.append(Vector2(cos(ang), sin(ang)))
		# 底：三圈网格 + 辐条
		for ring in [1.0, 0.66, 0.33]:
			var poly := PackedVector2Array()
			for p in pts:
				poly.append(c + p * r * ring)
			poly.append(poly[0])
			draw_polyline(poly, Color(0.55, 0.55, 0.65, 0.55), 1.0)
		for p in pts:
			draw_line(c, c + p * r, Color(0.55, 0.55, 0.65, 0.35), 1.0)
		# 值
		var vals := PackedVector2Array()
		for i in 6:
			var v := clampf(float(values[ORDER[i]]) / FULL, 0.05, 1.0)
			vals.append(c + pts[i] * r * v)
		draw_colored_polygon(vals, Color(0.35, 0.75, 1.0, 0.45))
		var outline := vals.duplicate()
		outline.append(vals[0])
		draw_polyline(outline, Color(0.45, 0.85, 1.0, 1.0), 2.0)
		# 标签 + 数值
		var font := get_theme_default_font()
		for i in 6:
			var txt := "%s %d" % [tr(LABELS[i]), int(values[ORDER[i]])]   # 自己画的字不会自动翻，手动 tr
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var pos := c + pts[i] * (r + 12.0) + Vector2(-w * 0.5, 4.0)
			draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.92, 0.85))
