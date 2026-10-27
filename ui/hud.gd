extends CanvasLayer
# 割草小项目的 HUD。外观照搬主项目（主神模拟器2）城镇 / 城镇战斗那一套：
# 墨色底 + 暗金线 + 中式漆框九宫格（ui/hanb/panel.png、panel_small.png）。
# 主项目是 C#，这里把它用代码搭的样式按原数值重写了一遍，出处见 ui/SOURCES.md。
#
# 用法：
#   hud.set_stats({...}) 每帧调；hud.show_cards([...]) / hud.hide_cards()；hud.show_death() / hud.show_victory()
#   hud.show_banner("头狼来了")   屏幕上方中间提示一行字，过两三秒自己淡掉
#   hud.set_loadout([{name, category, icon}, ...])   这一局带的功法，显示在内力条右边（小图标 + 名字）；不调就不显示
#   hud.set_tags([{text, on}, ...])   功法挂的小字（归元），排在功法后面；on = false 灰掉。可以每帧调，没变就不动
#
# set_stats 的键：time level xp xp_need hp max_hp kills enemies fps points_total points_run，另有
#   points_total / points_run   击杀点数：持久总余额 / 本局获得（0 也显示，右上角击杀面板同行）
#   inner / max_inner / inner_reserved   内力现在多少 / 容量 / 被硬占掉多少点（占掉的那段在条的右头单独画出来）；
#                                        max_inner 是 0 时整行不显示。老的 shield / max_shield 还认，当成没有硬占的内力
#   inner_shield                         龟息诀的盾还能挡几次（-1 = 这一局没有盾）；盾在时内力条亮起、数字换成“盾 · 还能挡 N 次”
#   phase                                计时下面的一行小字（这一波的名字），不给就不显示
# show_cards 的每个选项：name from_lv to_lv effect，可选 id / icon（图标）、category（卡面右上角的小标：外功 / 内功 / 硬功 / 轻功 / 通用）
#   hud.card_picked.connect(func(i): ...)   鼠标点卡片，或卡片显示时按 1/2/3（含小键盘）
#   hud.set_rerolls(n)  三选一下面的“重抽”按钮还剩几次（0 = 按钮灰掉）；hud.reroll_pressed 是点了它或按 R
#
# 卡片界面不用补间、不靠时间推进，Engine.time_scale = 0 时照常能用。

signal card_picked(index: int)
signal evac_pressed   # 计时下面的「撤离」按钮（在一个地区待满 5 分钟才出现）
signal effect_clicked(action: String, step: int)   # 左上角可点的效果图标（护身金币：左键 +1、右键 -1）
signal move_toggled(id: String)   # 左下角技能开关被点了（只在暂停抓宠界面里 main 才会真的切换）
signal reroll_pressed   # 三选一界面上的“重抽”按钮或 R 键（v2.0）

# ---- 主项目 TowerScene.Msm2TownView.cs 的调色板（原数值）----
const TOWN_INK := Color(0.055, 0.050, 0.047, 1.0)
const TOWN_INK_WARM := Color(0.125, 0.098, 0.075, 1.0)
const TOWN_PANEL := Color(0.115, 0.100, 0.088, 0.96)
const TOWN_PANEL_RAISED := Color(0.165, 0.140, 0.118, 0.98)
const TOWN_LINE := Color(0.36, 0.29, 0.19, 1.0)
const TOWN_GOLD := Color(0.87, 0.70, 0.38, 1.0)
const TOWN_PAPER := Color(0.94, 0.90, 0.81, 1.0)
const TOWN_MUTED := Color(0.66, 0.60, 0.50, 1.0)
const TOWN_JADE := Color(0.50, 0.78, 0.60, 1.0)
const TOWN_RED := Color(0.82, 0.36, 0.30, 1.0)
const TOWN_BLUE := Color(0.42, 0.66, 0.90, 1.0)
# 城镇战斗里各块面板的底色（TowerScene.Msm2BattleSkin.cs）
const HUD_PANEL_BG := Color(0.08, 0.07, 0.06, 0.82)
const BAR_BG := Color(0.05, 0.045, 0.04, 1.0)

const CARD_SIZE := Vector2(316, 300)
# 界面迁移包第二期的两个开关（用户目测不喜欢就改成 false 回到原样）：
const CARD_PAPER := false  # 主神模拟器2现行 TownCompactCard 的墨色漆框
const HANB_BARS := false   # 主神模拟器2现行 TownBar 的深底纯色条
const CARD_INK := Color(0.12, 0.10, 0.09)          # 纸牌上的字
const CARD_JADE := Color(0.16, 0.42, 0.26)         # 纸牌上的等级字
# 卡面上类别小标的颜色
const CATEGORY_COLORS := {
	"外功": Color(0.82, 0.36, 0.30, 1.0), "内功": Color(0.42, 0.66, 0.90, 1.0), "硬功": Color(0.87, 0.70, 0.38, 1.0),
	"轻功": Color(0.50, 0.78, 0.60, 1.0), "通用": Color(0.66, 0.60, 0.50, 1.0),
}
const BANNER_SECS := 2.6   # 提示的字显示多久（真实时间）

# ---- 音效（ui/pack/sounds，出处见 SOURCES.md）。AudioStreamPlayer 不受 Engine.time_scale 影响 ----
const SOUNDS := {
	"hover": preload("res://ui/pack/sounds/select_1.wav"),
	"pick": preload("res://ui/pack/sounds/click_double_on.wav"),
	"levelup": preload("res://ui/pack/sounds/synth_process_complete.wav"),
	"death": preload("res://ui/pack/sounds/synth_shut_down.wav"),
}
# 卡片图标：选项里带 id 时找 ICON_DIR/<id>.png（没有这张图就不显示图标）；也可以直接在选项里给 icon: Texture2D
const ICON_DIR := "res://ui/icons/"
const ICON_BOX := 76   # 图标等比缩放到这个边长以内（现在的图标是手绘的 128 像素图，线性采样）
const RESULT_ART := {
	"death": {"tex": preload("res://ui/art/defeat_banner.png"), "band": Vector2(51, 173)},
	"victory": {"tex": preload("res://ui/art/victory_banner.png"), "band": Vector2(33, 119)},
}

var sounds_enabled := true
var sound_volume_db := -6.0
var _players := {}

var _root: Control
var _portrait_panel: PanelContainer
var _portrait: TextureRect
var _portrait_name: Label
var _actor_name := ""
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _shield_row: Control
var _shield_bar: ProgressBar
var _shield_text: Label
var _reserved_block: ColorRect
var _loadout_box: HBoxContainer
var _tag_box: HBoxContainer
var _tag_key := ""
var _timer_label: Label
var _boss_box: VBoxContainer   # 头目血条（用户 10-14 要的）：计时下面，一个头目一条
var _boss_rows: Array = []     # 每条 {"bar": ProgressBar, "text": Label}
var _phase_label: Label
var _banner: Label
var _banner_until_ms := 0
var _kills_label: Label
var _debug_label: Label
var _status_label: Label
var _info_box: Control = null          # 原版玩家信息框（ui/rogue_info_box.gd），替换原来的底栏血条 / 等级 / 经验条
var _info_types: Array = []
var _info_status := ""
var _info_mark := ""
const RogueInfoBox := preload("res://ui/rogue_info_box.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")
const RogueAtlas := preload("res://ui/rogue_atlas.gd")
const Berries := preload("res://game/pokemon_berries.gd")
const USE_ROGUE_INFO_BOX := true   # 抄原版 UI 的开关（用户 2026-10-17）；false 回到原来的底栏

var _cards_layer: Control
var _cards: Array[Button] = []
var _card_parts: Array[Dictionary] = []
var _cards_shown := 0
var _reroll_btn: Button
var _cards_title: Label
var _rerolls := 0

var _death_layer: Control
var _death_summary: Label
var _victory_layer: Control
var _victory_summary: Label
var _victory_title: Label
var _last_time := 0.0
var _last_kills := 0
var _last_level := 1
# 击杀点数最后显示值 + 未保存标记（state.gd 保存失败 / 坏档时通过 set_points_unsaved 维护）。
var _last_points_total := 0
var _last_points_run := 0
var _points_unsaved := false


