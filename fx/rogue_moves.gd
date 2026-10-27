extends Node3D
# 只读移植：绿毛虫一族招式改用宝可梦肉鸽原战斗动画数据（assets/pokemon/move_fx）播放特效。
# 本节点不参与伤害 / 冷却 / 范围 / 击退 / 减速 / 命中规则，只按原 JSON 的帧序和图层数据做 2.5D 显示。
# 素材、源路径、哈希与适配限制见 assets/pokemon/move_fx/SOURCES.md。
#
# 原引擎关键公式（index-7def6496.js 的 BattleAnim.play / getGraphicFrameData）：
#   每帧 50ms = Fi(3) = floor(3*1000/60)，Fi(i)=floor(i*1000/60)
#   图集按 96x96 切格（loadSpritesheet(graphic, "battle_anims", 96)）
#   focus 1 锚受击方：dx=x-128, dy=y+64
#   focus 2 锚出招方：dx=x,     dy=y
#   focus 3 规范线：s=x/128，位置=user→target 按 s 插值，垂直偏移 y+64*s
#   背景补间时长 = Fi(duration*3) ms（漏掉 *3 会让整段快/慢 3 倍）
#   整段时长 = 帧表（frames.length 个 50ms）+ 尾部 Fi(T)，T 是帧数单位的计数（见 _tail_units）
# 首帧对齐：原引擎帧 0 的事件在第一个 50ms 周期**结束**时（第一次 onRepeat）才触发，
#   本作在 play() 里把帧 0 对齐到 t=0；这是与原来的固定 1 帧（50ms）相位差，记在 SOURCES.md。
#
# 2026-10-15 异常战斗轮新增 5 招原动画（超音波 / 念力 / 毒粉 / 麻痹粉 / 催眠粉）：
#   - supersonic.json 顶层是**两变体数组**（原 MoveAnim.getAnim()：`Array.isArray($i.get(move))
#     ? $i.get(move)[user.isPlayer() ? 0 : 1]`）。玩家变体 25 帧、敌人变体 27 帧，不能拼成 52 帧。
#   - confusion.json 的 graphic 是空字符串，但 28 帧角色变换 + 帧 0/23 的
#     AnimTimedAddBgEvent / AnimTimedUpdateBgEvent 仍有完整演出（PRAS- Confusion BG + 原声音）。
#   - 三份粉末 JSON 的 hue 只有 import 期赋值（本文件 _read_anim 也读进来），**原播放代码没有使用**
#     （整个 bundle 只有 populateAnims 的 `case"hue":L.hue=parseInt(g)` 一处写、没有任何读），
#     所以本播放器保留原值但不额外调色。

const DIR := "res://assets/pokemon/move_fx/"
const FRAME_SECS := 0.05
const CELL := 96
const PIXEL_SIZE := 0.022     # 原 1 像素对应的世界单位；自定值，见 SOURCES.md
const ANCHOR_H := 0.9         # 角色中心相对脚底的高度
const SWEEP_MIN_DIST := 8.0   # 玩家和敌人几乎重叠时不做连线重映射
const CANON_W := 128.0        # 原规范线：user x=106 → target x=234
const CENTER_X := 128.0       # 原战场中心 x
# 出招方被原动画推走的距离超过这个值（世界单位）时，不动真身，另起一个半透明虚影去冲
# （用户 2026-10-18：“猛撞这些招数，其实可以弄出个虚影去撞人，而不是自己去撞”）。
const PHANTOM_MIN_OFFSET := 0.35
const PHANTOM_SHADER := preload("res://fx/phantom.gdshader")
const BODY_ZOOM_MIN := 0.55   # 出招 / 受击方真身精灵的缩放下限（别被原动画压成一条线）
const CENTER_Y := 64.0        # focus1 垂直常量：原 116 - 52 = 64，相对受击方中心
# 原 AnimTimedAddBgEvent：add.tileSprite(bgX-320, bgY-284, 896, 576) + origin(0,0) + scale 1.25。
# tileSprite 会按贴图原始尺寸平铺重复采样：896/tex_w x 576/tex_h 次（Confusion BG 256x192 → 3.5x3.0）。
const BG_W := 896.0
const BG_H := 576.0
const BG_SCALE := 1.25
const BG_ORIGIN_X := 320.0
const BG_ORIGIN_Y := 284.0
const BG_PIXEL_SIZE := 0.022  # 与图层同一像素→世界比例；2.5D 下只保原位置关系，尺寸/重复见 SOURCES.md

