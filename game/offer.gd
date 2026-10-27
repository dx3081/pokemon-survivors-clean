extends RefCounted
# 从可选池中无重复抽取升级卡；保留已有的通用抽样规则。

static func choose(pool: Array, taken: Dictionary, n := 3, forced: Array = []) -> Array:
	var rest: Array = pool.duplicate()
	var out: Array = []
	for c in forced:
		if out.size() < n and rest.has(c) and not out.has(c):
			out.append(c)
			rest.erase(c)
	var has_taken := false
	for c in out:
		has_taken = has_taken or taken.has(c["id"])
	var owned: Array = []
	for c in rest:
		if taken.has(c["id"]):
			owned.append(c)
	if not has_taken and not owned.is_empty():
		if out.size() >= n:
			rest.append(out.pop_back())   # 必须出现的占满了，让出最后一个位置给拿过的
		var first = owned[randi() % owned.size()]
		out.append(first)
		rest.erase(first)
	rest.shuffle()
	out.append_array(rest.slice(0, maxi(0, n - out.size())))
	out.shuffle()
	return out
