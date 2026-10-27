extends RefCounted
# 原版 Pokémon Rogue 的控件皮肤（给普通 Godot 控件页用：商店等）。rogue_ui.gd 是“往 640×360 画布里按逻辑像素摆东西”的做法，
# 这里是另一种：让 Button / PanelContainer / Label 直接穿上原版的窗口九宫格、点阵字体和字色，布局仍由容器管。
# 窗口贴图（assets/pokerogue_ui/ui/windows）是 24×24、边 8 像素的九宫格；放大整数倍后最近邻使用，保持点阵硬边。
const RogueUI := preload("res://ui/rogue_ui.gd")
const Atlas := preload("res://ui/rogue_atlas.gd")

const SCALE := 2          # 窗口贴图放大倍数（1 贴图像素 = 2 屏幕像素）
const SIZE_TITLE := 32
const SIZE_BODY := 24
const SIZE_SMALL := 16

static var _cache := {}

# true = 全部页面用这套；false = 回到原版 Rogue 的窗口贴图。别的页面只调 box() / button()，不用改。
const USE_KIT := true
const KIT_DIR := "res://assets/ui_kit/2x/"
# 窗口类型 → 素材名 + 九宫格边距（2× 像素；来自 ui_kit/manifest.json 的 1× 边距乘 2）
const KIT_BOX := {
	1: ["window_main.png", 16],   # 红框主窗口
	2: ["row.png", 10],           # 普通行 / 可点
	3: ["panel_sunk.png", 8],     # 说明栏
	4: ["row_selected.png", 10],  # 选中 / 可买
	5: ["row_disabled.png", 10],  # 不可用
}
const KIT_BTN_TEXT := Color("F4F1EA")
const KIT_BTN_TEXT_DARK := Color("2E2A3B")


static func kit_texture(file: String) -> Texture2D:
	var key := "kit:" + file
	if not _cache.has(key):
		_cache[key] = load(KIT_DIR + file)
	return _cache[key]


static func kit_box(file: String, margin: int, pad: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = kit_texture(file)
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = margin + pad
	sb.content_margin_right = margin + pad
	sb.content_margin_top = margin + pad * 0.5
	sb.content_margin_bottom = margin + pad * 0.5
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


# 窗口样式。type：1 红（主窗口）/ 2 青（普通行）/ 3 白（说明）/ 4 金（选中·可买）/ 5 灰（不可用）；variant "" / "_thin"。
static func box(type := 1, variant := "_thin", pad := 12) -> StyleBoxTexture:
	if USE_KIT and KIT_BOX.has(type):
		return kit_box(str(KIT_BOX[type][0]), int(KIT_BOX[type][1]), pad)
	var key := "%d%s" % [type, variant]
	if not _cache.has(key):
		var src := Atlas.texture("ui/windows/window_%d%s.png" % [type, variant])
		var img: Image = src.get_image()
		img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = _cache[key]
	var m := 8 * SCALE
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = m + pad
	sb.content_margin_right = m + pad
	sb.content_margin_top = m + pad * 0.5
	sb.content_margin_bottom = m + pad * 0.5
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


static func style_color(style: String) -> Color:
	return (RogueUI.STYLES.get(style, RogueUI.STYLES["window"]) as Array)[1]


static func style_shadow(style: String) -> Color:
	return (RogueUI.STYLES.get(style, RogueUI.STYLES["window"]) as Array)[2]


# 一行 / 一段字。style 见 RogueUI.STYLES；size 建议 16 的倍数（点阵字最清晰）。
static func label(text: String, size := SIZE_SMALL, style := "window", wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", RogueUI.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", style_color(style))
	l.add_theme_color_override("font_shadow_color", style_shadow(style))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 2)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# 按钮：青框（可点）→ 悬停金框；accent = "gold" 时常态就是金框；"red" 红框（危险）；不可点灰框。
static func button(text: String, size := SIZE_BODY, min_size := Vector2(160, 48), enabled := true, accent := "teal") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", RogueUI.font())
	b.add_theme_font_size_override("font_size", size)
	if USE_KIT:
		var normal_file := "btn_primary.png" if accent == "gold" else ("btn_danger.png" if accent == "red" else "btn_normal.png")
		var hover_file := "btn_primary.png" if accent == "gold" else ("btn_danger.png" if accent == "red" else "btn_hover.png")
		b.add_theme_stylebox_override("normal", kit_box(normal_file, 10, 6))
		b.add_theme_stylebox_override("hover", kit_box(hover_file, 10, 6))
		b.add_theme_stylebox_override("pressed", kit_box("btn_hover.png", 10, 6))
		b.add_theme_stylebox_override("focus", kit_box("btn_hover.png", 10, 6))
		b.add_theme_stylebox_override("disabled", kit_box("btn_disabled.png", 10, 6))
		var txt := KIT_BTN_TEXT_DARK if accent == "gold" else (Color("E8806A") if accent == "red" else KIT_BTN_TEXT)
		b.add_theme_color_override("font_color", txt)
		b.add_theme_color_override("font_hover_color", txt if accent in ["gold", "red"] else Color("FFE29A"))
		b.add_theme_color_override("font_pressed_color", txt)
		b.add_theme_color_override("font_disabled_color", Color("6E6882"))
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		b.add_theme_constant_override("shadow_offset_x", 0)
		b.add_theme_constant_override("shadow_offset_y", 0)
		b.disabled = not enabled
		return b
	var base := 4 if accent == "gold" else (1 if accent == "red" else 2)
	b.add_theme_stylebox_override("normal", box(base, "_thin", 6))
	b.add_theme_stylebox_override("hover", box(4, "_thin", 6))
	b.add_theme_stylebox_override("pressed", box(3, "_thin", 6))
	b.add_theme_stylebox_override("focus", box(4, "_thin", 6))
	b.add_theme_stylebox_override("disabled", box(5, "_thin", 6))
	b.add_theme_color_override("font_color", style_color("window"))
	b.add_theme_color_override("font_hover_color", style_color("summary_gold"))
	b.add_theme_color_override("font_pressed_color", style_color("window"))
	b.add_theme_color_override("font_disabled_color", style_color("summary_gray"))
	b.add_theme_color_override("font_shadow_color", style_shadow("window"))
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 1)
	b.disabled = not enabled
	return b


# 带描边的点阵图标（和树果一样：同一张图往八个方向错开 2 像素垫深色，再把彩色的放上面）。
# 返回一个 size×size 的 Control；拿到的 Control 默认不吃鼠标，要悬停提示的话调用方自己改 mouse_filter。
const OUTLINE_COLOR := Color(0.08, 0.06, 0.12, 1.0)


static func outlined_icon(tex: Texture2D, size: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2), Vector2.ZERO]:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(size - 4, size - 4)
		ic.position = Vector2(2, 2) + off
		ic.texture_filter = Atlas.filter_for(tex)   # 高清图标线性，像素图最近邻
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if off != Vector2.ZERO:
			ic.modulate = OUTLINE_COLOR
		holder.add_child(ic)
	return holder
