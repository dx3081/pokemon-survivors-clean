extends RefCounted
# 战斗报告（用户 2026-10-16：“可能需要一个战斗 report 看看到底被什么搞死了”）。
#
# 一局里每次玩家掉血都记一条：时间、来源（哪种敌人 / 中毒 / 灼伤 / 混乱自伤 / 反伤）、等级、伤害、
# 受击后剩余 HP、受击时 4 米内的活敌人数（看敌人密度）。纯数据层：不读节点、不写文件；
# main 在死亡 / 通关结算时用 summary_lines() 给结算页补几行，用 full_text() / to_dict() 写整份报告。
#
# 只统计“玩家实际掉的血”（已被 0 血封顶后的数），治疗只记总量。

const NEARBY_RADIUS := 4.0
const TIMELINE_BUCKET := 5.0   # 时间线每格秒数
const LAST_HITS := 10          # 报告里列出的最后几次受击

var events: Array = []
var debuffs: Array = []   # 被敌人削弱能力的记录（不算受伤）
var heal_total := 0.0
var peak_nearby := 0


func reset() -> void:
	events.clear()
	debuffs.clear()
	heal_total = 0.0
	peak_nearby = 0


# kind: "enemy" 敌人近身；"dot" 中毒 / 灼伤 / 混乱自伤 / 反伤等非敌人来源。
func record(time: float, kind: String, source: String, level: int, amount: float, hp_after: float, nearby: int, move_name := "") -> void:
	if amount <= 0.0:
		return
	events.append({"t": time, "kind": kind, "source": source, "level": level, "amount": amount,
		"hp_after": hp_after, "nearby": nearby, "move": move_name})
	peak_nearby = maxi(peak_nearby, nearby)


# 被敌人削弱能力（叫声 / 瞪眼 / 摇尾巴 / 泼沙…）：单独记一份，不算受伤、不进伤害统计。
func record_debuff(time: float, source: String, move_name: String, stat_zh: String, delta: int, stage_after: int) -> void:
	debuffs.append({"t": time, "source": source, "move": move_name, "stat": stat_zh, "delta": delta, "stage": stage_after})


func record_heal(amount: float) -> void:
	if amount > 0.0:
		heal_total += amount


func total_damage() -> float:
	var sum := 0.0
	for e: Dictionary in events:
		sum += float(e["amount"])
	return sum


# 按来源汇总：[{source, kind, hits, total, share, max_hit, avg_level}]，伤害从高到低。
func by_source() -> Array:
	var acc := {}
	for e: Dictionary in events:
		var key := str(e["source"])
		if not acc.has(key):
			acc[key] = {"source": key, "kind": str(e["kind"]), "hits": 0, "total": 0.0, "max_hit": 0.0, "level_sum": 0, "moves": {}}
		var row: Dictionary = acc[key]
		row["hits"] = int(row["hits"]) + 1
		row["total"] = float(row["total"]) + float(e["amount"])
		row["max_hit"] = maxf(float(row["max_hit"]), float(e["amount"]))
		row["level_sum"] = int(row["level_sum"]) + int(e["level"])
		var mv := str(e.get("move", ""))
		if mv != "":
			row["moves"][mv] = float(row["moves"].get(mv, 0.0)) + float(e["amount"])
	var out: Array = []
	var all := total_damage()
	for key in acc:
		var row: Dictionary = acc[key]
		row["share"] = float(row["total"]) / all if all > 0.0 else 0.0
		row["avg_level"] = float(row["level_sum"]) / float(maxi(int(row["hits"]), 1))
		out.append(row)
	out.sort_custom(func(a, b): return float(a["total"]) > float(b["total"]))
	return out


# 按（来源·招式）汇总：[{label, total, hits}]，伤害从高到低；没有招式名的（中毒等）按来源名。
func by_move() -> Array:
	var acc := {}
	for e: Dictionary in events:
		var mv := str(e.get("move", ""))
		var label := str(e["source"]) if mv == "" else "%s·%s" % [e["source"], mv]
		if not acc.has(label):
			acc[label] = {"label": label, "total": 0.0, "hits": 0}
		acc[label]["total"] = float(acc[label]["total"]) + float(e["amount"])
		acc[label]["hits"] = int(acc[label]["hits"]) + 1
	var out: Array = acc.values()
	out.sort_custom(func(a, b): return float(a["total"]) > float(b["total"]))
	return out


# 时间线：每 TIMELINE_BUCKET 秒一格 [{from, damage, hits, peak_nearby}]，覆盖到 end_time。
func timeline(end_time: float) -> Array:
	var buckets: Array = []
	var count := int(ceil(maxf(end_time, 0.01) / TIMELINE_BUCKET))
	for i in count:
		buckets.append({"from": float(i) * TIMELINE_BUCKET, "damage": 0.0, "hits": 0, "peak_nearby": 0})
	for e: Dictionary in events:
		var idx := clampi(int(float(e["t"]) / TIMELINE_BUCKET), 0, count - 1)
		var b: Dictionary = buckets[idx]
		b["damage"] = float(b["damage"]) + float(e["amount"])
		b["hits"] = int(b["hits"]) + 1
		b["peak_nearby"] = maxi(int(b["peak_nearby"]), int(e["nearby"]))
	return buckets


