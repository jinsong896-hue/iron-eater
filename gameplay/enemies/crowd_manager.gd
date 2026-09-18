class_name CrowdManager
extends Node3D
## 海量单位管理器 —— CrowdSim 的房间级接线
##
## 职责边界：
##   · 拥有 CrowdSim 实例与 MultiMesh（渲染）
##   · 每物理帧推进一步模拟并同步渲染缓冲
##   · 消费死亡事件 → 同步计数 + 触发掉落
##   · 把房间墙体转成 AABB 障碍喂给模拟核
##
## **不负责**：命中判定（批次 5 接 combat_system）、机制/词缀（后续批次）。
##
## ## 为什么路由是 opt-in
## `MonsterDB` 条目带 `swarm: true` 才走本管理器；默认没有任何怪带这个标记。
## 这样分流能力就位但**不改变现有行为**——17 套门禁零破坏。
## 真正启用是"给选定的基础怪加 swarm 标记"这一数据决定，可单独评估。

## 死亡事件（供 room_controller 结算计数与掉落）
signal crowd_died(position: Vector3, is_elite: bool)
## 群体单位攻击玩家（供 room_controller 走正常受击结算）
signal crowd_attacked(position: Vector3, damage: float)

## 模拟核实例（真扩展或 GDScript 降级）
var sim: Node = null
## MultiMesh 渲染节点
var mmi: MultiMeshInstance3D = null
## 当前活跃单位数（含未同步的）
var active := 0

var _multimesh: MultiMesh = null
var _capacity := 0
var _player: Node3D = null
## id → 该单位的怪物配置（掉落时要用原始 monster dict）
var _spawn_meta: Dictionary = {}
## id → buff 宿主（按需创建，见 buffs_of）
var _hosts: Dictionary = {}


func _ready() -> void:
	sim = CrowdSimLoader.create()
	if sim == null:
		push_warning("CrowdManager：两条后端都不可用，群体模拟已禁用")
		set_physics_process(false)
		return
	add_child(sim)
	_capacity = CrowdSimLoader.capacity_limit()
	sim.call("setup", _capacity, 2.0)
	# 攻击参数：进 1.4 米每 1.2 秒打 8 点。
	# 数值取"基础杂兵"档——真正的差异化等批次 6 把怪物类型带进核里再说。
	if sim.has_method("set_attack_params"):
		sim.call("set_attack_params", 1.4, 1.2, 8.0)
	_setup_multimesh()
	_ensure_player()


## 配置 MultiMesh：实例数固定 = 容量，未存活的靠"缩放写 0"隐藏
##（与批次 1 调试场景同方案，见 world/debug/crowd_sim_debug.gd）
func _setup_multimesh() -> void:
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Swarm"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = _capacity
	# 占位网格：后续接角色图集时换成 billboard QuadMesh
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.9
	mm.mesh = mesh
	mmi.multimesh = mm
	_multimesh = mm
	add_child(mmi)


func _ensure_player() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and is_instance_valid(ps[0]):
		_player = ps[0]


## 把房间墙体转成 AABB 喂给模拟核。
## 障碍格式：每 4 个 float 一组 = min_x, min_z, max_x, max_z
func set_obstacles(aabbs: PackedFloat32Array) -> void:
	if sim != null:
		sim.call("set_obstacles", aabbs)


## 生成一个群体单位。返回 id（-1 = 池满或后端不可用）。
## monster：MonsterDB 条目（用于掉落与数值），可为空。
func spawn_unit(pos: Vector3, hp: float, speed: float, radius: float,
		scale: float, monster: Dictionary = {}) -> int:
	if sim == null:
		return -1
	var id := int(sim.call("spawn", pos.x, pos.z, hp, speed, radius, scale))
	if id < 0:
		return -1
	_spawn_meta[id] = monster
	active += 1
	return id


func despawn_unit(id: int) -> void:
	if sim == null:
		return
	if bool(sim.call("is_alive", id)):
		active = maxi(active - 1, 0)
	sim.call("despawn", id)
	_spawn_meta.erase(id)
	_free_host(id)


func is_alive(id: int) -> bool:
	return sim != null and bool(sim.call("is_alive", id))


func unit_position(id: int) -> Vector3:
	return sim.call("get_position", id) if sim != null else Vector3.ZERO


## 单位当前血量（测试/UI 血条用）
func unit_hp(id: int) -> float:
	return float(sim.call("get_hp", id)) if sim != null else 0.0


