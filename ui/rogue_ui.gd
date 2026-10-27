extends RefCounted
# 原版 Pokémon Rogue 的界面零件（窗口九宫格 / 文字样式 / 图标）。用户 2026-10-18：“他所有 UI 都是口袋妖怪原生的，
# 我们的 UI 应该是他这种感觉”。布局数字一律用**原版逻辑像素**（320×180 画布）写，这里统一乘 K 放到设计画布上：
# 设计画布 640×360 = 原版逻辑画布的 2 倍（中文字用 16 像素的点阵字，在原版画布里相当于 8 像素，所以多放大一倍才够写）；
# 画布本身再整数倍放大到屏幕（ui/rogue_screen.gd），贴图一律最近邻。HD remake 时只换 assets/pokerogue_ui 里的同名图。
const Atlas := preload("res://ui/rogue_atlas.gd")
const DESIGN := Vector2(640, 360)
const K := 2.0
const FONT_LATIN := "res://assets/pokerogue_ui/fonts/pkmnems.ttf"
const FONT_CJK := "res://assets/pokerogue_ui/fonts/unifont.subset.ttf"   # 原版自带的 Galmuri 子集缺 700 多个简体字，中文用 unifont 子集（全覆盖、点阵）

# 原版 text.ts 的文字样式：[字号（设计像素，16 的倍数最清晰）, 字色, 阴影色]
const STYLES := {
	"window": [16, Color("f8f8f8"), Color("6b5a73")],
	"window_alt": [16, Color("484848"), Color("d0d0c8")],
	"summary": [16, Color("f8f8f8"), Color("636363")],
	"summary_alt": [16, Color("484848"), Color("d0d0c8")],
	"summary_red": [16, Color("e70808"), Color("ffbd73")],
	"summary_blue": [16, Color("40c8f8"), Color("006090")],
	"summary_pink": [16, Color("f89890"), Color("984038")],
	"summary_gold": [16, Color("e8e8a8"), Color("a0a060")],
	"summary_gray": [16, Color("a0a0a0"), Color("636363")],
	"party": [16, Color("f8f8f8"), Color("707070")],
	"party_red": [16, Color("f89890"), Color("984038")],
	"tooltip": [16, Color("f8f8f8"), Color("6b5a73")],
	"tooltip_title": [16, Color("e70808"), Color("ffbd73")],
	"small_alt": [16, Color("484848"), Color("d0d0c8")],
	"small": [16, Color("f8f8f8"), Color("6b5a73")],
}

const TYPE_EN := {"一般": "normal", "火": "fire", "水": "water", "电": "electric", "草": "grass", "冰": "ice", "格斗": "fighting", "毒": "poison",
	"地面": "ground", "飞行": "flying", "超能力": "psychic", "虫": "bug", "岩石": "rock", "幽灵": "ghost", "龙": "dragon", "恶": "dark",
	"钢": "steel", "妖精": "fairy"}

static var _font: Font = null
static var _icon_sheet := {}   # 图标帧名 -> 图集名
static var _icon_first_form := {}   # 编号 -> 该编号第一个带形态后缀的帧名（原版图集里 423 只有 423-west / 423-east 没有 423）；闪光另存一份
static var _icon_first_form_shiny := {}


# 拉丁字用原版 pkmnems，中文落到 unifont；关掉抗锯齿和次像素定位，保持点阵的硬边。
static func font() -> Font:
	if _font == null:
		var latin := load(FONT_LATIN) as FontFile
		var cjk := load(FONT_CJK) as FontFile
		var f := latin.duplicate() as FontFile if latin != null else FontFile.new()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		if cjk != null:
			var c := cjk.duplicate() as FontFile
			c.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			c.hinting = TextServer.HINTING_NONE
			c.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			f.fallbacks = [c]
		_font = f
	return _font


# 一行字。x / y 是原版逻辑像素；style 见 STYLES；size < 0 用样式自带字号；width > 0 时在这个宽度（原版逻辑像素）里按 align 对齐。
static func label(parent: Node, text: String, x: float, y: float, style := "window", size := -1, align := HORIZONTAL_ALIGNMENT_LEFT, width := 0.0, wrap := false) -> Label:
	var st: Array = STYLES.get(style, STYLES["window"])
	var l := Label.new()
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # 要先开自动换行再给宽度，否则 Label 会先按整行宽度撑开
	l.text = text
	l.position = Vector2(x, y) * K
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size if size > 0 else int(st[0]))
	l.add_theme_color_override("font_color", st[1])
	l.add_theme_color_override("font_shadow_color", st[2])
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 0)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width * K, 0)
		l.size = Vector2(width * K, 0)
		l.horizontal_alignment = align
	parent.add_child(l)
	return l


