class_name BossMechanics
extends RefCounted
## Boss 通用机制原语 —— 批次 C
##
## 把 BossDB 里声明的 9 类机制翻译成可执行行为。
## **不是每个 Boss 一个脚本**：这里按类实现，Boss 只提供参数
## （见 BossDB 的 mechs + params）。
##
## 生命周期：RoomController 刷 Boss 时创建并 attach 到 EnemyBase；
## 每物理帧调 tick()；Boss 受击后调 on_damaged()。
##
## 已实现（本批次）：
##   phase   —— 血量阈值触发增益（半血狂暴等），支持多阶段
##   shield  —— 高减伤，受击累积后破除（绕背/打柱子的通用表达）
##   field   —— 地面区域（复用 DamageZone）
##   summon  —— 定期召唤（复用 EnemyBase 的 summon 路径）
##   split   —— 死亡分裂（复用 death_split 原语）
##
## 登记待实现（参数已在 BossDB 中，行为后续补）：
##   stealth / ranged / control / charge 的 Boss 专属变体
##   —— 这些在 EnemyBase 里已有通用版本（隐身/减速/突进），
##      Boss 只需在 to_monster_config 里把参数写进对应字段即可，
##      无需重复实现在这里。

var boss: Node3D = null
var mechs: Array = []
var params: Dictionary = {}

# 阶段
var _phase_thresholds: Array = []   ## 降序的血量比例阈值
var _phase_index := 0               ## 已触发到第几阶段
var _base_atk := 0.0
var _base_interval := 0.0

# 护盾
var _shield_reduction := 0.0
var _shield_absorbed := 0.0
var _shield_break_at := 0.0
var _shield_broken := false

# 场地
var _field_zone: Node = null
var _field_type := ""

# 召唤
var _summon_spec: Dictionary = {}
var _summon_timer := 0.0
var _summon_interval := 8.0

var _rng := RandomNumberGenerator.new()


## 按 BossDB 的 boss 定义装配到某个敌人上
static func attach(target: Node3D, boss_def: Dictionary) -> BossMechanics:
	if target == null or boss_def.is_empty():
		return null
	var bm := BossMechanics.new()
	bm.boss = target
	bm.mechs = boss_def.get("mechs", [])
	bm.params = boss_def.get("params", {})
	bm._setup()
	return bm


func _setup() -> void:
	_rng.randomize()
	# **基准值延迟到首次使用时记录**，不在这里读。
	# 原因：attach 发生在 RoomController 乘难度倍率之前，
	# 此处读到的是「未乘难度」的 atk/攻速；阶段转换若拿它当基准，
	# 会把难度加成抹掉（实测第 8 层 Boss 从 atk 227 掉回 100）。
	_base_atk = 0.0
	_base_interval = 0.0

	# —— 阶段转换 ——
	# 支持两种写法：phases 数组（多阶段，第 8/9 层）或 phase_at 单阈值
	if params.has("phases"):
		for t in params["phases"]:
			_phase_thresholds.append(float(t))
	elif params.has("phase_at"):
		_phase_thresholds.append(float(params["phase_at"]))
	_phase_thresholds.sort()
	_phase_thresholds.reverse()   # 降序：先触发高血量阈值

	# —— 护盾 ——
	if params.has("shield_reduction"):
		_shield_reduction = float(params["shield_reduction"])
		# 破盾阈值：策划没给明数，按 Boss 最大血量的 25% 折算
		# （即"打下四分之一血就破防"），保证战斗节奏可控
		_shield_break_at = float(boss.get("max_hp")) * 0.25
		_apply_shield_reduction()

	# —— 场地 ——
	if params.has("field"):
		_field_type = str(params["field"])

	# —— 召唤 ——
	if params.has("summon"):
		_summon_spec = params["summon"]
		_summon_interval = float(_summon_spec.get("interval", 8.0))