func last_hits(n := LAST_HITS) -> Array:
	var start := maxi(0, events.size() - n)
	return events.slice(start)


# 结算页补的几行（短）：谁打得最多、最后一击、密度。
func summary_lines(max_sources := 3) -> Array:
	var lines: Array = []
	if events.is_empty():
		lines.append("战斗报告：本局没有受到伤害")
		return lines
	var rows := by_source()
	var parts: Array = []
	for i in mini(max_sources, rows.size()):
		var r: Dictionary = rows[i]
		parts.append("%s %d%%（%d 次）" % [r["source"], int(round(float(r["share"]) * 100.0)), int(r["hits"])])
	lines.append("受伤来源：" + "、".join(parts))
	var last: Dictionary = events[events.size() - 1]
	lines.append("最后一击：%s%s%s -%d（剩 %d 血，周围 %d 只）" % [last["source"], _mv(last), _lv(last), int(round(float(last["amount"]))), int(round(float(last["hp_after"]))), int(last["nearby"])])
	lines.append("总受伤 %d · 受击 %d 次 · 周围敌人最多 %d 只" % [int(round(total_damage())), events.size(), peak_nearby])
	return lines


# 敌人来源显示等级；中毒 / 灼伤 / 自伤 / 反伤没有等级，不显示。
func _mv(e: Dictionary) -> String:
	return "·" + str(e["move"]) if str(e.get("move", "")) != "" else ""


func _lv(e: Dictionary) -> String:
	return " Lv%d" % int(e["level"]) if str(e["kind"]) == "enemy" else ""


func _mmss(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


# 整份文字报告（写文件 / 打印用）。
func full_text(end_time: float, level: int, kills: int, outcome: String, extra: Array = []) -> String:
	var L: Array = []
	L.append("战斗报告 · %s · 撑了 %s · 等级 %d · 击杀 %d" % [outcome, _mmss(end_time), level, kills])
	for x in extra:
		L.append(str(x))
	L.append("总受伤 %d · 受击 %d 次 · 治疗总量 %d · 周围敌人最多 %d 只" % [int(round(total_damage())), events.size(), int(round(heal_total)), peak_nearby])
	L.append("")
	L.append("## 伤害来源（从多到少）")
	for r: Dictionary in by_source():
		L.append("- %s：%d（%d%%），%d 次，单次最高 %d，平均等级 %.1f%s" % [r["source"], int(round(float(r["total"]))), int(round(float(r["share"]) * 100.0)), int(r["hits"]), int(round(float(r["max_hit"]))), float(r["avg_level"]), "" if str(r["kind"]) == "enemy" else "（非敌人来源）"])
	L.append("")
	L.append("## 伤害招式（来源·招式，从多到少）")
	for r: Dictionary in by_move().slice(0, 12):
		L.append("- %s：%d，%d 次" % [r["label"], int(round(float(r["total"]))), int(r["hits"])])
	if not debuffs.is_empty():
		L.append("")
		L.append("## 被削弱（敌人的降能力招，共 %d 次命中，最多降到 -2 级）" % debuffs.size())
		for d: Dictionary in debuffs.slice(0, 20):
			L.append("- %s %s·%s：%s %+d → %d 级" % [_mmss(float(d["t"])), d["source"], d["move"], d["stat"], int(d["delta"]), int(d["stage"])])
	L.append("")
	L.append("## 时间线（每 %d 秒）" % int(TIMELINE_BUCKET))
	for b: Dictionary in timeline(end_time):
		if int(b["hits"]) > 0:
			L.append("- %s 起：受伤 %d，%d 次，周围敌人峰值 %d" % [_mmss(float(b["from"])), int(round(float(b["damage"]))), int(b["hits"]), int(b["peak_nearby"])])
	L.append("")
	L.append("## 最后 %d 次受击" % LAST_HITS)
	for e: Dictionary in last_hits():
		L.append("- %s %s%s%s -%d → 剩 %d 血（周围 %d 只）" % [_mmss(float(e["t"])), e["source"], _mv(e), _lv(e), int(round(float(e["amount"]))), int(round(float(e["hp_after"]))), int(e["nearby"])])
	return "\n".join(L) + "\n"


func to_dict(end_time: float, level: int, kills: int, outcome: String) -> Dictionary:
	return {"outcome": outcome, "time": end_time, "level": level, "kills": kills, "total_damage": total_damage(),
		"heal_total": heal_total, "peak_nearby": peak_nearby, "sources": by_source(), "events": events}
