extends Control
# 原版 Pokémon Rogue 的玩家信息框（src/ui/battle-info.ts，player = true）：布局数字照原版逻辑像素（320×180 画布），
# 本作整体整数放大 UI_SCALE 倍、最近邻过滤；HD remake 时换 assets/pokerogue_ui 里的同名图即可。
# 原点 = 信息框右边缘的垂直中点（原 box.setOrigin(1, 0.5)）。
const Atlas := preload("res://ui/rogue_atlas.gd")
const BASE_SCALE := 3.0   # 720p 取 3 倍；1080p 取 4 倍（见 place）
var UI_SCALE := BASE_SCALE
const TYPE_EN := {"一般": "normal", "火": "fire", "水": "water", "电": "electric", "草": "grass", "冰": "ice", "格斗": "fighting", "毒": "poison",
	"地面": "ground", "飞行": "flying", "超能力": "psychic", "虫": "bug", "岩石": "rock", "幽灵": "ghost", "龙": "dragon", "恶": "dark",
	"钢": "steel", "妖精": "fairy"}
const BAR_HP := Vector2(-61, -1)
const BAR_EXP := Vector2(-98, 18)
const HP_W := 48.0
const EXP_W := 85.0

var _root: Control          # 逻辑像素容器（scale = UI_SCALE）
var _name: Label
var _fusion_icon: TextureRect
var _lv_digits: Control
var _hp_digits: Control
var _hp_bar: TextureRect
var _exp_bar: TextureRect
var _type1: TextureRect
var _type2: TextureRect
var _status: TextureRect
var _shiny: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.scale = Vector2(UI_SCALE, UI_SCALE)
	add_child(_root)
	var box := TextureRect.new()
	box.texture = Atlas.texture("ui/pbinfo_player.png")
	box.position = Vector2(-130, -21)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_name = Label.new()
	_name.position = Vector2(-115, -17.5)
	_name.add_theme_font_size_override("font_size", 9)
	_name.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	_name.add_theme_color_override("font_shadow_color", Color(0.27, 0.27, 0.27))
	_name.add_theme_constant_override("shadow_offset_x", 1)
	_name.add_theme_constant_override("shadow_offset_y", 1)
	_name.add_theme_constant_override("outline_size", 0)
	_root.add_child(_name)
	_fusion_icon = TextureRect.new()   # 融合了：名字左边一个基因之楔小图标（用户 2026-10-22）
	_fusion_icon.texture = Atlas.frame("icons/items", "dna_splicers")
	_fusion_icon.position = Vector2(-127, -18)
	_fusion_icon.scale = Vector2(0.3, 0.3)
	_fusion_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fusion_icon.visible = false
	_root.add_child(_fusion_icon)
	var lv := TextureRect.new()
	lv.texture = Atlas.texture("ui/overlay_lv.png")
	lv.position = Vector2(-41, -10)
	_root.add_child(lv)
	_lv_digits = Control.new()
	_lv_digits.position = Vector2(-41 + 9.5, -10)
	_root.add_child(_lv_digits)
	_hp_bar = TextureRect.new()
	_hp_bar.position = BAR_HP
	_hp_bar.stretch_mode = TextureRect.STRETCH_KEEP
	_root.add_child(_hp_bar)
	_exp_bar = TextureRect.new()
	_exp_bar.texture = Atlas.texture("ui/overlay_exp.png")
	_exp_bar.position = BAR_EXP
	_exp_bar.stretch_mode = TextureRect.STRETCH_KEEP
	_exp_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_root.add_child(_exp_bar)
	_hp_digits = Control.new()
	_hp_digits.position = Vector2(-15, 6)   # 原版是 10；用户 2026-10-18“血条往上点”：血量数字上提，别压着经验条
	_root.add_child(_hp_digits)
	_type1 = TextureRect.new()
	_type1.position = Vector2(-139, -17)
	_root.add_child(_type1)
	_type2 = TextureRect.new()
	_type2.position = Vector2(-139, -1)
	_root.add_child(_type2)
	_status = TextureRect.new()
	_status.position = Vector2(-115, -6)
	_status.visible = false
	_root.add_child(_status)
	_shiny = Label.new()
	_shiny.position = Vector2(-60, -17.5)
	_shiny.add_theme_font_size_override("font_size", 8)
	_root.add_child(_shiny)