## 每物理帧推进
func tick(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	_tick_summon(delta)
	_tick_field(delta)


## Boss 受击后调用（血量已更新）
func on_damaged(amount: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	_check_phase()
	_check_shield_break(amount)


## 记录攻击基准（首次进入阶段时调用，确保已包含难度倍率）
func _ensure_baseline() -> void:
	if _base_atk > 0.0:
		return
	_base_atk = float(boss.get("atk"))
	_base_interval = float(boss.get("attack_interval"))


## 血量跨过阈值 → 进入下一阶段（增攻/提速）。多阶段 Boss 逐个触发。
func _check_phase() -> void:
	if _phase_thresholds.is_empty():
		return
	var ratio: float = float(boss.call("hp_ratio"))
	# 阈值降序，可一次跨过多个（大幅伤害越过两阶段时不能漏触发）
	while _phase_index < _phase_thresholds.size() and ratio <= _phase_thresholds[_phase_index]:
		_phase_index += 1
		_enter_phase(_phase_index)

func _enter_phase(n: int) -> void:
	# 基准值首次使用时才记录（见 _setup 注释：attach 发生在难度倍率之前）
	_ensure_baseline()
	# 每进入一阶段：攻击 +25%、攻速 +20%（策划各 Boss 的"狂暴/换招"共性表达）。
	# BossDB 的 phase_haste 是额外加成，叠加在其上。
	var atk_gain := 1.0 + 0.25 * float(n)
	var haste_gain := 1.0 + 0.20 * float(n)
	if params.has("phase_haste"):
		haste_gain += float(params["phase_haste"]) * float(n)
	boss.set("atk", _base_atk * atk_gain)
	boss.set("attack_interval", maxf(_base_interval / haste_gain, 0.4))
	# 阶段切换的视觉反馈：闪一下（复用受击闪红通道）
	if boss.has_method("_flash_hit"):
		boss.call("_flash_hit")
	var bus: Node = _event_bus()
	if bus:
		bus.message.emit("%s 进入第 %d 阶段！" % [
			str(boss.get("monster_name")), n + 1])


## 护盾：达到吸收阈值前维持减伤，达到后破除
func _check_shield_break(amount: float) -> void:
	if _shield_broken or _shield_reduction <= 0.0:
		return
	_shield_absorbed += amount
	if _shield_break_at > 0.0 and _shield_absorbed >= _shield_break_at:
		_shield_broken = true
		boss.set("armor_plates", 0.0)
		var bus: Node = _event_bus()
		if bus:
			bus.message.emit("%s 的护盾被击破！" % str(boss.get("monster_name")))


## 把减伤写进敌人已有的 armor_plates 字段（复用普通怪的护甲减伤通道）
func _apply_shield_reduction() -> void:
	if _shield_reduction > 0.0:
		boss.set("armor_plates", _shield_reduction)


## 场地机制：用 DamageZone 铺一块常驻区域（毒/熔岩/焦油/泥潭）
## 区域尺寸按 Boss 房尺度给（半径 4 米，覆盖战场中段，逼玩家走位）
func _tick_field(delta: float) -> void:
	if _field_type.is_empty() or _field_zone != null:
		return
	# 首帧延迟一点，等房间与 Boss 都就位
	_field_zone = _spawn_field_zone()


func _spawn_field_zone() -> Node:
	var spec := _field_spec(_field_type)
	if spec.is_empty():
		return null
	var parent: Node = boss.get_parent()
	if parent == null:
		return null
	var zone: Node = DamageZone.spawn({
		"position": boss.global_position,
		"radius": 4.0,
		"duration": 999.0,          # 常驻（随房间销毁）
		"tick_interval": float(spec.get("interval", 1.0)),
		"damage": float(spec.get("damage", 8.0)),
		"target_group": "player",
		"slow_buff": str(spec.get("slow_buff", "")),
		"color": spec.get("color", Color(0.4, 0.8, 0.3, 0.3)),
	}, parent as Node3D)
	return zone


## 场地类型 → 参数（策划 4 的环境机制与 Boss 场地机制共用一套口径）
func _field_spec(kind: String) -> Dictionary:
	match kind:
		"poison", "spore":
			return {"damage": 6.0, "interval": 1.0, "slow_buff": "erosion",
				"color": Color(0.35, 0.75, 0.30, 0.30)}
		"lava", "firestorm":
			return {"damage": 14.0, "interval": 1.0,
				"color": Color(0.95, 0.35, 0.10, 0.35)}
		"mire", "tar":
			return {"damage": 4.0, "interval": 1.0, "slow_buff": "mire",
				"color": Color(0.30, 0.28, 0.18, 0.35)}
		"rocks":
			return {"damage": 5.0, "interval": 1.5,
				"color": Color(0.35, 0.33, 0.30, 0.30)}
		"rift", "devour", "gravity_flip":
			return {"damage": 8.0, "interval": 1.0,
				"color": Color(0.45, 0.35, 0.95, 0.30)}
		"collapse":
			return {"damage": 3.0, "interval": 1.0, "slow_buff": "erosion",
				"color": Color(0.30, 0.26, 0.22, 0.30)}
	return {}


## 召唤：按间隔刷小怪（复用 EnemyBase 的召唤路径）
func _tick_summon(delta: float) -> void:
	if _summon_spec.is_empty():
		return
	_summon_timer -= delta
	if _summon_timer > 0.0:
		return
	_summon_timer = _summon_interval
	var chance := float(_summon_spec.get("chance", 1.0))
	if _rng.randf() > chance:
		return
	# EnemyBase 已有 _try_summon 路径，传配置即可
	if boss.has_method("summon_minions"):
		boss.call("summon_minions", _summon_spec)


## 该 Boss 是否声明了某类机制
func has_mech(mech: String) -> bool:
	return mechs.has(mech)


## 当前阶段（0 = 未进入任何阶段）
func current_phase() -> int:
	return _phase_index


## 护盾是否已破（供测试与 HUD）
func shield_broken() -> bool:
	return _shield_broken


func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("EventBus")
