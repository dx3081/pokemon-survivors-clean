extends Node3D
# 顶替一部分招式的“特效图层”。不碰伤害 / 冷却 / 命中；原版播放器 rogue_moves.gd 仍负责声音和出招 / 受击方的身体动作
# （冲撞、抖动），只是对这里接管的招式不再画自己的特效图层（play(..., effects=false)）。
#
# 用户 2026-10-19 的方向：
#   - 所有“指向性”的招式都要从主角射向敌人（原版是左下打右上，只有一个方向），这里按真实的 主角 → 敌人 连线转；
#   - 飞射类（啄 / 空气之刃 / 毒针 / 魔法叶）：弹体从主角飞到敌人，到了再放命中；
#   - 光柱类（电击 / 电光）：从主角拉到敌人的一道光，招式威力越大光柱越粗；
#   - 从上往下砸（十万伏特）：落点上方砸下，带一点延迟（敌人用这招时落点要先画红圈，敌方还没接，见 CURRENT.md）；
#   - 范围招（地震 / 放电）：围着主角一圈，一部分从上往下砸；
#   - 藤鞭：4～5 道藤蔓沿连线一路推过去。
#
# 对外：setup(rogue_fx) / play(move_id, user, target, power) -> bool（true = 本招由这里接管）/ clear() / step(delta)（测试用）。

const DIR := "res://assets/fx_pack/"
const WORLD_192 := 2.112          # 192 像素一格对应的世界尺寸（米）：原版 96 像素 × 0.022 米 × 1，对齐原版特效大小
const MAX_ACTIVE := 96
const RING_DEDUP_MS := 250

