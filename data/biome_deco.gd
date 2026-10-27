extends RefCounted
# 两种做法，每个地区可以各写一套，用 world/scenery.gd 的 deco_style 切换（"model" / "sprite" / "off"）。现行 = sprite（和高清像素地面一个画风；KayKit 3D 的树和灌木颜色太艳，只留在这里备用）：
#   model  = 3D 低多边形模型（KayKit，CC0，assets/props/kaykit/），随机朝向
# 全部只是装饰：不挡路、不挡子弹、不进障碍表（block 恒为 0）。
#
# DECO_PROPS[id]：
#   kind = "model"：path = 模型文件，s = 缩放范围，shadow = 投不投影
#   kind = "sprite"：tex = 图，h = 立起来多高（米，宽按图的比例），shadow 恒为 false
# DECO[地区][风格] = 列表，每项：
#   id    = DECO_PROPS 里的 id
#   n     = 每个区块（24 米见方）平均放几个（小数部分按概率）
#   group = （可选）[最少, 最多]：成簇出现，簇半径 spread
#   mask  = （可选）[低, 高]：只放在平原同款噪声值在这个范围里的地方（比如只放在“林子里”）
#   clear = （可选）出生点周围多少米内不放，默认 8
#   tint  = （可选）这个物件整体的亮度倍数（默认 1.0），亮得突兀的压低一点
# 整体密度倍数：表里的 n 是“相对多少”，乘上它才是每个区块的个数（调一个数就能整体稀 / 密）
const DENSITY := 7.0
const KK := "res://assets/props/kaykit/"
const SP := "res://assets/props/sprites/"

