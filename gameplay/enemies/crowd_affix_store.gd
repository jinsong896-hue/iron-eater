class_name CrowdAffixStore
extends RefCounted
## 群体单位的词缀状态与结算 —— 让 swarm 怪也能吃精英词缀
##
## ## 为什么需要它
## 词缀（`AffixDB`，怪物设计分册第 7 章）本来是挂在 `EnemyBase` 节点上的：
## 数值型由 `AffixDB.apply()` 直接写进 monster dict，非数值型由
## `enemy_base._apply_affix()` 装配战斗钩子。
##
## 群体单位**不是场景节点**，也没有 `EnemyBase`，所以两条路都断了：
## 数值型里 `speed_pct` 在生成时被读一次还算生效，但
## `attack_interval` 与 `knockback_mult` **生成后再也不会被读**；
## 非数值型（燃烧/冰冻/复仇/不朽/吸血/虚空/混沌）则**全部失效**。
## 同一个词缀挂到 swarm 怪身上会静默缩水成"只有移速变快"。
##
## 本表把状态收在 GDScript 侧、按单位 id 索引，由 `CrowdManager` 在
## 单位死亡时清理。**不加锁、不跨线程**——所有读写都在主线程。
##
## ## 数值口径
## 逐条对齐 `enemy_base` 的同名常量与实现，保证"同一个词缀挂到节点怪和
## swarm 怪上行为相同"。这是本项目反复踩过的坑：两条路径的规则一旦分叉，
## 差异极难察觉（玩家只会觉得"有时候词缀好像没生效"）。
##
## ## 已知范围收缩（有意为之，非遗漏）
##   · **混沌**只改移速。核里攻击力/攻速是**全体共用**的一组参数，
##     改不了单个单位（节点侧会随机改这三项）。
##   · **燃烧/冰冻**复用玩家侧的 `BuffHolder` 词条（`burn` / `frost`），
##     与节点侧 `enemy_base` 施加的是同一套，行为一致。
##   · **虚空**换位受核的接口限制，见 `_swap_with_player`。

## 复仇：受击反伤比例（对齐 enemy_base.AFFIX_REVENGE_PCT）
const BASE_REVENGE_PCT := 0.15
## 吸血：造成伤害时回血比例（对齐 enemy_base.AFFIX_LIFESTEAL_PCT）
const BASE_LIFESTEAL_PCT := 0.20
## 不朽：血量低于该比例触发（对齐 enemy_base.AFFIX_IMMORTAL_THRESHOLD）
const IMMORTAL_THRESHOLD := 0.30
## 不朽：回复最大生命的比例（对齐 enemy_base.AFFIX_IMMORTAL_HEAL_PCT）
const IMMORTAL_HEAL_PCT := 0.15
## 不朽：免伤持续秒数（对齐 enemy_base.AFFIX_IMMORTAL_SHIELD_TIME）
const IMMORTAL_SHIELD_TIME := 2.5
## 混沌：变动间隔秒数（对齐 enemy_base.AFFIX_CHAOS_INTERVAL）
const CHAOS_INTERVAL := 6.0
## 虚空：换位最大距离（对齐 enemy_base._swap_with_player 的调用值）
const VOID_SWAP_DIST := 10.0

## 该单位的词缀 id 列表（含数值型，供 UI/调试显示）
var ids: Array = []
## 复仇：受击反伤比例
var revenge_pct := 0.0
## 吸血：造成伤害时回血比例
var lifesteal_pct := 0.0
## 燃烧：命中给玩家挂灼烧
var burn := false
## 冰冻：命中给玩家叠寒霜
var freeze := false
## 虚空：命中与玩家交换位置
var void_hit := false
## 混沌：周期性随机改自身移速
var chaos := false
## 不朽：低血触发一次免伤 + 回血
var immortal := false
## 不朽已用掉（每只怪一次，对齐 enemy_base._immortal_used）
var immortal_used := false
## 不朽免伤剩余时长
var immortal_timer := 0.0
## 混沌下次变动倒计时
var chaos_timer := 0.0
## 混沌累积的移速倍率（`base_speed` × 它 = 当前速度）
var speed_mult := 1.0
## 生成时的移速（混沌改的是倍率，不是这个基准值）
var base_speed := 0.0
## 生成时的移速倍率来源：词缀·快速（`AffixDB.apply` 写进 monster dict 的
## `speed_pct`，基准 100）。**必须由调用方在登记时设好**，否则混沌重掷
## 会从 1.0 起算，把「快速」那部分加成整个抹掉。
var spawn_mult := 1.0


