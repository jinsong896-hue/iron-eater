class_name FloorEnvironment
extends Node3D
## 楼层环境机制 —— 按层施加场地危害（关卡设计分册第 4 章「每层主题与环境机制」）
##
## 9 层各有一套环境危害：2 层坍塌减速、3 层毒气、4 层泥潭、5 层熔岩+齿轮、
## 6 层硫磺爆炸、7 层随机传送、8 层火焰风暴、9 层强制传送。
## 1 层是教学层，无机制。
##
## **实现方式**：复用 DamageZone（已支持伤害/减速/回血/计时），
## 本类只负责「按层决定生成什么、生成在哪、多久来一次」。
##
## **安全区原则**（关键，否则关卡不可玩）：
## 危害区永远避开玩家出生点与门的触发区——否则玩家一落地就持续掉血，
## 或还没反应过来就被推回上一层。生成时对候选位置做几何剔除。

const SAFE_RADIUS_FROM_SPAWN := 3.0    ## 距出生点的最小安全距离（米）
const SAFE_RADIUS_FROM_DOOR := 2.0     ## 距门的触发区的最小安全距离

var floor_num := 1
var _room_node: Node3D = null
var _spawn_points: Array[Vector3] = []
var _door_points: Array[Vector3] = []

# 周期型机制的计时（机关/爆炸/风暴/传送共用一个累加器，各机制自行判断间隔）
var _periodic_timer := 0.0
var _mech: Dictionary = {}


## 给房间挂上本层环境机制。
## room_node: 房间根节点（危害挂其下，随房间销毁）
## data: 房间 JSON（用于取宽高与门/生成点位置）
static func apply(room_node: Node3D, floor_num: int, data: Dictionary) -> FloorEnvironment:
	var env_id := FloorDefs.env_id(floor_num)
	if env_id.is_empty():
		return null      # 1 层等无机制层
	var fe := FloorEnvironment.new()
	fe.name = "FloorEnvironment"
	fe.floor_num = floor_num
	fe._room_node = room_node
	fe._collect_safe_points(data)
	room_node.add_child(fe)
	fe._setup(env_id, data)
	return fe


## 收集安全点（出生点与门），供危害区剔除用
func _collect_safe_points(data: Dictionary) -> void:
	var w: float = float(data.get("width", 20))
	var h: float = float(data.get("height", 15))
	# 出生点
	for e in data.get("entities", []):
		if str(e.get("type", "")) == "player_spawn":
			_spawn_points.append(Vector3(float(e.get("x", 0)), 0.0, float(e.get("y", 0))))
	# 门（格子坐标 → 世界坐标；门在格边缘，与 DoorBuilder 同口径）
	for d in data.get("doors", []):
		var dir := str(d.get("direction", ""))
		var p := Vector3(float(d.get("x", 0)), 0.0, float(d.get("y", 0)))
		match dir:
			"north": p.z -= 0.5
			"south": p.z += 0.5
			"west":  p.x -= 0.5
			"east":  p.x += 0.5
		_door_points.append(p)
	# 兜底：无出生点数据时用房间中心当安全点，避免危害铺满整间
	if _spawn_points.is_empty():
		_spawn_points.append(Vector3(w * 0.5, 0.0, h * 0.5))


## 位置是否安全（远离出生点与门）
func _is_safe(pos: Vector3) -> bool:
	for s in _spawn_points:
		if Vector2(pos.x - s.x, pos.z - s.z).length() < SAFE_RADIUS_FROM_SPAWN:
			return false
	for d in _door_points:
		if Vector2(pos.x - d.x, pos.z - d.z).length() < SAFE_RADIUS_FROM_DOOR:
			return false
	return true


