class_name ProjectileSimFallback
extends Node
## ProjectileSim 的纯 GDScript 降级实现 —— 与 C++ 扩展**同名 API**
##
## **为什么需要**：C++ 扩展要编译产物（`bin/libcrowd_sim.*.dll`），
## CI / 新克隆的机器上不存在。没有 fallback 的话，投射物逻辑在那些环境
## 测不了，门禁只能整片 SKIP——"测不到"等于没有防线。
##
## 与 `CrowdSimFallback` 同一思路：不追求与 C++ 数值一致（数组布局、
## 缓存友好性在脚本层没意义），只保证**语义一致**：
## 同样的输入 → 同样的可观测行为（推进/命中/穿透/弹射/引信/分裂）。
##
## 容量刻意压到 256——这是降级路径，脚本层逐帧遍历 256 发已接近上限。

const FALLBACK_CAP := 256
const MAX_HIT_MEMORY := 8
## 子弹碰撞球半径（与 C++ 侧 BULLET_RADIUS 一致）
const BULLET_RADIUS := 0.3
## 目标高度（与 C++ 侧 TARGET_HEIGHT 一致）
const TARGET_HEIGHT := 2.0

var _capacity := 0
var _active := 0
var _free: Array[int] = []

# —— SoA 池（与 C++ 同构，便于对照）——
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _dx := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _lifetime := PackedFloat32Array()
var _elapsed := PackedFloat32Array()
var _elem := PackedInt32Array()
var _pierce := PackedInt32Array()
var _bounces := PackedInt32Array()
var _hit_count := PackedInt32Array()
var _faction := PackedInt32Array()
var _alive := PackedByteArray()
var _fuse_armed := PackedByteArray()

# 弧线
var _arc := PackedByteArray()
var _arc_sx := PackedFloat32Array()
var _arc_sz := PackedFloat32Array()
var _arc_lx := PackedFloat32Array()
var _arc_lz := PackedFloat32Array()
var _arc_h := PackedFloat32Array()

# 引信
var _fuse_time := PackedFloat32Array()
var _fuse_timer := PackedFloat32Array()
var _explode_radius := PackedFloat32Array()
var _explode_damage := PackedFloat32Array()

# 分裂 / 落地区域
var _split_count := PackedInt32Array()
var _split_pct := PackedFloat32Array()
var _split_spread := PackedFloat32Array()
var _has_zone := PackedInt32Array()

## 去重：子弹 id → 已命中 ref 列表
var _hit_memory := {}

var _targets: Array = []   # [{x, z, radius, ref, faction}]
var _events: Array = []


func setup(capacity: int) -> void:
	_capacity = clampi(capacity, 1, FALLBACK_CAP)
	var n := _capacity
	_px.resize(n); _py.resize(n); _pz.resize(n)
	_dx.resize(n); _dz.resize(n)
	_speed.resize(n); _damage.resize(n)
	_lifetime.resize(n); _elapsed.resize(n)
	_elem.resize(n); _pierce.resize(n); _bounces.resize(n)
	_hit_count.resize(n); _faction.resize(n)
	_alive.resize(n); _fuse_armed.resize(n)
	_arc.resize(n)
	_arc_sx.resize(n); _arc_sz.resize(n); _arc_lx.resize(n); _arc_lz.resize(n); _arc_h.resize(n)
	_fuse_time.resize(n); _fuse_timer.resize(n)
	_explode_radius.resize(n); _explode_damage.resize(n)
	_split_count.resize(n); _split_pct.resize(n); _split_spread.resize(n)
	_has_zone.resize(n)
	for i in n:
		_alive[i] = 0
		_fuse_armed[i] = 0
		_arc[i] = 0
		_elem[i] = -1
	_free.clear()
	for i in range(n - 1, -1, -1):
		_free.append(i)
	_active = 0
	_hit_memory.clear()
	_targets.clear()
	_events.clear()


func clear() -> void:
	setup(_capacity)


