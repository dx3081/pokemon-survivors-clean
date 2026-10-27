extends Node3D
# PokeRogue front/back atlases: one battle loop, reused for idle and movement.
# Horizontal views are mirrored explicitly; these are not four separate walk cycles.
# Species 10 / 11 / 12 (绿毛虫 / 铁甲蛹 / 巴大蝶) each keep their own atlas and
# frame count, but share the same battle loop, 12 fps cadence and foot anchor.
# Switching species never changes race data, level, HP or the four-direction rules.
#
# 帧身份来自每套原 TexturePacker JSON 的数值文件名，不按打包顺序 / 文件枚举播放；
# 画布取该套 front/back 实际最大 sourceSize，脚底中央锚点；像素比例与 FPS 12 不变。

const FPS := 12.0
const WildSpecies := preload("res://data/pokemon_wild_species.gd")

# species id -> asset folder + transparent canvas + foot anchor (bottom-center).
# 10 keeps the original project values. 11 / 12 canvases only need to fit their
# sourceSize (36x38 / 42x43 and 62x57 / 64x57); pixels stay 1:1 so each species
# keeps its own proportions while the feet land on the node origin.
const SPECIES := {
	10: {"folder": "caterpie", "canvas": Vector2(40, 40), "anchor": Vector2(20, 38)},
	11: {"folder": "metapod", "canvas": Vector2(48, 48), "anchor": Vector2(24, 46)},
	12: {"folder": "butterfree", "canvas": Vector2(72, 64), "anchor": Vector2(36, 62)},
}

# 画布底下留白的物种：原图集是 96×96 的画布，画面内容只占中间一段，底下空着这么多像素。
# 脚底锚点要落在“画面内容的最低一行”上，否则整只怪被抬离地面（用户 2026-10-18：“这个猪一直飘在天空中”）。
# 数值 = 前 / 后两个视角、所有帧里底下留白的最小值（按图集 json 的 sourceSize 与 spriteSourceSize 算出，留白 < 6 像素的不用管）。
# 2026-10-18 夜：原先只列了 5 个，其余 Gen9 物种（906–1024）同样有留白，一并补全（用户：“这个宠物浮空了”）。
# 图集放在 assets/pokemon_shiny/<档位>/<目录>/<front|back>/<键>.png；json 和普通版一样的不重复放，读取时回落到普通版的 json。
# 某一档没有素材（这只宠物没有蓝 / 红闪）就落回上一档，最后落回普通配色。
const ShinyVariants := preload("res://data/pokemon_shiny_variants.gd")
const SHINY_ROOT := "res://assets/pokemon_shiny/"
var wild_shiny_variant := -1   # -1 = 普通配色；0 / 1 / 2 = 闪光档位

const FOOT_GAP := {
	906: 26, 907: 15, 908: 7, 909: 23, 910: 19, 911: 16, 912: 21, 913: 15, 915: 32, 916: 24, 917: 23,
	918: 17, 919: 30, 920: 15, 921: 24, 922: 18, 923: 14, 924: 27, 925: 26, 926: 29, 927: 18, 928: 27,
	929: 18, 930: 12, 932: 28, 933: 23, 934: 13, 935: 20, 936: 8, 937: 6, 938: 30, 939: 22, 940: 28,
	941: 11, 942: 26, 943: 17, 944: 33, 945: 21, 946: 31, 947: 24, 948: 18, 949: 8, 950: 23, 951: 27,
	952: 15, 953: 31, 954: 15, 955: 29, 956: 12, 957: 31, 958: 29, 959: 13, 960: 30, 961: 20, 963: 29,
	965: 27, 966: 20, 967: 14, 968: 24, 969: 26, 970: 15, 971: 18, 972: 13, 973: 11, 974: 27, 975: 15,
	976: 17, 977: 16, 978: 29, 996: 28, 997: 20, 998: 7, 999: 11, 1000: 11, 1001: 9, 1002: 20, 1003: 6,
	1004: 25, 1012: 23, 1013: 17, 1014: 10, 1015: 16, 1019: 6, 1024: 24,
}

