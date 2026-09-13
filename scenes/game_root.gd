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
var dungeon_start_index := 0
var current_room_index := 0
var dungeon_generated := false
var current_room_node: Node3D = null
var room_state: Dictionary = {}

# 子节点
@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig
@onready var player: Node3D = $Player


func _ready() -> void:
	# 小地图数据源（HUD MinimapView 自动拉取）
	add_to_group("game_root")
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
	room_templates = {"start": [], "normal": [], "elite": [], "treasure": [], "boss": [], "shop": [], "heal": [], "event": []}
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
	dungeon_start_index = gen.start_room_index
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
		# 门按地牢拓扑重算，覆盖模板里写死的门（消除哑门与死胡同）
		_apply_topology_doors(jd)
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


## 按地牢拓扑重算本房的门，写回 jd["doors"]，并让边界墙在门格留洞
## 模板里的门方位是固定的，与随机拓扑对不上就会产生哑门（走上去不切房）
func _apply_topology_doors(jd: Dictionary) -> void:
	if dungeon_graph.is_empty() or dungeon_connections.is_empty():
		return
	if current_room_index < 0 or current_room_index >= dungeon_graph.size():
		return

	var start_idx: int = clampi(dungeon_start_index, 0, dungeon_graph.size() - 1)
	var parents: Array = DoorsByTopology.bfs_parents(dungeon_graph, dungeon_connections, start_idx)
	var back_idx: int = start_idx
	if current_room_index < parents.size() and int(parents[current_room_index]) >= 0:
		back_idx = int(parents[current_room_index])

	var w: int = int(jd.get("width", 20))
	var h: int = int(jd.get("height", 15))
	var doors: Array = DoorsByTopology.build_doors(
		dungeon_graph, dungeon_connections, current_room_index,
		start_idx, back_idx, w, h
	)
	if doors.is_empty():
		return
	jd["doors"] = doors

	# 墙在门格留洞：门替换的是「同名方位」的墙段
	# （门与墙同方位时位置重合；角落格的反向墙要保留）
	var door_keys := {}
	for d in doors:
		door_keys["%d_%d_%s" % [int(d["x"]), int(d["y"]), str(d["direction"])]] = true
	var walls: Array = []
	for wall in jd.get("walls", []):
		var wdk := "%d_%d_%s" % [
			int(wall.get("x", 0)), int(wall.get("y", 0)), str(wall.get("direction", ""))
		]
		if door_keys.has(wdk):
			continue
		walls.append(wall)
	jd["walls"] = walls


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
			"shop_npc":     gn = "shop_npc"
			"heal_shrine":  gn = "heal_shrine"
			"event_shrine": gn = "event_shrine"
		if gn.is_empty():
			continue
		var marker := Marker3D.new()
		marker.position = Vector3(float(entity.get("x", 0)), 0.0, float(entity.get("y", 0)))
		marker.add_to_group(gn)
		parent.add_child(marker)
		# 宝箱：chest_spawn 处实例化宝箱实体（可交互掉落）
		if etype == "chest_spawn":
			_spawn_chest(marker.position, parent)
		# 特殊房交互物：商店 NPC / 治疗泉水 / 事件祭坛
		elif etype in ["shop_npc", "heal_shrine", "event_shrine"]:
			_spawn_special_prop(marker.position, etype, parent)


## 在标记位置生成特殊房交互物（按实体类型决定外观）
func _spawn_special_prop(pos: Vector3, entity_type: String, parent: Node3D) -> void:
	var kinds := {"shop_npc": "shop", "heal_shrine": "heal", "event_shrine": "event"}
	var kind: String = kinds.get(entity_type, "")
	if kind.is_empty():
		return
	var script_res := load("res://world/props/special_prop.gd")
	if script_res == null:
		return
	var prop := Node3D.new()
	prop.name = "SpecialProp_%s" % kind
	prop.set_script(script_res)
	prop.set("prop_kind", kind)
	prop.position = pos
	parent.add_child(prop)


## 在标记位置生成宝箱实体
func _spawn_chest(pos: Vector3, parent: Node3D) -> void:
	var chest_scene := "res://scenes/props/chest.tscn"
	if not ResourceLoader.exists(chest_scene):
		return
	var scene := ResourceLoader.load(chest_scene, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return
	var chest := scene.instantiate()
	chest.position = pos
	parent.add_child(chest)


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
	_transition_to_room(target_idx, direction)


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


func _transition_to_room(target_idx: int, enter_direction: String = "") -> void:
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
	_place_player(enter_direction)


func _activate_current_room() -> void:
	if current_room_node == null:
		return
	var ctrl := current_room_node.get_node_or_null("RoomController")
	if ctrl and ctrl is RoomController:
		(ctrl as RoomController).activate()


## 放置玩家：优先 player_spawn 标记；无标记时按进入方向放在入口门内侧
func _place_player(enter_direction: String = "") -> void:
	if player == null:
		return
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() > 0:
		player.global_position = (spawns[0] as Node3D).global_position
		return

	if enter_direction != "" and current_room_node:
		var placed := _place_player_at_door(enter_direction)
		if placed:
			return

	# 兜底：房间中心
	if current_room_node:
		player.global_position = Vector3.ZERO
	else:
		player.global_position = Vector3(15, 0, 15)


## 按进入方向把玩家放在入口门内侧 1.5m（相对门触发器位置）
func _place_player_at_door(enter_direction: String) -> bool:
	if current_room_node == null:
		return false
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return false

	# 玩家从 enter_direction 的门进入（例如从北门进，即当前房的 north 门）
	for door in doors_node.get_children():
		if not door.name.begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or str(trig.get("direction")) != enter_direction:
			continue
		# 门内侧方向：与进入方向相反
		var inward := Vector3.ZERO
		match enter_direction:
			"north": inward = Vector3(0, 0, 1)
			"south": inward = Vector3(0, 0, -1)
			"west":  inward = Vector3(1, 0, 0)
			"east":  inward = Vector3(-1, 0, 0)
		player.global_position = door.global_position + inward * 1.5
		return true
	return false
