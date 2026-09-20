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

## 扁平事件流的每事件 float 步长——必须与两侧核实现一致：
## C++ 侧 `projectile_sim.cpp` 的 EVENT_STRIDE，降级侧
## `projectile_sim_fallback.gd` 的 EVENT_STRIDE。改一处必须三处同改。
const EVENT_STRIDE := 11
## 事件类型（与 C++ 侧 proj::EventType 一致）
const EV_HIT := 0
const EV_EXPLODE := 1
const EV_EXPIRE := 2

## 核产出的渲染缓冲：每实例 12 个 float（3×4 变换矩阵）。
## **这是核的契约，两侧核实现一致**（C++ `projectile_core.cpp:fill_render_buffer`、
## 降级侧 `projectile_sim_fallback.gd:get_render_buffer`），别改。
const RENDER_STRIDE := 12
## 本管理器 MultiMesh 的实例步长：12 个变换 + 4 个颜色 = 16。
##
## **必须与 `use_colors` 相符**：开了颜色通道实例就是 16 个 float，
## 给 `multimesh.buffer` 赋 12 步长的数组会被 Godot 直接拒收
##（"different size from the Multimesh's existing buffer"），
## 表现为子弹一发都不显示 + 每帧一条错误日志。
const INSTANCE_STRIDE := 16

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
## 投射物 id → 元素枚举（供 `_color_of` 上色）。
##
## 核里也存了（`get_elem`），但那要每帧逐条发跨语言调用；
## 元素一经生成就不变，故本地留一份。**在本表里按存活剪枝**，
## 见 `_color_of`。
var _bullet_elem: Dictionary = {}
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
	# **必须在 instance_count 之前开**：Godot 不允许在已有实例时切换
	# custom_data / colors 开关（报 "Instance count must be 0 to toggle"）。
	#
	# 这里用 `use_colors` 而不是 `use_custom_data`，理由是**卡不卡取决于
	# 开几个通道，而不是开哪一个**：开任意一个都会让实例步长变成 16，
	# 与群体单位侧的缓冲布局一致，共用同一支 `unit_billboard.gdshader`。
	# 顺带这个选择让核不用改——`get_render_buffer` 保持原样，颜色由
	# GDScript 每帧按元素填（见 `_color_of`）。
	mm.use_colors = true
	mm.instance_count = CAPACITY
	# billboard 平面：顶点是**单位**尺寸，实际大小由核写进缓冲的缩放决定
	#（核里是 `base_scale`，引信期会放大 1.4 倍）。
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mmi.multimesh = mm
	mmi.material_override = _build_bullet_material()
	_multimesh = mm
	add_child(mmi)


## 造弹丸材质。
##
## **不用贴图**：图集里没有弹丸类小图（tiny-dungeon 的角色行只有单位），
## 为子弹单独烤一张 1 格贴图不值得。用纯色 + 元素配色——
## 配色直接复用 `Projectile.element_color()`，那是全项目既有的唯一真相源
##（近战/旧投射物路径都用它），这里另起一套会立刻产生不一致。
func _build_bullet_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://rendering/shaders/unit_billboard.gdshader")
	mat.set_shader_parameter("use_instance_color", true)
	mat.set_shader_parameter("contact_shadow", 0.0)
	return mat


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


## 把核的渲染缓冲搬进 MultiMesh，并补上颜色。
##
## **不能直接赋值**：核按每实例 12 个 float 产出（3×4 变换），而本 MultiMesh
## 开了 `use_colors` ⇒ 每条实例 16 个 float。长度对不上，Godot 会报
## "Cannot set a buffer on a Multimesh that is a different size" 并**整个丢弃**
## 这次赋值——表现为子弹一发都不显示，且每帧刷一条错误日志。
##
## 所以这里做一次 12→16 的重排：逐条把 12 个变换 float 拷到前面，
## 颜色写在末尾 4 个。2048 发弹幕下这是一次 32768 float 的拷贝，可忽略。
func _sync_render() -> void:
	if _multimesh == null:
		return
	var src: PackedFloat32Array = sim.call("get_render_buffer")
	var dst := PackedFloat32Array()
	dst.resize(CAPACITY * INSTANCE_STRIDE)
	for i in CAPACITY:
		var s := i * RENDER_STRIDE
		var d := i * INSTANCE_STRIDE
		for k in RENDER_STRIDE:
			dst[d + k] = src[s + k]
		var c := _color_of(i)
		dst[d + 12] = c.r
		dst[d + 13] = c.g
		dst[d + 14] = c.b
		dst[d + 15] = 1.0
	_multimesh.buffer = dst


