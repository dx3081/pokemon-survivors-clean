extends RefCounted
# 升级规则与进化的纯函数层（本轮新增；本作 AI 工程实现）。
# 公式、字段和来源核对写在同目录 game/POKEMON_GROWTH_SOURCE.md。
#
# 这里只放纯函数：不读节点、不弹界面、不读存档、不写状态。
# 目前只接入绿毛虫进化链 #0010 → #0011 → #0012；不建 1025 种全物种进化 / 捕捉 / 个体值架构。
#
# 经验曲线（2026-10-15 接线）：`xp_needed` 不再自算立方，唯一委托已验纯层
# game/pokemon_species_exp.gd 按物种原 growthRate 查原 `ms` / `rX`；见
# game/POKEMON_SPECIES_EXP_RUNTIME_SOURCE.md。
const SpeciesExp := preload("res://game/pokemon_species_exp.gd")

# 六项顺序与原作图鉴 / data/pokedex.json 一致：生命 / 攻击 / 防御 / 特攻 / 特防 / 速度。
const STAT_COUNT := 6
# 没有等级上限（用户 2026-10-17：“游戏不要设定 99 级上限”）。原来这里封顶 100；现在放到 9999 当“无限”：
# 100 级以后照 game/pokemon_species_exp.gd 里已有的公式（立方 / 混合）继续算升级经验和六维，不再有“满级不升级”。
const MAX_LEVEL := 9999
# 本作实时战斗里招式的初始攻击基准（level 1 的原作 ATK = 5），用于把原作 ATK 换算成招式基础伤害。
const BASE_ATTACK := 5.0

# 本轮占位个体参数（AI 工程选择，可回退，不是用户定稿）：
# IV 全 0、性格中性 id 0。main/state.gd 与 ui/town.gd 都从这里取默认值，
# 避免城镇显示和实际出发各写一套导致数字对不上；不新增培养 / 随机 / 存档。
const DEFAULT_IVS: Array = [0, 0, 0, 0, 0, 0]
const DEFAULT_NATURE_ID := 0



# 按原版 calculateStats() 的公式，从种族值、等级、个体值、性格倍率算出六项。
#
#   base_stats 长度 6，顺序 [HP, ATK, DEF, SPATK, SPDEF, SPD]，对应原作 baseStats / 本作图鉴 stats。
#   level      当前等级（1 起）。
#   ivs        长度 6 的个体值 0..31；本作本轮固定全 0（AI 占位，口子保留）。
#   nature     长度 6 的性格倍率，1.0 = 中性；由 nature_multipliers(nature_id) 生成，本轮 id 0（中性）。
#
# 原作公式（原作 Rogue 没有 EV 项；本作加了局外营养饮料的努力值，用户 2026-10-16 定：每颗 +10、单项 252、六项都能拉满）：
#   非 HP：o = floor((2*base + iv + floor(ev/4)) * level * 0.01) + 5
#   HP：  o = floor((2*base + iv + floor(ev/4)) * level * 0.01) + level + 10
#   ev 缺省 / 全 0 时与原作公式完全相同（floor(0/4) = 0）。
#   性格倍率 != 1：>1 用 ceil(o*nature)，<1 用 floor(o*nature)，再 max(..., 1)；HP 不吃性格。
# 返回 Array[int] 六项。base_stats 缺项按 0 处理，ivs/nature 缺项按 0 / 1 处理。
static func calculate_stats(base_stats: Array, level: int, ivs: Array = [], nature: Array = [], evs: Array = []) -> Array[int]:
    var out: Array[int] = []
    var lv := maxi(1, level)
    for i in STAT_COUNT:
        var base := float(base_stats[i]) if i < base_stats.size() else 0.0
        var iv := float(ivs[i]) if i < ivs.size() else 0.0
        var ev_bonus := floorf((float(evs[i]) if i < evs.size() else 0.0) / 4.0)
        var o := floorf((2.0 * base + iv + ev_bonus) * float(lv) * 0.01)
        if i == 0:
            # HP 固定 +level+10，不吃性格。
            out.append(int(o) + lv + 10)
            continue
        o += 5.0
        var mult := float(nature[i]) if i < nature.size() else 1.0
        if not is_equal_approx(mult, 1.0):
            o = ceilf(o * mult) if mult > 1.0 else floorf(o * mult)
            o = maxf(o, 1.0)
        out.append(int(o))
    return out


