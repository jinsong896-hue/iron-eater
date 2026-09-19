class_name ProjectileManager
extends Node3D
## 投射物管理器 —— ProjectileSim 的场景级接线
##
## 职责：
##   · 拥有 ProjectileSim 与 MultiMesh（渲染）
##   · 每物理帧组装**目标表** → step → 同步渲染 → 消费事件
##   · 把命中/爆炸/到期事件接回既有伤害链路（DamagePipeline + 元素叠层）
##
## **不负责**：投射物的行为逻辑（全在核里）、伤害公式（在 DamagePipeline）。
##
## ## 目标引用怎么回溯
## 核只报一个 `target_id`（整数 ref），管理器要据此找回真实对象。
## 两类目标来源不同：
##   · 节点式敌人（精英/Boss）——场景树里的节点
##   · 群体单位（CrowdSim）——另一个核里的 id，**不在场景树**
## 故 ref 约定为「本管理器 _refs 数组的下标」：
## 每帧组装目标表时把来源登记进去，事件回来时按下标取。

## 每次投射物命中（供音效/统计挂钩）
signal projectile_hit(world_pos: Vector3, damage: float, kind: String)

const CAPACITY := 4096
## 投射物视觉：小球
const BULLET_SCALE := 0.18

var sim: Node = null
var mmi: MultiMeshInstance3D = null
var active := 0

var _multimesh: MultiMesh = null
var _player: Node3D = null
## 本帧目标来源：[{kind:"node", node:Node} | {kind:"crowd", id:int}]
var _refs: Array = []
## 投射物 id → 它的 zone_on_land 规格。
##
## 核只报 `has_zone` 布尔（它不关心区域参数），具体参数在这里存着。
## 用完即删（事件到达后清），避免长期占用。
var _zone_specs: Dictionary = {}
## 最近一次 _spawn_zone 用的规格（供测试断言参数确实透传了）
var _zone_spec: Dictionary = {}


func _ready() -> void:
	# 加入组：Projectile.spawn 的分流靠这个组找管理器
	add_to_group("projectile_manager")
	sim = ProjectileSimLoader.create()
	if sim == null:
		push_warning("ProjectileManager：两条后端都不可用，投射物核已禁用")
		set_physics_process(false)
		return
	add_child(sim)
	sim.call("setup", CAPACITY)
	sim.call("set_base_scale", BULLET_SCALE)
	_setup_multimesh()
	_ensure_player()


func _setup_multimesh() -> void:
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Projectiles"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = CAPACITY
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mm.mesh = mesh
	mmi.multimesh = mm
	_multimesh = mm
	add_child(mmi)


func _ensure_player() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and is_instance_valid(ps[0]):
		_player = ps[0]


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	_sync_targets()
	sim.call("step", delta)
	_sync_render()
	_drain_events()


## 组装目标表：节点式敌人 + 群体单位。
##
## 群体单位**必须走批量接口**（get_position_buffer）：逐 id 调
## get_position 在 2000 单位时就是 2000 次跨语言调用，光 FFI 开销
## 就吃掉整帧预算。
func _sync_targets() -> void:
	_refs.clear()
	var targets := PackedFloat32Array()
	var factions := PackedInt32Array()

	# ① 节点式敌人（打敌人的投射物找它们）
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		if not e.has_method("take_damage"):
			continue
		# 破坏物也在 enemies 组里，但它们不是战斗目标
		if e.get("prop_kind") != null:
			continue
		var en := e as Node3D
		var radius := float(en.get("radius")) if en.get("radius") != null else 0.5
		targets.append(en.global_position.x)
		targets.append(en.global_position.z)
		targets.append(maxf(radius, 0.3))
		targets.append(float(_refs.size()))
		factions.append(0)   # FACTION_ENEMY
		_refs.append({"kind": "node", "node": en})

	# ② 玩家（打玩家的投射物找它）
	_ensure_player()
	if _player != null and is_instance_valid(_player):
		targets.append(_player.global_position.x)
		targets.append(_player.global_position.z)
		targets.append(0.5)
		targets.append(float(_refs.size()))
		factions.append(1)   # FACTION_PLAYER
		_refs.append({"kind": "player"})

	# ③ 群体单位（走批量坐标接口）
	var crowd = _crowd_manager()
	if crowd != null and int(crowd.get("active")) > 0:
		var buf: PackedFloat32Array = crowd.call("get_position_buffer")
		var n := buf.size() / 4
		for i in n:
			targets.append(buf[i * 4 + 0])   # x
			targets.append(buf[i * 4 + 1])   # z
			targets.append(0.35)             # 半径
			targets.append(float(_refs.size()))
			factions.append(0)               # FACTION_ENEMY
			_refs.append({"kind": "crowd", "id": int(buf[i * 4 + 2])})

	sim.call("set_targets", targets, factions)


