extends CanvasLayer
# 标题页：主神模拟器2的暖墨背景、漆框和 TownButton 样式。
# 不用补间、不靠时间推进，Engine.time_scale = 0 时照常能用。
#
#   page.start_pressed / skills_pressed / settings_pressed 接上；page.open()

signal start_pressed
signal skills_pressed   # 2026-10-15：旧的“功法研习”入口改成“技能”，进城镇的技能页
signal settings_pressed
signal slot_selected(slot: int)   # 点了某个存档槽（从 1 开始）

const Hud := preload("res://ui/hud.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")
const SaveSlots := preload("res://game/save_slots.gd")

var _root: Control
var _start: Button
var _slot_row: GridContainer
var _slot_buttons: Array[Button] = []


func _init() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	_refresh_slots()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# 背景：深紫蓝竖向渐变（原版标题页没有现成底图，先用同色系纯渐变，不再是主项目那套暖墨色）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.17, 0.15, 0.24), Color(0.07, 0.06, 0.11)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gtex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)

	var plaque := PanelContainer.new()
	plaque.custom_minimum_size = Vector2(680, 140)
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 16))
	col.add_child(plaque)
	var name_l := RogueSkin.label("Pokemon Survivors", 56, "summary_gold")
	name_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plaque.add_child(name_l)
	var sub := RogueSkin.label("（暂名）", RogueSkin.SIZE_SMALL, "summary_gray")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	_slot_row = GridContainer.new()   # 9 个存档位排成 3×3
	_slot_row.columns = 3
	_slot_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_slot_row.add_theme_constant_override("h_separation", 12)
	_slot_row.add_theme_constant_override("v_separation", 8)
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_slot_row)
	for i in SaveSlots.COUNT:
		var b := RogueSkin.button("", RogueSkin.SIZE_SMALL, Vector2(220, 46))
		b.pressed.connect(func(): slot_selected.emit(i + 1))
		_slot_row.add_child(b)
		_slot_buttons.append(b)
	_refresh_slots()

	_start = RogueSkin.button("开始", RogueSkin.SIZE_TITLE, Vector2(300, 64), true, "gold")
	_start.pressed.connect(func(): start_pressed.emit())
	_add_centered(col, _start)
	# “技能”键去掉（用户 2026-10-26：没用，城镇里有技能页）
	var settings := RogueSkin.button("设置", RogueSkin.SIZE_BODY, Vector2(300, 48))
	settings.pressed.connect(func(): settings_pressed.emit())
	_add_centered(col, settings)
	var quit := RogueSkin.button("退出", RogueSkin.SIZE_BODY, Vector2(300, 48))
	quit.pressed.connect(func(): get_tree().quit())
	_add_centered(col, quit)

	var hint := RogueSkin.label("回车 开始", RogueSkin.SIZE_SMALL, "summary_gray")
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -26
	hint.offset_left = -200
	hint.offset_right = 200
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)


# 存档名一律“存档 N”（用户 2026-10-26：不再标 AI 名字）
const SLOT_OWNER := {}


# 每个槽一行概况：当前槽用玉色高亮；空槽写“新存档”。
func _refresh_slots() -> void:
	var cur := SaveSlots.current()
	for i in _slot_buttons.size():
		var sm := SaveSlots.summary(i + 1)
		var line := "存档 %d%s" % [i + 1, SLOT_OWNER.get(i + 1, "")]
		if bool(sm.get("empty", false)):
			line += "\n新存档"
		elif bool(sm.get("corrupt", false)):
			line += "\n（存档损坏）"
		else:
			line += "\n点数 %d · 已捕获 %d" % [int(sm["balance"]), int(sm["caught"])]
		var b := _slot_buttons[i]
		b.text = line
		var on := (i + 1) == cur
		# 当前存档槽：金框常亮；其余青框，鼠标放上去变金（和商店 / 详情页同一套）
		b.add_theme_stylebox_override("normal", RogueSkin.box(4 if on else 2, "_thin", 6))
		# 素材包的“选中行”是奶白底，字要用深色，不然看不见
		var ink := RogueSkin.KIT_BTN_TEXT_DARK if (on and RogueSkin.USE_KIT) else RogueSkin.KIT_BTN_TEXT
		b.add_theme_color_override("font_color", ink)
		b.add_theme_color_override("font_hover_color", ink)


func _add_centered(parent: Control, b: Control) -> void:
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		start_pressed.emit()