## 该单位对应的怪物配置（掉落用）
func monster_of(id: int) -> Dictionary:
	return _spawn_meta.get(id, {})


## 取（或创建）某单位的 buff 宿主。
##
## **为什么要宿主**：`BuffHolder` 需要一个 Node 才能工作，而群体单位不是
## 场景节点。没有它的话，元素叠层 / 审判印记 / 咒焰印记 / 装备触发词条
## 这些"给敌人挂状态"的效果在群体路径上全部失效——
## 同一个形态打 swarm 怪会少一整套交互。
##
## 宿主按需创建（不是每个单位都建）：绝大多数单位一生都不会被挂状态，
## 提前建一堆 Node 反而浪费。
func buffs_of(id: int) -> BuffHolder:
	if not is_alive(id):
		return null
	if _hosts.has(id):
		var h: CrowdUnitHost = _hosts[id]
		if is_instance_valid(h):
			# 每次取用时同步一次位置/数值（核里的坐标是权威的）
			h.bind(id, unit_position(id), _unit_atk(id), self)
			return h.buffs
	var host := CrowdUnitHost.new()
	host.name = "UnitHost_%d" % id
	add_child(host)
	host.bind(id, unit_position(id), _unit_atk(id), self)
	var holder := BuffHolder.new(host)
	_hosts[id] = host
	host.set_meta("holder", holder)
	return holder


## 单位攻击力（从 monster 配置取；缺省 10）
func _unit_atk(id: int) -> float:
	return float(monster_of(id).get("atk", 10.0))


## 单位当前坐标的便捷入口（脚本外部用）
func position_of(id: int) -> Vector3:
	return unit_position(id)


func _physics_process(delta: float) -> void:
	if sim == null or active == 0:
		return
	_ensure_player()
	var px := 0.0
	var pz := 0.0
	if _player != null and is_instance_valid(_player):
		px = _player.global_position.x
		pz = _player.global_position.z
	sim.call("step", delta, px, pz)
	_sync_render()
	_drain_deaths()


## 把模拟结果写进 MultiMesh（一次 buffer 拷贝，不逐实例 set_transform）
func _sync_render() -> void:
	if _multimesh == null:
		return
	_multimesh.buffer = sim.call("get_render_buffer")


## 消费死亡/攻击事件。
##
## **攻击事件必须导出**：模拟核不知道玩家的护甲/减伤/无敌帧，
## 也不该知道——它只报"谁在何时打了多少"，由 GDScript 侧走正常的
## `take_damage` 链路结算（与节点式敌人同一套规则）。
## 若在核里直接扣血，玩家堆防御就对群体单位无效——那种不一致极难察觉。
func _drain_deaths() -> void:
	var evs: Array = sim.call("drain_events")
	if evs.is_empty():
		return
	for e in evs:
		var d: Dictionary = e
		if str(d.get("type", "")) == "attack":
			crowd_attacked.emit(d.get("pos", Vector3.ZERO),
				float(d.get("damage", 0.0)))
			continue
		active = maxi(active - 1, 0)
		var dead_id := int(d.get("id", -1))
		_spawn_meta.erase(dead_id)
		_free_host(dead_id)
		crowd_died.emit(d.get("pos", Vector3.ZERO), bool(d.get("is_elite", false)))


## 释放单位对应的 buff 宿主（单位死亡时调，避免宿主节点泄漏）
func _free_host(id: int) -> void:
	if not _hosts.has(id):
		return
	var h = _hosts[id]
	_hosts.erase(id)
	if is_instance_valid(h):
		h.queue_free()


## 查询接口（批次 5 的命中判定用）
func query_circle(cx: float, cz: float, radius: float) -> PackedInt32Array:
	if sim == null:
		return PackedInt32Array()
	return sim.call("query_circle", cx, cz, radius)


func query_cone(ox: float, oz: float, dx: float, dz: float,
		half_angle: float, range_: float) -> PackedInt32Array:
	if sim == null:
		return PackedInt32Array()
	return sim.call("query_cone", ox, oz, dx, dz, half_angle, range_)


func apply_damage(ids: PackedInt32Array, amount: float) -> int:
	if sim == null:
		return 0
	return int(sim.call("apply_damage", ids, amount))


## 当前使用的后端名（日志/调试面板用）
func backend_name() -> String:
	return CrowdSimLoader.backend_name()
