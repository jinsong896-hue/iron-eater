class_name EnemyBase
extends CharacterBody3D
## 敌人基类 —— HD-2D 重构版
## 3D 敌人通用基类：状态机、AI 追踪/风筝/哨兵/突进、远程弹射、闪避、死亡毒雾
## 数据来源：MonsterDB（怪物设计分册第一层 10 种）

# 基础属性
@export var max_hp: float = 100.0
@export var atk: float = 10.0
@export var defense: float = 5.0
@export var move_speed: float = 2.0
@export var attack_range: float = 2.0
@export var detect_range: float = 12.0
@export var attack_interval: float = 1.0
var _base_attack_interval := 1.0   ## 攻击间隔基准（提速类机制还原用）

# AI 行为
enum AIBehavior {
	MELEE_CHASE,   # 近战追击（含缓慢/快速，速度由 move_speed 区分）
	RANGED_KITE,   # 远程风筝（被近身后退）
	SENTRY,        # 固定炮台（不移动，远射程）
	RUSHER,        # 突进（远距冲刺接敌）
	PATROL,
	STATIONARY,    # 旧占位（木桩），等同 SENTRY 但不攻击
}

@export var behavior := AIBehavior.MELEE_CHASE

# 状态
enum EnemyState {
	IDLE,
	DETECT,
	CHASE,
	WINDUP,   # 攻击前摇（可被受击打断）
	ATTACK,
	RECOVER,
	STAGGERED,  # 受击硬直（AI 暂停，velocity 走击退摩擦）
	DASH,   # 突进冲刺中
	DEAD,
}

## 死亡信号（RoomController 计数、LootSystem 掉落都监听它）
signal died(world_position: Vector3)

@export var loot_table: String = ""  ## 掉落表 ID（空 = 默认白装池）
@export var is_elite := false        ## 精英标记：掉落概率走 ELITE_DROP_CHANCE
@export var gold_min := 3
@export var gold_max := 12

# 第一层扩展属性（MonsterDB 应用）
var monster_id := ""          ## 怪物 ID（显示名查询用）
var monster_name := ""        ## 显示名
var dodge_pct := 0.0          ## 闪避率（0~1）
var is_ranged := false        ## 远程怪（攻击走弹射）
var kite_range := 5.0         ## 风筝后退触发距离
var dash_range := 0.0         ## 突进触发距离（0=不突进）
var death_poison := false     ## 死亡释放毒雾
var body_scale := 1.0         ## 体型缩放
## 碰撞体（见 _create_collision；投射物命中依赖它存在）
var _collision: CollisionShape3D = null

## 突进类（分册 4.6 猎犬家族）的默认突进距离，按**阶段**取（阶段 1~4）。
##
## 为什么要这份兜底：`dash_range` 原本**只**从 `special.dash_range` 读，
## 而 `MonsterDB._special_for()` 只映射 6 个机制、其余一律返回
## `{"mechanic": mech}`——没有任何地方为基础怪写过这个键。
## 后果是 4 只猎犬 + 虚空猎手虽然 `ai=rusher`，`dash_range` 恒为 0，
## `_state_chase` 的突进分支永不进入，连带挂在突进结束点上的
## `dash_slow_trap` / `dash_lava_trail` / `dash_root` / `long_dash_root`
## 四个机制触发 0 次。
##
## 数值取分册 4.6 表格原文：突进距离 2 / 2.5 / 3 / 4 米（阶段一~四）。
## 放在这里而不是 `_special_for`，是因为本文件已持有 `behavior`，
## 且 `apply_monster_config` 对 `mech` 字符串是无状态分派的。
const DASH_RANGE_BY_PHASE := [2.0, 2.5, 3.0, 4.0]

# —— 怪物机制（分册第 4/5 章；本轮实现「自爆/分裂/召唤」三种）——
var death_explode := false    ## 死亡自爆（带前摇，期间被打死则提前引爆）
var explode_damage := 40.0    ## 自爆伤害
var explode_radius := 3.0     ## 自爆范围（米）
var death_split := false      ## 死亡分裂为小型同类
var split_count := 2          ## 分裂数量
var summon_spec: Dictionary = {}   ## 召唤配置 {id,count,chance}
var affixes: Array = []       ## 词缀 id 列表（数值型已作用到属性，其余待后续系统）
var buffs = null              ## BuffHolder：词条与元素叠层容器（_ready 创建）
var attack_element := -1      ## 攻击附带的元素（ElementDefs.Elem；-1 = 纯物理）
## 元素抗性（分册 7.10：「法术伤害仅受极少数怪物自带抗性减免」）。
## 格式 {"fire": 0.6, "frost": 0.35}，键为 ElementDefs 的 key。
## 玩家侧「元素穿透」词条就是拿来削这个值的（见 DamagePipeline.elemental_attack）。
var elem_resist: Dictionary = {}

# —— 分册第 5/6 章专属机制（本轮落地「状态/属性类」8 个）——
var mech := ""                ## 本怪的机制标记（来自 MonsterDB 的 special 标记名）
var true_damage := false      ## 混沌利刃：攻击无视护甲（真实伤害）
var armor_plates := 0.0       ## 矿晶甲虫：常驻护甲减伤，累计受伤后碎裂归零
var armor_break_at := 0.0     ## 护甲碎裂阈值（累计伤害）
var armor_absorbed := 0.0     ## 已累计吸收的伤害
var rage_per_hit := 0.0       ## 虚无守卫：每次受击自身伤害 +X%（可叠层）
var rage_max_stacks := 0      ## 叠层上限
var _rage_stacks := 0
var _base_atk := 0.0          ## 激怒加成基准（避免反复自乘）
var _ash_timer := 0.0         ## 灰烬形态剩余（结束时还原闪避与移速）

# —— 分册第 5/6 章「光环与区域」机制（本轮落地 4 个）——
var zone_on_attack: Dictionary = {}   ## 攻击后在原地留区域（毒腺蛙）
var aura_interval := 0.0              ## 周期性光环间隔（秒）；0 = 无
var aura_spec: Dictionary = {}        ## 光环参数
var trail_spec: Dictionary = {}       ## 突进时沿途留轨迹（熔岩猎犬）
var _aura_timer := 0.0
var _trail_accum := 0.0

# —— 攻击/突进附加效果（分册 4.x / 5.x）——
var melee_haste_range := 0.0     ## 被近身触发提速的距离（骸骨弓手）
var melee_haste_mult := 1.0      ## 提速倍数
var melee_haste_seconds := 0.0
var _melee_haste_used := false   ## 每场战斗仅 1 次
var _melee_haste_timer := 0.0
var enrage_below_pct := 0.0      ## 低血量激怒阈值（狂乱囚徒）
var enrage_atk_pct := 0.0
var _enrage_applied := false
var hit_atk_pct := 0.0           ## 命中叠攻（狂怒恶魔）
var hit_atk_max := 0
var _hit_atk_stacks := 0
var hit_healcut_seconds := 0.0   ## 命中使玩家受治疗降低（虚空狂战士）
var trap_slow_buff := ""         ## 突进后减速陷阱的词条 id
var dash_range_mult := 1.0       ## 突进距离倍数（虚空猎犬）
var hit_root_seconds := 0.0      ## 命中定身（虚空猎犬）
var dash_stun_seconds := 0.0     ## 突进未命中后的自我硬直（狱卒猎犬，0.5 秒）
var hit_split_count := 0         ## 受击分裂数量（墓穴蝙蝠）
var _hit_split_used := false
var hit_dodge_bonus := 0.0       ## 受击后闪避加成（硫磺蝙蝠）
var hit_dodge_seconds := 0.0
var _hit_dodge_timer := 0.0
var hit_slow_buff := ""          ## 命中减速词条（硫磺幽魂）

# —— 传送/位移 · 潜伏 · 护盾（分册 4.x / 5.x / 6.x）——
var teleport_behind := false     ## 闪避成功后瞬移到玩家背后（虚空蝠群）
var teleport_after_shot := 0.0   ## 射击后瞬移距离（熵能幽灵，3 米）
var hit_swap_positions := false  ## 命中后与玩家交换位置（熵能幽灵，≤8 米）
var stealth_always := false      ## 常态隐身（暗影潜伏者，半透明）
var _reveal_timer := 0.0         ## 临时显形剩余（受击/攻击后）
var ambush := false              ## 潜伏于地面，靠近突袭（湿地伏击者）
var ambush_range := 3.0
var ambush_damage_pct := 2.0     ## 突袭伤害倍率（分册「高伤害」）
var _ambush_armed := true        ## 是否处于潜伏态
var shield_on_timer := 0.0       ## 每 N 秒生成护盾（暗影哨兵，20 秒）
var shield_amount := 0.0         ## 护盾吸收量（200）
var _shield := 0.0               ## 当前护盾值
var _shield_cd := 0.0
var stealth_exit_bonus := 0.0    ## 退出隐身时突袭伤害加成（+50%）
var _stealth_bonus_ready := false
var pulse_invuln := false        ## 脉冲期间自身无敌（熔炉核心）
var _pulse_timer := 0.0          ## 无敌剩余
var gravity_pull := false        ## 周期性全屏引力（扭曲巨兽）
var gravity_pull_seconds := 0.0  ## 引力持续时长（虚空巨兽，2 秒）；0 = 常驻
var gravity_pull_dps := 0.0      ## 引力期间每秒伤害（虚空巨兽，30）
var _pull_timer := 0.0           ## 引力剩余时长
var _pull_tick := 0.0            ## 引力伤害的每秒累加器

