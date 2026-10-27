extends RefCounted
# 属性汇总：(基础 + 固定加成) × (1 + 百分比加成)。每笔加成按来源登记，可覆盖和撤回。
# attack.tackle / attack.bug_bite 同时继承 attack 上的加成。
const NAMES := {"hp_max": "生命", "defence": "防御", "move_speed": "移速", "magnet": "吸附距离",
    "attack": "伤害", "attack.tackle": "撞击伤害", "attack.bug_bite": "虫咬伤害", "aspd": "出招速度"}

var _base := {}    # 属性 -> 基础
var _flat := {}    # 属性 -> {来源: 固定加成}
var _pct := {}     # 属性 -> {来源: 百分比加成}
var _cache := {}   # 属性 -> 算好的最终值；任何一笔改动都清空
var _cap := {}     # 属性 -> 硬上限（神奇守护的最大 HP 恒 1：闪光开局 +10% 等百分比也不能把它抬上去）


func set_base(key: String, v: float) -> void:
	_base[key] = v
	_cache.clear()


func base(key: String) -> float:
	return _base.get(key, 0.0)


# 登记一笔加成（flat 固定、pct 百分比，可以只给一样）。同一个来源对同一个属性再登记就是覆盖；两样都是 0 等于撤掉
func add(key: String, source: String, flat := 0.0, pct := 0.0) -> void:
	_put(_flat, key, source, flat)
	_put(_pct, key, source, pct)
	_cache.clear()


# 撤掉一个来源的加成。key 留空 = 它在所有属性上的都撤
func remove(source: String, key := "") -> void:
	for table: Dictionary in [_flat, _pct]:
		if key != "":
			if table.has(key):
				table[key].erase(source)
		else:
			for k in table:
				table[k].erase(source)
	_cache.clear()


# 最终值 =（基础 + 所有固定加成）×（1 + 所有百分比加成）。百分比加起来低于 −100% 时按 0 算
func value(key: String) -> float:
	if _cache.has(key):
		return _cache[key]
	var v := (base(key) + flat_sum(key)) * maxf(0.0, 1.0 + pct_sum(key))
	if _cap.has(key):
		v = minf(v, float(_cap[key]))
	_cache[key] = v
	return v


# 这个属性（连同它上一层的）固定加成一共多少
func flat_sum(key: String) -> float:
	return _sum(_flat, key)


# 这个属性（连同它上一层的）百分比加成一共多少（0.3 = +30%）
func pct_sum(key: String) -> float:
	return _sum(_pct, key)


func has_source(source: String) -> bool:
	for table: Dictionary in [_flat, _pct]:
		for k in table:
			if table[k].has(source):
				return true
	return false


# 把数据表里的一包按等级登记上去。pack 的格式见 data\gongfa.gd 开头；等级 ≤ 0 = 撤掉这个来源
func apply_pack(source: String, pack: Array, level: int) -> void:
	remove(source)
	if level <= 0:
		return
	var flats := {}
	var pcts := {}
	for row: Dictionary in pack:
		if level < int(row.get("at", 1)):
			continue
		var n: int = maxi(0, level - int(row.get("skip", 0)))
		var key: String = row["stat"]
		flats[key] = float(flats.get(key, 0.0)) + float(row.get("flat", 0.0)) + float(row.get("flat_lv", 0.0)) * n
		pcts[key] = float(pcts.get(key, 0.0)) + float(row.get("pct", 0.0)) + float(row.get("pct_lv", 0.0)) * n
	for key: String in flats:
		add(key, source, flats[key], pcts[key])


# 防御公式，主角和怪共用：先减防御，再按减伤比例打折，最后“至少掉 1”（v2.0 第 22 条：至少 1 放在防御和减伤之后）。
# 主角的常驻减伤另有五成封顶（main.gd 传进来之前就封好了）。
# 选“减法”的理由：数小、好懂、和用户举的“+1 防御”对得上；缺点是对一下一下的小伤害特别管用（暗器怕甲），这是有意留的。
static func mitigate(dmg: float, defence: float, reduce := 0.0) -> float:
	if dmg <= 0.0:
		return 0.0
	return maxf(1.0, (dmg - defence) * (1.0 - clampf(reduce, 0.0, 0.9)))


func _put(table: Dictionary, key: String, source: String, v: float) -> void:
	if is_zero_approx(v):
		if table.has(key):
			table[key].erase(source)
		return
	if not table.has(key):
		table[key] = {}
	table[key][source] = v


func _sum(table: Dictionary, key: String) -> float:
	var total := 0.0
	var k := key
	while true:
		if table.has(k):
			for src in table[k]:
				total += float(table[k][src])
		var dot := k.rfind(".")
		if dot < 0:
			break
		k = k.substr(0, dot)
	return total


# 硬上限：cap < 0 = 取消。
func set_cap(key: String, cap: float) -> void:
	if cap < 0.0:
		_cap.erase(key)
	else:
		_cap[key] = cap
	_cache.clear()
