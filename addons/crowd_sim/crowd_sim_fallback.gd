class_name CrowdSimFallback
extends Node
## CrowdSim 的纯 GDScript 降级实现 —— 与 C++ 扩展**同名 API**
##
## **为什么需要它**：C++ 扩展要编译产物（`bin/libcrowd_sim.*.dll`），
## 在 CI / 新克隆的机器上不存在。没有 fallback 的话，任何依赖 CrowdSim 的
## 逻辑（房间生成、命中判定、掉落）都无法在那些环境跑测试，
## 门禁只能整片 SKIP——而"测不到"等于"没有防线"。
##
## 有了它：逻辑正确性走 fallback 验（慢但对），性能类断言打印 SKIP。
##
## **容量刻意压到 200**：这是降级路径，GDScript 逐帧遍历 200 个实体已经
## 接近脚本层能承受的上限；再大就该用真扩展了。上限也提醒调用方
## "你现在跑在慢路径上"。
##
## 实现上**不追求与 C++ 完全一致的数值**（六步哈希、并行前缀和在这里
## 没有意义），只保证**语义一致**：同样的输入 → 同样的可观测行为
##（位置推进、不穿墙、斥力分离、查询命中、伤害与事件）。

## 降级路径的容量上限
const FALLBACK_CAP := 200

## 空间哈希格边长（与 C++ 侧默认一致）
const CELL_SIZE := 2.0

var _capacity := 0
var _active := 0

# —— SoA 池（与 C++ 同构，便于对照）——
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _stagger := PackedFloat32Array()
var _alive := PackedByteArray()
var _target := PackedInt32Array()
var _free: Array[int] = []

var _obstacles: Array[Rect2] = []   # x/z 平面上的 AABB（用 Rect2 的 position/size）
var _events: Array[Dictionary] = []

## 空间哈希：格子 → 实例 id 列表
var _grid := {}


func setup(capacity: int, _cell_size: float = CELL_SIZE) -> void:
	_capacity = clampi(capacity, 1, FALLBACK_CAP)
	_px.resize(_capacity)
	_pz.resize(_capacity)
	_vx.resize(_capacity)
	_vz.resize(_capacity)
	_hp.resize(_capacity)
	_speed.resize(_capacity)
	_radius.resize(_capacity)
	_scale.resize(_capacity)
	_stagger.resize(_capacity)
	_alive.resize(_capacity)
	_target.resize(_capacity)
	for i in _capacity:
		_alive[i] = 0
		_scale[i] = 0.0
		_target[i] = -1
	_free.clear()
	# 逆序压栈 → id 从小到大分配（与 C++ 侧一致，便于对照调试）
	for i in range(_capacity - 1, -1, -1):
		_free.append(i)
	_active = 0
	_obstacles.clear()
	_events.clear()
	_grid.clear()


## 障碍：PackedFloat32Array 每 4 个一组 = min_x, min_z, max_x, max_z
func set_obstacles(aabbs: PackedFloat32Array) -> void:
	_obstacles.clear()
	var n := aabbs.size() / 4
	for i in n:
		var min_x := aabbs[i * 4 + 0]
		var min_z := aabbs[i * 4 + 1]
		var max_x := aabbs[i * 4 + 2]
		var max_z := aabbs[i * 4 + 3]
		_obstacles.append(Rect2(min_x, min_z, max_x - min_x, max_z - min_z))


func spawn(x: float, z: float, hp: float, speed: float, radius: float, scale: float) -> int:
	if _free.is_empty():
		return -1
	var id: int = _free.pop_back()
	_px[id] = x
	_pz[id] = z
	_vx[id] = 0.0
	_vz[id] = 0.0
	_hp[id] = hp
	_speed[id] = speed
	_radius[id] = radius
	_scale[id] = scale
	_stagger[id] = 0.0
	_alive[id] = 1
	_target[id] = -1
	_active += 1
	return id


func despawn(id: int) -> void:
	if id < 0 or id >= _capacity or _alive[id] == 0:
		return
	_alive[id] = 0
	_scale[id] = 0.0
	_free.append(id)
	_active -= 1


