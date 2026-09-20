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
##
## **带上 `id` 是必需的**：接收方要据此拿到 `CrowdUnitHost` 当攻击者节点，
## 玩家的「伤害反弹」词条才能打回这只怪。丢了 id 就只能传 null，
## 那条词缀在群体路径上会静默失效。
signal crowd_attacked(position: Vector3, damage: float, id: int)
## 群体单位触发了不朽免伤（回血后发，供特效/调试）
signal crowd_immortal(position: Vector3)

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

## 攻击参数的核默认值（`_ready` 里设的那组）。单位生成时按怪物配置收敛，
## 故这里留一份"没有怪物数据时"的基准。
const DEFAULT_ATTACK_RANGE := 1.4
const DEFAULT_ATTACK_INTERVAL := 1.2
const DEFAULT_ATTACK_ATK := 8.0

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
## id → 该单位的词缀状态（`CrowdAffixStore`；没有词缀的怪不登记）。
##
## 词缀本来挂在 `EnemyBase` 节点上，群体单位没有节点，故收在这里。
## 见 `gameplay/enemies/crowd_affix_store.gd`。
var _affixes: Dictionary = {}
## id → 该单位的基础移速（混沌改速度时要按基准值乘，不能原地累乘）
var _base_speed: Dictionary = {}
## 词缀计时用的随机源（不共享全局 rng——那个被地图生成占着）
var _affix_rng := RandomNumberGenerator.new()
## 单位攻击力合计（含词缀·强壮的加成），每次生成/死亡时重算并写回核
var _atk_total := 0.0
## 当前生效的攻击间隔（全体最小值；核里是全局单值）
var _atk_interval := DEFAULT_ATTACK_INTERVAL
## 上一帧的模拟增量——`damage_unit` 需要它来推进词缀计时器
var _last_delta := 1.0 / 60.0
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
	_affix_rng.randomize()
	# 攻击参数：进 1.4 米每 1.2 秒打 8 点。
	# 数值取"基础杂兵"档——真正的差异化等批次 6 把怪物类型带进核里再说。
	if sim.has_method("set_attack_params"):
		sim.call("set_attack_params", DEFAULT_ATTACK_RANGE, DEFAULT_ATTACK_INTERVAL,
			DEFAULT_ATTACK_ATK)
	_atk_interval = DEFAULT_ATTACK_INTERVAL
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
##
## **词缀在这里落地**：`AffixDB.apply()` 早把数值型词缀写进了 monster dict，
## 但群体路径此前只读到 `speed_pct`（生成时读一次），
## `attack_interval` / `knockback_mult` 与全部非数值词缀都无处生效。
## 本函数把攻击间隔与攻击力写进核，非数值词缀登记进 `CrowdAffixStore`。
func spawn_unit(pos: Vector3, hp: float, speed: float, radius: float,
		scale: float, monster: Dictionary = {}) -> int:
	if sim == null:
		return -1
	var id := int(sim.call("spawn", pos.x, pos.z, hp, speed, radius, scale))
	if id < 0:
		return -1
	_spawn_meta[id] = monster
	_base_speed[id] = speed
	# 先把单位的基础移速按词缀·快速调好，再交给核——核里 speed 只在 spawn
	# 时能写。早期版本漏了这一步，「快速」词缀挂到 swarm 怪上会**静默失效**
	#（词缀登记了、状态也对，就是速度没变）。
	_apply_spawn_affixes(id, monster)
	_set_unit_speed(id, _base_speed[id])
	active += 1
	return id


