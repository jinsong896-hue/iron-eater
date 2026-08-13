class_name DungeonGenerator
extends Node2D
## 随机地牢生成器（Godot GDScript）
## 依据《关卡设计分册》：
##  - 母网格 14×14 → 30×30（ChapterConfig.map_size）
##  - BSP 生成房间，房间 1～3 格，初始房中心 (0,0)，Boss 房最远端
##  - 瓦片规格：64×64；1 格 = 20×12 瓦片（1280×768px）；墙厚 2 瓦片（128px）
##  - 走廊连通 + 门洞自动开凿 + NavigationServer2D 寻路烘焙

const TILE_SIZE := 64
const LAYOUT_CELL := Vector2(1280.0, 768.0)   # 1 格 = 20×12 瓦片
const WALL_PX := 128.0                        # 2 瓦片墙厚
const DOOR_HALF_WIDTH := 96.0                 # 门洞半宽（3 瓦片 = 192px）

const RoomDataScript := preload("res://scripts/dungeon/room_data.gd")
const BSPNodeScript := preload("res://scripts/dungeon/bsp_node.gd")
const AllocatorScript := preload("res://scripts/dungeon/room_type_allocator.gd")
const RoomScene := preload("res://scenes/dungeon/room.tscn")
const CameraTriggerScript := preload("res://scripts/dungeon/camera_trigger.gd")
const StartRoomScene := preload("res://rooms/layer_01/start_room.tscn")
const Layer1TemplateScene := preload("res://rooms/layer_01/normal/layer1_room_template.tscn")

@export var use_room_templates := true

var rng := RandomNumberGenerator.new()
var config: ChapterConfig
var rooms: Array = []                 # Array[RoomData]
var corridor_cells: Dictionary = {}   # Vector2i -> true
var start_room: RoomData
var _start_added := false

var _nav_region: NavigationRegion2D
var _rooms_root: Node2D
var _corridors_root: Node2D

signal generated
signal template_room_cleared(room_type: int)


func _ready() -> void:
	_nav_region = NavigationRegion2D.new()
	add_child(_nav_region)
	_rooms_root = Node2D.new()
	_rooms_root.name = "Rooms"
	_nav_region.add_child(_rooms_root)
	_corridors_root = Node2D.new()
	_corridors_root.name = "Corridors"
	add_child(_corridors_root)


func clear_previous() -> void:
	if _rooms_root:
		for child in _rooms_root.get_children():
			child.queue_free()
	if _corridors_root:
		for child in _corridors_root.get_children():
			child.queue_free()
	rooms.clear()
	corridor_cells.clear()
	start_room = null


func generate(cfg: ChapterConfig, seed_value: int = -1, bake_nav: bool = false, spawn_enemies: bool = true) -> void:
	clear_previous()
	config = cfg
	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value
	if cfg.layer_id == 9:
		_generate_final_layer()
	else:
		_generate_bsp_layer()
	_assign_room_types()
	_compute_door_cells()
	_compute_direct_doors()
	_build_corridor_visuals()
	_spawn_room_instances(spawn_enemies)
	_build_camera_triggers()
	if bake_nav:
		bake_navigation()
	generated.emit()


func start_world_center() -> Vector2:
	if start_room == null:
		return Vector2.ZERO
	return start_room.center_world(LAYOUT_CELL)


func start_usable_rect() -> Rect2:
	if start_room == null:
		return Rect2()
	return _usable_rect(start_room)


static func world_rect_of(r: Rect2i) -> Rect2:
	return Rect2(Vector2(r.position) * LAYOUT_CELL, Vector2(r.size) * LAYOUT_CELL)


func _usable_rect(r: RoomData) -> Rect2:
	var w := world_rect_of(r.rect)
	return w.grow(-WALL_PX)


# ---------------------------------------------------------------------------
# 一、BSP 布局
# ---------------------------------------------------------------------------

func _generate_bsp_layer() -> void:
	var half := config.map_size / 2
	var root := BSPNodeScript.new(Rect2i(Vector2i(-half, -half), Vector2i(config.map_size, config.map_size)))
	_split_recursive(root, root)
	_collect_leaf_rooms(root)
	_ensure_start_room()
	_connect_bsp(root)
	_connect_start_if_added()
	_ensure_min_rooms()


