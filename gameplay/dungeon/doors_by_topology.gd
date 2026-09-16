class_name DoorsByTopology
extends RefCounted
## 按地牢拓扑计算房间的门 —— 替代房间模板里写死的门
##
## 背景：房间模板的门是固定方位（普通房南北各一扇），而地牢拓扑随机，
## 于是「门通向哪里」全凭运气。朝向没有邻接房间的门即**哑门**：
## 玩家走上去 DoorTrigger 发出 door_opened 信号，GameRoot 按方向找不到
## 邻接房间（_find_room_in_direction 返回 -1），静默不切房 —— 看起来像卡住。
##
## 本类把 DungeonGenerator.connections（真实邻接关系）折算成每间房应有的门方位，
## 消除哑门；同时补一扇回起点的门，消除死胡同。


## 计算指定房间应有的门方位列表
## rooms:         [{position: Vector2i, type: String, ...}, ...]
## connections:   [[i, j], ...] 无向邻接对
## start_index:   起始房索引（回退门指向它；其余房间默认回指起始房）
## back_index:    本房的父节点（从起点 BFS 得到），即回退门指向的房间
## 返回: ["north", "south", ...] 去重后的方位
##
## 不变量：返回的每个方位都必须有真实邻接房间——门永远不指向空处。
## 补回退门有风险（父房间可能不在可用方位上，补出来仍是哑门），
## 故只在「本房完全没有邻接房间」时才补，并逐个尝试候选房间。
static func directions_for(
	rooms: Array, connections: Array, room_index: int,
	start_index: int, back_index: int
) -> Array:
	var dirs: Array = []
	# 1) 真实邻接：每个邻居占一个方位
	for other in _neighbors_of(connections, room_index):
		var d := _direction_between(rooms, room_index, other)
		if d != "" and not dirs.has(d):
			dirs.append(d)

	# 2) 只在本房无路可走时补回退门（死胡同救急，不保证成功）
	if dirs.is_empty() and room_index != start_index:
		for candidate in [back_index, start_index]:
			var back := _direction_between(rooms, room_index, candidate)
			if back != "" and not dirs.has(back):
				dirs.append(back)
				break

	return dirs


## 门在房间里的格子坐标：取该边界方向的中点
static func cell_for(direction: String, width: int, height: int) -> Vector2i:
	match direction:
		"north":
			return Vector2i(width / 2, 0)
		"south":
			return Vector2i(width / 2, height - 1)
		"west":
			return Vector2i(0, height / 2)
		"east":
			return Vector2i(width - 1, height / 2)
	return Vector2i(width / 2, height / 2)


## 为房间数据生成 doors 数组（覆盖模板里原有的门）
##
## **隐藏房只生成一扇「通往锚房间」的出口门**。
## 背景：隐藏房刻意不在 connections 里（否则门会暴露它），但一开始
## 完全不给门 → 玩家破墙进去后**出不来**（实测踩到）。
## 那扇门不会暴露隐藏房：隐藏是「从锚房进不来」而不是「里面没有门」——
## 锚房间的门由 directions_for 按 connections 算，不含这扇。
## 出得去靠 `_find_room_in_direction`：它按**格子坐标**找邻房，与
## connections 无关，故从隐藏房走这扇门能找到相邻的锚房间。
static func build_doors(
	rooms: Array, connections: Array, room_index: int,
	start_index: int, back_index: int, width: int, height: int
) -> Array:
	if room_index >= 0 and room_index < rooms.size():
		if str(rooms[room_index].get("type", "")) == "hidden":
			# 出口方位 = 从隐藏房看锚房间的方向（与锚房记录的反向）
			var out_dir := _hidden_exit_dir(rooms, room_index)
			if out_dir.is_empty():
				return []
			var hcell := cell_for(out_dir, width, height)
			return [{
				"direction": out_dir,
				"id": "exit_%s_%d_%d" % [out_dir, hcell.x, hcell.y],
				"x": hcell.x,
				"y": hcell.y,
			}]
	var doors: Array = []
	for d in directions_for(rooms, connections, room_index, start_index, back_index):
		var cell := cell_for(d, width, height)
		doors.append({
			"direction": d,
			"id": "%s_%d_%d" % [d, cell.x, cell.y],
			"x": cell.x,
			"y": cell.y,
		})
	return doors


## 隐藏房的出口方位：从隐藏房指向其锚房间。
## 锚房间在生成隐藏房时记下了 anchor_dir（从锚房看隐藏房的方位），
## 这里取反向。
static func _hidden_exit_dir(rooms: Array, hidden_index: int) -> String:
	if hidden_index < 0 or hidden_index >= rooms.size():
		return ""
	var r: Dictionary = rooms[hidden_index]
	var adir := str(r.get("anchor_dir", ""))
	match adir:
		"north": return "south"
		"south": return "north"
		"west":  return "east"
		"east":  return "west"
	return ""


## 从起点做 BFS，返回每个房间的父节点（用于回退门）
## 返回 Array[int]，-1 表示不可达
static func bfs_parents(rooms: Array, connections: Array, start_index: int) -> Array:
	var parents: Array = []
	parents.resize(rooms.size())
	parents.fill(-1)
	if start_index < 0 or start_index >= rooms.size():
		return parents

	var visited := {start_index: true}
	var queue: Array = [start_index]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for other in _neighbors_of(connections, cur):
			if visited.has(other):
				continue
			visited[other] = true
			parents[other] = cur
			queue.append(other)
	return parents


## 取某房间的所有邻接房间索引
static func _neighbors_of(connections: Array, room_index: int) -> Array:
	var result: Array = []
	for conn in connections:
		if conn.size() < 2:
			continue
		if int(conn[0]) == room_index:
			result.append(int(conn[1]))
		elif int(conn[1]) == room_index:
			result.append(int(conn[0]))
	return result


## 两间房之间的方位（按格子坐标差）
static func _direction_between(rooms: Array, from_index: int, to_index: int) -> String:
	if from_index < 0 or to_index < 0:
		return ""
	if from_index >= rooms.size() or to_index >= rooms.size():
		return ""
	var from_pos: Vector2i = rooms[from_index].get("position", Vector2i.ZERO)
	var to_pos: Vector2i = rooms[to_index].get("position", Vector2i.ZERO)
	var diff := to_pos - from_pos
	if diff.x > 0:
		return "east"
	if diff.x < 0:
		return "west"
	if diff.y > 0:
		return "south"
	if diff.y < 0:
		return "north"
	return ""