## 把某单位的当前移速写回模拟核。
##
## **核没有 `set_speed` 接口**（C++ 侧 `crowd_sim.cpp` 只暴露
## setup/spawn/despawn/step/set_obstacles/set_attack_params/set_stagger/
## set_elite/set_target），而 `speed` 是**每单位独立的数组、只在 spawn 时能写**。
## 故这里沿用 `teleport_unit` 那条路数：despawn + 在同位 spawn 更大的 hp，
## 池是 LIFO，刚释放的 id 会被下一次 spawn 立刻取回，故 id 不变、登记不用搬。
##
## 只给低频事件用（生成时一次、词缀·混沌改动时一次）。**攻击冷却与硬直会被
## 重置**——这正是混沌改速度时想要的（"突变"应当同时打断当前动作）。
func _set_unit_speed(id: int, speed: float) -> void:
	if sim == null or not bool(sim.call("is_alive", id)):
		return
	var hp := float(sim.call("get_hp", id))
	var pos: Vector3 = sim.call("get_position", id)
	sim.call("despawn", id)
	var new_id := int(sim.call("spawn", pos.x, pos.z, hp, speed, 0.35, 1.0))
	if new_id != id:
		# LIFO 池理论上必然同 id；真出现偏差就把登记搬过去，
		# 否则词缀/掉落数据会跟丢（静默失效，极难察觉）。
		_migrate_registration(id, new_id)


## 把生成时的词缀效果落到核与状态表上。
##
## 攻击间隔取**全体最小值**：核里 `attack_interval` 是全局单值，
## 做不到"这只快那只慢"。取最小值是刻意的保守选择——
## 宁可整批略快，也不让带「快速」词缀的怪比不带的还慢（那才是真 bug）。
##
## 调用方必须在返回后立刻调 `_set_unit_speed(id, _base_speed[id])`：
## 本函数只负责算出速度，写进核是调用方的事（`spawn_unit` 已经这么做了）。
func _apply_spawn_affixes(id: int, monster: Dictionary) -> void:
	var store := CrowdAffixStore.from_monster(monster)
	if store != null:
		# 词缀·快速由 AffixDB.apply 写成 `speed_pct`（百分比，基准 100）。
		# 记进 `spawn_mult` 而不是直接乘进 `base_speed`：混沌重掷要围绕
		# "生成时的速度"抖动，丢了这一项会把快速加成抹掉。
		var pct := float(monster.get("speed_pct", 100.0))
		store.base_speed = float(_base_speed.get(id, 4.0))
		store.spawn_mult = pct / 100.0 if pct > 0.0 else 1.0
		store.speed_mult = store.spawn_mult
		_base_speed[id] = store.base_speed * store.spawn_mult
		_affixes[id] = store
	var interval := float(monster.get("attack_interval", DEFAULT_ATTACK_INTERVAL))
	_atk_total += float(monster.get("atk", DEFAULT_ATTACK_ATK))
	_recompute_attack_params()
	# **顺序有讲究**：`_recompute_attack_params` 在 active<=0 时会**复位**成
	# 默认间隔，而本函数是在 `spawn_unit` 里 `active += 1` **之前**调的，
	# 故间隔必须写在它之后，否则第一个单位生成时会被复位覆盖
	#（表现为"攻击间隔永远是默认的 1.2，怪物的 attack_interval 不生效"）。
	_atk_interval = minf(_atk_interval, interval)


func despawn_unit(id: int) -> void:
	if sim == null:
		return
	if bool(sim.call("is_alive", id)):
		active = maxi(active - 1, 0)
	sim.call("despawn", id)
	_forget_unit(id)


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


## 该单位的词缀状态（没有词缀时返回 null）
func affixes_of(id: int) -> CrowdAffixStore:
	return _affixes.get(id, null)


## 把单位移到新坐标。
##
## **核没有直接设坐标的接口**（`set_stagger` / `set_target` 都不是），
## 故这里用「despawn + spawn」在同一 id 上重建——池是 LIFO，刚释放的 id
## 会被下一次 spawn 立刻取回，所以 id 不变，`_spawn_meta` 等登记也不用动。
##
## 只给低频事件用（当前唯一调用方是词缀·虚空的换位）。
## **攻击冷却与硬直会被重置**，对换位这种语义是可接受的。
func teleport_unit(id: int, pos: Vector3) -> void:
	if sim == null or not bool(sim.call("is_alive", id)):
		return
	var store: CrowdAffixStore = _affixes.get(id, null)
	var speed := float(_base_speed.get(id, 4.0))
	if store != null:
		speed *= store.speed_mult
	var hp := float(sim.call("get_hp", id))
	sim.call("despawn", id)
	var new_id := int(sim.call("spawn", pos.x, pos.z, hp, speed, 0.35, 1.0))
	if new_id != id:
		# LIFO 池理论上必然同 id；真出现偏差就把登记搬过去，
		# 否则词缀/掉落数据会跟丢（静默失效，极难察觉）。
		_migrate_registration(id, new_id)