# —— 召唤 · 死亡区域变体 · 弹道变体（分册 4.x / 5.x）——
var pierce_every := 0            ## 每 N 次射击发射穿透箭（符文哨兵，3）
var _shot_count := 0
var dodge_teleport := false      ## 闪避成功后瞬移到玩家背后并强化下次攻击
var dodge_break := false         ## 闪避成功后破除玩家闪避（虚空魅影）
var _next_hit_bonus := 0.0       ## 下次攻击伤害加成（瞬移后的突袭）
var void_echo := false           ## 射击后产生虚空回响区域（减速+伤害）
# 死亡区域变体：由 death_poison 的具体形态决定
enum DeathZone { NONE, POISON, SULFUR, ENTROPY, BIG_POISON }
var death_zone := DeathZone.NONE
var melee_knockback := 0.0    ## 石翼蝙蝠：命中击退玩家
## 「强壮」词缀的击退倍率（`AffixDB.apply` 写入 monster dict，此处读入）。
## 乘在 melee_knockback 上——没有这个字段时，词缀写进 dict 也没人读，
## 表现为"强壮只加攻击、不提升击退"。
var knockback_mult := 1.0
## 词缀·复仇：受击时按此比例反伤给来源（0 = 无）
var affix_revenge_pct := 0.0
## 词缀·吸血：造成伤害时按此比例回血（0 = 无）
var affix_lifesteal_pct := 0.0
## 词缀·燃烧：命中时给玩家挂灼烧（0 = 无）
var affix_burn := false
## 词缀·冰冻：命中时给玩家叠冰元素层（false = 无）
var affix_freeze := false
## 词缀·虚空：命中时与玩家交换位置（false = 无）
var affix_void := false
## 词缀·不朽：低血触发免伤+回血（false = 无）
var affix_immortal := false
## 词缀·混沌：周期性随机改自身属性（false = 无）
var affix_chaos := false
## 不朽已触发过（每只怪只触发一次）
var _immortal_used := false
## 不朽免伤剩余时长
var _immortal_timer := 0.0
## 混沌下次变动的倒计时
var _chaos_timer := 0.0
## 最近一次伤害来源（复仇反伤用）
var _last_attacker: Node3D = null
## 精英标识光环节点
var _elite_ring: MeshInstance3D = null
## 词缀名标签（世界空间 billboard）
var _affix_label: Label3D = null
var hit_mark_seconds := 0.0   ## 熵能浮体：命中标记玩家（秒）
var ash_chance_on_hit := 0.0  ## 灰烬行者：命中后进入灰烬形态的概率
var ash_duration := 0.0
var slow_target_pct := 0.0    ## 时间畸变者：命中减速玩家
var slow_target_seconds := 0.0
var haste_self_pct := 0.0     ## 时间畸变者：自身攻速提升
var haste_self_seconds := 0.0
var _haste_timer := 0.0
var _explode_timer := 0.0     ## 自爆前摇倒计时（>0 表示正在蓄爆）
var _exploding := false
var _dash_timer := 0.0        ## 突进持续时间
var _dash_dir := Vector3.ZERO
## 本次突进是否够到过玩家（狱卒猎犬「突进失败」判定用）
var _dash_hit := false
var rng := RandomNumberGenerator.new()

# —— 9-5 虚空吞噬者「吞噬成长」——
## 每次击杀（**含其他怪物**）恢复的血量比例
var devour_heal_pct := 0.0
## 每次击杀的伤害增幅（在 `_base_atk` 上累乘，避免逐次复利叠加）
var devour_atk_pct := 0.0
## 每次击杀的体型增幅
var devour_scale_pct := 0.0
## 已吞噬数量
var _devour_stacks := 0
## 死亡时是否需要广播（有吞噬者在场时才发信号，省掉每只怪一次全表查找）
var _broadcast_death := false

## Boss 通用机制（阶段转换/护盾破防/场地/召唤）。
## 用无类型声明避免 enemy_base ↔ boss_mechanics 的解析期循环依赖
## （BossMechanics 要读本类的字段，本类要调它的 tick）。
var boss_mech = null

var _current_state := EnemyState.IDLE
var _hp: float
var _attack_timer := 0.0
var _player  # Player（动态类型：避免 --script 测试模式下 class_name 编译依赖）
var _visual_color := Color(0.8, 0.2, 0.2)
var _model: MeshInstance3D = null          # 模型引用（受击闪红/血条用）
var _flash_timer := 0.0                    # 受击闪红剩余时间
# 头顶血条（受伤后显示）
var _hp_bar: Node3D = null
var _hp_bar_fill: MeshInstance3D = null
var _hp_bar_bg: MeshInstance3D = null

## 受击闪红时长（秒）
const HIT_FLASH_DURATION := 0.18
## 血条尺寸（米）与挂高（乘体型缩放）
const BAR_WIDTH := 1.1
const BAR_HEIGHT := 0.14

# 前摇与硬直
var _windup_timer := 0.0        # 前摇剩余
var _stagger_timer := 0.0       # 硬直剩余
var _knockback_velocity := Vector3.ZERO  # 硬直期间击退速度（摩擦衰减）

## 视觉表现组件（模型/精英光环/词缀标签/血条/受击闪红）。
## 在 `_ready()` 里经 `_setup_visuals()` 装配。
var visuals: EnemyVisuals = null

## 位移机制组件（突进/瞬移/潜伏/引力）。
## 在 `_ready()` 里经 `_setup_movement()` 装配。
var movement: EnemyMovement = null


## 装配视觉组件。**必须在 _create_visual 之前**——后者经它转发。
func _setup_visuals() -> void:
	visuals = EnemyVisuals.new()
	visuals.name = "VisualsComponent"
	add_child(visuals)
	visuals.setup(self)


## 装配位移机制组件
func _setup_movement() -> void:
	movement = EnemyMovement.new()
	movement.name = "MovementComponent"
	add_child(movement)
	movement.setup(self)


func _ready() -> void:
	add_to_group("enemies")
	_hp = max_hp
	rng.randomize()
	_setup_visuals()
	_setup_movement()
	# 词条/元素容器：挂在敌人身上，玩家攻击时读它的易伤与减伤
	if buffs == null:
		buffs = BuffHolder.new(self)
	_find_player()
	visuals.build()
	if stealth_always or stealth_exit_bonus > 0.0:
		movement.apply_stealth_visual()
	# 虚空吞噬者：接上「有单位死亡」广播。
	# 放在 `_ready` 而不是 `apply_monster_config`——后者在 add_child **之前**
	# 调用，那时本节点还不在树里，`get_nodes_in_group` 拿不到东西。
	if devour_heal_pct > 0.0:
		var bus = _event_bus()
		if bus and bus.has_signal("unit_died") \
				and not bus.unit_died.is_connected(_on_unit_died):
			bus.unit_died.connect(_on_unit_died)


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	# 隐身中的玩家不成为目标（装备参考2：暗影步/烟雾弹）。
	# 这是隐身的**核心效果**——只是半透明不算隐身，敌人照打就没意义。
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.has_method("is_stealthed") and bool(p.call("is_stealthed")):
			continue
		_player = p
		return
	# 全部玩家都隐身 → 清空目标（敌人转 IDLE 游荡）
	_player = null


## 装配词缀的战斗钩子（分册 7.2）。
##
## **为什么是"直接改字段/置标志"而不是挂 stat 词条**：敌人没有 AttributeSystem
##（见下方 eff_atk 附近的注释），`BuffHolder._sync_modifier` 会因找不到
## `add_modifier` 而静默早退。所以词缀只能落在敌人自己的字段上。
##
## 数值型（快速/强壮）已由 `AffixDB.apply` 写进 monster dict 并在
## `apply_monster_config` 里读入；这里只处理需要战斗钩子的 7 种。
func _apply_affixes() -> void:
	for id in affixes:
		_apply_affix(str(id))


func _apply_affix(id: String) -> void:
	match id:
		"burn":
			affix_burn = true
		"freeze":
			affix_freeze = true
		"revenge":
			# 策划 7.2「受击一定比例反伤」——数值自定（分册只给效果示例）
			affix_revenge_pct = AFFIX_REVENGE_PCT
		"immortal":
			affix_immortal = true
		"lifesteal":
			affix_lifesteal_pct = AFFIX_LIFESTEAL_PCT
		"void":
			affix_void = true
		"chaos":
			affix_chaos = true
			_chaos_timer = AFFIX_CHAOS_INTERVAL
		_:
			pass   # 数值型词缀（fast/strong）已由 AffixDB 处理