# 原 JSON 文件名（graphic 名称在 JSON 里，本表只映射招式 id → 帧表）。
# harden 的 graphic 是 PRAS- Clear Smog、gust 的 graphic 是 PRAS- Gust，均由 JSON 自带。
const MOVES := {
    "tackle": "tackle.json",
    "string_shot": "string-shot.json",
    "bug_bite": "bug-bite.json",
    "harden": "harden.json",
    "gust": "gust.json",
    "supersonic": "supersonic.json",
    "confusion": "confusion.json",
    "poison_powder": "poison-powder.json",
    "stun_spore": "stun-spore.json",
    "sleep_powder": "sleep-powder.json",
    # 2026-10-15 抓获选角前置四招：抓 7 帧 / 拍击 8 帧 / 瞪眼两变体各 6 帧 / 摇尾巴 24 帧。
    # 瞪眼顶层是两变体数组，`_anim_for` 按出招方玩家 / 敌人选 0 / 1（原 MoveAnim.getAnim()）。
    "scratch": "scratch.json",
    "pound": "pound.json",
    "leer": "leer.json",
    "tail_whip": "tail-whip.json",
    # 2026-10-15 捕获选角下一小段：叫声两变体 14/15 帧（frame0 是空 resourceName 的原声音事件，
    # 原 HB.execute 走 `n.user.cry(r)`，本播放器按出招方物种播原 cry）；啄单变体 9 帧
    # （frame 1/4/7 各一声原 PRSFX- Peck.wav，沿用已有 PRAS- Strike 图集）。
    "growl": "growl.json",
    "peck": "peck.json",
    # 2026-10-15 泼沙接真实战斗轮：原 sand-attack.json 顶层两变体、各 10 帧，frame0 一条命名原声
    # `PRSFX- Sand Attack.wav`；帧 0 相位 / 尾部 35 / 整段 1.083s 沿原已记录适配（下方注释）。
    "sand_attack": "sand-attack.json",
    # 2026-10-15 电光一闪接真实战斗轮：原 quick-attack.json 顶层两变体、各 13 帧，帧 3 一条命名原声
    # `PRSFX- Quick Attack.wav`（graphic 沿用已有 `PRAS- Strike.png`）；尾部 17 / 整段 0.933s。
    "quick_attack": "quick-attack.json",
    # 2026-10-16 变圆接真实战斗轮：原 defense-curl.json 顶层是**单个 object**（不是两变体数组），
    # 14 帧，帧 0 唯一一条命名原声 `PRSFX- Defense Curl1.wav`（graphic `PRAS- Gyro Ball`，原图集名，
    # 不代表本作实现陀螺球）；尾部 16 / 整段 0.966s。与变硬共用 `_cast_harden` 自身施放路径，
    # 只按传入 move_id 播各自原动画，不新增播放器 / 第二套自身 DEF。
    "defense_curl": "defense-curl.json",
    # 2026-10-16 电击接真实战斗轮：原 thunder-shock.json 顶层是**单个 object**（不是两变体数组），
    # 19 帧，graphic `PRAS- Electric`；帧 0 一条命名原声 `PRSFX- Thundershock.wav` + 空 resourceName 的
    # AnimTimedAddBgEvent / AnimTimedUpdateBgEvent（不画背景图，原事件仍访问、参与尾部计数），帧 16
    # 一条空 UpdateBgEvent。尾部 48 / 整段 1.750s；与念力共用「先伤害、命中后独立概率附加状态」窄路径，
    # 只按传入 move_id 播各自原动画，不新增播放器 / 第二套状态。
    "thunder_shock": "thunder-shock.json",
    # 2026-10-16 猛撞 / 舍身冲撞接真实战斗轮：原 take-down.json 顶层两变体各 19 帧（声帧 0 / 4，尾 14，1.183s）；
    # 原 double-edge.json 顶层单 object 29 帧（声帧 0 / 14，尾 40，2.116s）；共享只读 PRAS- Strike，不新增播放器。
    "take_down": "take-down.json",
    "double_edge": "double-edge.json",
    # 只按传入 move_id 播各自原动画，不新增播放器。
    "power_gem": "power-gem.json",
    "aqua_jet": "aqua-jet.json",
    "water_gun": "water-gun.json",
    "wing_attack": "wing-attack.json",
    "shadow_punch": "shadow-punch.json",
    "slash": "slash.json",
    "ember": "ember.json",
    "lick": "lick.json",
    "buzzy_buzz": "buzzy-buzz.json",
    "sizzly_slide": "sizzly-slide.json",
    "psybeam": "psybeam.json",
    "cross_poison": "cross-poison.json",
    "psychic": "psychic.json",
    "flame_charge": "flame-charge.json",
    "steel_wing": "steel-wing.json",
    "close_combat": "close-combat.json",
    "snarl": "snarl.json",
    "bouncy_bubble": "bouncy-bubble.json",
    "absorb": "absorb.json",
    "arm_thrust": "arm-thrust.json",
    "wild_charge": "wild-charge.json",
    "charm": "charm.json",
    "screech": "screech.json",
    "kinesis": "kinesis.json",
    "sweet_kiss": "sweet-kiss.json",
    "hone_claws": "hone-claws.json",
    "agility": "agility.json",
    "dragon_dance": "dragon-dance.json",
    # 2026-10-16 第三批 A 档 10 招
    "zippy_zap": "zippy-zap.json",
    "splash": "splash.json",
    "psywave": "psywave.json",
    "power_trip": "power-trip.json",
    "stored_power": "stored-power.json",
    "flail": "flail.json",
    "tri_attack": "tri-attack.json",
    "freezy_frost": "freezy-frost.json",
    "focus_energy": "focus-energy.json",
    "odor_sleuth": "odor-sleuth.json",
    "disable": "disable.json",
    "counter": "counter.json",
    "teleport": "teleport.json",
    "assurance": "assurance.json",
    "payback": "payback.json",
    "sucker_punch": "sucker-punch.json",
    "frustration": "frustration.json",
    "return": "return.json",
    "covet": "covet.json",
    "heal_block": "heal-block.json",
    # 2026-10-17 技能批次 b1（31 招，原动画 / 图集 / 声音原字节入库）
    "astonish": "astonish.json",
    "mud_slap": "mud-slap.json",
    "poison_sting": "poison-sting.json",
    "powder_snow": "powder-snow.json",
    "growth": "growth.json",
    "withdraw": "withdraw.json",
    "headbutt": "headbutt.json",
    "leafage": "leafage.json",
    "ancient_power": "ancient-power.json",
    "rock_smash": "rock-smash.json",
    "constrict": "constrict.json",
    "rock_throw": "rock-throw.json",
    "metal_claw": "metal-claw.json",
    "dragon_breath": "dragon-breath.json",
    "vise_grip": "vise-grip.json",
    "noble_roar": "noble-roar.json",
    "fairy_wind": "fairy-wind.json",
    "shadow_claw": "shadow-claw.json",
    "thunder_fang": "thunder-fang.json",
    "twister": "twister.json",
    "thunder_wave": "thunder-wave.json",
    "confuse_ray": "confuse-ray.json",
    "nuzzle": "nuzzle.json",
    "crunch": "crunch.json",
    "rapid_spin": "rapid-spin.json",
    "bubble": "bubble.json",
    "vine_whip": "vine-whip.json",
    "play_nice": "play-nice.json",
    "smack_down": "smack-down.json",
    "pursuit": "pursuit.json",
    "night_shade": "night-shade.json",
    # 2026-10-17 技能批次 b2（64 招，原动画 / 图集 / 声音原字节入库）
    "hydro_pump": "hydro-pump.json",
    "slam": "slam.json",
    "earthquake": "earthquake.json",
    "stone_edge": "stone-edge.json",
    "aerial_ace": "aerial-ace.json",
    "aqua_tail": "aqua-tail.json",
    "swift": "swift.json",
    "dragon_pulse": "dragon-pulse.json",
    "hyper_voice": "hyper-voice.json",
    "hex": "hex.json",
    "disarming_voice": "disarming-voice.json",
    "brine": "brine.json",
    "drill_peck": "drill-peck.json",
    "x_scissor": "x-scissor.json",
    "pluck": "pluck.json",
    "razor_leaf": "razor-leaf.json",
    "night_slash": "night-slash.json",
    "water_pulse": "water-pulse.json",
    "discharge": "discharge.json",
    "rock_slide": "rock-slide.json",
    "air_slash": "air-slash.json",
    "zen_headbutt": "zen-headbutt.json",
    "body_slam": "body-slam.json",
    "flamethrower": "flamethrower.json",
    "stomp": "stomp.json",
    "shadow_ball": "shadow-ball.json",
    "spark": "spark.json",
    "bulldoze": "bulldoze.json",
    "bubble_beam": "bubble-beam.json",
    "blizzard": "blizzard.json",
    "iron_head": "iron-head.json",
    "moonblast": "moonblast.json",
    "earth_power": "earth-power.json",
    "icy_wind": "icy-wind.json",
    "play_rough": "play-rough.json",
    "fire_fang": "fire-fang.json",
    "bug_buzz": "bug-buzz.json",
    "mud_shot": "mud-shot.json",
    "ice_fang": "ice-fang.json",
    "flash_cannon": "flash-cannon.json",
    "thunderbolt": "thunderbolt.json",
    "ice_beam": "ice-beam.json",
    "flame_wheel": "flame-wheel.json",
    "sludge_bomb": "sludge-bomb.json",
    "superpower": "superpower.json",
    "giga_drain": "giga-drain.json",
    "mega_drain": "mega-drain.json",
    "brave_bird": "brave-bird.json",
    "fury_attack": "fury-attack.json",
    "fury_swipes": "fury-swipes.json",
    "double_kick": "double-kick.json",
    "scary_face": "scary-face.json",
    "iron_defense": "iron-defense.json",
    "swords_dance": "swords-dance.json",
    "nasty_plot": "nasty-plot.json",
    "amnesia": "amnesia.json",
    "swagger": "swagger.json",
    "baby_doll_eyes": "baby-doll-eyes.json",
    "metal_sound": "metal-sound.json",
    "calm_mind": "calm-mind.json",
    "work_up": "work-up.json",
    "recover": "recover.json",
    "roost": "roost.json",
    "synthesis": "synthesis.json",
    # 2026-10-17 技能批次 b3（87 招，原动画 / 图集 / 声音原字节入库）
    "magical_leaf": "magical-leaf.json",
    "seed_bomb": "seed-bomb.json",
    "dragon_claw": "dragon-claw.json",
    "shadow_sneak": "shadow-sneak.json",
    "power_whip": "power-whip.json",
    "megahorn": "megahorn.json",
    "dazzling_gleam": "dazzling-gleam.json",
    "horn_attack": "horn-attack.json",
    "brick_break": "brick-break.json",
    "surf": "surf.json",
    "incinerate": "incinerate.json",
    "brutal_swing": "brutal-swing.json",
    "petal_blizzard": "petal-blizzard.json",
    "shock_wave": "shock-wave.json",
    "ice_shard": "ice-shard.json",
    "fell_stinger": "fell-stinger.json",
    "seismic_toss": "seismic-toss.json",
    "leaf_blade": "leaf-blade.json",
    "psycho_cut": "psycho-cut.json",
    "air_cutter": "air-cutter.json",
    "poison_jab": "poison-jab.json",
    "struggle_bug": "struggle-bug.json",
    "energy_ball": "energy-ball.json",
    "acid": "acid.json",
    "extrasensory": "extrasensory.json",
    "zap_cannon": "zap-cannon.json",
    "hurricane": "hurricane.json",
    "thunder": "thunder.json",
    "muddy_water": "muddy-water.json",
    "liquidation": "liquidation.json",
    "smog": "smog.json",
    "dark_pulse": "dark-pulse.json",
    "fire_blast": "fire-blast.json",
    "thunder_punch": "thunder-punch.json",
    "fire_punch": "fire-punch.json",
    "aurora_beam": "aurora-beam.json",
    "poison_fang": "poison-fang.json",
    "razor_shell": "razor-shell.json",
    "crush_claw": "crush-claw.json",
    "sludge_wave": "sludge-wave.json",
    "force_palm": "force-palm.json",
    "sludge": "sludge.json",
    "icicle_crash": "icicle-crash.json",
    "rock_tomb": "rock-tomb.json",
    "gunk_shot": "gunk-shot.json",
    "charge_beam": "charge-beam.json",
    "lava_plume": "lava-plume.json",
    "freeze_dry": "freeze-dry.json",
    "inferno": "inferno.json",
    "low_sweep": "low-sweep.json",
    "dragon_rush": "dragon-rush.json",
    "flare_blitz": "flare-blitz.json",
    "wood_hammer": "wood-hammer.json",
    "wave_crash": "wave-crash.json",
    "head_smash": "head-smash.json",
    "leaf_storm": "leaf-storm.json",
    "overheat": "overheat.json",
    "hammer_arm": "hammer-arm.json",
    "draining_kiss": "draining-kiss.json",
    "leech_life": "leech-life.json",
    "double_hit": "double-hit.json",
    "bullet_seed": "bullet-seed.json",
    "rock_blast": "rock-blast.json",
    "pin_missile": "pin-missile.json",
    "bulk_up": "bulk-up.json",
    "rock_polish": "rock-polish.json",
    "acid_armor": "acid-armor.json",
    "cosmic_power": "cosmic-power.json",
    "cotton_guard": "cotton-guard.json",
    "autotomize": "autotomize.json",
    "quiver_dance": "quiver-dance.json",
    "coil": "coil.json",
    "shell_smash": "shell-smash.json",
    "howl": "howl.json",
    "smokescreen": "smokescreen.json",
    "fake_tears": "fake-tears.json",
    "feather_dance": "feather-dance.json",
    "tickle": "tickle.json",
    "cotton_spore": "cotton-spore.json",
    "flatter": "flatter.json",
    "teeter_dance": "teeter-dance.json",
    "will_o_wisp": "will-o-wisp.json",
    "poison_gas": "poison-gas.json",
    "leech_seed": "leech-seed.json",
    "slack_off": "slack-off.json",
    "moonlight": "moonlight.json",
    "life_dew": "life-dew.json",
    # 2026-10-17 技能批次 b4（守住 / 看穿 / 挺住 / 连斩）
    "protect": "protect.json",
    "detect": "detect.json",
    "endure": "endure.json",
    "fury_cutter": "fury-cutter.json",
    # 2026-10-17 技能批次 b5（睡眠类 10 招）
    "hypnosis": "hypnosis.json",
    "sing": "sing.json",
    "lovely_kiss": "lovely-kiss.json",
    "grass_whistle": "grass-whistle.json",
    "spore": "spore.json",
    "dark_void": "dark-void.json",
    "relic_song": "relic-song.json",
    "yawn": "yawn.json",
    "dream_eater": "dream-eater.json",
    "wake_up_slap": "wake-up-slap.json",
    # 2026-10-17 技能批次 b6（缠绕类 10 招）
    "wrap": "wrap.json",
    "bind": "bind.json",
    "fire_spin": "fire-spin.json",
    "clamp": "clamp.json",
    "whirlpool": "whirlpool.json",
    "sand_tomb": "sand-tomb.json",
    "magma_storm": "magma-storm.json",
    "infestation": "infestation.json",
    "snap_trap": "snap-trap.json",
    "thunder_cage": "thunder-cage.json",
    # 2026-10-17 技能批次 b7（自动推断 144 招）
    "acid_spray": "acid-spray.json",
    "dynamic_punch": "dynamic-punch.json",
    "iron_tail": "iron-tail.json",
    "ice_punch": "ice-punch.json",
    "aura_sphere": "aura-sphere.json",
    "lunge": "lunge.json",
    "extreme_speed": "extreme-speed.json",
    "poison_tail": "poison-tail.json",
    "strength": "strength.json",
    "cross_chop": "cross-chop.json",
    "dual_chop": "dual-chop.json",
    "high_horsepower": "high-horsepower.json",
    "tearful_look": "tearful-look.json",
    "glare": "glare.json",
    "crabhammer": "crabhammer.json",
    "boomburst": "boomburst.json",
    "breaking_swipe": "breaking-swipe.json",
    "mega_kick": "mega-kick.json",
    "vital_throw": "vital-throw.json",
    "drill_run": "drill-run.json",
    "horn_leech": "horn-leech.json",
    "shift_gear": "shift-gear.json",
    "mystical_fire": "mystical-fire.json",
    "mega_punch": "mega-punch.json",
    "hyper_fang": "hyper-fang.json",
    "mach_punch": "mach-punch.json",
    "meteor_mash": "meteor-mash.json",
    "drain_punch": "drain-punch.json",
    "feint_attack": "feint-attack.json",
    "bone_rush": "bone-rush.json",
    "icicle_spear": "icicle-spear.json",
    "bullet_punch": "bullet-punch.json",
    "frost_breath": "frost-breath.json",
    "tail_slap": "tail-slap.json",
    "eerie_impulse": "eerie-impulse.json",
    "branch_poke": "branch-poke.json",
    "skitter_smack": "skitter-smack.json",
    "dual_wingbeat": "dual-wingbeat.json",
    "aqua_cutter": "aqua-cutter.json",
    "submission": "submission.json",
    "vacuum_wave": "vacuum-wave.json",
    "ominous_wind": "ominous-wind.json",
    "parabolic_charge": "parabolic-charge.json",
    "confide": "confide.json",
    "fire_lash": "fire-lash.json",
    "headlong_rush": "headlong-rush.json",
    "barrier": "barrier.json",
    "waterfall": "waterfall.json",
    "barrage": "barrage.json",
    "dizzy_punch": "dizzy-punch.json",
    "bonemerang": "bonemerang.json",
    "blaze_kick": "blaze-kick.json",
    "electroweb": "electroweb.json",
    "leaf_tornado": "leaf-tornado.json",
    "night_daze": "night-daze.json",
    "gear_grind": "gear-grind.json",
    "mystical_power": "mystical-power.json",
    "karate_chop": "karate-chop.json",
    "comet_punch": "comet-punch.json",
    "cut": "cut.json",
    "rolling_kick": "rolling-kick.json",
    "twineedle": "twineedle.json",
    "bone_club": "bone-club.json",
    "soft_boiled": "soft-boiled.json",
    "flash": "flash.json",
    "octazooka": "octazooka.json",
    "milk_drink": "milk-drink.json",
    "tail_glow": "tail-glow.json",
    "needle_arm": "needle-arm.json",
    "signal_beam": "signal-beam.json",
    "sky_uppercut": "sky-uppercut.json",
    "mirror_shot": "mirror-shot.json",
    "storm_throw": "storm-throw.json",
    "fiery_dance": "fiery-dance.json",
    "power_up_punch": "power-up-punch.json",
    "toxic_thread": "toxic-thread.json",
    "smart_strike": "smart-strike.json",
    "dragon_hammer": "dragon-hammer.json",
    "zing_zap": "zing-zap.json",
    "spirit_break": "spirit-break.json",
    "false_surrender": "false-surrender.json",
    "psyshield_bash": "psyshield-bash.json",
    "bitter_malice": "bitter-malice.json",
    "shelter": "shelter.json",
    "spin_out": "spin-out.json",
    "hyper_drill": "hyper-drill.json",
    "twin_beam": "twin-beam.json",
    "spike_cannon": "spike-cannon.json",
    "aeroblast": "aeroblast.json",
    "luster_purge": "luster-purge.json",
    "mist_ball": "mist-ball.json",
    "silver_wind": "silver-wind.json",
    "psycho_boost": "psycho-boost.json",
    "focus_blast": "focus-blast.json",
    "rock_climb": "rock-climb.json",
    "chatter": "chatter.json",
    "attack_order": "attack-order.json",
    "defend_order": "defend-order.json",
    "heal_order": "heal-order.json",
    "spacial_rend": "spacial-rend.json",
    "seed_flare": "seed-flare.json",
    "head_charge": "head-charge.json",
    "searing_shot": "searing-shot.json",
    "glaciate": "glaciate.json",
    "bolt_strike": "bolt-strike.json",
    "blue_flare": "blue-flare.json",
    "v_create": "v-create.json",
    "diamond_storm": "diamond-storm.json",
    "hyperspace_hole": "hyperspace-hole.json",
    "oblivion_wing": "oblivion-wing.json",
    "lands_wrath": "lands-wrath.json",
    "light_of_ruin": "light-of-ruin.json",
    "origin_pulse": "origin-pulse.json",
    "precipice_blades": "precipice-blades.json",
    "dragon_ascent": "dragon-ascent.json",
    "ice_hammer": "ice-hammer.json",
    "trop_kick": "trop-kick.json",
    "fleur_cannon": "fleur-cannon.json",
    "shadow_bone": "shadow-bone.json",
    "accelerock": "accelerock.json",
    "decorate": "decorate.json",
    "drum_beating": "drum-beating.json",
    "overdrive": "overdrive.json",
    "apple_acid": "apple-acid.json",
    "strange_steam": "strange-steam.json",
    "wicked_blow": "wicked-blow.json",
    "freezing_glare": "freezing-glare.json",
    "fiery_wrath": "fiery-wrath.json",
    "thunderous_kick": "thunderous-kick.json",
    "springtide_storm": "springtide-storm.json",
    "mountain_gale": "mountain-gale.json",
    "victory_dance": "victory-dance.json",
    "esper_wing": "esper-wing.json",
    "lumina_crash": "lumina-crash.json",
    "jet_punch": "jet-punch.json",
    "spicy_extract": "spicy-extract.json",
    "kowtow_cleave": "kowtow-cleave.json",
    "flower_trick": "flower-trick.json",
    "torch_song": "torch-song.json",
    "aqua_step": "aqua-step.json",
    "armor_cannon": "armor-cannon.json",
    "bitter_blade": "bitter-blade.json",
    "mighty_cleave": "mighty-cleave.json",
    "tachyon_cutter": "tachyon-cutter.json",
    # 2026-10-17 技能批次 b8（天气 / 场地 13 招）
    "rain_dance": "rain-dance.json",
    "sunny_day": "sunny-day.json",
    "sandstorm": "sandstorm.json",
    "hail": "hail.json",
    "snowscape": "hail.json",   # 原仓库没有雪景动画，借冰雹的
    "electric_terrain": "electric-terrain.json",
    "grassy_terrain": "grassy-terrain.json",
    "misty_terrain": "misty-terrain.json",
    "psychic_terrain": "psychic-terrain.json",
    "morning_sun": "morning-sun.json",
    "solar_beam": "solar-beam.json",
    "solar_blade": "solar-blade.json",
    "weather_ball": "weather-ball.json",
    # 2026-10-17 技能批次 b9（蓄力招 12 招 + 各自的蓄力动画）
    "dig": "dig.json",
    "dig_charging": "dig-charging.json",
    "fly": "fly.json",
    "fly_charging": "fly-charging.json",
    "dive": "dive.json",
    "dive_charging": "dive-charging.json",
    "bounce": "bounce.json",
    "bounce_charging": "bounce-charging.json",
    "shadow_force": "shadow-force.json",
    "shadow_force_charging": "shadow-force-charging.json",
    "phantom_force": "phantom-force.json",
    "phantom_force_charging": "phantom-force-charging.json",
    "sky_attack": "sky-attack.json",
    "sky_attack_charging": "sky-attack-charging.json",
    "razor_wind": "razor-wind.json",
    "razor_wind_charging": "razor-wind-charging.json",
    "skull_bash": "skull-bash.json",
    "skull_bash_charging": "skull-bash-charging.json",
    "freeze_shock": "freeze-shock.json",
    "freeze_shock_charging": "freeze-shock-charging.json",
    "ice_burn": "ice-burn.json",
    "ice_burn_charging": "ice-burn-charging.json",
    "meteor_beam": "meteor-beam.json",
    "meteor_beam_charging": "meteor-beam-charging.json",
    # 2026-10-17 技能批次 b10（111 招：屏障 / 护盾 / 反击 / 反冲 / 延迟 / 狂暴 / 自爆 / 威力规则 / 神兽专属 / 状态）
    "reflect": "reflect.json",
    "light_screen": "light-screen.json",
    "aurora_veil": "aurora-veil.json",
    "quick_guard": "quick-guard.json",
    "wide_guard": "wide-guard.json",
    "crafty_shield": "crafty-shield.json",
    "mat_block": "mat-block.json",
    "spiky_shield": "spiky-shield.json",
    "kings_shield": "kings-shield.json",
    "baneful_bunker": "baneful-bunker.json",
    "burning_bulwark": "burning-bulwark.json",
    "obstruct": "obstruct.json",
    "silk_trap": "silk-trap.json",
    "mirror_coat": "mirror-coat.json",
    "metal_burst": "metal-burst.json",
    "comeuppance": "comeuppance.json",
    "hyper_beam": "hyper-beam.json",
    "giga_impact": "giga-impact.json",
    "rock_wrecker": "rock-wrecker.json",
    "roar_of_time": "roar-of-time.json",
    "prismatic_laser": "prismatic-laser.json",
    "meteor_assault": "meteor-assault.json",
    "blast_burn": "blast-burn.json",
    "hydro_cannon": "hydro-cannon.json",
    "frenzy_plant": "frenzy-plant.json",
    "eternabeam": "eternabeam.json",
    "future_sight": "future-sight.json",
    "doom_desire": "doom-desire.json",
    "focus_punch": "focus-punch.json",
    "geomancy": "geomancy.json",
    "thrash": "thrash.json",
    "outrage": "outrage.json",
    "petal_dance": "petal-dance.json",
    "explosion": "explosion.json",
    "self_destruct": "self-destruct.json",
    "mind_blown": "mind-blown.json",
    "misty_explosion": "misty-explosion.json",
    "memento": "memento.json",
    "eruption": "eruption.json",
    "water_spout": "water-spout.json",
    "dragon_energy": "dragon-energy.json",
    "wring_out": "wring-out.json",
    "crush_grip": "crush-grip.json",
    "low_kick": "low-kick.json",
    "grass_knot": "grass-knot.json",
    "heavy_slam": "heavy-slam.json",
    "heat_crash": "heat-crash.json",
    "gyro_ball": "gyro-ball.json",
    "electro_ball": "electro-ball.json",
    "reversal": "reversal.json",
    "venoshock": "venoshock.json",
    "facade": "facade.json",
    "revenge": "revenge.json",
    "avalanche": "avalanche.json",
    "echoed_voice": "echoed-voice.json",
    "fusion_flare": "fusion-flare.json",
    "fusion_bolt": "fusion-bolt.json",
    "collision_course": "collision-course.json",
    "electro_drift": "electro-drift.json",
    "super_fang": "super-fang.json",
    "natures_madness": "natures-madness.json",
    "ruination": "ruination.json",
    "endeavor": "endeavor.json",
    "false_swipe": "false-swipe.json",
    "fissure": "fissure.json",
    "guillotine": "guillotine.json",
    "horn_drill": "horn-drill.json",
    "psyshock": "psyshock.json",
    "psystrike": "psystrike.json",
    "secret_sword": "secret-sword.json",
    "foul_play": "foul-play.json",
    "body_press": "body-press.json",
    "acrobatics": "acrobatics.json",
    "knock_off": "knock-off.json",
    "uproar": "uproar.json",
    "round": "round.json",
    "sacred_fire": "sacred-fire.json",
    "steam_eruption": "steam-eruption.json",
    "malignant_chain": "malignant-chain.json",
    "bleakwind_storm": "bleakwind-storm.json",
    "wildbolt_storm": "wildbolt-storm.json",
    "sandsear_storm": "sandsear-storm.json",
    "thousand_arrows": "thousand-arrows.json",
    "thousand_waves": "thousand-waves.json",
    "core_enforcer": "core-enforcer.json",
    "judgment": "judgment.json",
    "techno_blast": "techno-blast.json",
    "photon_geyser": "photon-geyser.json",
    "spectral_thief": "spectral-thief.json",
    "plasma_fists": "plasma-fists.json",
    "dynamax_cannon": "dynamax-cannon.json",
    "ivy_cudgel": "ivy-cudgel.json",
    "double_iron_bash": "double-iron-bash.json",
    "lunar_blessing": "lunar-blessing.json",
    "jungle_healing": "jungle-healing.json",
    "take_heart": "take-heart.json",
    "wish": "wish.json",
    "rest": "rest.json",
    "belly_drum": "belly-drum.json",
    "aqua_ring": "aqua-ring.json",
    "ingrain": "ingrain.json",
    "magnet_rise": "magnet-rise.json",
    "lock_on": "lock-on.json",
    "mind_reader": "mind-reader.json",
    "haze": "haze.json",
    "clear_smog": "clear-smog.json",
    "tailwind": "tailwind.json",
    "roar": "roar.json",
    "whirlwind": "whirlwind.json",
    "dragon_tail": "dragon-tail.json",
    "circle_throw": "circle-throw.json",
    "future_sight_charging": "future-sight-charging.json",
    "doom_desire_charging": "doom-desire-charging.json",
    "geomancy_charging": "geomancy-charging.json",
    # 2026-10-16 第四批 B 档 11 招
    "toxic": "toxic.json",
    "charge": "charge.json",
    "rollout": "rollout.json",
    "baddy_bad": "baddy-bad.json",
    "glitzy_glow": "glitzy-glow.json",
    "sappy_seed": "sappy-seed.json",
    "sparkly_swirl": "sparkly-swirl.json",
    "bite": "bite.json",
    "fake_out": "fake-out.json",
    "metronome": "metronome.json",
    "copycat": "copycat.json",
    "acupressure": "acupressure.json",
    "anchor_shot": "anchor-shot.json",
    "aromatherapy": "aromatherapy.json",
    "aura_wheel": "aura-wheel.json",
    "axe_kick": "axe-kick.json",
    "barb_barrage": "barb-barrage.json",
    "beak_blast": "beak-blast.json",
    "belch": "belch.json",
    "bolt_beak": "bolt-beak.json",
    "burn_up": "burn-up.json",
    "captivate": "captivate.json",
    "chilly_reception": "chilly-reception.json",
    "chip_away": "chip-away.json",
    "clanging_scales": "clanging-scales.json",
    "clangorous_soul": "clangorous-soul.json",
    "curse": "curse.json",
    "darkest_lariat": "darkest-lariat.json",
    "defog": "defog.json",
    "destiny_bond": "destiny-bond.json",
    "dire_claw": "dire-claw.json",
    "doodle": "doodle.json",
    "double_shock": "double-shock.json",
    "double_team": "double-team.json",
    "dragon_darts": "dragon-darts.json",
    "entrainment": "entrainment.json",
    "expanding_force": "expanding-force.json",
    "feint": "feint.json",
    "fickle_beam": "fickle-beam.json",
    "fillet_away": "fillet-away.json",
    "first_impression": "first-impression.json",
    "fishious_rend": "fishious-rend.json",
    "flip_turn": "flip-turn.json",
    "flower_shield": "flower-shield.json",
    "flying_press": "flying-press.json",
    "foresight": "foresight.json",
    "forests_curse": "forests-curse.json",
    "gastro_acid": "gastro-acid.json",
    "gear_up": "gear-up.json",
    "gigaton_hammer": "gigaton-hammer.json",
    "glaive_rush": "glaive-rush.json",
    "grav_apple": "grav-apple.json",
    "gravity": "gravity.json",
    "guard_swap": "guard-swap.json",
    "heal_bell": "heal-bell.json",
    "heat_wave": "heat-wave.json",
    "hidden_power": "hidden-power.json",
    "high_jump_kick": "high-jump-kick.json",
    "hydro_steam": "hydro-steam.json",
    "ice_ball": "ice-ball.json",
    "ice_spinner": "ice-spinner.json",
    "jaw_lock": "jaw-lock.json",
    "jump_kick": "jump-kick.json",
    "laser_focus": "laser-focus.json",
    "last_resort": "last-resort.json",
    "last_respects": "last-respects.json",
    "lucky_chant": "lucky-chant.json",
    "magic_powder": "magic-powder.json",
    "magnetic_flux": "magnetic-flux.json",
    "make_it_rain": "make-it-rain.json",
    "matcha_gotcha": "matcha-gotcha.json",
    "minimize": "minimize.json",
    "mist": "mist.json",
    "moongeist_beam": "moongeist-beam.json",
    "mortal_spin": "mortal-spin.json",
    "mud_sport": "mud-sport.json",
    "multi_attack": "multi-attack.json",
    "nightmare": "nightmare.json",
    "no_retreat": "no-retreat.json",
    "octolock": "octolock.json",
    "order_up": "order-up.json",
    "pain_split": "pain-split.json",
    "parting_shot": "parting-shot.json",
    "pay_day": "pay-day.json",
    "perish_song": "perish-song.json",
    "pika_papow": "pika-papow.json",
    "pollen_puff": "pollen-puff.json",
    "population_bomb": "population-bomb.json",
    "power_swap": "power-swap.json",
    "psyblade": "psyblade.json",
    "psych_up": "psych-up.json",
    "psychic_fangs": "psychic-fangs.json",
    "psycho_shift": "psycho-shift.json",
    "purify": "purify.json",
    "pyro_ball": "pyro-ball.json",
    "rage": "rage.json",
    "rage_fist": "rage-fist.json",
    "raging_bull": "raging-bull.json",
    "raging_fury": "raging-fury.json",
    "retaliate": "retaliate.json",
    "revelation_dance": "revelation-dance.json",
    "rising_voltage": "rising-voltage.json",
    "role_play": "role-play.json",
    "rototiller": "rototiller.json",
    "sacred_sword": "sacred-sword.json",
    "safeguard": "safeguard.json",
    "salt_cure": "salt-cure.json",
    "scald": "scald.json",
    "scale_shot": "scale-shot.json",
    "shell_trap": "shell-trap.json",
    "shore_up": "shore-up.json",
    "simple_beam": "simple-beam.json",
    "skill_swap": "skill-swap.json",
    "snipe_shot": "snipe-shot.json",
    "snore": "snore.json",
    "soak": "soak.json",
    "sparkling_aria": "sparkling-aria.json",
    "spikes": "spikes.json",
    "spirit_shackle": "spirit-shackle.json",
    "spit_up": "spit-up.json",
    "stealth_rock": "stealth-rock.json",
    "steel_roller": "steel-roller.json",
    "sticky_web": "sticky-web.json",
    "stockpile": "stockpile.json",
    "stomping_tantrum": "stomping-tantrum.json",
    "stone_axe": "stone-axe.json",
    "strength_sap": "strength-sap.json",
    "stuff_cheeks": "stuff-cheeks.json",
    "sunsteel_strike": "sunsteel-strike.json",
    "swallow": "swallow.json",
    "sweet_scent": "sweet-scent.json",
    "synchronoise": "synchronoise.json",
    "syrup_bomb": "syrup-bomb.json",
    "tar_shot": "tar-shot.json",
    "teatime": "teatime.json",
    "terrain_pulse": "terrain-pulse.json",
    "thief": "thief.json",
    "throat_chop": "throat-chop.json",
    "thunderclap": "thunderclap.json",
    "tidy_up": "tidy-up.json",
    "topsy_turvy": "topsy-turvy.json",
    "toxic_spikes": "toxic-spikes.json",
    "trick_or_treat": "trick-or-treat.json",
    "triple_dive": "triple-dive.json",
    "triple_kick": "triple-kick.json",
    "u_turn": "u-turn.json",
    "veevee_volley": "veevee-volley.json",
    "venom_drench": "venom-drench.json",
    "volt_switch": "volt-switch.json",
    "water_shuriken": "water-shuriken.json",
    "water_sport": "water-sport.json",
    "worry_seed": "worry-seed.json",
}