var species_id := 10
# 0 = 本作内置三形态；>0 = 平原源物种（wild_active 为 true）。
var wild_species_id := 0
var wild_form_index := 0
var wild_active := false
var sprite: Sprite3D
var player_animation: AnimationPlayer
var view_direction := "south"
static var _shared_views := {}
static var _instances := 0
var _views := {}
# 当前动画库是按哪个视角（front/back）的原帧数建的；切视角必须重建，否则短侧相位会被长侧顶掉。
var _built_view := ""
var _canvas := Vector2(40, 40)
var frame_index := 0:
	set(value):
		frame_index = value
		_refresh_frame()


func _init() -> void:
	_instances += 1
	_views = _view_set(species_id)
	_canvas = SPECIES[species_id]["canvas"]
	sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.pixel_size = 0.045
	_apply_canvas_anchor(_canvas, SPECIES[species_id]["anchor"])
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.1
	add_child(sprite)
	player_animation = AnimationPlayer.new()
	player_animation.name = "AnimationPlayer"
	add_child(player_animation)
	_build_animations()
	_refresh_frame()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_instances -= 1
		if _instances == 0:
			_shared_views.clear()


# --- species switching (display only; no race / level / stat changes) ---

# Change the visible built-in species. 10 / 11 / 12 are supported; idempotent.
# 若当前是平原野生物种，切回内置形态也会正确重建。
func set_species(id: int, shiny_variant := -1) -> void:
	if not wild_active and id == species_id and wild_shiny_variant == shiny_variant:
		return
	assert(SPECIES.has(id), "unsupported species id: %d" % id)
	wild_active = false
	form_sprite_key = ""
	wild_shiny_variant = shiny_variant
	wild_species_id = 0
	wild_form_index = 0
	species_id = id
	_views = _view_set(id, shiny_variant)
	_canvas = SPECIES[id]["canvas"]
	_apply_canvas_anchor(_canvas, SPECIES[id]["anchor"])
	_build_animations()
	frame_index = 0
	_refresh_frame()


# 超级进化 / 超极巨化形态（game/pokemon_special_forms.gd）：图在 assets/pokemon/forms/，闪光只有一档（0）。
const FORMS_ROOT := "res://assets/pokemon/forms/"
var form_sprite_key := ""


func set_form_sprite(id: int, sprite_key: String, shiny_variant := -1) -> void:
	if wild_active and wild_species_id == id and form_sprite_key == sprite_key and wild_shiny_variant == shiny_variant:
		return
	var info := _form_view_set(id, sprite_key, shiny_variant)
	if (info["front"] as Array).is_empty():
		return
	wild_active = true
	wild_shiny_variant = shiny_variant
	wild_species_id = id
	wild_form_index = -1
	form_sprite_key = sprite_key
	species_id = 0
	_views = info
	_canvas = Vector2(float(info["canvas_w"]), float(info["canvas_h"]))
	_apply_canvas_anchor(_canvas, Vector2(_canvas.x * 0.5, _canvas.y))
	_build_animations()
	frame_index = 0
	_refresh_frame()


func portrait_for_form(id: int, sprite_key: String, shiny_variant := -1) -> Texture2D:
	var info := _form_view_set(id, sprite_key, shiny_variant)
	return (info["front"] as Array)[0] if not (info["front"] as Array).is_empty() else null


# 画布 = front / back 所有帧最大的 sourceSize（同平原图集的约定）。
static func _form_canvas(json_path: String) -> Vector2:
	var out := Vector2.ZERO
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return out
	for tex: Dictionary in parsed.get("textures", []):
		for fr: Dictionary in tex.get("frames", []):
			var ss: Dictionary = fr.get("sourceSize", {})
			out = Vector2(maxf(out.x, float(ss.get("w", 0))), maxf(out.y, float(ss.get("h", 0))))
	return out