func _init() -> void:
	layer = 10


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_portrait()
	_build_xp_strip()
	_build_vitals()
	_build_rogue_info_box()
	_build_timer()
	_build_boss_bars()
	_build_kills()
	_build_berries()
	_build_debug()
	_build_cards()
	var d := _build_result("death", "倒下了", TOWN_PAPER, "按 R 重来")
	_death_layer = d["layer"]
	_death_summary = d["summary"]
	var v := _build_result("victory", "通关", TOWN_GOLD, "按 R 再来一局")
	_victory_layer = v["layer"]
	_victory_summary = v["summary"]
	_victory_title = v["title"]
	for key in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = SOUNDS[key]
		add_child(p)
		_players[key] = p


func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _players.values():
		voice.stop()
		voice.stream = null


func _play(key: String) -> void:
	if not sounds_enabled or not _players.has(key):
		return
	var p: AudioStreamPlayer = _players[key]
	p.volume_db = sound_volume_db
	p.play()


# 选项里的 icon（Texture2D）优先；否则按 id 去 ICON_DIR 找；都没有就返回 null
func _icon_for(o: Dictionary) -> Texture2D:
	if o.get("icon") is Texture2D:
		return o["icon"]
	var id := str(o.get("id", ""))
	if id.is_valid_filename() and ResourceLoader.exists(ICON_DIR + id + ".png"):
		return load(ICON_DIR + id + ".png") as Texture2D
	return null


# ================= 对外接口 =================

func set_portrait(texture: Texture2D, actor_name: String) -> void:
	_portrait.texture = texture
	_actor_name = actor_name
	_portrait_name.text = "%s Lv%d" % [_actor_name, _last_level]
	_portrait_panel.visible = false   # 左下头像框不要了（用户 2026-10-18：“底下需要那个头像吗？”）：名字等级血量右下角信息框里都有


func set_stats(s: Dictionary) -> void:
	var t: float = s.get("time", 0.0)
	var level: int = s.get("level", 1)
	var xp: int = s.get("xp", 0)
	var xp_need: int = max(1, int(s.get("xp_need", 1)))
	var hp: float = max(0.0, float(s.get("hp", 0.0)))
	var max_hp: float = max(1.0, float(s.get("max_hp", 1.0)))
	var shield: float = max(0.0, float(s.get("inner", s.get("shield", 0.0))))
	var max_shield: float = max(0.0, float(s.get("max_inner", s.get("max_shield", 0.0))))
	var reserved: float = clampf(float(s.get("inner_reserved", 0.0)), 0.0, max_shield)
	var kills: int = s.get("kills", 0)
	_last_time = t
	_last_kills = kills
	_last_level = level
	_portrait_name.text = "%s Lv%d" % [_actor_name, level]

	# 顶上计时 = 在这个地区待了多久，撤离换地区后从 0 重新计（用户 2026-10-20）；结算仍用整局时间
	_timer_label.text = _mmss(float(s.get("map_time", t)))
	_level_label.text = "等级 %d" % level
	_xp_bar.max_value = xp_need
	_xp_bar.value = clampi(xp, 0, xp_need)
	_xp_text.text = "经验 %d / %d" % [xp, xp_need]

	_hp_bar.max_value = max_hp
	_hp_bar.value = min(hp, max_hp)
	_hp_text.text = RogueInfoBox.hp_pair(hp, max_hp).replace("/", " / ")
	var dot := str(s.get("dot_text", ""))
	if dot != "":
		_hp_text.text += "   " + dot   # 最近 5 秒的持续掉血（中毒 / 灼伤 / 反伤 / 混乱自伤）
	# 没有内力时整行不显示，免得一条永远是空的
	_shield_row.visible = max_shield > 0.0
	if _shield_row.visible:
		_shield_bar.max_value = max_shield
		_shield_bar.value = min(shield, max_shield)
		# 被硬占的那段画在条的右头：暗金色的一块，内力涨不到那里
		_reserved_block.visible = reserved > 0.0
		_reserved_block.anchor_left = 1.0 - reserved / max_shield
		if reserved > 0.0:
			_shield_text.text = "%d / %d · 占 %d" % [int(shield), int(max_shield - reserved), int(round(reserved))]
		else:
			_shield_text.text = "%d / %d" % [int(shield), int(max_shield)]
		_set_shield(int(s.get("inner_shield", -1)))
	if _info_box != null:
		_info_box.call("set_info", _actor_name, level, hp, max_hp, float(xp), float(xp_need), s.get("types", _info_types), _info_status, _info_mark)
		_set_dot_text(str(s.get("dot_text", "")))
		if s.has("stage_rows"):
			_set_stage_icons(s["stage_rows"])   # 图标版（用户 2026-10-25：文字太丑）
		else:
			_set_stage_text(str(s.get("stage_text", "")))
	var phase := str(s.get("phase", ""))
	_phase_label.visible = phase != ""
	_phase_label.text = phase

	# 击杀点数（每只 1 点）：总点数是持久余额，本局是本局获得；0 也一直显示。
	# 未保存时由 _refresh_kills_text() 追加“未保存”，不把没落盘的余额冒充成已保存。
	_last_points_total = int(s.get("points_total", 0))
	_last_points_run = int(s.get("points_run", 0))
	_refresh_kills_text()
	_debug_label.text = "怪 %d · %d 帧" % [int(s.get("enemies", 0)), int(s.get("fps", 0))]


# 未保存标记：state.gd 在保存失败 / 坏档锁定时置真，成功落盘后置假。只在变化时重画。
func set_points_unsaved(unsaved: bool) -> void:
	if _points_unsaved == unsaved:
		return
	_points_unsaved = unsaved
	_refresh_kills_text()


func _refresh_kills_text() -> void:
	var text := "击杀 %d · 总点数 %d · 本局 %d" % [_last_kills, _last_points_total, _last_points_run]
	if _points_unsaved:
		text += " · 未保存"
	_kills_label.text = text


# title：面板顶上那行字（升级三选一用默认；秘籍、撤离面板另传）
func show_cards(options: Array, title := "升级了，选一个") -> void:
	_cards_title.text = title
	_cards_shown = min(options.size(), _cards.size())
	for i in _cards.size():
		var card := _cards[i]
		card.visible = i < _cards_shown
		if not card.visible:
			continue
		var o: Dictionary = options[i]
		var parts := _card_parts[i]
		parts["name"].text = str(o.get("name", ""))
		var nc: Color = o.get("name_color", CARD_INK if CARD_PAPER else TOWN_GOLD)
		if CARD_PAPER and o.has("name_color"):
			nc = nc.darkened(0.35)   # 纸牌是白底，品质色压暗一点才看得清
		parts["name"].add_theme_color_override("font_color", nc)   # 外功按品质上色（v2.1c）
		parts["level"].text = "%d 级 → %d 级" % [int(o.get("from_lv", 0)), int(o.get("to_lv", 0))]
		parts["level"].visible = int(o.get("from_lv", 0)) != 0 or int(o.get("to_lv", 0)) != 0   # 面板（秘籍、撤离）不写等级
		parts["effect"].text = str(o.get("effect", ""))
		var cat := str(o.get("category", ""))
		var tag: PanelContainer = parts["tag"]
		tag.visible = cat != ""
		if cat != "":
			var col: Color = CATEGORY_COLORS.get(cat, TOWN_MUTED)
			parts["tag_text"].text = cat
			parts["tag_text"].add_theme_color_override("font_color", col)
			tag.add_theme_stylebox_override("panel", town_box(Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.92), col.darkened(0.25), 1, 3, 5, true))
		var icon: TextureRect = parts["icon"]
		var fr: TextureRect = parts["frame"]
		fr.texture = o.get("frame") if o.get("frame") is Texture2D else null
		fr.visible = fr.texture != null
		var tex := _icon_for(o)
		icon.texture = tex
		icon.visible = tex != null
		if tex != null:
			var k: float = float(ICON_BOX) / max(1, max(tex.get_width(), tex.get_height()))
			icon.custom_minimum_size = (Vector2(tex.get_width(), tex.get_height()) * k).round()
	_cards_layer.visible = _cards_shown > 0
	if _cards_shown > 0:
		_play("levelup")


