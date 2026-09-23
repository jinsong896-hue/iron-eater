class_name Projectile
extends Area3D
## 统一投射物 —— 玩家与敌人共用
##
## 取代原先两套互不相通的实现（ProjectileSystem 的运行时编译脚本 +
## EnemyBase 的 await 逐帧循环）。两者都缺弹射/弧线/延时/分裂能力。
##
## 设计要点：
##   · 用 _physics_process 推进，不用 await 循环——await 期间节点被 free
##     会导致协程悬挂；且每帧重新取 delta 在暂停/变速下行为不一致。
##   · 用 groups 判定命中目标（不 hardcode 单向）：同一套代码，玩家打敌人、
##     敌人打玩家都走这里。
##   · 支持分册第 5/6 章四种投射物机制：弹射 / 弧线 / 延时爆炸 / 命中分裂。

## 命中判定：只打这些组里的节点
const TARGET_PLAYER := "player"
const TARGET_ENEMY := "enemies"

## 命中检测的物理层掩码（Area3D.mask 与目标 layer 相交才产生 body_entered）。
## 1 = 世界/墙，2 = 敌人（见 enemy_base.ENEMY_LAYER），3 = 玩家。
## 必须显式列出——Area3D 默认 mask 只含第 1 层。
const PROJECTILE_MASK := 0b111

var direction := Vector3.FORWARD
var speed := 10.0
var damage := 0.0
var lifetime := 2.0
var element := "physical"
var elem_enum := -1            ## ElementDefs.Elem；>=0 时命中会叠元素层
var pierce_count := 0          ## 可穿透的额外目标数（0 = 命中即消失）

# —— 弹射（bounce_shot：硫磺元素火球弹射 2 次）——
var bounces := 0               ## 剩余弹射次数
var _bounced := 0
var _hit_targets: Array = []   ## 已命中目标，避免弹回时重复打同一个
## 命中回调：`func(target: Node3D, damage: float) -> void`。
##
## **为什么需要它**：投射物默认走 `_deal_damage` —— 一条只做
## `DamagePipeline.elemental_attack` + 裸 `take_damage` 的简化路径。
## 而玩家普攻有一整套结算（连击计数、生命偷取、装备触发词条、
## 形态印记、职业资源积攒、背刺判定、命中顿帧），全在
## `Player._apply_hit` 里。玩家用远程武器时若走默认路径，
## **远程普攻会比近战少掉一大截效果**（不攒连击、不吸血、不触发装备）。
##
## 故：玩家远程普攻把自己的 `_apply_hit` 接进这个回调，
## 投射物只负责「飞过去、判定命中」，结算交回调用方。
## 留空则保持旧行为（敌人射击用的简化路径），两者互不影响。
var on_hit: Callable = Callable()

# —— 弧线（抛物线轨迹）——
var arc := false
var _arc_elapsed := 0.0
var _arc_start := Vector3.ZERO
var _arc_landing := Vector3.ZERO
var _arc_height := 3.0

# —— 延时爆炸（orb_bomber：投掷延时炸弹，3 秒后爆炸）——
var fuse := 0.0                ## >0 表示落地后进入引信倒计时
var explode_radius := 0.0
var explode_damage := 0.0
var _fuse_armed := false
var _fuse_timer := 0.0

# —— 分册第 4/9 章：击杀分裂 / 命中留区域 ——
var split_on_hit := 0          ## >0：命中时分裂出 N 枚小弹（虚空弓手/混沌幼蛛）
var split_damage_pct := 0.4    ## 分裂弹伤害占本体的比例
var split_spread := 0.5        ## 分裂弹的散射半角（弧度）
var zone_on_land := {}         ## 命中/有效期结束后原地生成区域（熔炉哨兵火焰区）
var data: Dictionary = {}      ## 生成时的原始配置（分裂时复制用）

var _owner_faction := TARGET_ENEMY   ## 本投射物"属于"哪一方（决定打谁）
var _elapsed := 0.0
var _hit_count := 0


## 配置并生成。data 键与旧接口兼容（direction/speed/damage/lifetime/element/pierce_count），
## 另支持 bounces / arc / fuse / explode_radius / explode_damage / split 等。
## target_group 决定打谁：Projectile.TARGET_ENEMY（玩家射出）/ TARGET_PLAYER（敌人射出）
## 分流开关：是否把投射物交给 C++ 模拟核（ProjectileSim）。
##
## **默认开启**（2026-09-19 切换）。切换前做了逐条行为对照与压力测试：
##
## 行为对照（核 vs 旧节点路径）：
##   直线 / 弧线含 y / 穿透 / 弹射 / 引信爆炸 / 分裂 / 落地区域 / 阵营过滤
##   —— `tests/test_projectile_sim.gd` 逐条断言，两套后端都跑。
##
## 压力测试（4096 发满容量 + 512 目标，每步补满）：
##   核内 step            0.4 ~ 0.9 ms
##   事件回传（扁平接口）  0.02 ms
##   合计                 3.2 ~ 5.5% 帧预算
##   对照：逐事件 Dictionary 编组要 15 ms/帧（约 90% 帧预算），
##   故事件回传走 `drain_events_packed()` 扁平数组，不走 Dictionary。
##
## 已知两条路径**共有**的遗留问题（非切换引入）：
##   · 都不处理撞墙——旧路径 `_on_body_entered` 开头就按阵营组过滤，
##     墙不在 player/enemies 组里，直接 return。
##
## 需要退回旧路径时：`Projectile.USE_SIM_CORE = false`（调试用）。
static var USE_SIM_CORE := true