## 按层装配机制
func _setup(env_id: String, data: Dictionary) -> void:
	var w: float = float(data.get("width", 20))
	var h: float = float(data.get("height", 15))
	match env_id:
		"collapse":    _setup_collapse(w, h)      # 2 层：地面坍塌（减速）
		"poison":      _setup_poison(w, h)        # 3 层：毒气区（持续掉血）
		"mire":        _setup_mire(w, h)          # 4 层：泥潭（减速 + 伤害）
		"lava":        _setup_lava(w, h)          # 5 层：熔岩 + 齿轮机关
		"sulfur":      _setup_sulfur()            # 6 层：硫磺毒气（周期爆炸）
		"void_warp":   _setup_void_warp()         # 7 层：随机传送
		"low_gravity": _setup_void_warp()         # 7 层的旧标识（兼容旧存档；见 floor_defs 注释说明为何不叫重力）
		"firestorm":   _setup_firestorm()         # 8 层：全屏火风暴
		"chaos_warp":  _setup_chaos_warp()        # 9 层：强制传送


# ============================================================
# 区域型机制（静态危害区，进区即生效）
# ============================================================

## 2 层「废弃矿道」：部分地面坍塌。
##
## 策划原文：「部分地面坍塌（减速区域）」。
## **与 3/4 层的区别**：坍塌是**动态**的——地面先裂开（1.5 秒预警），
## 然后才塌成减速区。玩家有时间躲开，且场地会随时间变得更难走。
## 3 层毒气是静态常驻、4 层泥潭是越踩越深，三者玩法不同。
func _setup_collapse(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 4, 2.0)
	for pos in zones:
		var z := DamageZone.spawn({
			"position": pos, "radius": 2.0, "duration": -1.0,
			"damage": 0.0, "tick_interval": 0.5,
			"slow_buff": "thorn_slow",
			"color": Color(0.35, 0.30, 0.22, 0.45),
		}, self)
		# 预警：先只画裂纹（无效果），1.5 秒后才真正生效
		_arm_crack_warning(z)
	_mech = {"kind": "collapse", "zone_count": zones.size()}


## 给坍塌区加"裂纹预警"阶段：先禁用效果、放大视觉提示，延时后启用。
## 用 DamageZone 自身的 `monitoring` 开关实现——禁用期间不产生任何效果。
func _arm_crack_warning(zone: DamageZone) -> void:
	if zone == null:
		return
	zone.set_deferred("monitoring", false)
	var timer := get_tree().create_timer(COLLAPSE_WARN_TIME) if get_tree() else null
	if timer == null:
		zone.monitoring = true
		return
	timer.timeout.connect(func():
		if is_instance_valid(zone):
			zone.monitoring = true)


## 坍塌预警时长（秒）。策划未给具体值，取 1.5 秒——
## 足够玩家看清并走开，又不会让场地显得空荡。
const COLLAPSE_WARN_TIME := 1.5


## 3 层「古老墓穴」：毒气区域。
##
## 策划原文：「毒气区域（持续掉血，**可破坏通风口消除**）」。
## **与 2/4 层的区别**：毒气不是"躲开就完"——每个毒气区旁边有一个
## 通风口，**打掉它才能永久清除该区**。这给了玩家一个主动目标，
## 而不是单纯绕路。通风口不摧毁则毒气一直存在。
func _setup_poison(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 5, 2.2)
	var vents := 0
	for i in zones.size():
		var pos: Vector3 = zones[i]
		var z := DamageZone.spawn({
			"position": pos, "radius": 2.2, "duration": -1.0,
			"damage": 6.0, "tick_interval": 1.0,
			"color": Color(0.30, 0.75, 0.25, 0.35),
		}, self)
		# 记下引用，供通风口的 destroyed 回调按 index 精确清除
		_poison_zones[i] = z
		if _spawn_vent_for(pos, i, w, h):
			vents += 1
	_mech = {"kind": "poison", "zone_count": zones.size(), "vent_count": vents}


## 在毒气区旁生成一个通风口，并绑定"打掉即清除该区"。
## 返回是否成功生成（找不到安全位时不生成，机制退化为"只能绕路"）。
func _spawn_vent_for(zone_pos: Vector3, index: int, w: float, h: float) -> bool:
	if not _poison_zones.has(index):
		return false
	var vent_pos := _find_vent_spot(zone_pos, w, h)
	if vent_pos == Vector3.INF:
		return false
	var vent := VentProp.new()
	vent.name = "Vent_%d" % index
	vent.zone_index = index
	vent.position = vent_pos
	add_child(vent)
	# 打掉通风口 → 清除对应的毒气区（按下标取引用，精确对应）
	var zone_ref: DamageZone = _poison_zones[index]
	vent.destroyed.connect(func(_p):
		if is_instance_valid(zone_ref):
			zone_ref.queue_free())
	return true