func spawn(desc: Dictionary) -> int:
	if _free.is_empty():
		return -1
	var id: int = _free.pop_back()
	var dx := float(desc.get("dx", 0.0))
	var dz := float(desc.get("dz", 1.0))
	var len := sqrt(dx * dx + dz * dz)
	if len > 1e-6:
		dx /= len
		dz /= len
	else:
		dx = 0.0
		dz = 1.0
	_px[id] = float(desc.get("x", 0.0))
	_py[id] = float(desc.get("y", 0.0))
	_pz[id] = float(desc.get("z", 0.0))
	_dx[id] = dx
	_dz[id] = dz
	_speed[id] = float(desc.get("speed", 10.0))
	_damage[id] = float(desc.get("damage", 10.0))
	_lifetime[id] = maxf(float(desc.get("lifetime", 2.0)), 0.01)
	_elapsed[id] = 0.0
	_elem[id] = int(desc.get("elem", -1))
	_pierce[id] = int(desc.get("pierce", 0))
	_bounces[id] = int(desc.get("bounces", 0))
	_hit_count[id] = 0
	_faction[id] = int(desc.get("faction", 0))
	_alive[id] = 1
	_fuse_armed[id] = 0
	_arc[id] = 1 if bool(desc.get("arc", false)) else 0
	_arc_sx[id] = _px[id]
	_arc_sz[id] = _pz[id]
	var travel := _speed[id] * maxf(_lifetime[id], 1.0)
	_arc_lx[id] = _px[id] + dx * travel
	_arc_lz[id] = _pz[id] + dz * travel
	_arc_h[id] = float(desc.get("arc_height", 3.0))
	_fuse_time[id] = float(desc.get("fuse", 0.0))
	_fuse_timer[id] = 0.0
	_explode_radius[id] = float(desc.get("explode_radius", 0.0))
	var ed := float(desc.get("explode_damage", 0.0))
	_explode_damage[id] = ed if ed > 0.0 else _damage[id]
	_split_count[id] = int(desc.get("split_count", 0))
	_split_pct[id] = float(desc.get("split_pct", 0.4))
	_split_spread[id] = float(desc.get("split_spread", 0.5))
	_has_zone[id] = int(desc.get("has_zone", 0))
	_hit_memory[id] = []
	_active += 1
	return id


func despawn(id: int) -> void:
	if not is_alive(id):
		return
	_alive[id] = 0
	_free.append(id)
	_active -= 1


func is_alive(id: int) -> bool:
	return id >= 0 and id < _capacity and _alive[id] != 0


func set_targets(targets: PackedFloat32Array, factions: PackedInt32Array) -> void:
	_targets.clear()
	var n := targets.size() / 4
	for i in n:
		_targets.append({
			"x": targets[i * 4 + 0],
			"z": targets[i * 4 + 1],
			"radius": targets[i * 4 + 2],
			"ref": int(targets[i * 4 + 3]),
			"faction": int(factions[i]) if i < factions.size() else 0,
		})


func clear_targets() -> void:
	_targets.clear()


func step(dt: float) -> void:
	if _active == 0:
		return
	_phase_advance(dt)
	_phase_hit_test()
	_phase_lifetime()


func _phase_advance(dt: float) -> void:
	for i in _capacity:
		if _alive[i] == 0:
			continue
		if _fuse_armed[i] != 0:
			_fuse_timer[i] -= dt
			continue
		_elapsed[i] += dt
		if _arc[i] != 0:
			var t := clampf(_elapsed[i] / maxf(_lifetime[i], 0.01), 0.0, 1.0)
			_px[i] = _arc_sx[i] + (_arc_lx[i] - _arc_sx[i]) * t
			_pz[i] = _arc_sz[i] + (_arc_lz[i] - _arc_sz[i]) * t
			_py[i] = 4.0 * _arc_h[i] * t * (1.0 - t)
		else:
			_px[i] += _dx[i] * _speed[i] * dt
			_pz[i] += _dz[i] * _speed[i] * dt


func _phase_hit_test() -> void:
	if _targets.is_empty():
		return
	for i in _capacity:
		if _alive[i] == 0 or _fuse_armed[i] != 0:
			continue
		for t in _targets.size():
			var tg: Dictionary = _targets[t]
			if int(tg["faction"]) != _faction[i]:
				continue
			var ref := int(tg["ref"])
			if _already_hit(i, ref):
				continue
			# 命中模型：球（子弹）vs 竖直圆柱（目标）——与 C++ 侧同口径。
			# 横向：圆心距 ≤ 目标半径 + 子弹半径；纵向：在目标高度范围内。
			# 不能把子弹当质点、目标当球——那样贴地弹的 y 分量会吃掉横向容差。
			var ddx: float = _px[i] - float(tg["x"])
			var ddz: float = _pz[i] - float(tg["z"])
			var r: float = float(tg["radius"]) + BULLET_RADIUS
			if ddx * ddx + ddz * ddz > r * r:
				continue
			if _py[i] < -BULLET_RADIUS or _py[i] > TARGET_HEIGHT + BULLET_RADIUS:
				continue
			_remember_hit(i, ref)
			_hit_count[i] += 1
			_events.append({
				"type": "hit", "id": i,
				"pos": Vector3(_px[i], _py[i], _pz[i]),
				"target_id": ref, "damage": _damage[i], "elem": _elem[i],
				"explode_radius": 0.0, "explode_damage": 0.0,
				"has_zone": _has_zone[i] != 0,
			})
			if _bounces[i] > 0:
				_bounces[i] -= 1
				_do_bounce(i)
				break
			if _hit_count[i] <= _pierce[i]:
				break
			if _fuse_time[i] > 0.0:
				_explode(i)
			else:
				# 命中后消失**不补发 expire**（命中事件已报告这次交互）。
				# has_zone 已挂在命中事件上。与 C++ 侧同口径。
				despawn(i)
			break