static func spawn(data: Dictionary, parent: Node3D, target_group: String = TARGET_ENEMY) -> Projectile:
	# 分流：交给核（ProjectileSim）时**返回 null**——核里的投射物不是节点。
	#
	# 调用方必须能接受 null。现有两处调用点（敌人 _shoot / 技能系统）
	# 都不使用返回值，故安全；新增调用点要注意判空。
	#
	# **`force_node` 例外**：核只回传 `projectile_hit(world_pos, damage, kind)`，
	# **不带目标引用**，且 Callable 跨不过 C++ 边界——故 `on_hit` 回调在核路径
	# 下永不触发。玩家普攻依赖该回调把结算接回 `Player._apply_hit`
	#（连击/吸血/装备触发/形态印记），走核会**静默丢掉全部普攻效果**。
	# 故这类调用方用 `force_node` 显式要求节点路径。
	if USE_SIM_CORE and not bool(data.get("force_node", false)) \
			and _spawn_via_sim(data, parent, target_group):
		return null
	var p := Projectile.new()
	p.direction = (data.get("direction", Vector3.FORWARD) as Vector3).normalized()
	p.speed = float(data.get("speed", 10.0))
	p.damage = float(data.get("damage", 10.0))
	p.lifetime = float(data.get("lifetime", 2.0))
	p.element = str(data.get("element", "physical"))
	p.elem_enum = ElementDamage.elem_from_key(p.element)
	p.pierce_count = int(data.get("pierce_count", 0))
	p.bounces = int(data.get("bounces", 0))
	p.arc = bool(data.get("arc", false))
	p.fuse = float(data.get("fuse", 0.0))
	p.explode_radius = float(data.get("explode_radius", 0.0))
	p.explode_damage = float(data.get("explode_damage", p.damage))
	p._owner_faction = target_group
	p._arc_height = float(data.get("arc_height", 3.0))
	p.split_on_hit = int(data.get("split_on_hit", 0))
	p.split_damage_pct = float(data.get("split_damage_pct", 0.4))
	p.split_spread = float(data.get("split_spread", 0.5))
	p.zone_on_land = data.get("zone_on_land", {})
	# 命中回调（玩家远程普攻接管结算用，见该字段的说明）
	p.on_hit = data.get("on_hit", Callable())
	# 保留原始配置：分裂时要据此复制出同类型小弹
	p.data = data

	p.position = data.get("position", Vector3.ZERO)
	p._arc_start = p.position
	p._arc_landing = p.position + p.direction * p.speed * maxf(p.lifetime, 1.0)

	parent.add_child(p)
	p._build_visual()
	return p


## 把同一份 data 交给 C++ 模拟核。返回是否成功接管。
##
## **为什么复用同一份 data 字典**：分流只该换后端，不该换接口。
## 调用方（敌人 _shoot / 技能系统）构造 data 的方式完全不变，
## 开关一翻就切后端。
static func _spawn_via_sim(data: Dictionary, parent: Node3D, target_group: String) -> bool:
	var mgr := _sim_manager(parent)
	if mgr == null:
		return false
	return int(mgr.call("spawn_from_data", data, target_group)) >= 0


## 找场景里的投射物管理器（没有则返回 null —— 此时回退旧路径）
static func _sim_manager(from: Node) -> Node:
	if from == null:
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	var found := tree.get_nodes_in_group("projectile_manager")
	if found.is_empty():
		return null
	return found[0]


## 构建视觉与碰撞体（Area3D 自身即命中区）
func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)
	monitoring = true
	# **命中判定靠 mask 与目标的 layer 相交**：Area3D 的 mask 默认只含第 1 层，
	# 而敌人占第 2 层（见 enemy_base.ENEMY_LAYER）——不显式打开就永远
	# 收不到 body_entered，投射物类技能全部"放出去没效果"。
	collision_mask = PROJECTILE_MASK
	collision_layer = 0   # 投射物本身不需要被别的物体检测

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	var c := element_color(element)
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	add_child(mesh)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# 引信阶段：停住不动，倒计时结束爆炸
	if _fuse_armed:
		_fuse_timer -= delta
		if _fuse_timer <= 0.0:
			_explode()
		return

	_elapsed += delta
	if _elapsed >= lifetime:
		if fuse > 0.0:
			_arm_fuse()
			return
		queue_free()
		return

	if arc:
		_advance_arc(delta)
	else:
		position += direction * speed * delta