static func _form_view_set(id: int, sprite_key: String, shiny_variant := -1) -> Dictionary:
	var name := "%d-%s" % [id, sprite_key]
	var key := "f%s" % name if shiny_variant < 0 else "f%s:s" % name
	if not _shared_views.has(key):
		var front := FORMS_ROOT + "front/" + name
		var back := FORMS_ROOT + "back/" + name
		if not FileAccess.file_exists(front + ".json") or not FileAccess.file_exists(back + ".json"):
			return {"front": [], "back": [], "canvas_w": 0, "canvas_h": 0}
		var a := _form_canvas(front + ".json")
		var b := _form_canvas(back + ".json")
		var canvas := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		var anchor := Vector2(canvas.x * 0.5, canvas.y)
		var sf := ""
		var sb := ""
		if shiny_variant >= 0:
			sf = SHINY_ROOT + "0/forms/front/" + name
			sb = SHINY_ROOT + "0/forms/back/" + name
			if not ResourceLoader.exists(sf + ".png"):
				sf = ""
			if not ResourceLoader.exists(sb + ".png"):
				sb = ""
		_shared_views[key] = {
			"front": _load_frames(canvas, anchor, front, sf),
			"back": _load_frames(canvas, anchor, back, sb),
			"canvas_w": canvas.x,
			"canvas_h": canvas.y,
		}
	return _shared_views[key]


# 平原源物种 + 形态：sprite_key 决定原图集文件（id 或 id-spriteKey）。
# 丢图 / 未录入形态直接断言失败，不静默退回绿毛虫画像。
func set_wild_species(id: int, form_index: int, shiny_variant := -1) -> void:
	if wild_active and form_sprite_key == "" and wild_species_id == id and wild_form_index == form_index and wild_shiny_variant == shiny_variant:
		return
	form_sprite_key = ""
	assert(WildSpecies.has_species(id), "unsupported wild species id: %d" % id)
	var form: Dictionary = WildSpecies.form_at(id, form_index)
	var sprite_key := str(form["sprite_key"])
	var info := _wild_view_set(id, sprite_key, shiny_variant)
	assert(not (info["front"] as Array).is_empty(),
		"missing plains atlas for species %d sprite '%s'" % [id, sprite_key])
	wild_active = true
	wild_shiny_variant = shiny_variant
	wild_species_id = id
	wild_form_index = form_index
	species_id = 0
	_views = info
	_canvas = Vector2(float(info["canvas_w"]), float(info["canvas_h"]))
	_apply_canvas_anchor(_canvas, Vector2(_canvas.x * 0.5, _canvas.y - float(FOOT_GAP.get(id, 0))))
	_build_animations()
	frame_index = 0
	_refresh_frame()


# Portrait of another built-in species without changing the current one (used by fx).
func portrait_for_species(id: int) -> Texture2D:
	assert(SPECIES.has(id), "unsupported species id: %d" % id)
	return _view_set(id)["front"][0]


# Portrait of a plains wild species / form (shared atlas cache; no per-call load).
func portrait_for_wild(id: int, form_index: int, shiny_variant := -1) -> Texture2D:
	var form: Dictionary = WildSpecies.form_at(id, form_index)
	var info := _wild_view_set(id, str(form["sprite_key"]), shiny_variant)
	return (info["front"] as Array)[0]


# --- shared frame loading ---

static func _view_set(id: int, shiny_variant := -1) -> Dictionary:
	var vkey: Variant = id if shiny_variant < 0 else "%d:s%d" % [id, shiny_variant]
	if not _shared_views.has(vkey):
		var folder: String = SPECIES[id]["folder"]
		var canvas: Vector2 = SPECIES[id]["canvas"]
		var anchor: Vector2 = SPECIES[id]["anchor"]
		_shared_views[vkey] = {
			"front": _load_frames(canvas, anchor, "res://assets/pokemon/%s/front/%d" % [folder, id], _shiny_builtin_base(shiny_variant, folder, "front", id)),
			"back": _load_frames(canvas, anchor, "res://assets/pokemon/%s/back/%d" % [folder, id], _shiny_builtin_base(shiny_variant, folder, "back", id)),
		}
	return _shared_views[vkey]


