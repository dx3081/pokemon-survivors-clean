extends RefCounted
# 异常状态实时钟 · 只负责「原作回合换 1 秒」的余数、行动判定缓存与起停。
#
# 为什么单独一个文件：状态规则（game/pokemon_status.gd）是纯回合制规则，本作战斗是逐帧实时；
# 二者之间只差这一件事——把累计的有效战斗 delta 攒成整秒、每秒只推一次 before_action / end_turn，
# 并把当秒的行动判定缓存下来给出招 / 移动看。本文件不持有 HP、不画 UI、不掷骰、不认识招式，
# 也不做成全局 ActorRegistry / StatusManager / 回合总线；每个单位一个实例，放在该单位自己的字段里。
#
# 接口（角色侧不用实现任何东西，全部传闭包进来）：
#   update(status, on_tick: Callable, delta) -> int
#     status  = 这个单位自己的 game/pokemon_status.gd 实例（null = 没有状态）。
#     on_tick = 本逻辑秒的推进回调，返回 bool：false = 中途死亡 / 事件取消，立刻停在当秒。
#   activate() / stop()
#     第一次成功附加给本来无状态的单位开始走钟（elapsed = 0，状态马上可见）；
#     已经在走的钟不重置（加入另一类状态不重置、重复附加不刷新）；全清后复位。
#   blocked / can_act()
#     当秒判定缓存：决定接下来一秒能否出招。2..4 的「活动许可」读它，不每帧 / 每招重掷。
#
# 1 秒适配的几个明确取舍（game/POKEMON_STATUS_SOURCE.md 第七节有记录）：
#   - 目标太远、没有技能就绪，逻辑秒照样走；这是一秒回合适配，不是「有交互才走时间」。
#   - 大 delta（例如一次卡顿 2.5 秒）逐秒补：每补一秒都完整走一次 before_action → end_turn，
#     期间单位可能死亡；回调返回 false 时立刻停在当秒，不把 2.5 秒当一次处理。
#   - 单位状态在某一秒里被治愈时，本秒仍照常走完 end_turn（中毒 / 灼伤那一下），下一秒停钟。
#   - 没有状态的单位不攒时间、不运行重复状态判断、不耗随机。

var elapsed := 0.0        # 本秒已经累计的有效战斗时间（0..1）
var blocked := false      # 当秒行动判定缓存：true = 这一秒不能出招
var running := false      # 是否正在走钟（单位身上有状态）
var ticks := 0            # 真的推进过的逻辑秒数（调试 / 检查用）


func can_act() -> bool:
    return not blocked


# 单位第一次拿到状态。已在走的钟不重置；没在走的从 elapsed = 0 起跳。
func activate() -> void:
    if running:
        return
    running = true
    elapsed = 0.0
    blocked = false


# 状态全清：复位余数 / 缓存，并解除当秒的出招限制。
func stop() -> void:
    running = false
    elapsed = 0.0
    blocked = false


# 每个有效战斗帧调用一次。返回本帧**真的推进过的逻辑秒数**，含最后一次治愈 / 死亡的那一秒
# （大 delta 一次补齐多秒时，最后一次也会被算进返回值，不会被漏掉）。
# on_tick  = 本逻辑秒的 before_action + end_turn；返回 false = 中途死亡 / 事件取消，停在当秒。
# on_blocked（可选）= 本秒判定为「不能出招」时按契约消耗已就绪招的原冷却。
func update(status, on_tick: Callable, delta: float, on_blocked := Callable()) -> int:
    if status == null or not status.has_major() and not status.has_confusion():
        # 没有状态：不攒时间、不运行重复状态判断、不耗随机（普通单位走原战斗路径）。
        if running:
            stop()
        return 0
    if not running:
        # 第一次成功附加给本来无状态的单位：从本帧开始走，下一次满 1.0 秒才推。
        running = true
        elapsed = 0.0
        blocked = false
    elapsed += delta
    var advanced := 0
    while elapsed >= 1.0:
        elapsed -= 1.0
        ticks += 1
        # 一进循环就计数：这一逻辑秒真的推进过 before_action + end_turn。
        # 治愈 / 死亡 / 事件取消都发生在本秒**之内**，所以最后一次也要算进返回值，
        # 不能只在「还活着且还有状态」的分支末尾 +1（那样最后一次会被漏掉）。
        advanced += 1
        # 这一秒已经判定过；默认放行，只有宿主回调（before_action）说被挡才置 true。
        blocked = false
        var keep := true
        if on_tick.is_valid():
            keep = bool(on_tick.call())
        if blocked and on_blocked.is_valid():
            on_blocked.call()
        if not keep:
            # 当秒中途死亡 / 事件取消：余数不保留，等宿主自己清理。
            elapsed = 0.0
            break
        if not status.has_major() and not status.has_confusion():
            # 这一秒走完已经没有状态了：本秒的 end_turn 已经作用过，下一秒停钟（缓存同时解除）。
            stop()
            break
    return advanced