## 抛物线：水平线性推进 + 垂直抛物线（sulfur_elemental 的弧线轨迹）
func _advance_arc(delta: float) -> void:
	_arc_elapsed += delta
	var t := clampf(_arc_elapsed / maxf(lifetime, 0.01), 0.0, 1.0)
	var base := _arc_start.lerp(_arc_landing, t)
	base.y += 4.0 * _arc_height * t * (1.0 - t)   # 标准抛物线 4h·t(1-t)
	position = base


## 落地进入引信倒计时（延时炸弹）
func _arm_fuse() -> void:
	_fuse_armed = true
	_fuse_timer = fuse
	# 引信期间视觉闪烁提示
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		var tween := create_tween().set_loops()
		tween.tween_property(mesh, "scale", Vector3(1.3, 1.3, 1.3), 0.15)
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.15)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(_owner_faction):
		return
	if _hit_targets.has(body):
		return
	_hit_targets.append(body)
	# 命中回调：调用方接管结算（玩家远程普攻走这条，见 on_hit 的说明）。
	# **放在默认结算之前**并 return——两者不能都跑，否则一次命中扣两次血。
	if on_hit.is_valid():
		on_hit.call(body, damage)
	else:
		_deal_damage(body)
	_hit_count += 1

	# 命中分裂（虚空弓手 9-4 / 混沌幼蛛）：射出 N 枚散射小弹。
	# 只分裂一次，否则会无限繁殖。
	if split_on_hit > 0:
		_spawn_split()
		split_on_hit = 0

	# 弹射：命中后改变方向继续飞（弹向下一个目标或反弹）
	if _bounced < bounces:
		_bounced += 1
		_do_bounce()
		return

	if _hit_count > pierce_count:
		_spawn_land_zone()
		if fuse > 0.0:
			_arm_fuse()
		else:
			queue_free()


## 命中时分裂出散射小弹（只分裂一次）
func _spawn_split() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in split_on_hit:
		# 以飞行方向为中心均匀散射
		var t := 0.0 if split_on_hit <= 1 else (float(i) / float(split_on_hit - 1)) * 2.0 - 1.0
		var ang := t * split_spread
		var d := data.duplicate()
		d["direction"] = direction.rotated(Vector3.UP, ang)
		d["damage"] = damage * split_damage_pct
		d["bounces"] = 0
		d["pierce_count"] = 0
		d["lifetime"] = 1.2
		d["position"] = global_position
		Projectile.spawn(d, parent, _owner_faction)


## 命中/结束时在原地留下区域（熔炉哨兵 4-4 射击点火焰区）
func _spawn_land_zone() -> void:
	if zone_on_land.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return
	var spec := zone_on_land.duplicate()
	spec["position"] = global_position
	DamageZone.spawn(spec, parent)


## 弹射：转向到最近的未命中目标；找不到则原路反弹
func _do_bounce() -> void:
	var next := _nearest_unhit_target()
	if next != null:
		direction = (next.global_position - global_position).normalized()
	else:
		direction = -direction
	# 弹射后重置寿命，保证能飞到新目标
	_elapsed = 0.0
	lifetime = maxf(lifetime, 1.5)


func _nearest_unhit_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(_owner_faction):
		if _hit_targets.has(n):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


## 对目标结算伤害（近战/投射物统一走元素管线）
func _deal_damage(body: Node3D) -> void:
	var target_def := 0.0
	var gm := get_tree().root.get_node_or_null("GameManager")
	if gm:
		target_def = float(gm.stat_value("def")) if _owner_faction == TARGET_PLAYER else float(body.get("defense") if body.get("defense") != null else 0.0)
	var result := DamagePipeline.elemental_attack(damage, 1.0, 0.0, target_def, elem_enum)
	body.call("take_damage", result.damage)
	var bus := get_tree().root.get_node_or_null("EventBus")
	if bus:
		bus.damage_popup.emit(body.global_position, result.damage, "normal")
	# 元素叠层：与近战一致，投射物也应叠元素
	if elem_enum >= 0:
		var tb = body.get("buffs")
		if tb != null:
			var out: Dictionary = ElementDamage.attack(tb, elem_enum)
			for ev in out.get("events", []):
				var ctrl_id: String = ElementDamage.control_for_event(str(ev))
				if ctrl_id != "":
					tb.apply(ctrl_id, "element")


## 引信爆炸：范围伤害（延时炸弹 / 落地爆炸）
func _explode() -> void:
	if explode_radius > 0.0:
		for n in get_tree().get_nodes_in_group(_owner_faction):
			var node := n as Node3D
			if global_position.distance_to(node.global_position) <= explode_radius:
				_deal_damage(node)
	var bus := get_tree().root.get_node_or_null("EventBus")
	if bus:
		bus.screen_shake.emit(0.2, 0.15)
	queue_free()


## 元素配色（键名与 ElementDefs 一致）
static func element_color(element: String) -> Color:
	match element:
		"fire": return Color(1.0, 0.3, 0.1)
		"frost": return Color(0.3, 0.7, 1.0)
		"static": return Color(1.0, 0.9, 0.2)
		"poison": return Color(0.2, 0.8, 0.2)
		"earth": return Color(0.6, 0.45, 0.25)
		"wind": return Color(0.7, 0.9, 0.8)
		_: return Color(0.8, 0.8, 0.8)
