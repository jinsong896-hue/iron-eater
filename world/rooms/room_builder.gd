class_name RoomBuilder
extends Node3D
## 房间生成器 —— HD-2D 重构版
## 核心转换器：RoomData → 3D Room 场景
## 负责协调 FloorBuilder / WallBuilder / DoorBuilder 等子模块

@export var room_data_path := ""

const CELL_SIZE := 1.0

@onready var floor_root: Node3D = $Floor
@onready var wall_root: Node3D = $Walls
@onready var door_root: Node3D = $Doors
@onready var prop_root: Node3D = $Props
@onready var spawn_root: Node3D = $SpawnPoints

var room_data = null   # RoomData


func _ready() -> void:
	if not room_data_path.is_empty():
		build_from_file(room_data_path)


## 从 RoomData 构建 3D 房间
func build(data) -> void:
	room_data = data
	clear_room()

	# 构建各组件
	FloorBuilder.build(floor_root, data)
	WallBuilder.build(wall_root, data)
	DoorBuilder.build(door_root, data)
	DecorationBuilder.build(prop_root, data)

	# 创建生成点
	_build_spawn_points(data)


## 从 JSON 文件路径构建
func build_from_file(path: String) -> void:
	var jd := _read_json_file(path)
	if jd.is_empty():
		return
	var RoomDataClass = load("res://data/rooms/room_data.gd")
	if RoomDataClass == null:
		return
	var data = RoomDataClass.new()
	data.load_from_dict(jd)
	build(data)


## 从 JSON 文件读取数据
func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(t) != OK:
		return {}
	return j.data


## 网格坐标转世界坐标
static func grid_to_world(x: int, y: int, height: float = 0.0) -> Vector3:
	return Vector3(float(x) * CELL_SIZE, height, float(y) * CELL_SIZE)


## 清理房间
func clear_room() -> void:
	for root in [floor_root, wall_root, door_root, prop_root, spawn_root]:
		if root:
			for child in root.get_children():
				child.queue_free()


## 创建生成点标记
func _build_spawn_points(data) -> void:
	for entity in data.entities:
		var type := str(entity.get("type", ""))
		var group_name := _get_spawn_group(type)
		if group_name.is_empty():
			continue

		var marker := Marker3D.new()
		marker.position = grid_to_world(int(entity.get("x", 0)), int(entity.get("y", 0)), 0.0)
		marker.add_to_group(group_name)
		# 绑定具体怪物 ID（供 enemy_spawner 读取）
		var monster_id := str(entity.get("monster_id", ""))
		if monster_id != "":
			marker.set_meta("monster_id", monster_id)
		spawn_root.add_child(marker)


func _get_spawn_group(type: String) -> String:
	match type:
		"player_spawn":
			return "player_spawn"
		"enemy_spawn":
			return "enemy_spawn"
		"elite_spawn":
			return "elite_spawn"
		"boss_spawn":
			return "boss_spawn"
		"chest_spawn":
			return "chest_spawn"
		"shop_npc":
			return "shop_npc"
		_:
			return ""