# 原 AnimTimedSoundEvent 的空 resourceName 音效 = 出招方物种原 cry（源 `n.user.cry(r)`）。
# `% 2000`（少数地区形态例外表不走，本作 34 个有限 Growl 物种里没有那些例外），其余用自身 ID。
# 本作只接原 34 个有限 Growl 学习物种 form0 → 33 个独立 cry 文件；**2026 地区雷丘按源取 26**
# （不是 10、不套绿毛虫）。未列出的物种明确拒绝 / 报告，不做通用音效或绿毛虫回退。
const CRY_DIR := "res://assets/pokemon/cries/"
const CRY_KEYS := {
    52: "52", 53: "53", 263: "263", 264: "264", 399: "399", 400: "400",
    84: "84", 85: "85", 396: "396", 397: "397", 398: "398",
    519: "519", 520: "520", 521: "521", 921: "921", 922: "922", 923: "923",
    21: "21", 22: "22", 25: "25", 661: "661", 662: "662", 663: "663",
    133: "133", 2026: "26", 26: "26", 700: "700", 196: "196", 197: "197",
    134: "134", 135: "135", 136: "136", 470: "470", 471: "471",
}

# ================= 近战拳风 =================
# 接触类招式（撞击 / 抓 / 虫咬 / 啄 / 斩击…）原动画里出招方不动、特效直接画在敌人身上；这里敌人可能在几米外，
# 看起来像隔空打人。目标有点距离时先放一团拳风从出招方飞到敌人身上（主项目的 white-impact 拳风，图的“上”朝着飞行方向，
# 亮的一团在前、气流拖在后面），飞到那一刻才放招式原本的受击动画（用户 2026-10-18：“有拳风的从人发射出去到怪物的”，
# 取代之前的蓝色冲刺虚影 / 天降拳风 / 剑气）。原动画本来就让出招方位移的招走上面的“位移虚影”，不重复。
const CONTACT_PATH := "res://data/rogue_upstream/contact_moves.json"
const GameMoves := preload("res://data/pokemon_moves.gd")
const FIST_ENABLED := false     # 接触类招式前的拳风：2026-10-19 用户说不好看，关掉
const FIST_MIN_DIST := 1.6      # 目标近于这个距离就不放拳风（贴身了）
const FIST_FLY := 0.2          # 拳风从出招方飞到敌人要多久，受击动画等它
const FIST_TOTAL := 0.5        # 拳风整段 8 帧播多久（前 4 帧在飞行途中，后 4 帧到达后散开）
const FIST_PIXEL := 0.0085     # 图集一个像素对应多少米（亮的一团到气流尾约 1.7 米）
const FIST_SHEET := "res://assets/fx/fist_shot/sheet.png"
const FIST_SHADER := preload("res://fx/fist_shot.gdshader")
static var _contact_loaded := false
static var _noncontact: Dictionary = {}
static var _contact_other: Dictionary = {}
var _fists: Array = []