# 内置三形态（绿毛虫 / 铁甲蛹 / 巴大蝶）的闪光图集路径，规则同 _shiny_base。
static func _shiny_builtin_base(variant: int, folder: String, view: String, id: int) -> String:
	if variant < 0:
		return ""
	for v in range(variant, -1, -1):
		var p := SHINY_ROOT + str(v) + "/" + folder + "/" + view + "/" + str(id)
		if ResourceLoader.exists(p + ".png"):
			return p
	return ""


# 平原套：同一物种 + sprite_key 的 front/back 共用一份纹理缓存；画布取两视角实际最大 sourceSize，
# 脚底中央锚点，保证 front/back 帧数不同时脚底仍对齐、画布不裁切。
static func _wild_view_set(id: int, sprite_key: String, shiny_variant := -1) -> Dictionary:
	var key := "w%d:%s" % [id, sprite_key] if shiny_variant < 0 else "w%d:%s:s%d" % [id, sprite_key, shiny_variant]
	if not _shared_views.has(key):
		var front_entry := WildSpecies.atlas_entry(id, sprite_key, "front")
		var back_entry := WildSpecies.atlas_entry(id, sprite_key, "back")
		assert(not front_entry.is_empty() and not back_entry.is_empty(),
			"missing plains atlas entry for %d sprite '%s'" % [id, sprite_key])
		var canvas := Vector2(
			maxf(float(front_entry["w"]), float(back_entry["w"])),
			maxf(float(front_entry["h"]), float(back_entry["h"])))
		var anchor := Vector2(canvas.x * 0.5, canvas.y)
		var base := "res://assets/pokemon/" + WildSpecies.atlas_dir(id) + "/%s/" + WildSpecies.file_base(id, sprite_key)
		_shared_views[key] = {
			"front": _load_frames(canvas, anchor, base % "front", _shiny_base(shiny_variant, id, sprite_key, "front")),
			"back": _load_frames(canvas, anchor, base % "back", _shiny_base(shiny_variant, id, sprite_key, "back")),
			"canvas_w": canvas.x,
			"canvas_h": canvas.y,
		}
	return _shared_views[key]


# 帧按原 JSON 的数值文件名排序（打包顺序不是播放顺序），每帧唯一且从 1 连续；
# region / trim 必须在画布内，非 rotated。margin 把裁剪帧还原到画布上的脚底中央锚点。
# 闪光档位的图集路径（不带扩展名）：这一档有素材用这一档，没有就往下一档（2 → 1 → 0），都没有返回 ""（用普通配色）。
static func _shiny_base(variant: int, id: int, sprite_key: String, view: String) -> String:
	if variant < 0:
		return ""
	var tail := "/" + WildSpecies.atlas_dir(id) + "/" + view + "/" + WildSpecies.file_base(id, sprite_key)
	for v in range(variant, -1, -1):
		var p := SHINY_ROOT + str(v) + tail
		if ResourceLoader.exists(p + ".png"):
			return p
	return ""