func is_alive(id: int) -> bool:
	return id >= 0 and id < _capacity and _alive[id] != 0


func get_capacity() -> int:
	return _capacity


func get_active_count() -> int:
	return _active


func get_position(id: int) -> Vector3:
	if not is_alive(id):
		return Vector3.ZERO
	return Vector3(_px[id], 0.0, _pz[id])


func get_hp(id: int) -> float:
	if not is_alive(id):
		return 0.0
	return _hp[id]


func set_stagger(id: int, seconds: float) -> void:
	if is_alive(id):
		_stagger[id] = maxf(seconds, 0.0)


func set_elite(_id: int, _elite: bool) -> void:
	pass   # 降级路径不做精英标识（视觉/掉落由 GDScript 侧自己管）


func set_target(id: int, target_id: int) -> void:
	if is_alive(id):
		_target[id] = target_id


## 一帧模拟。语义与 C++ 侧一致：seek + 斥力 + 障碍推出 + 积分。
func step(dt: float, player_x: float, player_z: float) -> void:
	if _active == 0:
		return
	_rebuild_grid()

	# 阶段 1：转向（seek 插值，不含斥力）
	for i in _capacity:
		if _alive[i] == 0:
			continue
		if _stagger[i] > 0.0:
			_stagger[i] = maxf(_stagger[i] - dt, 0.0)
			continue
		var tx := player_x
		var tz := player_z
		var tid := _target[i]
		if tid >= 0 and tid < _capacity and _alive[tid] != 0:
			tx = _px[tid]
			tz = _pz[tid]
		var dx := tx - _px[i]
		var dz := tz - _pz[i]
		var dist := sqrt(dx * dx + dz * dz)
		var des_vx := 0.0
		var des_vz := 0.0
		if dist > 0.35:
			des_vx = dx / dist * _speed[i]
			des_vz = dz / dist * _speed[i]
		var t := clampf(6.0 * dt, 0.0, 1.0)
		var nvx: float = _vx[i] + (des_vx - _vx[i]) * t
		var nvz: float = _vz[i] + (des_vz - _vz[i]) * t
		var sp: float = _speed[i]
		var v2 := nvx * nvx + nvz * nvz
		if v2 > sp * sp and v2 > 1e-8:
			var inv := sp / sqrt(v2)
			nvx *= inv
			nvz *= inv
		_vx[i] = nvx
		_vz[i] = nvz

	# 阶段 2：斥力（直接改位置）+ 阶段 3：障碍 + 阶段 4：积分
	for i in _capacity:
		if _alive[i] == 0:
			continue
		var push_x := 0.0
		var push_z := 0.0
		for j in _neighbors(i):
			var ddx: float = _px[i] - _px[j]
			var ddz: float = _pz[i] - _pz[j]
			var d2 := ddx * ddx + ddz * ddz
			var r_sum: float = _radius[i] + _radius[j]
			if d2 < 1e-8:
				push_x += 0.05
				continue
			var d := sqrt(d2)
			if d < r_sum:
				var overlap := (r_sum - d) * 0.5
				push_x += ddx / d * overlap
				push_z += ddz / d * overlap
			elif d < 1.6:
				var f := 6.0 * (1.0 - d / 1.6) / 1.6
				push_x += ddx / d * f * dt
				push_z += ddz / d * f * dt
		# 位移限幅（与 C++ 侧同口径）
		var p2 := push_x * push_x + push_z * push_z
		var max_push: float = _speed[i] * dt * 2.0
		if p2 > max_push * max_push and p2 > 1e-8:
			var inv := max_push / sqrt(p2)
			push_x *= inv
			push_z *= inv
		var nx: float = _px[i] + push_x + _vx[i] * dt
		var nz: float = _pz[i] + push_z + _vz[i] * dt
		# 障碍推出
		var r: float = _radius[i]
		for box in _obstacles:
			var cx := clampf(nx, box.position.x, box.end.x)
			var cz := clampf(nz, box.position.y, box.end.y)
			var ddx2 := nx - cx
			var ddz2 := nz - cz
			var dd2 := ddx2 * ddx2 + ddz2 * ddz2
			if dd2 >= r * r:
				continue
			if dd2 > 1e-8:
				var dd := sqrt(dd2)
				nx += ddx2 / dd * (r - dd + 0.001)
				nz += ddz2 / dd * (r - dd + 0.001)
			else:
				# 陷在盒内：退回最小穿透轴
				var dl := nx - box.position.x
				var dr := box.end.x - nx
				var dtp := nz - box.position.y
				var db := box.end.y - nz
				var m: float = minf(minf(dl, dr), minf(dtp, db))
				if m == dl:
					nx = box.position.x - r - 0.001
				elif m == dr:
					nx = box.end.x + r + 0.001
				elif m == dtp:
					nz = box.position.y - r - 0.001
				else:
					nz = box.end.y + r + 0.001
		_px[i] = nx
		_pz[i] = nz


