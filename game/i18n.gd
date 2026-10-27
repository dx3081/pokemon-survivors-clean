extends Translation
# 中英切换（用户 2026-10-26：“做个语言，中文和英文”）。
# 游戏代码里的字都是中文；这里不改那几千处，而是在“显示”这一步翻：
# Label / Button / 提示框等控件显示文字时 Godot 会自动 tr()，语言是 en 时就走到这里的 _get_message。
#   1. 整句查表（i18n/rogue.json 原版对照、i18n/auto.json 枚举名转写、i18n/en.json 本作自己的字）；
#   2. 带数字的句子按模板对（中文模板 "点数 %d · 已捕获 %d" ↔ 英文模板），%s 里的内容再递归翻；
#   3. 还对不上：按标点 / 数字 / BBCode 拆成小段，各段查表后拼回去（“攻击：12”这种拼出来的字）。
# 查不到的保持中文，不报错。结果有缓存。

const LOCALES := ["zh", "en"]
const LOCALE_NAMES := {"zh": "中文", "en": "English"}

var exact := {}
var templates: Array = []   # [{"re": RegEx, "pre": String, "en": String, "kinds": Array}]
var _cache := {}
var _han := RegEx.new()
var _split := RegEx.new()
var _fine := RegEx.new()


func _init() -> void:
	locale = "en"
	_han.compile("[\\x{4e00}-\\x{9fff}]")
	# 先按 BBCode 和标点切成短句（短句里留着空格和数字，好对“第 %d 波”这种模板），对不上再按空格 / 数字细切
	_split.compile("(\\[[^\\]]*\\]|[：:·、，,。！!？?（）()/|→▸▾★☆<>《》“”\"【】~～…；;]+)")
	_fine.compile("(\\s+|[0-9]+(?:\\.[0-9]+)?%?|[+\\-×x]+)")
	_load("res://i18n/rogue.json")   # 原版 PokéRogue 自己的中英对照（官方译名优先）
	_load("res://i18n/auto.json")    # 枚举名转写，补原版没有的
	_load("res://i18n/en.json")
	_load("res://i18n/en_fix.json")   # 人工改的短译名（排版放不下长英文），最后读、全覆盖


func _load(path: String, override := false) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.has("exact"):
		for k in d["exact"]:
			exact[k] = d["exact"][k]
		# 后读的模板排前面（人工改的优先）
		var before := templates.duplicate()
		templates.clear()
		for pair in d.get("templates", []):
			_add_template(str(pair[0]), str(pair[1]))
		templates.append_array(before)
	elif d is Dictionary:
		for k in d:
			if override or not exact.has(k):
				exact[k] = d[k]


var _ph := RegEx.create_from_string("%(%|[-+ 0]*[0-9]*(?:\\.[0-9]+)?[dsf])")


func _add_template(zh: String, en: String) -> void:
	var pat := "^"
	var kinds: Array = []
	var last := 0
	for m in _ph.search_all(zh):
		pat += _esc(zh.substr(last, m.get_start() - last))
		var tok := m.get_string(1)
		if tok == "%":
			pat += "%"
		elif tok.ends_with("d"):
			pat += "(-?[0-9]+)"
			kinds.append("d")
		elif tok.ends_with("f"):
			pat += "(-?[0-9]+(?:\\.[0-9]+)?)"
			kinds.append("f")
		else:
			pat += "(.*?)"
			kinds.append("s")
		last = m.get_end()
	pat += _esc(zh.substr(last)) + "$"
	var re := RegEx.new()
	if re.compile(pat) != OK:
		return
	var first := _ph.search(zh)
	templates.append({"re": re, "pre": zh.substr(0, first.get_start()) if first else zh, "en": en, "kinds": kinds})


static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\" + ch
		else:
			out += ch
	return out


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message)
	if s.is_empty() or _han.search(s) == null:
		return src_message
	if _cache.has(s):
		return _cache[s]
	var r := translate_text(s)
	if _cache.size() > 30000:
		_cache.clear()
	_cache[s] = r
	return StringName(r)


func translate_text(s: String) -> String:
	if _han.search(s) == null:
		return s
	if exact.has(s):
		return exact[s]
	if s.contains("\n"):
		var parts := s.split("\n")
		for i in parts.size():
			parts[i] = translate_text(parts[i])
		return "\n".join(parts)
	var t := _try_templates(s)
	if t != "":
		return t
	return _by_pieces(s)


func _try_templates(s: String) -> String:
	for tp in templates:
		if not s.begins_with(tp["pre"]):
			continue
		var m: RegExMatch = (tp["re"] as RegEx).search(s)
		if m == null:
			continue
		var en: String = tp["en"]
		var out := ""
		var i := 0
		var last := 0
		for pm in _ph.search_all(en):
			out += en.substr(last, pm.get_start() - last)
			var tok := pm.get_string(1)
			if tok == "%":
				out += "%"
			else:
				i += 1
				var v := m.get_string(i) if i <= m.get_group_count() else ""
				out += translate_text(v) if (tp["kinds"].size() >= i and tp["kinds"][i - 1] == "s") else v
			last = pm.get_end()
		out += en.substr(last)
		return out
	return ""


func _by_pieces(s: String) -> String:
	var out := ""
	var last := 0
	for m in _split.search_all(s):
		out += _piece(s.substr(last, m.get_start() - last))
		out += m.get_string()
		last = m.get_end()
	out += _piece(s.substr(last))
	# 拆开查的时候中文标点换成英文的
	return out.replace("：", ": ").replace("，", ", ").replace("（", " (").replace("）", ")").replace("、", ", ").replace("。", ". ").replace("！", "!").replace("？", "?").replace("；", "; ")


func _piece(p: String) -> String:
	if p.is_empty() or _han.search(p) == null:
		return p
	var core := p.strip_edges()
	var lead := p.substr(0, p.find(core))
	var tail := p.substr(lead.length() + core.length())
	if exact.has(core):
		return lead + exact[core] + tail
	var t := _try_templates(core)
	if t != "":
		return lead + t + tail
	# 细切：按空格 / 数字 / 正负号
	var out := ""
	var last := 0
	for m in _fine.search_all(p):
		var w := p.substr(last, m.get_start() - last)
		out += str(exact.get(w, w))
		out += m.get_string()
		last = m.get_end()
	var w2 := p.substr(last)
	return out + str(exact.get(w2, w2))


# ---- 语言设置 ----
# 只在英文时把翻译表挂到 TranslationServer；退出前（main 的 _exit_tree）摘掉，
# 不然进程关闭时脚本先被释放、翻译表后释放会崩（2026-10-26 检查全过但退出码 0xC0000005）。
static var _tr: Translation = null


static func install() -> void:
	if _tr == null:
		_tr = load("res://game/i18n.gd").new()
		TranslationServer.add_translation(_tr)


static func uninstall() -> void:
	if _tr != null:
		TranslationServer.remove_translation(_tr)
		_tr = null


# 切语言；中文就是原文，不挂翻译表。
static func set_language(code: String) -> void:
	if code == "en":
		install()
		TranslationServer.set_locale("en")
	else:
		uninstall()
		TranslationServer.set_locale("zh")


static func language() -> String:
	return "en" if _tr != null and TranslationServer.get_locale().begins_with("en") else "zh"