# png_base = 闪光图集（不带扩展名，"" = 用普通图集）；json 优先读它自己的，没有就读普通版的（布局一样的不重复放）。
static func _load_frames(canvas: Vector2, anchor: Vector2, base: String, png_base := "") -> Array[AtlasTexture]:
	var path := base + ".json"
	if png_base != "" and FileAccess.file_exists(png_base + ".json"):
		path = png_base + ".json"
	assert(FileAccess.file_exists(path), "atlas json missing: " + path)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null and data.has("textures"), "atlas json invalid: " + path)
	var frames: Array = data["textures"][0]["frames"]
	frames.sort_custom(func(a, b): return int(a["filename"].get_basename()) < int(b["filename"].get_basename()))
	var atlas: Texture2D = load((png_base if png_base != "" else base) + ".png")
	assert(atlas != null, "atlas png missing: " + path)
	var out: Array[AtlasTexture] = []
	for i in frames.size():
		var f: Dictionary = frames[i]
		assert(int(f["filename"].get_basename()) == i + 1 and not f["rotated"],
			"atlas frame identity broken: %s #%d" % [path, i + 1])
		var region: Dictionary = f["frame"]
		var source: Dictionary = f["sourceSize"]
		var trim: Dictionary = f["spriteSourceSize"]
		assert(float(source["w"]) <= canvas.x and float(source["h"]) <= canvas.y, "sourceSize exceeds canvas: " + path)
		assert(float(region["x"]) >= 0.0 and float(region["y"]) >= 0.0
			and float(region["x"]) + float(region["w"]) <= float(data["textures"][0]["size"]["w"])
			and float(region["y"]) + float(region["h"]) <= float(data["textures"][0]["size"]["h"]),
			"frame region outside atlas: " + path)
		var tex := AtlasTexture.new()
		tex.atlas = atlas
		tex.region = Rect2(region["x"], region["y"], region["w"], region["h"])
		# margin.position offsets the drawn region, margin.size pads it back to
		# the transparent canvas so the frame's bottom-center lands on the foot anchor.
		tex.margin = Rect2(anchor.x - float(source["w"]) * 0.5 + float(trim["x"]),
			anchor.y - float(source["h"]) + float(trim["y"]),
			canvas.x - float(region["w"]), canvas.y - float(region["h"]))
		out.append(tex)
	assert(out.size() > 0, "no frames loaded: " + path)
	return out


func _apply_canvas_anchor(canvas: Vector2, anchor: Vector2) -> void:
	sprite.offset = Vector2(canvas.x * 0.5 - anchor.x, anchor.y - canvas.y * 0.5)


func _build_animations() -> void:
	# 每个 action 的长度 = **当前显示视角自己的原帧数 / 12fps**。这样 AnimationPlayer 每个循环的
	# 位置就恰好是该视角原 12fps 序列的相位：front / back 帧数不同（如 262 front96/back120）
	# 时各自按自己的原序列连续循环，不截断较长侧、也不在短侧周期末乱跳。
	# 不用 LCM 把轨道膨胀成共同周期（83 套 / 同屏 250 实例会炸），改为切视角时按新视角重建。
	# 重建前记下正在播的 action / 速度 / 位置，重建后原样续播，敌人不会被冻住。
	var prev_action := player_animation.current_animation
	var was_playing := prev_action != "" and player_animation.is_playing()
	var prev_speed := 1.0
	var prev_pos := 0.0
	if was_playing:
		# 只在真的有当前动画时读 position / speed，否则引擎会报 "no current animation"。
		prev_speed = player_animation.get_playing_speed()
		prev_pos = player_animation.current_animation_position
	_built_view = "back" if view_direction == "north" else "front"
	var count: int = (_views[_built_view] as Array).size()
	if player_animation.has_animation_library(""):
		player_animation.remove_animation_library("")
	var library := AnimationLibrary.new()
	for action in ["idle", "move", "attack", "death"]:
		var anim := Animation.new()
		anim.length = 0.4 if action == "death" else (0.45 if action == "attack" else count / FPS)
		anim.loop_mode = Animation.LOOP_LINEAR if action in ["idle", "move"] else Animation.LOOP_NONE
		var track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, NodePath(".:frame_index"))
		anim.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		if action == "death":
			anim.track_insert_key(track, 0.0, 0)
		else:
			for i in count:
				anim.track_insert_key(track, i * anim.length / count, i)
		library.add_animation(action, anim)
	player_animation.add_animation_library("", library)
	if prev_action != "" and was_playing and player_animation.has_animation(prev_action):
		var new_len: float = player_animation.get_animation(prev_action).length
		player_animation.play(prev_action, 0.0, prev_speed)
		if new_len > 0.0:
			player_animation.seek(fmod(prev_pos, new_len), true)