const DECO_PROPS := {
	# ---- 3D 模型（KayKit）----
	"kk_bare_a": {"kind": "model", "path": KK + "forest/Tree_Bare_1_A_Color1.gltf", "s": [0.9, 1.25], "shadow": true},
	"kk_bare_b": {"kind": "model", "path": KK + "forest/Tree_Bare_2_A_Color1.gltf", "s": [0.9, 1.25], "shadow": true},
	"kk_bare_c": {"kind": "model", "path": KK + "forest/Tree_Bare_1_B_Color1.gltf", "s": [0.8, 1.1], "shadow": true},
	"kk_rock_a": {"kind": "model", "path": KK + "forest/Rock_2_A_Color1.gltf", "s": [0.9, 1.5], "shadow": true},
	"kk_rock_b": {"kind": "model", "path": KK + "forest/Rock_3_A_Color1.gltf", "s": [0.9, 1.5], "shadow": true},
	"kk_bush_a": {"kind": "model", "path": KK + "forest/Bush_1_A_Color1.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_bush_b": {"kind": "model", "path": KK + "forest/Bush_2_A_Color1.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_bush_c": {"kind": "model", "path": KK + "forest/Bush_3_A_Color1.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_bush_d": {"kind": "model", "path": KK + "forest/Bush_4_A_Color1.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_tree_a": {"kind": "model", "path": KK + "forest/Tree_1_A_Color1.gltf", "s": [0.8, 1.1], "shadow": true},
	"kk_barrel": {"kind": "model", "path": KK + "hex/barrel.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_crate": {"kind": "model", "path": KK + "hex/crate_A_small.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_crate_big": {"kind": "model", "path": KK + "hex/crate_A_big.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_sack": {"kind": "model", "path": KK + "hex/sack.gltf", "s": [0.9, 1.2], "shadow": true},
	"kk_bucket": {"kind": "model", "path": KK + "hex/bucket_empty.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_wheelbarrow": {"kind": "model", "path": KK + "hex/wheelbarrow.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_tent": {"kind": "model", "path": KK + "hex/tent.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_stone_pile": {"kind": "model", "path": KK + "hex/resource_stone.gltf", "s": [0.9, 1.2], "shadow": true},
	"kk_lumber": {"kind": "model", "path": KK + "hex/resource_lumber.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_flag": {"kind": "model", "path": KK + "hex/flag_red.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_well": {"kind": "model", "path": KK + "hex/building_well_green.gltf", "s": [0.9, 1.1], "shadow": true},
	"kk_hrock_a": {"kind": "model", "path": KK + "hex/rock_single_A.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_hrock_b": {"kind": "model", "path": KK + "hex/rock_single_B.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_hrock_c": {"kind": "model", "path": KK + "hex/rock_single_C.gltf", "s": [0.9, 1.4], "shadow": true},
	"kk_htree_a": {"kind": "model", "path": KK + "hex/tree_single_A.gltf", "s": [0.8, 1.1], "shadow": true},
	"kk_htree_b": {"kind": "model", "path": KK + "hex/tree_single_B.gltf", "s": [0.8, 1.1], "shadow": true},
	"kk_lily_a": {"kind": "model", "path": KK + "hex/waterlily_A.gltf", "s": [0.9, 1.3], "shadow": false},
	"kk_lily_b": {"kind": "model", "path": KK + "hex/waterlily_B.gltf", "s": [0.9, 1.3], "shadow": false},
	"kk_wplant_a": {"kind": "model", "path": KK + "hex/waterplant_A.gltf", "s": [0.9, 1.3], "shadow": false},
	"kk_wplant_b": {"kind": "model", "path": KK + "hex/waterplant_B.gltf", "s": [0.9, 1.3], "shadow": false},
	"kk_wplant_c": {"kind": "model", "path": KK + "hex/waterplant_C.gltf", "s": [0.9, 1.3], "shadow": false},
	"kk_pillar": {"kind": "model", "path": KK + "dungeon/pillar.glb", "s": [0.9, 1.1], "shadow": true},
	"kk_pillar_broken": {"kind": "model", "path": KK + "dungeon/pillar_broken.glb", "s": [0.9, 1.1], "shadow": true},
	"kk_bricks": {"kind": "model", "path": KK + "dungeon/bricks.glb", "s": [0.9, 1.2], "shadow": true},
	"kk_rubble": {"kind": "model", "path": KK + "dungeon/floorDecoration_shatteredBricks.glb", "s": [0.9, 1.2], "shadow": false},
	"kk_torch": {"kind": "model", "path": KK + "dungeon/torchWall.glb", "s": [0.9, 1.1], "shadow": false},
	"sp_dead_tree": {"kind": "sprite", "tex": SP + "dead_tree.png", "h": 5.0},
	"sp_cactus": {"kind": "sprite", "tex": SP + "cactus.png", "h": 3.0},
	"sp_gravestone": {"kind": "sprite", "tex": SP + "gravestone.png", "h": 2.0},
	"sp_crystal": {"kind": "sprite", "tex": SP + "crystal.png", "h": 2.4},
	"sp_mushrooms": {"kind": "sprite", "tex": SP + "mushrooms.png", "h": 1.3},
	"sp_fern": {"kind": "sprite", "tex": SP + "fern.png", "h": 1.5},
	"sp_reeds": {"kind": "sprite", "tex": SP + "reeds.png", "h": 2.4},
	"sp_lily": {"kind": "sprite", "tex": SP + "lily.png", "h": 1.4},
	"sp_barrel": {"kind": "sprite", "tex": SP + "barrel.png", "h": 1.6},
	"sp_crate": {"kind": "sprite", "tex": SP + "crate.png", "h": 1.6},
	"sp_well": {"kind": "sprite", "tex": SP + "well.png", "h": 2.8},
	"sp_pillar": {"kind": "sprite", "tex": SP + "broken_pillar.png", "h": 3.2},
	"sp_boulder": {"kind": "sprite", "tex": SP + "boulder.png", "h": 2.2},
	"sp_snow_pine": {"kind": "sprite", "tex": SP + "snowy_pine.png", "h": 5.5},
	"sp_round_bush": {"kind": "sprite", "tex": SP + "round_bush.png", "h": 1.8},
	"sp_signpost": {"kind": "sprite", "tex": SP + "signpost.png", "h": 2.4},
	"sp_bamboo": {"kind": "sprite", "tex": SP + "bamboo_clump.png", "h": 4.6},
	"sp_lantern": {"kind": "sprite", "tex": SP + "stone_lantern.png", "h": 2.8},
	"sp_snowy_rock": {"kind": "sprite", "tex": SP + "snowy_rock.png", "h": 2.4},
	"sp_brick_wall": {"kind": "sprite", "tex": SP + "brick_wall.png", "h": 1.8},
	"sp_planks": {"kind": "sprite", "tex": SP + "plank_bridge.png", "h": 1.2},
}

# 各地区的装饰。没写的地区 / 没写的风格 = 不加。n 是相对多少（乘 DENSITY 才是每区块个数）。
const DECO := {
	"desert": {
		"model": [
			{"id": "kk_bare_a", "n": 0.7}, {"id": "kk_bare_b", "n": 0.6}, {"id": "kk_hrock_a", "n": 0.9},
			{"id": "kk_hrock_b", "n": 0.7}, {"id": "kk_crate", "n": 0.25}, {"id": "kk_barrel", "n": 0.2}, {"id": "kk_tent", "n": 0.06},
		],
		"sprite": [
			{"id": "sp_cactus", "n": 1.1}, {"id": "sp_dead_tree", "n": 0.35}, {"id": "sp_boulder", "n": 0.5},
			{"id": "sp_crate", "n": 0.08}, {"id": "sp_barrel", "n": 0.08},
		],
	},
	"ruins": {
		"model": [
			{"id": "kk_pillar_broken", "n": 0.9}, {"id": "kk_pillar", "n": 0.35}, {"id": "kk_bricks", "n": 1.2},
			{"id": "kk_rubble", "n": 1.6}, {"id": "kk_hrock_c", "n": 0.8},
		],
		"sprite": [
			{"id": "sp_pillar", "n": 1.0}, {"id": "sp_boulder", "n": 0.4}, {"id": "sp_brick_wall", "n": 0.7},
			{"id": "sp_lantern", "n": 0.25}, {"id": "sp_gravestone", "n": 0.2},
		],
	},
	"town": {
		"model": [
			{"id": "kk_barrel", "n": 0.8}, {"id": "kk_crate", "n": 0.7}, {"id": "kk_crate_big", "n": 0.25},
			{"id": "kk_sack", "n": 0.6}, {"id": "kk_bucket", "n": 0.4}, {"id": "kk_wheelbarrow", "n": 0.2},
			{"id": "kk_well", "n": 0.08}, {"id": "kk_flag", "n": 0.2}, {"id": "kk_lumber", "n": 0.2},
		],
		"sprite": [
			{"id": "sp_barrel", "n": 0.7, "tint": 0.85}, {"id": "sp_crate", "n": 0.7, "tint": 0.85}, {"id": "sp_well", "n": 0.07, "tint": 0.9},
			{"id": "sp_signpost", "n": 0.2}, {"id": "sp_lantern", "n": 0.4}, {"id": "sp_planks", "n": 0.3},
		],
	},
	"jungle": {
		"model": [
			{"id": "kk_bush_a", "n": 2.0}, {"id": "kk_bush_b", "n": 1.6}, {"id": "kk_bush_c", "n": 1.6}, {"id": "kk_bush_d", "n": 1.2},
			{"id": "kk_bare_c", "n": 0.4}, {"id": "kk_htree_a", "n": 0.5},
		],
		"sprite": [
			{"id": "sp_bamboo", "n": 1.2}, {"id": "sp_fern", "n": 1.6}, {"id": "sp_mushrooms", "n": 0.8},
			{"id": "sp_round_bush", "n": 0.8},
		],
	},
	"snowy_forest": {
		"model": [
			{"id": "kk_bare_a", "n": 0.8}, {"id": "kk_bare_b", "n": 0.6}, {"id": "kk_hrock_a", "n": 0.8},
			{"id": "kk_hrock_b", "n": 0.6}, {"id": "kk_htree_b", "n": 0.4},
		],
		"sprite": [
			{"id": "sp_snow_pine", "n": 1.3}, {"id": "sp_snowy_rock", "n": 0.9}, {"id": "sp_dead_tree", "n": 0.25},
		],
	},
	"swamp": {
		"model": [
			{"id": "kk_lily_a", "n": 1.6}, {"id": "kk_lily_b", "n": 1.6}, {"id": "kk_wplant_a", "n": 1.8},
			{"id": "kk_wplant_b", "n": 1.4}, {"id": "kk_wplant_c", "n": 1.4}, {"id": "kk_bare_c", "n": 0.5},
		],
		"sprite": [
			{"id": "sp_reeds", "n": 1.6}, {"id": "sp_lily", "n": 1.2}, {"id": "sp_mushrooms", "n": 0.6},
			{"id": "sp_dead_tree", "n": 0.5}, {"id": "sp_fern", "n": 0.5},
		],
	},
	"graveyard": {
		"sprite": [
			{"id": "sp_gravestone", "n": 1.5}, {"id": "sp_dead_tree", "n": 0.7}, {"id": "sp_mushrooms", "n": 0.3},
			{"id": "sp_boulder", "n": 0.25},
		],
	},
	"fairy_cave": {
		"sprite": [
			{"id": "sp_crystal", "n": 1.4}, {"id": "sp_mushrooms", "n": 0.9}, {"id": "sp_boulder", "n": 0.3},
		],
	},
	"forest": {
		"sprite": [
			{"id": "sp_fern", "n": 1.3}, {"id": "sp_mushrooms", "n": 0.7}, {"id": "sp_round_bush", "n": 0.7},
			{"id": "sp_boulder", "n": 0.3},
		],
	},
	"temple": {
		"sprite": [
			{"id": "sp_lantern", "n": 0.9, "tint": 0.8}, {"id": "sp_pillar", "n": 0.6, "tint": 0.9}, {"id": "sp_boulder", "n": 0.2, "tint": 0.9},
		],
	},
	"cave": {
		"sprite": [
			{"id": "sp_crystal", "n": 0.4, "tint": 0.75}, {"id": "sp_boulder", "n": 0.9, "tint": 0.6}, {"id": "sp_mushrooms", "n": 0.5, "tint": 0.8},
		],
	},
}


static func list_for(biome: String, style: String) -> Array:
	var d: Dictionary = DECO.get(biome, {})
	return d.get(style, [])


static func def_of(id: String) -> Dictionary:
	return DECO_PROPS.get(id, {})


# 把一个装饰物件做成可以放进 MultiMesh 的网格
static func build_mesh(id: String) -> Mesh:
	var d: Dictionary = DECO_PROPS[id]
	if d["kind"] == "sprite":
		return _sprite_mesh(d)
	return _model_mesh(d)


static func _model_mesh(d: Dictionary) -> Mesh:
	var scene := load(d["path"]) as PackedScene
	var root := scene.instantiate()
	var out := ArrayMesh.new()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		# 节点相对根的变换要带上（KayKit 的 glb 有些会放一个缩放 / 朝向）
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = xf * verts[i]
				if i < norms.size():
					norms[i] = (xf.basis * norms[i]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := mi.mesh.surface_get_material(s)
			if mat == null and mi.get_surface_override_material(s) != null:
				mat = mi.get_surface_override_material(s)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
	root.free()
	return out


const SHADOW_ALPHA := 0.42
const SPRITE_LIGHT := 0.92   # 牌子不受光，整体压一点亮度，免得比地面亮、显得突兀
static var _blob: ImageTexture


static func _blob_texture() -> ImageTexture:
	if _blob != null:
		return _blob
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_blob = ImageTexture.create_from_image(img)
	return _blob


const SPRITE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
varying vec3 tint;
void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	// 完全正对相机（脚在地面原点不动）：镜头是从斜上方往下看的，立着的竖面会被压扁，
	// 让牌子垂直于视线，画面上看到的就是原图的样子
	vec3 wpos = origin + INV_VIEW_MATRIX[0].xyz * VERTEX.x * s + INV_VIEW_MATRIX[1].xyz * VERTEX.y * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
}
void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.5) discard;
	ALBEDO = t.rgb * tint * %SPRITE_LIGHT%;
}
"""


static func _sprite_mesh(d: Dictionary) -> Mesh:
	var tex := load(d["tex"]) as Texture2D
	var h: float = d["h"]
	var w: float = h * float(tex.get_width()) / float(tex.get_height())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vs := [Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0), Vector3(w * 0.5, h, 0), Vector3(-w * 0.5, h, 0)]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(vs[i])
	var mesh := st.commit()
	var sh := Shader.new()
	sh.code = SPRITE_SHADER.replace("%SPRITE_LIGHT%", str(SPRITE_LIGHT))
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", tex)
	mesh.surface_set_material(0, mat)
	# 脚下一团柔和的软阴影（贴地的深色椭圆），不然牌子像贴在画面上、飘在地面之上
	var sw := w * 0.78
	var sd := w * 0.40
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sv := [Vector3(-sw, 0.03, -sd), Vector3(sw, 0.03, -sd), Vector3(sw, 0.03, sd), Vector3(-sw, 0.03, sd)]
	var suv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		sst.set_uv(suv[i])
		sst.set_normal(Vector3.UP)
		sst.add_vertex(sv[i])
	sst.commit(mesh)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _blob_texture()
	smat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, smat)
	# 面片是在顶点着色器里再摆朝向的，视锥剔除要用放大的包围盒，免得斜着看时被误剔除
	mesh.custom_aabb = AABB(Vector3(-w, 0, -w), Vector3(w * 2.0, h, w * 2.0))
	return mesh