# 龟息诀的盾：盾在时内力条亮起、文字换成还能挡几次。n = -1 是这一局没有盾，什么都不改
func _set_shield(n: int) -> void:
	if n < 0:
		return
	_shield_bar.modulate = Color(1.45, 1.45, 1.8) if n > 0 else Color.WHITE
	if n > 0:
		_shield_text.text = "盾 · 还能挡 %d 次" % n


# 这一局带的功法。items 每项：name 名字，category（可选）类别——决定名字的颜色，icon（可选）Texture2D
func set_loadout(items: Array) -> void:
	for child in _loadout_box.get_children():
		_loadout_box.remove_child(child)
		child.queue_free()
	for it: Dictionary in items:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if it.get("icon") is Texture2D:
			var icon := TextureRect.new()
			icon.texture = it["icon"]
			if it.get("frame") is Texture2D:
				var fr2 := TextureRect.new()
				fr2.texture = it["frame"]
				fr2.set_anchors_preset(Control.PRESET_FULL_RECT)
				fr2.offset_left = -4
				fr2.offset_top = -4
				fr2.offset_right = 4
				fr2.offset_bottom = 4
				fr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				fr2.stretch_mode = TextureRect.STRETCH_SCALE
				fr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
				icon.add_child(fr2)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(30, 30)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)
		var col: Color = CATEGORY_COLORS.get(str(it.get("category", "")), TOWN_PAPER)
		# 招式名换成原版小窗口，和商店 / 详情页同一套皮肤；名字下面一行“开 / 关”就是开关（暂停时点，关掉的招不放）
		var on: bool = bool(it.get("on", true))
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", RogueSkin.box(2 if on else 5, "_thin", 2))
		var pcol := VBoxContainer.new()
		pcol.add_theme_constant_override("separation", 0)
		pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(pcol)
		var nm := RogueSkin.label(str(it.get("name", "")), RogueSkin.SIZE_SMALL, "window" if on else "summary_gray")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pcol.add_child(nm)
		if it.has("id"):
			var sw := RogueSkin.label("● 开" if on else "○ 关", RogueSkin.SIZE_SMALL, "summary_blue" if on else "summary_gray")
			sw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pcol.add_child(sw)
			plate.mouse_filter = Control.MOUSE_FILTER_STOP
			plate.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var mid := str(it["id"])
			plate.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					move_toggled.emit(mid))
		else:
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(plate)
		_loadout_box.add_child(cell)
	_loadout_box.visible = not items.is_empty()


func set_tags(tags: Array) -> void:
	var key := str(tags)
	if key == _tag_key:
		return
	_tag_key = key
	for child in _tag_box.get_children():
		_tag_box.remove_child(child)
		child.queue_free()
	for t: Dictionary in tags:
		var on: bool = t.get("on", true)
		_tag_box.add_child(town_label(str(t.get("text", "")), 14, TOWN_GOLD if on else Color(0.42, 0.40, 0.37), false, true))


# 屏幕上方中间提示一行字（“头狼来了”“被围住了”），过两三秒淡掉。用真实时间，不受暂停影响
func show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner.visible = text != ""
	_banner_until_ms = Time.get_ticks_msec() + int(BANNER_SECS * 1000.0)


func _process(_delta: float) -> void:
	_dex_card_tick()
	_tip_tick()
	if _banner != null and _banner.visible:
		var left := (_banner_until_ms - Time.get_ticks_msec()) / 1000.0
		if left <= 0.0:
			_banner.visible = false
		else:
			_banner.modulate.a = clampf(left / 0.6, 0.0, 1.0)


var _evac_btn: Button = null


func set_evac_ready(on: bool) -> void:
	if _evac_btn != null:
		_evac_btn.visible = on


func set_rerolls(n: int) -> void:
	_rerolls = n
	if _reroll_btn != null:
		_reroll_btn.visible = n >= 0   # -1 = 这不是升级三选一（秘籍、撤离面板），不显示重抽
		_reroll_btn.text = "重抽这三张（还剩 %d 次）· R" % maxi(0, n)
		_reroll_btn.disabled = n <= 0


func hide_cards() -> void:
	_cards_shown = 0
	_cards_layer.visible = false


# lines：结算页另外几行（进账多少点、这局拿到的秘籍……，v2.1c）
func show_death(lines: Array = []) -> void:
	hide_cards()
	if not _death_layer.visible:
		_play("death")
	# 未保存时结算页也写清：本局点数和余额里有一部分没落盘，不能当成已保存。
	if _points_unsaved:
		lines = lines.duplicate()
		lines.append("点数未保存：本次进账没有写入磁盘")
	_death_summary.text = "
".join(["撑了 %s · 等级 %d · 击杀 %d" % [_mmss(_last_time), _last_level, _last_kills]] + lines)
	_death_layer.visible = true


# 通关（撑满时间）。样子和倒下那张一样，换成蓝色横幅；小结同样取最后一次 set_stats 的数
# title 换横幅上的字（撤离时写“撤离”）
func show_victory(lines: Array = [], title := "通关") -> void:
	hide_cards()
	if not _victory_layer.visible:
		_play("levelup")
	# 未保存时结算页也写清：本局点数和余额里有一部分没落盘，不能当成已保存。
	if _points_unsaved:
		lines = lines.duplicate()
		lines.append("点数未保存：本次进账没有写入磁盘")
	_victory_title.text = title
	_victory_summary.text = "
".join(["撑过 %s · 等级 %d · 击杀 %d" % [_mmss(_last_time), _last_level, _last_kills]] + lines)
	_victory_layer.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3 and _debug_label != null:
		_debug_label.visible = not _debug_label.visible
		return
	if _cards_shown <= 0 or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		get_viewport().set_input_as_handled()
		if _rerolls > 0:
			reroll_pressed.emit()
		return
	var i: int = [KEY_1, KEY_2, KEY_3].find(event.physical_keycode)
	if i < 0:
		i = [KEY_KP_1, KEY_KP_2, KEY_KP_3].find(event.physical_keycode)
	if i >= 0 and i < _cards_shown:
		get_viewport().set_input_as_handled()
		_play("pick")
		card_picked.emit(i)


func _on_card_pressed(i: int) -> void:
	if i < _cards_shown:
		_play("pick")
		card_picked.emit(i)


func _on_card_hover() -> void:
	if _cards_shown > 0:
		_play("hover")


# ================= 样式（照主项目重写）=================

# 对应主项目 TownBox。用户 2026-10-17：“把这个里面的 UI 的框去掉换成一个线”——不再用漆框九宫格（带四角花纹），
# 统一成一条细线（选中 border_width >= 2 时线加粗、全亮；平时线半透明，不抢字）。
static func town_box(bg: Color, border: Color, border_width := 1, radius := 4, padding := 14, _flat := false) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	var line := border
	if border_width < 2:
		line.a = border.a * 0.45
	box.border_color = line
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = max(0, padding - 2)
	box.content_margin_bottom = max(0, padding - 2)
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(mini(radius, 2))
	return box


