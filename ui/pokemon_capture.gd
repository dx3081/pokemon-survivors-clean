extends Node3D
#
# 这个脚本只做「展示 + 收集真实鼠标 / 按键 + 发信号」：
#   - 左侧竖排五种球的可点击按钮（中文名 + 当前库存 / 上限），点一个发 `ball_pressed(type)`；
#   - 一个贴地圆圈（半径由 main/state.gd::BALL_AIM_RADIUS 注入，初版 3 米），Camera3D 射线与
#     地面 y=0 平面求交，圈随鼠标；左键确认发 `throw_requested(world_pos)`，右键 / Esc 取消；
#   - UI 点击由 Godot GUI 自己消费（按钮是 STOP），不会穿透到 `_unhandled_input` 投球。
# 它不自己扣球、不掷骰、不写档、不暂停世界、不改 Engine.time_scale，也不生成任何假 Rogue 演出。
# 库存 / 地点校验 / 逐只原判定 / 持久解锁 / 奖励都在 main/state.gd + game/*.gd。
#
# 命名边界：本仓库里已有 `capture` = 旧的自动截图调试模式（main/state.gd），本脚本一律用
# ball_ / aim_ / throw_ 前缀，绝不覆盖那个 capture。

signal ball_pressed(ball_type: int)
signal throw_requested(world_pos: Vector3)
signal cancelled
signal shop_pressed     # 暂停抓宠界面右上角（B 区）的“商店”按钮
signal resume_pressed   # 暂停抓宠界面的“继续游戏”（Esc）
signal teleport_requested   # 按 T：想用瞬间移动（进入点地面传送的瞄准，慢动作）
signal settings_pressed   # 暂停抓宠界面右上角横条里的“设置”
signal detail_pressed   # 暂停抓宠界面的“宠物详情”：看当前宠物的特性 / 六维 / 每个招式的说明

const Hud := preload("res://ui/hud.gd")
const RogueSkin := preload("res://ui/rogue_skin.gd")
const RogueAtlas := preload("res://ui/rogue_atlas.gd")
const Shop := preload("res://game/pokemon_shop.gd")

# 捕获 HUD 画在现有战斗 HUD（layer 10）之上、城镇 / 商店 / 暂停 / 选择（20/25/27/28/30）之下：
# 商店或选择弹窗出现时会盖住它，不会并排冲突。
const LAYER := 12
const TELEPORT_AIM := -2   # show_aim 的“球种类”：-2 = 瞬间移动瞄准（不是球）
const RING_Y := 0.02

var cam: Camera3D = null
var aim_radius := 3.0
# 每帧从 main 自取可用性 + 库存的只读查询（返回 {"available": bool, "counts": Array}）。
var state_query := Callable()

var _layer: CanvasLayer
var _root: Control
var _panel: PanelContainer
var _title: Label
var _hint: Label
var _buttons := {}    # ball_type -> Button（只有原版球图标；名字和库存在悬停提示里）
var _counts := {}     # ball_type -> 右下角库存数字
var _shop_btn: Button      # B 区：只在暂停抓宠界面显示
var _resume_btn: Button
var _detail_btn: Button
var _settings_btn: Button
var _pause_mode := false
var _ring: MeshInstance3D
var _available := false
var _aiming := false
var _aim_type := -1
var _aim_pos := Vector3.ZERO
var _has_aim := false
# 最后已知的鼠标屏幕位置（来自 motion / 点击）；_has_mouse=false 时不做任何投影，
# 避免初始瞄准把旧圈或原点圈假显示成有效。
var _last_mouse_pos := Vector2.ZERO
var _has_mouse := false


func _init() -> void:
    # 暂停 / 选择 / 进化时主循环 early-return，但本页仍要刷新可用性并收起圈。
    process_mode = Node.PROCESS_MODE_ALWAYS
    _layer = CanvasLayer.new()
    _layer.layer = LAYER
    add_child(_layer)
    _build_hud()
    _build_ring()
    _layer.visible = false
    _ring.visible = false


func setup(camera: Camera3D, state_callable: Callable = Callable()) -> void:
    cam = camera
    state_query = state_callable


func _process(_delta: float) -> void:
    if state_query.is_valid():
        var state: Dictionary = state_query.call()
        set_available(bool(state.get("available", false)))
        set_counts(state.get("counts", []))
    # 瞄准不暂停世界、主角 / 镜头一直在动：每帧按**当前镜头**和最后鼠标屏幕位置重投影，
    # 让可见圈始终就是左键确认会用的位置；没有鼠标位置前不显示旧圈 / 原点圈。
    if _aiming and _has_mouse:
        _update_aim(_last_mouse_pos)