static func _load_contact() -> void:
    if _contact_loaded:
        return
    _contact_loaded = true
    var f := FileAccess.open(CONTACT_PATH, FileAccess.READ)
    if f == null:
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    if not (parsed is Dictionary):
        return
    for m in parsed.get("noncontact_physical", []):
        _noncontact[str(m)] = true
    for m in parsed.get("contact_other", []):
        _contact_other[str(m)] = true


# 接触类：本作招式表里是物理招且源码没标“不接触”，或源码里非物理但标了接触。
static func is_contact_move(move_id: String) -> bool:
    _load_contact()
    if _contact_other.has(move_id):
        return true
    if not GameMoves.MOVES.has(move_id):
        return false
    return str(GameMoves.MOVES[move_id].get("category", "")) == "物理" and not _noncontact.has(move_id)


# 原动画里出招方自己有明显位移（走位移虚影的那一类）。
static func _anim_moves_body(anim: Dictionary) -> bool:
    for frame in anim.get("frames", []):
        for layer in frame:
            if int(layer.get("target", 2)) != 0:
                continue
            var focus := int(layer.get("focus", 1))
            var x := float(layer.get("x", 0.0))
            var y := float(layer.get("y", 0.0))
            if (focus == 3 and absf(x) > 0.0) or (focus == 2 and Vector2(x, y).length() > 20.0):
                return true
    return false


# 这次近战要不要改成放拳风：接触类、原动画出招方不动、目标离出招方 FIST_MIN_DIST 以上。
func _wants_fist(move_id: String, anim: Dictionary, user: Node3D, target: Node3D) -> bool:
    if not FIST_ENABLED:
        return false   # 用户 2026-10-19：“拳风不行，要去掉”——代码留着，常量改 true 就恢复
    if user == target or not is_contact_move(move_id) or _anim_moves_body(anim):
        return false
    var d := _center(target) - _center(user)
    d.y = 0.0
    return d.length() >= FIST_MIN_DIST


# 放一团拳风从出招方飞到敌人，返回飞到要等的秒数。
func _shoot_fist(user: Node3D, target: Node3D) -> float:
    var tex := load(FIST_SHEET) as Texture2D
    if tex == null:
        return 0.0
    var from := _center(user)
    var to := _center(target)
    var d := to - from
    d.y = 0.0
    var dir := d.normalized()
    var basis := _view_basis()
    # 屏幕平面里的飞行方向（y 向上），让图的“上”（亮的一团）朝着它。
    var sx := d.dot(basis.x)
    var sy := d.dot(basis.y)
    var roll := atan2(-sx, sy) if Vector2(sx, sy).length() > 0.001 else 0.0
    var mesh := QuadMesh.new()
    mesh.size = Vector2(330.0, 360.0) * FIST_PIXEL
    mesh.center_offset = Vector3(30.0, -100.0, 0.0) * FIST_PIXEL   # 让亮的一团（格内 (135,80)）落在节点原点上
    var mat := ShaderMaterial.new()
    mat.shader = FIST_SHADER
    mat.set_shader_parameter("tex", tex)
    mat.set_shader_parameter("roll", roll)
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = mat
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.extra_cull_margin = 4.0
    add_child(node)
    _fists.append({"node": node, "mat": mat, "from": from + dir * 0.4, "to": to - dir * 0.5, "t": 0.0})
    return FIST_FLY


func _tick_fists(delta: float) -> void:
    var i := 0
    while i < _fists.size():
        var f: Dictionary = _fists[i]
        var node = f["node"]
        if node == null or not is_instance_valid(node):
            _fists.remove_at(i)
            continue
        f["t"] = float(f["t"]) + delta
        var t := float(f["t"])
        if t >= FIST_TOTAL:
            node.queue_free()
            _fists.remove_at(i)
            continue
        var k := minf(t / FIST_FLY, 0.999)
        node.global_position = (f["from"] as Vector3).lerp(f["to"] as Vector3, k)
        var frame := floorf(k * 4.0) if t < FIST_FLY else 4.0 + floorf((t - FIST_FLY) / (FIST_TOTAL - FIST_FLY) * 4.0)
        (f["mat"] as ShaderMaterial).set_shader_parameter("frame", minf(frame, 7.0))
        i += 1


# 六种异常状态的「通用发动」动画（原 CommonBattleAnim）。**独立于可上场招式 MOVES**：
# data/pokemon_moves.gd 的 MOVES / IMPLEMENTED 是 20 招（含抓获选角前置四招 + 叫声 / 啄 + 泼沙 + 电光一闪 + 变圆 + 电击），本表不进学习表、不算技能。
# 原 JSON 文件名由只读源 `battle-anims\common-*.json` 而来，共用一张 `PRAS- Status.png`（480x576，96 格切图）。
const COMMON_ANIMS := {
    "poison": "common-poison.json",
    "paralysis": "common-paralysis.json",
    "sleep": "common-sleep.json",
    "frozen": "common-frozen.json",
    "burn": "common-burn.json",
    "confusion": "common-confusion.json",
}

# `ta.POISON+(effect-1)` 取（effect POISON=1→2010、PARALYSIS=3→2012、SLEEP=4→2013、
# FREEZE=5→2014、BURN=6→2015），混乱单独走 `ta.CONFUSION=2016`。
# 这张表是唯一来源，禁止对 effect 做算术：冰冻 effect=5 必须是 2014/FREEZE，不是 2011/TOXIC。
const COMMON_ENUM := {
    "poison": 2010,
    "paralysis": 2012,
    "sleep": 2013,
    "frozen": 2014,
    "burn": 2015,
    "confusion": 2016,
}

# 出招方冲向敌人 / 蓝色虚影（原动画里出招方会动的招：撞击 / 猛撞 / 电光一闪…）。2026-10-19 用户说去掉，默认关；测试里要测展示层归属时打开。
var dash_enabled := false
var cam: Camera3D
var _data := {}
var _common_data := {}
var _sheets := {}
var _quads := {}
var _plays: Array = []
var _audio: Array = []
# 命名声音事件的真实片长（帧数单位）缓存：原 AnimTimedSoundEvent.execute 的返回值只跟资源长度有关。
var _sound_units := {}
var _next_id := 0


func setup(camera: Camera3D) -> void:
    cam = camera


# 招式动画按需读取（567 招 / 数百 MB 级 JSON，一次全读要卡十几秒），读过的在进程内缓存、各实例共用。
# 需要整张表的检查调 preload_all()。
static var _file_cache := {}


func _ensure(id: String) -> void:
    if _data.has(id) or not MOVES.has(id):
        return
    var file: String = MOVES[id]
    if not _file_cache.has(file):
        _file_cache[file] = _read_anim(file)
    _data[id] = _file_cache[file]


func preload_all() -> void:
    for id in MOVES:
        _ensure(id)


# 最早登记的那批（前 EAGER_COUNT 个，含老检查直接读 _data 的 22 招）启动时读好；后来接的招按需读。
const EAGER_COUNT := 70


func _ready() -> void:
    var n := 0
    for id in MOVES:
        if n >= EAGER_COUNT:
            break
        _ensure(id)
        n += 1
    # 通用状态动画单独一份数据表：MOVES 的键集 / 计数契约不变（仍是 10 条）。
    for id in COMMON_ANIMS:
        _common_data[id] = _read_anim(COMMON_ANIMS[id])


# 播放一次招式特效。user / target 是场上的角色根节点（脚底位置）。
# sound=false 只用于同一群体释放的后续目标：只播原图层、不重复播同两声 WAV，避免叠成几十份。
# species_id = 出招方当前准确物种 ID：只用于原动画里空 resourceName 的 AnimTimedSoundEvent
# （原 `n.user.cry(r)`）。默认 0 保持旧 3/4 参调用兼容，不挂任何隐藏开关。
# effects=false：不画这条招的特效图层（target 2），声音、背景事件、出招 / 受击方身体动作照常——
# 招式特效由 fx/pack_fx.gd（新派特效包）接管时用（2026-10-19）。
func play(move_id: String, user: Node3D, target: Node3D, sound := true, species_id := 0, effects := true) -> void:
    var tint := Color.WHITE
    if PLAY_ALIAS.has(move_id):   # 整段换成别的招的原动画（念力 → 紫色超声波）
        tint = (PLAY_ALIAS[move_id] as Dictionary).get("tint", Color.WHITE)
        move_id = str((PLAY_ALIAS[move_id] as Dictionary)["as"])
    _ensure(move_id)
    if not _data.has(move_id) or user == null or target == null:
        return
    if not is_instance_valid(user) or not is_instance_valid(target):
        return
    var anim = _anim_for(move_id, user)
    if _wants_fist(move_id, anim, user, target):
        # 拳风先飞过去，飞到那一刻再放招式原本的受击动画 / 声音。
        var delay := _shoot_fist(user, target)
        get_tree().create_timer(delay).timeout.connect(func() -> void:
            if is_instance_valid(user) and is_instance_valid(target):
                _start(anim, user, target, sound, "", species_id, effects, tint))
        return
    _start(anim, user, target, sound, "", species_id, effects, tint)


# 六种异常状态的「通用发动」：原 CommonBattleAnim 是**自我施受**（源 `new yu(anim, pokemon).play`，
# 未传 targetIndex 时 target = user）。所以 user = target = 状态单位自己的根节点：玩家是 `player`，
# 每个敌人是各自的 `e.node`；不会画在攻击者身上，也不画在全局中心。
# 一个单位一次调用只播一段；单位之间各自独立（不合并图层 / 计数 / 事件）。
func play_common(common_id: String, unit: Node3D, sound := true) -> bool:
    if unit == null or not is_instance_valid(unit):
        return false
    var anim = _common_data.get(common_id)
    if not (anim is Dictionary):
        return false
    return _start(anim, unit, unit, sound, common_id)


# 招式与通用状态共用的启动：登记播放、放首帧展示层与首帧事件。
# `common` 记录这条播放来自哪个通用状态（招式播放为空串），供来源辨认与清理，不影响播放逻辑。
func _start(anim: Dictionary, user: Node3D, target: Node3D, sound: bool, common: String,
        species_id := 0, effects := true, tint := Color.WHITE) -> bool:
    if anim.is_empty():
        return false
    var frames: Array = anim["frames"]
    if frames.is_empty():
        return false
    var p := {
        "id": _next_id,
        "anim": anim,
        "common": common,
        "user": user,
        "target": target,
        "t": 0.0,
        "frame": 0,
        "sprites": [],
        "touched": [],
        "bg": [],
        # 背景状态：bg_tw 是 x / y / a 三条独立补间（同一属性只留最新一条，见 _bg_update）；
        # bg_st.px 是面板左上角的**源像素**坐标，bg_st.alpha 是当前 alpha；
        # bg_clock 是本条播放已经把背景推进到的绝对时刻（秒），与 p["t"] 同一条时间轴。
        "bg_tw": {},
        "bg_st": {"px": Vector2.ZERO, "alpha": 0.0},
        "bg_clock": 0.0,
        "dead": false,
        "novisual": not effects,   # true = 特效图层和背景由 pack_fx 接管，这里只做声音和身体动作
        "sound": sound,
        # 本条播放的出招方物种 / 空声音事件的 cry 时长（帧数单位）。空声音事件来自出招方物种，
        # 所以尾部 T 必须按这条播放自己的 cry_units 算，不能把某个物种的尾部缓存到共享 anim 上。
        "species_id": species_id,
        "cry_units": -1,
        "tint": tint   # 整段染色（乘在原图上；PLAY_ALIAS 用，普通招是白色 = 不变）
    }
    p["cry_units"] = _cry_units_for(anim, species_id)
    _next_id += 1
    # 先把本条播放登记进 _plays，再放它自己的首帧事件：首帧的 Add/Update 背景事件
    # 从一开始就归属于这一条播放（原序也是先建 BattleAnim 再跑帧事件）。
    # sound 只管声音事件（_play_event 里判断），帧 0 的**背景**事件任何情况下都要跑。
    _plays.append(p)
    _apply_frame(p, 0)
    _fire_events(p, 0)
    return true


# 原 MoveAnim.getAnim()：顶层是数组时按「出招方是不是玩家」选 0 / 1 号变体，单对象直接用。
# 本作只有玩家放新招，因此实际走 0 号；保留两变体数据与选择语义，不拼帧、不丢资料。
func _anim_for(move_id: String, user: Node3D) -> Dictionary:
    _ensure(move_id)
    var raw = _data.get(move_id)
    if raw is Dictionary:
        return raw
    if raw is Array:
        var variants: Array = raw
        if variants.is_empty():
            return {}
        var idx := 0 if _is_player_side(user) else 1
        if idx >= variants.size():
            idx = 0
        return variants[idx] if variants[idx] is Dictionary else {}
    return {}


# 出招方是不是玩家：玩家根节点下挂的是角色模型（有子节点），敌人根节点自己也挂模型。
# 这里只看「根节点有没有父级是玩家根」不可靠，因此用同一约定：main.gd 的 player 根是
# 纯 Node3D 且只挂一个模型；Enemy.node 是 caterpie 场景实例（脚本带 set_world_facing）。
func _is_player_side(user: Node3D) -> bool:
    if user == null or not is_instance_valid(user):
        return true
    return not user.has_method("set_world_facing")


# 吐丝飞弹的飞行显示：用原图集第 0 格，按行进方向的屏幕角度摆正。
# 只负责显示；位移与线段碰撞仍由 main/arts.gd 的原逻辑驱动。
func make_bolt(dir: Vector3) -> MeshInstance3D:
    var mi := _make_sprite()
    var mat := mi.material_override as StandardMaterial3D
    mat.albedo_texture = _sheet("PRAS- String Shot")
    mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
    mat.emission_enabled = false
    mat.render_priority = 1
    mi.mesh = _quad("PRAS- String Shot", 0)
    var basis := _view_basis()
    var roll := 0.0
    var sx := dir.dot(basis.x)
    var sy := dir.dot(basis.y)
    if absf(sx) > 0.0001 or absf(sy) > 0.0001:
        roll = atan2(sy, sx)
    _orient(mi, Vector3.ZERO, roll, 1.0, 1.0)
    return mi


