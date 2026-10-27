extends RefCounted
# 原版 Pokémon Rogue 的 Phaser 图集（TexturePacker JSON + PNG）读取：按帧名给 AtlasTexture。
const BASE := "res://assets/pokerogue_ui/"

static var _tex := {}
static var _frames := {}
static var _margins := {}


static func texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(BASE + path) as Texture2D
	return _tex[path]


# sheet = 图集文件名（不含扩展名，如 "ui/numbers" / "types_zh-CN"）；frame = 帧名。找不到返回 null。
static func frame(sheet: String, frame_name: String) -> AtlasTexture:
	if not _frames.has(sheet):
		var table := {}
		var margins := {}
		var f := FileAccess.open(BASE + sheet + ".json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var list: Array = []
				if parsed.has("textures"):
					list = parsed["textures"][0]["frames"]
				elif parsed.has("frames"):
					list = parsed["frames"]
				for fr: Dictionary in list:
					var r: Dictionary = fr["frame"]
					table[str(fr["filename"])] = Rect2(r["x"], r["y"], r["w"], r["h"])
					# 裁边图集：帧被裁掉了透明边，原来的位置信息在 spriteSourceSize / sourceSize 里（Phaser 会自动补回，这里补成 margin）。
					if bool(fr.get("trimmed", false)) and fr.has("spriteSourceSize") and fr.has("sourceSize"):
						var ss: Dictionary = fr["spriteSourceSize"]
						var src: Dictionary = fr["sourceSize"]
						margins[str(fr["filename"])] = Rect2(ss["x"], ss["y"], float(src["w"]) - float(r["w"]), float(src["h"]) - float(r["h"]))
		_frames[sheet] = table
		_margins[sheet] = margins
	var table: Dictionary = _frames[sheet]
	if not table.has(frame_name):
		return null
	if sheet == "icons/items" and HD_ITEMS:
		var hd := _hd_item(frame_name)
		if hd != null:
			return hd
	var at := AtlasTexture.new()
	at.atlas = texture(sheet + ".png")
	at.region = table[frame_name]
	var mg: Dictionary = _margins.get(sheet, {})
	if mg.has(frame_name):
		at.margin = mg[frame_name]
	return at


# ---- 物品图标高清版（用户 2026-10-25：“hd remake 放进去”）----
# assets/items_hd/<帧名>.png（128×128，透明底）有就用它：贴图报告的大小仍是原版的 32×32（size override），
# 所以所有按原版大小摆的地方不用改；画的时候用的是高清像素（带 mipmap）。画图的控件要用线性过滤（看 meta "hd"）。
const HD_ITEMS := true
const HD_DIR := "res://assets/items_hd/"
const ITEM_SIZE := 32
static var _hd_cache := {}


static func _hd_item(frame_name: String) -> AtlasTexture:
	if not _hd_cache.has(frame_name):
		var tex: ImageTexture = null
		var path := HD_DIR + frame_name + ".png"
		if ResourceLoader.exists(path):
			var src := load(path) as Texture2D
			var img: Image = src.get_image() if src != null else null
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				tex.set_size_override(Vector2i(ITEM_SIZE, ITEM_SIZE))
		_hd_cache[frame_name] = tex
	var t: ImageTexture = _hd_cache[frame_name]
	if t == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(0, 0, ITEM_SIZE, ITEM_SIZE)
	at.set_meta("hd", true)
	return at


# 控件该用的过滤方式：高清图标线性 + mipmap，像素图最近邻。
static func filter_for(tex: Texture2D) -> int:
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if tex != null and tex.has_meta("hd") else CanvasItem.TEXTURE_FILTER_NEAREST

