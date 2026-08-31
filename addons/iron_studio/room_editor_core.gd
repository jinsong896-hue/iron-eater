class_name RoomEditorCore
extends RefCounted
## 3D 房间编辑器核心 —— 节点树 ↔ JSON 转换、格子计算、笔刷操作
## 编辑期间 3D 节点树是真实数据源，JSON 是存盘格式
## 每个节点用 set_meta("cell", {...}) 存原始格子数据，序列化时直接读

# 笔刷工具枚举
enum Tool {
	FLOOR,      # 涂地板
	RECT_FILL,  # 矩形填充地板
	WALL_EDGE,  # 墙-边缘
	WALL_CELL,  # 墙-格内
	WALL_LINE,  # 墙-拖线
	DOOR,       # 门
	SPAWN,      # 刷怪点
	ERASER,     # 橡皮擦
}

const CELL_SIZE := 1.0
const FLOOR_SCENE := "res://scenes/world/floor_tile.tscn"
const WALL_SCENE := "res://scenes/world/wall_segment.tscn"
const DOOR_SCENE := "res://scenes/props/door.tscn"


## 世界坐标 → 格子坐标（格子中心在整数坐标）
static func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x), roundi(world_pos.z))


## 格子坐标 → 世界坐标（格子中心）
static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x), 0.0, float(cell.y))


## 鼠标世界坐标在格子内的相对位置 → 最近的边缘方向
## 用于墙-边缘模式：判断点击的是格子的哪条边
static func edge_direction_at(world_pos: Vector3, cell: Vector2i) -> String:
	var center := cell_to_world(cell)
	var dx := world_pos.x - center.x  # 东正西负
	var dz := world_pos.z - center.z  # 南正北负
	# 比较到四条边的距离，取最近的
	if abs(dx) >= abs(dz):
		return "east" if dx >= 0 else "west"
	return "south" if dz >= 0 else "north"


# ============================================================
# 构建：JSON → 3D 节点树
# ============================================================

## 从 JSON 数据构建编辑器节点树（清空后重建）
static func build_editor_tree(root: Node3D, data: Dictionary) -> void:
	clear_tree(root)

	var floor_root := root.get_node_or_null("Floor")
	var wall_root := root.get_node_or_null("Walls")
	var door_root := root.get_node_or_null("Doors")
	var spawn_root := root.get_node_or_null("Spawns")

	# 地板
	for tile in data.get("floor", []):
		_add_floor(floor_root, tile)

	# 墙（用数据里的 direction，缺失则推断；type 透传）
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	for wall in data.get("walls", []):
		var direction := str(wall.get("direction", ""))
		if direction.is_empty():
			direction = _infer_wall_direction(int(wall.get("x", 0)), int(wall.get("y", 0)), w, h)
		_add_wall(wall_root, int(wall.get("x", 0)), int(wall.get("y", 0)), direction, str(wall.get("type", "normal_wall")))

	# 门
	for door in data.get("doors", []):
		var dx := int(door.get("x", 0))
		var dy := int(door.get("y", 0))
		var ddir := str(door.get("direction", "north"))
		_add_door(door_root, dx, dy, ddir)

	# 刷怪点
	for entity in data.get("entities", []):
		var type := str(entity.get("type", "enemy_spawn"))
		var monster_id := str(entity.get("monster_id", ""))
		_add_spawn(spawn_root, int(entity.get("x", 0)), int(entity.get("y", 0)), type, monster_id)


## 清空编辑器节点树的所有内容
static func clear_tree(root: Node3D) -> void:
	for child_name in ["Floor", "Walls", "Doors", "Spawns"]:
		var node := root.get_node_or_null(child_name)
		if node:
			for child in node.get_children():
				child.free()


# ============================================================
# 序列化：3D 节点树 → JSON
# ============================================================