## 重建空间哈希（降级路径用 Dictionary，不追求 C++ 的六步流水线）
func _rebuild_grid() -> void:
	_grid.clear()
	for i in _capacity:
		if _alive[i] == 0:
			continue
		var key := _cell_key(_px[i], _pz[i])
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


func _cell_key(x: float, z: float) -> int:
	var cx := int(floor(x / CELL_SIZE))
	var cz := int(floor(z / CELL_SIZE))
	# 打包成单个 int 作 key（偏移避免负数冲突）
	return (cx + 4096) * 8192 + (cz + 4096)


## 邻居：3x3 邻格内的实例 id（不含自己）
func _neighbors(i: int) -> Array:
	var out: Array = []
	var cx := int(floor(_px[i] / CELL_SIZE))
	var cz := int(floor(_pz[i] / CELL_SIZE))
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var key := (cx + ox + 4096) * 8192 + (cz + oz + 4096)
			if _grid.has(key):
				for j in _grid[key]:
					if j != i:
						out.append(j)
	return out


func query_circle(cx: float, cz: float, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _active == 0:
		_rebuild_grid()
	var r2 := radius * radius
	for i in _capacity:
		if _alive[i] == 0:
			continue
		var dx: float = _px[i] - cx
		var dz: float = _pz[i] - cz
		if dx * dx + dz * dz <= r2:
			out.append(i)
	return out


func query_cone(ox: float, oz: float, dir_x: float, dir_z: float,
		half_angle: float, range_: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _active == 0:
		_rebuild_grid()
	var len := sqrt(dir_x * dir_x + dir_z * dir_z)
	if len < 1e-6:
		return out
	var ux := dir_x / len
	var uz := dir_z / len
	var cos_half := cos(half_angle)
	var r2 := range_ * range_
	for i in _capacity:
		if _alive[i] == 0:
			continue
		var dx: float = _px[i] - ox
		var dz: float = _pz[i] - oz
		var d2 := dx * dx + dz * dz
		if d2 > r2 or d2 < 1e-8:
			continue
		var d := sqrt(d2)
		if (dx * ux + dz * uz) / d >= cos_half:
			out.append(i)
	return out


func apply_damage(ids: PackedInt32Array, amount: float) -> int:
	var kills := 0
	for id in ids:
		if not is_alive(id):
			continue
		_hp[id] -= amount
		if _hp[id] <= 0.0:
			_hp[id] = 0.0
			_events.append({
				"type": "death", "id": id,
				"pos": Vector3(_px[id], 0.0, _pz[id]),
				"is_elite": false,
			})
			despawn(id)
			kills += 1
	return kills


func drain_events() -> Array:
	var out := _events.duplicate()
	_events.clear()
	return out


## 渲染缓冲：12 float/实例的 MultiMesh 变换（与 C++ 侧同格式）
func get_render_buffer() -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(_capacity * 12)
	for i in _capacity:
		var base := i * 12
		if _alive[i] == 0:
			# 未存活：缩放写 0 → MultiMesh 不渲染
			for k in 12:
				buf[base + k] = 0.0
			continue
		var s: float = _scale[i]
		buf[base + 0] = s
		buf[base + 5] = s
		buf[base + 10] = s
		buf[base + 3] = _px[i]
		buf[base + 7] = 0.0
		buf[base + 11] = _pz[i]
	return buf