## 清掉某单位在本管理器里的全部登记（死亡/移除时调）。
##
## 收在一个函数里：单位在 `_spawn_meta` / `_affixes` / `_base_speed` /
## `_hosts` 四处都有登记，漏清任何一处都是静默泄漏——
## 而 id 会被池复用，泄漏的旧登记会**串到新单位上**（表现为
## "这只怪莫名其妙带着上一只的词缀/掉落"）。
func _forget_unit(id: int) -> void:
	# 攻击力合计要同步扣掉，否则平均值会随死亡越算越低
	var m := monster_of(id)
	if not m.is_empty():
		_atk_total = maxf(_atk_total - float(m.get("atk", DEFAULT_ATTACK_ATK)), 0.0)
	_spawn_meta.erase(id)
	_affixes.erase(id)
	_base_speed.erase(id)
	_free_host(id)


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


## 取（或创建）某单位的节点代理 `CrowdUnitHost`。
##
## 存在的理由：`player.take_damage(amount, from)` 的 `from` 要一个 Node3D，
## 群体单位不是节点，只能拿宿主顶替（它有 `take_damage`，把反伤转回核）。
## 走 `buffs_of` 那条路要再穿一层 `BuffHolder._target`，那是私有字段；
## 这里直接把宿主暴露出来，语义清楚也不会随 BuffHolder 内部改名而断。
func host_of(id: int) -> CrowdUnitHost:
	if buffs_of(id) == null:
		return null
	return _hosts.get(id, null)


## 单位攻击力（从 monster 配置取；缺省 10）
func _unit_atk(id: int) -> float:
	return float(monster_of(id).get("atk", 10.0))


## 单位当前坐标的便捷入口（脚本外部用）
func position_of(id: int) -> Vector3:
	return unit_position(id)


func _physics_process(delta: float) -> void:
	if sim == null or active == 0:
		return
	_last_delta = delta
	_ensure_player()
	_tick_affixes(delta)
	var px := 0.0
	var pz := 0.0
	if _player != null and is_instance_valid(_player):
		px = _player.global_position.x
		pz = _player.global_position.z
	sim.call("step", delta, px, pz)
	_sync_render()
	_drain_deaths()


## 推进词缀计时器。
##
## 只为**真正带词缀**的单位建条目（`CrowdAffixStore.from_monster` 没词缀返回
## null），所以这里绝大多数时候是空字典遍历，开销可忽略。
##
## 混沌改了移速时必须**立刻写回核**：核里 `speed` 只在 spawn 时能写，
## 故走 `_set_unit_speed`（despawn + 同位 spawn，LIFO 保证 id 不变）。
## 代价是这次"突变"会顺带重置该单位的攻击冷却——对混沌这种
## "随机突变"的语义反而是想要的。
func _tick_affixes(delta: float) -> void:
	if _affixes.is_empty():
		return
	for raw_id in _affixes:
		var id := int(raw_id)
		var store: CrowdAffixStore = _affixes[raw_id]
		if store.tick(delta, _affix_rng):
			# 混沌真的改了移速——按新的倍率写回核（走 despawn+spawn 那条路）
			_base_speed[id] = float(_base_speed.get(id, 4.0))
			_set_unit_speed(id, _base_speed[id])