# 敌人弹药的飞行显示（用户 2026-10-17：起风“他自身的特效就是个小龙卷风”）：
# 取该招原动画里第一个特效图层（target 2）的图集 + graphicFrame 序列，当作飞行中的弹体画。
# 只负责显示；飞行 / 命中由 main/arts.gd 驱动。没有原动画或没有特效图层返回 null，调用方退回色球。
const PROJECTILE_SCALE := 0.6   # 原图层 96px 对应 2.1 世界单位；弹体 = 0.6 × 该招图层的平均缩放（用户：弹体偏小，按原动画缩放放大）
const IMPACT_SECS := 0.35       # 命中特效播放时长
const IMPACT_SCALE := 1.0
# 没有自己飞行图层的招借用别的招的弹体画面（用户 2026-10-17：“念力就一个小圈，精神强念就是幻象光线放大”）：
# 念力 = 幻象光线的小圈（0.6 倍），精神强念 = 幻象光线放大（1.6 倍）。声音仍用自己原动画的。
# 用户 2026-10-20：念力改用超声波的画面、染成紫色（tint 乘在原图上）。玩家出招走 play() 的整段原动画（PLAY_ALIAS），
# 敌人弹药走弹体 / 命中（VISUAL_ALIAS），两边都换。
const PLAY_ALIAS := {"confusion": {"as": "supersonic", "tint": Color(1.0, 0.45, 1.0)}}
const VISUAL_ALIAS := {"confusion": {"as": "supersonic", "scale": 1.0, "tint": Color(1.0, 0.45, 1.0)}, "psychic": {"as": "psybeam", "scale": 1.6}}
# 玩家自己招式的原动画图层是否也描边（实验开关）。
var outline_effects := true
const OUTLINE_SHADER := preload("res://fx/vfx_outline.gdshader")
const OUTLINE_PX := 1.5          # 描边宽度（原像素）
const LAUNCH_SOUND_FRAMES := 12  # 发射声：原动画前 12 帧（约 0.4 秒）里的声音事件（最多 2 个）


func projectile_frames(move_id: String) -> Array:
    var raw = _anim_for(visual_id(move_id), null)
    var out: Array = []
    if not (raw is Dictionary) or raw.is_empty():
        return out
    for layers in raw["frames"]:
        for layer in layers:
            if int(layer.get("target", 2)) == 2:
                out.append(int(layer.get("graphicFrame", 0)))
                break
    return out


func add_outline(mi: MeshInstance3D) -> void:
    var base := mi.material_override as StandardMaterial3D
    for i in 8:
        var ang := float(i) * TAU / 8.0
        var copy := MeshInstance3D.new()
        copy.name = "Outline%d" % i
        copy.mesh = mi.mesh
        copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var mat := ShaderMaterial.new()
        mat.shader = OUTLINE_SHADER
        mat.render_priority = clampi(base.render_priority - 1, -128, 127)
        mat.set_shader_parameter("tex", base.albedo_texture)
        mat.set_shader_parameter("shift", Vector2(cos(ang), sin(ang)) * OUTLINE_PX * PIXEL_SIZE)
        copy.material_override = mat
        mi.add_child(copy)


# 这一帧图的边缘是否清晰：有像素的地方里，半透明像素（0.1 < α < 0.9）占比 ≤ SOFT_MAX。结果按 图集#帧 缓存。
const SOFT_MAX := 0.25
var _crisp_cache: Dictionary = {}


func _is_crisp(graphic: String, gf: int) -> bool:
    var key := "%s#%d" % [graphic, gf]
    if _crisp_cache.has(key):
        return bool(_crisp_cache[key])
    var crisp := true
    var sheet := _sheet(graphic)
    if sheet != null:
        var img := sheet.get_image()
        if img != null:
            if img.is_compressed():
                img.decompress()
            var uv := _region_uv(graphic, gf)
            var w := float(img.get_width())
            var h := float(img.get_height())
            var x0 := int(uv.position.x * w)
            var y0 := int(uv.position.y * h)
            var x1 := mini(img.get_width(), int(ceil((uv.position.x + uv.size.x) * w)))
            var y1 := mini(img.get_height(), int(ceil((uv.position.y + uv.size.y) * h)))
            var solid := 0
            var soft := 0
            for y in range(y0, y1):
                for x in range(x0, x1):
                    var a := img.get_pixel(x, y).a
                    if a > 0.9:
                        solid += 1
                    elif a > 0.1:
                        soft += 1
            var total := solid + soft
            crisp = total > 0 and float(soft) / float(total) <= SOFT_MAX
    _crisp_cache[key] = crisp
    return crisp


func _sync_outline(mi: MeshInstance3D, show := true) -> void:
    var base := mi.material_override as StandardMaterial3D
    for c in mi.get_children():
        if c is MeshInstance3D and str(c.name).begins_with("Outline"):
            c.visible = show
            c.mesh = mi.mesh
            var smat := c.material_override as ShaderMaterial
            smat.set_shader_parameter("alpha", base.albedo_color.a)
            var tex := base.albedo_texture
            if tex != null:
                var sh: Vector2 = smat.get_shader_parameter("shift")
                var local_w := CELL * PIXEL_SIZE
                smat.set_shader_parameter("uv_shift", Vector2(sh.x, -sh.y) / local_w * Vector2(CELL / float(tex.get_width()), CELL / float(tex.get_height())))


# 该招飞行图层的平均缩放（原 zoomX / 100，夹到 0.8..1.3）：起风 = 1（不变），水枪 / 火花等带 1.05..1.5 的放大。
func visual_id(move_id: String) -> String:
    return str((VISUAL_ALIAS[move_id] as Dictionary)["as"]) if VISUAL_ALIAS.has(move_id) else move_id


func visual_scale(move_id: String) -> float:
    return float((VISUAL_ALIAS[move_id] as Dictionary)["scale"]) if VISUAL_ALIAS.has(move_id) else 1.0


func visual_tint(move_id: String) -> Color:
    return (VISUAL_ALIAS[move_id] as Dictionary).get("tint", Color.WHITE) if VISUAL_ALIAS.has(move_id) else Color.WHITE


func projectile_zoom(move_id: String) -> float:
    var raw = _anim_for(visual_id(move_id), null)
    if not (raw is Dictionary) or raw.is_empty():
        return 1.0
    var sum := 0.0
    var n := 0
    for layers in raw["frames"]:
        for layer in layers:
            if int(layer.get("target", 2)) == 2:
                sum += float(layer.get("zoomX", 100.0)) / 100.0
                n += 1
                break
    return clampf(sum / float(n), 0.8, 1.3) if n > 0 else 1.0


# 命中特效用的帧：飞行图层序列的后 40%（原动画里弹体到了目标身上那一段，如火花的爆开火焰）。
func impact_frames(move_id: String) -> Array:
    var frames := projectile_frames(move_id)
    if frames.is_empty():
        return frames
    return frames.slice(int(float(frames.size()) * 0.6))


func make_impact(move_id: String) -> MeshInstance3D:
    var frames := impact_frames(move_id)
    if frames.is_empty():
        return null
    var graphic := str(_anim_for(visual_id(move_id), null)["graphic"])
    var mi := _make_sprite()
    var mat := mi.material_override as StandardMaterial3D
    mat.albedo_texture = _sheet(graphic)
    mat.render_priority = 2
    mi.mesh = _quad(graphic, int(frames[0]))
    mi.set_meta("graphic", graphic)
    mi.set_meta("frames", frames)
    mi.set_meta("scale", IMPACT_SCALE * visual_scale(move_id))
    mi.set_meta("tint", visual_tint(move_id))
    add_outline(mi)
    place_impact(mi, Vector3.ZERO, 0.0)
    return mi


# 命中特效：IMPACT_SECS 内把那段帧播一遍，最后 30% 淡出。
func place_impact(mi: MeshInstance3D, pos: Vector3, age: float) -> void:
    if mi == null or not is_instance_valid(mi):
        return
    var frames: Array = mi.get_meta("frames", [])
    var t := clampf(age / IMPACT_SECS, 0.0, 1.0)
    if not frames.is_empty():
        var fi := mini(int(t * float(frames.size())), frames.size() - 1)
        mi.mesh = _quad(str(mi.get_meta("graphic")), int(frames[fi]))
    var mat := mi.material_override as StandardMaterial3D
    var tint: Color = mi.get_meta("tint", Color.WHITE)
    mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0 if t < 0.7 else clampf((1.0 - t) / 0.3, 0.0, 1.0))
    var isc := float(mi.get_meta("scale", IMPACT_SCALE))
    _orient(mi, pos, 0.0, isc, isc)
    _sync_outline(mi)


# 发射声：原动画前几帧里的声音事件（带资源名的；空名字的是出招方叫声，敌人弹药不播）。
func play_launch_sound(move_id: String) -> void:
    var raw = _anim_for(move_id, null)
    if not (raw is Dictionary) or raw.is_empty():
        return
    var events = raw.get("frameTimedEvents", {})
    if not (events is Dictionary):
        return
    var played := 0
    for f in LAUNCH_SOUND_FRAMES + 1:
        var evs = events.get(str(f), [])
        if not (evs is Array):
            continue
        for e in evs:
            if played >= 2:
                return
            if str(e.get("eventType", "")) == "AnimTimedSoundEvent" and str(e.get("resourceName", "")) != "":
                _play_sound(e)
                played += 1


func make_projectile(move_id: String) -> MeshInstance3D:
    var frames := projectile_frames(move_id)
    if frames.is_empty():
        return null
    var graphic := str(_anim_for(visual_id(move_id), null)["graphic"])
    var mi := _make_sprite()
    var mat := mi.material_override as StandardMaterial3D
    mat.albedo_texture = _sheet(graphic)
    mat.render_priority = 1
    mi.mesh = _quad(graphic, int(frames[0]))
    mi.set_meta("graphic", graphic)
    mi.set_meta("frames", frames)
    mi.set_meta("scale", PROJECTILE_SCALE * projectile_zoom(move_id) * visual_scale(move_id))
    mat.albedo_color = visual_tint(move_id)
    add_outline(mi)
    place_projectile(mi, Vector3.ZERO, 0.0)
    return mi


# 摆位置并按飞行时间换帧（原帧长 FRAME_SECS，循环）。
func place_projectile(mi: MeshInstance3D, pos: Vector3, age: float) -> void:
    if mi == null or not is_instance_valid(mi):
        return
    var frames: Array = mi.get_meta("frames", [])
    if not frames.is_empty():
        var fi := int(age / FRAME_SECS) % frames.size()
        mi.mesh = _quad(str(mi.get_meta("graphic")), int(frames[fi]))
    var sc := float(mi.get_meta("scale", PROJECTILE_SCALE))
    _orient(mi, pos, 0.0, sc, sc)
    _sync_outline(mi)


func _process(delta: float) -> void:
    _tick_fists(delta)
    # 从旧到新推进：同一角色上多个特效叠加时，最新一次招式的展示层后写、优先。
    var i := 0
    while i < _plays.size():
        _advance(_plays[i], delta)
        i += 1
    # 错峰更新（旧动画本帧跨帧、新动画没跨）会让较旧动画重新写展示层。这里每帧重申一次
    # 归属：从旧到新逐条重申当前帧展示层，较新的播放自然最后写各自涉及的 Sprite，于是
    # 每个独立角色的 Sprite 都保留自己“最新有效播放”的归属；共享 user 也按最新写。
    # 旧写法从最新往旧找第一条会写展示层的就 break，只要有另一个角色起了更新的播放，
    # 就会把某个角色自己的较新播放整个跳过（A 被旧动画夺层）。已结束 / 无效播放不参与。
    i = 0
    while i < _plays.size():
        var p: Dictionary = _plays[i]
        if not bool(p["dead"]):
            _reassert_body(p)
        i += 1
    # 再生效回收本帧结束的播放：归属已由上面的重申确定，旧动画收尾不会复位新动画
    # 仍拥有的展示层；只有最后一个有效播放也结束后才复位。
    i = 0
    while i < _plays.size():
        var p2: Dictionary = _plays[i]
        if bool(p2["dead"]):
            _cleanup(p2)
            _plays.remove_at(i)
        else:
            i += 1


func _exit_tree() -> void:
    clear()


# 清掉本播放器当前所有临时播放：背景 / 特效面片、被写过的角色展示层归属与变换、音频。
# 供真实取消（`_cancel_events`）/ 放弃 / 结算（`_settle`）/ 场景退出（`_exit_tree`）调用：
#   - 不释放播放器节点本身，之后 play() / play_common() 仍能正常新建（战斗中途取消后继续放招）；
#   - 幂等：空表 / 重复调用 / 已释放的子对象都安全；
#   - 可在 `_exit_tree` 中调用（子对象可能已在退出树，`is_instance_valid` 逐个判）。
func clear() -> void:
    for p in _plays:
        _cleanup(p)
    _plays.clear()
    for pl in _audio:
        if is_instance_valid(pl):
            pl.stop()
            pl.stream = null
            pl.queue_free()
    _audio.clear()


# ================= 播放推进 =================

func _advance(p: Dictionary, delta: float) -> void:
    if not is_instance_valid(p["user"]) or not is_instance_valid(p["target"]):
        p["dead"] = true
        return
    var t := float(p["t"]) + delta
    p["t"] = t
    var frames: Array = p["anim"]["frames"]
    var last := frames.size() - 1
    # 帧表与背景补间在原引擎是同一条时间轴上的两个 tween：帧事件在**它自己的时刻**触发，
    # 背景补间因此只能推进到该帧时刻为止；事件生效后再继续吃剩余 delta。
    #   «一步推进» 与 «0.10 + 0.25 两步» 下得到不同 alpha。）
    # 低帧率时 delta 可能一帧跨过多帧：cur+1 .. target 逐帧「先推背景、再触发事件」补完，
    # 同帧事件按原 JSON 数组顺序触发。
    var target := mini(int(floor(t / FRAME_SECS)), last)
    var cur := int(p["frame"])
    if target > cur:
        var f := cur + 1
        while f <= target:
            _advance_bg_to(p, float(f) * FRAME_SECS)
            _fire_events(p, f)
            f += 1
        p["frame"] = target
        _apply_frame(p, target)
    _advance_bg_to(p, t)
    # 帧表播完不代表演出结束：原 onComplete 还要再等 Fi(T) 的尾部计数（见 _tail_units /
    # _tail_secs），期间背景补间必须继续跑，不能被帧表长度提前裁掉。尾部 T 含本条播放自己的
    # cry_units（叫声按物种时长），所以按 p 上的 cry_units 算，不读共享 anim 的全局缓存。
    if t > _lifetime(p["anim"], int(p.get("cry_units", -1))):
        p["dead"] = true