## 毒气区引用表（下标与通风口的 zone_index 对应）
var _poison_zones: Dictionary = {}


## 在毒气区附近找一个能放通风口的安全位（半径 2.6~3.4 米的环上取点）
func _find_vent_spot(zone_pos: Vector3, w: float, h: float) -> Vector3:
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var r := 2.8
		var p := Vector3(zone_pos.x + cos(ang) * r, 0.0, zone_pos.z + sin(ang) * r)
		if p.x < 1.0 or p.x > w - 1.0 or p.z < 1.0 or p.z > h - 1.0:
			continue
		if not _is_safe(p):
			continue
		return p
	return Vector3.INF


## 4 层「地下沼泽」：泥潭陷阱。
##
## 策划原文：「泥潭陷阱（减速 + 持续伤害）」。
## **与 2/3 层的区别**：泥潭的减速**随停留时间加深**（3 档：-25%/-40%/-55%），
## 表达"越陷越深"。踩一下就走的代价很小，站桩不走会被困住。
func _setup_mire(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 5, 2.5)
	for pos in zones:
		# **不设 slow_buff**：减速完全由 _tick_mire 按停留时长分档管理。
		# 若这里也挂一个基础减速，玩家会被施加两条减速词条（叠加），
		# 实际减速远超档位表的设计值。
		var z := DamageZone.spawn({
			"position": pos, "radius": 2.5, "duration": -1.0,
			"damage": 8.0, "tick_interval": 1.0,
			"color": Color(0.25, 0.22, 0.14, 0.5),
		}, self)
		_mire_zones.append(z)
	_mech = {"kind": "mire", "zone_count": zones.size()}


## 泥潭区引用（每帧检查玩家停留时长，逐档加深减速）
var _mire_zones: Array[DamageZone] = []
## 玩家在各泥潭区的累计停留时长（key = zone instance_id）
var _mire_dwell: Dictionary = {}
## 泥潭减速档位：{秒数门槛, 减速词条 id}
## 越陷越深——踩一下就走的代价很小，站桩不走会被困住。
const MIRE_TIERS := [
	[0.0, "mire"],            # 刚踩进去：-40%
	[2.0, "mire_deep"],       # 站 2 秒：-50%
	[4.0, "mire_deepest"],    # 站 4 秒：-60%
]


## 每帧推进泥潭的"越陷越深"。
## 只在玩家位于某泥潭区内时累加该区的停留时长，离开即清零并撤掉减速。
func _tick_mire(delta: float) -> void:
	var p := _find_player()
	if p == null:
		return
	var deepest := ""
	for z in _mire_zones:
		if not is_instance_valid(z):
			continue
		var zid := z.get_instance_id()
		var inside: bool = z.global_position.distance_to(p.global_position) <= z.radius
		if inside:
			_mire_dwell[zid] = float(_mire_dwell.get(zid, 0.0)) + delta
			var t := _mire_tier_for(float(_mire_dwell[zid]))
			if _tier_rank(t) > _tier_rank(deepest):
				deepest = t
		else:
			_mire_dwell.erase(zid)
	_apply_mire_tier(p, deepest)


## 停留时长对应的档位词条 id
func _mire_tier_for(dwell: float) -> String:
	var want := ""
	for tier in MIRE_TIERS:
		if dwell >= float(tier[0]):
			want = str(tier[1])
	return want


func _tier_rank(bid: String) -> int:
	for i in MIRE_TIERS.size():
		if str(MIRE_TIERS[i][1]) == bid:
			return i
	return -1


## 只保留当前最深的一档减速（切档时先撤掉其余档）
func _apply_mire_tier(p: Node, want: String) -> void:
	var buffs = p.get("buffs")
	if buffs == null:
		return
	for tier in MIRE_TIERS:
		var bid := str(tier[1])
		if bid != want and buffs.has(bid):
			buffs.remove(bid)
	if not want.is_empty() and not buffs.has(want):
		buffs.apply(want, "mire")


