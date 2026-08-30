extends Node3D
## GameRoot —— 游戏场景根节点，HD-2D 重构版
## 管理地下城生成、房间加载、房间切换
## 替代 Autoload DungeonManager，避免 class_name 编译依赖

const ROOM_DATA_DIR := "res://data/rooms/"
const ROOM_SIZE := 30.0

# 房间模板
var room_templates: Dictionary = {}
# 地下城数据
var dungeon_graph: Array[Dictionary] = []
var dungeon_connections: Array[Array] = []
var current_room_index := 0
var dungeon_generated := false
var current_room_node: Node3D = null
var room_state: Dictionary = {}

# 子节点
@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig
@onready var player: Node3D = $Player


func _ready() -> void:
	# 直跑场景兜底：未经主菜单 start_new_run 时初始化局内数据
	if GameManager.attributes == null:
		GameManager.start_new_run(GameManager.run_info.duplicate())
	_register_templates()
	EventBus.door_opened.connect(_on_door_entered)
	# 延迟生成地下城
	call_deferred("_init_dungeon")


func _init_dungeon() -> void:
	generate_dungeon(randi(), 13)
	load_current_room()
	_place_player()
	_activate_current_room()


## 进入下一层：清空当前层 → 重生成地牢 → 回初始房
func next_floor() -> void:
	# 清空旧房间
	if current_room_node:
		current_room_node.queue_free()
		current_room_node = null
	room_state.clear()

	# 层数推进由 RoomController 传送门写入 run_info；此处读取
	var gm := get_node_or_null("/root/GameManager")
	var floor_num := 1
	if gm:
		floor_num = int(gm.run_info.get("floor", 1))
	var seed_value := randi()
	if gm and gm.rng:
		seed_value = gm.rng.randi()

	generate_dungeon(seed_value, 13)
	load_current_room()
	_place_player()
	_activate_current_room()

	if gm:
		gm.set_state(GameManager.GamePhase.DUNGEON)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.floor_changed.emit(floor_num)
		bus.message.emit("进入第 %d 层" % floor_num)


# ============================================================
# 模板注册
# ============================================================

