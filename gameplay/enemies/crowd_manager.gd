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

## 核产出的渲染缓冲：每实例 12 个 float（3×4 变换矩阵）。
## **这是核的契约，两侧核实现一致**（C++ `crowd_sim.cpp:get_render_buffer`、
## 降级侧 `crowd_sim_fallback.gd:get_render_buffer`），别改。
const RENDER_STRIDE := 12
## 本管理器 MultiMesh 的实例步长：12 个变换 + 4 个精灵格 = 16。
##
## **必须与 `use_custom_data` 相符**：开了 custom_data 实例就是 16 个 float，
## 给 `multimesh.buffer` 赋 12 步长的数组会被 Godot 直接拒收
##（"different size from the Multimesh's existing buffer"），
## 表现为群体单位一只都不显示 + 每帧一条错误日志。
const INSTANCE_STRIDE := 16

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
##
## ## 精灵格怎么传给着色器
## 核给的渲染缓冲每条实例只有 12 个 float（3×4 变换），**没有精灵格的位置**。
## 精灵格走 MultiMesh 自带的 `custom_data`：开 `use_custom_data` 后每条实例
## 变成 16 个 float，末尾 4 个自由使用（已实测确认偏移是 [12..15]）。
##
## 核的缓冲**长度对不上本 MultiMesh**（12 vs 16），故 `_sync_render` 里
## 必须做一次 12→16 的重排，不能直接把核的数组赋给 `multimesh.buffer`。
func _setup_multimesh() -> void:
	mmi = MultiMeshInstance3D.new()
	mmi.name = "Swarm"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# **必须在 instance_count 之前开**：Godot 不允许在已有实例时切换
	# custom_data / colors 开关（报 "Instance count must be 0 to toggle"）。
	mm.use_custom_data = true
	mm.instance_count = _capacity
	# billboard 平面：顶点是**单位**尺寸，实际大小由核写进缓冲的缩放决定。
	# 1.0 米见方 ≈ 一格（CELL_SIZE=1.0），与旧胶囊占位同量级。
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mmi.multimesh = mm
	mmi.material_override = _build_billboard_material()
	_multimesh = mm
	add_child(mmi)


## 造 billboard 材质。拿不到精灵表时返回 null——
## 此时 MultiMesh 会用 QuadMesh 的默认白材质，单位显示为白方块，
## 比整批不渲染好排查（至少能看到数量与位置是对的）。
func _build_billboard_material() -> ShaderMaterial:
	var tex := SpriteDefs.sheet()
	if tex == null:
		push_warning("CrowdManager：精灵表 %s 加载失败，单位退化为白色方块" % SpriteDefs.SHEET_PATH)
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load("res://rendering/shaders/unit_billboard.gdshader")
	mat.set_shader_parameter("albedo_texture", tex)
	return mat


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


## 全体单位坐标的批量缓冲，每单位 4 个 float：x, z, id, 保留。
##
## **给投射物管理器喂目标表用**。必须批量——逐 id 调 `unit_position()`
## 在 2000 单位时就是 2000 次跨语言调用，光 FFI 开销就吃掉整帧预算。
## 返回的是底层数组的副本（C++ 侧每次新建 PackedFloat32Array）。
func get_position_buffer() -> PackedFloat32Array:
	if sim == null:
		return PackedFloat32Array()
	return sim.call("get_position_buffer")


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
			# 宿主自己持有 holder，**不能写 `h.buffs`**——
			# CrowdUnitHost 没有这个属性，取属性会抛错，而且错误发生在
			# 本函数内部，调用方拿不到返回值（拿到的是 null），
			# 表现为"元素叠层对 swarm 怪静默失效"。
			# 只有投射物会撞上这条：近战每次命中都调本函数，早就把宿主建好了。
			var existing: BuffHolder = h.get_meta("holder")
			return existing
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
##
## **不能直接赋值**：核按每实例 12 个 float 产出（3×4 变换），而本 MultiMesh
## 开了 `use_custom_data` ⇒ 每条实例 16 个 float。长度对不上时 Godot 会报
## "Cannot set a buffer on a Multimesh that is a different size" 并**整个丢弃**
## 这次赋值——表现为群体单位一只都不显示 + 每帧刷一条错误日志。
##
## 故这里做一次 12→16 的重排：逐条拷 12 个变换 float，精灵格写在末尾 4 个。
## 2048 单位下这是一次 32768 float 的拷贝，可忽略。
func _sync_render() -> void:
	if _multimesh == null:
		return
	var src: PackedFloat32Array = sim.call("get_render_buffer")
	var dst := PackedFloat32Array()
	dst.resize(_capacity * INSTANCE_STRIDE)
	for i in _capacity:
		var s := i * RENDER_STRIDE
		var d := i * INSTANCE_STRIDE
		for k in RENDER_STRIDE:
			dst[d + k] = src[s + k]
		# 精灵格：只给存活单位写。死单位的缩放是 0（着色器会塌掉顶点），
		# 写不写都画不出来，跳过省一次查表。
		var rect := SpriteDefs.uv_rect_for_monster(_spawn_meta.get(i, {}))
		dst[d + 12] = rect.x
		dst[d + 13] = rect.y
		dst[d + 14] = rect.z
		dst[d + 15] = rect.w
	_multimesh.buffer = dst


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


## 清空全部群体单位，走正常死亡路径（死亡事件照常经 `_drain_deaths` 导出）。
##
## 存在的理由：`RoomController.enemies_alive` 把节点式敌人与群体单位**算在一起**，
## 但两者的死亡入口完全不同（节点侧 `EnemyBase.die()` / 群体侧 `crowd_died`）。
## 任何"清场"的调用方只处理一半，就会让计数归不了零 → 房间永不清空 → 门永不开。
## 统一收在这里，调试命令与测试共用同一套清空逻辑。
##
## **走 `apply_damage` 而不是 `despawn_unit`**：后者是静默移除，不产死亡事件，
## 调用方（掉落、计数、特效）全都收不到通知——那正是"清场清不干净"的成因。
func kill_all_units() -> int:
	if sim == null or active == 0:
		return 0
	# 空间网格只在 `step()` 里重建：没跑过物理帧时 `query_circle` 恒返回空。
	# 故这里直接扫 id 空间（容量 2048，一次扫描可忽略），不依赖核的空间索引。
	var ids := PackedInt32Array()
	for i in range(_capacity):
		if bool(sim.call("is_alive", i)):
			ids.append(i)
	if ids.is_empty():
		return 0
	var kills := apply_damage(ids, 1.0e9)
	# **必须立刻排空事件**：死亡事件平时由 `_physics_process` → `_drain_deaths()`
	# 消费，而"清场"的调用方（调试命令、测试）在调用后**不会**再跑物理帧——
	# 不排空的话 `active` 不掉、`crowd_died` 不发，`enemies_alive` 就永远差一只，
	# 房间清不掉、门不开（实测踩到：killed=6 而 enemies_alive 仍为 1）。
	_drain_deaths()
	return kills


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
