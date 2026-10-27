extends Control
# 原生 UI 的画布：640×360 的设计画布，整数倍放大到屏幕、居中。
# 页面往 `canvas`（640×360 的 Control）里放东西。
#
# 2026-10-25（用户：“文字有点糊”）：以前是先画进 640×360 的 SubViewport 再整张放大，
# 高清字（ui/hd_text.gd）也跟着被放大成糊的。现在直接把 canvas 按倍数放大摆在屏幕上：
# 像素图照样最近邻，文字按屏幕实际大小重新栅格化。鼠标坐标由 Control 的缩放自动换算回设计画布。
const RogueUI := preload("res://ui/rogue_ui.gd")

var canvas: Control
var _k := 1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# 不透明底：窗口比例和设计画布不一样时，两边 / 上下的空白不能露出后面的游戏场景。
	var backdrop := ColorRect.new()
	backdrop.color = Color("14121c")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	canvas = Control.new()
	canvas.size = RogueUI.DESIGN
	canvas.custom_minimum_size = RogueUI.DESIGN
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	resized.connect(_relayout)
	_relayout.call_deferred()


func _relayout() -> void:
	_k = float(maxi(1, int(floor(minf(size.x / RogueUI.DESIGN.x, size.y / RogueUI.DESIGN.y)))))
	canvas.scale = Vector2(_k, _k)
	canvas.position = ((size - RogueUI.DESIGN * _k) * 0.5).floor()


func scale_factor() -> int:
	return int(_k)