# ================= 时长（原 Fi / 帧计数 / 尾部等待）=================

# 原 `Fi(i)=Math.floor(1/60*1e3*i)`（源 index-7def6496.js @1553869）：整份移植里
# 「帧数 / 毫秒」换算的唯一入口。原引擎帧间隔 = Fi(3) = 50ms，背景补间时长 = Fi(duration*3)。
func _fi_ms(units: float) -> float:
    return floorf(units * 1000.0 / 60.0)


# 原 BattleAnim.play（源 @3180400 起）的主帧计数器：
#   let T = c.frames.length, R = 0;
#   t.tweens.addCounter({ duration: Fi(3), repeat: c.frames.length, onRepeat: () => {
#       for (const v of frameTimedEvents[R]) T = Math.max(c.frames.length - R + v.execute(t, this), T);
#       R++; T--;
#   }, onComplete: () => { T ? t.tweens.addCounter({ duration: Fi(T), onComplete: () => m() }) : m(); }});
# 要点（前两轮移植在这里用错了单位）：
#   - 两类背景事件 `execute` 都 `return this.duration*2`，返回的是**帧数单位**；
#   - T 全程是「帧数单位」的计数，帧回调每个 50ms 递减 1，帧回调共 repeat = frames.length 次；
#   - onComplete 之后的尾部等待是 `Fi(T)` **毫秒**（T 不是帧数、更不是毫秒本身）。
# 因此 T 必须在「原帧回调序号 R」上累计，不能写成 «帧表长度 vs 帧号+duration*2» 的帧数最大值。
# 声音事件 `execute` 也返回帧数单位：命名资源是 `ceil(sound.totalDuration*1e3/33.33)`，空
# resourceName 是 `ceil(user.cry(r).totalDuration*1e3/33.33)`（原 HB.execute 两个分支都 return），
# 所以声音事件同样参与 T。以前只累计背景事件是漏项：没有背景事件的超音波 / 三粉实际尾部不为 0。
#
# `cry_units` 是这条播放的**空 resourceName** 声音事件的片长（帧数单位，来自出招方物种真实 cry）；
# 默认 -1 表示没有 cry 上下文（只算命名声音 / 背景）。带 cry 的招（叫声）每个物种片长不同，
# 所以 cry_units >= 0 时**不写 anim 缓存**，避免把某个物种的尾部张冠李戴到共享 anim 上。
func _tail_units(anim: Dictionary, cry_units := -1) -> int:
    if cry_units < 0 and anim.has("_tail_units"):
        return int(anim["_tail_units"])
    var n := (anim["frames"] as Array).size()
    var t := n
    var events = anim.get("frameTimedEvents", {})
    if events is Dictionary:
        var r := 0
        while r < n:
            var list = (events as Dictionary).get(str(r), [])
            if list is Array:
                for ev in list:
                    if not (ev is Dictionary):
                        continue
                    var kind := str((ev as Dictionary).get("eventType", ""))
                    var ext := 0
                    match kind:
                        "AnimTimedAddBgEvent", "AnimTimedUpdateBgEvent":
                            ext = int(float((ev as Dictionary).get("duration", 0)) * 2.0)
                        "AnimTimedSoundEvent":
                            ext = _sound_event_units(str((ev as Dictionary).get("resourceName", "")), cry_units)
                        _:
                            continue
                    t = maxi(n - r + ext, t)
            t -= 1
            r += 1
    if cry_units < 0:
        anim["_tail_units"] = t
    return t


# 原 AnimTimedSoundEvent.execute 的返回值（帧数单位）：
#   命名资源 = ceil(totalDuration*1000/33.33)；空 resourceName = ceil(cry.totalDuration*1000/33.33)。
# 命名资源时长按真实 WAV load 后算一次并缓存；空名字用本条播放的 cry_units。
func _sound_event_units(resource_name: String, cry_units: int) -> int:
    if resource_name == "":
        return maxi(0, cry_units)
    if _sound_units.has(resource_name):
        return int(_sound_units[resource_name])
    var units := 0
    var path := _sound_path(resource_name)
    if ResourceLoader.exists(path):
        var st = load(path)
        if st is AudioStream:
            units = int(ceil(float(st.get_length()) * 1000.0 / 33.33))
    _sound_units[resource_name] = units
    return units


# 这条播放的空 resourceName 声音事件片长：只有 anim 里真有这种事件时才去取 cry。
# 未知物种 / 缺文件返回 0（明确不播、不撑尾部），不伪造绿毛虫或通用音效。
func _cry_units_for(anim: Dictionary, species_id: int) -> int:
    if not _has_empty_sound(anim):
        return -1
    var st := _cry_stream(species_id)
    if st == null:
        return 0
    return int(ceil(float(st.get_length()) * 1000.0 / 33.33))


func _has_empty_sound(anim: Dictionary) -> bool:
    var events = anim.get("frameTimedEvents", {})
    if not (events is Dictionary):
        return false
    for key in (events as Dictionary):
        var list = (events as Dictionary)[key]
        if not (list is Array):
            continue
        for ev in list:
            if (ev is Dictionary) and str((ev as Dictionary).get("eventType", "")) == "AnimTimedSoundEvent" \
                    and str((ev as Dictionary).get("resourceName", "")) == "":
                return true
    return false


# 原 getCryKey 的有限实现：只认 CRY_KEYS 里 34 个 Growl 学习物种 form0；其余返回 null。
# 加载失败 / 缺文件也返回 null，让调用方 push_warning 明确报告，不做回退。
func _cry_stream(species_id: int) -> AudioStream:
    var key := str(CRY_KEYS.get(species_id, ""))
    if key == "":
        return null
    var path := CRY_DIR + key + ".wav"
    if not ResourceLoader.exists(path):
        return null
    var st = load(path)
    return st if st is AudioStream else null


# 尾部等待毫秒：原 `tweens.addCounter({duration: Fi(T)})`。T <= 0 时原引擎直接结束（不建 counter）。
func _tail_secs(anim: Dictionary, cry_units := -1) -> float:
    var u := _tail_units(anim, cry_units)
    if u <= 0:
        return 0.0
    return _fi_ms(float(u)) / 1000.0


# 整段演出的生存时长（秒）= 主帧段 + 尾部等待。
# 首帧对齐差异：原引擎第一次 onRepeat（也就是帧 0 的事件）发生在「第一个 Fi(3)=50ms 周期结束时」，
# 本作在 play() 里把帧 0 对齐到 t=0（见 SOURCES.md「首帧对齐」），所以主帧段取
# frames.length * 50ms，而不是原 counter 的 (frames.length + 1) * 50ms。
func _lifetime(anim: Dictionary, cry_units := -1) -> float:
    var n := (anim["frames"] as Array).size()
    return n * FRAME_SECS + _tail_secs(anim, cry_units)


func _apply_frame(p: Dictionary, fi: int) -> void:
    var frames: Array = p["anim"]["frames"]
    if fi < 0 or fi >= frames.size():
        return
    var layers: Array = frames[fi]
    var si := 0
    for layer in layers:
        var kind := int(layer.get("target", 2))
        if kind == 2:
            if not bool(p.get("novisual", false)):
                _apply_effect(p, si, layer)
                si += 1
        else:
            _apply_body(p, kind, layer)
    var sprites: Array = p["sprites"]
    while si < sprites.size():
        var extra = sprites[si]
        if is_instance_valid(extra):
            extra.visible = false
        si += 1


# ================= 特效图层（target 2）=================

# 地震（原动画 id 89）：去掉蓝色背景，石头放大让落点更直观（用户 2026-10-18）。
const EARTHQUAKE_ANIM_ID := 89
const EARTHQUAKE_BG := "PRAS- Earthquake BG"
const EARTHQUAKE_ROCK_ZOOM := 2.4


func _apply_effect(p: Dictionary, i: int, layer: Dictionary) -> void:
    var sprites: Array = p["sprites"]
    while sprites.size() <= i:
        sprites.append(_make_sprite())
    var mi: MeshInstance3D = sprites[i]
    if not is_instance_valid(mi):
        return
    var mat := mi.material_override as StandardMaterial3D
    var graphic := str(p["anim"]["graphic"])
    var graphic_frame := int(layer.get("graphicFrame", 0))
    mat.albedo_texture = _sheet(graphic)
    mi.mesh = _quad(graphic, graphic_frame)
    var tint: Color = p.get("tint", Color.WHITE)
    mat.albedo_color = Color(tint.r, tint.g, tint.b, clampf(float(layer.get("opacity", 255)) / 255.0, 0.0, 1.0))
    mat.render_priority = clampi(int(layer.get("priority", 1)), -128, 127)
    var tone = layer.get("tone", null)
    if (tone is Array) and tone.size() >= 3:
        # 原为线性叠加 color.rgb += tone.rgb * alpha；这里用 emission 近似。
        mat.emission_enabled = true
        mat.emission = Color(float(tone[0]) / 255.0, float(tone[1]) / 255.0, float(tone[2]) / 255.0)
        mat.emission_energy_multiplier = 1.0
    else:
        mat.emission_enabled = false
    var zx := float(layer.get("zoomX", 100.0)) / 100.0
    var zy := float(layer.get("zoomY", 100.0)) / 100.0
    # 原 getGraphicFrameData：`N=T.zoomX/100*(T.mirror?-1:1)`，mirror 只翻 X 轴缩放。
    # 六份 common 里只有 common-paralysis 的 target 2 图层用 mirror（20 层）；不臆造其它调色。
    if int(p["anim"].get("id", 0)) == EARTHQUAKE_ANIM_ID and graphic == "PRAS- Rock":
        zx *= EARTHQUAKE_ROCK_ZOOM
        zy *= EARTHQUAKE_ROCK_ZOOM
    var mirror := bool(layer.get("mirror", false))
    _orient(mi, _layer_pos(p, layer), deg_to_rad(-float(layer.get("angle", 0.0))), zx, zy, mirror)
    mi.visible = bool(layer.get("visible", true))
    # 描边只给边缘清晰的像素图层（火苗 / 水滴 / 爱心 / 牙齿…）；软边的光晕 / 云雾 / 气场（精神强念的云、哗哗气场）垫深色会变成黑块，不描。
    if outline_effects:
        var crisp := _is_crisp(graphic, graphic_frame)
        if crisp and mi.get_node_or_null("Outline0") == null:
            add_outline(mi)
        _sync_outline(mi, crisp)


func _layer_pos(p: Dictionary, layer: Dictionary) -> Vector3:
    var lx := float(layer.get("x", 0.0))
    var ly := float(layer.get("y", 0.0))
    var user_pos := _center(p["user"])
    var target_pos := _center(p["target"])
    match int(layer.get("focus", 1)):
        2:
            var v2 := _sweep_remap(Vector2(lx, ly), user_pos, target_pos, true)
            return user_pos + _screen_offset(v2.x, v2.y)
        3:
            var s := lx / CANON_W
            return user_pos.lerp(target_pos, s) + _screen_offset(0.0, ly + CENTER_Y * s)
        _:
            var v := _sweep_remap(Vector2(lx - CENTER_X, ly + CENTER_Y), user_pos, target_pos)
            return target_pos + _screen_offset(v.x, v.y)


# 受击方锚点（focus 1）的图层偏移是按原版横版场景写的：玩家在左下、敌人在右上，连线固定是 (128, -64)。
# 本作里玩家和敌人可以在任何方位，所以“在玩家这一侧、沿连线飞过来”的图层（超音波的圈圈、一些飞行物）
# 要按真实的“玩家 → 敌人”连线转 + 缩放过去，才会从主角发射、飞向敌人（用户 2026-10-18：
# “超声波应该是从主角发射往敌人的，而不是敌人的左下角发射给敌人的”）。
# 只重映射沿连线的图层（focus 1 靠玩家一侧 / focus 2 朝敌人一侧；竖直火柱、围着自己或敌人转的小光点原样不动），用平滑权重过渡。
func _sweep_remap(v: Vector2, user_pos: Vector3, target_pos: Vector3, from_user := false) -> Vector2:
    var basis := _view_basis()
    var d := target_pos - user_pos
    var actual := Vector2(d.dot(basis.x), -d.dot(basis.y)) / PIXEL_SIZE   # 屏幕像素，y 向下为正
    if actual.length() < SWEEP_MIN_DIST:
        return v
    var canon := Vector2(CANON_W, -CENTER_Y)   # 原版 玩家 → 敌人
    var denom := canon.length_squared()
    var a := v.dot(canon) / denom
    var perp := Vector2(-canon.y, canon.x)
    var b := v.dot(perp) / denom
    # from_user：偏移是相对出招方的（focus 2），朝敌人那一侧（a > 0）才重映射；否则偏移相对受击方（focus 1），靠玩家那一侧（a < 0）。
    var side := smoothstep(0.1, 0.35, a) if from_user else smoothstep(-0.1, -0.35, a)
    var w := side * (1.0 - smoothstep(0.4, 0.8, absf(b)))
    if w <= 0.0:
        return v
    var mapped := actual * a + Vector2(-actual.y, actual.x) * b
    return v.lerp(mapped, w)


# 出招方真身 / 虚影的位移（focus 2）：原版写的是“朝右上冲向敌人”，沿连线的分量换成真实的玩家 → 敌人方向，
# 垂直连线的分量（跳起来、后仰）保持原样不转。
func _body_remap(v: Vector2, user_pos: Vector3, target_pos: Vector3, gain := 1.0) -> Vector2:
    var basis := _view_basis()
    var d := target_pos - user_pos
    var actual := Vector2(d.dot(basis.x), -d.dot(basis.y)) / PIXEL_SIZE
    if actual.length() < SWEEP_MIN_DIST:
        return v
    var canon := Vector2(CANON_W, -CENTER_Y)
    var a := v.dot(canon) / canon.length_squared()
    var a_move := a * gain if a > 0.0 else a
    return v - canon * a + actual * a_move


# 这个动画里出招方朝敌人冲得最远的比例（focus 3 = x / 128，focus 2 = 沿连线分量）。原版有些招只冲 20%（撞击 / 电光一闪），
# 这里距离是几米，看着像没撞到：把虚影的冲出比例放大到刚好够着敌人（最多 REACH_GAIN_MAX 倍；本来就冲到位的招不变）。
const REACH_GAIN_MAX := 5.0
const REACH_TARGET := 0.9


