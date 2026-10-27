extends RefCounted
# 招式按类型生效（用户 2026-10-24）：哪个招算哪一类只在这里判断一次，战斗规则（main/arts.gd）和招式说明共用。
#   buff   强化自己的招（剑舞 / 高速移动 / 变硬…）：带着就生效一次、整局保持，不叠层
#   aura   降别人能力的招（叫声 / 瞪眼 / 吐丝…）：光环，攻击圈里的怪各降一次，不用放
#   screen 反射壁 / 光墙 / 极光幕：常驻减伤
#   heal   回自己血的招：血低于门槛才自动放，冷却长（睡觉门槛更低）
#   field  天气 / 场地：持续 20 秒、冷却 40 秒
#   ""     其他（伤害招、上异常的招、特殊流程）：照旧自动放

const PokemonMoves := preload("res://data/pokemon_moves.gd")

const HEAL_GATE := 0.5    # 回血招先放（能反复用），文柚果留到更低才吃（用户 2026-10-24）
const REST_GATE := 0.35
const HEAL_CD := 40.0
const FIELD_SECS := 20.0
const FIELD_CD := 40.0
const SCREEN_MULT := 0.7
const VEIL_MULT := 0.8


static func _effs(id: String) -> Array:
	return (PokemonMoves.MOVES.get(id, {}) as Dictionary).get("effects", [])


static func _is_status(id: String) -> bool:
	return str((PokemonMoves.MOVES.get(id, {}) as Dictionary).get("category", "")) == "变化"


static func _self(eff: Dictionary) -> bool:
	return str(eff.get("who", "")) == "self" or bool(eff.get("self", false))   # 老格式（变硬 / 变圆）写 "self": true


static func is_self_buff(id: String) -> bool:
	var effs := _effs(id)
	if not _is_status(id) or effs.is_empty():
		return false
	for eff: Dictionary in effs:
		if str(eff.get("kind", "")) != "stat" or not _self(eff):
			return false
	return true


# 别的“带着就生效一次、整局保持”的招（用户 2026-10-24：“聚气感觉应该是被动”）：
# 聚气（会心 +2）、水流环 / 扎根（持续回血）、腹鼓 / 甩肉 / 魂舞烈音爆（扣血换强化，只扣一次）。
const PASSIVE_KINDS := ["crit_boost", "regen", "belly_drum", "cut_hp_boost", "acupressure"]
# 防守救急（守住 / 挺住 / 尖刺防守…）：血低于 GUARD_GATE 自动放，GUARD_SECS 秒什么都伤不到，冷却 HEAL_CD（用户 2026-10-24）
const GUARD_GATE := 0.3
const GUARD_SECS := 1.5


static func is_passive_other(id: String) -> bool:
	var effs := _effs(id)
	if not _is_status(id) or effs.is_empty():
		return false
	var hit := false
	for eff: Dictionary in effs:
		var k := str(eff.get("kind", ""))
		if PASSIVE_KINDS.has(k):
			hit = true
		elif k != "stat" or not _self(eff):
			return false
	return hit


static func is_guard(id: String) -> bool:
	if not _is_status(id):
		return false
	for eff: Dictionary in _effs(id):
		if str(eff.get("kind", "")) == "protect":
			return true
	return false


# 解异常（芳香治疗 / 治愈铃声 / 勇气填充）：中了异常才自动放。
static func is_cure(id: String) -> bool:
	if not _is_status(id):
		return false
	for eff: Dictionary in _effs(id):
		if str(eff.get("kind", "")) == "cure_self":
			return true
	return false


# 识破 / 气味侦测：光环（攻击圈里的怪都被识破）。
static func is_expose_aura(id: String) -> bool:
	var effs := _effs(id)
	if not _is_status(id) or effs.is_empty():
		return false
	for eff: Dictionary in effs:
		if str(eff.get("kind", "")) != "expose":
			return false
	return true


static func is_aura(id: String) -> bool:
	if is_expose_aura(id):
		return true
	var effs := _effs(id)
	if not _is_status(id) or effs.is_empty():
		return false
	for eff: Dictionary in effs:
		if str(eff.get("kind", "")) != "stat" or _self(eff) or int(eff.get("stages", 0)) >= 0:
			return false
	return true


static func is_screen(id: String) -> bool:
	for eff: Dictionary in _effs(id):
		if str(eff.get("kind", "")) == "screen":
			return true
	return false


# 回血门槛（0 = 不是这一类）。祈愿 / 吞下 / 吸取力量流程特殊，不算。
static func heal_gate(id: String, gate := HEAL_GATE) -> float:
	for eff: Dictionary in _effs(id):
		var k := str(eff.get("kind", ""))
		if k == "rest":
			return REST_GATE
		if (k == "heal" and str(eff.get("who", "self")) == "self") or k == "wish":
			return gate   # 祈愿也按回血门槛放（2026-10-24）
	return 0.0