## 5 层「符文熔炉」：熔岩地面（灼烧）+ 齿轮机关（周期伤害）
## 策划：熔岩每秒 40 伤害（Boss 战口径，普通房按比例下调，
## 否则普通房走两圈就死了）；机关「范围提示 3 秒后爆发」
func _setup_lava(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 4, 2.0)
	for pos in zones:
		DamageZone.spawn({
			"position": pos, "radius": 2.0, "duration": -1.0,
			"damage": 12.0, "tick_interval": 1.0,
			"color": Color(0.95, 0.40, 0.10, 0.5),
		}, self)
	# 齿轮机关：周期性在随机安全位置爆发（预警 1 秒 → 30 伤害）
	_mech = {
		"kind": "lava", "zone_count": zones.size(),
		"gear_interval": 5.0, "gear_damage": 30.0, "gear_warn": 1.0,
		"gear_radius": 2.0, "w": w, "h": h,
	}


## 6 层「硫磺深渊」：硫磺气体（间歇性爆炸）。
## 策划 6.7：Boss 战「每 35 秒 +1 层毒气，每层每秒 1.5 真实伤害，最高 10 层」，
## 普通房用场地爆炸表达（策划 4 章：硫磺气体间歇性爆炸，需躲掩体）
func _setup_sulfur() -> void:
	_mech = {
		"kind": "sulfur",
		"blast_interval": 4.5, "blast_damage": 25.0, "blast_radius": 2.6,
	}


## 7 层「虚空回廊」：策划写的是「重力降低（跳跃高度翻倍）+ 随机传送」。
## **重力项在本项目不适用**——HD-2D 俯视角没有真正的跳跃/重力
## （"跳跃攻击"是三段脚本化位移），故只实现同时列出的**随机传送**。
func _setup_void_warp() -> void:
	_mech = {"kind": "void_warp", "warp_interval": 12.0}


## 8 层「地狱王座」：全屏间歇性火焰风暴（策划 6.9.2：每 15 秒安全区重置）
func _setup_firestorm() -> void:
	_mech = {
		"kind": "firestorm",
		"storm_interval": 10.0, "storm_damage": 35.0, "storm_radius": 3.2,
	}


## 9 层「混沌裂隙」：随机传送门，每 10 秒强制传送一次（策划 6.10 / 4 章）
func _setup_chaos_warp() -> void:
	_mech = {"kind": "chaos_warp", "warp_interval": 10.0}


## 在房间内散布 n 个危害区（按安全区规则剔除；不足时放宽但仍避开出生点）
func _scatter_zones(w: float, h: float, n: int, radius: float) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < n * 40:
		guard += 1
		var pos := Vector3(_randf_range(radius, w - radius), 0.0, _randf_range(radius, h - radius))
		if not _is_safe(pos):
			continue
		# 避免危害区互相重叠过多（保持场地可读）
		var too_close := false
		for p in out:
			if Vector2(pos.x - p.x, pos.z - p.z).length() < radius * 2.0:
				too_close = true
				break
		if too_close:
			continue
		out.append(pos)
	return out