## 取某条实例的弹丸颜色。
##
## 元素取自 `_bullet_elem`（`spawn_from_data` 时记下）而不是回头调核的
## `get_elem(id)`：元素一经生成就不再变，每帧为每条存活子弹发一次跨语言
## 调用纯属浪费。代价是本表要自己维护——所以这里顺手用 `is_alive` 剪掉
## 已死的 id，否则这张表会随游戏时长无限涨（这是它唯一的泄漏口）。
##
## 配色复用 `Projectile.element_color()`——全项目既有的唯一真相源
##（近战/旧投射物路径都用它），这里另起一套会立刻产生不一致。
## 查不到元素的实例（如核内部生成的子母弹）留白，白色在深色场景里最显眼。
func _color_of(id: int) -> Color:
	if not _bullet_elem.has(id):
		return Color.WHITE
	if not bool(sim.call("is_alive", id)):
		_bullet_elem.erase(id)
		return Color.WHITE
	return Projectile.element_color(ElementDamage.key_from_elem(int(_bullet_elem[id])))


## 消费事件：命中 / 爆炸 / 到期
##
## 走**扁平数组**接口（每事件 11 float）而不是逐事件 Dictionary：
## 4096 发弹幕下字典编组实测 15 ms/帧（约 90% 帧预算），
## 扁平数组只要 0.02 ms。布局见 EVENT_STRIDE 常量。
func _drain_events() -> void:
	var ev: PackedFloat32Array = sim.call("drain_events_packed")
	var n := ev.size() / EVENT_STRIDE
	if n == 0:
		return
	for k in n:
		var b := k * EVENT_STRIDE
		match int(ev[b + 0]):
			EV_HIT:
				_deal_hit(ev, b)
			EV_EXPLODE:
				_deal_explode(ev, b)
			EV_EXPIRE:
				_deal_expire(ev, b)
	active = int(sim.call("get_active_count"))


## 单目标命中：走既有伤害链路（与旧 Projectile._deal_damage 同口径）
func _deal_hit(ev: PackedFloat32Array, b: int) -> void:
	var ref := int(ev[b + 5])
	var target := _resolve(ref)
	var pos := Vector3(ev[b + 2], ev[b + 3], ev[b + 4])
	var dmg := ev[b + 6]
	var elem := int(ev[b + 7])
	# 群体单位不是场景节点（_resolve 对它们返回 null），伤害另走批量接口。
	# 这条分支必须存在：`_sync_targets` 把群体单位喂进了核，若这里直接
	# return，子弹会**命中并消失但零伤害**——玩家看到弹幕穿群而过却没反应。
	if _is_crowd_ref(ref):
		_apply_damage_to_crowd(ref, dmg, elem, pos)
		return
	if target == null:
		return
	_apply_damage_to(target, dmg, elem, pos)
	# 命中后原地留区域（策划「命中/有效期结束后原地生成区域」）
	if ev[b + 10] != 0.0:
		_spawn_zone(pos, int(ev[b + 1]))


## 引信爆炸：半径内**全组**结算（与旧 Projectile._explode 同口径）
func _deal_explode(ev: PackedFloat32Array, b: int) -> void:
	var pos := Vector3(ev[b + 2], ev[b + 3], ev[b + 4])
	var radius := ev[b + 8]
	var dmg := ev[b + 9]
	var elem := int(ev[b + 7])
	if radius > 0.0:
		for t in _all_targets():
			if t is Node3D and is_instance_valid(t):
				if (t as Node3D).global_position.distance_to(pos) <= radius:
					_apply_damage_to(t, dmg, elem, pos)
		_explode_crowd(pos, radius, dmg, elem)
	# 震屏（旧实现也发这个）
	EventBus.screen_shake.emit(0.2, 0.15)
	if ev[b + 10] != 0.0:
		_spawn_zone(pos, int(ev[b + 1]))


