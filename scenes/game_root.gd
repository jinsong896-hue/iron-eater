extends Node3D
## GameRoot —— 游戏场景根节点，HD-2D 重构版
## 管理地下城生成、房间加载、房间切换
## 替代 Autoload DungeonManager，避免 class_name 编译依赖

const ROOM_DATA_DIR := "res://data/rooms/"
const ROOM_SIZE := 30.0
## 穿门进房后，玩家落在入口门内侧多远处（避开触发器的体积，防止立刻回触发）
const DOOR_ENTRY_OFFSET := 2.0

# 房间模板
var room_templates: Dictionary = {}
# 地下城数据
var dungeon_graph: Array[Dictionary] = []
var dungeon_connections: Array[Array] = []
var dungeon_start_index := 0
var current_room_index := 0
var _is_transitioning := false   # 切房重入保护（见 _transition_to_room）
## 切房后的全局防抖窗口（秒）：期间忽略所有门信号，杜绝连锁切房。
## 只覆盖「落点踩门」那一两帧——设大了会误伤正常玩法（玩家快速连续穿门
## 会被拦掉，表现为门"没反应"）。0.15s ≈ 9 帧，足够覆盖落点抖动。
const TRANSITION_COOLDOWN := 0.15
var _last_transition_time := -999.0
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
	# 全局防抖：刚切完房的一小段时间内忽略所有门信号。
	# 落点靠近门、或奔跑时一帧位移大，都可能在同一帧/紧邻帧再次踩门；
	# 旧房间的门要到帧末才销毁，也在此时仍可被触发 → 「进一格穿两房」。
	# 单靠入口门自身的失效不够，这里再加一道与门无关的总闸。
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	var target_idx := _find_room_in_direction(direction)
	if target_idx < 0:
		return
	# 只在「门触发的切房」时启动防抖；程序性切房（下一层、测试直调）不启动，
	# 否则会误伤正常玩法与测试里的连续切房
	_last_transition_time = now
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
	# 重入保护：一次触发只切一次房。
	# 旧房间的门在本帧内仍然活着（queue_free 要到帧末），落点又靠近门，
	# 没有这道闸门时同一帧可能被第二扇门再触发一次 → 「进一格却穿两房」。
	if _is_transitioning:
		return
	_is_transitioning = true

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
	# 刚进来的那扇门暂时失效：玩家落点就在它旁边，立刻踩上会再触发一次
	# → 「进一格却穿两房」。短暂失效后恢复，保留回头路。
	_disarm_entry_door(enter_direction)

	_is_transitioning = false


## 让玩家刚穿过的那扇门短暂失效，避免落点踩门导致连锁切房
## 门方向 = 行进方向的反向（往东走 → 从本房西门进来）
func _disarm_entry_door(enter_direction: String) -> void:
	if enter_direction.is_empty() or current_room_node == null:
		return
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return
	var entry_dir := _opposite_dir(enter_direction)
	for door in doors_node.get_children():
		if not str(door.name).begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or str(trig.get("direction")) != entry_dir:
			continue
		if trig.has_method("disarm_until_clear"):
			trig.call("disarm_until_clear")
		return


func _activate_current_room() -> void:
	if current_room_node == null:
		return
	var ctrl := current_room_node.get_node_or_null("RoomController")
	if ctrl and ctrl is RoomController:
		(ctrl as RoomController).activate()


## 放置玩家。
## 顺序很重要：穿门切房时**必须**按入口门内侧落点，否则玩家会掉在房间中央
## （甚至落在别的门触发器上）导致反复切房 / 走进不该进的房间。
##
## 原实现先查全局 player_spawn 组，而每个模板都有该标记且旧房间是延迟销毁，
## 于是 spawns[0] 可能取到**上一个房间的残留标记** —— 这就是"随机跳到其他房间
## /传送到地图外"的根因。现改为：按门优先，本房标记只在无方向时用。
func _place_player(enter_direction: String = "") -> void:
	if player == null:
		return

	# 关键：落点前清零速度。
	# 奔跑穿门时玩家带着 7m/s 的惯性被搬到新房间门内侧，若不清零，
	# 一帧就能再次踩上门触发器；门失效保护只有 0.25s，
	# 足够跑出 1.75m —— 小房间里足以冲过整个房间踩到对面门，
	# 表现为「进右边的门却到了右边两格」。
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)

	# 1) 有进入方向（穿门切房）：放在入口门内侧
	if enter_direction != "" and _place_player_at_door(enter_direction):
		return

	# 2) 无方向（开局 / 传送门进新层）：用**本房**的 player_spawn 标记
	var spawn := _current_room_player_spawn()
	if spawn != null:
		player.global_position = spawn.global_position
		return

	# 3) 兜底：房间中心（原先用 Vector3.ZERO，那是房间角落的墙里）
	player.global_position = _room_center_world()


## 取当前房间自己的 player_spawn 标记（限定在本房间节点内，不跨房间）
func _current_room_player_spawn() -> Node3D:
	if current_room_node == null:
		return null
	for child in current_room_node.get_children():
		if child.is_in_group("player_spawn"):
			return child as Node3D
	# 标记可能挂在下级容器里
	for node in current_room_node.find_children("*", "Marker3D", true, false):
		if (node as Node).is_in_group("player_spawn"):
			return node as Node3D
	return null


## 当前房间的世界中心（按模板宽高算，不是硬编码的角落/固定值）
func _room_center_world() -> Vector3:
	var ctrl = current_room_node.get_node_or_null("RoomController") if current_room_node else null
	if ctrl != null:
		var d = ctrl.get("room_data")
		if d is Dictionary:
			return Vector3(float(d.get("width", 20)) * 0.5, 0.0, float(d.get("height", 15)) * 0.5)
	if current_room_node != null:
		# 退化：取所有生成点标记的包围盒中心
		var marks := current_room_node.find_children("*", "Marker3D", true, false)
		if not marks.is_empty():
			var sum := Vector3.ZERO
			for m in marks:
				sum += (m as Node3D).global_position
			return sum / float(marks.size())
	return Vector3.ZERO


## 按进入方向把玩家放在入口门内侧 1.5m
##
## 方向语义易错：从 A 往北走，进入的是 B 的**南门**（B 在 A 北侧），
## 且要在 B 内继续向**北**推进。原实现找的是「同向门」并往反向放，
## 结果玩家被放到房间另一侧（正好落在对面门触发器上 → 再次切房）。
func _place_player_at_door(enter_direction: String) -> bool:
	if current_room_node == null:
		return false
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return false

	# 进入本房所穿的门，方向与行进方向相反
	var entry_door_dir := _opposite_dir(enter_direction)
	# 进门后继续深入的方向就是行进方向
	var inward := _dir_vector(enter_direction)

	for door in doors_node.get_children():
		if not door.name.begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or str(trig.get("direction")) != entry_door_dir:
			continue
		player.global_position = (door as Node3D).global_position + inward * DOOR_ENTRY_OFFSET
		return true
	return false


## 行进方向 → 该方向上的单位向量（3D，x 东 / z 南）
func _dir_vector(dir: String) -> Vector3:
	match dir:
		"north": return Vector3(0, 0, -1)
		"south": return Vector3(0, 0, 1)
		"west":  return Vector3(-1, 0, 0)
		"east":  return Vector3(1, 0, 0)
	return Vector3.ZERO


## 相反方向
func _opposite_dir(dir: String) -> String:
	match dir:
		"north": return "south"
		"south": return "north"
		"west":  return "east"
		"east":  return "west"
	return ""