# 主项目 TownButton；保留函数名供现有页面调用。
static func hanb_button(text: String, font_size := 20, min_size := Vector2(220, 52), filled := false, accent := TOWN_GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", RogueSkin.RogueUI.font())
	b.add_theme_font_size_override("font_size", font_size)
	var normal: Color = accent if filled else TOWN_PANEL_RAISED
	var hover: Color = accent.lightened(0.12) if filled else accent.darkened(0.55)
	b.add_theme_stylebox_override("normal", town_box(normal, accent, 1, 4, 8))
	b.add_theme_stylebox_override("hover", town_box(hover, accent.lightened(0.2), 1, 4, 8))
	b.add_theme_stylebox_override("pressed", town_box(accent.darkened(0.35), accent, 1, 4, 8))
	b.add_theme_stylebox_override("focus", town_box(Color(0, 0, 0, 0), accent.lightened(0.2), 1, 4, 8))
	b.add_theme_stylebox_override("disabled", town_box(TOWN_PANEL, TOWN_LINE.darkened(0.3), 1, 4, 8))
	b.add_theme_color_override("font_color", TOWN_INK if filled else accent.lightened(0.15))
	b.add_theme_color_override("font_hover_color", TOWN_INK if filled else TOWN_PAPER)
	b.add_theme_color_override("font_pressed_color", TOWN_PAPER)
	b.add_theme_color_override("font_disabled_color", TOWN_MUTED.darkened(0.25))
	return b


# 主项目 TownBackdrop 的暖墨色渐变。
static func town_background() -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([TOWN_INK_WARM, TOWN_INK, Color(0.03, 0.03, 0.035)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0.35, 1)
	texture.width = 64
	texture.height = 256
	var bg := TextureRect.new()
	bg.texture = texture
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


static func fit_page(root: Control, available: Vector2, minimum: Vector2) -> void:
	var design := Vector2(maxf(minimum.x, available.x), maxf(minimum.y, available.y))
	var factor := minf(available.x / design.x, available.y / design.y)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.size = design
	root.scale = Vector2.ONE * factor
	root.position = (available - design * factor) * 0.5


# 品质框（绿 / 蓝 / 金 / 暗金 / 红，ui/hanb/frame_*.png）；没有这一档就返回 null
static func quality_frame(q: String) -> Texture2D:
	var path := "res://ui/hanb/frame_%s.png" % q
	return load(path) if q != "" and ResourceLoader.exists(path) else null


static func town_label(text: String, size: int, color: Color, wrap := false, outline := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", RogueSkin.RogueUI.font())   # 原版点阵字体（用户 2026-10-18：界面都换原生的）
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if outline:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 5)
	return label


# 对应主项目 TownBar / 城镇战斗血条：深底 + 纯色填充，描边比填充亮一档。
# 汉 B 纸牌（三选一卡片）的九宫格；tint 是悬停时提亮
static func _paper_box(tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://ui/hanb/card_paper.png")
	sb.texture_margin_left = 40
	sb.texture_margin_right = 40
	sb.texture_margin_top = 44
	sb.texture_margin_bottom = 44
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 30
	sb.content_margin_bottom = 58   # 底边的云纹角花约 55 像素高，字别压上去
	sb.modulate_color = tint
	return sb


# 汉 B 的条（ui/hanb/bar_*.png）：kind = "empty" / "red" / "green" / "blue"
static func _hanb_bar_box(kind: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://ui/hanb/bar_%s.png" % kind)
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 8
	sb.texture_margin_bottom = 8
	return sb


# 底栏的条换成汉 B 的（HANB_BARS）；kind 是满的那一截用哪种颜色
static func hanb_bar(kind: String, height: int) -> ProgressBar:
	var bar := town_bar(TOWN_GOLD, height)
	if HANB_BARS and ResourceLoader.exists("res://ui/hanb/bar_%s.png" % kind):
		bar.add_theme_stylebox_override("background", _hanb_bar_box("empty"))
		bar.add_theme_stylebox_override("fill", _hanb_bar_box(kind))
	return bar


static func town_bar(fill: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = 1
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", town_box(BAR_BG, TOWN_LINE.darkened(0.2), 1, 3, 0))
	bar.add_theme_stylebox_override("fill", town_box(fill, fill.lightened(0.15), 1, 3, 0))
	return bar


# 头目血条：list = [{"name": 头目名, "hp": 现在的血, "max": 血上限, "segments": 段数, "index": 当前段}]
# 空数组就全藏起来。同时有几个头目就上下几条（20:00 以后可能两个）。
# 段数 >1 时按原 source `round(maxHP/N*k)/maxHP` 加原分界位置；明暗关系照原
# `t.bossSegmentIndex>=l`：所有 `l <= index` 的剩余分界都亮，`l > index` 的暗。
# 普通怪没有 segments 字段（或 segments<=1），不显示任何分界。
func set_bosses(list: Array) -> void:
	while _boss_rows.size() < list.size():
		_boss_rows.append(_make_boss_row())
	var s := _boss_scale()
	for k in _boss_rows.size():
		var row: Dictionary = _boss_rows[k]
		var on := k < list.size()
		row["holder"].visible = on
		if on:
			var b: Dictionary = list[k]
			var mx: float = maxf(1.0, float(b["max"]))
			var hp: float = clampf(float(b["hp"]), 0.0, mx)
			var segments := int(b.get("segments", 0))
			var index := int(b.get("index", -1))
			row["holder"].custom_minimum_size = BOSS_BOX_PX * s
			row["art"].scale = Vector2(s, s)
			row["name"].position = Vector2(8, 2) * s
			row["name"].add_theme_font_size_override("font_size", 16 if s < 4.0 else 24)
			row["name"].text = str(b["name"])
			row["text"].text = "%s    %s" % [b["name"], RogueInfoBox.hp_pair(hp, mx).replace("/", " / ")]   # 只留给检查读；画面上数字用原版数字图
			# 原版 overlay_hp_boss：过半绿、过四分之一黄、其余红；按比例截宽度
			var ratio := hp / mx
			var strip := RogueAtlas.frame("ui/overlay_hp_boss", "high" if ratio > 0.5 else ("medium" if ratio > 0.25 else "low"))
			var w := roundf(BOSS_HP_W * ratio)
			if strip != null:
				var r := strip.region
				strip.region = Rect2(r.position.x, r.position.y, maxf(w, 0.0), r.size.y)
			row["strip"].texture = strip
			row["strip"].size = Vector2(w, 4.0)
			_boss_digits(row["digits"], RogueInfoBox.hp_pair(hp, mx))
			_set_boss_dividers(row, mx, segments, index)
	_boss_box.visible = not list.is_empty()
	var push := 0 if list.is_empty() else int((BOSS_BOX_PX.y * s + 6.0) * list.size()) + 8
	_banner.offset_top = 128 + push
	_banner.offset_bottom = 174 + push


# 头目框放大倍数：720p / 1080p 都是 2 倍（约 356 像素宽），4K 才 4 倍。
# 用户 2026-10-20：原来和右下信息框一样 3–4 倍，太挡视野。
func _boss_scale() -> float:
	var h := _root.size.y if _root != null and _root.size.y > 0.0 else 720.0
	return maxf(2.0, floorf(h / 540.0))


# 原版数字图（ui/numbers，8×8）右对齐画在框右上。
func _boss_digits(holder: Control, text: String) -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var n := text.length()
	for i in n:
		var tex := RogueAtlas.frame("ui/numbers", text[i])
		if tex == null:
			continue
		var d := TextureRect.new()
		d.texture = tex
		d.position = Vector2((i - n) * 8.0, 0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(d)


# 原 source 分界：k=1..N-1（l 就是 k）时位置 = round(maxHP/N*k)/maxHP（在血条上 0..1）。
# 明暗照原 `updateBossSegmentDividers`：`t.bossSegmentIndex >= l ? bright : dark`；
# bright 白、dark 深灰（原版 0xffffff / 0x404040），1 像素宽，压在血条那两行上。
# 界线只做显示，不改变血条数值 / 判定。
func _set_boss_dividers(row: Dictionary, max_hp: float, segments: int, index: int) -> void:
	var dividers: Array = row["dividers"]
	var want := maxi(0, segments - 1)
	while dividers.size() < want:
		var line := ColorRect.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_top = 0.0
		line.anchor_bottom = 1.0
		line.offset_left = 0.0
		line.offset_right = 1.0
		line.color = BOSS_DIVIDER_DARK
		row["slot"].add_child(line)
		dividers.append(line)
	for k in dividers.size():
		var line: ColorRect = dividers[k]
		if k >= want:
			line.visible = false
			continue
		line.visible = true
		var l := k + 1
		var frac := clampf(float(round(max_hp / float(segments) * float(l))) / max_hp, 0.0, 1.0)
		line.anchor_left = frac
		line.anchor_right = frac
		# 源：`bossSegmentIndex >= l` 的剩余分界全亮（index 4/N5 -> 全部；index 2/N5 -> 前两条）。
		line.color = BOSS_DIVIDER_BRIGHT if index >= l else BOSS_DIVIDER_DARK


func _build_boss_bars() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_box.offset_left = -300
	_boss_box.offset_right = 300
	_boss_box.offset_top = 128   # 让开右上角暂停那排按钮（y 84–120）
	_boss_box.add_theme_constant_override("separation", 6)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	_root.add_child(_boss_box)


# 原版头目信息框（pbinfo_enemy_boss，178×31，带“BOSS”字样）：名字在上半截，血条槽在下面（x 69、宽 86、两行高）。
# 贴图都按原版逻辑像素摆在 art 里、整体放大；名字用点阵字另摆（不跟着贴图放大，免得糊）。
const BOSS_BOX_PX := Vector2(178, 31)
const BOSS_HP_POS := Vector2(69, 18)   # overlay_hp_boss 每帧 86×4，有颜色的是第 2、3 行，正好落在槽里（y 20–21）
const BOSS_HP_W := 86.0
const BOSS_DIVIDER_BRIGHT := Color(1, 1, 1)
const BOSS_DIVIDER_DARK := Color("404040")


func _make_boss_row() -> Dictionary:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boss_box.add_child(holder)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)
	var frame := TextureRect.new()
	frame.texture = RogueAtlas.texture("ui/pbinfo_enemy_boss.png")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(frame)
	var strip := TextureRect.new()
	strip.position = BOSS_HP_POS
	strip.stretch_mode = TextureRect.STRETCH_KEEP
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(strip)
	# 分界线挂在和血条槽一样大的透明块上，anchor 0..1 = 血条 0..满
	var slot := Control.new()
	slot.position = BOSS_HP_POS + Vector2(0, 2)
	slot.size = Vector2(BOSS_HP_W, 2)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(slot)
	var digits := Control.new()
	digits.position = Vector2(170, 5)
	digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(digits)
	var name_label := RogueSkin.label("", 24, "window")
	holder.add_child(name_label)
	var text := Label.new()   # 不显示，只给检查读“名字 血/上限”
	text.visible = false
	holder.add_child(text)
	return {"holder": holder, "bar": holder, "art": art, "strip": strip, "slot": slot, "digits": digits, "name": name_label, "text": text, "dividers": []}


# ================= 搭界面 =================

var _xp_strip_row: Control = null
var _vitals_panel: PanelContainer = null
var _vitals_hp_row: Control = null


func _build_xp_strip() -> void:
	# 贴着屏幕底边一整条：等级 | 经验条 | 数字
	var row := HBoxContainer.new()
	_xp_strip_row = row
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = -30
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)
	_level_label = town_label("等级 1", 18, TOWN_GOLD, false, true)
	_level_label.custom_minimum_size = Vector2(72, 0)
	row.add_child(_level_label)
	_xp_bar = hanb_bar("green", 16) if HANB_BARS else town_bar(TOWN_GOLD, 12)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_xp_bar)
	_xp_text = town_label("经验 0 / 1", 14, TOWN_PAPER, false, true)
	_xp_text.custom_minimum_size = Vector2(110, 0)
	_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_xp_text)


# 抄原版 Pokémon Rogue 的玩家信息框（右下角）：名字 / 等级 / 血条 / 血量数字 / 经验条 / 属性图标；
# 原来的底栏血条、等级条、经验条仍在（测试读它们的文字），只是藏起来。
func _build_rogue_info_box() -> void:
	if not USE_ROGUE_INFO_BOX:
		return
	_info_box = RogueInfoBox.new()
	_root.add_child(_info_box)
	_vitals_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_vitals_panel.offset_right = -560   # 给右下角的信息框让位，招式列表留在左边
	_vitals_panel.offset_left = 16      # 头像框撤了，招式列表贴左边
	_vitals_hp_row.visible = false
	_xp_strip_row.visible = false
	_root.resized.connect(_place_info_box)
	_place_info_box()


func _place_info_box() -> void:
	if _info_box != null:
		_info_box.call("place", _root.size)


# 状态异常（汉字）-> 原版状态图标帧名；没有 / 混乱（原版是另一套）返回 ""。
const STATUS_FRAME := {"中毒": "poison", "剧毒": "toxic", "麻痹": "paralysis", "睡眠": "sleep", "冰冻": "freeze", "灼伤": "burn"}


# types = 汉字属性数组；mark = 头顶那种“★ 闪光”之类的短标记（可空）。
# 融合了：右下角信息框名字左边挂基因之楔（main 开局时调）。
func set_fusion_mark(on: bool) -> void:
	if _info_box != null:
		_info_box.call("set_fusion", on)


func set_info_extra(types: Array, status_text := "", mark := "") -> void:
	_info_types = types
	_info_status = str(STATUS_FRAME.get(status_text, ""))
	_info_mark = mark


func _build_portrait() -> void:
	# 主项目 EnsureMsm2PortraitPanel，适配本项目底栏。
	_portrait_panel = PanelContainer.new()
	_portrait_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait_panel.offset_left = 16
	_portrait_panel.offset_right = 114
	_portrait_panel.offset_top = -140
	_portrait_panel.offset_bottom = -34
	_portrait_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_panel.add_theme_stylebox_override("panel", town_box(Color(0.08, 0.07, 0.06, 0.9), TOWN_GOLD, 2, 4, 4))
	_portrait_panel.visible = false
	_root.add_child(_portrait_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_panel.add_child(box)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_portrait)
	_portrait_name = town_label("", 13, TOWN_PAPER)
	_portrait_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_portrait_name)


func _build_vitals() -> void:
	# 底部正中、经验条上面：生命和护盾并排成一行，压得矮一点，少挡从下面来的怪
	var panel := PanelContainer.new()
	_vitals_panel = panel
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 124
	panel.offset_right = -16
	panel.offset_bottom = -34
	panel.offset_top = -106
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", town_box(HUD_PANEL_BG, TOWN_LINE, 1, 4, 8))
	_root.add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var hp := _vital_row("生命", TOWN_RED)
	_vitals_hp_row = hp["row"]
	box.add_child(hp["row"])
	_hp_bar = hp["bar"]
	_hp_text = hp["text"]
	var sh := _vital_row("内力", TOWN_BLUE)
	box.add_child(sh["row"])
	_shield_row = sh["row"]
	_shield_bar = sh["bar"]
	_shield_text = sh["text"]
	_reserved_block = ColorRect.new()
	_reserved_block.color = Color(TOWN_GOLD.r * 0.62, TOWN_GOLD.g * 0.62, TOWN_GOLD.b * 0.62, 0.95)
	_reserved_block.anchor_left = 1.0
	_reserved_block.anchor_right = 1.0
	_reserved_block.anchor_top = 0.0
	_reserved_block.anchor_bottom = 1.0
	_reserved_block.offset_top = 1
	_reserved_block.offset_bottom = -1
	_reserved_block.offset_right = -1
	_reserved_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reserved_block.visible = false
	_shield_bar.add_child(_reserved_block)
	# 这一局带的功法：三个小图标加名字，排在内力条右边
	_loadout_box = HBoxContainer.new()
	_loadout_box.add_theme_constant_override("separation", 12)
	_loadout_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loadout_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loadout_box.visible = false
	box.add_child(_loadout_box)
	_tag_box = HBoxContainer.new()
	_tag_box.add_theme_constant_override("separation", 8)
	_tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_tag_box)
	# 异常状态标识（中毒 / 麻痹 / 睡眠 / 冰冻 / 灼伤 / 混乱）：有状态才显示，没状态不占位。
	# 只做「用户看得懂的状态反馈」，不重排技能 / 属性 / 地图那几页。位置在生命条面板正上方居中。
	# 原版样式：主要异常用原版状态图标（statuses 图集，放大 3 倍），混乱原版没有图标，用点阵字小窗口。
	var status_box := HBoxContainer.new()
	_status_box = status_box
	status_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status_box.offset_bottom = -110
	status_box.add_theme_constant_override("separation", 8)
	status_box.alignment = BoxContainer.ALIGNMENT_CENTER
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.visible = false
	_root.add_child(status_box)
	_status_icon = TextureRect.new()
	_status_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_status_icon.custom_minimum_size = Vector2(60, 24)
	_status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_icon.visible = false
	status_box.add_child(_status_icon)
	_status_plate = PanelContainer.new()
	_status_plate.add_theme_stylebox_override("panel", RogueSkin.box(3, "_thin", 2))
	_status_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_plate.visible = false
	status_box.add_child(_status_plate)
	_status_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "window")
	_status_label.visible = false
	_status_plate.add_child(_status_label)