func portrait_texture() -> Texture2D:
	return (_views["front"] as Array)[0]


static func direction_for(world_facing: Vector3, camera_basis: Basis) -> String:
	var right := Vector3(camera_basis.x.x, 0, camera_basis.x.z).normalized()
	var toward := Vector3(camera_basis.z.x, 0, camera_basis.z.z).normalized()
	var x := world_facing.dot(right)
	var y := world_facing.dot(toward)
	if absf(x) > absf(y):
		return "east" if x > 0.0 else "west"
	return "south" if y >= 0.0 else "north"


func set_world_facing(world_facing: Vector3, camera: Camera3D) -> void:
	if world_facing.length_squared() < 0.0001:
		return
	view_direction = direction_for(world_facing, camera.global_basis)
	# Front faces screen-left; back faces screen-right in the source art.
	sprite.flip_h = view_direction == "east"
	_refresh_frame()


func _refresh_frame() -> void:
	if sprite == null:
		return
	var view := "back" if view_direction == "north" else "front"
	if view != _built_view:
		# 视角切换：动画库必须按新视角自己的原帧数重建（phase 不会被另一种帧数顶掉）。
		_build_animations()
	var frames: Array = _views[view]
	sprite.texture = frames[frame_index % frames.size()]
	if not _outline_copies.is_empty():
		_sync_outline()
	if _flash_node != null and _flash_node.visible:
		_sync_flash()


const FLASH_SHADER := preload("res://fx/sprite_flash.gdshader")
const FLASH_SECS := 0.12
var _flash_node: Sprite3D
var _flash_tween: Tween


func flash_white(secs := FLASH_SECS) -> void:
	if sprite == null or not is_inside_tree():
		return
	if _flash_node == null:
		_flash_node = Sprite3D.new()
		_flash_node.name = "HitFlash"
		_flash_node.pixel_size = sprite.pixel_size
		_flash_node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_flash_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = FLASH_SHADER
		_flash_node.material_override = mat
		add_child(_flash_node)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_sync_flash()
	var smat := _flash_node.material_override as ShaderMaterial
	smat.set_shader_parameter("amount", 1.0)
	_flash_node.visible = true
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float): smat.set_shader_parameter("amount", v), 1.0, 0.0, secs)
	_flash_tween.tween_callback(func(): _flash_node.visible = false)


func _sync_flash() -> void:
	_flash_node.offset = sprite.offset
	_flash_node.flip_h = sprite.flip_h
	_flash_node.texture = sprite.texture
	(_flash_node.material_override as ShaderMaterial).set_shader_parameter("tex", sprite.texture)


# 金色描边（闪光 / 神兽宠物，用户 2026-10-17）：8 份纯色剪影朝 8 个方向错开 OUTLINE_PIXELS 个原像素，
const OUTLINE_SHADER := preload("res://fx/sprite_outline.gdshader")
const OUTLINE_PIXELS := 1.5
var _outline_copies: Array = []


func set_outline(color: Color = Color(1.0, 0.82, 0.2)) -> void:
	if _outline_copies.is_empty():
		for i in 8:
			var ang := float(i) * TAU / 8.0
			var copy := Sprite3D.new()
			copy.name = "Outline%d" % i
			copy.pixel_size = sprite.pixel_size
			copy.offset = sprite.offset
			copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := ShaderMaterial.new()
			mat.shader = OUTLINE_SHADER
			mat.set_shader_parameter("shift", Vector2(cos(ang), sin(ang)) * OUTLINE_PIXELS * sprite.pixel_size)
			copy.material_override = mat
			add_child(copy)
			_outline_copies.append(copy)
	for copy: Sprite3D in _outline_copies:
		(copy.material_override as ShaderMaterial).set_shader_parameter("color", color)
	_sync_outline()


func clear_outline() -> void:
	for copy in _outline_copies:
		if is_instance_valid(copy):
			copy.queue_free()
	_outline_copies.clear()