func _split_recursive(node: BSPNode, root: BSPNode) -> void:
	var leaves := _count_leaves(root)
	if leaves >= config.max_rooms - 1:
		return
	var want_more := leaves < config.min_rooms - 1
	if not want_more and rng.randf() > 0.55:
		return
	if node.split(4 if config.layer_id == 1 else 3):
		_split_recursive(node.left, root)
		_split_recursive(node.right, root)


func _count_leaves(node: BSPNode) -> int:
	if node.is_leaf():
		return 1
	return _count_leaves(node.left) + _count_leaves(node.right)


func _collect_leaf_rooms(node: BSPNode) -> void:
	if node.is_leaf():
		_create_leaf_room(node)
	else:
		_collect_leaf_rooms(node.left)
		_collect_leaf_rooms(node.right)


func _create_leaf_room(node: BSPNode) -> void:
	var max_sz: Vector2i
	if config.layer_id == 1:
		# 第一层启用房间模板：普通房统一 2×2
		max_sz = Vector2i(maxi(2, node.rect.size.x - 2), maxi(2, node.rect.size.y - 2))
	else:
		max_sz = Vector2i(
			maxi(1, mini(3, node.rect.size.x - 2)),
			maxi(1, mini(3, node.rect.size.y - 2)),
		)
	var size := Vector2i(
		maxi(1, mini(max_sz.x, rng.randi_range(2 if config.layer_id == 1 else 1, max_sz.x))),
		maxi(1, mini(max_sz.y, rng.randi_range(2 if config.layer_id == 1 else 1, max_sz.y))),
	)
	var hi_x := maxi(1, node.rect.size.x - size.x - 1)
	var hi_y := maxi(1, node.rect.size.y - size.y - 1)
	var pos := Vector2i(
		node.rect.position.x + rng.randi_range(mini(1, hi_x), hi_x),
		node.rect.position.y + rng.randi_range(mini(1, hi_y), hi_y),
	)
	node.room = Rect2i(pos, size)
	rooms.append(RoomDataScript.new(node.room))


## 初始房固定中心 (0,0)：优先使用覆盖原点的 BSP 房间，否则补一间 1×1 并连走廊
func _ensure_start_room() -> void:
	for r in rooms:
		if r.rect.has_point(Vector2i.ZERO):
			r.type = RoomData.RoomType.START
			start_room = r
			return
	var candidates := [Vector2i.ZERO, Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0)]
	for pos in candidates:
		var new_rect := Rect2i(pos, Vector2i.ONE)
		var overlap := false
		for r in rooms:
			if r.rect.intersects(new_rect):
				overlap = true
				break
		if not overlap:
			var room := RoomDataScript.new(new_rect)
			room.type = RoomData.RoomType.START
			rooms.append(room)
			start_room = room
			_start_added = true
			return
	# 兜底：把离原点最近的房间设为初始房
	var nearest: RoomData = null
	var nearest_d := 1 << 30
	for r in rooms:
		var d: int = r.center_cell().length_squared()
		if d < nearest_d:
			nearest_d = d
			nearest = r
	nearest.type = RoomData.RoomType.START
	start_room = nearest


func _connect_bsp(node: BSPNode) -> void:
	if node.left == null or node.right == null:
		return
	var room_a := _get_room(node.left)
	var room_b := _get_room(node.right)
	if room_a != null and room_b != null:
		_create_corridor(room_a, room_b)
		_connect_bsp(node.left)
		_connect_bsp(node.right)


func _get_room(node: BSPNode) -> Rect2i:
	if node.room.size != Vector2i.ZERO:
		return node.room
	var child_rooms: Array = []
	if node.left:
		child_rooms.append(_get_room(node.left))
	if node.right:
		child_rooms.append(_get_room(node.right))
	if child_rooms.is_empty():
		return Rect2i()
	return child_rooms.pick_random()


func _connect_start_if_added() -> void:
	if not _start_added:
		return
	var nearest: RoomData = null
	var nearest_d := 1 << 30
	for r in rooms:
		if r == start_room:
			continue
		var d: int = (r.center_cell() - start_room.center_cell()).length_squared()
		if d < nearest_d:
			nearest_d = d
			nearest = r
	if nearest:
		_create_corridor(start_room.rect, nearest.rect)