func _sync_render() -> void:
	if _multimesh == null:
		return
	_multimesh.buffer = sim.call("get_render_buffer")


## 消费事件：命中 / 爆炸 / 到期
func _drain_events() -> void:
	var evs: Array = sim.call("drain_events")
	if evs.is_empty():
		return
	for e in evs:
		var d: Dictionary = e
		var kind := str(d.get("type", ""))
		match kind:
			"hit":
				_deal_hit(d)
			"explode":
				_deal_explode(d)
			"expire":
				_deal_expire(d)
	active = int(sim.call("get_active_count"))


## 单目标命中：走既有伤害链路（与旧 Projectile._deal_damage 同口径）
func _deal_hit(d: Dictionary) -> void:
	var ref := int(d.get("target_id", -1))
	var target := _resolve(ref)
	if target == null:
		return
	var pos: Vector3 = d.get("pos", Vector3.ZERO)
	var dmg := float(d.get("damage", 0.0))
	var elem := int(d.get("elem", -1))
	_apply_damage_to(target, dmg, elem, pos)
	# 命中后原地留区域（策划「命中/有效期结束后原地生成区域」）
	if bool(d.get("has_zone", false)):
		_spawn_zone(pos, int(d.get("id", -1)))


## 引信爆炸：半径内**全组**结算（与旧 Projectile._explode 同口径）
func _deal_explode(d: Dictionary) -> void:
	var pos: Vector3 = d.get("pos", Vector3.ZERO)
	var radius := float(d.get("explode_radius", 0.0))
	var dmg := float(d.get("explode_damage", 0.0))
	var elem := int(d.get("elem", -1))
	if radius > 0.0:
		for t in _all_targets():
			if t is Node3D and is_instance_valid(t):
				if (t as Node3D).global_position.distance_to(pos) <= radius:
					_apply_damage_to(t, dmg, elem, pos)
	# 震屏（旧实现也发这个）
	EventBus.screen_shake.emit(0.2, 0.15)
	if bool(d.get("has_zone", false)):
		_spawn_zone(pos, int(d.get("id", -1)))


## 到期消散：可能要在原地留区域
func _deal_expire(d: Dictionary) -> void:
	if bool(d.get("has_zone", false)):
		_spawn_zone(d.get("pos", Vector3.ZERO), int(d.get("id", -1)))


