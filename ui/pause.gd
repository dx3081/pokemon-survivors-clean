extends CanvasLayer
# 暂停和设置：采用主神模拟器2的墨色漆框弹窗与按钮。
#
#   page.resume_pressed / abandon_pressed 接上；page.open_pause() 或 page.open_settings()（标题页进来只看设置）

signal resume_pressed
signal abandon_pressed     # 放弃这一局，回标题页
signal closed              # 设置页关了（从标题页进来时用）
signal xp_rate_changed(pct: int)   # 经验加成调节（0..100，买到的经验护符加成里实际生效多少）
signal tuning_changed   # 游戏速度 / 敌人密度 / 捕捉圈大小改了（main 重读存档里的值）
signal settings_returned   # 设置页从局内商店进来，返回时回商店（不并排留两个弹窗）

const Hud := preload("res://ui/hud.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")
const CFG := "user://settings.cfg"
const I18n := preload("res://game/i18n.gd")

var _root: Control
var _pause_box: VBoxContainer
var _settings_box: VBoxContainer
var _rows: VBoxContainer   # 设置页里可滚动的那一块（滑块 / 开关都在里面）
var _from_title := false
var _return_to_shop := false
var _vol: HSlider
var _vol_label: Label
var _full: CheckButton
var _show_rng: CheckButton
var _outline_new: CheckButton   # 没抓过的宝可梦描边（用户 2026-10-24）
var _tips: CheckButton          # 新手提示（默认开；新存档在关键时刻提示怎么玩）
var _squad: CheckButton         # 自爆小队（默认关；用户 2026-10-25：会很折磨）
var _lang_btns := {}            # 语言：zh / en 两个按钮（用户 2026-10-26）
var _dev_toggle: Button         # “开发者设置”展开 / 收起
var _dev_rows: VBoxContainer    # 经验加成 / 游戏速度 / 敌人密度 / 闪光… 这些调试用的滑块收在这里，默认收起
var _xp: HSlider
var _xp_label: Label
var _tune: Dictionary = {}   # 键 -> {slider, label}；游戏速度 / 敌人密度 / 捕捉圈大小

# 可调系数（用户 2026-10-18：“再加个游戏速度系数，和敌人密度系数，捕捉圈子也搞个系数，在设置里调试，找最舒服的”）。
# 键 -> [标题, 最小, 最大, 步长, 默认]；存在 settings.cfg 的 [gameplay]。
const TUNING := {
	"game_speed": ["游戏速度", 0.5, 2.0, 0.05, 1.0],
	"enemy_density": ["敌人密度", 0.25, 3.0, 0.05, 0.75],   # 默认 0.75（用户 2026-10-24）
	"shiny_rate": ["闪光几率", 0.0, 200.0, 1.0, 1.0],   # 乘在原版闪光基础几率（约 0.098%）上；0 = 不出闪光，200 ≈ 19.5%
	"shiny_hp": ["闪光血量", 1.0, 10.0, 0.5, 2.0],   # 闪光宠物刷出时血量 × 这个（默认 ×2，和神兽血量叠乘）
	"legendary_hp": ["神兽血量", 1.0, 10.0, 0.5, 4.0],   # 神兽刷出时血量 × 这个（默认 ×4：耐打一点；当初“只能满血抓”的理由在捕获血量按半血算之后已经没有了）
	"attack_cd": ["攻击冷却", 0.25, 3.0, 0.05, 1.0],   # 乘在所有玩家招式的冷却上（越小招放得越快）
	# 乘在所有玩家招式的射程上，敌人的远程射程和贴身挥击距离也乘同一个（用户 2026-10-21：“我远敌人也远，我近敌人也近”，原来分两条）
	"attack_range": ["攻击距离（你和敌人）", 0.5, 2.0, 0.05, 1.0],
	"capture_ring": ["捕捉圈大小", 0.4, 2.0, 0.05, 1.0],
}
var xp_max_provider: Callable = Callable()   # 返回买到的经验护符总倍率（×1.0 = 没买）；局内 / 局外设置页都用它显示