## 房间数低于下限时，在现有房间旁补建 1×1 房间（直达门由 _compute_direct_doors 开凿）
func _ensure_min_rooms() -> void:
	var guard := 0
	while rooms.size() < config.min_rooms and guard < 400:
		guard += 1
		var candidates: Array = []
		var half := config.map_size / 2
		for r in rooms:
			for y in range(r.rect.position.y - 1, r.rect.end.y + 1):
				for x in range(r.rect.position.x - 1, r.rect.end.x + 1):
					var cell := Vector2i(x, y)
					if r.rect.has_point(cell):
						continue
					if cell.x < -half or cell.x >= half or cell.y < -half or cell.y >= half:
						continue
					if not _cell_occupied(cell):
						candidates.append(cell)
		if candidates.is_empty():
			break
		var cell: Vector2i = candidates.pick_random()
		rooms.append(RoomDataScript.new(Rect2i(cell, Vector2i.ONE)))


func _cell_occupied(cell: Vector2i) -> bool:
	for r in rooms:
		if r.rect.has_point(cell):
			return true
	return false


## L 形走廊（1 格宽），跳过房间内部格，并记录门洞格
func _create_corridor(a: Rect2i, b: Rect2i) -> void:
	var start := a.get_center()
	var end := b.get_center()
	var horizontal_first := rng.randf() > 0.5
	if horizontal_first:
		_carve_line(Vector2i(start.x, start.y), Vector2i(end.x, start.y))
		_carve_line(Vector2i(end.x, start.y), Vector2i(end.x, end.y))
	else:
		_carve_line(Vector2i(start.x, start.y), Vector2i(start.x, end.y))
		_carve_line(Vector2i(start.x, end.y), Vector2i(end.x, end.y))


func _carve_line(from: Vector2i, to: Vector2i) -> void:
	var cell := from
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	while cell != to:
		_carve_cell(cell)
		cell += step
	_carve_cell(to)


func _carve_cell(cell: Vector2i) -> void:
	for r in rooms:
		if r.rect.has_point(cell):
			return
	if not corridor_cells.has(cell):
		corridor_cells[cell] = true


func _assign_room_types() -> void:
	if config.layer_id == 9:
		return
	var allocator = AllocatorScript.new()
	allocator.allocate(rooms, config)


## 门洞格：走廊格与房间边界相邻的位置（自动开洞）
func _compute_door_cells() -> void:
	for r in rooms:
		r.door_cells.clear()
	for cell in corridor_cells:
		for r in rooms:
			if not r.rect.has_point(cell) and r.rect.grow(1).has_point(cell):
				r.door_cells.append(cell)


## 相邻房间（共享边界）之间补直达门洞：适用于第 9 层线性链等无走廊场景
func _compute_direct_doors() -> void:
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var a: RoomData = rooms[i]
			var b: RoomData = rooms[j]
			var pair := _shared_edge_door_cells(a.rect, b.rect)
			if pair.is_empty():
				continue
			if not a.door_cells.has(pair[0]):
				a.door_cells.append(pair[0])
			if not b.door_cells.has(pair[1]):
				b.door_cells.append(pair[1])


func _shared_edge_door_cells(a: Rect2i, b: Rect2i) -> Array:
	# 左右相邻
	if a.end.x == b.position.x and _y_overlap(a, b):
		var y := (maxi(a.position.y, b.position.y) + mini(a.end.y, b.end.y)) / 2
		return [Vector2i(a.end.x, y), Vector2i(b.position.x - 1, y)]
	if b.end.x == a.position.x and _y_overlap(a, b):
		var y := (maxi(a.position.y, b.position.y) + mini(a.end.y, b.end.y)) / 2
		return [Vector2i(b.end.x, y), Vector2i(a.position.x - 1, y)]
	# 上下相邻
	if a.end.y == b.position.y and _x_overlap(a, b):
		var x := (maxi(a.position.x, b.position.x) + mini(a.end.x, b.end.x)) / 2
		return [Vector2i(x, a.end.y), Vector2i(x, b.position.y - 1)]
	if b.end.y == a.position.y and _x_overlap(a, b):
		var x := (maxi(a.position.x, b.position.x) + mini(a.end.x, b.end.x)) / 2
		return [Vector2i(x, b.end.y), Vector2i(x, a.position.y - 1)]
	return []


func _y_overlap(a: Rect2i, b: Rect2i) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y


