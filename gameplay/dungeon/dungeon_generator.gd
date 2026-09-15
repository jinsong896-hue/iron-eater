class_name DungeonGenerator
extends RefCounted
## 地下城生成器 —— HD-2D 重构版
## 基于 BSP 或图算法生成随机地下城房间图
## 房间实例化由 RoomController 管理

var rng := RandomNumberGenerator.new()

# 生成参数
var min_rooms := 8
var max_rooms := 15
var room_size := 20.0   # 房间世界尺寸（米）
## 生成安全下限：起始房 + Boss 房 + 至少 1 间普通房。
## 低于此数时房型分配（特殊房/精英按距离门控）会因候选不足而退化。
const MIN_SAFE_ROOMS := 4
## 可用范围半边长（母网格约束）。0 = 不限制。
## 策划书 2.1：每层在 14×14 → 30×30 的范围内生成，逐层扩张。
## 给 1 层留出余量（房间坐标是曼哈顿扩展，range_half 太小时会提前填满）。
var range_half := 0
## 当前层数。第 9 层（隐藏层）结构特殊：奖励大厅 + Boss 连战 ×3 + 传送点，
## 不是常规的「1 间 Boss + 一堆怪物房」（策划书 6.10）。
var floor_num := 1

# 生成结果
var rooms: Array[Dictionary] = []       # [{id, position: Vector2i, type, ...}]
var connections: Array[Array] = []      # 房间连接关系
var start_room_index := 0
var boss_room_index := 0