## 从怪物配置构造。**只认 `affixes` 字段**（`AffixDB.apply()` 写入的 id 列表）。
## 没有词缀时返回 null——绝大多数基础怪都没有，省一次分配与一次查表。
static func from_monster(m: Dictionary) -> CrowdAffixStore:
	var list: Array = m.get("affixes", [])
	if list.is_empty():
		return null
	var s := CrowdAffixStore.new()
	s.ids = list.duplicate()
	for raw in list:
		match str(raw):
			"revenge":
				s.revenge_pct = BASE_REVENGE_PCT
			"lifesteal":
				s.lifesteal_pct = BASE_LIFESTEAL_PCT
			"burn":
				s.burn = true
			"freeze":
				s.freeze = true
			"void":
				s.void_hit = true
			"chaos":
				s.chaos = true
				s.chaos_timer = CHAOS_INTERVAL
			"immortal":
				s.immortal = true
			_:
				pass   # 数值型（fast/strong）已由 AffixDB.apply 写进 monster dict
	return s


## 是否还有需要每帧推进的计时器。
## 纯数值型词缀（fast/strong）返回 false——省掉每帧的无效遍历。
func has_timers() -> bool:
	return immortal_timer > 0.0 or chaos


## 词缀显示名列表（调试/UI 用）
func names() -> Array:
	var out: Array = []
	for id in ids:
		out.append(AffixDB.affix_name(str(id)))
	return out


## 推进计时器。由 `CrowdManager._physics_process` 每帧调用一次。
##
## 不朽免伤只在这里"计时归零"，**触发判定在 `note_damage` 里**——
## 与节点侧一致（`enemy_base._tick_mech_timers` 只减计时，触发在 `take_damage`）。
##
## 返回 **true 表示移速被混沌改动了**，调用方需要把新速度写回模拟核
##（核里 `speed` 是每单位独立数组，但只有 spawn 时能写）。
func tick(delta: float, rng: RandomNumberGenerator) -> bool:
	if immortal_timer > 0.0:
		immortal_timer = maxf(immortal_timer - delta, 0.0)
	if chaos:
		chaos_timer -= delta
		if chaos_timer <= 0.0:
			chaos_timer = CHAOS_INTERVAL
			return _roll_chaos(rng)
	return false


## 混沌：累积移速倍率（节点侧还会改攻击力/攻速，那两项群体单位无处安放）。
##
## 群体单位的攻击参数是**全体共用**的（核里只有一组 attack_* 变量），
## 改不了单个单位；但 `speed` 在核里是**每单位独立的数组**，
## 故这里改的是"生成速度 × speed_mult"，由 `CrowdManager` 写回核。
## 这是有意的范围收缩，不是遗漏。
##
## **与节点侧的口径差异**：节点侧 `_tick_chaos` 是 1/3 概率改攻速、
## 1/3 概率改移速、1/3 概率改攻击力。群体路径只能改移速，若照抄那个
## 1/3 判定，等于**三分之二的触发都被丢弃**（表现为"混沌词缀几乎没反应"）。
## 故这里**每次都改移速**，把节点侧三分之一的频率补偿回来。
##
## 返回是否真的变动了（恒为 true；保留返回值是为了调用方不用改判断）。
func _roll_chaos(rng: RandomNumberGenerator) -> bool:
	# 重掷是**围绕生成时的倍率**做的，不是原地累乘——累乘会让倍率
	# 随游戏时长漂走（几百次重掷后速度会离谱），而设计意图是
	# "在正常速度附近随机抖动"。`spawn_mult` 里含着「快速」词缀的加成。
	speed_mult = maxf(spawn_mult * (1.0 + rng.randf_range(-0.2, 0.3)), 0.5)
	return true


