extends SceneTree
## 地牢生成器逻辑测试：房间数量、中心初始房、Boss 最远、特殊房、连通性、边界

const GenScript := preload("res://scripts/dungeon/dungeon_generator.gd")
const RoomDataScript := preload("res://scripts/dungeon/room_data.gd")
const Layer01 := preload("res://data/dungeon/layers/layer01.tres")
const Layer05 := preload("res://data/dungeon/layers/layer05.tres")
const Layer09 := preload("res://data/dungeon/layers/layer09.tres")

var failed := 0


func _init() -> void:
	await _test_layer(Layer01, 12, 16)
	await _test_layer(Layer05, 16, 20)
	await _test_layer(Layer09, 5, 5)
	if failed == 0:
		print("ALL DUNGEON TESTS PASSED")
		quit(0)
	else:
		print("DUNGEON TESTS FAILED: %d" % failed)
		quit(1)


func _test_layer(cfg: ChapterConfig, min_rooms: int, max_rooms: int) -> void:
	var gen = GenScript.new()
	root.add_child(gen)
	await process_frame
	gen.generate(cfg, 20260812, false, false)
	var rooms: Array = gen.rooms
	var count := rooms.size()
	print("  [DBG] %s 走廊格数 %d，房间门洞总数 %d" % [
		cfg.chapter_name, gen.corridor_cells.size(), _total_doors(gen)])
	_check(count >= min_rooms - 1 and count <= max_rooms, "%s 房间数 %d ∈ [%d,%d]" % [cfg.chapter_name, count, min_rooms, max_rooms])

	# 初始房存在且在中心附近
	var start: RoomData = null
	for r in rooms:
		if r.type == RoomData.RoomType.START:
			start = r
	_check(start != null, "%s 初始房存在" % cfg.chapter_name)

	# 房间不重叠 + 在母网格内
	var overlap := false
	var out_of_bounds := false
	var half := cfg.map_size / 2
	for i in rooms.size():
		var r: RoomData = rooms[i]
		if r.rect.position.x < -half or r.rect.position.y < -half \
				or r.rect.end.x > half or r.rect.end.y > half:
			out_of_bounds = true
		for j in range(i + 1, rooms.size()):
			if rooms[i].rect.intersects(rooms[j].rect):
				overlap = true
	_check(not overlap, "%s 房间无重叠" % cfg.chapter_name)
	_check(not out_of_bounds, "%s 房间在母网格内" % cfg.chapter_name)

	# Boss 最远
	if cfg.layer_id != 9 and start != null:
		var boss: RoomData = null
		for r in rooms:
			if r.type == RoomData.RoomType.BOSS:
				boss = r
		var boss_ok := boss != null
		if boss_ok:
			var boss_d := boss.center_cell().length_squared()
			for r in rooms:
				if r.center_cell().length_squared() > boss_d:
					boss_ok = false
					break
		_check(boss_ok, "%s Boss 存在且最远" % cfg.chapter_name)

	# 特殊房
	if cfg.layer_id != 9:
		var shop := 0
		var chest := 0
		var heal := 0
		var events := 0
		var hidden := 0
		for r in rooms:
			match r.type:
				RoomData.RoomType.SHOP: shop += 1
				RoomData.RoomType.CHEST: chest += 1
				RoomData.RoomType.HEAL: heal += 1
				RoomData.RoomType.EVENT: events += 1
				RoomData.RoomType.HIDDEN: hidden += 1
		_check(shop >= 1 and chest >= 1 and heal >= 1, "%s 商店/宝箱/泉水各 ≥1" % cfg.chapter_name)
		_check(events >= 2 and hidden >= 2, "%s 事件/隐藏各 ≥2" % cfg.chapter_name)

	# 连通性：二部图 BFS（房间 ↔ 走廊格，相邻房间直连）
	var reachable := _count_reachable(gen, start)
	_check(reachable == count, "%s 全部连通（%d/%d）" % [cfg.chapter_name, reachable, count])
	if reachable != count and start != null:
		var edges := _debug_edge_count(gen)
		print("  [DBG] %s 邻接边数 %d，起点门洞 %d" % [cfg.chapter_name, edges, start.door_cells.size()])
		_debug_start_component(gen, start)

	gen.queue_free()
	await process_frame