func _phase_lifetime() -> void:
	for i in _capacity:
		if _alive[i] == 0:
			continue
		if _fuse_armed[i] != 0 and _fuse_timer[i] <= 0.0:
			_explode(i)
			continue
		if _elapsed[i] >= _lifetime[i]:
			if _fuse_time[i] > 0.0:
				# 守卫必须判"未武装"——本阶段每帧都跑到这里，进入引信后
				# elapsed 不再增长、条件恒成立，不判就会每帧重置计时器
				#（实测引信永不爆炸）。与 C++ 侧同口径。
				if _fuse_armed[i] == 0:
					_fuse_armed[i] = 1
					_fuse_timer[i] = _fuse_time[i]
			else:
				_emit_expire(i)
				despawn(i)


func _do_bounce(id: int) -> void:
	var best := -1
	var best_d := INF
	for t in _targets.size():
		var tg: Dictionary = _targets[t]
		if int(tg["faction"]) != _faction[id]:
			continue
		if _already_hit(id, int(tg["ref"])):
			continue
		var ddx: float = float(tg["x"]) - _px[id]
		var ddz: float = float(tg["z"]) - _pz[id]
		var d := ddx * ddx + ddz * ddz
		if d < best_d:
			best_d = d
			best = t
	if best >= 0:
		var tg2: Dictionary = _targets[best]
		var ux: float = float(tg2["x"]) - _px[id]
		var uz: float = float(tg2["z"]) - _pz[id]
		var len := sqrt(ux * ux + uz * uz)
		if len > 1e-6:
			_dx[id] = ux / len
			_dz[id] = uz / len
	else:
		_dx[id] = -_dx[id]
		_dz[id] = -_dz[id]
	_elapsed[id] = 0.0
	_lifetime[id] = maxf(_lifetime[id], 1.5)
	_arc[id] = 0


func _explode(id: int) -> void:
	_events.append({
		"type": "explode", "id": id,
		"pos": Vector3(_px[id], _py[id], _pz[id]),
		"target_id": -1, "damage": _explode_damage[id], "elem": _elem[id],
		"explode_radius": _explode_radius[id],
		"explode_damage": _explode_damage[id],
		"has_zone": _has_zone[id] != 0,
	})
	despawn(id)


func _emit_expire(id: int) -> void:
	_events.append({
		"type": "expire", "id": id,
		"pos": Vector3(_px[id], _py[id], _pz[id]),
		"target_id": -1, "damage": _damage[id], "elem": _elem[id],
		"explode_radius": 0.0, "explode_damage": 0.0,
		"has_zone": _has_zone[id] != 0,
	})


func _remember_hit(id: int, ref: int) -> void:
	var arr: Array = _hit_memory.get(id, [])
	arr.append(ref)
	_hit_memory[id] = arr


func _already_hit(id: int, ref: int) -> bool:
	var arr: Array = _hit_memory.get(id, [])
	return arr.has(ref)


func drain_events() -> Array:
	var out := _events.duplicate()
	_events.clear()
	return out


func get_render_buffer() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(_capacity * 12)
	for i in _capacity:
		var base := i * 12
		if _alive[i] == 0:
			continue
		var s := 1.0
		buf[base + 0] = s
		buf[base + 5] = s
		buf[base + 10] = s
		buf[base + 3] = _px[i]
		buf[base + 7] = _py[i]
		buf[base + 11] = _pz[i]
	return buf


func set_base_scale(_scale: float) -> void:
	pass   # 降级路径不做缩放（视觉细节，不影响行为）


func get_active_count() -> int:
	return _active


func get_capacity() -> int:
	return _capacity


func get_position(id: int) -> Vector3:
	if not is_alive(id):
		return Vector3.ZERO
	return Vector3(_px[id], _py[id], _pz[id])


func get_damage(id: int) -> float:
	return _damage[id] if is_alive(id) else 0.0


func get_elem(id: int) -> int:
	return _elem[id] if is_alive(id) else -1


func get_pierce_left(id: int) -> int:
	return _pierce[id] if is_alive(id) else 0


func get_bounces_left(id: int) -> int:
	return _bounces[id] if is_alive(id) else 0


func is_fuse_armed(id: int) -> bool:
	return is_alive(id) and _fuse_armed[id] != 0