func _register_templates() -> void:
	room_templates = {"start": [], "normal": [], "elite": [], "treasure": [], "boss": []}
	var dir := DirAccess.open(ROOM_DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json") and not dir.current_is_dir():
			var rtype := _read_json_field(ROOM_DATA_DIR + fn, "room_type")
			if not rtype.is_empty():
				if not room_templates.has(rtype):
					room_templates[rtype] = []
				room_templates[rtype].append(ROOM_DATA_DIR + fn)
		fn = dir.get_next()
	dir.list_dir_end()


func _read_json_field(path: String, field: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(t) != OK:
		return ""
	return str(j.data.get(field, ""))


# ============================================================
# 地下城生成
# ============================================================

func generate_dungeon(seed_value: int, count: int = 13) -> void:
	var gen := DungeonGenerator.new()
	gen.rng.set_seed(seed_value)
	gen.min_rooms = count
	gen.max_rooms = count
	gen.generate(seed_value)

	dungeon_graph = gen.rooms
	dungeon_connections = gen.connections
	dungeon_generated = true
	current_room_index = 0
	room_state.clear()

	for i in dungeon_graph.size():
		room_state[i] = {"cleared": false, "visited": false}


# ============================================================
# 房间加载
# ============================================================

func get_current_room_data() -> Dictionary:
	if dungeon_graph.is_empty() or current_room_index >= dungeon_graph.size():
		return {}
	return dungeon_graph[current_room_index]


func load_current_room() -> Node3D:
	var data := get_current_room_data()
	if data.is_empty():
		return _create_fallback_room()

	var room_type: String = data.get("type", "normal")
	var template_path := _pick_template(room_type)
	if template_path.is_empty():
		return _create_fallback_room()

	# 创建房间节点
	var room_node := Node3D.new()
	room_node.name = "Room_%d" % current_room_index
	world.add_child(room_node)

	# 子容器
	var containers := {}
	for name in ["Floor", "Walls", "Doors", "Props", "SpawnPoints"]:
		var c := Node3D.new()
		c.name = name
		room_node.add_child(c)
		containers[name] = c

	# 加载 RoomData 并构建
	var RoomDataClass = load("res://data/rooms/room_data.gd")
	var jd := _read_json_dict(template_path)
	if RoomDataClass and not jd.is_empty():
		var rd = RoomDataClass.new()
		rd.load_from_dict(jd)
		FloorBuilder.build(containers["Floor"], jd)
		WallBuilder.build(containers["Walls"], jd)
		DoorBuilder.build(containers["Doors"], jd)
		DecorationBuilder.build(containers["Props"], jd)
		_build_spawn_markers(containers["SpawnPoints"], jd)

		# 附加 RoomController
		var controller := RoomController.new()
		controller.name = "RoomController"
		controller.set("room_data", jd)
		room_node.add_child(controller)

	room_node.position = Vector3(0, 0, 0)
	room_state[current_room_index]["visited"] = true
	current_room_node = room_node
	return room_node


func _read_json_dict(path: String) -> Dictionary:
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


func _pick_template(room_type: String) -> String:
	var templates: Array = room_templates.get(room_type, [])
	if templates.is_empty():
		for key in room_templates:
			var arr: Array = room_templates[key]
			if not arr.is_empty():
				return arr[0]
		return ""
	return templates[randi() % templates.size()]


func _build_spawn_markers(parent: Node3D, data) -> void:
	var entities = data.get("entities", [])
	for entity in entities:
		var etype := str(entity.get("type", ""))
		var gn := ""
		match etype:
			"player_spawn": gn = "player_spawn"
			"enemy_spawn":  gn = "enemy_spawn"
			"elite_spawn":  gn = "elite_spawn"
			"boss_spawn":   gn = "boss_spawn"
			"chest_spawn":  gn = "chest_spawn"
		if gn.is_empty():
			continue
		var marker := Marker3D.new()
		marker.position = Vector3(float(entity.get("x", 0)), 0.0, float(entity.get("y", 0)))
		marker.add_to_group(gn)
		parent.add_child(marker)


func _create_fallback_room() -> Node3D:
	var room_node := Node3D.new()
	room_node.name = "Room_Fallback"
	world.add_child(room_node)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor.mesh = plane
	room_node.add_child(floor)
	return room_node


# ============================================================
# 房间切换
# ============================================================

func _on_door_entered(direction: String, _door_id: String) -> void:
	if not dungeon_generated:
		return
	var target_idx := _find_room_in_direction(direction)
	if target_idx < 0:
		return
	_transition_to_room(target_idx)


func _find_room_in_direction(direction: String) -> int:
	var data := get_current_room_data()
	if data.is_empty():
		return -1
	var current_pos: Vector2i = data.get("position", Vector2i.ZERO)
	var dir_vec := Vector2i.ZERO
	match direction:
		"north": dir_vec = Vector2i(0, -1)
		"south": dir_vec = Vector2i(0, 1)
		"west":  dir_vec = Vector2i(-1, 0)
		"east":  dir_vec = Vector2i(1, 0)
	var target_pos := current_pos + dir_vec
	for i in dungeon_graph.size():
		var pos: Vector2i = dungeon_graph[i].get("position", Vector2i.ZERO)
		if pos == target_pos:
			return i
	return -1


func _transition_to_room(target_idx: int) -> void:
	if target_idx == current_room_index:
		return

	# 离开当前房间
	if current_room_node:
		var ctrl := current_room_node.get_node_or_null("RoomController")
		if ctrl and ctrl is RoomController:
			(ctrl as RoomController).deactivate()

	# 销毁旧房间
	if current_room_node:
		current_room_node.queue_free()
		current_room_node = null

	# 更新索引
	current_room_index = target_idx

	# 加载新房间
	load_current_room()
	_activate_current_room()
	_place_player()


func _activate_current_room() -> void:
	if current_room_node == null:
		return
	var ctrl := current_room_node.get_node_or_null("RoomController")
	if ctrl and ctrl is RoomController:
		(ctrl as RoomController).activate()


func _place_player() -> void:
	if player == null:
		return
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() > 0:
		player.global_position = (spawns[0] as Node3D).global_position
	else:
		player.global_position = Vector3(15, 0, 15)
