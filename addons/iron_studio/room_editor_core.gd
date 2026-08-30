class_name RoomEditorCore
extends RefCounted
## 3D 房间编辑器核心 —— 节点树 ↔ JSON 转换、格子计算、笔刷操作
## 编辑期间 3D 节点树是真实数据源，JSON 是存盘格式
## 每个节点用 set_meta("cell", {...}) 存原始格子数据，序列化时直接读

# 笔刷工具枚举
enum Tool {
	FLOOR,
	WALL_EDGE,
	WALL_CELL,
	WALL_LINE,
	DOOR,
	SPAWN,
	ERASER,
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

	# 墙（用数据里的 direction，缺失则推断）
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	for wall in data.get("walls", []):
		var direction := str(wall.get("direction", ""))
		if direction.is_empty():
			direction = _infer_wall_direction(int(wall.get("x", 0)), int(wall.get("y", 0)), w, h)
		_add_wall(wall_root, int(wall.get("x", 0)), int(wall.get("y", 0)), direction)

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
				"type": "normal_wall",
			})

	var door_root := root.get_node_or_null("Doors")
	if door_root:
		for child in door_root.get_children():
			var cell: Dictionary = child.get_meta("cell", {})
			if cell.is_empty():
				continue
			var dir := str(cell.get("direction", "north"))
			doors.append({"direction": dir, "id": dir, "x": cell.x, "y": cell.y})

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
		"tags": [meta.get("room_type", "normal")],
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


## 橡皮擦：删除该格子的所有元素。返回操作记录（removed 节点用 remove_child 保留引用供 undo）
static func erase_cell(root: Node3D, cell: Vector2i) -> Dictionary:
	var removed: Array = []
	for child_name in ["Floor", "Walls", "Doors", "Spawns"]:
		var node := root.get_node_or_null(child_name)
		if node == null:
			continue
		# 删该格子所有墙/门（任意方向）
		if child_name in ["Walls", "Doors"]:
			for child in node.get_children():
				var c: Dictionary = child.get_meta("cell", {})
				if c.x == cell.x and c.y == cell.y:
					node.remove_child(child)
					removed.append({"node": child, "parent": node})
		else:
			var target := _find_node_at_cell(node, cell)
			if target:
				node.remove_child(target)
				removed.append({"node": target, "parent": node})
	return {"added": [], "removed": removed}


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
static func _add_wall(parent: Node3D, x: int, y: int, direction: String) -> Node3D:
	var node := _instantiate_scene(WALL_SCENE)
	if node == null:
		node = _create_wall_placeholder()
	node.position = _edge_position(x, y, direction)
	node.rotation = _edge_rotation(direction)
	node.name = "Wall_%d_%d_%s" % [x, y, direction]
	node.set_meta("cell", {"x": x, "y": y, "direction": direction})
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

## 墙/门在格子边缘的位置（与 WallBuilder._get_edge_position 一致）
static func _edge_position(x: int, y: int, direction: String) -> Vector3:
	var p := cell_to_world(Vector2i(x, y))
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