func _reach_gain(p: Dictionary) -> float:
    if p.has("reach_gain"):
        return float(p["reach_gain"])
    var best := 0.0
    var canon := Vector2(CANON_W, -CENTER_Y)
    for frame in p["anim"]["frames"]:
        for layer in frame:
            if int(layer.get("target", 2)) != 0:
                continue
            var focus := int(layer.get("focus", 1))
            var x := float(layer.get("x", 0.0))
            var y := float(layer.get("y", 0.0))
            if focus == 3:
                best = maxf(best, x / CANON_W)
            elif focus == 2:
                best = maxf(best, Vector2(x, y).dot(canon) / canon.length_squared())
    var gain := 1.0
    if best > 0.05 and best < REACH_TARGET:
        gain = minf(REACH_TARGET / best, REACH_GAIN_MAX)
    p["reach_gain"] = gain
    return gain


# ================= 出招 / 受击方展示层（target 0/1）=================
# 只动 Sprite3D 的本地偏移与缩放；不碰世界位置、碰撞体、朝向根节点。

# 只重申展示层（target 0/1）的归属，不动各自独立的面片特效；返回是否真的写了展示层。
func _reassert_body(p: Dictionary) -> bool:
    var frames: Array = p["anim"]["frames"]
    var fi := int(p["frame"])
    if fi < 0 or fi >= frames.size():
        return false
    var wrote := false
    for layer in frames[fi]:
        var kind := int(layer.get("target", 2))
        if kind == 2:
            continue
        if _apply_body(p, kind, layer):
            wrote = true
    return wrote


func _apply_body(p: Dictionary, kind: int, layer: Dictionary) -> bool:
    var node = p["user"] if kind == 0 else p["target"]
    if node == null or not is_instance_valid(node):
        return false
    var focus := int(layer.get("focus", 1))
    # 原引擎 0/1 图层多为“按横版布局重画的精灵副本”，只在锚点就是该实体自己时才有原生位移。
    var self_anchored := (kind == 0 and (focus == 2 or focus == 3)) or (kind == 1 and focus == 1)
    if not self_anchored:
        return false
    if kind == 0 and (focus == 2 or focus == 3) and not dash_enabled:
        return false   # 出招方不冲出去、不出蓝色虚影（用户 2026-10-19：“蓝影子也去掉吧”）；受击方的抖动不受影响
    var spr := _sprite_of(node)
    if spr == null:
        return false
    var lx := float(layer.get("x", 0.0))
    var ly := float(layer.get("y", 0.0))
    var offset := Vector3.ZERO
    if focus == 3:
        var user_pos := _center(p["user"])
        var target_pos := _center(p["target"])
        var s := lx / CANON_W
        var s_move := s
        if kind == 0 and s > 0.0:
            s_move = s * _reach_gain(p)   # 冲出去的比例按这个动画的最大冲刺放大到够得着敌人
        offset = (user_pos.lerp(target_pos, s_move) - user_pos) + _screen_offset(0.0, ly + CENTER_Y * s)
    elif focus == 1:
        offset = _screen_offset(lx - CENTER_X, ly + CENTER_Y)
    else:
        var v := Vector2(lx, ly)
        if kind == 0:
            v = _body_remap(v, _center(p["user"]), _center(p["target"]), _reach_gain(p))
        offset = _screen_offset(v.x, v.y)
    if kind == 0 and offset.length() > PHANTOM_MIN_OFFSET:
        spr = _phantom_of(p, spr)
        # 虚影要正面冲敌人（用户 2026-10-18：“向右方向的虚影应该反过来，不会有拿屁股尾巴撞击的情况”）：
        # 原画正面朝屏幕左（flip_h = false），敌人在屏幕右边就翻面；几乎正上 / 正下方时沿用本体朝向。
        var to_target := (_center(p["target"]) - _center(p["user"])).dot(_view_basis().x)
        if absf(to_target) > 0.15:
            spr.flip_h = to_target > 0.0
    spr.position = offset
    # 原动画里出招方副本会被压成一条细缝（钢翼 zoomX 9 / 滚动 / 追打）；这里是真身精灵，压成细线很难看
    # （用户 2026-10-17：“他这个变窄的是啥技能，太难看了”），缩放不小于 BODY_ZOOM_MIN。
    var zx := maxf(float(layer.get("zoomX", 100.0)) / 100.0, BODY_ZOOM_MIN)
    var zy := maxf(float(layer.get("zoomY", 100.0)) / 100.0, BODY_ZOOM_MIN)
    spr.scale = Vector3(-zx if bool(layer.get("mirror", false)) else zx, zy, 1.0)
    if not spr.has_meta("rogue_phantom"):
        spr.set_meta("rogue_fx_token", int(p["id"]))
    var touched: Array = p["touched"]
    if not touched.has(spr):
        touched.append(spr)
    return true


# 虚影：复制真身精灵（同贴图 / 同帧 / 同朝向），半透明，挂在同一个父节点下；本条播放结束时一并释放。
func _phantom_of(p: Dictionary, real: Sprite3D) -> Sprite3D:
    var ghost = p.get("phantom", null)
    if ghost != null and is_instance_valid(ghost):
        return ghost
    var g := _make_ghost(real)
    p["phantom"] = g
    return g


func _make_ghost(real: Sprite3D) -> Sprite3D:
    var g := real.duplicate() as Sprite3D
    for c in g.get_children():   # 描边副本等不要带过来
        g.remove_child(c)
        c.queue_free()
    g.set_meta("rogue_phantom", true)
    var mat := ShaderMaterial.new()
    mat.shader = PHANTOM_SHADER
    mat.set_shader_parameter("tex", real.texture)
    g.material_override = mat
    g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    real.get_parent().add_child(g)
    return g


# ================= 声音 / 背景事件 =================

func _fire_events(p: Dictionary, f: int) -> void:
    for e in _events_at(p, f):
        _play_event(p, e)


func _events_at(p: Dictionary, f: int) -> Array:
    var events = p["anim"].get("frameTimedEvents", {})
    if not (events is Dictionary):
        return []
    var key := str(f)
    if not events.has(key):
        return []
    var out = events[key]
    return out if out is Array else []


# 按原 eventType 分派：AnimTimedSoundEvent 播原 WAV；AnimTimedAddBgEvent / AnimTimedUpdateBgEvent
# 建 / 移动背景板。**不把背景事件当声音资源**（否则会 push_warning 找不到 WAV）。
# 原 HB.execute 的 AnimTimedSoundEvent 两个分支：命名 resourceName 播那个 WAV；空名字调用
# `n.user.cry(r)`（出招方物种原 cry），不是「没有声音」。这里按 resourceName 是否为空显式分派。
# sound 只拦声音事件：同一群体释放的后续目标不重复播同两声 WAV，但背景事件照跑。
func _play_event(p: Dictionary, e: Dictionary) -> void:
    var kind := str(e.get("eventType", ""))
    match kind:
        "AnimTimedSoundEvent":
            if bool(p.get("sound", true)):
                if str(e.get("resourceName", "")) == "":
                    _play_cry(p, e)
                else:
                    _play_sound(e)
        "AnimTimedAddBgEvent":
            _bg_add(p, e)
        "AnimTimedUpdateBgEvent":
            _bg_update(p, e)


# 原 AnimTimedAddBgEvent.execute（源偏移约 3176852）：
#   `n.bgSprite=this.resourceName?t.add.tileSprite(this.bgX-320,this.bgY-284,896,576,this.resourceName)
#      :t.add.rectangle(...,0), n.bgSprite.setOrigin(0,0), n.bgSprite.setScale(1.25),
#      n.bgSprite.setAlpha(this.opacity/255)`
# 位置 = (bgX-320, bgY-284)，尺寸 896x576、origin(0,0)、scale 1.25、alpha = opacity/255。
# 这里用一块面向相机的大面板表示，UV 平铺重复次数与 tileSprite 相同（见 _make_bg_sprite）。
# **这条事件只操作 p 自己的背景板**。
func _bg_add(p: Dictionary, e: Dictionary) -> void:
    _bg_free(p)
    if bool(p.get("novisual", false)):
        return   # 特效由 pack_fx 接管时不画原背景板（事件仍走，尾部计数不变）
    var name := str(e.get("resourceName", ""))
    # 地震不要那块蓝色背景影子（用户 2026-10-18）：事件照走（尾部计数不变），只是不画背景板。
    if name == EARTHQUAKE_BG:
        return
    var quad := _make_bg_sprite(name)
    if quad == null:
        return
    _bg_attach(p, quad)
    # 新播放的背景叠在旧播放之上（显示层最新 ownership），但旧播放的事件永远写不到它。
    (quad.material_override as StandardMaterial3D).render_priority = clampi(int(p.get("id", 0)), -128, 127)
    _bg_state(p)["px"] = _bg_add_px(e)
    _bg_state(p)["alpha"] = clampf(float(e.get("opacity", 0)) / 255.0, 0.0, 1.0)
    _bg_tw(p).clear()
    _apply_bg(p, quad, _bg_state(p)["px"], _bg_state(p)["alpha"])


# 原 AnimTimedUpdateBgEvent.execute（源偏移约 3176419）：
#   `const r={}; this.bgX!==void 0&&(r.x=this.bgX*.5-320);
#    this.bgY!==void 0&&(r.y=this.bgY*.5-284);
#    this.opacity!==void 0&&(r.alpha=(this.opacity||0)/255);
#    Object.keys(r).length&&t.tweens.add(Object.assign({targets:n.bgSprite,duration:Fi(this.duration*3)},r))`
# 三条都要点：
#   1) 坐标换算与 Add **不同**：Update 是 `bgX*.5-320` / `bgY*.5-284`。
#   2) 时长是 `Fi(duration*3)` **毫秒**（`Fi(i)=floor(i*1000/60)`）：duration 5 → 250ms、
#      10 → 500ms、50 → 2500ms。上一轮漏了 `*3`（按 duration 帧算），背景补间整体快/慢 3 倍。
#   3) 源里 x / y / alpha 是**独立补间**：只对本次给了的属性建 tween，其余属性继续由先前的事件驱动。
#      **同一属性上的多个 tween 在原引擎里是并行的、不会互相取消**（下方 2026-10-15 收尾证据）：
#      Phaser 3.80 TweenManager.add 只 `D.push(g.reset())`，没有 killTweensOf / overwrite；
#      每帧按数组（加入）顺序逐条 update，各自写 `target[key]`，所以**后加入的每帧后写、当帧生效**，
#      但先加入那条的时钟照走；新 tween 一结束，仍在活跃的旧 tween 下一帧重新成为可见写入者。
#      因此本作按属性保存**一条加入顺序的活跃补间列表**（不是只留最新一条），_advance_bg_to 逐条推进 / 写入，
#      写完到期才移除 —— 新短结束后旧长仍继续生效，无关属性不受影响。
# 本作不建 Node Tween：目标与时长记在这条播放自己的 bg_tw 上，交给 _advance_bg_to 按同一时间轴插值。
func _bg_update(p: Dictionary, e: Dictionary) -> void:
    var quad = _current_bg(p)
    if quad == null or not is_instance_valid(quad):
        return
    var st := _bg_state(p)
    var dur := maxf(0.0, _fi_ms(float(e.get("duration", 0)) * 3.0) / 1000.0)
    if e.has("bgX"):
        _bg_push(p, "x", _bg_tween_spec(float((st["px"] as Vector2).x), float(e.get("bgX", 0.0)) * 0.5 - BG_ORIGIN_X, dur))
    if e.has("bgY"):
        _bg_push(p, "y", _bg_tween_spec(float((st["px"] as Vector2).y), float(e.get("bgY", 0.0)) * 0.5 - BG_ORIGIN_Y, dur))
    if e.has("opacity"):
        _bg_push(p, "a", _bg_tween_spec(float(st["alpha"]), clampf(float(e.get("opacity", 0)) / 255.0, 0.0, 1.0), dur))
    # 原 duration 0（`Fi(0)=0`）的 tween 立即到位；_advance_bg_to 对 dur<=0 也直接判完成。
    _advance_bg_to(p, float(p.get("bg_clock", 0.0)))


# 把一条新补间追加到该属性已有的活跃列表尾部（原 Phaser `tweens.add` 的 push 语义）。
# 属性列表为空时把 key 删掉，让 bg_tw.is_empty() 仍是「没有活跃补间」的准确判据。
func _bg_push(p: Dictionary, key: String, spec: Dictionary) -> void:
    var tw := _bg_tw(p)
    if not (tw.get(key) is Array):
        tw[key] = []
    (tw[key] as Array).append(spec)


func _bg_tween_spec(from_v: float, to_v: float, dur: float) -> Dictionary:
    return {"from": from_v, "to": to_v, "dur": dur, "t": 0.0}


# 背景板的显示状态（左上角源像素 + 当前 alpha）。手搓的测试字典也走这里，缺键就地补默认值。
func _bg_state(p: Dictionary) -> Dictionary:
    if not (p.get("bg_st") is Dictionary):
        p["bg_st"] = {"px": Vector2.ZERO, "alpha": 0.0}
    return p["bg_st"]


func _bg_tw(p: Dictionary) -> Dictionary:
    if not (p.get("bg_tw") is Dictionary):
        p["bg_tw"] = {}
    return p["bg_tw"]


# 原 x/y 目标位置（左上角像素）→ 世界中心位置。
func _bg_world_pos(p: Dictionary, px: Vector2) -> Vector3:
    # origin(0,0) 是左上角，中心要补半个「缩放后」尺寸；+y 在屏幕像素里向下。
    var half_w := BG_W * BG_SCALE * 0.5
    var half_h := BG_H * BG_SCALE * 0.5
    var c := px + Vector2(half_w, half_h)
    return _center(p.get("target")) + _screen_offset(c.x, c.y) - _view_basis().z * 3.0


# Add 的像素位置：原 `bgX-320` / `bgY-284`。
func _bg_add_px(e: Dictionary) -> Vector2:
    return Vector2(float(e.get("bgX", 0.0)) - BG_ORIGIN_X, float(e.get("bgY", 0.0)) - BG_ORIGIN_Y)


# 这条播放**自己**拥有的背景板（没有就是 null）。每条播放的事件只写自己这一块，
# 所以旧播放的 Update 永远不会改到新播放的背景上；不按「全局最新播放」去取别人的对象。
func _current_bg(p: Dictionary) -> Node3D:
    for q in p.get("bg", []):
        if is_instance_valid(q):
            return q
    return null