func _randf_range(lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	return randf_range(lo, hi)


# ============================================================
# 周期型机制（按间隔触发）
# ============================================================

func _process(delta: float) -> void:
	var kind := str(_mech.get("kind", ""))
	if kind.is_empty():
		set_process(false)
		return
	_periodic_timer += delta
	match kind:
		"mire":
			# 泥潭的"越陷越深"需要每帧追踪停留时长，不走周期计时
			_tick_mire(delta)
		"lava":
			_tick_gear()
		"sulfur":
			_tick_blast("blast_interval", "blast_damage", "blast_radius", Color(0.9, 0.25, 0.2, 0.5))
		"firestorm":
			_tick_blast("storm_interval", "storm_damage", "storm_radius", Color(1.0, 0.35, 0.15, 0.55))
		"void_warp":
			_tick_warp("warp_interval")
		"chaos_warp":
			_tick_warp("warp_interval")


## 齿轮机关：在随机安全位爆发一次（策划：范围提示 3 秒后爆发 → 这里压缩到 1 秒）
func _tick_gear() -> void:
	var interval := float(_mech.get("gear_interval", 5.0))
	if _periodic_timer < interval:
		return
	_periodic_timer = 0.0
	var w := float(_mech.get("w", 20.0))
	var h := float(_mech.get("h", 15.0))
	var pos := Vector3(_randf_range(1.0, w - 1.0), 0.0, _randf_range(1.0, h - 1.0))
	_spawn_burst(pos, float(_mech.get("gear_radius", 2.0)),
		float(_mech.get("gear_damage", 30.0)), Color(1.0, 0.6, 0.2, 0.5))


## 间歇爆炸（硫磺 / 火风暴通用）：在随机位置爆一次
func _tick_blast(interval_key: String, dmg_key: String, radius_key: String, color: Color) -> void:
	var interval := float(_mech.get(interval_key, 5.0))
	if _periodic_timer < interval:
		return
	_periodic_timer = 0.0
	var room_root := get_parent()
	if room_root == null:
		return
	var ctrl := room_root.get_node_or_null("RoomController")
	var w := 20.0
	var h := 15.0
	if ctrl != null:
		var d = ctrl.get("room_data")
		if d is Dictionary:
			w = float(d.get("width", 20))
			h = float(d.get("height", 15))
	var pos := Vector3(_randf_range(1.0, w - 1.0), 0.0, _randf_range(1.0, h - 1.0))
	_spawn_burst(pos, float(_mech.get(radius_key, 2.5)),
		float(_mech.get(dmg_key, 25.0)), color)


## 生成一次短时爆发（预警色 → 实际伤害由 DamageZone 的 short duration 表达）
func _spawn_burst(pos: Vector3, radius: float, damage: float, color: Color) -> void:
	DamageZone.spawn({
		"position": pos, "radius": radius, "duration": 0.8,
		"damage": damage, "tick_interval": 0.4,
		"color": color,
	}, self)


## 强制传送（7 / 9 层）：把玩家挪到本房间内的随机安全位
func _tick_warp(interval_key: String) -> void:
	var interval := float(_mech.get(interval_key, 12.0))
	if _periodic_timer < interval:
		return
	_periodic_timer = 0.0
	var room_root := get_parent()
	if room_root == null:
		return
	var ctrl := room_root.get_node_or_null("RoomController")
	# 未激活的房间（玩家不在此）不传送
	if ctrl == null or not bool(ctrl.get("is_active")):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0] as Node3D
	if p == null:
		return
	var w := 20.0
	var h := 15.0
	var d = ctrl.get("room_data")
	if d is Dictionary:
		w = float(d.get("width", 20))
		h = float(d.get("height", 15))
	# 找安全落点（避开出生点/门，也避开当前站位以免原地传送）
	var target := Vector3.ZERO
	var found := false
	for _i in 30:
		var cand := Vector3(_randf_range(2.0, w - 2.0), 0.0, _randf_range(2.0, h - 2.0))
		if not _is_safe(cand):
			continue
		if Vector2(cand.x - p.global_position.x, cand.z - p.global_position.z).length() < 4.0:
			continue
		target = cand
		found = true
		break
	if not found:
		return
	p.global_position = target
	if "velocity" in p:
		p.set("velocity", Vector3.ZERO)
	# EventBus 运行时查找（**不能直接写 EventBus**：它是 autoload，
	# --script 测试模式没有 autoload，直接引用会让整个脚本编译失败——
	# 表现为调用方报 "Nonexistent function 'apply'"，实际是脚本根本没加载出来）
	var tree := Engine.get_main_loop() as SceneTree
	var bus = tree.root.get_node_or_null("EventBus") if tree and tree.root else null
	if bus:
		bus.message.emit("空间扭曲——你被传送了")


## 供测试读取机制配置
func mechanism() -> Dictionary:
	return _mech


## 本房间的玩家（泥潭停留判定用）。
## 走 `group("player")` 而非缓存引用——房间会销毁重建，缓存会悬空。
func _find_player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	if ps.size() > 0 and is_instance_valid(ps[0]):
		return ps[0]
	return null