## 对单个目标结算伤害 + 元素叠层。
##
## **防御按阵营取**（与旧实现一致）：打玩家取玩家的 def，
## 打敌人取该怪的 defense。
## `take_damage` **单参**调用 ⇒ 玩家侧伤害反射不触发（旧实现即如此，
## 是有意为之），但无敌帧/翻滚免疫/护盾/连击减伤全部照常。
func _apply_damage_to(target: Object, dmg: float, elem: int, popup_pos: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_def := 0.0
	var gm := get_node_or_null("/root/GameManager")
	if target is Node and (target as Node).is_in_group("player"):
		if gm != null:
			target_def = float(gm.call("stat_value", "def"))
	else:
		var dv = target.get("defense")
		target_def = float(dv) if dv != null else 0.0

	var result := DamagePipeline.elemental_attack(dmg, 1.0, 0.0, target_def, elem)
	target.call("take_damage", result.damage)
	EventBus.damage_popup.emit(popup_pos, result.damage, "normal")
	projectile_hit.emit(popup_pos, result.damage, "normal")

	# 元素叠层：与近战一致，投射物也应叠元素
	if elem >= 0:
		var tb = target.get("buffs")
		if tb != null:
			var out: Dictionary = ElementDamage.attack(tb, elem)
			for ev in out.get("events", []):
				var ctrl_id: String = ElementDamage.control_for_event(str(ev))
				if ctrl_id != "":
					tb.apply(ctrl_id, "element")


## 原地生成区域（zone_on_land）。
##
## **参数必须透传**：`shot_fire_zone`（熔炉哨兵）声明的
## `radius:2.0 / duration:4.0 / damage:20.0` 与默认值差很远——
## 早期版本在这里写死了参数，实际生成的是 `damage:4.0` 的弱化区域，
## 机制强度被静默削掉。
func _spawn_zone(pos: Vector3, bullet_id: int = -1) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spec: Dictionary = _zone_specs.get(bullet_id, {})
	_zone_specs.erase(bullet_id)   # 用完即删
	if spec.is_empty():
		# 兜底：核报了 has_zone 但没有规格（不该发生）
		spec = {"radius": 2.0, "duration": 3.0, "damage": 4.0, "tick_interval": 0.5}
	spec = spec.duplicate()
	spec["position"] = pos
	_zone_spec = spec   # 供测试断言透传
	DamageZone.spawn(spec, parent)


## ref → 真实对象
func _resolve(ref: int) -> Object:
	if ref < 0 or ref >= _refs.size():
		return null
	var r: Dictionary = _refs[ref]
	match str(r.get("kind", "")):
		"node":
			var n = r.get("node")
			return n if is_instance_valid(n) else null
		"player":
			return _player if (_player != null and is_instance_valid(_player)) else null
		"crowd":
			# 群体单位没有节点对象——伤害由 CrowdManager 结算。
			# 这里返回 null 是**有意的**：群体单位不接投射物伤害
			#（保持现状：它们只被玩家近战/技能直接打）。
			return null
	return null


## 全部可被爆炸波及的目标（节点 + 玩家）
func _all_targets() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and is_instance_valid(e) and e.has_method("take_damage"):
			out.append(e)
	_ensure_player()
	if _player != null and is_instance_valid(_player):
		out.append(_player)
	return out


func _crowd_manager():
	var node: Node = get_parent()
	while node != null:
		if node.get("current_room_node") != null:
			var room = node.get("current_room_node")
			if is_instance_valid(room):
				var ctrl = room.get_node_or_null("RoomController")
				if ctrl != null:
					var mgr = ctrl.get("_crowd_mgr")
					if mgr != null and is_instance_valid(mgr):
						return mgr
			return null
		node = node.get_parent()
	return null


# ============================================================
# 生成入口（供 Projectile 分流调用）
# ============================================================

## 用旧的 data 字典格式生成一发投射物。返回核里的 id（-1 = 失败）。
## **保持与旧 Projectile.spawn 的 data 键名一致**，这样分流开关
## 只是把同一份 data 交给不同后端，调用方无感。
func spawn_from_data(data: Dictionary, faction: String) -> int:
	if sim == null:
		return -1
	var dir: Vector3 = data.get("direction", Vector3.FORWARD)
	var pos: Vector3 = data.get("position", Vector3.ZERO)
	var elem_str := str(data.get("element", ""))
	var elem_enum := ElementDamage.elem_from_key(elem_str) if not elem_str.is_empty() else -1
	var zone: Dictionary = data.get("zone_on_land", {})
	var id := int(sim.call("spawn", {
		"x": pos.x, "y": pos.y, "z": pos.z,
		"dx": dir.x, "dz": dir.z,
		"speed": float(data.get("speed", 12.0)),
		"damage": float(data.get("damage", 10.0)),
		"lifetime": float(data.get("lifetime", 2.0)),
		"elem": elem_enum,
		"faction": 1 if faction == "player" else 0,
		"pierce": int(data.get("pierce_count", 0)),
		"bounces": int(data.get("bounces", 0)),
		"arc": bool(data.get("arc", false)),
		"arc_height": float(data.get("arc_height", 3.0)),
		"fuse": float(data.get("fuse", 0.0)),
		"explode_radius": float(data.get("explode_radius", 0.0)),
		"explode_damage": float(data.get("explode_damage", 0.0)),
		"split_count": int(data.get("split_on_hit", 0)),
		"split_pct": float(data.get("split_damage_pct", 0.4)),
		"split_spread": float(data.get("split_spread", 0.5)),
		"has_zone": 0 if zone.is_empty() else 1,
	}))
	if id >= 0:
		active = int(sim.call("get_active_count"))
		# 记下这发子弹的落地区域规格（事件回来时用）
		if not zone.is_empty():
			_zone_specs[id] = zone.duplicate()
	return id


func backend_name() -> String:
	return ProjectileSimLoader.backend_name()
