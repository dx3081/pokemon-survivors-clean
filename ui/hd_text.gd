extends RefCounted
# 高清文字（用户 2026-10-24：“文字可以小一点更高清一点……现在新时代，游戏东西可以不用那么 GBA”）。
# 和 RogueUI.label 一样按原版逻辑像素摆位置（× RogueUI.K），但用系统自带的平滑中文字体（微软雅黑等），
# 字号按画布像素给（RogueUI.label 的 16 ≈ 一行 8 个原版像素；这里常用 11～13，更小更清楚）。
# 打包发布时可以换成随游戏自带的字体（这里只改 font()）。

const RogueUI := preload("res://ui/rogue_ui.gd")

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "SimHei"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.font_weight = 500
		_font = f
	return _font


# x / y / width 是原版逻辑像素；size 是画布像素。dark = 浅底（白框）上用的深色字。
static func label(parent: Node, text: String, x: float, y: float, size := 12, color := Color("f0f0e8"), width := 0.0, wrap := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	l.position = Vector2(x, y) * RogueUI.K
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", -2)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width * RogueUI.K, 0)
		l.size = Vector2(width * RogueUI.K, 0)
	parent.add_child(l)
	return l


const DARK := Color("3a3a42")       # 白框里的字
const LIGHT := Color("f0f0e8")
const BLUE := Color("2f9fd8")
const GOLD := Color("d8a830")
const RED := Color("d84040")
const GREEN := Color("3aa858")