# 原版 addWindow：window_<type>[_thin|_xthin] 九宫格，边 8 像素。variant = "" / "_thin" / "_xthin"；type 默认 1（红框）。
static func window(parent: Node, x: float, y: float, w: float, h: float, variant := "", type := 1) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = Atlas.texture("ui/windows/window_%d%s.png" % [type, variant])
	n.patch_margin_left = 8
	n.patch_margin_right = 8
	n.patch_margin_top = 8
	n.patch_margin_bottom = 8
	n.position = Vector2(x, y) * K
	n.scale = Vector2(K, K)
	n.size = Vector2(w, h)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(n)
	return n


# 一张图（整张或图集帧）。scale 是相对原版逻辑像素的缩放（原版 sprite.setScale(0.5) 就传 0.5）。
static func image(parent: Node, tex: Texture2D, x: float, y: float, scale := 1.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_KEEP
	t.position = Vector2(x, y) * K
	t.scale = Vector2(K, K) * scale
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture_filter = Atlas.filter_for(tex)   # 高清物品图标线性，像素图最近邻
	parent.add_child(t)
	return t


static func fill(parent: Node, x: float, y: float, w: float, h: float, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = Vector2(x, y) * K
	r.size = Vector2(w, h) * K
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


# 宝可梦小图标按“实际内容”放进一个框里居中、放大到刚好装下（小个子物种不再缩成一小点）。
# 图标帧是 40×30 的透明画布，内容常常只占 14×16；cx / cy 是框中心，max_w / max_h 是框大小（原版逻辑像素），
# max_scale 是相对原版逻辑像素的最大放大（1.0 = 一贴图像素对一原版像素）。
static func fit_icon(parent: Node, tex: AtlasTexture, cx: float, cy: float, max_w: float, max_h: float, max_scale := 1.0, min_scale := 0.5) -> TextureRect:
	var content := tex.region.size                      # 裁掉透明边之后的内容尺寸（贴图像素）
	var offset := tex.margin.position                   # 内容在 40×30 画布里的位置
	var s := clampf(minf(max_w / maxf(content.x, 1.0), max_h / maxf(content.y, 1.0)), min_scale, max_scale)
	var pos := Vector2(cx, cy) - (offset + content * 0.5) * s
	return image(parent, tex, pos.x, pos.y, s)


# 属性图标：一般 / 火 / …；帧名是英文小写。英文模式用原版英文那套图（2026-10-26 中英切换）。
static func type_icon(zh_type: String) -> AtlasTexture:
	var sheet := "types" if preload("res://game/i18n.gd").language() == "en" else "types_zh-CN"
	return Atlas.frame(sheet, str(TYPE_EN.get(zh_type, "")))


# 选宠格子用的小图标（40×30，原版 pokemon_icons_N 图集）。shiny = 取闪光那套。找不到回 unknown。
static func species_icon(species_id: int, shiny := false) -> AtlasTexture:
	if _icon_sheet.is_empty():
		for n in range(0, 10):
			var f := FileAccess.open(Atlas.BASE + "icons/pokemon_icons_%d.json" % n, FileAccess.READ)
			if f == null:
				continue
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for fr: Dictionary in parsed["textures"][0]["frames"]:
					var fname := str(fr["filename"])
					_icon_sheet[fname] = "icons/pokemon_icons_%d" % n
					# 带形态后缀的帧：“423-west” → 编号 423；“423s-west” → 闪光
					var dash := fname.find("-")
					if dash > 0:
						var head := fname.substr(0, dash)
						if head.is_valid_int():
							if not _icon_first_form.has(int(head)):
								_icon_first_form[int(head)] = fname
						elif head.ends_with("s") and head.trim_suffix("s").is_valid_int():
							if not _icon_first_form_shiny.has(int(head.trim_suffix("s"))):
								_icon_first_form_shiny[int(head.trim_suffix("s"))] = fname
	var key := "%ds" % species_id if shiny else str(species_id)
	if not _icon_sheet.has(key):
		key = str(species_id)
	if not _icon_sheet.has(key):
		# 没有不带后缀的帧：用这个编号的第一个形态帧（33 个物种是这样，以前显示成问号）
		if shiny and _icon_first_form_shiny.has(species_id):
			key = str(_icon_first_form_shiny[species_id])
		elif _icon_first_form.has(species_id):
			key = str(_icon_first_form[species_id])
	if not _icon_sheet.has(key):
		return Atlas.frame("icons/pokemon_icons_0", "unknown")
	return Atlas.frame(str(_icon_sheet[key]), key)