# ================= 只读查询 / 展示 =================

func set_aim_radius(radius: float) -> void:
    aim_radius = maxf(0.1, radius)
    _apply_ring_radius()


func is_aiming() -> bool:
    return _aiming


func aim_valid() -> bool:
    return _has_aim


# 当前有没有有效的圈位置（鼠标已经投影到地面）；高光圈里的怪要先问这个。
func has_aim() -> bool:
    return _aiming and _has_aim


func aim_position() -> Vector3:
    return _aim_pos


func aim_ball_type() -> int:
    return _aim_type


# 检查按球 type 找同一批真实按钮（不是另建模拟控件）。
func button_for(ball_type: int) -> Button:
    return _buttons.get(ball_type, null)


func visible_ball_types() -> Array:
    var out: Array = []
    for ball_type in _buttons:
        out.append(int(ball_type))
    out.sort()
    return out


# 可用性变化：不可用时收起整页并清圈（清圈要通知 main 同步 ball_aiming）。
func set_available(value: bool) -> void:
    if value == _available:
        return
    _available = value
    if _layer != null:
        _layer.visible = value
    if not value:
        var was_aiming := _aiming
        hide_aim()
        if was_aiming:
            cancelled.emit()


func set_counts(counts: Array) -> void:
    for ball_type in _buttons:
        var have := 0
        if ball_type < counts.size():
            have = int(counts[ball_type])
        var sid := Shop.ball_source_id(int(ball_type))
        var button: Button = _buttons[ball_type]
        button.tooltip_text = "[%d] %s %d/%d" % [int(ball_type) + 1, Shop.display_name(sid), have, Shop.BALL_CAP]   # 悬停看名字
        (_counts[ball_type] as Label).text = str(have)
        var disabled := have <= 0
        if button.disabled != disabled:
            button.disabled = disabled
            button.modulate = Color(0.45, 0.45, 0.5, 0.8) if disabled else Color.WHITE


# 暂停抓宠物模式：面板常驻、多一个“返回商店”按钮、提示文字改成“放圈后游戏继续”。
func set_pause_mode(value: bool) -> void:
    _pause_mode = value
    if _shop_btn != null:
        _shop_btn.visible = value
    if _resume_btn != null:
        _resume_btn.visible = value
    if _detail_btn != null:
        _detail_btn.visible = value
    if _settings_btn != null:
        _settings_btn.visible = value
    if _hint != null and not _aiming:
        _hint.text = _hint_idle()
        _hint.visible = false


func is_pause_mode() -> bool:
    return _pause_mode


# 球快捷键：数字键 1–5（主键盘 / 小键盘）对应五种球；面板可用、该球有库存才响应。
func hotkey_ball_type(keycode: int) -> int:
    var i: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5].find(keycode)
    if i < 0:
        i = [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5].find(keycode)
    return i


# ================= 瞄准 =================

func show_aim(ball_type: int, radius: float) -> void:
    set_aim_radius(radius)
    _aiming = true
    _aim_type = ball_type
    _has_aim = false
    # 还没有新的鼠标位置前不显示圈 / 不显示旧位置：等第一次 motion / 点击再给有效投影。
    _has_mouse = false
    if _ring != null:
        _ring.visible = false
    if _hint != null:
        _hint.visible = true   # 只在瞄准时出一行字
        if ball_type == TELEPORT_AIM:
            _hint.text = "瞬间移动：左键点要去的地方，右键 / 取消键退出"
        else:
            _hint.text = "瞄准「%s」：左键放圈，右键 / 取消键退出" % _ball_name(ball_type)


func hide_aim() -> void:
    _aiming = false
    _aim_type = -1
    _has_aim = false
    _has_mouse = false
    if _ring != null and is_instance_valid(_ring):
        _ring.visible = false
    if _hint != null:
        _hint.text = _hint_idle()
        _hint.visible = false


