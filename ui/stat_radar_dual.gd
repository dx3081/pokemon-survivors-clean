extends Control
# 选宠页“能力”页的六边形图（用户 2026-10-24：原版按一下就把宝可梦图换成六维图）：
# 两层叠着画——蓝色 = 种族值（满格 180），金色 = 个体值（满格 31）；每个角写“种族 / 个体”两个数。
# HP 在上，顺时针 攻击 / 防御 / 速度 / 特防 / 特攻（和局内详情页同一个排法）。

const HD := preload("res://ui/hd_text.gd")
const ORDER := [0, 1, 2, 5, 4, 3]   # 六维下标 [HP, 攻, 防, 特攻, 特防, 速] → 画的顺序
const LABELS := ["HP", "攻击", "防御", "速度", "特防", "特攻"]
const BASE_FULL := 180.0
const IV_FULL := 31.0

var base: Array = []   # 种族值六项
var ivs: Array = []    # 个体值六项（没有就空）
var font_size := 11


func _draw() -> void:
	var c := size * 0.5 + Vector2(0, 2)
	var r := minf(size.x * 0.5 - 30.0, size.y * 0.5 - 20.0)
	var dirs: Array[Vector2] = []
	for i in 6:
		var ang := -PI / 2.0 + TAU * float(i) / 6.0
		dirs.append(Vector2(cos(ang), sin(ang)))
	for ring in [1.0, 0.66, 0.33]:
		var poly := PackedVector2Array()
		for d in dirs:
			poly.append(c + d * r * ring)
		poly.append(poly[0])
		draw_polyline(poly, Color(0.35, 0.35, 0.45, 0.55), 1.0, true)
	for d in dirs:
		draw_line(c, c + d * r, Color(0.35, 0.35, 0.45, 0.35), 1.0, true)
	if base.size() >= 6:
		_series(c, r, dirs, base, BASE_FULL, Color(0.25, 0.65, 0.95, 0.40), Color(0.2, 0.6, 0.95, 1.0))
	if ivs.size() >= 6:
		_series(c, r, dirs, ivs, IV_FULL, Color(0.95, 0.75, 0.2, 0.30), Color(0.9, 0.65, 0.1, 1.0))
	var f := HD.font()
	for i in 6:
		var bv := int(base[ORDER[i]]) if base.size() >= 6 else 0
		var iv := int(ivs[ORDER[i]]) if ivs.size() >= 6 else 0
		var t1: String = tr(LABELS[i])   # 自己画的字不会自动翻，手动 tr
		var t2 := "%d / %d" % [bv, iv]
		var w1 := f.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var p := c + dirs[i] * (r + 14.0)
		var dy := -2.0 if dirs[i].y < -0.5 else (8.0 if dirs[i].y > 0.5 else 2.0)
		draw_string(f, p + Vector2(-w1 * 0.5, dy - 2.0), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.25, 0.25, 0.3))
		draw_string(f, p + Vector2(-w2 * 0.5, dy + font_size - 1.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.15, 0.45, 0.75))


func _series(c: Vector2, r: float, dirs: Array[Vector2], vals: Array, full: float, fill: Color, line: Color) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var v := clampf(float(vals[ORDER[i]]) / full, 0.04, 1.0)
		pts.append(c + dirs[i] * r * v)
	draw_colored_polygon(pts, fill)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, line, 1.5, true)