func _x_overlap(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x


# ---------------------------------------------------------------------------
# 二、第 9 层（隐藏层）：线性 5 房，无探索
# ---------------------------------------------------------------------------

func _generate_final_layer() -> void:
	var chain := [
		[RoomData.RoomType.START, Vector2i(0, 0)],
		[RoomData.RoomType.EVENT, Vector2i(1, 0)],
		[RoomData.RoomType.BOSS, Vector2i(2, 0)],
		[RoomData.RoomType.BOSS, Vector2i(3, 0)],
		[RoomData.RoomType.BOSS, Vector2i(4, 0)],
	]
	for item in chain:
		var room := RoomDataScript.new(Rect2i(item[1], Vector2i.ONE))
		room.type = item[0]
		rooms.append(room)
		if room.type == RoomData.RoomType.START:
			start_room = room
	for i in range(rooms.size() - 1):
		_create_corridor(rooms[i].rect, rooms[i + 1].rect)
	_assign_room_types()


# ---------------------------------------------------------------------------
# 三、物理生成：走廊地面 / 房间实例（地板、墙、门洞、触发器、怪物）
# ---------------------------------------------------------------------------

func _build_corridor_visuals() -> void:
	for cell in corridor_cells:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(LAYOUT_CELL.x, 0),
			Vector2(LAYOUT_CELL.x, LAYOUT_CELL.y), Vector2(0, LAYOUT_CELL.y),
		])
		poly.color = config.corridor_color
		poly.position = Vector2(cell) * LAYOUT_CELL
		_corridors_root.add_child(poly)


func _spawn_room_instances(spawn_enemies: bool) -> void:
	for r in rooms:
		if _use_template_for(r):
			_spawn_template_room(r, spawn_enemies)
			continue
		var room = RoomScene.instantiate()
		room.position = world_rect_of(r.rect).position
		room.initialize(r, config, _usable_rect(r))
		_rooms_root.add_child(room)
		if spawn_enemies:
			_spawn_enemies(r, _usable_rect(r))


## 第一层：初始房 / 普通房 / 精英房使用房间模板（2×2 布局）
func _use_template_for(r: RoomData) -> bool:
	if not use_room_templates:
		return false
	if r.type == RoomData.RoomType.START:
		return config.layer_id == 1
	return r.type == RoomData.RoomType.NORMAL or r.type == RoomData.RoomType.ELITE \
		or r.type == RoomData.RoomType.BOSS


func _spawn_template_room(r: RoomData, spawn_enemies: bool) -> void:
	var room = StartRoomScene.instantiate() if r.type == RoomData.RoomType.START else Layer1TemplateScene.instantiate()
	room.position = world_rect_of(r.rect).position
	room.room_width = r.rect.size.x * 20
	room.room_height = r.rect.size.y * 12
	# 按走廊入口写入动态门洞（瓦片坐标）
	var openings: Array = []
	for cell in r.door_cells:
		var side := ""
		var center := 0.0
		if cell.x == r.rect.end.x:
			side = "east"
			center = (float(cell.y - r.rect.position.y) + 0.5) * 12.0
		elif cell.x == r.rect.position.x - 1:
			side = "west"
			center = (float(cell.y - r.rect.position.y) + 0.5) * 12.0
		elif cell.y == r.rect.end.y:
			side = "south"
			center = (float(cell.x - r.rect.position.x) + 0.5) * 20.0
		elif cell.y == r.rect.position.y - 1:
			side = "north"
			center = (float(cell.x - r.rect.position.x) + 0.5) * 20.0
		if side != "":
			openings.append({"side": side, "center": center})
	room.door_openings = openings
	if spawn_enemies and (r.type == RoomData.RoomType.NORMAL or r.type == RoomData.RoomType.ELITE or r.type == RoomData.RoomType.BOSS):
		var chaser = load("res://scenes/dungeon/chaser_enemy.tscn")
		var pool: Array[PackedScene] = [chaser as PackedScene]
		room.set_enemy_pool(pool)
		if r.type == RoomData.RoomType.BOSS:
			room.room_kind_override = RoomBase.RoomType.BOSS
			room.template_type = 0
			room.min_enemies = 4
			room.max_enemies = 6
		elif r.type == RoomData.RoomType.ELITE:
			room.elite_override = true
			room.template_type = 4 + rng.randi_range(1, 5)  # T05~T09 障碍型
			room.min_enemies = 4
			room.max_enemies = 6
		else:
			room.template_type = rng.randi_range(0, 9)
			room.min_enemies = 3
			room.max_enemies = 5
	_rooms_root.add_child(room)
	room.room_cleared.connect(_on_template_room_cleared.bind(r.type))
	room.exit_requested.connect(_on_room_exit_requested)
	# 门锁（战斗锁门 / 清怪开门）
	for opening in openings:
		var door := _make_template_door(room, opening)
		if door != null:
			_connect_door_target(room, door, r)
			room.doors_root.add_child(door)
			door.used.connect(room._on_door_used)


