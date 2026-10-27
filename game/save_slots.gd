extends RefCounted
# 存档槽（用户 2026-10-18：“你给我几个存档 slot”）。
# 每个槽就是一份独立的 pokemon_points.cfg 快照（点数 / 护符 / 捕获 / 糖果 / 努力值 / 技能机器 / 球全在里面）。
# 1 号槽沿用原来的文件名，旧存档不用迁移；2、3 号槽是各自独立的新文件。

const Points := preload("res://game/pokemon_points.gd")

const COUNT := 9   # 用户 2026-10-24：3 → 9 个
const INDEX_PATH := "user://save_slot.cfg"


static func path_for(slot: int) -> String:
	var s := clampi(slot, 1, COUNT)
	return Points.DEFAULT_PATH if s == 1 else "user://pokemon_points_slot%d.cfg" % s


static func current() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(INDEX_PATH) != OK:
		return 1
	var v = cfg.get_value("slot", "index", 1)
	return clampi(int(v), 1, COUNT) if (v is int or v is float) else 1


static func set_current(slot: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("slot", "index", clampi(slot, 1, COUNT))
	cfg.save(INDEX_PATH)


# 一个槽的概况（只读，不改文件）：empty / corrupt / balance / caught。
static func summary(slot: int) -> Dictionary:
	var p := path_for(slot)
	# 存档保存中途被打断时正式档可能暂时不在，.bak / .tmp 还在：照样算“有档”，交给 reload() 恢复。
	if not (FileAccess.file_exists(p) or FileAccess.file_exists(p + ".bak") or FileAccess.file_exists(p + ".tmp")):
		return {"empty": true}
	var w := Points.new(p)
	w.reload()
	return {"empty": false, "corrupt": w.is_corrupt(), "balance": w.balance, "caught": w.caught.size()}