## 每次命中玩家时结算"附加在玩家身上的效果"。
##
## `player` 可能为 null（玩家不在场）——不该崩。
## 燃烧/冰冻走玩家侧既有的 `BuffHolder` 词条（`burn` / `frost`），
## 与 `enemy_base._apply_melee_mechanics` 施加的是同一套，不另造计时器。
func on_hit_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tb = player.get("buffs")
	if tb == null:
		return
	if burn:
		tb.apply("burn", "affix")
	if freeze:
		tb.apply("frost", "affix")


## 虚空换位的判定部分：给出"是否该换位"以及交换后的两个坐标。
##
## **核没有直接设坐标的接口**（`set_stagger` / `set_target` 都不是），
## 所以单位侧只能走 `CrowdManager.teleport_unit`——那里用
## `despawn` + `spawn` 在同一 id 上重建，代价是一次池操作，
## 而换位本来就是个低频事件（词缀·虚空，冷却由核的攻击间隔兜着）。
##
## 返回 {} 表示不换位（超出距离/玩家无效）。
func plan_swap(player: Node, mine: Vector3) -> Dictionary:
	if not void_hit:
		return {}
	if player == null or not is_instance_valid(player) or not (player is Node3D):
		return {}
	var theirs: Vector3 = (player as Node3D).global_position
	if mine.distance_to(theirs) > VOID_SWAP_DIST:
		return {}
	return {"unit_to": theirs, "player_to": mine}


## 受击时结算"作用于自身的效果"，返回免伤后的实际伤害。
##
## **调用方必须用返回值扣血**——不朽的免伤就在这里生效。
## `attacker` 是玩家节点（复仇反伤用；可能为 null）。
##
## 约定：
##   · 返回 **-1** ⇒ 本次触发不朽，调用方跳过扣血并按 `immortal_heal_amount` 回血
##   · 返回 **0**  ⇒ 免伤期内完全免疫
##   · 返回 **>0** ⇒ 正常扣这个数值
func note_damage(amount: float, hp: float, max_hp: float,
		attacker: Node, pos: Vector3) -> float:
	# 复仇：在扣血之前算——反伤基于"这次挨了多少"，与自身是否会被打死无关
	#（对齐 enemy_base.take_damage 里的顺序）
	if revenge_pct > 0.0 and attacker != null and is_instance_valid(attacker) \
			and attacker.has_method("take_damage"):
		var back := amount * revenge_pct
		# **两参调用**：`attacker` 在生产路径上永远是玩家（近战/投射物打过来），
		# 而玩家侧 `take_damage(amount, from)` 只有两个参数。
		# 按节点式敌人的四参签名调会报 "Cannot convert argument 2 from Nil"
		# 并**静默反伤失败**——`enemy_base._reflect_to` 的注释记的就是同一个坑。
		attacker.call("take_damage", back, null)
		EventBus.damage_popup.emit(pos, back, "aoe")
	# 不朽：血量将跌破阈值时触发一次免伤 + 回血（每只怪一次）
	if immortal and not immortal_used \
			and (hp - amount) / maxf(max_hp, 0.001) < IMMORTAL_THRESHOLD:
		immortal_used = true
		immortal_timer = IMMORTAL_SHIELD_TIME
		return -1.0
	# 免伤期内完全免疫（对齐 enemy_base.take_damage：计时中直接 return）
	if immortal_timer > 0.0:
		return 0.0
	return amount


## 不朽触发时要回的血量（占最大生命的比例）
func immortal_heal_amount(max_hp: float) -> float:
	return max_hp * IMMORTAL_HEAL_PCT