var _status_box: HBoxContainer = null
var _status_icon: TextureRect = null
var _status_plate: PanelContainer = null


# text 空 = 没有异常状态，整行隐藏。text 形如“中毒 · 混乱”：有原版图标的画图标，其余（混乱 / 没图标的）写字。
func set_player_status(text: String) -> void:
	var names: Array = []
	for part in text.split(" "):
		if part != "" and part != "·":
			names.append(part)
	var frame_name := ""
	var words: Array = []
	for n in names:
		var f := str(STATUS_FRAME.get(n, ""))
		if f != "" and frame_name == "":
			frame_name = f
		else:
			words.append(n)
	_info_status = frame_name
	if _status_label == null:
		return
	_status_label.text = " ".join(words)
	_status_label.visible = not words.is_empty()
	_status_plate.visible = not words.is_empty()
	_status_icon.visible = frame_name != ""
	if frame_name != "":
		_status_icon.texture = RogueAtlas.frame("statuses", frame_name)
	_status_box.visible = text != ""


func _vital_row(caption: String, fill: Color) -> Dictionary:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(200, 0)
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := town_label(caption, 14, TOWN_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var text := town_label("0 / 0", 15, TOWN_PAPER)
	head.add_child(text)
	column.add_child(head)
	var bar := town_bar(fill, 12)
	if HANB_BARS:
		bar = hanb_bar("red" if caption == "生命" else "blue", 20)
	column.add_child(bar)
	return {"row": column, "bar": bar, "text": text}


func _build_timer() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", RogueSkin.box(1, "_thin", 0))
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	_timer_label = town_label("00:00", 30, TOWN_GOLD)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.custom_minimum_size = Vector2(96, 0)
	column.add_child(_timer_label)
	_phase_label = town_label("", 14, TOWN_MUTED)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.visible = false
	column.add_child(_phase_label)
	# 提示的字：计时下面一点，直接压在画面上
	# 撤离按钮：计时窗口下面，金色，待满 5 分钟才出现（main/meta_flow.gd _evac_tick）
	_evac_btn = RogueSkin.button("撤离 [X]", RogueSkin.SIZE_SMALL, Vector2(110, 34), true, "gold")
	_evac_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_evac_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_evac_btn.offset_left = -55
	_evac_btn.offset_right = 55
	_evac_btn.offset_top = 88
	_evac_btn.visible = false
	_evac_btn.pressed.connect(func(): evac_pressed.emit())
	_root.add_child(_evac_btn)
	_banner = town_label("", 34, TOWN_PAPER, false, true)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 104
	_banner.offset_bottom = 150
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_root.add_child(_banner)


# 树果显示（画面右边中间，有树果才出现）：每种一行“图标 ×个数”，带着就会自动吃（规则见 game/pokemon_berries.gd）。
var _berry_panel: PanelContainer = null
var _berry_box: VBoxContainer = null
var _berry_key := ""


func _build_berries() -> void:
	_berry_panel = PanelContainer.new()
	_berry_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_berry_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_berry_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_berry_panel.offset_right = -16
	_berry_panel.offset_left = -16
	_berry_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_berry_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # 不要黑底框，图标和数字直接浮在画面上、只描边（用户 2026-10-19）
	_berry_panel.visible = false
	_root.add_child(_berry_panel)
	_berry_box = VBoxContainer.new()
	_berry_box.add_theme_constant_override("separation", 6)
	_berry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_berry_panel.add_child(_berry_box)


# counts：{"SITRUS": 个数, "LUM": 个数}；全 0 就整块收起。数没变不重画。
func set_berries(counts: Dictionary) -> void:
	var key := str(counts)
	if key == _berry_key or _berry_box == null:
		return
	_berry_key = key
	for c in _berry_box.get_children():
		_berry_box.remove_child(c)
		c.queue_free()
	var any := false
	for kind: String in Berries.KINDS:
		var n := int(counts.get(kind, 0))
		if n <= 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 图标描边：同一张图向四周错开 2 像素各放一份黑色的垫在后面，再放彩色的在上面
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(40, 40)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := RogueAtlas.frame("icons/items", Berries.icon_name(kind))
		for off in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2), Vector2.ZERO]:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.size = Vector2(36, 36)
			ic.position = Vector2(2, 2) + off
			ic.texture_filter = RogueAtlas.filter_for(tex)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if off != Vector2.ZERO:
				ic.modulate = Color(0.08, 0.06, 0.12, 1.0)   # 描边色：深紫黑
			holder.add_child(ic)
		row.add_child(holder)
		var cnt := RogueSkin.label("×%d" % n, RogueSkin.SIZE_BODY, "window")
		cnt.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 1.0))
		cnt.add_theme_constant_override("outline_size", 8)   # 数字描边
		row.add_child(cnt)
		_berry_box.add_child(row)
	_berry_panel.visible = any


