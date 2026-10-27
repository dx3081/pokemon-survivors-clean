extends CanvasLayer
# 补给站（用户 2026-10-25：“换地图中间加个补给时间，就是类似在初始界面给宠物强化的地方”）。
# 撤离选好新地区后弹出，游戏暂停；上面是新地区的信息卡（原版地区背景图 / 野怪等级 / 天气 / 常见宝可梦），
# 左边是选中商品的说明，右边是图标格子（用户给的商店样式：左详情 + 右图标）。按「出发」（或 X）进新地区。
#
# 本页只展示和发信号：商品行、价格、能不能买都由 main/meta_flow.gd 的 _supply_info() 算好传进来，
# 扣点 / 存档 / 马上生效都在 main 那边做（走城镇商店同一条购买入口）。
#
# 用法：
#   page.buy_pressed.connect(...); page.depart_pressed.connect(...)
#   page.open(info) / page.refresh(info, message) / page.close() / page.is_open()
# info = {"map_id", "map_name", "enemy_lv", "weather": [中文], "species": [编号], "points",
#         "tabs": {"grow": [行], "held": [行], "tm": [行]}}
# 行 = {"id", "name", "icon", "desc", "price", "state", "can": bool, "badge"}

signal buy_pressed(id: String)
signal depart_pressed
signal cancel_pressed          # 再待会儿：不走了
signal map_step(step: int)     # 换下一站（◀ ▶ / Q E）

const RogueUI := preload("res://ui/rogue_ui.gd")
const RogueScreen := preload("res://ui/rogue_screen.gd")
const RogueAtlas := preload("res://ui/rogue_atlas.gd")
const HD := preload("res://ui/hd_text.gd")

const TABS := [["grow", "培养"], ["held", "携带道具"], ["tm", "技能机器"]]
const KIT_DIR := "res://assets/ui_kit/2x/"
const KIT_INK := Color("2E2A3B")     # 亮底（选中 / 主按钮 / 当前页签）上的深色字
const KIT_CREAM := Color("F4F1EA")
const KIT_TEXT2 := Color("B8B2C8")
const COLS := 9
const ROWS := 4
const CELL := 20.0
const GRID_X := 129.0
const GRID_Y := 78.0

var _screen: Control
var _c: Control
var _info := {}
var _tab := "grow"
var _page := 0
var _sel := ""
var _msg := ""
var _last_click_id := ""
var _last_click_at := -10.0


func _init() -> void:
	layer = 60
	visible = false
	_screen = RogueScreen.new()
	add_child(_screen)
	_c = _screen.canvas


func open(info: Dictionary) -> void:
	_info = info
	_tab = "grow"
	_page = 0
	_sel = ""
	_msg = "买了马上生效，也永久留着。双击格子或 Enter 买。"
	visible = true
	_redraw()


func refresh(info: Dictionary, message := "") -> void:
	_info = info
	if message != "":
		_msg = message
	if visible:
		_redraw()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func current_tab() -> String:
	return _tab


func set_tab(tab: String) -> void:
	for t in TABS:
		if str(t[0]) == tab:
			_tab = tab
			_page = 0
			_sel = ""
			_redraw()
			return


# 给 AI 接口 / 检查看的：某一页的商品行（tab 为空 = 当前页）。
func rows(tab := "") -> Array:
	var key := tab if tab != "" else _tab
	return ((_info.get("tabs", {}) as Dictionary).get(key, []) as Array)


func message() -> String:
	return _msg


func _row(id: String) -> Dictionary:
	for r in rows():
		if str(r.get("id", "")) == id:
			return r
	return {}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		var handled := true
		match k:
			KEY_X:
				depart_pressed.emit()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if _sel != "":
					buy_pressed.emit(_sel)
			KEY_TAB:
				_flip_tab(1)
			KEY_LEFT:
				_move_sel(-1)
			KEY_RIGHT:
				_move_sel(1)
			KEY_UP:
				_move_sel(-COLS)
			KEY_DOWN:
				_move_sel(COLS)
			KEY_Q:
				map_step.emit(-1)
			KEY_E:
				map_step.emit(1)
			KEY_ESCAPE:
				cancel_pressed.emit()
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()


func _flip_tab(step: int) -> void:
	var i := 0
	for n in TABS.size():
		if str(TABS[n][0]) == _tab:
			i = n
	set_tab(str(TABS[posmod(i + step, TABS.size())][0]))


func _move_sel(step: int) -> void:
	var list := rows()
	if list.is_empty():
		return
	var i := 0
	for n in list.size():
		if str(list[n].get("id", "")) == _sel:
			i = n
	i = clampi(i + step, 0, list.size() - 1)
	_sel = str(list[i].get("id", ""))
	_page = i / (COLS * ROWS)
	_redraw()