# kind：burst 在敌人身上 / self 在自己身上 / slash 斩击（沿连线转）/ bolt 飞射 / beam 光柱 / strike 砸下 / ring 一圈 / seq 沿连线推进
# 每个招式：{"kind": ..., "layers": [{"fx": 图集 id, "size": 像素(192 = 原版大小), "t0": 延迟秒}], 其余看各 kind}
const RECIPES := {
	# —— 用户已批的 —— tackle 选 normal_c；power_gem 选 rock_c；head_smash 选 rock_a；night_shade / psychic 选 psychic_c；
	#                    agility 选 self_c；hypnosis 选 status_a；steel_wing 选 steel_a
	"tackle": {"kind": "burst", "layers": [{"fx": "p3_e2", "size": 192}, {"fx": "p2_e3", "size": 192, "t0": 0.03}]},
	"power_gem": {"kind": "burst", "layers": [{"fx": "p8_e18", "size": 224}, {"fx": "p1_e7", "size": 160, "t0": 0.05}]},
	"head_smash": {"kind": "burst", "layers": [{"fx": "p9_e9", "size": 224}]},
	"night_shade": {"kind": "burst", "layers": [{"fx": "p4_e21", "size": 208}]},
	"psychic": {"kind": "burst", "layers": [{"fx": "p4_e21", "size": 208}]},
	"hypnosis": {"kind": "burst", "layers": [{"fx": "p6_e4", "size": 224}]},
	"agility": {"kind": "self", "layers": [{"fx": "p3_e12", "size": 224}]},
	"steel_wing": {"kind": "slash", "fx": "p3_e9", "size": 288, "rot": 0.0},
	# —— 指向性：主角 → 敌人 ——
	"peck": {"kind": "bolt", "fx": "p4_e1", "size": 176, "speed": 22.0, "rot": 0.0, "impact": [{"fx": "p3_e15", "size": 128}]},
	"air_slash": {"kind": "bolt", "fx": "p5_e20", "size": 240, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p3_e5", "size": 192}]},
	"poison_sting": {"kind": "bolt", "fx": "p4_e10", "size": 176, "speed": 22.0, "rot": 0.0, "impact": [{"fx": "p10_e29", "size": 160}]},
	"magical_leaf": {"kind": "bolt", "fx": "p5_e23", "size": 224, "speed": 16.0, "rot": 0.0, "impact": [{"fx": "p10_e29", "size": 160}]},
	"vine_whip": {"kind": "seq", "fx": "p4_e14", "size": 256, "count": 5, "gap": 0.07},
	"bone_club": {"kind": "slash", "fx": "p1_e13", "size": 288, "rot": 0.0},
	"night_slash": {"kind": "slash", "fx": "p3_e9", "size": 288, "rot": 0.0, "tint": Color(0.62, 0.45, 0.95)},
	# 光柱：威力越大越粗（电击 40、电光 65）
	"thunder_shock": {"kind": "beam", "fx": "p7_e30", "size": 192},
	"spark": {"kind": "beam", "fx": "p7_e30", "size": 192},
	# 从上往下砸：延迟低一点（敌人也会用这招，主角好躲）
	"thunderbolt": {"kind": "strike", "layers": [{"fx": "p8_e2", "size": 288}], "delay": 0.20},
	# 范围：围着主角一圈
	"earthquake": {"kind": "ring", "fx": "p8_e18", "size": 208, "count": 10, "radius": 3.0, "slam": true, "outward": false},
	"discharge": {"kind": "ring", "fx": "p6_e16", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true, "extra": "p3_e34"},
}


# ---------------- 按“属性 × 招式类型”的默认配方（用户批了再打开：use_defaults = true） ----------------
# 招式类型：S 单体物理（贴身）/ R 单体特殊（远程）/ A 范围（目标 = 周围一圈）/ U 自己（目标 = 自己）/ D 单体变化（状态 / 削弱）
# RECIPES 里单独列的招式永远优先；没单独列的，use_defaults 打开后按这张表走。
static var use_defaults := false
const MOVES := preload("res://data/pokemon_moves.gd")
const DEFAULTS := {
	"一般": {
		"S": {"kind": "burst", "layers": [{"fx": "p3_e2", "size": 192}, {"fx": "p2_e3", "size": 192, "t0": 0.03}]},
		"R": {"kind": "bolt", "fx": "p3_e15", "size": 176, "speed": 20.0, "rot": 0.0, "impact": [{"fx": "p5_e16", "size": 160}]},
		"A": {"kind": "ring", "fx": "p1_e14", "size": 208, "count": 8, "radius": 2.6, "slam": false, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p4_e31", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p6_e4", "size": 208}]}},
	"虫": {
		"S": {"kind": "slash", "fx": "p5_e23", "size": 256, "rot": 0.0},
		"R": {"kind": "bolt", "fx": "p4_e10", "size": 240, "speed": 22.0, "rot": 0.0, "impact": [{"fx": "p10_e29", "size": 160}]},
		"A": {"kind": "ring", "fx": "p4_e14", "size": 208, "count": 8, "radius": 2.8, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p1_e15", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p4_e11", "size": 192}]}},
	"飞行": {
		"S": {"kind": "slash", "fx": "p3_e5", "size": 288, "rot": 0.0},
		"R": {"kind": "bolt", "fx": "p5_e20", "size": 240, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p3_e5", "size": 192}]},
		"A": {"kind": "ring", "fx": "p5_e22", "size": 224, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p5_e21", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p10_e12", "size": 224}]}},
	"毒": {
		"S": {"kind": "burst", "layers": [{"fx": "p7_e31", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p4_e10", "size": 240, "speed": 20.0, "rot": 0.0, "impact": [{"fx": "p7_e31", "size": 192}]},
		"A": {"kind": "ring", "fx": "p7_e31", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p4_e21", "size": 208}]},
		"D": {"kind": "burst", "layers": [{"fx": "p7_e8", "size": 208}]}},
	"草": {
		"S": {"kind": "burst", "layers": [{"fx": "p4_e14", "size": 224}]},
		"R": {"kind": "bolt", "fx": "p5_e23", "size": 224, "speed": 16.0, "rot": 0.0, "impact": [{"fx": "p10_e29", "size": 160}]},
		"A": {"kind": "ring", "fx": "p4_e14", "size": 208, "count": 10, "radius": 3.0, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p5_e4", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p4_e11", "size": 192}]}},
	"地面": {
		"S": {"kind": "burst", "layers": [{"fx": "p8_e18", "size": 224}]},
		"R": {"kind": "bolt", "fx": "p9_e6", "size": 192, "speed": 16.0, "rot": 0.0, "impact": [{"fx": "p8_e18", "size": 224}]},
		"A": {"kind": "ring", "fx": "p8_e18", "size": 208, "count": 10, "radius": 3.0, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p1_e7", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p1_e12", "size": 208}]}},
	"电": {
		"S": {"kind": "burst", "layers": [{"fx": "p3_e13", "size": 224}]},
		"R": {"kind": "beam", "fx": "p7_e30", "size": 192},
		"A": {"kind": "ring", "fx": "p6_e16", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true, "extra": "p3_e34"},
		"U": {"kind": "self", "layers": [{"fx": "p6_e24", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p6_e16", "size": 208}]}},
	"岩石": {
		"S": {"kind": "burst", "layers": [{"fx": "p9_e9", "size": 224}]},
		"R": {"kind": "bolt", "fx": "p9_e6", "size": 192, "speed": 16.0, "rot": 0.0, "impact": [{"fx": "p9_e9", "size": 224}]},
		"A": {"kind": "ring", "fx": "p8_e18", "size": 208, "count": 10, "radius": 3.0, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p5_e24", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p1_e7", "size": 192}]}},
	"水": {
		"S": {"kind": "burst", "layers": [{"fx": "p10_e5", "size": 224}]},
		"R": {"kind": "bolt", "fx": "p4_e12", "size": 192, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p9_e18", "size": 192}]},
		"A": {"kind": "ring", "fx": "p10_e5", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p3_e12", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p10_e18", "size": 224}]}},
	"幽灵": {
		"S": {"kind": "burst", "layers": [{"fx": "p7_e8", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p7_e8", "size": 208, "speed": 16.0, "rot": 0.0, "impact": [{"fx": "p11_e14", "size": 208}]},
		"A": {"kind": "ring", "fx": "p11_e14", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p7_e15", "size": 208}]},
		"D": {"kind": "burst", "layers": [{"fx": "p11_e14", "size": 208}]}},
	"火": {
		"S": {"kind": "burst", "layers": [{"fx": "p4_e2", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p4_e6", "size": 176, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p1_e27", "size": 192}]},
		"A": {"kind": "ring", "fx": "p8_e20", "size": 208, "count": 8, "radius": 2.8, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p4_e7", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p9_e14", "size": 192}]}},
	"超能力": {
		"S": {"kind": "burst", "layers": [{"fx": "p4_e21", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p7_e12", "size": 192, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p8_e26", "size": 224}]},
		"A": {"kind": "ring", "fx": "p7_e31", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p3_e12", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p6_e4", "size": 224}]}},
	"钢": {
		"S": {"kind": "slash", "fx": "p3_e9", "size": 288, "rot": 0.0},
		"R": {"kind": "bolt", "fx": "p4_e9", "size": 176, "speed": 20.0, "rot": 0.0, "impact": [{"fx": "p3_e9", "size": 224}]},
		"A": {"kind": "ring", "fx": "p5_e24", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p5_e24", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p5_e2", "size": 208}]}},
	"恶": {
		"S": {"kind": "slash", "fx": "p3_e9", "size": 288, "rot": 0.0, "tint": Color(0.62, 0.45, 0.95)},
		"R": {"kind": "bolt", "fx": "p4_e9", "size": 176, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p4_e3", "size": 208}]},
		"A": {"kind": "ring", "fx": "p4_e3", "size": 208, "count": 8, "radius": 2.8, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p4_e9", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p4_e3", "size": 192}]}},
	"妖精": {
		"S": {"kind": "burst", "layers": [{"fx": "p1_e15", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p4_e30", "size": 176, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p1_e15", "size": 192}]},
		"A": {"kind": "ring", "fx": "p1_e15", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p1_e15", "size": 192}]},
		"D": {"kind": "burst", "layers": [{"fx": "p10_e18", "size": 208}]}},
	"格斗": {
		"S": {"kind": "burst", "layers": [{"fx": "p5_e28", "size": 208}, {"fx": "p5_e16", "size": 176, "t0": 0.04}]},
		"R": {"kind": "bolt", "fx": "p4_e1", "size": 240, "speed": 22.0, "rot": 0.0, "impact": [{"fx": "p5_e28", "size": 192}]},
		"A": {"kind": "ring", "fx": "p5_e28", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p5_e17", "size": 224}]},
		"D": {"kind": "burst", "layers": [{"fx": "p3_e2", "size": 208}]}},
	"冰": {
		"S": {"kind": "burst", "layers": [{"fx": "p7_e9", "size": 208}]},
		"R": {"kind": "bolt", "fx": "p4_e22", "size": 176, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p7_e5", "size": 224}]},
		"A": {"kind": "ring", "fx": "p4_e22", "size": 208, "count": 8, "radius": 2.8, "slam": true, "outward": false},
		"U": {"kind": "self", "layers": [{"fx": "p4_e23", "size": 208}]},
		"D": {"kind": "burst", "layers": [{"fx": "p7_e5", "size": 224}]}},
	"龙": {
		"S": {"kind": "burst", "layers": [{"fx": "p9_e1", "size": 224}]},
		"R": {"kind": "bolt", "fx": "p7_e15", "size": 224, "speed": 18.0, "rot": 0.0, "impact": [{"fx": "p9_e1", "size": 224}]},
		"A": {"kind": "ring", "fx": "p9_e1", "size": 208, "count": 8, "radius": 2.8, "slam": false, "outward": true},
		"U": {"kind": "self", "layers": [{"fx": "p4_e27", "size": 208}]},
		"D": {"kind": "burst", "layers": [{"fx": "p7_e15", "size": 208}]}},
}


# 这个招式属于哪一类（S / R / A / U / D）
static func archetype(move_id: String) -> String:
	if not MOVES.MOVES.has(move_id):
		return ""
	var m: Dictionary = MOVES.MOVES[move_id]
	var tgt := int(m.get("target", 3))
	if tgt == 6:
		return "A"
	if tgt == 0:
		return "U"
	var cat := str(m.get("category", ""))
	if cat == "变化":
		return "D"
	return "R" if cat == "特殊" else "S"


# 单独配方优先；没有就按默认表（use_defaults 打开时）。找不到返回空字典。
static func recipe_for(move_id: String) -> Dictionary:
	if RECIPES.has(move_id):
		return RECIPES[move_id]
	if use_defaults and MOVES.MOVES.has(move_id):
		return (DEFAULTS.get(str(MOVES.MOVES[move_id].get("type", "")), {}) as Dictionary).get(archetype(move_id), {})
	return {}

var rogue = null                  # RogueFX：借它的相机朝向 / 中心点
var _manifest: Dictionary = {}
var _tex: Dictionary = {}
var _active: Array = []
var _last_ms: Dictionary = {}
var _quad: QuadMesh = null


func setup(rogue_fx) -> void:
	rogue = rogue_fx
	_load_manifest()


func _ready() -> void:
	if _manifest.is_empty():
		_load_manifest()


func _load_manifest() -> void:
	var f := FileAccess.open(DIR + "manifest.json", FileAccess.READ)
	if f == null:
		push_warning("pack_fx: manifest missing")
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_manifest = d


func has_recipe(id: String) -> bool:
	return not recipe_for(id).is_empty()


func clear() -> void:
	for it in _active:
		var mi = it["mi"]
		if is_instance_valid(mi):
			mi.queue_free()
	_active.clear()


func _exit_tree() -> void:
	clear()


func _process(delta: float) -> void:
	step(delta)


# ---------------- 对外：播放 ----------------

func play(id: String, user: Node3D, target: Node3D, power := 40.0) -> bool:
	var r: Dictionary = recipe_for(id)
	if r.is_empty() or _manifest.is_empty():
		return false
	if user == null or target == null or not is_instance_valid(user) or not is_instance_valid(target):
		return false
	if not _textures_ready(id, r):
		return false         # 图集没导入 / 缺失：交还给原版特效，别让招式一点特效都没有
	var kind := str(r["kind"])
	if kind == "ring":
		var now := Time.get_ticks_msec()
		if now - int(_last_ms.get(id, -100000)) < RING_DEDUP_MS:
			return true          # 同一次群体释放里的后续目标：圈只画一次
		_last_ms[id] = now
	var up := _pos(user)
	var tp := _pos(target)
	match kind:
		"burst":
			for L in r["layers"]:
				_spawn(str(L["fx"]), tp, float(L["size"]), 0.0, 1.0, 1.0, float(L.get("t0", 0.0)))
		"self":
			for L in r["layers"]:
				_spawn(str(L["fx"]), up, float(L["size"]), 0.0, 1.0, 1.0, float(L.get("t0", 0.0)))
		"slash":
			# 斩击的长轴躺在 主角 → 敌人 的连线上（用户 2026-10-19：“有些 \ 要是 /，方向是 mc → 敌人”）。
			# 图自己的长轴角在 manifest 的 axis（弧度，y 向上），转到连线角上；rot 是额外微调（默认 0）。
			var ax := float(_manifest[str(r["fx"])].get("axis", 0.0))
			_spawn(str(r["fx"]), tp, float(r["size"]), _roll(up, tp) - ax + float(r.get("rot", 0.0)), 1.0, 1.0, 0.0,
				{"tint": r.get("tint", Color.WHITE)})
		"bolt":
			_bolt(r, up, tp)
		"beam":
			_beam(r, up, tp, power)
		"strike":
			var delay := float(r.get("delay", 0.2))
			for L in r["layers"]:
				_spawn(str(L["fx"]), tp, float(L["size"]), 0.0, 1.0, 1.0, delay + float(L.get("t0", 0.0)))
		"ring":
			_ring(r, up)
		"seq":
			var n := int(r["count"])
			for i in n:
				var a := float(i + 1) / float(n)
				_spawn(str(r["fx"]), up.lerp(tp, a), float(r["size"]), 0.0, 1.0, 1.0, float(i) * float(r["gap"]))
	return true


var _ready_cache: Dictionary = {}


func _recipe_fx(r: Dictionary) -> Array:
	var out: Array = []
	for L in r.get("layers", []):
		out.append(str(L["fx"]))
	if r.has("fx"):
		out.append(str(r["fx"]))
	if r.has("extra"):
		out.append(str(r["extra"]))
	for L in r.get("impact", []):
		out.append(str(L["fx"]))
	return out


func _textures_ready(id: String, r: Dictionary) -> bool:
	if not _ready_cache.has(id):
		var ok := true
		for fx in _recipe_fx(r):
			if not _manifest.has(fx) or _texture(fx) == null:
				ok = false
		_ready_cache[id] = ok
	return bool(_ready_cache[id])


# ---------------- 各类型 ----------------

func _bolt(r: Dictionary, from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	var dur := clampf(dist / float(r["speed"]), 0.12, 0.5)
	var roll := _roll(from, to) + float(r.get("rot", 0.0))
	var it := _spawn(str(r["fx"]), from, float(r["size"]), roll, 1.0, 1.0, 0.0,
		{"move_to": to, "move_from": from, "move_dur": dur, "loop": true, "life": dur})
	if it.is_empty():
		return
	for L in r.get("impact", []):
		_spawn(str(L["fx"]), to, float(L["size"]), 0.0, 1.0, 1.0, dur)


func _beam(r: Dictionary, from: Vector3, to: Vector3, power: float) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.01:
		return
	var start := from + d / dist * 0.6          # 从主角身前一点拉出
	var length := maxf(0.5, start.distance_to(to))
	var width := WORLD_192 * 1.6 * clampf(0.45 + power / 90.0, 0.7, 1.8)
	var mid := (start + to) * 0.5
	# 光柱原图是竖直的：转 -90°，让它的长轴躺到 主角 → 敌人 的连线上；zx = 宽（米）、zy = 长（米）
	_spawn(str(r["fx"]), mid, float(r["size"]), _roll(from, to) - PI * 0.5, width / WORLD_192, length / WORLD_192, 0.0,
		{"beam": true})


func _ring(r: Dictionary, center: Vector3) -> void:
	var n := int(r["count"])
	var radius := float(r["radius"])
	var slam := bool(r.get("slam", false))
	var basis_y: Vector3 = rogue._view_basis().y if rogue != null else Vector3.UP
	for i in n:
		var a := TAU * float(i) / float(n) + 0.3
		var dir := Vector3(cos(a), 0.0, sin(a))
		var p := Vector3(center.x, center.y - 0.5, center.z) + dir * radius      # 落在地面一圈（center 带 0.9 的身高，往下收回地面附近）
		var roll := 0.0
		if bool(r.get("outward", false)):
			roll = _roll(center, p)
		var extra := {}
		var delay := 0.0
		if slam:
			delay = float(i % 5) * 0.045            # 错开落下，一部分先砸、一部分后砸
			extra = {"drop": 1.6, "drop_dur": 0.12}
		_spawn(str(r["fx"]), p, float(r["size"]), roll, 1.0, 1.0, delay, extra)
		if r.has("extra") and i % 2 == 0:
			_spawn(str(r["extra"]), p, float(r["size"]) * 0.8, roll, 1.0, 1.0, delay + 0.05, extra)


# ---------------- 底层 ----------------

func _pos(n: Node3D) -> Vector3:
	if rogue != null and is_instance_valid(rogue):
		return rogue._center(n)
	return n.global_position + Vector3.UP * 0.9


func _roll(from: Vector3, to: Vector3) -> float:
	# 世界里 from → to 的方向在屏幕平面上的角度（0 = 朝屏幕右，逆时针为正）
	var b: Basis = rogue._view_basis() if rogue != null else Basis.IDENTITY
	var d := to - from
	return atan2(d.dot(b.y), d.dot(b.x))


func _texture(fx: String) -> Texture2D:
	if not _tex.has(fx):
		var path := DIR + fx + ".png"
		_tex[fx] = load(path) as Texture2D if ResourceLoader.exists(path) else null
		if _tex[fx] == null:
			push_warning("pack_fx: sheet missing " + path)
	return _tex[fx]


func _spawn(fx: String, pos: Vector3, size_px: float, roll: float, zx: float, zy: float, delay: float, extra := {}) -> Dictionary:
	if not _manifest.has(fx) or _active.size() >= MAX_ACTIVE:
		return {}
	var tex := _texture(fx)
	if tex == null:
		return {}
	var m: Dictionary = _manifest[fx]
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.no_depth_test = true
	mat.render_priority = 8
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(1.0 / float(m["cols"]), 1.0 / float(m["rows"]), 1.0)
	var tint = extra.get("tint", Color.WHITE)
	mat.albedo_color = tint
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	var it := {
		"mi": mi, "mat": mat, "fx": fx, "frames": int(m["frames"]), "cols": int(m["cols"]), "rows": int(m["rows"]),
		"fps": float(m["fps"]), "t": -delay, "pos": pos, "roll": roll, "zx": zx, "zy": zy,
		"world": WORLD_192 * size_px / 192.0, "extra": extra, "beam": bool(extra.get("beam", false)),
		"loop": bool(extra.get("loop", false)),
	}
	_active.append(it)
	_place(it)
	return it


func step(delta: float) -> void:
	var i := _active.size() - 1
	while i >= 0:
		var it: Dictionary = _active[i]
		it["t"] = float(it["t"]) + delta
		var life := float(it["frames"]) / float(it["fps"])
		if it["extra"].has("life"):
			life = float(it["extra"]["life"])
		if float(it["t"]) >= life:
			var mi = it["mi"]
			if is_instance_valid(mi):
				mi.queue_free()
			_active.remove_at(i)
		else:
			_place(it)
		i -= 1


func _place(it: Dictionary) -> void:
	var mi: MeshInstance3D = it["mi"]
	if not is_instance_valid(mi):
		return
	var t := float(it["t"])
	if t < 0.0:
		mi.visible = false
		return
	mi.visible = true
	var n: int = it["frames"]
	var f := int(t * float(it["fps"]))
	f = (f % n) if bool(it["loop"]) else mini(f, n - 1)
	var mat: StandardMaterial3D = it["mat"]
	mat.uv1_offset = Vector3(float(f % int(it["cols"])) / float(it["cols"]), float(f / int(it["cols"])) / float(it["rows"]), 0.0)
	var pos: Vector3 = it["pos"]
	var ex: Dictionary = it["extra"]
	if ex.has("move_to"):
		var a := clampf(t / float(ex["move_dur"]), 0.0, 1.0)
		pos = (ex["move_from"] as Vector3).lerp(ex["move_to"], a)
	var b: Basis = rogue._view_basis() if rogue != null else Basis.IDENTITY
	if ex.has("drop"):
		var d := clampf(t / float(ex["drop_dur"]), 0.0, 1.0)
		pos += b.y * float(ex["drop"]) * (1.0 - d * d)      # 从上方加速落下
	var roll := float(it["roll"])
	var bb := b
	if absf(roll) > 0.0001:
		bb = b.rotated(b.z, roll)
	mi.global_transform = Transform3D(bb, pos)
	var w := float(it["world"])
	mi.scale = Vector3(w * float(it["zx"]), w * float(it["zy"]), 1.0)
	# 末尾 25% 淡出（弹体循环播放时不淡）
	var life := float(it["frames"]) / float(it["fps"])
	if ex.has("life"):
		life = float(ex["life"])
	var alpha := 1.0
	if not bool(it["loop"]):
		alpha = clampf((life - t) / (life * 0.25), 0.0, 1.0)
	var c: Color = ex.get("tint", Color.WHITE)
	mat.albedo_color = Color(c.r, c.g, c.b, alpha)