func _build_kills() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -16
	panel.offset_left = -16
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", RogueSkin.box(1, "_thin", 0))
	_root.add_child(panel)
	_kills_label = town_label("击杀 0 · 总点数 0 · 本局 0", 16, TOWN_PAPER)
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label.custom_minimum_size = Vector2(240, 0)
	panel.add_child(_kills_label)


# 右侧的“场上稀有 / 神兽 / 闪光”列表（用户 2026-10-18）：每种一行，同种同标记合并成「×N」，不挨个列。
# list 每项 {"text": 「超梦（神兽）」, "color": Color, "count": 个数}；没变就不重画。
# 起点让开右上角暂停那排按钮（y 84–120），不然暂停时神兽名字被“设置 / 继续”盖住（用户 2026-10-21 截图）
const NOTABLE_TOP := 128
const NOTABLE_FONT := 20
const NOTABLE_OUTLINE := 10
var _notable_box: VBoxContainer = null
var _notable_key := ""


func set_notables(list: Array) -> void:
	var key := str(list)
	if key == _notable_key:
		return
	_notable_key = key
	if _notable_box == null:
		_notable_box = VBoxContainer.new()
		_notable_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_notable_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_notable_box.offset_right = -16
		_notable_box.offset_left = -16
		_notable_box.offset_top = NOTABLE_TOP
		_notable_box.add_theme_constant_override("separation", 2)
		_notable_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_notable_box)
	for c in _notable_box.get_children():
		_notable_box.remove_child(c)
		c.queue_free()
	for row: Dictionary in list:
		var text := str(row["text"])
		if int(row.get("count", 1)) > 1:
			text += " ×%d" % int(row["count"])
		var lab := town_label(text, NOTABLE_FONT, row["color"], false, true)
		lab.add_theme_constant_override("outline_size", NOTABLE_OUTLINE)   # 描边加粗（用户 2026-10-21），怪堆里也看得清
		lab.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 1.0))
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notable_box.add_child(lab)


# 左上角“这局带着什么”（用户 2026-10-20：原版左上角那排道具图标）：闪光加成 / 镜片 / 被动，一排原版道具图标，
# 右下角小数字（镜片等级）；说明只在鼠标悬停时出（用户：“不用详细写，就是悬停显示”）。
# list 每项 {"icon": icons/items 里的帧名, "text": 悬停说明, "badge": 角标（可省）}；空数组就藏起来；没变不重画。
var _effects_box: HFlowContainer = null
var _effects_key := ""


func set_effects(list: Array) -> void:
	var key := str(list)
	if key == _effects_key:
		return
	_effects_key = key
	if _effects_box == null:
		# 放不下就换行往下排，不压中间的计时框（用户 2026-10-25：道具多了压住了）
		_effects_box = HFlowContainer.new()
		_effects_box.position = Vector2(14, 12)
		_effects_box.add_theme_constant_override("h_separation", 4)
		_effects_box.add_theme_constant_override("v_separation", 6)
		_effects_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_effects_box)
	# 宽度到计时框左边为止（计时框居中、最宽约 400）
	_effects_box.custom_minimum_size = Vector2(maxf(220.0, _root.size.x * 0.5 - 200.0), 0)
	_effects_box.size = Vector2(_effects_box.custom_minimum_size.x, 0)
	for c in _effects_box.get_children():
		_effects_box.remove_child(c)
		c.queue_free()
	for it: Dictionary in list:
		var ic := RogueSkin.outlined_icon(RogueAtlas.frame("icons/items", str(it.get("icon", ""))), 40)   # 描边和树果一样
		ic.mouse_filter = Control.MOUSE_FILTER_STOP   # 要吃鼠标才有悬停提示
		ic.tooltip_text = str(it.get("text", ""))
		var act := str(it.get("action", ""))
		if act != "":
			ic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			ic.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed:
					if e.button_index == MOUSE_BUTTON_LEFT:
						effect_clicked.emit(act, 1)
						ic.accept_event()
					elif e.button_index == MOUSE_BUTTON_RIGHT:
						effect_clicked.emit(act, -1)
						ic.accept_event())
		var badge := str(it.get("badge", ""))
		if badge != "":
			var b := RogueSkin.label(badge, RogueSkin.SIZE_SMALL, str(it.get("style", "window")))
			b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			b.grow_vertical = Control.GROW_DIRECTION_BEGIN
			b.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 1.0))
			b.add_theme_constant_override("outline_size", 6)
			ic.add_child(b)
		_effects_box.add_child(ic)
	_effects_box.visible = not list.is_empty()