## 生成地下城房间图
func generate(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.set_seed(seed_value)

	rooms.clear()
	connections.clear()

	# 计算房间数量
	# 隐藏房计入总配额（策划 3.1：总房间数 = 怪物房 + 特殊房 + 隐藏房），
	# 故连通房只生成 count - 隐藏房数，余下 2 间在连通性之后追加。
	var room_count := rng.randi_range(min_rooms, max_rooms)
	# 隐藏房数受总配额约束：连通房至少要 MIN_SAFE_ROOMS 间
	# （起始房 + Boss 房 + 普通房），否则特殊房/精英分配会因候选不足退化。
	var max_hidden := maxi(room_count - MIN_SAFE_ROOMS, 0)
	var hidden_count := mini(2, max_hidden) if floor_num < FloorDefs.MAX_FLOOR else 0
	var linked_count := room_count - hidden_count

	# 生成房间节点
	_generate_rooms(linked_count)

	# 生成连接（最小生成树 + 额外回路）
	_generate_connections()

	# 隐藏房：**在连通性之后**追加，故不写入 connections、无门通向它。
	# 第 9 层（纯 Boss 连战）不加隐藏房。
	if hidden_count > 0:
		_append_hidden_rooms(hidden_count)

	# 分配房间类型
	_assign_room_types()


## 生成房间节点（简单路径扩展）
## range_half > 0 时限制坐标在 ±range_half（母网格可用范围，策划书 2.1）；
## 超出范围的方向直接放弃。实测各层房间数/范围组合都能放满（见测试）。
func _generate_rooms(count: int) -> void:
	rooms.append({
		"id": "room_start",
		"position": Vector2i.ZERO,
		"type": "start",
	})

	var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var occupied := {Vector2i.ZERO: true}

	while rooms.size() < count:
		var parent := rooms[rng.randi() % rooms.size()]
		var parent_pos: Vector2i = parent["position"]
		var dir: Vector2i = directions[rng.randi() % directions.size()]
		var new_pos: Vector2i = parent_pos + dir

		# 越界 → 换方向（不直接 continue，否则贴着边界的房间会空转）
		if not _in_range(new_pos):
			var placed_edge := false
			for d in directions:
				var q: Vector2i = parent_pos + d
				if _in_range(q) and not occupied.has(q):
					new_pos = q
					placed_edge = true
					break
			if not placed_edge:
				continue

		# 避免重叠
		elif occupied.has(new_pos):
			# 尝试随机方向
			var placed := false
			for d in directions:
				var q2: Vector2i = parent_pos + d
				if _in_range(q2) and not occupied.has(q2):
					new_pos = q2
					placed = true
					break
			if not placed:
				continue

		occupied[new_pos] = true
		rooms.append({
			"id": "room_%d" % (rooms.size() + 1),
			"position": new_pos,
			"type": "normal",
		})


## 坐标是否在可用范围内（range_half <= 0 表示不限制）
func _in_range(p: Vector2i) -> bool:
	if range_half <= 0:
		return true
	return absi(p.x) <= range_half and absi(p.y) <= range_half


## 生成连接（相邻房间自动连接）
func _generate_connections() -> void:
	for i in rooms.size():
		var pos_i: Vector2i = rooms[i]["position"]
		for j in range(i + 1, rooms.size()):
			var pos_j: Vector2i = rooms[j]["position"]
			var diff := pos_i - pos_j
			if abs(diff.x) + abs(diff.y) == 1:
				connections.append([i, j])


## 分配房间类型（Boss 用图距离；特殊房按策划距离门控）
func _assign_room_types() -> void:
	# 第 9 层（隐藏层）：固定结构——奖励大厅 + Boss 连战 ×3 + 传送点。
	# 策划书 6.10 明写「无探索负担，纯 Boss 挑战 + 奖励狂欢」，
	# 故不走常规的特殊房/精英分配。
	if floor_num >= FloorDefs.MAX_FLOOR:
		_assign_layer9_rooms()
		return

	# Boss 房：图距离最远的房间
	# （原实现用曼哈顿距离 abs(x)+abs(y) 代理，绕墙 5 步可能输给直线 4 步）
	var dist_from_start := _bfs_distances(start_room_index)
	var max_dist := -1
	for i in rooms.size():
		var d: int = int(dist_from_start.get(i, 0))
		if d > max_dist:
			max_dist = d
			boss_room_index = i
	rooms[boss_room_index]["type"] = "boss"

	# 顺序要紧：先放特殊房（它们从普通房里挑），再定精英
	# 否则精英先占了普通房，特殊房可选项变少
	_assign_special_rooms(dist_from_start)

	# 精英房：占**怪物房** 20~30%（策划 3.1）
	# 分母是剩余的普通房，不是总房间数——特殊房不算怪物房
	var normal_count := 0
	for r in rooms:
		if r["type"] == "normal":
			normal_count += 1
	var elite_count := maxi(int(round(float(normal_count) * 0.25)), 1)
	elite_count = mini(elite_count, normal_count)
	var guard := 0
	var assigned := 0
	while assigned < elite_count and guard < rooms.size() * 10:
		guard += 1
		var idx := rng.randi() % rooms.size()
		if rooms[idx]["type"] == "normal":
			rooms[idx]["type"] = "elite"
			assigned += 1


## 第 9 层专用房型分配（策划书 6.10：固定三连战）。
## 结构：起始房（传送进入点）+ 3 间 Boss 房（混沌守卫 → 虚空双子 → 破坏神完全体）
##       + 1 间奖励大厅（满地图宝箱）。
## 按 BFS 距离排序：越远的越靠后（Boss 战顺序由玩家推进自然形成）。
func _assign_layer9_rooms() -> void:
	var dist := _bfs_distances(start_room_index)
	# 按距离升序排列候选房（排除起始房）
	var order: Array = []
	for i in rooms.size():
		if i != start_room_index:
			order.append(i)
	order.sort_custom(func(a, b): return int(dist.get(a, 0)) < int(dist.get(b, 0)))

	# 依次标：3 间 Boss 房（连战顺序即距离顺序），最后一间作奖励大厅
	var boss_seq := 0
	for k in order.size():
		var idx: int = order[k]
		if boss_seq < 3:
			rooms[idx]["type"] = "boss"
			boss_room_index = idx          # 最后一间 Boss 房（连战终点）
			boss_seq += 1
		else:
			rooms[idx]["type"] = "treasure"   # 奖励大厅（宝箱房）

	# 兜底：房间不足 4 间时至少保证 1 间 Boss 房
	if boss_seq == 0 and rooms.size() > 1:
		rooms[1]["type"] = "boss"
		boss_room_index = 1


## 分配特殊房（商店/宝箱/泉水），按策划的距离规则而非纯随机
## 商店距初始 3~5、宝箱距初始 4~7、泉水距 Boss 2~4（关卡分册 3.1）
##
## ⚠ 放置顺序按「约束最强优先」：策划的距离区间是为 14×14 大地图设计的，
## 而本层固定 13 房（BFS 直径仅 3~6）。宝箱的 4~7 在直径 4 的图上几乎无处可放，
## 若让商店（3~5）先挑就会把仅有的远房占走。故宝箱先放，其次泉水、商店、事件。
func _assign_special_rooms(dist_from_start: Dictionary) -> void:
	var dist_from_boss := _bfs_distances(boss_room_index)
	# 最受限的先挑
	_place_by_distance("treasure", dist_from_start, 4, 7)
	_place_by_distance("heal", dist_from_boss, 2, 4)
	_place_by_distance("shop", dist_from_start, 3, 5)
	# 事件房：策划要求每层至少 2 间
	_place_by_distance("event", dist_from_start, 2, 99)
	_place_by_distance("event", dist_from_start, 2, 99)


## 追加隐藏房（策划 3.1：每层稳定 2 间，**不计入总房间数配额**）。
##
## 在 `_generate_connections()` **之后**调用——它不写入 connections，
## 因此没有邻居、没有门指向它（门由坐标差算出，见 DoorsByTopology）。
## 这就是「隐藏」的实现：不需要额外标记，靠图论上的孤立天然成立。
##
## 位置：贴着某个已连通房间。破墙入口挂在那个邻房间的共用墙上
## （见 GameRoot 的隐藏房入口生成）。
func _append_hidden_rooms(count: int) -> void:
	var guard := 0
	var added := 0
	while added < count and guard < count * 60:
		guard += 1
		# 随机挑一个已有房间，在它四邻中找一个空位
		var anchor_idx := rng.randi() % rooms.size()
		var anchor: Vector2i = rooms[anchor_idx].get("position", Vector2i.ZERO)
		var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		var d: Vector2i = dirs[rng.randi() % dirs.size()]
		var pos: Vector2i = anchor + d
		if not _in_range(pos):
			continue
		# 位置必须空着
		var occupied := false
		for r in rooms:
			if r.get("position", Vector2i.ZERO) == pos:
				occupied = true
				break
		if occupied:
			continue
		rooms.append({
			"id": "room_hidden_%d" % (added + 1),
			"position": pos,
			"type": "hidden",
			"anchor_index": anchor_idx,   # 破墙入口挂在这个房间
			"anchor_dir": _dir_name_from(d),  # 从锚点看隐藏房的方位
		})
		added += 1


## 方向向量 → 方位名
func _dir_name_from(d: Vector2i) -> String:
	if d == Vector2i.UP:
		return "north"
	if d == Vector2i.DOWN:
		return "south"
	if d == Vector2i.LEFT:
		return "west"
	return "east"


## 在满足距离区间的普通房里挑一间改为指定类型
## 无候选时放宽为"距目标区间最近的普通房"，保证 13 房小图上也能配上
func _place_by_distance(room_type: String, dist: Dictionary, lo: int, hi: int) -> bool:
	var best := -1
	var best_penalty := 0x7FFFFFFF
	for idx in rooms.size():
		if rooms[idx]["type"] != "normal":
			continue
		var d: int = int(dist.get(idx, 0))
		var penalty := 0
		if d < lo:
			penalty = lo - d
		elif d > hi:
			penalty = d - hi
		if penalty < best_penalty:
			best_penalty = penalty
			best = idx
		if penalty == 0:
			break  # 落在区间内，直接采用
	if best < 0:
		return false
	rooms[best]["type"] = room_type
	return true


## 从起点做 BFS，返回 {房间索引: 步数}
func _bfs_distances(from_index: int) -> Dictionary:
	var dist := {}
	if from_index < 0 or from_index >= rooms.size():
		return dist
	dist[from_index] = 0
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb in get_adjacent_rooms(cur):
			if not dist.has(nb):
				dist[nb] = int(dist[cur]) + 1
				queue.append(nb)
	return dist


## 获取房间世界坐标
func get_room_world_position(room_index: int) -> Vector3:
	var pos: Vector2i = rooms[room_index]["position"]
	return Vector3(float(pos.x) * room_size, 0.0, float(pos.y) * room_size)


## 获取相邻房间
func get_adjacent_rooms(room_index: int) -> Array:
	var result: Array = []
	for conn in connections:
		if conn[0] == room_index:
			result.append(conn[1])
		elif conn[1] == room_index:
			result.append(conn[0])
	return result


## 获取两个房间之间的方向
func get_direction(from_index: int, to_index: int) -> String:
	var from_pos: Vector2i = rooms[from_index]["position"]
	var to_pos: Vector2i = rooms[to_index]["position"]
	var diff := to_pos - from_pos
	if diff.x > 0:
		return "east"
	elif diff.x < 0:
		return "west"
	elif diff.y > 0:
		return "south"
	elif diff.y < 0:
		return "north"
	return ""