extends RefCounted
# 融合宝可梦（用户 2026-10-20：“融合就是主宠外型”）。规则照原版 src/field/pokemon.ts（c16a3bbf）：
#   六维：两只的种族值逐项平均、向上取整（Math.ceil((a + b) / 2)）。
#   属性：主宠的第一属性 + 融合对象的第二属性（没有第二属性或和主宠第一属性一样就用它的第一属性；
#         还一样就不加），只有一个属性时再补主宠的第二属性。
#   特性：用融合对象那只的特性，栏位按对象那一系自己选的（选宠页融合时按 E 换，2026-10-22）；被动仍是主宠的。
#   招式：两只的升级招都能学（主宠的先，重复的不算）。
#   经验曲线 / 外观 / 叫声：主宠的（外观用户定：就是主宠外型）。
#   进化：主宠先进化；主宠这一级不能进化时，融合对象那一半按自己的等级进化表进化。
#   名字：两只名字各取一半拼起来（原版 getFusedSpeciesName 的意思；中文按字数对半）。
# 选宠页“融合”里选对象（要抓到过；不能选自己），存档 [dex_extra] fusion {主宠编号: 对象编号}。百变怪不能融合。


static func types(base_types: Array, partner_types: Array) -> Array:
	if base_types.is_empty():
		return partner_types.duplicate()
	var out: Array = [base_types[0]]
	if partner_types.size() >= 2 and partner_types[1] != base_types[0]:
		out.append(partner_types[1])
	elif not partner_types.is_empty() and partner_types[0] != base_types[0]:
		out.append(partner_types[0])
	if out.size() == 1 and base_types.size() >= 2:
		out.append(base_types[1])
	return out


static func base_stats(a: Array, b: Array) -> Array:
	var out: Array = []
	for i in mini(a.size(), b.size()):
		out.append(int(ceilf((float(a[i]) + float(b[i])) / 2.0)))
	return out


static func name_of(base_name: String, partner_name: String) -> String:
	if partner_name == "":
		return base_name
	var head := base_name.left(int(ceilf(base_name.length() / 2.0)))
	var tail := partner_name.right(partner_name.length() - int(floorf(partner_name.length() / 2.0)))
	return head + tail