## 遍历节点树生成 JSON Dictionary
static func serialize_tree(root: Node3D, meta: Dictionary) -> Dictionary:
	var floor_tiles: Array = []
	var walls: Array = []
	var doors: Array = []
	var entities: Array = []

	var floor_root := root.get_node_or_null("Floor")
	if floor_root:
		for child in floor_root.get_children():
			var cell: Dictionary = child.get_meta("cell", {})
			if cell.is_empty():
				continue
			floor_tiles.append({"x": cell.x, "y": cell.y, "type": cell.get("type", "stone")})

	var wall_root := root.get_node_or_null("Walls")
	if wall_root:
		for child in wall_root.get_children():
			var cell: Dictionary = child.get_meta("cell", {})
			if cell.is_empty():
				continue
			walls.append({
				"x": cell.x,
				"y": cell.y,
				"direction": cell.get("direction", "north"),
				"type": cell.get("type", "normal_wall"),
			})

	var door_root := root.get_node_or_null("Doors")
	if door_root:
		for child in door_root.get_children():
			var cell: Dictionary = child.get_meta("cell", {})
			if cell.is_empty():
				continue
			var dir := str(cell.get("direction", "north"))
			# id 加坐标后缀保证唯一（同方向多扇门不再重名）
			doors.append({
				"direction": dir,
				"id": "%s_%d_%d" % [dir, cell.x, cell.y],
				"x": cell.x,
				"y": cell.y,
			})

	var spawn_root := root.get_node_or_null("Spawns")
	if spawn_root:
		for child in spawn_root.get_children():
			var cell: Dictionary = child.get_meta("cell", {})
			if cell.is_empty():
				continue
			var entity := {
				"type": cell.get("type", "enemy_spawn"),
				"x": cell.x,
				"y": cell.y,
			}
			var monster_id := str(cell.get("monster_id", ""))
			if monster_id != "":
				entity["monster_id"] = monster_id
			entities.append(entity)

	return {
		"version": 2,
		"id": meta.get("id", "room_new"),
		"room_type": meta.get("room_type", "normal"),
		"width": meta.get("width", 20),
		"height": meta.get("height", 15),
		"cell_size": 1.0,
		"theme": meta.get("theme", "crypt"),
		"tags": meta.get("tags", [meta.get("room_type", "normal")]),
		"doors": doors,
		"floor": floor_tiles,
		"walls": walls,
		"entities": entities,
	}


# ============================================================
# 笔刷操作：增删节点
# ============================================================

## 地板笔刷：在格子放置地板（已存在则跳过）。返回操作记录 {added:[node], removed:[node]}
static func paint_floor(
	root: Node3D, cell: Vector2i, tile_type: String = "stone"
) -> Dictionary:
	var floor_root := root.get_node_or_null("Floor")
	if floor_root == null:
		return {}
	if _find_node_at_cell(floor_root, cell) != null:
		return {}  # 已有地板
	var node := _add_floor(floor_root, {"x": cell.x, "y": cell.y, "type": tile_type})
	return {"added": [node], "removed": []} if node != null else {}


## 墙笔刷：在格子指定方向放置墙段。返回操作记录
static func paint_wall(root: Node3D, cell: Vector2i, direction: String) -> Dictionary:
	var wall_root := root.get_node_or_null("Walls")
	if wall_root == null:
		return {}
	# 同格同方向已存在则跳过
	if _find_wall(wall_root, cell, direction) != null:
		return {}
	var node := _add_wall(wall_root, cell.x, cell.y, direction)
	return {"added": [node], "removed": []} if node != null else {}


## 门笔刷：在格子指定方向放置门。返回操作记录
static func paint_door(root: Node3D, cell: Vector2i, direction: String) -> Dictionary:
	var door_root := root.get_node_or_null("Doors")
	if door_root == null:
		return {}
	if _find_door(door_root, cell, direction) != null:
		return {}
	var node := _add_door(door_root, cell.x, cell.y, direction)
	return {"added": [node], "removed": []} if node != null else {}


## 刷怪笔刷：在格子放置刷怪点，绑定怪物。返回操作记录
static func paint_spawn(
	root: Node3D, cell: Vector2i, spawn_type: String, monster_id: String
) -> Dictionary:
	var spawn_root := root.get_node_or_null("Spawns")
	if spawn_root == null:
		return {}
	# 同格已有刷怪点则更新怪物绑定（无新节点，记为 meta 变更）
	var existing := _find_node_at_cell(spawn_root, cell)
	if existing != null:
		var meta_dict := {
			"x": cell.x, "y": cell.y, "type": spawn_type, "monster_id": monster_id
		}
		existing.set_meta("cell", meta_dict)
		_apply_spawn_visual(existing, spawn_type)
		return {}  # 更新而非新增，暂不记 undo（meta 变更复杂）
	var node := _add_spawn(spawn_root, cell.x, cell.y, spawn_type, monster_id)
	return {"added": [node], "removed": []} if node != null else {}