func _count_reachable(gen, start: RoomData) -> int:
	if start == null:
		return 0
	var adjacency := {}
	for room in gen.rooms:
		adjacency[room] = []
	for cell in gen.corridor_cells:
		if not adjacency.has(cell):
			adjacency[cell] = []
		for room in gen.rooms:
			if not room.rect.has_point(cell) and room.rect.grow(1).has_point(cell):
				if not adjacency[cell].has(room):
					adjacency[cell].append(room)
				if not adjacency[room].has(cell):
					adjacency[room].append(cell)
	# 相邻走廊格互相连通（4 方向）
	var cells: Array = gen.corridor_cells.keys()
	for cell in cells:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb_cell: Vector2i = cell + offset
			if gen.corridor_cells.has(nb_cell):
				if not adjacency[cell].has(nb_cell):
					adjacency[cell].append(nb_cell)
				if not adjacency[nb_cell].has(cell):
					adjacency[nb_cell].append(cell)
	var rooms: Array = gen.rooms
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if _rects_touch(rooms[i].rect, rooms[j].rect):
				if not adjacency[rooms[i]].has(rooms[j]):
					adjacency[rooms[i]].append(rooms[j])
					adjacency[rooms[j]].append(rooms[i])
	var seen := {}
	var queue: Array = [start]
	seen[start] = true
	while not queue.is_empty():
		var cur = queue.pop_front()
		for nb in adjacency[cur]:
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	var reachable_rooms := 0
	for room in gen.rooms:
		if seen.has(room):
			reachable_rooms += 1
	return reachable_rooms


func _total_doors(gen) -> int:
	var total := 0
	for room in gen.rooms:
		total += room.door_cells.size()
	return total


func _rects_touch(a: Rect2i, b: Rect2i) -> bool:
	return a.grow(1).intersects(b) and not a.intersects(b)


func _debug_edge_count(gen) -> int:
	var count := 0
	for cell in gen.corridor_cells:
		for room in gen.rooms:
			if not room.rect.has_point(cell) and room.rect.grow(1).has_point(cell):
				count += 1
	return count


func _debug_start_component(gen, start: RoomData) -> void:
	var adjacency := {}
	for room in gen.rooms:
		adjacency[room] = []
	for cell in gen.corridor_cells:
		if not adjacency.has(cell):
			adjacency[cell] = []
		for room in gen.rooms:
			if not room.rect.has_point(cell) and room.rect.grow(1).has_point(cell):
				if not adjacency[cell].has(room):
					adjacency[cell].append(room)
				if not adjacency[room].has(cell):
					adjacency[room].append(cell)
	var cells: Array = gen.corridor_cells.keys()
	for cell in cells:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb_cell: Vector2i = cell + offset
			if gen.corridor_cells.has(nb_cell):
				if not adjacency[cell].has(nb_cell):
					adjacency[cell].append(nb_cell)
				if not adjacency[nb_cell].has(cell):
					adjacency[nb_cell].append(cell)
	var stack: Array = [start]
	var seen := {start: true}
	var hops := 0
	while not stack.is_empty() and hops < 60:
		var cur = stack.pop_back()
		hops += 1
		for nb in adjacency.get(cur, []):
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	print("  [DBG]   起点组件节点数 %d（含走廊格）" % seen.size())
	for dc in start.door_cells:
		var rooms_touched: Array = []
		for room in gen.rooms:
			if not room.rect.has_point(dc) and room.rect.grow(1).has_point(dc):
				rooms_touched.append(str(room.rect.position) + "/" + room.type_name())
		print("  [DBG]   起点门洞 %s → 触达房间 %s" % [str(dc), "、".join(PackedStringArray(rooms_touched))])


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
