class_name DoorBuilder
extends RefCounted
## 门生成器 —— HD-2D 重构版
## 根据 RoomData 在房间边界创建门（Area3D 触发器）

const DOOR_PATH := "res://scenes/props/door.tscn"

const DOOR_WIDTH := 2.0
const DOOR_HEIGHT := 3.0
const DOOR_THICKNESS := 0.3
const CELL_SIZE := 1.0


## 生成门到指定父节点
static func build(parent: Node3D, data) -> void:
	for door_data in data.get("doors", []):
		_create_door(parent, door_data, data)


## 创建单个门
static func _create_door(parent: Node3D, door_data: Dictionary, data) -> void:
	var direction := str(door_data.get("direction", "north"))
	var door_id := str(door_data.get("id", direction))

	# 门位置：优先用 JSON 的格子坐标（编辑器口径，x/y 是格子）
	# 旧数据无 x/y 时回退到房间边界中心公式
	var position: Vector3 = _door_position_from_cell(door_data, direction)
	if position == Vector3.INF:
		position = _get_door_position(data, direction)

	# 尝试加载预制体，失败则创建基础门
	var door: Node3D
	if ResourceLoader.exists(DOOR_PATH):
		var scene := ResourceLoader.load(DOOR_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		if scene:
			door = scene.instantiate()
		else:
			door = _create_door_node()
	else:
		door = _create_door_node()

	door.position = position
	door.rotation = _get_door_rotation(direction)
	door.name = "Door_%s" % door_id

	# 设置门属性：触发器写入方向，body_entered 连接 door_trigger 自身的处理
	for child in door.get_children():
		if child is Area3D:
			child.add_to_group("door_trigger")
			child.set("direction", direction)
			# 连接 Area3D 信号到 door_trigger.gd 的 _on_body_entered（真实穿门传送）
			if child.has_method("_on_body_entered"):
				child.body_entered.connect(child._on_body_entered)

	parent.add_child(door)


## 由格子坐标计算门位置（编辑器口径：门在格子边缘，与墙同算法）
## JSON 无 x/y 时返回 Vector3.INF（走回退公式）
static func _door_position_from_cell(door_data: Dictionary, direction: String) -> Vector3:
	if not door_data.has("x") or not door_data.has("y"):
		return Vector3.INF
	var x := int(door_data["x"])
	var y := int(door_data["y"])
	var p := Vector3(float(x), DOOR_HEIGHT / 2.0, float(y))
	match direction:
		"north":
			p.z -= 0.5
		"south":
			p.z += 0.5
		"west":
			p.x -= 0.5
		"east":
			p.x += 0.5
	return p


## 创建基础门节点
static func _create_door_node() -> Node3D:
	var root := Node3D.new()

	var frame := MeshInstance3D.new()
	frame.name = "DoorFrame"
	var frame_box := BoxMesh.new()
	frame_box.size = Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_THICKNESS)
	frame.mesh = frame_box
	var frame_mat := ToonMaterial.create(Color(0.3, 0.22, 0.15))
	frame.material_override = frame_mat
	root.add_child(frame)

	var area := Area3D.new()
	area.name = "DoorTrigger"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_THICKNESS * 2)
	collision.shape = shape
	area.add_child(collision)

	# 加载门脚本
	var door_script := load("res://world/rooms/door_trigger.gd")
	area.set_script(door_script)
	area.add_to_group("door_trigger")

	root.add_child(area)
	return root


## 计算门在房间边界的位置
static func _get_door_position(data, direction: String) -> Vector3:
	var width := float(data.get("width", 16))
	var height := float(data.get("height", 12))
	var center_x := width / 2.0
	var center_y := height / 2.0

	match direction:
		"north":
			return Vector3(center_x, DOOR_HEIGHT / 2.0, -0.5)
		"south":
			return Vector3(center_x, DOOR_HEIGHT / 2.0, height - 0.5)
		"west":
			return Vector3(-0.5, DOOR_HEIGHT / 2.0, center_y)
		"east":
			return Vector3(width - 0.5, DOOR_HEIGHT / 2.0, center_y)

	return Vector3.ZERO


## 获取门的旋转角度
static func _get_door_rotation(direction: String) -> Vector3:
	match direction:
		"east", "west":
			return Vector3(0.0, deg_to_rad(90.0), 0.0)
	return Vector3.ZERO