func _on_template_room_cleared(_room: RoomBase, room_type: int) -> void:
	template_room_cleared.emit(room_type)


## 把门与相邻房间数据绑定：玩家使用门时传送到目标房间
func _connect_door_target(room, door: RoomDoor, r: RoomData) -> void:
	var neighbor_cell := r.rect.position
	match door.direction:
		RoomDoor.Direction.NORTH:
			neighbor_cell = Vector2i(r.rect.position.x, r.rect.position.y - 1)
		RoomDoor.Direction.SOUTH:
			neighbor_cell = Vector2i(r.rect.position.x, r.rect.end.y)
		RoomDoor.Direction.EAST:
			neighbor_cell = Vector2i(r.rect.end.x, r.rect.position.y)
		RoomDoor.Direction.WEST:
			neighbor_cell = Vector2i(r.rect.position.x - 1, r.rect.position.y)
	for other in rooms:
		if other.rect.has_point(neighbor_cell):
			door.target_room_data = other
			return
	# 兜底：按门方向找最近的房间（处理走廊末端等非相邻情况）
	var door_world: Vector2 = door.global_position
	var best: RoomData = null
	var best_d := INF
	for other in rooms:
		if other == r:
			continue
		var center: Vector2 = other.center_world(LAYOUT_CELL)
		var d: float = center.distance_squared_to(door_world)
		if d < best_d:
			best_d = d
			best = other
	door.target_room_data = best


## 玩家使用门：把玩家传送进目标房间（门内安全点），并切换镜头
func _on_room_exit_requested(room: RoomBase, door: RoomDoor) -> void:
	var target: RoomData = door.target_room_data
	if target == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var target_node := _room_node_of(target)
	if target_node == null:
		return
	var spawn := Vector2.ZERO
	if target_node.has_method("get_player_spawn_position"):
		spawn = target_node.get_player_spawn_position()
	if spawn == Vector2.ZERO:
		spawn = _usable_rect(target).get_center()
	player.global_position = spawn
	var camera := _find_room_camera()
	if camera:
		camera.switch_to_room(_usable_rect(target))
	EventBus.message.emit("进入 %s" % target.type_name())


func _room_node_of(r: RoomData) -> Node2D:
	if _rooms_root == null:
		return null
	var expected := world_rect_of(r.rect).position
	for child in _rooms_root.get_children():
		if child is Node2D and (child as Node2D).position.is_equal_approx(expected):
			return child as Node2D
	return null


func _make_template_door(room, opening: Dictionary) -> RoomDoor:
	var side: String = opening.get("side", "north")
	var center: float = opening.get("center", 0.0)
	var door := RoomDoor.new()
	var tiles_w: float = float(room.room_width) * 64.0
	var tiles_h: float = float(room.room_height) * 64.0
	match side:
		"north":
			door.direction = RoomDoor.Direction.NORTH
			door.position = Vector2(center * 64.0, 64.0)
		"south":
			door.direction = RoomDoor.Direction.SOUTH
			door.position = Vector2(center * 64.0, tiles_h - 64.0)
		"east":
			door.direction = RoomDoor.Direction.EAST
			door.position = Vector2(tiles_w - 64.0, center * 64.0)
		"west":
			door.direction = RoomDoor.Direction.WEST
			door.position = Vector2(64.0, center * 64.0)
	return door


func _spawn_enemies(r: RoomData, usable: Rect2) -> void:
	match r.type:
		RoomData.RoomType.NORMAL:
			_spawn_chasers(usable, 2)
		RoomData.RoomType.ELITE:
			_spawn_chasers(usable, 3)
		RoomData.RoomType.START:
			var dummy = load("res://scenes/enemies/dummy_enemy.tscn").instantiate()
			dummy.position = usable.get_center() + Vector2(0, 160)
			_rooms_root.add_child(dummy)