func has_outline() -> bool:
	return not _outline_copies.is_empty()


func _sync_outline() -> void:
	for copy: Sprite3D in _outline_copies:
		copy.offset = sprite.offset
		copy.flip_h = sprite.flip_h
		copy.texture = sprite.texture
		(copy.material_override as ShaderMaterial).set_shader_parameter("tex", sprite.texture)


# 异常状态头顶标识（异常战斗轮的轻量反馈）：只加一行短字，不重排角色、不碰朝向 / 动画。
# text 空 = 没有异常状态，整行隐藏。
# 稀有宠物头顶标记（用户 2026-10-17：遇到珍惜宠物方便我们抓）：金色一行字，比异常状态字略大、放在它上面。
const MARKER_PIXEL_SIZE := 0.0006
var _marker_label: Label3D        # 第一条标记（兼容旧检查）
var _marker_labels: Array[Label3D] = []   # 每条标记一个 Label3D，各自一个颜色，往上叠
const MARKER_ROW_PIXELS := 58.0           # 两条标记之间的像素间隔（Label3D.offset 是像素）


# 一条标记：文字 + 颜色（旧入口，保留）。
func set_marker_text(text: String, color := Color(1.0, 0.85, 0.25)) -> void:
	set_marker_tags([] if text == "" else [[text, color]])


# 多条标记各自上色（稀有绿 / 神兽红 / 闪光黄），从下往上叠；tags = [[文字, 颜色], …]。
func set_marker_tags(tags: Array) -> void:
	while _marker_labels.size() < tags.size():
		var lab := Label3D.new()
		lab.name = "RareMarker" if _marker_labels.is_empty() else "RareMarker%d" % _marker_labels.size()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.fixed_size = true
		lab.pixel_size = MARKER_PIXEL_SIZE
		lab.font_size = 48
		lab.outline_size = 12
		lab.outline_modulate = Color(0.1, 0.07, 0.0, 0.95)
		lab.position = Vector3(0, _canvas.y * 0.045 + 0.42, 0)
		lab.offset = Vector2(0, _marker_labels.size() * MARKER_ROW_PIXELS)
		add_child(lab)
		_marker_labels.append(lab)
	for i in _marker_labels.size():
		var on := i < tags.size()
		_marker_labels[i].visible = on
		if on:
			_marker_labels[i].text = str(tags[i][0])
			_marker_labels[i].modulate = tags[i][1]
	_marker_label = _marker_labels[0] if not _marker_labels.is_empty() else null


func marker_text() -> String:
	var parts: Array = []
	for lab in _marker_labels:
		if lab.visible:
			parts.append(lab.text)
	return "  ".join(parts)


const STATUS_LABEL_FONT_SIZE := 48
const STATUS_LABEL_PIXEL_SIZE := 0.00044
var _status_label: Label3D