# 摆在屏幕右下角：right / bottom = 距右 / 下边的像素（屏幕像素，不是逻辑像素）。
func place(viewport_size: Vector2, right := 16.0, bottom := 16.0) -> void:
	UI_SCALE = maxf(2.0, roundf(viewport_size.y / 180.0 * 0.7))
	_root.scale = Vector2(UI_SCALE, UI_SCALE)
	position = Vector2(viewport_size.x - right, viewport_size.y - bottom - 21.0 * UI_SCALE)


# 名字 / 等级 / 血 / 经验 / 属性（汉字）/ 状态帧名（"" = 无）。
func set_info(actor_name: String, level: int, hp: float, max_hp: float, xp: float, xp_need: float, types: Array, status_frame := "", mark := "") -> void:
	_name.text = actor_name
	_shiny.text = mark
	_digits(_lv_digits, str(level), false)
	_digits(_hp_digits, hp_pair(hp, max_hp), true)   # 满血不再显示成 46/45
	var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var key := "high" if ratio > 0.5 else ("medium" if ratio > 0.25 else "low")
	var strip := Atlas.frame("ui/overlay_hp", key)
	var w := roundf(HP_W * ratio)
	if strip != null:
		var r := strip.region
		strip.region = Rect2(r.position.x, r.position.y, maxf(w, 0.0), r.size.y)
		_hp_bar.texture = strip
		_hp_bar.size = Vector2(w, 2.0)
	var xr := clampf(xp / maxf(xp_need, 1.0), 0.0, 1.0)
	var xw := roundf(EXP_W * xr)
	var xtex := Atlas.texture("ui/overlay_exp.png")
	var xat := AtlasTexture.new()
	xat.atlas = xtex
	xat.region = Rect2(0, 0, maxf(xw, 0.0), 2.0)
	_exp_bar.texture = xat
	_exp_bar.size = Vector2(xw, 2.0)
	var t1 := str(TYPE_EN.get(str(types[0]), "")) if types.size() > 0 else ""
	var t2 := str(TYPE_EN.get(str(types[1]), "")) if types.size() > 1 else ""
	_type1.texture = Atlas.frame("ui/pbinfo_player_type1", t1) if t1 != "" else null
	_type2.texture = Atlas.frame("ui/pbinfo_player_type2", t2) if t2 != "" else null
	_status.visible = status_frame != ""
	if status_frame != "":
		_status.texture = Atlas.frame("statuses", status_frame)


# 用原版数字图集（numbers，8×8）画数字；right = 右对齐（血量），否则左对齐（等级）。
func _digits(holder: Control, text: String, right: bool) -> void:
	for c in holder.get_children():
		c.queue_free()
		holder.remove_child(c)
	var n := text.length()
	for i in n:
		var tex := Atlas.frame("ui/numbers", text[i])
		if tex == null:
			continue
		var d := TextureRect.new()
		d.texture = tex
		d.position = Vector2((i - n) * 8.0 if right else i * 8.0, 0)
		holder.add_child(d)


# 血量显示成“当前 / 上限”：上限有小数时（闪光 +10% 之类）满血会显示成 46/45（当前向上取整、上限向下取整）。
# 统一成：上限向下取整，当前不超过显示的上限；还活着至少显示 1（用户 2026-10-21 截图）。
static func hp_pair(hp: float, max_hp: float) -> String:
	var mx := maxi(1, int(floor(max_hp)))
	var cur := mini(int(ceil(hp)), mx)
	if hp > 0.0:
		cur = maxi(cur, 1)
	return "%d/%d" % [maxi(cur, 0), mx]


func set_fusion(on: bool) -> void:
	if _fusion_icon != null:
		_fusion_icon.visible = on