func _spawn_chasers(usable: Rect2, count: int) -> void:
	for i in count:
		var enemy = load("res://scenes/dungeon/chaser_enemy.tscn").instantiate()
		var margin := 80.0
		enemy.position = Vector2(
			rng.randf_range(usable.position.x + margin, usable.end.x - margin),
			rng.randf_range(usable.position.y + margin, usable.end.y - margin),
		)
		_rooms_root.add_child(enemy)


func _build_camera_triggers() -> void:
	for r in rooms:
		var trigger: CameraTrigger = CameraTriggerScript.new()
		trigger.setup(_usable_rect(r))
		trigger.player_entered.connect(_on_player_entered)
		_rooms_root.add_child(trigger)
	for cell in corridor_cells:
		var trigger: CameraTrigger = CameraTriggerScript.new()
		trigger.setup(Rect2(Vector2(cell) * LAYOUT_CELL, LAYOUT_CELL))
		trigger.player_entered.connect(_on_player_entered)
		_corridors_root.add_child(trigger)


func _on_player_entered(rect: Rect2) -> void:
	var camera := _find_room_camera()
	if camera:
		camera.switch_to_room(rect)


func _find_room_camera() -> RoomCamera:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("Camera2D") as RoomCamera


# ---------------------------------------------------------------------------
# 四、寻路烘焙（NavigationServer2D）
# ---------------------------------------------------------------------------

## 构建寻路网格：按房间可用区 + 门洞桥接 + 走廊地面手工构建（确定性，不依赖碰撞解析）
func bake_navigation() -> void:
	if _nav_region == null:
		return
	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = 24.0
	var verts := PackedVector2Array()
	var polys: Array = []
	var added := {}
	for r in rooms:
		_add_nav_rect(nav_poly, verts, polys, added, _usable_rect(r))
		for dc in r.door_cells:
			var bridge := _door_bridge_rect(r, dc)
			if bridge != null:
				_add_nav_rect(nav_poly, verts, polys, added, bridge)
	for cell in corridor_cells:
		_add_nav_rect(nav_poly, verts, polys, added, Rect2(Vector2(cell) * LAYOUT_CELL, LAYOUT_CELL))
	nav_poly.vertices = verts
	for p in polys:
		nav_poly.add_polygon(p)
	_nav_region.navigation_polygon = nav_poly
	print("导航网格构建完成：%d 个房间，%d 个多边形" % [rooms.size(), polys.size()])


func _add_nav_rect(nav_poly: NavigationPolygon, verts: PackedVector2Array, polys: Array, added: Dictionary, rect: Rect2) -> void:
	var key := "%d_%d_%d_%d" % [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]
	if added.has(key):
		return
	added[key] = true
	var base := verts.size() / 2
	verts.append(rect.position)
	verts.append(rect.position + Vector2(rect.size.x, 0))
	verts.append(rect.end)
	verts.append(rect.position + Vector2(0, rect.size.y))
	polys.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))


## 门洞桥接矩形：连接房间可用区与走廊地面（填充 2 瓦片墙厚间隙）
func _door_bridge_rect(r: RoomData, dc: Vector2i) -> Rect2:
	var world := world_rect_of(r.rect)
	var usable := world.grow(-WALL_PX)
	if dc.x == r.rect.end.x:
		return Rect2(usable.end.x, (dc.y + 0.5) * LAYOUT_CELL.y - DOOR_HALF_WIDTH, WALL_PX, DOOR_HALF_WIDTH * 2.0)
	if dc.x == r.rect.position.x - 1:
		return Rect2(usable.position.x - WALL_PX, (dc.y + 0.5) * LAYOUT_CELL.y - DOOR_HALF_WIDTH, WALL_PX, DOOR_HALF_WIDTH * 2.0)
	if dc.y == r.rect.end.y:
		return Rect2((dc.x + 0.5) * LAYOUT_CELL.x - DOOR_HALF_WIDTH, usable.end.y, DOOR_HALF_WIDTH * 2.0, WALL_PX)
	if dc.y == r.rect.position.y - 1:
		return Rect2((dc.x + 0.5) * LAYOUT_CELL.x - DOOR_HALF_WIDTH, usable.position.y - WALL_PX, DOOR_HALF_WIDTH * 2.0, WALL_PX)
	return Rect2()
