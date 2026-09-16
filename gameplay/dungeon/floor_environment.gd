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

## 2 层「废弃矿道」：部分地面坍塌 → 减速区（策划：特殊机制是减速）
func _setup_collapse(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 4, 2.0)
	for pos in zones:
		DamageZone.spawn({
			"position": pos, "radius": 2.0, "duration": -1.0,
			"damage": 0.0, "tick_interval": 0.5,
			"slow_buff": "thorn_slow",
			"color": Color(0.35, 0.30, 0.22, 0.45),
		}, self)
	_mech = {"kind": "collapse", "zone_count": zones.size()}


## 3 层「古老墓穴」：毒气区域，持续掉血（策划：可破坏通风口消除——通风口机制待做）
func _setup_poison(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 5, 2.2)
	for pos in zones:
		DamageZone.spawn({
			"position": pos, "radius": 2.2, "duration": -1.0,
			"damage": 6.0, "tick_interval": 1.0,
			"color": Color(0.30, 0.75, 0.25, 0.35),
		}, self)
	_mech = {"kind": "poison", "zone_count": zones.size()}


## 4 层「地下沼泽」：泥潭陷阱（减速 + 持续伤害）
func _setup_mire(w: float, h: float) -> void:
	var zones := _scatter_zones(w, h, 5, 2.5)
	for pos in zones:
		DamageZone.spawn({
			"position": pos, "radius": 2.5, "duration": -1.0,
			"damage": 8.0, "tick_interval": 1.0,
			"slow_buff": "mire",
			"color": Color(0.25, 0.22, 0.14, 0.5),
		}, self)
	_mech = {"kind": "mire", "zone_count": zones.size()}


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