# 原作 25 性格表：Xp(nature_id, stat)（源内 getNatureStatMultiplier）。
# 返回六项倍率 [HP,ATK,DEF,SPATK,SPDEF,SPD]：+ 项 1.1、- 项 0.9、其余 1.0，HP 恒 1.0。
# ID 0/6/12/18/24 为中性；每个 id 同时只影响一项 +1.1 和另一项 -0.9（或中性）。
# 按源逐条抄录，不套通用宝可梦性格名表；调用方拿到的数组可直接喂给 calculate_stats 的 nature。
static func nature_multipliers(nature_id: int) -> Array:
    var mult := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    # 每行：[受影响的项下标, 用 1.1 的性格 id, 用 0.9 的性格 id]
    var rows := [
        [1, [1, 2, 3, 4], [5, 10, 15, 20]],      # ATK
        [2, [5, 7, 8, 9], [1, 11, 16, 21]],      # DEF
        [3, [15, 16, 17, 19], [3, 8, 13, 23]],   # SPATK
        [4, [20, 21, 22, 23], [4, 9, 14, 19]],   # SPDEF
        [5, [10, 11, 13, 14], [2, 7, 17, 22]],   # SPD
    ]
    for row: Array in rows:
        var stat_index: int = int(row[0])
        if nature_id in row[1]:
            mult[stat_index] = 1.1
        elif nature_id in row[2]:
            mult[stat_index] = 0.9
    return mult


# 25 性格的中文名，下标 = 原版 Nature 枚举（HARDY 0 … QUIRKY 24；上面倍率表就是按这个顺序）。
const NATURE_NAMES := ["勤奋", "怕寂寞", "勇敢", "固执", "顽皮", "大胆", "坦率", "悠闲", "淘气", "乐天",
    "胆小", "急躁", "认真", "爽朗", "天真", "内敛", "慢吞吞", "冷静", "害羞", "马虎",
    "温和", "温顺", "自大", "慎重", "浮躁"]
const NATURE_STAT_NAMES := ["HP", "攻击", "防御", "特攻", "特防", "速度"]


static func nature_name(nature_id: int) -> String:
    return str(NATURE_NAMES[clampi(nature_id, 0, NATURE_NAMES.size() - 1)])


# “固执（攻击↑ 特攻↓）” / “勤奋（不加不减）”
static func nature_label(nature_id: int) -> String:
    var m := nature_multipliers(nature_id)
    var up := ""
    var down := ""
    for i in m.size():
        if float(m[i]) > 1.0:
            up = NATURE_STAT_NAMES[i]
        elif float(m[i]) < 1.0:
            down = NATURE_STAT_NAMES[i]
    if up == "":
        return "%s（不加不减）" % nature_name(nature_id)
    return "%s（%s↑ %s↓）" % [nature_name(nature_id), up, down]


# 从 level 升到 level+1 所需经验：唯一委托 SpeciesExp.species_xp_needed(species_id, level)，
# 按该物种原 growthRate 查原 `ms` / `rX`（不在本文件复制第二套公式）。
# species_id 默认 10 是旧单参数调用兼容（历史玩家 API 绿毛虫链）；未知物种 / 未知成长组 /
# level<1 明确返回 -1，**不套 MEDIUM_FAST 兜底**；已知物种 100 级封顶返回 0。
# 绿毛虫链（MEDIUM_FAST）原 Fae 一级总经验为 0，所以 1→2 = 8（旧自算立方曾给 7），
# 2→3 = 19 与旧值相同；来源见 POKEMON_GROWTH_SOURCE.md / POKEMON_SPECIES_EXP_RUNTIME_SOURCE.md。
static func xp_needed(level: int, species_id: int = 10) -> int:
    return SpeciesExp.species_xp_needed(species_id, level)


# 击倒经验：照搬原作 Pokemon.getExpValue() 的单参与者野生战结果。
#
# 原作：getExpValue(){ return this.getSpeciesForm().getBaseExp()*this.level/5+1 }；
# 击倒分配时对当前单个参与者直接 s.push(Math.floor(getExpValue()))（无道具 / 无宝可病毒 /
# 非训练师战 / 无组队分摊），因此本作 effective = floor(base_exp * enemy_level / 5 + 1)。
# 不加任何自定义系数，也不改发放处的取整（这里一次 floor 即原作最终值）。
# 样例（base 39）：1 级 8、2 级 16、7 级 55、10 级 79。来源见 POKEMON_GROWTH_SOURCE.md。
static func defeat_exp(base_exp: int, enemy_level: int) -> int:
    return int(floor(float(base_exp) * float(enemy_level) / 5.0 + 1.0))


# 到达某等级时是否进化（只看纯等级进化；亲密度 / 招式 / 道具进化要带上下文，用 PokemonEvolution）。
# 只认本作已接入的物种；没有纯等级进化的原样返回。
static func next_evolution(species_id: int, level: int) -> int:
    var targets: Array[int] = preload("res://game/pokemon_evolution.gd").level_targets(species_id, level, 0, [])
    return targets[0] if not targets.is_empty() else species_id