func _init() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


# 开游戏时调一次：把存下的音量和全屏用上。
# 窗口模式只在进程第一次调用时设一次：战斗结束会 reload 场景再调一次，再设就会把玩家自己最大化 / 拉大的窗口强制压回小窗口
# （用户 2026-10-17：“战斗结束后屏幕还会强制性变小”）。
static var _window_applied := false


static func apply_saved() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(CFG) == OK
	I18n.set_language(str(cf.get_value("general", "language", "zh")) if ok else "zh")
	if not ok:
		return
	var first := not _window_applied
	_window_applied = true
	_apply(float(cf.get_value("audio", "volume", 1.0)), bool(cf.get_value("video", "fullscreen", false)), first)


static func _apply(vol: float, full: bool, touch_window := true) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, vol)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	if not touch_window or DisplayServer.get_name() == "headless":
		return
	if full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)   # 只把全屏退回窗口；最大化的窗口不动


func open_pause() -> void:
	_from_title = false
	_return_to_shop = false
	_pause_box.visible = true
	_settings_box.visible = false
	visible = true


func open_settings(from_title := false, return_to_shop := false) -> void:
	_from_title = from_title
	_return_to_shop = return_to_shop
	_load_into_controls()
	_pause_box.visible = false
	_settings_box.visible = true
	visible = true


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(760, 620)
	holder.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 16))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var inner := CenterContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(inner)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stack)

	_pause_box = VBoxContainer.new()
	_pause_box.add_theme_constant_override("separation", 10)
	_pause_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_pause_box)
	var t := RogueSkin.label("暂停", RogueSkin.SIZE_TITLE, "summary_gold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_box.add_child(t)
	for spec in [["继续（Esc）", func(): resume_pressed.emit()], ["设置", func(): open_settings(false)],
			["放弃这一局（已保存点数保留）", func(): abandon_pressed.emit()], ["退出游戏", func(): get_tree().quit()]]:
		var b := RogueSkin.button(spec[0], RogueSkin.SIZE_BODY, Vector2(440, 56), true, "red" if str(spec[0]).begins_with("放弃") else "teal")
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(spec[1])
		_pause_box.add_child(b)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 14)
	_settings_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_settings_box)
	var st := RogueSkin.label("设置", RogueSkin.SIZE_TITLE, "summary_gold")
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_box.add_child(st)
	# 设置项多了（15 行）一屏放不下：滑块和开关放进可滚动的一块，标题和“返回”钉在上下。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 12)
	_rows.add_child(vrow)
	vrow.add_child(_row_label("音量"))
	_vol = HSlider.new()
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.05
	_vol.custom_minimum_size = Vector2(300, 28)
	_style_slider(_vol)
	_vol.value_changed.connect(_on_vol)
	vrow.add_child(_vol)
	_vol_label = RogueSkin.label("100%", RogueSkin.SIZE_BODY, "window")
	_vol_label.custom_minimum_size = Vector2(90, 0)
	vrow.add_child(_vol_label)
	# 语言（中文 / English）：两个按钮本身不翻译，永远显示各自的语言名
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 12)
	_rows.add_child(lrow)
	var ll := _row_label("语言")
	lrow.add_child(ll)
	for code in I18n.LOCALES:
		var lb := RogueSkin.button(I18n.LOCALE_NAMES[code], RogueSkin.SIZE_BODY, Vector2(150, 44))
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lb.pressed.connect(func(): _set_language(code))
		lrow.add_child(lb)
		_lang_btns[code] = lb
	# 显示攻击范围 / 没抓过的描边 / 全屏放在外面；其余调试用的滑块收进“开发者设置”（用户 2026-10-24：滚轮滚过去就把数值改乱了）
	_show_rng = CheckButton.new()
	_show_rng.text = "显示攻击范围"
	_show_rng.focus_mode = Control.FOCUS_NONE
	_style_check(_show_rng)
	_show_rng.toggled.connect(func(_on): _save_controls(); tuning_changed.emit())
	_rows.add_child(_show_rng)
	_outline_new = CheckButton.new()
	_outline_new.text = "没抓过的宝可梦描边"
	_outline_new.focus_mode = Control.FOCUS_NONE
	_style_check(_outline_new)
	_outline_new.toggled.connect(func(_on): _save_controls(); tuning_changed.emit())
	_rows.add_child(_outline_new)
	_tips = CheckButton.new()
	_tips.text = "新手提示"
	_tips.focus_mode = Control.FOCUS_NONE
	_style_check(_tips)
	_tips.toggled.connect(func(_on): _save_controls(); tuning_changed.emit())
	_rows.add_child(_tips)
	_squad = CheckButton.new()
	_squad.text = "自爆小队（成群冲过来自爆，很折磨）"
	_squad.focus_mode = Control.FOCUS_NONE
	_style_check(_squad)
	_squad.toggled.connect(func(_on): _save_controls(); tuning_changed.emit())
	_rows.add_child(_squad)
	_full = CheckButton.new()
	_full.text = "全屏"
	_full.focus_mode = Control.FOCUS_NONE
	_style_check(_full)
	_full.toggled.connect(func(_on): _save_controls())
	_rows.add_child(_full)
	_dev_toggle = RogueSkin.button("开发者设置 ▸", RogueSkin.SIZE_SMALL, Vector2(260, 40))
	_dev_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_dev_toggle.pressed.connect(func():
		_dev_rows.visible = not _dev_rows.visible
		_dev_toggle.text = "开发者设置 ▾" if _dev_rows.visible else "开发者设置 ▸")
	_rows.add_child(_dev_toggle)
	_dev_rows = VBoxContainer.new()
	_dev_rows.add_theme_constant_override("separation", 10)
	_dev_rows.visible = false
	_rows.add_child(_dev_rows)
	# 经验加成：买了经验护符（比如 ×3）可以在这里调低，局外局内都行；0% = 原经验，100% = 买到的全部。
	var xrow := HBoxContainer.new()
	xrow.add_theme_constant_override("separation", 12)
	_dev_rows.add_child(xrow)
	xrow.add_child(_row_label("经验加成"))
	_xp = HSlider.new()
	_xp.min_value = 0
	_xp.max_value = 100
	_xp.step = 5
	_xp.custom_minimum_size = Vector2(300, 28)
	_style_slider(_xp)
	_xp.value_changed.connect(_on_xp)
	xrow.add_child(_xp)
	_xp_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "window")
	_xp_label.custom_minimum_size = Vector2(190, 0)
	xrow.add_child(_xp_label)
	for key: String in TUNING:
		var spec: Array = TUNING[key]
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 12)
		_dev_rows.add_child(trow)
		trow.add_child(_row_label(str(spec[0])))
		var sl := HSlider.new()
		sl.min_value = float(spec[1])
		sl.max_value = float(spec[2])
		sl.step = float(spec[3])
		sl.custom_minimum_size = Vector2(300, 28)
		_style_slider(sl)
		sl.value_changed.connect(_on_tune.bind(key))
		trow.add_child(sl)
		var lab := RogueSkin.label("", RogueSkin.SIZE_BODY, "window")
		lab.custom_minimum_size = Vector2(230, 0)
		trow.add_child(lab)
		_tune[key] = {"slider": sl, "label": lab}
	var back := RogueSkin.button("返回", RogueSkin.SIZE_BODY, Vector2(240, 52))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back)
	_settings_box.add_child(back)


