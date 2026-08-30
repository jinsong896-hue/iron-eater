class_name WallBuilder
extends RefCounted
## 墙壁生成器 —— HD-2D 重构版
## 根据数据生成 3D 墙壁（带碰撞）

const WALL_SEGMENT_PATH := "res://scenes/world/wall_segment.tscn"

const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.2
const CELL_SIZE := 1.0


## 生成墙壁到指定父节点
static func build(parent: Node3D, data) -> void:
	var walls: Array = data.get("walls", [])
	if walls.is_empty():
		_generate_boundary_walls(parent, data)
		return

	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	for wall in walls:
		# 旧数据无 direction 时，按墙在房间的位置推断朝向
		if not wall.has("direction"):
			wall["direction"] = _infer_direction(int(wall.get("x", 0)), int(wall.get("y", 0)), w, h)
		_create_wall_segment(parent, wall)


## 自动生成房间边界墙
static func _generate_boundary_walls(parent: Node3D, data) -> void:
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)

	for x in range(w):
		if not _has_door(data, "north"):
			_create_wall_segment(parent, {"x": x, "y": 0, "direction": "north", "type": "normal_wall"})
		if not _has_door(data, "south"):
			_create_wall_segment(parent, {"x": x, "y": h - 1, "direction": "south", "type": "normal_wall"})

	for y in range(h):
		if not _has_door(data, "west"):
			_create_wall_segment(parent, {"x": 0, "y": y, "direction": "west", "type": "normal_wall"})
		if not _has_door(data, "east"):
			_create_wall_segment(parent, {"x": w - 1, "y": y, "direction": "east", "type": "normal_wall"})


static func _has_door(data, direction: String) -> bool:
	var doors: Array = data.get("doors", [])
	for d in doors:
		if d.get("direction", "") == direction:
			return true
	return false


## 创建单段墙壁
static func _create_wall_segment(parent: Node3D, wall: Dictionary) -> void:
	var wall_type := str(wall.get("type", "normal_wall"))
	var x := int(wall.get("x", 0))
	var y := int(wall.get("y", 0))
	var direction := str(wall.get("direction", "north"))

	var segment: Node3D
	if ResourceLoader.exists(WALL_SEGMENT_PATH):
		var scene := ResourceLoader.load(WALL_SEGMENT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		if scene:
			segment = scene.instantiate()
		else:
			segment = _create_wall_node()
	else:
		segment = _create_wall_node()

	segment.position = _get_edge_position(x, y, direction)
	segment.rotation = _get_edge_rotation(direction)
	segment.name = "Wall_%d_%d_%s" % [x, y, direction]

	parent.add_child(segment)


## 创建基础墙壁节点（带碰撞）
static func _create_wall_node() -> Node3D:
	var root := Node3D.new()

	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS)
	mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh.material_override = mat

	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS)
	collision.shape = shape
	body.add_child(collision)

	root.add_child(mesh)
	root.add_child(body)

	return root


## 获取墙壁在格子边缘的位置
static func _get_edge_position(x: int, y: int, direction: String) -> Vector3:
	var p := RoomBuilder.grid_to_world(x, y, WALL_HEIGHT / 2.0)
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


## 获取墙壁旋转角度
static func _get_edge_rotation(direction: String) -> Vector3:
	match direction:
		"east", "west":
			return Vector3(0.0, deg_to_rad(90.0), 0.0)
	return Vector3.ZERO


## 旧数据无 direction 时，根据墙的位置推断朝向
## 房间边界墙：y=0→north，y=max→south，x=0→west，x=max→east；内部墙默认 north
static func _infer_direction(x: int, y: int, w: int, h: int) -> String:
	if y == 0:
		return "north"
	if y == h - 1:
		return "south"
	if x == 0:
		return "west"
	if x == w - 1:
		return "east"
	return "north"