static func is_field(id: String) -> bool:
	for eff: Dictionary in _effs(id):
		if str(eff.get("kind", "")) in ["weather", "terrain", "side", "float"]:   # 电磁飘浮也限时（2026-10-24）   # 神秘守护 / 白雾 / 幸运咒语 / 玩水 / 玩泥巴 / 重力：本来就是 20 秒，冷却也拉到 40
			return true
	return false


static func role(id: String) -> String:
	if is_self_buff(id):
		return "buff"
	if is_passive_other(id):
		return "passive"
	if is_aura(id):
		return "aura"
	if is_screen(id):
		return "screen"
	if is_guard(id):
		return "guard"
	if is_cure(id):
		return "cure"
	if heal_gate(id) > 0.0:
		return "heal"
	if is_field(id):
		return "field"
	return ""


const STAT_ZH := {"atk": "攻击", "attack": "攻击", "def": "防御", "defence": "防御", "defense": "防御", "spatk": "特攻",
	"special_attack": "特攻", "spdef": "特防", "special_defence": "特防", "special_defense": "特防", "spd": "速度", "speed": "速度",
	"acc": "命中", "accuracy": "命中", "eva": "闪避", "evasion": "闪避"}


static func _stat_text(id: String) -> String:
	var parts: Array = []
	for eff: Dictionary in _effs(id):
		var n := int(eff.get("stages", 0))
		parts.append("%s %s%d 级" % [str(STAT_ZH.get(str(eff.get("stat", "")), str(eff.get("stat", "")))), "+" if n > 0 else "", n])
	return "、".join(parts)


# 本作改版的招：直接写本作规则，前面标【改版】（用户 2026-10-24：“直接写我们的规则但是标识这是改版”）。普通招返回 ""。
static func note(id: String) -> String:
	var orig := str((PokemonMoves.MOVES.get(id, {}) as Dictionary).get("desc", ""))
	match role(id):
		"buff":
			return "【改版】自己的%s。带着就生效一次、整局保持，不叠层，不会反复放。" % _stat_text(id)
		"passive":
			var kinds: Array = []
			for eff: Dictionary in _effs(id):
				kinds.append(str(eff.get("kind", "")))
			if kinds.has("crit_boost"):
				return "【改版】被动：带着就常驻，会心率 1/24 → 1/2（会心一击伤害 ×1.5）；不用放。"
			if kinds.has("acupressure"):
				return "【改版】被动：开局随机一项能力（攻击 / 防御 / 特攻 / 特防 / 速度 / 命中）+2 级，整局保持；不用放。"
			if kinds.has("regen"):
				return "【改版】被动：带着就一直慢慢回血（每 4 秒回最大 HP 的 1/16）；不用放。"
			return "【改版】开局放一次、整局保持（只扣一次血）。效果：%s" % orig
		"guard":
			return "【改版】救急：血低于 %d%% 时自动放，%.1f 秒内什么都伤不到你，冷却 %d 秒。效果：%s" % [int(GUARD_GATE * 100.0), GUARD_SECS, int(HEAL_CD), _strip_turns(orig)]
		"cure":
			return "【改版】中了异常就自动放，冷却 %d 秒。效果：%s" % [int(HEAL_CD), orig]
		"aura":
			if is_expose_aura(id):
				return "【改版】光环：攻击圈里的怪都被识破（一般 / 格斗招打得到幽灵系，它们的闪避提高也没用）；不用放。"
			return "【改版】光环：攻击圈里的每只怪%s，每只只降一次。带着就生效、不用放；技能栏里关掉就停。" % _stat_text(id)
		"screen":
			var which := ""
			for eff: Dictionary in _effs(id):
				if str(eff.get("kind", "")) == "screen":
					which = str(eff.get("screen", ""))
			if which == "both":
				return "【改版】常驻减伤：受到的物理、特殊伤害都 ×%.1f。带着就生效、不用放；关掉就失效。" % VEIL_MULT
			return "【改版】常驻减伤：受到的%s伤害 ×%.1f。带着就生效、不用放；关掉就失效。" % ["物理" if which == "physical" else "特殊", SCREEN_MULT]
		"heal":
			return "【改版】救急：血低于 %d%% 时自动放，放完冷却 %d 秒。效果：%s" % [int(round(heal_gate(id) * 100.0)), int(HEAL_CD), orig]
		"field":
			return "【改版】持续 %d 秒、冷却 %d 秒。效果：%s" % [int(FIELD_SECS), int(FIELD_CD), _strip_turns(orig)]
	return ""


# 原作说明里的“在 5 回合内”这类字眼去掉（实时制，时长已经写在前面）。
static func _strip_turns(text: String) -> String:
	var re := RegEx.new()
	re.compile("在?[0-9０-９５]+回合(内|之间|中|里)?[，,]?")
	return re.sub(text, "", true)


# 招式说明：改版的招直接写本作规则（带【改版】），其他照原说明。
static func desc_with_note(id: String) -> String:
	var n := note(id)
	return n if n != "" else str((PokemonMoves.MOVES.get(id, {}) as Dictionary).get("desc", ""))