# 设置行的名字：固定宽度，滑块才能上下对齐。
func _row_label(text: String) -> Label:
	var l := RogueSkin.label(text, RogueSkin.SIZE_BODY, "window")
	l.custom_minimum_size = Vector2(190, 0)
	return l


# 滑块换成原版配色：深色槽 + 金色已填部分 + 方形把手，不用 Godot 默认的灰圆点。
func _style_slider(sl: HSlider) -> void:
	sl.scrollable = false   # 滚轮不改数值（用户 2026-10-24：滚动设置页时把滑块滚乱了）
	sl.focus_mode = Control.FOCUS_NONE
	if RogueSkin.USE_KIT:
		sl.add_theme_stylebox_override("slider", RogueSkin.kit_box("slider_track.png", 4, 0))
		sl.add_theme_stylebox_override("grabber_area", RogueSkin.kit_box("slider_fill.png", 4, 0))
		sl.add_theme_stylebox_override("grabber_area_highlight", RogueSkin.kit_box("slider_fill.png", 4, 0))
		var kn := RogueSkin.kit_texture("slider_knob.png")
		sl.add_theme_icon_override("grabber", kn)
		sl.add_theme_icon_override("grabber_highlight", kn)
		sl.add_theme_icon_override("grabber_disabled", kn)
		return
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.11, 0.1, 0.14)
	track.border_color = Color(0.9, 0.9, 0.93)
	track.set_border_width_all(2)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = RogueSkin.style_color("summary_gold")
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var img := Image.create(14, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.96, 0.96, 0.98))
	for x in 14:
		for y in [0, 1, 26, 27]:
			img.set_pixel(x, y, Color(0.35, 0.35, 0.42))
	var knob := ImageTexture.create_from_image(img)
	sl.add_theme_icon_override("grabber", knob)
	sl.add_theme_icon_override("grabber_highlight", knob)
	sl.add_theme_icon_override("grabber_disabled", knob)