func set_status_text(text: String) -> void:
	if _status_label == null:
		_status_label = Label3D.new()
		_status_label.name = "StatusLabel"
		_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_status_label.no_depth_test = true
		_status_label.fixed_size = true
		# 头顶状态字的屏幕大小 ≈ font_size × pixel_size（fixed_size 下按屏幕比例，约占屏高 5%）。
		# 2026-10-16 试玩反馈“太大了”：原 96 × 0.0016（≈0.154）在蜂群里满屏叠字，缩到 48 × 0.00044（≈0.021）。
		_status_label.pixel_size = STATUS_LABEL_PIXEL_SIZE
		_status_label.font_size = STATUS_LABEL_FONT_SIZE
		_status_label.outline_size = 10
		_status_label.modulate = Color(0.75, 1.0, 0.8)
		_status_label.outline_modulate = Color(0, 0, 0, 0.9)
		# 放在精灵画布上方一点；敌人被放大 / 缩小时跟着根节点缩放。
		_status_label.position = Vector3(0, _canvas.y * 0.045 + 0.12, 0)
		add_child(_status_label)
	# 主要异常换成原版状态图标（statuses 图集），字只留没有图标的（混乱）；Label3D 仍在，免得老检查找不到。
	var frame_name := ""
	var words: Array = []
	for part in text.split(" "):
		if part == "" or part == "·":
			continue
		var f := str(STATUS_FRAME.get(part, ""))
		if f != "" and frame_name == "":
			frame_name = f
		else:
			words.append(part)
	if _status_icon == null:
		_status_icon = _icon_sprite("StatusIcon", STATUS_ICON_PIXEL_SIZE)
		_status_icon.position = _status_label.position
	_status_icon.visible = frame_name != ""
	if frame_name != "":
		_status_icon.texture = RogueAtlas.frame("statuses", frame_name)
	_status_label.text = " ".join(words)
	_status_label.visible = not words.is_empty()
	# 图标和字都有时并排：图标靠左、字靠右（往上叠会压到稀有 / 神兽标记）
	var both := frame_name != "" and not words.is_empty()
	_status_icon.offset = Vector2(-8, 0) if both else Vector2.ZERO
	_status_label.offset = Vector2(70, 0) if both else Vector2.ZERO


const RogueAtlas := preload("res://ui/rogue_atlas.gd")
const STATUS_FRAME := {"中毒": "poison", "剧毒": "toxic", "麻痹": "paralysis", "睡眠": "sleep", "冰冻": "freeze", "灼伤": "burn"}
const STATUS_ICON_PIXEL_SIZE := 0.004    # 原版图标 20×8；fixed_size 下约占屏高 3%，比状态字略大好认
const OWNED_ICON_PIXEL_SIZE := 0.006  # 原版小精灵球 7×7
var _status_icon: Sprite3D
var _owned_icon: Sprite3D


# 头顶的原版小图标（点阵、永远朝镜头、不被挡、固定屏幕大小）。
func _icon_sprite(node_name: String, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = node_name
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.fixed_size = true
	s.pixel_size = px
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.render_priority = 10
	s.visible = false
	add_child(s)
	return s


# 暂停抓宠时的抓没抓过标记：抓过 = 原版小精灵球（ui/icon_owned，原版就是“抓过”的意思），没抓过 = 同一个球的灰色版。
# 挂在头顶标记那一摞的最上面。
static var _gray_ball: Texture2D = null


static func _gray_ball_texture() -> Texture2D:
	if _gray_ball == null:
		var img: Image = RogueAtlas.texture("ui/icon_owned.png").get_image()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var v := (c.r * 0.3 + c.g * 0.59 + c.b * 0.11) * 0.8   # 去色再压暗一点，和彩色球一眼分得开
				img.set_pixel(x, y, Color(v, v, v, c.a))
		_gray_ball = ImageTexture.create_from_image(img)
	return _gray_ball


func set_owned_icon(on: bool, caught := true) -> void:
	if _owned_icon == null:
		if not on:
			return
		_owned_icon = _icon_sprite("OwnedIcon", OWNED_ICON_PIXEL_SIZE)
	_owned_icon.texture = RogueAtlas.texture("ui/icon_owned.png") if caught else _gray_ball_texture()
	_owned_icon.position = Vector3(0, _canvas.y * 0.045 + 0.42, 0)
	var rows := 0
	for lab in _marker_labels:
		if lab.visible:
			rows += 1
	# Sprite3D 的 offset 按贴图像素算，换算成和标记字一样的屏幕距离
	_owned_icon.offset = Vector2(0, (rows * MARKER_ROW_PIXELS + 10.0) * MARKER_PIXEL_SIZE / OWNED_ICON_PIXEL_SIZE)
	_owned_icon.visible = on


func owned_icon_visible() -> bool:
	return _owned_icon != null and _owned_icon.visible


# 测试用：现在显示的是不是灰色（没抓过）那个球。
func owned_icon_is_gray() -> bool:
	return owned_icon_visible() and _owned_icon.texture == _gray_ball