func _click(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


# 透明点击区（原版逻辑像素）。
func _hit(x: float, y: float, w: float, h: float, cb: Callable) -> Control:
	var hit := Control.new()
	hit.position = Vector2(x, y) * RogueUI.K
	hit.size = Vector2(w, h) * RogueUI.K
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e): if _click(e): cb.call())
	_c.add_child(hit)
	return hit


# 一个图标放进 size × size 的框里（原版逻辑像素），保持比例居中。
func _icon(tex: Texture2D, x: float, y: float, size: float, dim := false) -> void:
	if tex == null:
		return
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = RogueAtlas.filter_for(tex)
	t.position = Vector2(x, y) * RogueUI.K
	t.size = Vector2(size, size) * RogueUI.K
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		t.modulate = Color(1, 1, 1, 0.35)
	_c.add_child(t)


func _item_tex(icon: String) -> Texture2D:
	return RogueAtlas.frame("icons/items", icon) if icon != "" else null


func _redraw() -> void:
	for ch in _c.get_children():
		ch.queue_free()
	RogueUI.fill(_c, 0, 0, 320, 180, Color("14121c"))
	_draw_region()
	_draw_tabs()
	_draw_grid()
	_draw_detail()
	_draw_bottom()


# 上面：新地区信息卡。
func _draw_region() -> void:
	_kit("window_main.png", 16, 2, 2, 316, 52)
	var map_id := str(_info.get("map_id", "plains"))
	var bg := RogueAtlas.texture("arenas/%s_bg.png" % map_id)
	if bg == null:
		bg = RogueAtlas.texture("arenas/default_bg.png")
	if bg != null:
		var t := TextureRect.new()
		t.texture = bg
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.position = Vector2(7, 6) * RogueUI.K
		t.size = Vector2(78, 44) * RogueUI.K
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_c.add_child(t)
	# 下一站在这里选（用户 2026-10-25：补给站里选地图，不再单独弹选地图的窗口）
	var maps: Array = _info.get("maps", [])
	var idx := int(_info.get("map_index", 0))
	var is_new := idx < maps.size() and bool(maps[idx].get("new", false))
	HD.label(_c, "补给站 · 下一站「%s」%s" % [str(_info.get("map_name", "")), "（新）" if is_new else ""], 91, 6, 15, HD.GOLD)
	if maps.size() > 1:
		HD.label(_c, "◀", 262, 5, 14, HD.BLUE)
		HD.label(_c, "%d/%d" % [idx + 1, maps.size()], 270, 6.5, 11, HD.LIGHT, 26, false, HORIZONTAL_ALIGNMENT_CENTER)
		HD.label(_c, "▶", 297, 5, 14, HD.BLUE)
		HD.label(_c, "Q / E 换", 268, 15, 9, Color("8a8496"), 30, false, HORIZONTAL_ALIGNMENT_CENTER)
		_hit(259, 4, 12, 12, func(): map_step.emit(-1))
		_hit(294, 4, 12, 12, func(): map_step.emit(1))
	var weather: Array = _info.get("weather", [])
	var wtext := "、".join(weather) if not weather.is_empty() else "没有天气"
	HD.label(_c, "野怪约 Lv%d（刚进去 1 分钟再低 5 级）　天气：%s" % [int(_info.get("enemy_lv", 1)), wtext], 91, 19, 11, HD.LIGHT)
	HD.label(_c, "常见宝可梦", 91, 33, 11, HD.LIGHT)
	var x := 124.0
	for sid in (_info.get("species", []) as Array).slice(0, 10):
		var tex := RogueUI.species_icon(int(sid))
		if tex != null:
			RogueUI.fit_icon(_c, tex, x + 9.0, 38.0, 18.0, 15.0, 0.8, 0.3)
		x += 19.0


func _draw_tabs() -> void:
	# 页签也用窗口框（用户 2026-10-25：纯色块和整体不搭）；选中的金字
	var x := 124.0
	for t in TABS:
		var on := str(t[0]) == _tab
		var w := 46.0 if str(t[0]) != "grow" else 34.0
		_kit("tab_on.png" if on else "tab_off.png", 10, x, 55, w, 16)
		_centered(str(t[1]), x, 55, w, 16, KIT_INK if on else KIT_TEXT2)
		var key := str(t[0])
		_hit(x, 55, w, 16, func(): set_tab(key))
		x += w + 2.0


