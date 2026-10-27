extends RefCounted
# 本作图鉴数据接口（只读 data/pokedex.json，静态提取自原作只读副本）。
# 全国图鉴 1~1025，每行 id / 简体中文名 / 世代 / 属性 / 原作六项种族值 / 缩略图路径。
# 原作的六项种族值只作资料展示，不是本作战斗数值；本轮只有绿毛虫 id=10 可上场。
#
# 用法：
#   Pokedex.list()          # Array[Dictionary] 全部 1025 行，id 升序
#   Pokedex.entry(10)       # 单行；无效 id 返回 {}
#   Pokedex.icon(10)        # Texture2D；缺失返回 null
#   Pokedex.is_playable(10) # 仅 id=10 为 true

const DATA_PATH := "res://data/pokedex.json"
const PLAYABLE_ID := 10

static var _loaded := false
static var _rows: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    if not FileAccess.file_exists(DATA_PATH):
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not (parsed is Array):
        return
    for raw: Variant in parsed:
        if not (raw is Dictionary):
            continue
        var types: Array[String] = []
        for t: Variant in raw.get("types", []):
            types.append(str(t))
        var stats: Array[int] = []
        for s: Variant in raw.get("stats", []):
            stats.append(int(s))
        var row := {
            "id": int(raw.get("id", 0)),
            "name": str(raw.get("name", "")),
            "generation": int(raw.get("generation", 0)),
            "types": types,
            "stats": stats,
            "icon": str(raw.get("icon", "")),
        }
        _rows.append(row)
        _by_id[row["id"]] = row


# 全部 1025 行，调用方拿到的字典是缓存行的同引用，不要写回。
static func list() -> Array[Dictionary]:
    _ensure_loaded()
    return _rows.duplicate()


# 无效 id 返回 {}。
static func entry(id: int) -> Dictionary:
    _ensure_loaded()
    if _by_id.has(id):
        var row: Dictionary = _by_id[id]
        return row
    return {}


# 图标缺失返回 null。
static func icon(id: int) -> Texture2D:
    _ensure_loaded()
    var row := entry(id)
    if row.is_empty():
        return null
    var path := str(row.get("icon", ""))
    if path.is_empty() or not ResourceLoader.exists(path):
        return null
    var res: Variant = load(path)
    return res as Texture2D


# 本轮只有绿毛虫（id=10）可上场；其他都只作图鉴资料。
static func is_playable(id: int) -> bool:
    return id == PLAYABLE_ID