## 重算并写回核的攻击参数。
##
## 核只有一组全局 `attack_*`，做不到逐单位差异化，故：
##   · 间隔取所有单位的**最小值**（宁可整批略快，也不让带「快速」的怪更慢）
##   · 攻击力取**存活单位的平均值**（含「强壮」加成）
## 纯基础怪时两者退化为同一档，与旧行为一致。
func _recompute_attack_params() -> void:
	if sim == null or not sim.has_method("set_attack_params"):
		return
	if active <= 0:
		sim.call("set_attack_params", DEFAULT_ATTACK_RANGE, DEFAULT_ATTACK_INTERVAL,
			DEFAULT_ATTACK_ATK)
		_atk_interval = DEFAULT_ATTACK_INTERVAL
		return
	sim.call("set_attack_params", DEFAULT_ATTACK_RANGE, _atk_interval,
		_atk_total / float(active))


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
			var atk_id := int(d.get("id", -1))
			var pos: Vector3 = d.get("pos", Vector3.ZERO)
			var dmg := float(d.get("damage", 0.0))
			# 词缀·吸血：这一击按比例回自己的血
			_apply_lifesteal(atk_id, dmg)
			# 词缀·燃烧/冰冻/虚空：作用于玩家，必须在发信号之前——
			# `crowd_attacked` 的接收方（room_controller）只负责结算玩家受击，
			# 不知道词缀的存在，混在一起会让"谁该处理什么"变模糊。
			_apply_on_hit_affixes(atk_id, pos)
			crowd_attacked.emit(pos, dmg, atk_id)
			continue
		active = maxi(active - 1, 0)
		var dead_id := int(d.get("id", -1))
		_forget_unit(dead_id)
		_recompute_attack_params()
		crowd_died.emit(d.get("pos", Vector3.ZERO), bool(d.get("is_elite", false)))


## 词缀·吸血：按本次造成的伤害回自己的血。
##
## 核没有"回血"接口（`apply_damage` 只扣），故这里用
## 「当前血量 + 回复量」重新 spawn——与 `teleport_unit` 同一条路数。
## 只对**带吸血词缀**的单位走，其余单位零开销。
func _apply_lifesteal(id: int, damage: float) -> void:
	var store: CrowdAffixStore = _affixes.get(id, null)
	if store == null or store.lifesteal_pct <= 0.0 or damage <= 0.0:
		return
	if not bool(sim.call("is_alive", id)):
		return
	var heal := damage * store.lifesteal_pct
	var hp := float(sim.call("get_hp", id)) + heal
	var pos: Vector3 = sim.call("get_position", id)
	var speed := float(_base_speed.get(id, 4.0)) * store.speed_mult
	sim.call("despawn", id)
	var new_id := int(sim.call("spawn", pos.x, pos.z, hp, speed, 0.35, 1.0))
	if new_id != id:
		_migrate_registration(id, new_id)


## 词缀·燃烧/冰冻/虚空：单位打中玩家时作用于玩家。
##
## 燃烧/冰冻走玩家侧既有的 `BuffHolder` 词条（`burn` / `frost`），
## 与节点侧 `enemy_base._apply_melee_mechanics` 施加的是同一套。
func _apply_on_hit_affixes(id: int, _pos: Vector3) -> void:
	var store: CrowdAffixStore = _affixes.get(id, null)
	if store == null or not (store.burn or store.freeze or store.void_hit):
		return
	_ensure_player()
	store.on_hit_player(_player)
	if store.void_hit and _player != null and is_instance_valid(_player):
		var plan := store.plan_swap(_player, unit_position(id))
		if not plan.is_empty():
			teleport_unit(id, plan["unit_to"])
			# 直接写 `global_position`，**不要调 `force_position`**：
			# 那个方法全项目都不存在（`enemy_base._swap_with_player` 里的
			# `has_method` 检查永远走 else 分支），调它只会静默失败——
			# 单位瞬移走了、玩家留在原地，看起来像"虚空词缀把怪送走了"。
			(_player as Node3D).global_position = plan["player_to"]