# 真实鼠标 / 按键：左键地面确认、右键或 Esc 取消；UI 点击先被按钮消费，不会走到这里。
# 左键只上报位置，**不在这里收圈**：收圈与否由后端 `_throw_ball_at` 决定（消费/真取消才收，
# 空圈 / 全被挡 / 非法位置等非消费拒绝保持"可见可操作"的瞄准，玩家可继续移动再点）。
func _unhandled_input(event: InputEvent) -> void:
    if _available and event is InputEventKey:
        var hk := event as InputEventKey
        if hk.pressed and not hk.echo:
            if hk.physical_keycode == KEY_T and not _aiming:
                get_viewport().set_input_as_handled()
                teleport_requested.emit()
                return
            var ball_type := hotkey_ball_type(hk.physical_keycode)
            if ball_type >= 0 and _buttons.has(ball_type) and not (_buttons[ball_type] as Button).disabled:
                get_viewport().set_input_as_handled()
                ball_pressed.emit(ball_type)
                return
    if not _aiming:
        return
    if event is InputEventMouseMotion:
        _update_aim((event as InputEventMouseMotion).position)
        return
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if not mouse.pressed:
            return
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            _update_aim(mouse.position)
            if not _has_aim:
                return
            get_viewport().set_input_as_handled()
            throw_requested.emit(_aim_pos)
        elif mouse.button_index == MOUSE_BUTTON_RIGHT:
            get_viewport().set_input_as_handled()
            hide_aim()
            cancelled.emit()
        return
    if event is InputEventKey:
        var key := event as InputEventKey
        if key.pressed and not key.echo and [KEY_ESCAPE, KEY_Q, KEY_E].has(key.physical_keycode):
            get_viewport().set_input_as_handled()
            hide_aim()
            cancelled.emit()


func _update_aim(screen_pos: Vector2) -> void:
    _last_mouse_pos = screen_pos
    _has_mouse = true
    var ground := _ground_at(screen_pos)
    _has_aim = bool(ground["ok"])
    if _has_aim:
        _aim_pos = ground["pos"]
        if _ring != null:
            _ring.position = Vector3(_aim_pos.x, RING_Y, _aim_pos.z)
    if _ring != null and is_instance_valid(_ring):
        # 有效投影才显示圈；投影失效（相机转开 / 射线平行）时收起，不假显示旧位置。
        _ring.visible = _has_aim


# Camera3D 射线与地面 y=0 平面求交；射线与地面平行 / 命中点在相机背后都算无效。
func _ground_at(screen_pos: Vector2) -> Dictionary:
    if cam == null or not is_instance_valid(cam):
        return {"ok": false, "pos": Vector3.ZERO}
    var origin := cam.project_ray_origin(screen_pos)
    var dir := cam.project_ray_normal(screen_pos)
    if absf(dir.y) < 0.00001:
        return {"ok": false, "pos": Vector3.ZERO}
    var t := -origin.y / dir.y
    if t <= 0.0:
        return {"ok": false, "pos": Vector3.ZERO}
    var pos := origin + dir * t
    if not pos.is_finite():
        return {"ok": false, "pos": Vector3.ZERO}
    return {"ok": true, "pos": pos}


# ================= 搭界面 =================

func _ball_name(ball_type: int) -> String:
    var sid := Shop.ball_source_id(ball_type)
    return Shop.display_name(sid) if sid != "" else "球"


func _hint_idle() -> String:
    if _pause_mode:
        return "暂停中：选球（点按钮或数字键）→ 战场上左键放圈 → 球投出、游戏继续；右上角「商店」买东西"
    return "点球或按数字键 1–5，再在战场上左键放圈，右键 / 取消键退出"