## 词缀数值（分册只给「效果示例」不给数值，故按威胁强度自定）
const AFFIX_REVENGE_PCT := 0.15      ## 复仇：反伤 15%
const AFFIX_LIFESTEAL_PCT := 0.20    ## 吸血：伤害的 20% 回血
const AFFIX_IMMORTAL_THRESHOLD := 0.30  ## 不朽：血量低于 30% 触发
const AFFIX_IMMORTAL_HEAL_PCT := 0.15   ## 不朽：回复 15% 最大生命
const AFFIX_IMMORTAL_SHIELD_TIME := 2.5 ## 不朽：免伤 2.5 秒
const AFFIX_CHAOS_INTERVAL := 6.0    ## 混沌：每 6 秒变动一次


## 词缀·复仇：把本次伤害的一部分打回来源。
## 镜像玩家侧的 `_reflect_damage`（player.gd）——那边是"受到近战伤害时反弹"
## 的装备词条，这里是敌人词缀，语义相同、方向相反。
##
## **签名要与玩家的 take_damage 对齐**：玩家侧是
## `take_damage(amount, from)`（只有 2 个参数），传 3 个会报
## "Expected 2 argument(s)" 并**静默反伤失败**——实测就是这么发现的。
func _reflect_to(attacker: Node3D, amount: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var back := amount * affix_revenge_pct
	if back <= 0.0 or not attacker.has_method("take_damage"):
		return
	attacker.call("take_damage", back, self)
	var bus = _event_bus()
	if bus:
		bus.damage_popup.emit(attacker.global_position, back, "aoe")


## 词缀·不朽：短暂免伤 + 回血（每只怪一次）
func _trigger_immortal() -> void:
	_immortal_used = true
	_immortal_timer = AFFIX_IMMORTAL_SHIELD_TIME
	_hp = minf(_hp + max_hp * AFFIX_IMMORTAL_HEAL_PCT, max_hp)
	visuals.update_health_bar()
	var bus = _event_bus()
	if bus:
		bus.damage_popup.emit(global_position, max_hp * AFFIX_IMMORTAL_HEAL_PCT, "heal")
		bus.message.emit("%s 触发不朽——短时间内无法造成伤害" % monster_name)


## 词缀·吸血：按造成的伤害回血（策划 7.2「造成伤害时回复自身」）。
## **不能复用玩家的 `_lifesteal_heal`**——那个走 GameManager.attributes.heal()，
## 而敌人没有 AttributeSystem。直接改 _hp 才是对的。
func _affix_lifesteal(amount: float) -> void:
	if affix_lifesteal_pct <= 0.0 or amount <= 0.0:
		return
	var before := _hp
	_hp = minf(_hp + amount * affix_lifesteal_pct, max_hp)
	if _hp > before:
		visuals.update_health_bar()


## 词缀·混沌：周期性随机改自身属性（策划 7.2「随机增益/减益组合，不可预测性」）。
## 策划未给具体表，按"改属性"实现——每次随机挑一项增减。
## 有策划表后只需替换这个函数体。
func _tick_chaos(delta: float) -> void:
	_chaos_timer -= delta
	if _chaos_timer > 0.0:
		return
	_chaos_timer = AFFIX_CHAOS_INTERVAL
	var roll := rng.randi() % 3
	match roll:
		0:
			atk = maxf(atk * (1.0 + rng.randf_range(-0.2, 0.3)), 1.0)
		1:
			move_speed = maxf(move_speed * (1.0 + rng.randf_range(-0.2, 0.3)), 0.5)
		2:
			attack_interval = maxf(
				attack_interval * (1.0 + rng.randf_range(-0.2, 0.3)), 0.5)


## 从 MonsterDB 字典应用配置（刷怪用）
func apply_monster_config(m: Dictionary) -> void:
	if m.is_empty():
		return
	monster_id = str(m.get("id", ""))
	monster_name = str(m.get("name", ""))
	max_hp = float(m.get("hp", 100))
	atk = float(m.get("atk", 10))
	defense = float(m.get("defense", 5))
	# 移速：玩家基准 4.0 m/s × 百分比
	move_speed = 4.0 * float(m.get("speed_pct", 50)) / 100.0
	# 攻击元素（分册 7.x）：该怪的攻击会给目标叠对应元素层数。
	# 表里用字符串键（"fire"/"poison"…），未标则为纯物理。
	attack_element = ElementDamage.elem_from_key(str(m.get("element", "")))
	# 元素抗性（稀疏表，多数怪为空）
	var er = m.get("elem_resist", {})
	elem_resist = er if er is Dictionary else {}
	attack_interval = float(m.get("attack_interval", 3.0))
	_base_attack_interval = attack_interval
	# 「强壮」词缀的击退倍率（AffixDB.apply 写入；默认 1.0 = 无修正）
	knockback_mult = float(m.get("knockback_mult", 1.0))
	dodge_pct = float(m.get("dodge_pct", 0.0))
	body_scale = float(m.get("scale", 1.0))
	# 金币按血量档位（血厚值钱：飞行/闪避怪低、高血怪高）
	var hp := float(m.get("hp", 100))
	gold_min = int(maxi(3, hp / 25.0))
	gold_max = gold_min + 8
	if bool(m.get("is_boss", false)):
		gold_min = 50
		gold_max = 120

	var special: Dictionary = m.get("special", {})
	death_poison = special.get("death_poison", false)
	# 死亡区域形态（分册 4.2 毒系四阶段的递进，数值取原文）
	# 死亡区域形态交给 _apply_mechanic 按 mech 装配（机制名在 mech 字段，
	# 不在 special 里——death_sulfur/death_entropy 在 _special_for 中未映射）
	kite_range = special.get("kite_range", 5.0)
	dash_range = special.get("dash_range", 0.0)
	# 死亡自爆（矿道自爆者）：范围伤害 + 前摇（前摇期间被打死则提前引爆）
	death_explode = special.get("death_explode", false)
	explode_damage = float(special.get("explode_damage", 40.0))
	explode_radius = float(special.get("explode_radius", 3.0))
	# 死亡分裂（水孢行者 / 混沌幼蛛）：分裂成 N 只小型同类
	death_split = special.get("death_split", false)
	split_count = int(special.get("split_count", 2))
	# 召唤小怪（僵尸各阶段）
	summon_spec = special.get("summon", {})

	# —— Boss 机制参数（BossDB 经 _special_of 映射而来）——
	# 这些原语在普通怪上也有使用，此处按 special 键直接装配，
	# 使「BossDB 声明机制」到「实际行为」的链路闭合。
	if special.has("stealth_always"):
		stealth_always = bool(special["stealth_always"])
		# 隐身怪现身时给突袭加成（策划对"隐身突袭"的共性表达）
		if stealth_always:
			stealth_exit_bonus = 0.5
	if special.has("ambush"):
		ambush = bool(special["ambush"])
		ambush_range = float(special.get("ambush_range", 3.0))
		ambush_damage_pct = float(special.get("ambush_damage_pct", 2.0))
	if special.has("slow_target_pct"):
		slow_target_pct = float(special["slow_target_pct"])
		slow_target_seconds = float(special.get("slow_target_seconds", 3.0))
	if special.has("haste_self_pct"):
		haste_self_pct = float(special["haste_self_pct"])
		haste_self_seconds = float(special.get("haste_self_seconds", 3.0))
	if special.has("healcut_on_hit"):
		hit_healcut_seconds = float(special["healcut_on_hit"])
	if special.has("knockback_on_hit"):
		melee_knockback = float(special["knockback_on_hit"])
	if special.has("aura_spec"):
		aura_spec = special["aura_spec"]
		aura_interval = float(special.get("aura_interval", 10.0))
	if special.has("zone_on_attack"):
		zone_on_attack = special["zone_on_attack"]
	if special.has("teleport_after_shot"):
		teleport_after_shot = float(special["teleport_after_shot"])
	if special.has("shield_amount"):
		shield_amount = float(special["shield_amount"])
		shield_on_timer = float(special.get("shield_on_timer", 20.0))
	if special.has("gravity_pull"):
		gravity_pull = true
		gravity_pull_seconds = float(special.get("gravity_pull_seconds", 0.0))
		gravity_pull_dps = float(special.get("gravity_pull_dps", 0.0))
	if special.has("devour_grow"):
		devour_heal_pct = float(special.get("devour_heal_pct", 0.20))
		devour_atk_pct = float(special.get("devour_atk_pct", 0.10))
		devour_scale_pct = float(special.get("devour_scale_pct", 0.10))
		_broadcast_death = true   # 死亡时发信号，供吞噬者感知

	# 词缀（分册第 7 章）：数值型由 AffixDB.apply 写进 monster dict，
	# 非数值型在这里装配战斗钩子。
	affixes = m.get("affixes", [])
	_apply_affixes()

	# 专属机制（分册第 5/6 章）：按机制标记装配，数值取自分册原文
	_apply_mechanic(str(m.get("mech", "")))

	# AI 类型映射
	match str(m.get("ai", "melee")):
		"kite":
			behavior = AIBehavior.RANGED_KITE
			is_ranged = true
			attack_range = float(m.get("attack_range", 8.0))
		"sentry":
			behavior = AIBehavior.SENTRY
			is_ranged = true
			attack_range = float(m.get("attack_range", 15.0))
			detect_range = float(m.get("attack_range", 15.0))
		"rusher":
			behavior = AIBehavior.RUSHER
			# 突进距离：优先用 special 显式声明的（BossDB 走这条），
			# 否则按阶段取分册 4.6 的兜底值。
			# **没有这段兜底，猎犬家族永远不会突进**（见 DASH_RANGE_BY_PHASE 注释）。
			if dash_range <= 0.0:
				var ph: int = clampi(int(m.get("phase", 1)), 1, DASH_RANGE_BY_PHASE.size())
				dash_range = float(DASH_RANGE_BY_PHASE[ph - 1])
		"flyer_melee":
			behavior = AIBehavior.MELEE_CHASE  # 飞行近战＝追击（飞行视觉后续做）
		"flyer_ranged":
			behavior = AIBehavior.RANGED_KITE
			is_ranged = true
			attack_range = float(m.get("attack_range", 10.0))
		_:
			behavior = AIBehavior.MELEE_CHASE


## 装配怪物专属机制参数（实现已拆到 EnemyMechanics）。
##
## **字段留在本类**：机制字段（aura_spec / summon_spec / death_zone…）
## 被行为函数与测试直接读写，故参数表按鸭子类型写 `e.xxx` 而不搬走字段。
func _apply_mechanic(m: String) -> void:
	mech = m
	EnemyMechanics.apply(self, m)


## 周期性光环（炎魔幼体的火焰光环 / 沼泽巨人的水波）
func _tick_aura(delta: float) -> void:
	if aura_interval <= 0.0 or aura_spec.is_empty():
		return
	_aura_timer -= delta
	if _aura_timer > 0.0:
		return
	_aura_timer = aura_interval
	# 熔炉核心：脉冲期间自身无敌（需打掉护盾发生器才能破，本版简化）
	if pulse_invuln:
		_pulse_timer = float(aura_spec.get("duration", 3.0))
	# 虚空巨兽：引力的「持续 2 秒」由这里开窗，伤害由 _pull_player 按秒结算
	if gravity_pull and gravity_pull_seconds > 0.0:
		_pull_timer = gravity_pull_seconds
		_pull_tick = 0.0
	var spec := aura_spec.duplicate()
	spec["position"] = global_position
	# 跟随型光环（熔岩巨兽的熔岩地面）：挂到自身身上，随移动而移动。
	# `follow` 传的是**节点引用**而非布尔——DamageZone 靠 `_follows` 标记
	# 判断跟随关系（它不能用 `follow != null`，见该类注释）。
	var follow_self := bool(spec.get("follow", false))
	spec.erase("follow")
	if follow_self:
		spec["follow"] = self
		spec["duration"] = -1.0   # 跟随型无独立寿命，随施法者一起消失
	# 水波是「减速」而非伤害：给区域内玩家挂减速词条（分册 4-18，40%）
	if str(spec.get("slow_buff", "")) != "":
		_apply_pulse_slow(str(spec["slow_buff"]), float(spec.get("radius", 5.0)))
	var parent := get_parent()
	if parent != null:
		DamageZone.spawn(spec, parent)


## 水波：给半径内的玩家挂减速词条
func _apply_pulse_slow(buff_id: String, radius: float) -> void:
	if _player == null:
		return
	if global_position.distance_to(_player.global_position) > radius:
		return
	var pb = _player.get("buffs")
	if pb != null:
		pb.apply(buff_id, "monster")


## 攻击后留下区域（毒腺蛙的毒液区）
func _spawn_attack_zone() -> void:
	if zone_on_attack.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return
	var spec := zone_on_attack.duplicate()
	spec["position"] = global_position
	DamageZone.spawn(spec, parent)


## 突进沿途留轨迹（熔岩猎犬）
func _tick_trail(delta: float) -> void:
	if trail_spec.is_empty():
		return
	_trail_accum += delta
	if _trail_accum < 0.25:   # 每 0.25 秒留一个，避免过密
		return
	_trail_accum = 0.0
	var parent := get_parent()
	if parent == null:
		return
	var spec := trail_spec.duplicate()
	spec["position"] = global_position
	DamageZone.spawn(spec, parent)


## 碰撞体 —— **此前完全缺失**。
##
## EnemyBase extends CharacterBody3D 且每帧调 move_and_slide()，但整个类
## 没有任何 CollisionShape3D：CharacterBody3D 没有形状时物理引擎不参与
## 碰撞，于是三件事同时坏掉——
##   ① 投射物（Projectile 是 Area3D，靠 body_entered 命中）永远打不中敌人；
##   ② 敌人不与墙碰撞，能穿墙；
##   ③ 敌人之间、敌人与玩家互不阻挡。
## 实测症状即用户报的「大部分技能使用后没有实际效果」（投射物类技能全废）。
##
## 层位：**占第 2 层（ENEMY_LAYER）**，mask 打开第 1 层（世界/墙）与
## 第 2 层（同类）——策划要求"敌人相互碰撞并且和墙碰撞"。
##
## 玩家侧**刻意不动**：player.tscn 的 layer/mask 都是 Godot 默认的第 1 层，
## 因此玩家与敌人**互不阻挡**（穿过去），这是本作有意的设计——
## 贴脸时不会被怪堆卡住。要改成互相阻挡需同时改玩家的 mask，
## 但那样会引出"玩家推不动怪、怪也推不动玩家"的顶死问题，需另开一轮。
##
## 已知限制：无寻路（敌人直线追击）。撞墙时 move_and_slide 会沿墙面滑动，
## 一般能绕出去；但凹角处可能短暂顶住。这是"加碰撞"的固有代价，
## 彻底解决要靠 NavigationAgent3D，不在本次范围。
func _create_collision() -> void:
	if _collision != null:
		return
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4 * body_scale
	shape.height = maxf(1.8 * body_scale, shape.radius * 2.0 + 0.01)
	_collision.shape = shape
	_collision.position = Vector3(0, 0.9 * body_scale, 0)
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER
	add_child(_collision)


## 物理层：1 = 世界/墙（wall_builder 的 StaticBody3D 默认层），
## 2 = 敌人。玩家自己占第 1 层（player.tscn 未改层，用 Godot 默认值）。
const WORLD_LAYER := 1
const ENEMY_LAYER := 2


## 视觉表现（模型/精英光环/词缀标签/血条/受击闪红）已拆到 EnemyVisuals。
##
## **字段留在本类**（_model / _hp_bar / _elite_ring / _affix_label /
## _flash_timer / _visual_color）——测试直接读它们，故组件按鸭子类型写
## `owner_enemy.xxx`。血条的三个陷阱见 enemy_visuals.gd 文件头。
func _create_visual() -> void:
	visuals.build()


## 按当前血量刷新血条（转发）
func _update_health_bar() -> void:
	visuals.update_health_bar()


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	# Boss 通用机制推进（阶段/场地/召唤；非 Boss 时为 null）
	if boss_mech != null and boss_mech.has_method("tick"):
		boss_mech.call("tick", delta)

	# 机制计时器：时间畸变者的攻速加成、灰烬行者的灰烬形态
	if _haste_timer > 0.0:
		_haste_timer = maxf(_haste_timer - delta, 0.0)
	if _ash_timer > 0.0:
		_ash_timer = maxf(_ash_timer - delta, 0.0)
		if _ash_timer == 0.0:
			# 还原灰烬形态加成（闪避 -50%、移速 ÷1.3），避免永久叠加
			dodge_pct = maxf(dodge_pct - 0.5, 0.0)
			move_speed /= 1.3
	_tick_aura(delta)
	_tick_mech_timers(delta)
	movement.tick_stealth_timers(delta)

	# 受击闪红衰减（每帧都要走，包括硬直/死亡前）
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		visuals.tick_flash(delta)

	# 突进推进
	if _current_state == EnemyState.DASH:
		# 引力窗口不因突进而中断：`_pull_player` 只在 CHASE 分支被调，
		# 若不在突进里补一次，正在突进的虚空巨兽会**恰好**在引力生效的
		# 那 2 秒内把拉扯和每秒 30 伤全吞掉（突进期间状态不是 CHASE）。
		movement.pull_player(delta)
		movement.update_dash(delta)
		return

	# 自爆前摇倒计时（蓄爆完成后引爆）
	if _exploding:
		_explode_timer -= delta
		if _explode_timer <= 0.0:
			_do_explode()
			if is_instance_valid(self):
				die()
			return
		return

	# 受击硬直：AI 暂停，走击退摩擦位移
	if _current_state == EnemyState.STAGGERED:
		_update_stagger(delta)
		return

	if _player == null:
		_find_player()
		if _player == null:
			return

	# 词条/元素推进：DOT 结算 + 元素衰减 + 控制判定
	if buffs != null:
		var tick_out: Dictionary = buffs.tick(delta)
		var dot: float = float(tick_out.get("dot", 0.0))
		if dot > 0.0:
			take_damage(dot)
			if not is_instance_valid(self) or _current_state == EnemyState.DEAD:
				return
		# 硬控（冰冻/麻痹/眩晕/定身）：期间不移动不攻击，被击退则继续位移
		if buffs.is_controlled():
			_update_stagger(delta)
			return

	match _current_state:
		EnemyState.IDLE:
			_state_idle()
		EnemyState.CHASE:
			if movement.try_ambush():
				return
			movement.pull_player(delta)
			_check_melee_haste()
			_state_chase(delta)
		EnemyState.WINDUP:
			_state_windup(delta)
		EnemyState.ATTACK:
			_state_attack()
		EnemyState.DEAD:
			pass


func _state_idle() -> void:
	if _player == null:
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist <= detect_range:
		_current_state = EnemyState.CHASE


func _state_chase(delta: float) -> void:
	if _player == null:
		return
	var dist: float = global_position.distance_to(_player.global_position)

	# 突进触发：距离在 [attack_range, dash_range] 外且冷却好 → 冲刺
	if behavior == AIBehavior.RUSHER and dash_range > 0.0:
		if dist > attack_range + 1.0 and dist < dash_range + 4.0 and _attack_timer <= 0.0:
			movement.start_dash()
			return

	# 进入攻击范围
	if dist <= attack_range:
		# 狱卒猎犬：记下「这一扑够到过玩家」，突进结束时不补硬直（见 _update_dash）。
		# 注意必须在 `movement.start_dash()` 之前判断——`_start_dash` 会把状态置为 DASH，
		# 之后这里就再也看不到「原本是突进态」了。
		if _current_state == EnemyState.DASH:
			_dash_hit = true
		_current_state = EnemyState.ATTACK
		return

	# 超出侦测范围
	if dist > detect_range:
		_current_state = EnemyState.IDLE
		return

	# 风筝：远程怪被近身（< kite_range）→ 后退
	if behavior == AIBehavior.RANGED_KITE and dist < kite_range:
		var away: Vector3 = (global_position - _player.global_position)
		away.y = 0.0
		if away.length_squared() > 0.001:
			velocity = away.normalized() * eff_speed()
			move_and_slide()
		return

	# 哨兵：不移动
	if behavior == AIBehavior.SENTRY:
		return

	# 追踪玩家
	var direction: Vector3 = (_player.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * eff_speed()
	move_and_slide()

	# 朝向玩家
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)


func _state_attack() -> void:
	if _player == null:
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > attack_range:
		_current_state = EnemyState.CHASE
		return

	if _attack_timer > 0.0:
		return

	# 自爆怪：进入前摇不普攻，蓄爆后自爆（分册 5.1，1.5 秒可被打断）
	if death_explode:
		_attack_timer = eff_attack_interval()
		_start_explode_windup()
		return

	# 进入攻击前摇（高伤害怪前摇更长，可被打断）
	_attack_timer = eff_attack_interval()
	_windup_timer = _windup_duration()
	_current_state = EnemyState.WINDUP
	_set_windup_visual(true)


## 前摇时长：普通 0.5s；高伤害（≥35 攻）加长到 1.0s（分册约束）
func _windup_duration() -> float:
	if atk >= 35.0:
		return 1.0
	return 0.5


## 前摇推进：结束才结算伤害；目标脱离范围则取消
func _state_windup(delta: float) -> void:
	if _player == null:
		_cancel_windup()
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > attack_range * 1.4:
		_cancel_windup()
		return
	_windup_timer -= delta
	if _windup_timer <= 0.0:
		_set_windup_visual(false)
		_current_state = EnemyState.ATTACK
		_perform_attack()
		_current_state = EnemyState.CHASE


## 取消前摇（目标脱离/被打断）
func _cancel_windup() -> void:
	_set_windup_visual(false)
	_current_state = EnemyState.CHASE


## 前摇视觉：模型发白光预警
func _set_windup_visual(active: bool) -> void:
	var model := get_node_or_null("Model") as MeshInstance3D
	if model == null:
		return
	var mat := model.material_override as ShaderMaterial
	if mat == null:
		return
	if active:
		ToonMaterial.set_emission(mat, Color(1.0, 0.95, 0.5), 0.8)
	elif not death_poison:
		ToonMaterial.set_emission(mat, Color.BLACK, 0.0)
	else:
		# 毒怪：前摇结束后退回常驻绿光，而不是熄掉
		ToonMaterial.set_emission(mat, Color(0.2, 0.8, 0.2), 0.4)


## 受击硬直推进：AI 暂停，击退速度摩擦衰减
func _update_stagger(delta: float) -> void:
	_stagger_timer -= delta
	velocity = _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	move_and_slide()
	if _stagger_timer <= 0.0:
		_knockback_velocity = Vector3.ZERO
		_current_state = EnemyState.CHASE


func eff_speed() -> float:
	if buffs == null:
		return move_speed
	return move_speed * (1.0 - buffs.total_slow())


## 有效攻击间隔：基础值 ×（1 + 攻速降低）——「迟钝」等词条；也含机制自身的加速
func eff_attack_interval() -> float:
	var interval := attack_interval
	if _haste_timer > 0.0 and haste_self_pct > 0.0:
		interval = interval / (1.0 + haste_self_pct)   # 时间畸变者：攻速 +30%
	if buffs == null:
		return interval
	var down := 0.0
	for id in buffs.active_ids():
		down += float(BuffDefs.params_of(id).get("aspd_down", 0.0))
	return interval / maxf(1.0 - clampf(down, 0.0, 0.8), 0.2)


## 累计护甲减伤（矿晶甲虫：常驻 30%，累计受伤达阈值后碎裂）
## 返回本次额外减伤比例（与词条减伤叠加前，由调用方并入）
func armor_mitigation() -> float:
	return armor_plates if armor_plates > 0.0 else 0.0


## 记录本次实际受到的伤害：护甲累计与碎裂、激怒叠层
func _note_damage_taken(amount: float) -> void:
	# 矿晶甲虫：护甲吸收累计，达阈值后碎裂（减伤失效）
	if armor_plates > 0.0:
		armor_absorbed += amount
		if armor_break_at > 0.0 and armor_absorbed >= armor_break_at:
			armor_plates = 0.0
			armor_absorbed = 0.0
	# 虚无守卫：每受一次攻击伤害 +5%，最多 10 层
	if rage_per_hit > 0.0 and _rage_stacks < rage_max_stacks:
		_rage_stacks += 1
		atk = _base_atk * (1.0 + rage_per_hit * float(_rage_stacks))
	# Boss 机制：阶段转换（血量阈值）与护盾破防
	if boss_mech != null and boss_mech.has_method("on_damaged"):
		boss_mech.call("on_damaged", amount)

# ============================================================
# 9-5 虚空吞噬者：吞噬成长
# ============================================================

## 场上是否还有活着的吞噬者。
## 死者用它决定要不要发 `unit_died`——没有吞噬者时全表查找纯属浪费。

func _has_devourer() -> bool:
	if not is_inside_tree():
		return false
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == self or not is_instance_valid(n):
			continue
		if n.get("devour_heal_pct") != null and float(n.get("devour_heal_pct")) > 0.0:
			return true
	return false


## 有单位死亡：若凶手是自己，就吞掉它（分册 9-5）。
##
## 判定口径：`killer == self` 即「我打死的」，**不区分是玩家助攻还是
## 怪物互殴**——分册原文「每击杀一个单位（包括其他怪物）」正是要这个口径。
## 自杀（凶手是自己）也会触发，因为 `take_damage(from=self)` 的来源就是自己。
func _on_unit_died(victim: Node, killer: Node, _pos: Vector3) -> void:
	if killer != self or victim == self:
		return
	if not is_alive():
		return
	_devour_stacks += 1
	# 回血：按**上限**比例而非当前值，避免残血时吞噬收益递减
	if _hp < max_hp:
		_hp = minf(_hp + max_hp * devour_heal_pct, max_hp)
		visuals.update_health_bar()
	# 伤害：在 `_base_atk` 上累乘，不用 `atk * (1+pct)` 逐次复利
	if devour_atk_pct > 0.0:
		atk = _base_atk * (1.0 + devour_atk_pct * float(_devour_stacks))
	# 体型：连同碰撞体一起放大（只改 body_scale 会让视觉与判定脱节）
	_grow_body(devour_scale_pct)


## 吞噬后的体型增长：视觉与碰撞体同步放大。
##
## 分册只说「增大体型」，未给上限。这里**设 2 倍封顶**——
## 不封顶的话，第 9 层怪多，吞噬者会在几十次击杀后涨成填满房间的怪物，
## 碰撞体撑爆房间。2 倍是保守值，策划若要更夸张改 DEVOUR_SCALE_CAP 即可。
const DEVOUR_SCALE_CAP := 2.0

func _grow_body(pct: float) -> void:
	if pct <= 0.0:
		return
	var next_scale: float = minf(body_scale * (1.0 + pct), DEVOUR_SCALE_CAP)
	if is_equal_approx(next_scale, body_scale):
		return
	body_scale = next_scale
	_resize_body()


## 按当前 body_scale 重建碰撞体与视觉尺寸。
## 与 `_create_collision` / `_create_visual` 用同一套尺寸公式，
## 但**原地改已有的节点**而不是重建——重建会丢材质与血条等子节点。
func _resize_body() -> void:
	if _collision != null and _collision.shape is CapsuleShape3D:
		var cs := _collision.shape as CapsuleShape3D
		cs.radius = 0.4 * body_scale
		cs.height = maxf(1.8 * body_scale, cs.radius * 2.0 + 0.01)
		_collision.position = Vector3(0, 0.9 * body_scale, 0)
	if _model != null and _model.mesh is CapsuleMesh:
		# 只改 mesh 尺寸，**不动 `_model.scale`**——血条/精英环/词缀标签
		# 是 `_model` 的兄弟节点，缩放 `_model` 不会带上它们，
		# 结果会是"身体变大、血条还挂在原来的高度"。
		var cm := _model.mesh as CapsuleMesh
		cm.radius = 0.4 * body_scale
		cm.height = 1.8 * body_scale
		_model.position = Vector3(0, 0.9 * body_scale, 0)
	if _hp_bar != null:
		_hp_bar.position = Vector3(0, 2.15 * body_scale, 0)


## 闪避成功后的位移/隐身效果
func _on_dodged() -> void:
	# 虚空蝠群 / 虚空魅影：闪避成功后瞬移到玩家背后
	if teleport_behind or dodge_teleport:
		movement.teleport_behind_target()
	# 迷雾幽灵：破除玩家闪避（下次命中必中）
	if dodge_break and _player != null:
		var pb = _player.get("buffs")
		if pb != null:
			pb.apply("expose", "monster")
	# 虚空魅影：进入隐身，退出时获得突袭加成
	if stealth_exit_bonus > 0.0:
		movement.apply_stealth_visual()
		_stealth_bonus_ready = true
		_reveal_timer = 3.0


## 虚空回响（熔炉哨兵）：射击点留下减速+伤害区域
func _spawn_void_echo() -> void:
	var parent := get_parent()
	if parent == null:
		return
	DamageZone.spawn({
		"position": global_position, "radius": 2.5, "duration": 3.0,
		"damage": 15.0, "slow_buff": "mire",
		"color": Color(0.5, 0.3, 0.8, 0.4),
	}, parent)


func _perform_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if is_ranged:
		_fire_projectile()
		return

	var player_def := 0.0
	var gm = _game_manager()
	if gm:
		player_def = gm.stat_value("def")
	# 混沌利刃：攻击无视护甲（真实伤害）→ 按 0 防御结算
	if true_damage:
		player_def = 0.0
	# 按攻击元素走对应伤害类型：火/冰/雷/毒 无视护甲（分册 7.1），
	# 土/风 各半，无元素为纯物理
	var result = DamagePipeline.elemental_attack(atk, 1.0, 0.0, player_def, attack_element)
	# 传自身为来源：玩家侧「伤害反弹」词条据此把伤害打回来（分册限定近战）
	#
	# **带元素走 take_elemental_damage**（装备参考2 扩充通道）：
	# 玩家侧「受到元素伤害 -N%」需要知道这次是不是元素伤害。
	# attack_element < 0 时仍走老路径（纯物理，不该被元素抗性减免）。
	if attack_element >= 0 and _player.has_method("take_elemental_damage"):
		_player.call("take_elemental_damage", result.damage, attack_element, self)
	else:
		_player.take_damage(result.damage, self)
	_apply_element_to_player()
	_apply_melee_mechanics()
	# 词缀·吸血：按造成的伤害回血（策划 7.2「考验持续压制能力」）
	_affix_lifesteal(result.damage)
	# 毒腺蛙：攻击后在原地留下毒液区
	_spawn_attack_zone()
	var bus = _event_bus()
	if bus:
		bus.damage_dealt.emit(self, _player, result.damage, _element_key(), false)


## 攻击命中后的专属机制（分册第 5/6 章）
func _apply_melee_mechanics() -> void:
	if _player == null:
		return
	# 石翼蝙蝠：命中击退玩家
	# 乘 knockback_mult 是「强壮」词缀的那一半效果——`AffixDB.apply` 会写这个字段，
	# 但此前**全项目无人读**，所以"强壮提升击退"从未生效过（只有攻击力那半生效）。
	if melee_knockback > 0.0 and _player.has_method("apply_knockback"):
		var dir: Vector3 = (_player.global_position - global_position)
		dir.y = 0.0
		_player.call("apply_knockback",
			dir.normalized() * melee_knockback * knockback_mult)
	# 熵能浮体 / 时间畸变者：给玩家挂词条（时长走词条自身的 duration）
	var pb = _player.get("buffs")
	if pb != null:
		if hit_mark_seconds > 0.0:
			pb.apply("mark", "monster")
		if slow_target_pct > 0.0 and slow_target_seconds > 0.0:
			pb.apply("thorn_slow", "monster")
		# 词缀·燃烧（策划 7.2「攻击附加持续灼烧，考验续航与净化管理」）
		if affix_burn:
			pb.apply("burn", "affix")
		# 词缀·冰冻（策划 7.2「攻击附加减速/冻结，限制走位」）
		# 走寒霜减速而非直接冻结——冻结是硬控，每次命中都触发会变成
		# "被精英粘住就动不了"，远超"限制走位"的设计强度。
		if affix_freeze:
			pb.apply("frost", "affix")
	# 时间畸变者：自身攻速提升
	if haste_self_pct > 0.0 and haste_self_seconds > 0.0:
		_haste_timer = haste_self_seconds
	# 灰烬行者：命中后概率进入灰烬形态（闪避 +50%、移速 +30%）
	if ash_chance_on_hit > 0.0 and rng.randf() < ash_chance_on_hit:
		dodge_pct = minf(dodge_pct + 0.5, 0.9)
		move_speed *= 1.3
		_ash_timer = ash_duration
	# 狂怒恶魔：每次命中自身攻击 +5%（最多 8 层）
	if hit_atk_pct > 0.0 and _hit_atk_stacks < hit_atk_max:
		_hit_atk_stacks += 1
		atk = _base_atk * (1.0 + hit_atk_pct * float(_hit_atk_stacks))
	# 虚空狂战士：命中使玩家受治疗 -50%
	if hit_healcut_seconds > 0.0 and pb != null:
		pb.apply("weakness", "monster")
	# 硫磺幽魂：命中减速玩家
	if hit_slow_buff != "" and pb != null:
		pb.apply(hit_slow_buff, "monster")
	# 虚空猎犬：命中定身 1.5 秒
	if hit_root_seconds > 0.0 and pb != null:
		pb.apply("entangle", "monster")
	# 熵能幽魂：命中后与玩家交换位置
	if hit_swap_positions:
		movement.swap_with_player(8.0)
	# 词缀·虚空（策划 7.2「传送/空间干扰类效果，打乱站位」）。
	# 复用现成的 _swap_with_player，不另造轮子。
	if affix_void:
		movement.swap_with_player(10.0)


## 每帧推进本怪的攻击/突进附加效果计时器
func _tick_mech_timers(delta: float) -> void:
	# 词缀·不朽：免伤计时
	if _immortal_timer > 0.0:
		_immortal_timer = maxf(_immortal_timer - delta, 0.0)
	# 词缀·混沌：周期性随机改属性
	if affix_chaos:
		_tick_chaos(delta)
	if _melee_haste_timer > 0.0:
		_melee_haste_timer = maxf(_melee_haste_timer - delta, 0.0)
		if _melee_haste_timer == 0.0:
			attack_interval = _base_attack_interval
	if _hit_dodge_timer > 0.0:
		_hit_dodge_timer = maxf(_hit_dodge_timer - delta, 0.0)
		if _hit_dodge_timer == 0.0:
			dodge_pct = maxf(dodge_pct - hit_dodge_bonus, 0.0)
	# 狂乱囚徒：低血量激怒（只触发一次）
	if enrage_below_pct > 0.0 and not _enrage_applied and max_hp > 0.0:
		if _hp / max_hp <= enrage_below_pct:
			_enrage_applied = true
			atk = _base_atk * (1.0 + enrage_atk_pct)


## 骸骨弓手：被近身时射速翻倍（每场战斗仅 1 次）
## 在 AI 追击/风筝状态下调用
func _check_melee_haste() -> void:
	if melee_haste_range <= 0.0 or _melee_haste_used or _player == null:
		return
	if global_position.distance_to(_player.global_position) > melee_haste_range:
		return
	_melee_haste_used = true
	attack_interval = _base_attack_interval / maxf(melee_haste_mult, 1.0)
	_melee_haste_timer = melee_haste_seconds


## 本怪攻击元素的字符串键（无元素返回 "physical"，供信号与文案用）
func _element_key() -> String:
	if attack_element < 0:
		return "physical"
	return ElementDefs.elem_name(attack_element)


## 把本怪的攻击元素叠到玩家身上（元素系怪才有；纯物理怪跳过）
## 阈值事件（冰冻/麻痹）转为控制词条挂到玩家。
func _apply_element_to_player() -> void:
	if attack_element < 0 or _player == null:
		return
	var tgt = _player.get("buffs")
	if tgt == null:
		return
	var out: Dictionary = ElementDamage.attack(tgt, attack_element)
	for ev in out.get("events", []):
		var ctrl_id: String = ElementDamage.control_for_event(str(ev))
		if ctrl_id != "":
			tgt.apply(ctrl_id, "element")


## 远程弹射（直线飞行的能量球）
func _fire_projectile() -> void:
	if _player == null:
		return
	var dir: Vector3 = (_player.global_position - global_position).normalized()
	var data := {
		"direction": dir,
		"position": global_position + Vector3(0, 1.2, 0) + dir * 0.6,
		"speed": 8.0,
		"damage": atk,
		"lifetime": attack_range / 8.0 + 0.5,
		"element": _element_key(),
	}
	# 分册第 5/6 章的投射物改造机制
	match mech:
		"bounce_shot":        # 6-19 硫磺元素：火球弹射 2 次 + 弧线轨迹
			data["bounces"] = 2
			data["arc"] = true
			data["arc_height"] = 2.5
		"delayed_bomb":       # 2-12 轨道投弹手：投掷延时炸弹，3 秒后爆炸
			data["fuse"] = 3.0
			data["explode_radius"] = 2.5
			data["explode_damage"] = atk * 1.5
			data["arc"] = true
			data["arc_height"] = 3.5
		"triple_shot":        # 9-2 裂隙射手：三连散射
			for angle in [-0.25, 0.0, 0.25]:
				var d2 := data.duplicate()
				d2["direction"] = dir.rotated(Vector3.UP, angle)
				d2["position"] = global_position + Vector3(0, 1.2, 0) + d2["direction"] * 0.6
				Projectile.spawn(d2, get_parent(), Projectile.TARGET_PLAYER)
			return
		"arrow_explode":      # 4-16 炎骨弓手：箭矢命中后爆炸（范围 2 米，20 伤）
			data["fuse"] = 0.05          # 命中即爆（极短引信）
			data["explode_radius"] = 2.0
			data["explode_damage"] = 20.0
		"arrow_split":        # 4-16 虚空弓手：箭矢分裂为 2 支（各 50% 伤害）
			data["split_on_hit"] = 2
			data["split_damage_pct"] = 0.5
			data["split_spread"] = 0.35
		"shot_fire_zone":     # 4-4 熔炉哨兵：射击点留下火焰区域（每秒 20 伤，4 秒）
			data["zone_on_land"] = {
				"radius": 2.0, "duration": 4.0, "damage": 20.0,
				"color": Color(1.0, 0.4, 0.1, 0.45),
			}
		"backstep_on_shot":   # 4.8 鬼火灵体：射击后后撤拉开距离
			var back: Vector3 = -dir
			global_position += back * 1.5
	# 符文哨兵：每 N 次射击发射穿透箭
	_shot_count += 1
	if pierce_every > 0 and _shot_count % pierce_every == 0:
		data["pierce_count"] = 3
	Projectile.spawn(data, get_parent(), Projectile.TARGET_PLAYER)
	# 熔炉哨兵：射击点留下虚空回响（减速 30% + 每秒 15 伤）
	if void_echo:
		_spawn_void_echo()
	# 熵能幽灵：射击后瞬移 3 米
	if teleport_after_shot > 0.0:
		movement.blink_after_shot(teleport_after_shot)


# ============================================================
# 属性接口（BuffHolder 消费）
# ============================================================
## 敌人**没有 AttributeSystem**（属性系统是玩家专有，见 data/attributes）。
## 但 BuffHolder 会用这两个方法读宿主的攻/法强来结算 DOT——
## 不提供的话 DOT 恒为 0（实测：给敌人叠 20 层毒蚀，每秒伤害为 0）。
##
## 敌人不受 stat 型词条影响（没有属性层可挂），这是**有意的**：
## 敌人强度由 MonsterDB 数值 + 难度倍率决定，不该被词条二次改写。
## 故这里只补「读」的接口，不提供 add_modifier——`_sync_modifier` 会
## 因此早退，与既有行为一致。

func eff_atk() -> float:
	return atk


func eff_ap() -> float:
	return atk * 0.5   # 敌人无独立法强字段，按攻击力折半近似


## `from`：伤害来源（可选）。**只有「复仇」词缀用得到**——它需要知道
## "谁打了我"才能把伤害按比例反打回去。默认 null 保持向后兼容，
## 现有不传来源的调用点（召唤物自伤、环境伤害等）行为不变。
func take_damage(amount: float, _is_crit: bool = false,
		knockback: Vector3 = Vector3.ZERO, from: Node3D = null) -> void:
	# 熔炉核心：脉冲期间自身无敌
	if _pulse_timer > 0.0:
		return
	# 记下伤害来源：词缀·复仇的反伤、以及虚空吞噬者的「谁杀的」判定都要用。
	# **必须在各种 early return 之前记**——否则被闪避/被护盾挡掉的那些次
	# 不会留下来源，最后致命一击恰好被挡时凶手就丢了。
	if from != null and is_instance_valid(from):
		_last_attacker = from
	# 词缀·不朽：低血时短暂免伤（策划 7.2「血量低于阈值时短暂免伤/回血，
	# 需要爆发斩杀或机制处理」）。**每只怪只触发一次**——否则低血时
	# 无限免伤会变成打不死的怪。
	if _immortal_timer > 0.0:
		return
	# 闪避判定（迷雾幽灵 30%）
	if dodge_pct > 0.0 and rng.randf() < dodge_pct:
		var bus0 = _event_bus()
		if bus0:
			bus0.damage_popup.emit(global_position, 0.0, "dodge")
		_on_dodged()
		return
	# 暗影哨兵：护盾先吸收伤害，未破盾则本次不受伤
	if _shield > 0.0:
		var absorbed := minf(_shield, amount)
		_shield -= absorbed
		amount -= absorbed
		if amount <= 0.0:
			return
	# 隐身怪受击：显形 3 秒
	if stealth_always or stealth_exit_bonus > 0.0:
		_reveal_timer = 3.0
		ToonMaterial.set_model_transparency(_model, 1.0)
	# 矿晶甲虫：常驻护甲减伤（在调用方已算的防御减伤之上再叠一层）
	if armor_plates > 0.0:
		amount = amount * (1.0 - armor_plates)
	# 词缀·复仇：受击反伤（策划 7.2「受击一定比例反伤，迫使玩家控制输出节奏」）。
	# 在扣血之前算——反伤基于"这次挨了多少"，与自身是否被打死无关。
	if affix_revenge_pct > 0.0:
		_reflect_to(from, amount)
	# 词缀·不朽：血量将跌破阈值时触发一次免伤 + 回血
	if affix_immortal and not _immortal_used \
			and (_hp - amount) / maxf(max_hp, 0.001) < AFFIX_IMMORTAL_THRESHOLD:
		_trigger_immortal()
	_hp = maxf(_hp - amount, 0.0)
	# 记录受伤：护甲累计/碎裂、虚无守卫激怒叠层
	_note_damage_taken(amount)
	var gm = _game_manager()
	if gm:
		gm.total_damage += amount

	if _hp <= 0.0:
		die()
		return

	# 墓穴蝙蝠：受击后分裂为 2 只小蝙蝠（每只怪只分裂一次）
	if hit_split_count > 0 and not _hit_split_used:
		_hit_split_used = true
		_spawn_splits()
	# 硫磺蝙蝠：被命中后闪避 +40%，3 秒（每次受击刷新计时）
	if hit_dodge_bonus > 0.0:
		if _hit_dodge_timer <= 0.0:
			dodge_pct = minf(dodge_pct + hit_dodge_bonus, 0.95)
		_hit_dodge_timer = hit_dodge_seconds

	# 受击硬直：打断前摇/攻击，进入 STAGGERED（击退为向量速度）
	_knockback_velocity = knockback
	_stagger_timer = 0.3
	if _current_state == EnemyState.WINDUP:
		_set_windup_visual(false)
		_attack_timer = maxf(_attack_timer, 0.4)  # 打断后惩罚：短冷却
	# 自爆前摇可被打断：受击即提前引爆（分册 5.1「可被攻击提前引爆」）
	if _exploding and _explode_timer > 0.0:
		_do_explode()
		return
	_current_state = EnemyState.STAGGERED
	visuals.flash_hit()
	visuals.update_health_bar()


## 当前血量比例（0~1）；HUD 的 Boss 血条栏靠它刷新，无需触碰私有字段
func hp_ratio() -> float:
	return clampf(_hp / maxf(max_hp, 0.001), 0.0, 1.0)


## 是否存活
func is_alive() -> bool:
	return _hp > 0.0 and _current_state != EnemyState.DEAD


## 受击闪红：模型短暂染红再还原（给出明确的打击反馈）
func die() -> void:
	# **重入保护**：同一帧内可能有多个来源同时打死敌人——DOT 结算 + 普攻、
	# AOE + 投射物、自爆连锁等。没有这道闸门时 die() 会跑多次：
	# kills 重复计数、掉落重复生成（实测双致命伤 → kills 0→2）。
	# 层数越高、伤害来源越多，撞上同帧双杀的概率越大，
	# 表现就是「后期经常一次掉一堆装备」。
	if _current_state == EnemyState.DEAD:
		return
	_current_state = EnemyState.DEAD
	# 死亡特效：走房间特效池（零新建）。
	# 精英用更大的爆炸表现（视觉上区分普通怪与精英）。
	var fx := _effect_field()
	if fx != null:
		fx.play("death", global_position,
			Color(1.0, 0.75, 0.25) if is_elite else Color(0.9, 0.3, 0.25))
	var gm = _game_manager()
	if gm:
		gm.kills += 1
	var bus = _event_bus()
	if bus:
		bus.enemy_died.emit(self, global_position, [])
	died.emit(global_position)
	# 击杀成长类机制（虚空吞噬者）：广播「有单位死了，凶手是谁」。
	# 只在场上存在吞噬者时才发（`_broadcast_death`），见 EventBus.unit_died 注释。
	if _has_devourer():
		if bus:
			bus.unit_died.emit(self, _last_attacker, global_position)

	# 死亡区域（分册 4.2 毒系四阶段：普通毒雾 → 扩大 → 硫磺爆炸 → 熵毒领域）
	if death_zone != DeathZone.NONE:
		_spawn_death_poison()

	# 死亡自爆（矿道自爆者 / 熔炉小鬼）
	if death_explode:
		_do_explode()

	# 死亡分裂（水孢行者 / 混沌幼蛛）
	if death_split:
		_spawn_splits()

	# 召唤小怪（僵尸各阶段）：死亡时按概率召唤
	if not summon_spec.is_empty():
		_try_summon()

	# 掉落（挂在房间节点下，随房间销毁）
	if gm:
		var loot := LootSystem.new()
		var parent := get_parent()
		if parent:
			loot.generate_loot(self, global_position, parent)

	set_physics_process(false)
	hide()
	# 延迟销毁
	await get_tree().create_timer(0.5).timeout
	queue_free()


# ============================================================
# 怪物机制（分册第 4/5 章，本轮实现自爆/分裂/召唤三种）
# ============================================================

## 死亡自爆：对范围内玩家结算伤害 + 视觉爆发
func _do_explode() -> void:
	if _explode_timer < 0.0:
		return
	_explode_timer = -1.0   # 标记已引爆，避免重复
	_exploding = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if not (p is Node3D):
			continue
		if (p as Node3D).global_position.distance_to(global_position) <= explode_radius:
			if p.has_method("take_damage"):
				p.call("take_damage", explode_damage)
	# 视觉：走房间特效池，而不是每次现建 mesh。
	#
	# **原实现有个泄漏**：`MeshInstance3D.new()` 后 `add_child(vis)`，
	# 但**没有任何地方销毁它**——挂在本节点下，而本节点随后 queue_free，
	# 所以实际不会永久泄漏；但每次自爆都新建节点 + 材质，
	# 大规模团战下是纯 CPU 开销。改用池后零新建。
	var field := _effect_field()
	if field != null:
		field.play("death", global_position, Color(1.0, 0.5, 0.1))
	else:
		# 兜底：拿不到特效池时退回原实现（保证自爆永远有视觉反馈）
		_spawn_explode_visual_legacy()


## 自爆视觉的旧实现（特效池不可用时的兜底）
func _spawn_explode_visual_legacy() -> void:
	var vis := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = explode_radius * 0.5
	sphere.height = explode_radius
	vis.mesh = sphere
	vis.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vis.material_override = mat
	add_child(vis)


## 取本房的特效池（向上找 RoomController）
func _effect_field() -> EffectField:
	var room := get_parent()
	while room != null and not room.has_method("effect_field"):
		room = room.get_parent()
	if room == null:
		return null
	return room.call("effect_field") as EffectField


## 进入自爆前摇（分册：前摇 1.5 秒，期间被打死或受击则提前引爆）
func _start_explode_windup() -> void:
	_exploding = true
	_explode_timer = 1.5


## 死亡分裂：生成 N 只小型同类（血量/攻击减半）
func _spawn_splits() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for _i in split_count:
		var child := EnemyBase.new()
		# 沿圆周散开，避免叠在同一点
		var ang := TAU * float(_i) / float(maxi(split_count, 1))
		child.position = position + Vector3(cos(ang), 0.0, sin(ang)) * 1.2
		var cfg := {
			"id": monster_id,
			"name": monster_name,
			"hp": maxf(max_hp * 0.5, 1.0),
			"atk": atk * 0.5,
			"defense": defense,
			"speed_pct": 60.0,
			"attack_interval": attack_interval,
			"attack_range": attack_range,
			"dodge_pct": dodge_pct,
			"scale": body_scale * 0.6,
			"special": {},          # 子体不再分裂，避免无限增殖
			"ai": "melee" if behavior == AIBehavior.MELEE_CHASE else "kite",
		}
		child.apply_monster_config(cfg)
		child.is_elite = false
		parent.add_child(child)


## 召唤小怪（僵尸各阶段：按概率召唤 1~N 只）
func _try_summon() -> void:
	if summon_spec.is_empty():
		return
	_do_summon(summon_spec)


## 供 Boss 机制调用的公开召唤入口（BossMechanics 按自己的间隔驱动）。
## 复用 _do_summon 的全部逻辑（含虚空裂痕、内联配置、死亡自爆子体）。
func summon_minions(spec: Dictionary) -> void:
	if spec.is_empty():
		return
	_do_summon(spec)


## 实际执行一次召唤（chance 由调用方判定；此处不再重复掷骰，
## 否则「按间隔必召」的 Boss 会被 50% 概率二次削弱）
func _do_summon(spec: Dictionary) -> void:
	var parent := get_parent()
	if parent == null:
		return

	# 虚空裂痕：不是召小怪，而是生成一块持续伤害区域（分册 4.1 虚空僵尸）
	if bool(spec.get("zone", false)):
		DamageZone.spawn({
			"position": global_position, "radius": float(spec.get("radius", 2.5)),
			"duration": float(spec.get("duration", 6.0)),
			"damage": float(spec.get("damage", 40.0)),
			"color": Color(0.6, 0.2, 0.9, 0.45),
		}, parent)
		return

	var count := int(spec.get("count", 1))
	for _i in count:
		var m := MonsterDB.get_monster(str(spec.get("id", "")))
		# 内联配置（熔炉小鬼等不在 MonsterDB 里的小怪）
		if m.is_empty() and spec.has("hp"):
			m = {
				"id": str(spec.get("id", "minion")),
				"name": str(spec.get("name", "小怪")),
				"hp": float(spec.get("hp", 60)),
				"atk": float(spec.get("atk", 10)),
				"defense": 3.0, "speed_pct": 70.0, "attack_interval": 3.0,
				"attack_range": 2.0, "dodge_pct": 0.0, "scale": 0.7,
				"special": {
					"death_explode": bool(spec.get("death_explode", false)),
					"explode_damage": float(spec.get("explode_damage", 30.0)),
				},
			}
		if m.is_empty():
			# **不静默跳过**：查不到 id 时召唤会无声失效，从数据层完全看不出来
			# （BossDB 早期把策划概念名当 id 传，7 个 Boss 的召唤全因此失效）。
			# 这里显式告警，让"配了召唤但没生效"立刻可见。
			push_warning("[%s] 召唤失败：MonsterDB 查不到 id '%s'（检查 BossDB 的 SUMMON_ID_MAP）" % [
				monster_name, str(spec.get("id", ""))])
			continue
		var minion := EnemyBase.new()
		var ang := randf() * TAU
		minion.position = position + Vector3(cos(ang), 0.0, sin(ang)) * 1.5
		minion.apply_monster_config(m)
		minion.is_elite = false
		parent.add_child(minion)
		# 先挂到房间树再登记，保证控制器能找到
		_register_summon(minion)


## 找到房间控制器登记召唤物（保持 enemies_alive 正确）
func _register_summon(minion: Node) -> void:
	var room := get_parent()
	while room != null and not room.has_method("register_summoned_enemy"):
		room = room.get_parent()
	if room != null:
		room.call("register_summoned_enemy", minion)


## 死亡毒雾（2 米，每秒 10 伤，持续 3 秒）—— 走统一 DamageZone
## 原实现用 await 定时器逐秒结算，节点被 free 时协程会悬挂；改后无此风险
## 死亡区域：按形态取不同半径/伤害（分册 4.2 毒系递进，数值取原文）
func _spawn_death_poison() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spec := {
		"position": global_position, "radius": 2.0, "duration": 3.0,
		"damage": 10.0, "color": Color(0.3, 0.9, 0.2, 0.4),
	}
	match death_zone:
		DeathZone.BIG_POISON:
			# 腐毒僵尸：毒雾扩大（半径 3.5）+ 持续更久
			spec["radius"] = 3.5
			spec["duration"] = 5.0
			spec["damage"] = 15.0
		DeathZone.SULFUR:
			# 硫磺僵尸：硫磺爆炸（4 米，40 伤），点燃地面 5 秒
			spec["radius"] = 4.0
			spec["damage"] = 40.0
			spec["duration"] = 5.0
			spec["color"] = Color(1.0, 0.45, 0.1, 0.5)
		DeathZone.ENTROPY:
			# 熵毒僵尸：熵毒领域（5 米，每秒 25 伤）
			spec["radius"] = 5.0
			spec["damage"] = 25.0
			spec["duration"] = 5.0
			spec["color"] = Color(0.6, 0.2, 0.8, 0.45)
	DamageZone.spawn(spec, parent)
	# 熵毒/腐毒：领域内同时给玩家叠毒气层数（分册「毒气层数 +1」）
	if death_zone == DeathZone.ENTROPY or death_zone == DeathZone.BIG_POISON:
		var pb = _player.get("buffs") if _player != null else null
		if pb != null:
			pb.add_element(ElementDefs.Elem.POISON, 1)


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var node := get_node_or_null("/root/GameManager")
	return node


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var node := get_node_or_null("/root/EventBus")
	return node