func _draw_grid() -> void:
	_kit("window_main.png", 16, 124, 72, 194, 90)
	var list := rows()
	if list.is_empty():
		HD.label(_c, "这一页没有能买的", 134, 80, 11, HD.LIGHT)
		return
	var per := COLS * ROWS
	var pages := int(ceil(float(list.size()) / per))
	_page = clampi(_page, 0, pages - 1)
	if _sel == "" or _row(_sel).is_empty():
		_sel = str(list[_page * per].get("id", ""))
	for n in range(_page * per, mini(list.size(), (_page + 1) * per)):
		var r: Dictionary = list[n]
		var i := n - _page * per
		var cx := GRID_X + float(i % COLS) * CELL
		var cy := GRID_Y + float(i / COLS) * CELL
		var id := str(r.get("id", ""))
		var sel := id == _sel
		_kit("row_selected.png" if sel else ("row.png" if bool(r.get("can", true)) else "row_disabled.png"), 10, cx, cy, CELL - 2, CELL - 2)
		_icon(_item_tex(str(r.get("icon", ""))), cx + 1, cy + 1, CELL - 4, not bool(r.get("can", true)))
		var badge := str(r.get("badge", ""))
		if badge != "":
			HD.label(_c, badge, cx, cy + 10.5, 9, KIT_INK if sel else HD.LIGHT, CELL - 3, false, HORIZONTAL_ALIGNMENT_RIGHT)
		_hit(cx, cy, CELL - 2, CELL - 2, func(): _on_cell(id))
	if pages > 1:
		# 翻页放在页签那一行右边（格子里放满 4 行就没地方了）
		HD.label(_c, "◀", 272, 57, 12, HD.BLUE)
		HD.label(_c, "%d/%d" % [_page + 1, pages], 280, 58, 10, HD.LIGHT, 26, false, HORIZONTAL_ALIGNMENT_CENTER)
		HD.label(_c, "▶", 307, 57, 12, HD.BLUE)
		_hit(270, 56, 10, 12, func(): _flip_page(-1))
		_hit(305, 56, 10, 12, func(): _flip_page(1))


func _flip_page(step: int) -> void:
	var per := COLS * ROWS
	var pages := int(ceil(float(rows().size()) / per))
	_page = posmod(_page + step, maxi(pages, 1))
	_sel = ""
	_redraw()


func _on_cell(id: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if id == _last_click_id and now - _last_click_at < 0.4:
		_last_click_at = -10.0
		buy_pressed.emit(id)
		return
	_last_click_id = id
	_last_click_at = now
	_sel = id
	_redraw()


# 左边：选中商品的说明。
func _draw_detail() -> void:
	_kit("window_main.png", 16, 2, 55, 120, 107)
	var r := _row(_sel)
	if r.is_empty():
		return
	_icon(_item_tex(str(r.get("icon", ""))), 7, 62, 22)
	HD.label(_c, str(r.get("name", "")), 32, 62, 13, HD.GOLD, 86, true)
	var price := int(r.get("price", -1))
	HD.label(_c, ("%d 点" % price) if price > 0 else ("免费" if price == 0 else "—"), 32, 75, 11, HD.LIGHT)
	var state := str(r.get("state", ""))
	if state != "":
		HD.label(_c, state, 62, 75, 11, Color("a0d8a0") if bool(r.get("can", true)) else Color("d89090"), 56)
	HD.label(_c, str(r.get("desc", "")), 10, 87, 11, HD.LIGHT, 105, true)


func _draw_bottom() -> void:
	HD.label(_c, "点数 %d" % int(_info.get("points", 0)), 4, 166, 12, HD.GOLD)
	HD.label(_c, _msg, 48, 165, 10, HD.LIGHT, 128, true)
	_button(178, "再待会儿 Esc", "btn_normal.png", KIT_TEXT2, func(): cancel_pressed.emit())
	_button(225, "购买 Enter", "btn_normal.png", KIT_CREAM, func(): if _sel != "": buy_pressed.emit(_sel))
	_button(272, "出发 X", "btn_primary.png", KIT_INK, func(): depart_pressed.emit())


func _button(x: float, text: String, file: String, color: Color, cb: Callable) -> void:
	_kit(file, 10, x, 163, 46, 16)
	_centered(text, x, 163, 46, 16, color)
	_hit(x, 163, 46, 16, cb)


# 在一个框里横竖都居中的一行字（按钮 / 页签；用户 2026-10-25：底下的字没居中）。
func _centered(text: String, x: float, y: float, w: float, h: float, color: Color) -> void:
	var l := HD.label(_c, text, x, y, 11, color, w, false, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(w, h) * RogueUI.K
	l.size = Vector2(w, h) * RogueUI.K


func _kit(file: String, m: int, x: float, y: float, w: float, h: float) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(KIT_DIR + file)
	n.patch_margin_left = m
	n.patch_margin_right = m
	n.patch_margin_top = m
	n.patch_margin_bottom = m
	n.position = Vector2(x, y) * RogueUI.K
	n.size = Vector2(w, h) * RogueUI.K
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_c.add_child(n)
	return n