func _build_hud() -> void:
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    # 整页只让按钮吃点击：空白处不挡投球 / 不挡战场。
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _layer.add_child(_root)

    # 左上偏中竖排，整块落在既有 HUD 的空档（调试字 y8 / 头目条 y104 中段 x340 起 /
    # 头像 y580 起 / 血条 y614 起 / 经验条 y690 起）之间，不压任何既有控件。
    _panel = PanelContainer.new()
    _panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
    _panel.offset_left = 16
    _panel.offset_top = 100
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # 用户 2026-10-20：面板太大，只放球的图标
    _root.add_child(_panel)

    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 4)
    column.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.add_child(column)
    var row := VBoxContainer.new()   # 竖着摆（用户 2026-10-20：还是喜欢以前竖排）
    row.add_theme_constant_override("separation", 2)
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.add_child(row)

    # 五个原版球图标（icons/items 的 pb / gb / ub / rb / mb）竖排：左上按键号、右下库存，悬停出名字
    var icons := ["pb", "gb", "ub", "rb", "mb"]
    var hover := StyleBoxFlat.new()
    hover.bg_color = Color(1, 1, 1, 0.12)
    hover.set_corner_radius_all(6)
    for ball_type in Shop.BALL_IDS.size():
        var button := Button.new()
        button.custom_minimum_size = Vector2(52, 52)
        # 只占图标那么大：下面的提示字把这一列撑到 272 宽时，按钮别跟着横向拉长（用户 2026-10-21：“好像有个隐形的框子”挡着放圈）
        button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
        button.focus_mode = Control.FOCUS_NONE
        button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for st in ["normal", "pressed", "focus", "disabled"]:
            button.add_theme_stylebox_override(st, StyleBoxEmpty.new())
        button.add_theme_stylebox_override("hover", hover)
        var ic := RogueSkin.outlined_icon(RogueAtlas.frame("icons/items", str(icons[ball_type])), 52)   # 描边和树果一样
        button.add_child(ic)
        var key := RogueSkin.label(str(int(ball_type) + 1), RogueSkin.SIZE_SMALL, "summary_gold")
        key.position = Vector2(2, 0)
        key.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
        key.add_theme_constant_override("outline_size", 6)
        button.add_child(key)
        var cnt := RogueSkin.label("0", RogueSkin.SIZE_SMALL, "window")
        cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        cnt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        cnt.grow_vertical = Control.GROW_DIRECTION_BEGIN
        cnt.offset_right = -2
        cnt.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
        cnt.add_theme_constant_override("outline_size", 6)
        button.add_child(cnt)
        button.pressed.connect(_on_ball_pressed.bind(int(ball_type)))
        row.add_child(button)
        _buttons[int(ball_type)] = button
        _counts[int(ball_type)] = cnt
    _hint = RogueSkin.label(_hint_idle(), RogueSkin.SIZE_SMALL, "window", true)
    _hint.custom_minimum_size = Vector2(272, 0)
    _hint.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
    _hint.add_theme_constant_override("outline_size", 6)
    _hint.visible = false
    column.add_child(_hint)
    # 右上角横条（击杀条下面）：商店 | 宠物详情 | 设置，三个同样大小的按钮并排，只在暂停抓宠界面显示。
    var bar := HBoxContainer.new()
    bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    bar.offset_right = -16
    bar.offset_left = -16
    bar.offset_top = 84   # 击杀条换成原版窗口后变高了，横条让到它下面
    bar.add_theme_constant_override("separation", 6)
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(bar)
    _shop_btn = RogueSkin.button("商店", RogueSkin.SIZE_SMALL, Vector2(84, 36))
    _shop_btn.visible = false
    _shop_btn.pressed.connect(func(): shop_pressed.emit())
    bar.add_child(_shop_btn)
    _detail_btn = RogueSkin.button("宠物详情", RogueSkin.SIZE_SMALL, Vector2(104, 36))
    _detail_btn.visible = false
    _detail_btn.pressed.connect(func(): detail_pressed.emit())
    bar.add_child(_detail_btn)
    _settings_btn = RogueSkin.button("设置", RogueSkin.SIZE_SMALL, Vector2(84, 36))
    _settings_btn.visible = false
    _settings_btn.pressed.connect(func(): settings_pressed.emit())
    bar.add_child(_settings_btn)
    _resume_btn = RogueSkin.button("继续（Esc）", RogueSkin.SIZE_SMALL, Vector2(110, 36))   # 从球面板挪到这排
    _resume_btn.pressed.connect(func(): resume_pressed.emit())
    _resume_btn.visible = false
    bar.add_child(_resume_btn)


func _on_ball_pressed(ball_type: int) -> void:
    ball_pressed.emit(ball_type)


func _build_ring() -> void:
    _ring = MeshInstance3D.new()
    _ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.9, 0.3, 0.9)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _ring.material_override = material
    _ring.position = Vector3(0, RING_Y, 0)
    add_child(_ring)
    _apply_ring_radius()


# 圆圈半径唯一来源是注入的 aim_radius（main/state.gd::BALL_AIM_RADIUS），这里只做几何。
func _apply_ring_radius() -> void:
    if _ring == null:
        return
    var mesh := TorusMesh.new()
    mesh.inner_radius = maxf(0.02, aim_radius - 0.08)
    mesh.outer_radius = aim_radius
    mesh.rings = 48
    mesh.ring_segments = 8
    _ring.mesh = mesh