func _bg_attach(p: Dictionary, quad: MeshInstance3D) -> void:
    (p["bg"] as Array).append(quad)


# 原 `t.add.tileSprite(x, y, 896, 576, res)` 的替代：一块面向相机、alpha 混合、最近邻采样的大面板。
# tileSprite 的「tile」语义必须保留：整块 tileSprite 是 896x576，**贴图按原始尺寸平铺重复采样**，
# 即横向 896/tex_w、纵向 576/tex_h 次（PRAS- Confusion BG.png 是 256x192 → 3.5 x 3.0 次，
# 原图 60x45 的格子在面板上出现 3~4 次）。
# 本作网格 UV 保持 0..1，用 `uv1_scale = (896/tex_w, 576/tex_h)` 把采样点送出 0..1 区间，
# 再靠 `texture_repeat = true` 平铺，重复次数与原来一致；不新增贴图、不加 shader。
# 面板整体还是 896x576 x scale 1.25 的 2.5D 尺寸（见 _apply_bg_pos）。
func _make_bg_sprite(resource: String) -> MeshInstance3D:
    if resource == "":
        return null
    var path := DIR + resource + ".png"
    if not ResourceLoader.exists(path):
        return null
    var tex := load(path) as Texture2D
    if tex == null:
        return null
    var mi := MeshInstance3D.new()
    mi.mesh = _quad_mesh(Rect2(0.0, 0.0, 1.0, 1.0))
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    mat.albedo_texture = tex
    mat.texture_repeat = true
    mat.uv1_scale = Vector3(
        BG_W / float(maxi(1, tex.get_width())),
        BG_H / float(maxi(1, tex.get_height())),
        1.0)
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    return mi


func _bg_free(p: Dictionary) -> void:
    _bg_tw(p).clear()
    for q in p.get("bg", []):
        if is_instance_valid(q):
            q.queue_free()
    if p.get("bg") is Array:
        (p["bg"] as Array).clear()


# 背景补间推进到本条播放时间轴上的**绝对时刻** abs_t（秒），与帧表共用同一个 p["t"]。
# 三条属性各自独立推进；同一属性按加入顺序逐条推进 / 写入（后加入的后写、当帧生效），到期才移除。
# 这复刻原 Phaser TweenManager：add 只 push、无同目标取消；每帧按数组顺序 update，逐条写 target[key]。
# 所以「新短补间结束后，仍在活跃的旧长补间下一帧重新成为可见值」——不是只留最新一条。
func _advance_bg_to(p: Dictionary, abs_t: float) -> void:
    var clock := float(p.get("bg_clock", 0.0))
    var dt := abs_t - clock
    if dt < 0.0:
        dt = 0.0
    p["bg_clock"] = maxf(clock, abs_t)
    var tw := _bg_tw(p)
    if tw.is_empty():
        return
    var quad = _current_bg(p)
    if quad == null or not is_instance_valid(quad):
        tw.clear()
        return
    var st := _bg_state(p)
    var px: Vector2 = st["px"]
    var alpha := float(st["alpha"])
    for key in ["x", "y", "a"]:
        if not tw.has(key):
            continue
        var specs = tw[key]
        if not (specs is Array):
            tw.erase(key)
            continue
        var live: Array = []
        for spec in specs:
            if not (spec is Dictionary):
                continue
            var dur := float(spec["dur"])
            # 原 TweenManager.step 在 delta <= 0 时整帧不更新。本作会在同一帧里为了帧事件
            # 分几次推进到帧时刻、最后再推进到 t；那次 delta=0 的收尾不能让已完成的较新补间
            # 被移除后、较旧补间又被重写一遍。所以 delta<=0 时只处理 duration 0 的即时补间，
            # 其余保持原值（它们刚加入时 from 就是当前值，跳过写入等价）。
            if dt <= 0.0 and dur > 0.0:
                live.append(spec)
                continue
            spec["t"] = float(spec["t"]) + dt
            # 原 duration 0 的 tween（`Fi(0)=0`）当帧就到位；浮点累计误差用 1µs 容差吸收
            # （绝对时间戳相减会比标称 delta 小一点，不能让该到期的补间多留一帧）。
            var done := dur <= 0.0 or float(spec["t"]) >= dur - 0.000001
            var k := 1.0 if done else clampf(float(spec["t"]) / dur, 0.0, 1.0)
            var v := lerpf(float(spec["from"]), float(spec["to"]), k)
            if key == "x":
                px.x = v
            elif key == "y":
                px.y = v
            else:
                alpha = v
            # 完成帧仍写一次末值（原 TweenData 完成帧也 update），下一帧不再保留。
            if not done:
                live.append(spec)
        if live.is_empty():
            tw.erase(key)
        else:
            tw[key] = live
    st["px"] = px
    st["alpha"] = alpha
    _apply_bg(p, quad, px, alpha)


# 旧签名保留：按 delta 推进背景（等价于推进到 bg_clock + delta），给单独驱动背景的测试用。
func _advance_bg(p: Dictionary, delta: float) -> void:
    _advance_bg_to(p, float(p.get("bg_clock", 0.0)) + delta)


# 原 tileSprite 的「尺寸 = 896x576 px、scale 1.25、origin 左上角」：本作把整块面板按
# 相机屏幕轴摆在目标中心 + 半尺寸处，并沿相机前向反方向推远一点压在角色后面。
# 尺寸本身（1120x720 px 世界面板）是 2.5D 适配值，见 SOURCES.md。
func _apply_bg(p: Dictionary, quad: MeshInstance3D, px: Vector2, alpha: float) -> void:
    _apply_bg_pos(quad, _bg_world_pos(p, px), alpha)


func _apply_bg_pos(quad: MeshInstance3D, pos: Vector3, alpha: float) -> void:
    var basis := _view_basis()
    quad.global_transform = Transform3D(basis, pos)
    var sx := BG_W * BG_SCALE * BG_PIXEL_SIZE / (CELL * PIXEL_SIZE)
    var sy := BG_H * BG_SCALE * BG_PIXEL_SIZE / (CELL * PIXEL_SIZE)
    quad.scale = Vector3(sx, sy, 1.0)
    (quad.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, alpha)


# 原声音资源名 → 实际可加载路径：Godot 读不了 m4a，原 m4a 声音（亮亮风暴的 Saint7 / Saint8 / Blow1）
# 另有同名 .wav 转码副本（assets/pokemon/move_fx/*.wav，ffmpeg 转 pcm_s16le；原 m4a 字节同在，不改）。
func _sound_path(resource_name: String) -> String:
    var path := DIR + resource_name
    if resource_name.ends_with(".m4a") and not ResourceLoader.exists(path):
        return DIR + resource_name.trim_suffix(".m4a") + ".wav"
    return path


# 命名 resourceName 的原 WAV 声音事件（原 HB.execute 的 `t.playSound(this.resourceName, r)`）。
func _play_sound(e: Dictionary) -> void:
    var name := str(e.get("resourceName", ""))
    if name == "":
        return
    var path := _sound_path(name)
    if not ResourceLoader.exists(path):
        push_warning("rogue_moves: sound not imported or missing: " + path)
        return
    var st = load(path)
    if not (st is AudioStream):
        return
    _play_stream(st, e)


# 空 resourceName 的原声音事件（原 HB.execute 的 `n.user.cry(r)`）：播**出招方物种**的原 cry。
# 只认 CRY_KEYS 里 34 个有限原 Growl 学习物种 form0；未知物种明确拒绝 / 报告，绝不拿绿毛虫
# 或通用音效冒充。volume / pitch 仍用该事件的原值。
func _play_cry(p: Dictionary, e: Dictionary) -> void:
    var species_id := int(p.get("species_id", 0))
    var st := _cry_stream(species_id)
    if st == null:
        push_warning("rogue_moves: no original cry for species %d (empty sound event rejected)" % species_id)
        return
    _play_stream(st, e)


# 真实播放一个 AudioStream（命名 WAV 与物种 cry 共用同一条路径，volume / pitch 取原事件值）。
func _play_stream(st: AudioStream, e: Dictionary) -> void:
    var pl := AudioStreamPlayer.new()
    pl.stream = st
    pl.volume_db = linear_to_db(clampf(float(e.get("volume", 100)) / 100.0, 0.0001, 1.0))
    pl.pitch_scale = maxf(0.01, float(e.get("pitch", 100)) / 100.0)
    pl.bus = _audio_bus()
    add_child(pl)
    pl.finished.connect(_on_sound_done.bind(pl))
    _audio.append(pl)
    pl.play()


func _on_sound_done(pl: AudioStreamPlayer) -> void:
    _audio.erase(pl)
    pl.queue_free()


func _audio_bus() -> StringName:
    if AudioServer.get_bus_index("Sfx") >= 0:
        return &"Sfx"
    return &"Master"


# ================= 资源与几何 =================

# 原 JSON 顶层可能是单个对象（多数招）或**两变体数组**（supersonic）。两种都保留：
# 单对象直接返回；数组逐项校验后原样存进 _data，播放时由 _anim_for 按出招方选变体。
# graphic 允许是空字符串（confusion 就是），此时角色变换 + 背景事件仍然照播。
func _read_anim(file: String):
    var path := DIR + file
    if not FileAccess.file_exists(path):
        push_warning("rogue_moves: missing " + path)
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if parsed is Array:
        var variants: Array = []
        for item in parsed:
            if item is Dictionary and item.has("frames") and item.has("graphic"):
                variants.append(item)
        if variants.is_empty():
            push_warning("rogue_moves: bad anim data " + path)
            return {}
        return variants
    if not (parsed is Dictionary) or not parsed.has("frames") or not parsed.has("graphic"):
        push_warning("rogue_moves: bad anim data " + path)
        return {}
    return parsed


func _make_sprite() -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.mesh = _quad_mesh(Rect2(0.0, 0.0, 1.0, 1.0))
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    mat.no_depth_test = true
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    return mi


# 整张图集（full sheet）。3D 材质直接采样，不用 AtlasTexture——它的 region 只在 2D 绘制里生效。
func _sheet(graphic: String) -> Texture2D:
    if not _sheets.has(graphic):
        var path := DIR + graphic + ".png"
        var sheet_tex: Texture2D = null
        if ResourceLoader.exists(path):
            sheet_tex = load(path) as Texture2D
        _sheets[graphic] = sheet_tex
        if sheet_tex == null:
            push_warning("rogue_moves: sheet not imported or missing: " + path)
    return _sheets[graphic]


# 把 graphicFrame 烤进网格 UV：按原 loadSpritesheet(..., 96) 的 96x96 方格。
func _quad(graphic: String, gf: int) -> ArrayMesh:
    var key := "%s#%d" % [graphic, gf]
    if not _quads.has(key):
        _quads[key] = _quad_mesh(_region_uv(graphic, gf))
    return _quads[key]


func _region_uv(graphic: String, gf: int) -> Rect2:
    var sheet := _sheet(graphic)
    if sheet == null:
        return Rect2(0.0, 0.0, 1.0, 1.0)
    var w := float(sheet.get_width())
    var h := float(sheet.get_height())
    if w < 1.0 or h < 1.0:
        return Rect2(0.0, 0.0, 1.0, 1.0)
    var cols := maxi(1, int(w / CELL))
    var frame := maxi(0, gf)
    var col := frame % cols
    var row := frame / cols
    return Rect2(col * CELL / w, row * CELL / h, CELL / w, CELL / h)


func _quad_mesh(uv: Rect2) -> ArrayMesh:
    var half := CELL * PIXEL_SIZE * 0.5
    var verts := PackedVector3Array([
        Vector3(-half, -half, 0.0), Vector3(half, -half, 0.0),
        Vector3(half, half, 0.0), Vector3(-half, half, 0.0)])
    var normals := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
    var uvs := PackedVector2Array([
        Vector2(uv.position.x, uv.position.y + uv.size.y),
        Vector2(uv.position.x + uv.size.x, uv.position.y + uv.size.y),
        Vector2(uv.position.x + uv.size.x, uv.position.y),
        Vector2(uv.position.x, uv.position.y)])
    var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


func _orient(mi: MeshInstance3D, pos: Vector3, roll: float, zx: float, zy: float, mirror := false) -> void:
    var basis := _view_basis()
    if absf(roll) > 0.0001:
        basis = basis.rotated(basis.z, roll)
    mi.global_transform = Transform3D(basis, pos)
    mi.scale = Vector3(-zx if mirror else zx, zy, 1.0)


func _view_basis() -> Basis:
    if cam != null and is_instance_valid(cam):
        return cam.global_transform.basis.orthonormalized()
    return Basis.IDENTITY


# 原 2D 像素偏移 → 相机屏幕平面上的世界偏移（dy 向下为正）。
func _screen_offset(dx: float, dy: float) -> Vector3:
    var basis := _view_basis()
    return basis.x * (dx * PIXEL_SIZE) - basis.y * (dy * PIXEL_SIZE)


func _center(node) -> Vector3:
    if node == null or not is_instance_valid(node):
        return Vector3.ZERO
    return node.global_position + Vector3.UP * ANCHOR_H


func _sprite_of(node: Node) -> Sprite3D:
    if node == null or not is_instance_valid(node):
        return null
    var direct := node.get_node_or_null("Sprite")
    if direct is Sprite3D:
        return direct
    if node.get_child_count() > 0:
        var child := node.get_child(0)
        if is_instance_valid(child):
            var nested := child.get_node_or_null("Sprite")
            if nested is Sprite3D:
                return nested
    return null


# ================= 收尾 =================

func _cleanup(p: Dictionary) -> void:
    _bg_free(p)
    _free_sprites(p)
    var ghost = p.get("phantom", null)
    if ghost != null and is_instance_valid(ghost):
        ghost.queue_free()
    p.erase("phantom")
    for spr in p["touched"]:
        if not is_instance_valid(spr):
            continue
        if spr.has_meta("rogue_fx_token") and int(spr.get_meta("rogue_fx_token")) == int(p["id"]):
            spr.position = Vector3.ZERO
            spr.scale = Vector3.ONE
            spr.remove_meta("rogue_fx_token")
    p["touched"].clear()


func _free_sprites(p: Dictionary) -> void:
    for spr in p["sprites"]:
        if is_instance_valid(spr):
            spr.queue_free()
    p["sprites"].clear()