## 橡皮擦：删除该格子的所有元素（四向墙+门+地板+刷怪点）
## removed 节点用 remove_child 保留引用供 undo
static func erase_cell(root: Node3D, cell: Vector2i) -> Dictionary:
	var removed: Array = []
	for child_name in ["Floor", "Walls", "Doors", "Spawns"]:
		var node := root.get_node_or_null(child_name)
		if node == null:
			continue
		# 该格子下所有元素（墙四向/门/地板/刷怪点全部匹配）
		for child in node.get_children():
			var c: Dictionary = child.get_meta("cell", {})
			if not c.is_empty() and c.x == cell.x and c.y == cell.y:
				node.remove_child(child)
				removed.append({"node": child, "parent": node})
	return {"added": [], "removed": removed}


## 矩形填充地板：from..to 矩形区域铺满指定材质（已存在的跳过）
static func fill_rect_floor(
	root: Node3D, from_cell: Vector2i, to_cell: Vector2i, tile_type: String = "stone"
) -> Dictionary:
	var floor_root := root.get_node_or_null("Floor")
	if floor_root == null:
		return {}
	var added: Array = []
	var x0 := mini(from_cell.x, to_cell.x)
	var x1 := maxi(from_cell.x, to_cell.x)
	var y0 := mini(from_cell.y, to_cell.y)
	var y1 := maxi(from_cell.y, to_cell.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var node := _add_floor(floor_root, {"x": x, "y": y, "type": tile_type})
			if node != null:
				added.append(node)
	return {"added": added, "removed": []}


## 矩形清除地板：from..to 矩形区域地板全删
static func clear_rect_floor(root: Node3D, from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	var floor_root := root.get_node_or_null("Floor")
	if floor_root == null:
		return {}
	var removed: Array = []
	var x0 := mini(from_cell.x, to_cell.x)
	var x1 := maxi(from_cell.x, to_cell.x)
	var y0 := mini(from_cell.y, to_cell.y)
	var y1 := maxi(from_cell.y, to_cell.y)
	for child in floor_root.get_children():
		var c: Dictionary = child.get_meta("cell", {})
		if c.is_empty():
			continue
		if x0 <= c.x and c.x <= x1 and y0 <= c.y and c.y <= y1:
			floor_root.remove_child(child)
			removed.append({"node": child, "parent": floor_root})
	return {"added": [], "removed": removed}


## 矩形墙圈：沿 from..to 矩形四条边放墙（内部不填充）
## 朝向按边决定：上边 north / 下边 south / 左边 west / 右边 east
static func place_wall_rect(root: Node3D, from_cell: Vector2i, to_cell: Vector2i) -> Dictionary:
	var added: Array = []
	var x0 := mini(from_cell.x, to_cell.x)
	var x1 := maxi(from_cell.x, to_cell.x)
	var y0 := mini(from_cell.y, to_cell.y)
	var y1 := maxi(from_cell.y, to_cell.y)
	# 上边（north）与下边（south）
	for x in range(x0, x1 + 1):
		var op_n := paint_wall(root, Vector2i(x, y0), "north")
		added.append_array(op_n.get("added", []))
		var op_s := paint_wall(root, Vector2i(x, y1), "south")
		added.append_array(op_s.get("added", []))
	# 左边（west）与右边（east）
	for y in range(y0, y1 + 1):
		var op_w := paint_wall(root, Vector2i(x0, y), "west")
		added.append_array(op_w.get("added", []))
		var op_e := paint_wall(root, Vector2i(x1, y), "east")
		added.append_array(op_e.get("added", []))
	return {"added": added, "removed": []}


## 矩形对角放置（门/刷怪点用）：只在两个对角点各放一个
static func place_corners(
	root: Node3D, from_cell: Vector2i, to_cell: Vector2i,
	element: String, dir_from: String, dir_to: String,
	spawn_type: String = "", monster_id: String = ""
) -> Dictionary:
	var added: Array = []
	var op1 := _place_single(root, from_cell, element, dir_from, spawn_type, monster_id)
	added.append_array(op1.get("added", []))
	var op2 := _place_single(root, to_cell, element, dir_to, spawn_type, monster_id)
	added.append_array(op2.get("added", []))
	return {"added": added, "removed": []}


## 单点放置统一入口（坐标放置面板用）
## element: "floor" / "wall" / "door" / "spawn"
static func place_single(
	root: Node3D, cell: Vector2i, element: String,
	direction: String = "north", tile_type: String = "stone",
	spawn_type: String = "enemy_spawn", monster_id: String = ""
) -> Dictionary:
	return _place_single(root, cell, element, direction, spawn_type, monster_id, tile_type)


## 单点放置（内部）
static func _place_single(
	root: Node3D, cell: Vector2i, element: String, direction: String,
	spawn_type: String = "", monster_id: String = "", tile_type: String = "stone"
) -> Dictionary:
	match element:
		"floor":
			return paint_floor(root, cell, tile_type)
		"wall":
			return paint_wall(root, cell, direction)
		"door":
			return paint_door(root, cell, direction)
		"spawn":
			return paint_spawn(root, cell, spawn_type, monster_id)
	return {}


## 坐标钳制到房间范围 [0, width-1] × [0, height-1]
static func clamp_cell(cell: Vector2i, width: int, height: int) -> Vector2i:
	return Vector2i(
		clampi(cell.x, 0, width - 1),
		clampi(cell.y, 0, height - 1)
	)


## 自动围墙：按房间尺寸在四周放墙，已有门的位置自动留洞
## 返回 {added, removed, msg}
static func auto_walls(root: Node3D, width: int, height: int) -> Dictionary:
	var wall_root := root.get_node_or_null("Walls")
	var door_root := root.get_node_or_null("Doors")
	if wall_root == null:
		return {"added": [], "removed": [], "msg": "无墙容器"}

	# 收集已有门的格子（门位置对应的边缘不放墙）
	var door_cells := {}
	if door_root:
		for child in door_root.get_children():
			var c: Dictionary = child.get_meta("cell", {})
			if not c.is_empty():
				door_cells["%d_%d_%s" % [c.x, c.y, c.get("direction", "")]] = true

	var added: Array = []
	var count := 0
	for x in range(width):
		for dir_y in [["north", 0], ["south", height - 1]]:
			var key := "%d_%d_%s" % [x, dir_y[1], dir_y[0]]
			if not door_cells.has(key):
				var op := paint_wall(root, Vector2i(x, dir_y[1]), dir_y[0])
				added.append_array(op.get("added", []))
				count += 1
	for y in range(height):
		for dir_x in [["west", 0], ["east", width - 1]]:
			var key := "%d_%d_%s" % [dir_x[1], y, dir_x[0]]
			if not door_cells.has(key):
				var op := paint_wall(root, Vector2i(dir_x[1], y), dir_x[0])
				added.append_array(op.get("added", []))
				count += 1
	return {
		"added": added,
		"removed": [],
		"msg": "补墙 %d 段（已有墙跳过，门位置留洞）" % count,
	}


## 校验房间：返回问题列表（空=通过）
## 检查：地板覆盖率 / 门越界 / spawn 在无地板格 / 无 player_spawn
static func validate_room(root: Node3D, meta: Dictionary) -> Array:
	var issues: Array = []
	var width: int = meta.get("width", 20)
	var height: int = meta.get("height", 15)

	# 收集数据
	var floor_cells := {}
	var door_list: Array = []
	var spawn_list: Array = []
	var floor_root := root.get_node_or_null("Floor")
	if floor_root:
		for child in floor_root.get_children():
			var c: Dictionary = child.get_meta("cell", {})
			if not c.is_empty():
				floor_cells[Vector2i(c.x, c.y)] = true
	var door_root := root.get_node_or_null("Doors")
	if door_root:
		for child in door_root.get_children():
			var c: Dictionary = child.get_meta("cell", {})
			if not c.is_empty():
				door_list.append(c)
	var spawn_root := root.get_node_or_null("Spawns")
	if spawn_root:
		for child in spawn_root.get_children():
			var c: Dictionary = child.get_meta("cell", {})
			if not c.is_empty():
				spawn_list.append(c)

	# 1. 地板覆盖率
	var total := width * height
	if floor_cells.size() < total:
		issues.append("地板未铺满：%d/%d 格（可用矩形填充或自动围墙后铺地）" % [floor_cells.size(), total])

	# 2. 门越界 / 门无地板
	for d in door_list:
		var dc := Vector2i(d.x, d.y)
		var dir := str(d.get("direction", ""))
		# 门在边界格子检查（north 门应在 y=0 行，south 在 y=height-1 行等）
		var on_boundary := false
		match dir:
			"north": on_boundary = dc.y == 0
			"south": on_boundary = dc.y == height - 1
			"west":  on_boundary = dc.x == 0
			"east":  on_boundary = dc.x == width - 1
		if not on_boundary:
			issues.append("门 (%d,%d,%s) 不在房间边界上" % [dc.x, dc.y, dir])
		if not floor_cells.has(dc):
			issues.append("门 (%d,%d,%s) 所在格无地板" % [dc.x, dc.y, dir])

	# 3. spawn 检查
	var has_player_spawn := false
	for s in spawn_list:
		var sc := Vector2i(s.x, s.y)
		var stype := str(s.get("type", ""))
		if stype == "player_spawn":
			has_player_spawn = true
		if not floor_cells.has(sc):
			issues.append("刷怪点 (%d,%d,%s) 在无地板格" % [sc.x, sc.y, stype])
		if sc.x < 0 or sc.x >= width or sc.y < 0 or sc.y >= height:
			issues.append("刷怪点 (%d,%d) 超出房间范围" % [sc.x, sc.y])
	if not has_player_spawn and str(meta.get("room_type", "")) == "start":
		issues.append("起始房缺少玩家出生点")

	return issues


## 删除格子指定方向的墙。返回操作记录
static func erase_wall(root: Node3D, cell: Vector2i, direction: String) -> Dictionary:
	var wall_root := root.get_node_or_null("Walls")
	if wall_root == null:
		return {}
	var target := _find_wall(wall_root, cell, direction)
	if target:
		wall_root.remove_child(target)
		return {"added": [], "removed": [{"node": target, "parent": wall_root}]}
	return {}


# ============================================================
# 节点创建（内部）
# ============================================================

## 创建地板节点
static func _add_floor(parent: Node3D, tile: Dictionary) -> Node3D:
	var x := int(tile.get("x", 0))
	var y := int(tile.get("y", 0))
	var tile_type := str(tile.get("type", "stone"))

	var node := _instantiate_scene(FLOOR_SCENE)
	if node == null:
		node = _create_floor_placeholder()
	node.position = cell_to_world(Vector2i(x, y))
	node.name = "Floor_%d_%d" % [x, y]
	node.set_meta("cell", {"x": x, "y": y, "type": tile_type})
	_apply_floor_material(node, tile_type)
	parent.add_child(node)
	return node


## 创建墙节点
static func _add_wall(parent: Node3D, x: int, y: int, direction: String, wall_type: String = "normal_wall") -> Node3D:
	var node := _instantiate_scene(WALL_SCENE)
	if node == null:
		node = _create_wall_placeholder()
	node.position = _edge_position(x, y, direction)
	node.rotation = _edge_rotation(direction)
	node.name = "Wall_%d_%d_%s" % [x, y, direction]
	node.set_meta("cell", {"x": x, "y": y, "direction": direction, "type": wall_type})
	parent.add_child(node)
	return node


## 创建门节点
static func _add_door(parent: Node3D, x: int, y: int, direction: String) -> Node3D:
	var node := _instantiate_scene(DOOR_SCENE)
	if node == null:
		node = _create_door_placeholder()
	node.position = _edge_position(x, y, direction)
	node.rotation = _edge_rotation(direction)
	node.name = "Door_%d_%d_%s" % [x, y, direction]
	node.set_meta("cell", {"x": x, "y": y, "direction": direction})
	parent.add_child(node)
	return node


## 创建刷怪点标记
static func _add_spawn(
	parent: Node3D, x: int, y: int, type: String, monster_id: String
) -> Node3D:
	var marker := Marker3D.new()
	marker.position = cell_to_world(Vector2i(x, y))
	marker.name = "Spawn_%d_%d" % [x, y]
	marker.set_meta("cell", {"x": x, "y": y, "type": type, "monster_id": monster_id})
	_apply_spawn_visual(marker, type)
	parent.add_child(marker)
	return marker


# ============================================================
# 查找（内部）
# ============================================================

## 在容器里找指定格子的节点（地板/刷怪点用）
static func _find_node_at_cell(parent: Node3D, cell: Vector2i) -> Node3D:
	for child in parent.get_children():
		var c: Dictionary = child.get_meta("cell", {})
		if c.x == cell.x and c.y == cell.y:
			return child
	return null


## 找指定格子+方向的墙
static func _find_wall(parent: Node3D, cell: Vector2i, direction: String) -> Node3D:
	for child in parent.get_children():
		var c: Dictionary = child.get_meta("cell", {})
		if c.x == cell.x and c.y == cell.y and str(c.get("direction", "")) == direction:
			return child
	return null


## 找指定格子+方向的门
static func _find_door(parent: Node3D, cell: Vector2i, direction: String) -> Node3D:
	for child in parent.get_children():
		var c: Dictionary = child.get_meta("cell", {})
		if c.x == cell.x and c.y == cell.y and str(c.get("direction", "")) == direction:
			return child
	return null


# ============================================================
# 几何与材质（内部）
# ============================================================

## 墙/门在格子边缘的位置（与 WallBuilder._get_edge_position 一致：y=高度/2）
static func _edge_position(x: int, y: int, direction: String) -> Vector3:
	var p := Vector3(float(x), 1.5, float(y))
	match direction:
		"north":
			p.z -= CELL_SIZE * 0.5
		"south":
			p.z += CELL_SIZE * 0.5
		"west":
			p.x -= CELL_SIZE * 0.5
		"east":
			p.x += CELL_SIZE * 0.5
	return p


## 墙/门旋转（与 WallBuilder._get_edge_rotation 一致）
static func _edge_rotation(direction: String) -> Vector3:
	match direction:
		"east", "west":
			return Vector3(0.0, deg_to_rad(90.0), 0.0)
	return Vector3.ZERO


## 旧数据墙无 direction 时推断朝向
static func _infer_wall_direction(x: int, y: int, w: int, h: int) -> String:
	if y == 0:
		return "north"
	if y == h - 1:
		return "south"
	if x == 0:
		return "west"
	if x == w - 1:
		return "east"
	return "north"


## 实例化场景，失败返回 null
static func _instantiate_scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := ResourceLoader.load(
		path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


## 地板占位（场景缺失时）
static func _create_floor_placeholder() -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh = PlaneMesh.new()
	return node


## 墙占位（场景缺失时）
static func _create_wall_placeholder() -> Node3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CELL_SIZE, 3.0, 0.2)
	node.mesh = box
	return node


## 门占位（场景缺失时）
static func _create_door_placeholder() -> Node3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 0.3)
	node.mesh = box
	return node


## 给地板上色（按类型）
static func _apply_floor_material(node: Node3D, tile_type: String) -> void:
	var mat := StandardMaterial3D.new()
	match tile_type:
		"stone":
			mat.albedo_color = Color(0.35, 0.35, 0.4)
		"wood":
			mat.albedo_color = Color(0.45, 0.3, 0.2)
		"grass":
			mat.albedo_color = Color(0.2, 0.5, 0.2)
		_:
			mat.albedo_color = Color(0.4, 0.4, 0.4)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_set_material_override(node, mat)


## 给刷怪点上色（按类型，便于区分）
static func _apply_spawn_visual(node: Node3D, type: String) -> void:
	# Marker3D 在编辑器里有内置图标，这里用 mesh 让 3D 视口可见
	if node is Marker3D:
		# Marker3D 不显示 mesh，加一个子 MeshInstance3D 表示
		for child in node.get_children():
			child.free()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.8, 0.4)
		mesh.mesh = box
		mesh.position.y = 0.4
		var mat := StandardMaterial3D.new()
		match type:
			"enemy_spawn":
				mat.albedo_color = Color(0.8, 0.2, 0.2)
			"elite_spawn":
				mat.albedo_color = Color(0.6, 0.1, 0.1)
			"boss_spawn":
				mat.albedo_color = Color(0.5, 0.0, 0.3)
			"chest_spawn":
				mat.albedo_color = Color(0.8, 0.7, 0.1)
			"player_spawn":
				mat.albedo_color = Color(0.2, 0.6, 0.2)
			_:
				mat.albedo_color = Color(0.5, 0.5, 0.5)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		node.add_child(mesh)


## 给节点的 MeshInstance3D 设材质覆盖
static func _set_material_override(node: Node3D, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat
			return
