class_name RoomTypeAllocator
extends RefCounted
## 房间类型分配器：《关卡设计分册》3.1 每层房间清单
## 商店 3～5 格、宝箱 4～7 格、泉水 2～4 格、事件 ≥2、隐藏 ≥2、精英 20%～30%

const RoomDataScript := preload("res://scripts/dungeon/room_data.gd")


func allocate(rooms: Array, config: ChapterConfig) -> void:
	if rooms.is_empty():
		return
	# 初始房已由生成器标记为 START
	var start: RoomData = _find_start(rooms)
	if start == null:
		return
	# 1. Boss = 距起点最远
	var boss: RoomData = _farthest_from(start, rooms)
	if boss != null:
		boss.type = RoomData.RoomType.BOSS
	# 2. 可用候选（去掉起点与 Boss）
	var candidates: Array = rooms.filter(func(r): return r != start and r != boss)
	# 3. 按距离约束分配特殊房
	_assign_near(start, candidates, RoomData.RoomType.SHOP, 3, 5, 1)
	_assign_near(start, candidates, RoomData.RoomType.CHEST, 4, 7, 1)
	_assign_near(start, candidates, RoomData.RoomType.HEAL, 2, 4, 1)
	_assign_near(start, candidates, RoomData.RoomType.EVENT, 2, 8, 2)
	_assign_near(start, candidates, RoomData.RoomType.HIDDEN, 1, 99, 2)
	# 4. 精英房 = 剩余战斗房的 20%～30%
	var normal_rooms: Array = candidates.filter(func(r): return r.type == RoomData.RoomType.NORMAL)
	var elite_count := ceili(normal_rooms.size() * config.elite_rate)
	normal_rooms.shuffle()
	for i in mini(elite_count, normal_rooms.size()):
		normal_rooms[i].type = RoomData.RoomType.ELITE
	# 5. 其余保持 NORMAL


func _find_start(rooms: Array) -> RoomData:
	for r in rooms:
		if r.type == RoomData.RoomType.START:
			return r
	return null


func _farthest_from(start: RoomData, rooms: Array) -> RoomData:
	var best: RoomData = null
	var best_dist := -1
	for r in rooms:
		if r == start:
			continue
		var d: int = (r.center_cell() - start.center_cell()).length_squared()
		if d > best_dist:
			best_dist = d
			best = r
	return best


func _assign_near(start: RoomData, candidates: Array, type: int, min_dist: int, max_dist: int, count: int) -> void:
	var pool: Array = []
	for r in candidates:
		if r.type == RoomData.RoomType.NORMAL:
			var d: int = _cell_dist(r.center_cell(), start.center_cell())
			if d >= min_dist and d <= max_dist:
				pool.append(r)
	if pool.is_empty():
		# 距离约束不可满足时兜底：任选剩余普通房，保证特殊房数量
		for r in candidates:
			if r.type == RoomData.RoomType.NORMAL:
				pool.append(r)
	pool.shuffle()
	for i in mini(count, pool.size()):
		pool[i].type = type


func _cell_dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