# 第一次抓到某个物种：右下角（信息框上面）弹一张“新登记！”卡片 3 秒；一球抓到好几只就排队一张一张出。
# shiny = -1 普通 / 0 金 / 1 蓝 / 2 红。
const DEX_CARD_SECS := 3.0
const DEX_CARD_QUEUED_SECS := 1.0   # 后面还有排队的：这张停 1 秒就被下一张顶掉（用户 2026-10-20：一次抓到好几只）
const DEX_TIER_TEXT := ["★ 闪光", "★★ 蓝闪", "★★★ 红闪"]
const DEX_TIER_STYLE := ["summary_gold", "summary_blue", "summary_red"]
var _dex_queue: Array = []
var _dex_card: PanelContainer = null
var _dex_until_ms := 0
var _dex_shown_ms := 0


# title：卡片顶上那行（默认“新登记！”；抓到这个物种第一次的某档闪光时是“新闪光！”，用户 2026-10-21）
func show_dex_entry(portrait: Texture2D, species_id: int, species_name: String, shiny := -1, title := "新登记！") -> void:
	_dex_queue.append([portrait, species_id, species_name, shiny, title])
	if _dex_card == null or not _dex_card.visible:
		_next_dex_card()


func _next_dex_card() -> void:
	if _dex_queue.is_empty():
		if _dex_card != null:
			_dex_card.visible = false
		return
	var it: Array = _dex_queue.pop_front()
	if _dex_card != null:
		_dex_card.queue_free()
	_dex_card = PanelContainer.new()
	_dex_card.add_theme_stylebox_override("panel", RogueSkin.box(1, "_thin", 6))
	_dex_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dex_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dex_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dex_card.offset_right = -16
	_dex_card.offset_bottom = -150
	_dex_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dex_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dex_card.add_child(row)
	var pic := TextureRect.new()
	pic.texture = it[0]
	pic.custom_minimum_size = Vector2(72, 72)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(RogueSkin.label(str(it[4]) if it.size() > 4 else "新登记！", RogueSkin.SIZE_SMALL, "summary_gold"))
	col.add_child(RogueSkin.label("No.%04d %s" % [int(it[1]), str(it[2])], RogueSkin.SIZE_BODY, "window"))
	var tier := int(it[3])
	if tier >= 0:
		col.add_child(RogueSkin.label(DEX_TIER_TEXT[clampi(tier, 0, 2)], RogueSkin.SIZE_SMALL, DEX_TIER_STYLE[clampi(tier, 0, 2)]))
	_dex_shown_ms = Time.get_ticks_msec()
	_dex_until_ms = _dex_shown_ms + int(DEX_CARD_SECS * 1000.0)
	_dex_card.modulate.a = 1.0
	_play("levelup")


func _dex_card_tick() -> void:
	if _dex_card == null or not _dex_card.visible:
		return
	var left := (_dex_until_ms - Time.get_ticks_msec()) / 1000.0
	if not _dex_queue.is_empty() and Time.get_ticks_msec() - _dex_shown_ms >= int(DEX_CARD_QUEUED_SECS * 1000.0):
		_next_dex_card()   # 有下一张在等：直接顶掉，不淡出
	elif left <= 0.0:
		_next_dex_card()
	else:
		_dex_card.modulate.a = clampf(left / 0.4, 0.0, 1.0)


func _build_debug() -> void:
	_debug_label = town_label("", 12, TOWN_MUTED, false, true)
	# 左上角；底边留给经验条
	_debug_label.position = Vector2(12, 8)
	_debug_label.visible = false   # 调试计数（怪数 / 帧数）默认不显示，按 F3 开关
	_root.add_child(_debug_label)


func _dim_layer(alpha: float) -> Panel:
	# 主项目的结果遮罩是一整块半透明纯色；这里换成同色系的墨色，留一点透明好看见场上
	var dim := Panel.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(TOWN_INK.r, TOWN_INK.g, TOWN_INK.b, alpha)
	dim.add_theme_stylebox_override("panel", sb)
	_root.add_child(dim)
	return dim


func _build_cards() -> void:
	_cards_layer = _dim_layer(0.66)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_layer.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var title := town_label("升级了，选一个", 30, TOWN_GOLD)
	_cards_title = title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var hint := town_label("按 1 / 2 / 3，或用鼠标点", 15, TOWN_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for i in 3:
		row.add_child(_make_card(i))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 12)
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap2)
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(holder)
	_reroll_btn = hanb_button("", 16, Vector2(360, 46))   # 汉 B 按钮（界面迁移包）
	_reroll_btn.pressed.connect(func(): if _rerolls > 0: reroll_pressed.emit())
	holder.add_child(_reroll_btn)
	set_rerolls(0)


func _make_card(i: int) -> Button:
	# 整张卡是一个按钮：平时是普通漆框，鼠标移上去 / 按下换成主项目“选中”的提亮漆框
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_SIZE.x, 372) if CARD_PAPER else CARD_SIZE   # 纸牌是竖版，底下有云纹角花，要高一些
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := town_box(TOWN_PANEL, TOWN_LINE, 1, 4, 12)
	var lit := town_box(TOWN_PANEL_RAISED, TOWN_GOLD, 2, 4, 12)
	if CARD_PAPER and ResourceLoader.exists("res://ui/hanb/card_paper.png"):
		normal = _paper_box(Color.WHITE)
		lit = _paper_box(Color(1.12, 1.08, 0.96))
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", lit)
	card.add_theme_stylebox_override("pressed", lit)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.pressed.connect(_on_card_pressed.bind(i))
	card.mouse_entered.connect(_on_card_hover)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(normal.content_margin_left))
	margin.add_theme_constant_override("margin_right", int(normal.content_margin_right))
	margin.add_theme_constant_override("margin_top", int(normal.content_margin_top))
	margin.add_theme_constant_override("margin_bottom", int(normal.content_margin_bottom))
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	# 按键号：金底墨字的小方块（主项目实心金按钮的配色）
	var key_row := HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.add_theme_constant_override("separation", 14)
	key_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key_row)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(40, 40)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", town_box(TOWN_GOLD, TOWN_GOLD.lightened(0.2), 1, 4, 4, true))
	key_row.add_child(badge)
	var key := town_label(str(i + 1), 22, TOWN_INK)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(key)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 图标（可选）：手绘图，线性采样
	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	key_row.add_child(icon)
	# 外功按品质套一个框（界面迁移包，ui/hanb/frame_*.png）
	var frame := TextureRect.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = -6
	frame.offset_top = -6
	frame.offset_right = 6
	frame.offset_bottom = 6
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	icon.add_child(frame)

	var name_label := town_label("", 26, CARD_INK if CARD_PAPER else TOWN_GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var level_label := town_label("", 17, CARD_JADE if CARD_PAPER else TOWN_JADE)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level_label)

	var line := ColorRect.new()
	line.color = TOWN_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)

	var effect := town_label("", 17, CARD_INK if CARD_PAPER else TOWN_PAPER, true)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect.add_theme_constant_override("line_spacing", 6)
	box.add_child(effect)

	# 类别小标：贴在卡面右上角，不占排版的位置
	var tag := PanelContainer.new()
	tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.offset_right = -int(normal.content_margin_right) + 6
	tag.offset_left = tag.offset_right
	tag.offset_top = int(normal.content_margin_top) - 4
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = false
	card.add_child(tag)
	var tag_text := town_label("", 15, TOWN_MUTED)
	tag_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(tag_text)

	_cards.append(card)
	_card_parts.append({"name": name_label, "level": level_label, "effect": effect, "icon": icon, "tag": tag, "tag_text": tag_text, "frame": frame})
	return card


