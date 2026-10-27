extends RefCounted
# 超级进化 / 超极巨化（用户 2026-10-23：“全加进去和进化道具一样售卖”“卖贵点，这 2 个形态只能局内进化，不能选择”）。
#
# 数据：data/rogue_upstream/special_forms.json（从原版包抽的 48 个超级形态 + 33 个超极巨形态：六维 / 属性 / 特性 / 道具 / 图）。
#   注意：PokéRogue 的超极巨形态六维比普通形态高（总和约 +100），照原版数据。
# 图：assets/pokemon/forms/{front,back}/<编号>-<形态>.json/png；闪光只有一档 assets/pokemon_shiny/0/forms/。
# 玩法：局内商店里，当前上场这只有超级 / 超极巨形态就卖对应的超级石 / 极巨菇，买了立刻变身，这一局一直保持；
#   再进化（等级 / 进化道具）就变回普通形态。选宠页不能直接选这两种形态。
# 没做：原始回归（海皇牙 / 固拉多）、无极汰那的无极巨化。

const PATH := "res://data/rogue_upstream/special_forms.json"
const PREFIX := "FORM:"   # 商品 ID：FORM:物种编号:形态键，如 FORM:6:mega-x
const PRICE := {"mega": 1000, "gmax": 1000}   # 卖贵点（用户）
const KIND_ZH := {"mega": "超级", "gmax": "超极巨"}

static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_data = parsed
		# JSON 的数字读出来是小数：六维 / 总和 / 经验转成整数
		for k in _data:
			for fm: Dictionary in _data[k]:
				var st: Array = []
				for v in fm.get("stats", []):
					st.append(int(v))
				fm["stats"] = st
				fm["base_total"] = int(fm.get("base_total", 0))
				fm["base_exp"] = int(fm.get("base_exp", 0))


# 这只有哪些超级 / 超极巨形态（没有返回空数组）。
static func forms_for(species_id: int) -> Array:
	_load()
	return (_data.get(str(species_id), []) as Array).duplicate(true)


static func form_of(species_id: int, form_key: String) -> Dictionary:
	for f: Dictionary in forms_for(species_id):
		if str(f.get("form_key", "")) == form_key:
			return f
	return {}


static func product_id(species_id: int, form_key: String) -> String:
	return "%s%d:%s" % [PREFIX, species_id, form_key]


static func is_product(source_id: String) -> bool:
	return source_id.begins_with(PREFIX)


# FORM:6:mega-x -> {"species": 6, "form_key": "mega-x"}；格式不对返回空字典。
static func parse(source_id: String) -> Dictionary:
	if not is_product(source_id):
		return {}
	var rest := source_id.substr(PREFIX.length())
	var i := rest.find(":")
	if i <= 0 or not rest.substr(0, i).is_valid_int():
		return {}
	return {"species": int(rest.substr(0, i)), "form_key": rest.substr(i + 1)}


static func price(form: Dictionary) -> int:
	return int(PRICE.get(str(form.get("kind", "mega")), 1000))


# 道具名：超级石用原版中文名，极巨菇统一叫“极巨菇”。
static func item_name(form: Dictionary) -> String:
	var zh := str(form.get("item_zh", ""))
	if zh != "":
		return zh
	return "极巨菇" if str(form.get("kind", "")) == "gmax" else str(form.get("item", ""))


# 显示名：超级喷火龙X / 超极巨喷火龙。
static func display_name(base_name: String, form: Dictionary) -> String:
	var tail := ""
	var fk := str(form.get("form_key", ""))
	if fk.ends_with("-x"):
		tail = "X"
	elif fk.ends_with("-y"):
		tail = "Y"
	return "%s%s%s" % [KIND_ZH.get(str(form.get("kind", "")), ""), base_name, tail]
