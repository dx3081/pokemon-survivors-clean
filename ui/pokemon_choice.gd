extends CanvasLayer
# 事件选择面板（2026-10-15 静默升级 / 四招补充轮新增）。
# 只负责显示选项和发信号，打开 / 关闭和状态清理由 main/combat.gd 的事件泵控制。
# 普通升级不调用本面板；只有进化确认 / 暂缓和四招满时换招 / 放弃会用到。
#
# 接口：
#   open_choice(title, message, options:Array, cancel_text := "取消", details:Array = [], header := "")
#     details[i] 是第 i 个选项的详细说明（悬停时显示在下方）；header 是常驻的一块说明（比如新招式的资料）。
#   close()
#   is_open() -> bool
# signal picked(index:int)  点了第 index 个选项后发一次
# signal cancelled          点取消 / 按 Esc 后发一次
#
# 用法（调用方）：
#   page.picked.connect(...); page.cancelled.connect(...)
#   page.open_choice("进化", "绿毛虫 要进化成 铁甲蛹 吗？", ["进化"], "暂缓")

signal picked(index: int)
signal cancelled

const RogueSkin := preload("res://ui/rogue_skin.gd")

var _root: Control
var _title: Label
var _message: Label
var _options_box: VBoxContainer
var _cancel_btn: Button
var _header: Label
var _detail: Label
var _details: Array = []
var _header_text := ""


func _init() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 14))   # 原版红框窗口，和商店 / 详情页同一套
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title = RogueSkin.label("", RogueSkin.SIZE_TITLE, "summary_gold")
	box.add_child(_title)

	_message = RogueSkin.label("", RogueSkin.SIZE_BODY, "window", true)
	_message.custom_minimum_size = Vector2(560, 0)
	box.add_child(_message)

	_header = RogueSkin.label("", RogueSkin.SIZE_SMALL, "summary_blue", true)
	_header.custom_minimum_size = Vector2(560, 0)
	box.add_child(_header)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
	box.add_child(_options_box)

	_detail = RogueSkin.label("", RogueSkin.SIZE_SMALL, "summary_gold", true)
	_detail.custom_minimum_size = Vector2(560, 64)
	box.add_child(_detail)

	_cancel_btn = RogueSkin.button("", RogueSkin.SIZE_BODY, Vector2(0, 46))
	_cancel_btn.pressed.connect(_on_cancel)
	box.add_child(_cancel_btn)


func open_choice(title: String, message: String, options: Array, cancel_text := "取消", details: Array = [], header := "") -> void:
	_title.text = title
	_message.text = message
	_details = details
	_header.text = header
	_header.visible = header != ""
	_header_text = header
	_detail.text = "把鼠标移到某一招上，可以看到它的威力和用途。" if not details.is_empty() else ""
	_detail.visible = not details.is_empty()
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	for i in options.size():
		var btn := RogueSkin.button(str(options[i]), RogueSkin.SIZE_BODY, Vector2(0, 48))
		btn.pressed.connect(_decide.bind(i))
		btn.mouse_entered.connect(_show_detail.bind(i))
		_options_box.add_child(btn)
	_cancel_btn.text = cancel_text
	visible = true


func _show_detail(i: int) -> void:
	if i >= 0 and i < _details.size():
		_detail.text = str(_details[i])


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _decide(index: int) -> void:
	if not visible:
		return
	visible = false
	picked.emit(index)


func _on_cancel() -> void:
	if not visible:
		return
	visible = false
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_cancel()