# 倒下 / 通关共用：漆框面板托底，横幅压在面板上沿，标题写在横幅上
func _build_result(kind: String, title_text: String, title_color: Color, hint_text: String) -> Dictionary:
	# 倒下 / 通关结算：原版窗口皮肤（和商店、详情页同一套），字都在窗口里，行数多了窗口自己撑高，不再有飘在外面的字。
	var layer_panel := _dim_layer(0.72)
	layer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_panel.add_child(center)

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(780, 0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", RogueSkin.box(1, "", 16))
	center.add_child(holder)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(column)

	var title := RogueSkin.label(title_text, RogueSkin.SIZE_TITLE + 16, "summary_gold" if title_color == TOWN_GOLD else "window")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var summary := RogueSkin.label("", RogueSkin.SIZE_BODY, "window", true)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.custom_minimum_size = Vector2(700, 0)
	column.add_child(summary)

	var hint := RogueSkin.label(hint_text, RogueSkin.SIZE_BODY, "summary_gold")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	return {"layer": layer_panel, "summary": summary, "title": title}



static func _mmss(t: float) -> String:
	var secs := int(max(0.0, t))
	@warning_ignore("integer_division")
	return "%02d:%02d" % [secs / 60, secs % 60]


# 屏幕边缘箭头（闪光 / 神兽在屏幕外时指向它们；main 每帧传 [{pos, angle, color}]）。
var _arrow_layer: Control = null


func set_edge_arrows(rows: Array) -> void:
	if _arrow_layer == null:
		_arrow_layer = EdgeArrows.new()
		_arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_arrow_layer)
	_arrow_layer.set("rows", rows)
	_arrow_layer.queue_redraw()


class EdgeArrows extends Control:
	var rows: Array = []

	func _draw() -> void:
		var pulse := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) / 160.0)
		for r in rows:
			var c: Vector2 = r["pos"]
			var a: float = r["angle"]
			var col: Color = r["color"]
			var tip := c + Vector2.from_angle(a) * 18.0
			var l := c + Vector2.from_angle(a + 2.5) * 14.0
			var rr := c + Vector2.from_angle(a - 2.5) * 14.0
			draw_colored_polygon(PackedVector2Array([tip, l, rr]), Color(0.08, 0.06, 0.12, 0.9))
			var s := 0.78
			draw_colored_polygon(PackedVector2Array([c + (tip - c) * s, c + (l - c) * s, c + (rr - c) * s]), Color(col.r, col.g, col.b, pulse))


# 新手提示框（用户 2026-10-24：新存档要有指导）：屏幕上方居中，停留久一点、不被普通横幅顶掉。
var _tip_box: PanelContainer = null
var _tip_label: Label = null
var _tip_until_ms := 0
const TIP_SECS := 10.0


func show_tip(text: String, secs := TIP_SECS) -> void:
	if _tip_box == null:
		_tip_box = PanelContainer.new()
		_tip_box.add_theme_stylebox_override("panel", RogueSkin.box(1, "_thin", 10))
		_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_tip_box.position = Vector2(-330, 150)
		_tip_box.custom_minimum_size = Vector2(660, 0)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_box.add_child(col)
		var title := RogueSkin.label("新手提示", RogueSkin.SIZE_SMALL, "summary_gold")
		col.add_child(title)
		_tip_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "window")
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_label.custom_minimum_size = Vector2(640, 0)
		col.add_child(_tip_label)
		_root.add_child(_tip_box)
	_tip_label.text = text
	_tip_box.visible = true
	_tip_box.modulate.a = 1.0
	_tip_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


func _tip_tick() -> void:
	if _tip_box == null or not _tip_box.visible:
		return
	var left := (_tip_until_ms - Time.get_ticks_msec()) / 1000.0
	if left <= 0.0:
		_tip_box.visible = false
	else:
		_tip_box.modulate.a = clampf(left / 0.8, 0.0, 1.0)


# 血量框上方一行红字：最近 5 秒的持续掉血（中毒 / 灼伤 / 反伤 / 混乱自伤），没有就不显示（用户 2026-10-24）。
var _dot_label: Label = null


func _set_dot_text(text: String) -> void:
	if _dot_label == null:
		if text == "" or _info_box == null:
			return
		_dot_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "window")
		_dot_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_dot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_dot_label.size = Vector2(520, 30)
		_dot_label.position = Vector2(-520, -34)   # 信息框的定位点在右边缘：往左排、右对齐
		_info_box.add_child(_dot_label)
	_dot_label.text = ("持续掉血 " + text) if text != "" else ""
	_dot_label.visible = text != ""


# 血量框上方再往上一行：能力变化（有降低 = 红字，只有提升 = 绿字）。
var _stage_label: Label = null


func _set_stage_text(text: String) -> void:
	if _stage_label == null:
		if text == "" or _info_box == null:
			return
		_stage_label = RogueSkin.label("", RogueSkin.SIZE_SMALL, "window")
		_stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stage_label.size = Vector2(620, 30)
		_stage_label.position = Vector2(-620, -64)
		_info_box.add_child(_stage_label)
	_stage_label.text = ("能力 " + text) if text != "" else ""
	_stage_label.visible = text != ""
	_stage_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if text.contains("-") else Color(0.5, 1.0, 0.55))


# 能力变化的图标版（用户 2026-10-25：“能力 攻击-1（4 秒）”那行字太丑，做成和左上角一样的图标）：
# 血量框上方一排，每项一个原版 X 道具图标（X攻击 / X防御…），右下角 +2 / -1（绿 / 红），右上角剩几秒，悬停看说明。
const STAGE_ICON := {"atk": "x_attack", "def": "x_defense", "spatk": "x_sp_atk", "spdef": "x_sp_def", "spd": "x_speed", "acc": "x_accuracy", "eva": "x_accuracy"}
var _stage_box: HBoxContainer = null
var _stage_key := ""


func _set_stage_icons(rows: Array) -> void:
	if _info_box == null:
		return
	if _stage_box == null:
		if rows.is_empty():
			return
		_stage_box = HBoxContainer.new()
		_stage_box.alignment = BoxContainer.ALIGNMENT_END
		_stage_box.add_theme_constant_override("separation", 8)
		_stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_box.size = Vector2(620, 40)
		_stage_box.position = Vector2(-620, -80)   # 信息框的定位点在右边缘：往左排、右对齐
		_info_box.add_child(_stage_box)
	var key := str(rows)
	if key == _stage_key:
		return
	_stage_key = key
	for c in _stage_box.get_children():
		_stage_box.remove_child(c)
		c.queue_free()
	for r: Dictionary in rows:
		var v := int(r.get("v", 0))
		var secs := int(r.get("secs", -1))
		var ic := RogueSkin.outlined_icon(RogueAtlas.frame("icons/items", str(STAGE_ICON.get(str(r.get("key", "")), "x_attack"))), 38)
		ic.mouse_filter = Control.MOUSE_FILTER_STOP   # 要吃鼠标才有悬停提示
		ic.tooltip_text = "%s %s%d%s" % [str(r.get("name", "")), "+" if v > 0 else "", v, ("（还剩 %d 秒）" % secs) if secs >= 0 else "（一直有效）"]
		var badge := RogueSkin.label("%s%d" % ["+" if v > 0 else "", v], RogueSkin.SIZE_SMALL, "window")
		badge.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55) if v > 0 else Color(1.0, 0.45, 0.4))
		badge.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 1.0))
		badge.add_theme_constant_override("outline_size", 6)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		ic.add_child(badge)
		if secs >= 0:
			var t := RogueSkin.label("%ds" % secs, RogueSkin.SIZE_SMALL, "window")
			t.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
			t.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 1.0))
			t.add_theme_constant_override("outline_size", 6)
			t.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			t.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			t.position.y = -10
			ic.add_child(t)
		_stage_box.add_child(ic)
	_stage_box.visible = not rows.is_empty()

