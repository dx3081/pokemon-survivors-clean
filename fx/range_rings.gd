extends Node3D
# 攻击范围圈（设置里的“显示攻击范围”开关，用户 2026-10-18）：主角脚下一圈青色 = 招式最远射程，
# 附近敌人脚下一圈红色 = 贴身挥击距离、橙色 = 远程招射程。只画，不参与任何判定。
# 用法：main 每帧调 draw([{"pos": Vector3, "r": 半径米, "color": Color}, ...])；空数组 = 清掉。

const SEGMENTS := 48
const BAND := 0.07      # 圈的粗细（米）
const Y := 0.06         # 离地高度

var _mesh := ImmediateMesh.new()
var _inst := MeshInstance3D.new()


func _init() -> void:
	_inst.mesh = _mesh
	_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	_inst.material_override = mat
	add_child(_inst)


func draw(rings: Array) -> void:
	_mesh.clear_surfaces()
	if rings.is_empty():
		return
	for ring: Dictionary in rings:
		var c: Vector3 = ring["pos"]
		var r: float = maxf(0.05, float(ring["r"]))
		var col: Color = ring["color"]
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in SEGMENTS + 1:
			var a := TAU * float(i) / float(SEGMENTS)
			var dir := Vector3(cos(a), 0.0, sin(a))
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(c + dir * (r - BAND) + Vector3(0, Y, 0))
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(c + dir * r + Vector3(0, Y, 0))
		_mesh.surface_end()