func _style_check(cb: CheckButton) -> void:
	if RogueSkin.USE_KIT:
		cb.add_theme_icon_override("checked", RogueSkin.kit_texture("toggle_on.png"))
		cb.add_theme_icon_override("unchecked", RogueSkin.kit_texture("toggle_off.png"))
		cb.add_theme_icon_override("checked_disabled", RogueSkin.kit_texture("toggle_on.png"))
		cb.add_theme_icon_override("unchecked_disabled", RogueSkin.kit_texture("toggle_off.png"))
	cb.add_theme_font_override("font", RogueSkin.RogueUI.font())
	cb.add_theme_font_size_override("font_size", RogueSkin.SIZE_BODY)
	cb.add_theme_color_override("font_color", RogueSkin.style_color("window"))
	cb.add_theme_color_override("font_hover_color", RogueSkin.style_color("summary_gold"))
	cb.add_theme_color_override("font_pressed_color", RogueSkin.style_color("window"))


# 读设置里的开关（缺失 = 关）。
static func set_flag(key: String, on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("gameplay", key, on)
	cf.save(CFG)


static func saved_flag(key: String, default := false) -> bool:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return default
	return bool(cf.get_value("gameplay", key, default))


func _set_language(code: String) -> void:
	I18n.set_language(code)
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("general", "language", code)
	cf.save(CFG)
	_refresh_lang_btns()


func _refresh_lang_btns() -> void:
	var cur := I18n.language()
	for code in _lang_btns:
		var b: Button = _lang_btns[code]
		b.add_theme_stylebox_override("normal", RogueSkin.box(4 if code == cur else 2, "_thin", 6))


func _load_into_controls() -> void:
	_refresh_lang_btns()
	var cf := ConfigFile.new()
	cf.load(CFG)
	_vol.set_value_no_signal(float(cf.get_value("audio", "volume", 1.0)))
	_vol_label.text = "%d%%" % roundi(_vol.value * 100.0)
	_full.set_pressed_no_signal(bool(cf.get_value("video", "fullscreen", false)))
	_show_rng.set_pressed_no_signal(bool(cf.get_value("gameplay", "show_ranges", false)))
	_outline_new.set_pressed_no_signal(bool(cf.get_value("gameplay", "outline_uncaught", false)))
	_tips.set_pressed_no_signal(bool(cf.get_value("gameplay", "newbie_tips", true)))
	_squad.set_pressed_no_signal(bool(cf.get_value("gameplay", "squad", false)))
	_xp.set_value_no_signal(float(cf.get_value("gameplay", "xp_rate_pct", 100)))
	_refresh_xp_label()
	for key: String in TUNING:
		var sl: HSlider = _tune[key]["slider"]
		sl.set_value_no_signal(saved_tuning(key))
		(_tune[key]["label"] as Label).text = _tune_text(key, sl.value)


# 读存档里的系数（缺失 / 越界回默认 / 钳到范围）。
static func saved_tuning(key: String) -> float:
	var spec: Array = TUNING[key]
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return float(spec[4])
	var v = cf.get_value("gameplay", key, spec[4])
	if not (v is float or v is int):
		return float(spec[4])
	return clampf(float(v), float(spec[1]), float(spec[2]))


# 攻击距离再显示实际米数：玩家招式射程上限 4 米（main/arts.gd 的 MAX_ATTACK_RANGE）乘上这个系数。
const ATTACK_RANGE_BASE_M := 4.0
const SHINY_BASE_PCT := 64.0 / 65536.0 * 100.0   # 闪光基础几率（%），和 main/state.gd 的 SHINY_CHANCE 同一个数


func _tune_text(key: String, v: float) -> String:
	if key == "attack_range":
		return "×%.2f（最远约 %.1f 米）" % [v, ATTACK_RANGE_BASE_M * v]
	if key == "shiny_rate":
		return "×%d（约 %.2f%%）" % [int(v), minf(100.0, SHINY_BASE_PCT * v)]
	return "×%.2f" % v


func _on_tune(v: float, key: String) -> void:
	(_tune[key]["label"] as Label).text = _tune_text(key, v)
	_save_controls()
	tuning_changed.emit()


func _on_vol(v: float) -> void:
	_vol_label.text = "%d%%" % roundi(v * 100.0)
	_save_controls()


# 买到的经验护符总倍率（没接 provider 时按 ×1 = 没买）。
func _xp_max() -> float:
	return maxf(1.0, float(xp_max_provider.call())) if xp_max_provider.is_valid() else 1.0


func _refresh_xp_label() -> void:
	var m := _xp_max()
	_xp.editable = m > 1.001
	if m <= 1.001:
		_xp_label.text = "（没买经验护符）"
		return
	_xp_label.text = "×%.2f（最高 ×%.2f）" % [effective_xp_mult(int(_xp.value), m), m]


# 0% = ×1，100% = 买到的全部倍率，中间线性。
static func effective_xp_mult(pct: int, max_mult: float) -> float:
	return 1.0 + (maxf(1.0, max_mult) - 1.0) * clampf(float(pct), 0.0, 100.0) / 100.0


static func saved_xp_rate_pct() -> int:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return 100
	return clampi(int(cf.get_value("gameplay", "xp_rate_pct", 100)), 0, 100)


func _on_xp(v: float) -> void:
	_refresh_xp_label()
	_save_controls()
	xp_rate_changed.emit(int(v))


func _save_controls() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("gameplay", "xp_rate_pct", int(_xp.value))
	for key: String in _tune:
		cf.set_value("gameplay", key, snappedf((_tune[key]["slider"] as HSlider).value, 0.01))
	cf.set_value("audio", "volume", _vol.value)
	cf.set_value("video", "fullscreen", _full.button_pressed)
	cf.set_value("gameplay", "show_ranges", _show_rng.button_pressed)
	cf.set_value("gameplay", "outline_uncaught", _outline_new.button_pressed)
	cf.set_value("gameplay", "newbie_tips", _tips.button_pressed)
	cf.set_value("gameplay", "squad", _squad.button_pressed)
	cf.save(CFG)
	_apply(_vol.value, _full.button_pressed)


func _back() -> void:
	if _from_title:
		visible = false
		closed.emit()
	elif _return_to_shop:
		visible = false
		settings_returned.emit()
	else:
		open_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _settings_box.visible:
			_back()
		else:
			resume_pressed.emit()
