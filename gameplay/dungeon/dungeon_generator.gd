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
	var room_count := rng.randi_range(min_rooms, max_rooms)

	# 生成房间节点
	_generate_rooms(room_count)

	# 生成连接（最小生成树 + 额外回路）
	_generate_connections()

	# 分配房间类型
	_assign_room_types()


## 生成房间节点（简单路径扩展）
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

		# 避免重叠
		if occupied.has(new_pos):
			# 尝试随机方向
			var placed := false
			for d in directions:
				new_pos = parent_pos + d
				if not occupied.has(new_pos):
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


## 生成连接（相邻房间自动连接）
func _generate_connections() -> void:
	for i in rooms.size():
		var pos_i: Vector2i = rooms[i]["position"]
		for j in range(i + 1, rooms.size()):
			var pos_j: Vector2i = rooms[j]["position"]
			var diff := pos_i - pos_j
			if abs(diff.x) + abs(diff.y) == 1:
				connections.append([i, j])


## 分配房间类型
func _assign_room_types() -> void:
	# Boss 房：最远节点
	var max_dist := 0
	for i in rooms.size():
		var pos: Vector2i = rooms[i]["position"]
		var dist: float = abs(pos.x) + abs(pos.y)
		if dist > max_dist:
			max_dist = dist
			boss_room_index = i

	rooms[boss_room_index]["type"] = "boss"

	# 中间随机分配精英房
	var elite_count := maxi(rooms.size() / 5, 1)
	var assigned := 0
	while assigned < elite_count:
		var idx := rng.randi() % rooms.size()
		if rooms[idx]["type"] == "normal":
			rooms[idx]["type"] = "elite"
			assigned += 1

	# 特殊房：商店 / 泉水 / 事件各一间（越多房间配得越全）
	_assign_special_rooms()


## 分配特殊房（商店 / 泉水 / 事件），数量随房间总数缩放且不超过可用普通房
func _assign_special_rooms() -> void:
	var quota := clampi(rooms.size() / 4, 1, 3)
	var pool := ["shop", "heal", "event"]
	for i in quota:
		var candidates: Array[int] = []
		for idx in rooms.size():
			if rooms[idx]["type"] == "normal":
				candidates.append(idx)
		if candidates.is_empty():
			return
		var pick: int = candidates[rng.randi() % candidates.size()]
		rooms[pick]["type"] = pool[i]


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