## 把某单位在本管理器里的登记从 old_id 搬到 new_id。
##
## 只在池没按 LIFO 返回同一 id 时走（理论上不会），但漏了会**静默**丢词缀/掉落。
func _migrate_registration(old_id: int, new_id: int) -> void:
	if _spawn_meta.has(old_id):
		_spawn_meta[new_id] = _spawn_meta[old_id]
		_spawn_meta.erase(old_id)
	if _affixes.has(old_id):
		_affixes[new_id] = _affixes[old_id]
		_affixes.erase(old_id)
	if _base_speed.has(old_id):
		_base_speed[new_id] = _base_speed[old_id]
		_base_speed.erase(old_id)
	if _hosts.has(old_id):
		_hosts[new_id] = _hosts[old_id]
		_hosts.erase(old_id)


## 回复单位血量（词缀·不朽用）。
##
## 核没有"回血"接口（`apply_damage` 只扣），故走与 `teleport_unit` 同一条
## 路数：despawn + 在同位 spawn 更大的 hp，池 LIFO 保证 id 不变。
## 移速按当前 `speed_mult` 带入，免得回一次血把混沌的改动抹掉。
func heal_unit(id: int, amount: float) -> void:
	if sim == null or amount <= 0.0 or not bool(sim.call("is_alive", id)):
		return
	var store: CrowdAffixStore = _affixes.get(id, null)
	var speed := float(_base_speed.get(id, 4.0))
	if store != null:
		speed *= store.speed_mult
	var pos: Vector3 = sim.call("get_position", id)
	var hp := float(sim.call("get_hp", id)) + amount
	sim.call("despawn", id)
	var new_id := int(sim.call("spawn", pos.x, pos.z, hp, speed, 0.35, 1.0))
	if new_id != id:
		_migrate_registration(id, new_id)


## 结算一次**由 GDScript 侧发起**的伤害（玩家近战/投射物命中群体单位时调）。
##
## **词缀·复仇与不朽必须在扣血之前介入**，否则：
##   · 复仇会漏掉"这一击把人打死了"的那次反伤
##   · 不朽来不及把致命伤挡下来（扣完血单位已经没了）
##
## `attacker` 是玩家节点（复仇反伤用），`pos` 是伤害数字的位置。
## 返回实际造成的伤害（不朽免伤后可能是 0）。
func damage_unit(id: int, amount: float, attacker: Node, pos: Vector3) -> float:
	if sim == null or not bool(sim.call("is_alive", id)):
		return 0.0
	var store: CrowdAffixStore = _affixes.get(id, null)
	var dealt := amount
	if store != null:
		# 先推进计时器：不朽的免伤窗口靠它递减。群体单位可能被"打了就死"
		# 而一直没轮到物理帧，不能指望 `_physics_process` 一定跑过。
		store.tick(_last_delta, _affix_rng)
		var m: Dictionary = _spawn_meta.get(id, {})
		var hp := float(sim.call("get_hp", id))
		var max_hp := maxf(float(m.get("hp", hp)), 0.001)
		var r := store.note_damage(amount, hp, max_hp, attacker, pos)
		if r < 0.0:
			# 不朽触发：本次免伤，改为回血
			heal_unit(id, store.immortal_heal_amount(max_hp))
			crowd_immortal.emit(pos)
			return 0.0
		dealt = r
	if dealt > 0.0:
		sim.call("apply_damage", PackedInt32Array([id]), dealt)
	# 立刻排空事件：调用方（玩家/投射物）当帧不会跑物理帧，
	# 不排空的话死亡事件要等下一帧才消费，`enemies_alive` 会短暂多算一只。
	_drain_deaths()
	return dealt


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
##
## **刻意绕过 `damage_unit`**：清场是"无条件移除"，不该被词缀·不朽
## 的免伤挡下来（那会让清场漏掉恰好处于免伤期的单位，房间永远清不空）。
## 换句话说这里的语义是「移除」，不是「造成伤害」。
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