## 爆炸波及群体单位（近战 AOE 早就打群体单位，投射物爆炸此前漏了）。
##
## `_all_targets()` 只收场景节点，群体单位不在里面——不加这段的话，
## 一发炸在怪堆里的炸弹只会伤到节点式精英/Boss。
## 半径查询走 `CrowdManager.query_circle`（核内空间哈希），不逐单位算距离。
func _explode_crowd(pos: Vector3, radius: float, dmg: float, elem: int) -> void:
	var crowd = _crowd_manager()
	if crowd == null:
		return
	var ids: PackedInt32Array = crowd.call("query_circle", pos.x, pos.z, radius)
	if ids.is_empty():
		return
	# 逐发结算：`apply_damage` 只吃一个统一数值，但每只怪的防御不同。
	# 防御按各自的 monster 配置取——与近战打群体单位同口径
	#（旧节点路径的爆炸本来就没扣防御，那是它自己的简化，不照搬）。
	for raw in ids:
		var id := int(raw)
		if not bool(crowd.call("is_alive", id)):
			continue
		var def_v := float((crowd.call("monster_of", id) as Dictionary).get("defense", 0.0))
		var result := DamagePipeline.elemental_attack(dmg, 1.0, 0.0, def_v, elem)
		var amount := float(result.damage)
		crowd.call("apply_damage", PackedInt32Array([id]), amount)
		var at: Vector3 = crowd.call("unit_position", id)
		EventBus.damage_popup.emit(at, amount, "normal")
		projectile_hit.emit(at, amount, "normal")
		if elem >= 0:
			var tb = crowd.call("buffs_of", id)
			if tb != null:
				var out: Dictionary = ElementDamage.attack(tb, elem)
				for e in out.get("events", []):
					var ctrl_id: String = ElementDamage.control_for_event(str(e))
					if ctrl_id != "":
						tb.apply(ctrl_id, "element")


## 到期消散：可能要在原地留区域
func _deal_expire(ev: PackedFloat32Array, b: int) -> void:
	if ev[b + 10] != 0.0:
		_spawn_zone(Vector3(ev[b + 2], ev[b + 3], ev[b + 4]), int(ev[b + 1]))


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


## ref 是否指向一个群体单位
func _is_crowd_ref(ref: int) -> bool:
	return ref >= 0 and ref < _refs.size() \
		and str((_refs[ref] as Dictionary).get("kind", "")) == "crowd"


## 对群体单位结算投射物伤害。
##
## 群体单位不是场景节点，拿不到 `take_damage`，走 `CrowdManager.apply_damage`
## 批量接口——与玩家近战打群体单位**同一套口径**（`player._apply_hit_crowd`）：
## 用怪物表里的 defense 过 DamagePipeline，然后按 id 扣血。
##
## 元素叠层走 `CrowdManager.buffs_of(id)` 拿到的 BuffHolder
##（群体单位本身没有 buff 槽，管理器按需给它们挂宿主 Node）。
func _apply_damage_to_crowd(ref: int, dmg: float, elem: int, popup_pos: Vector3) -> void:
	var crowd = _crowd_manager()
	if crowd == null:
		return
	var id := int((_refs[ref] as Dictionary).get("id", -1))
	if id < 0 or not bool(crowd.call("is_alive", id)):
		return
	var target_def := float((crowd.call("monster_of", id) as Dictionary).get("defense", 0.0))
	var result := DamagePipeline.elemental_attack(dmg, 1.0, 0.0, target_def, elem)
	crowd.call("apply_damage", PackedInt32Array([id]), float(result.damage))
	EventBus.damage_popup.emit(popup_pos, result.damage, "normal")
	projectile_hit.emit(popup_pos, result.damage, "normal")

	# 元素叠层：与节点路径同口径。群体单位的 buff 宿主按需创建，
	# 拿不到宿主（后端不支持）时静默跳过，不影响伤害本身。
	if elem >= 0:
		var tb = crowd.call("buffs_of", id)
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
			# 群体单位不是场景节点，这里没有对象可返回。
			# **不代表它们不吃伤害**——`_deal_hit` 会在调本函数前先分流到
			# `_apply_damage_to_crowd`（走 CrowdManager 批量接口）。
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
		# 记下这发子弹的元素（上色用）与落地区域规格（事件回来时用）
		_bullet_elem[id] = elem_enum
		if not zone.is_empty():
			_zone_specs[id] = zone.duplicate()
	return id


func backend_name() -> String:
	return ProjectileSimLoader.backend_name()
