extends SceneTree
## 房间系统测试：《房间生成.md》——瓦片集、初始房、模板布局、门洞、战斗锁门/清怪开门

const StartRoomScene := preload("res://rooms/layer_01/start_room.tscn")
const TemplateScene := preload("res://rooms/layer_01/normal/layer1_room_template.tscn")
const DoorScene := preload("res://rooms/base/room_door.tscn")
const DummyEnemy := preload("res://tests/test_dummy_enemy.tscn")

var failed := 0


func _init() -> void:
	await _test_tileset()
	await _test_start_room()
	await _test_template_layout()
	await _test_door_carving()
	await _test_encounter_lifecycle()
	if failed == 0:
		print("ALL ROOM TESTS PASSED")
		quit(0)
	else:
		print("ROOM TESTS FAILED: %d" % failed)
		quit(1)


func _test_tileset() -> void:
	var ts := TilesetFactory.get_tileset()
	_check(ts != null and ts.tile_size == Vector2i(64, 64), "瓦片集构建（64×64）")
	var atlas: TileSetAtlasSource = ts.get_source(0)
	_check(atlas != null and atlas.has_tile(TilesetFactory.TILE_FLOOR_A), "地板瓦片存在")
	_check(atlas != null and atlas.has_tile(TilesetFactory.TILE_WALL), "墙壁瓦片存在")
	_check(atlas != null and atlas.has_tile(TilesetFactory.TILE_GRASS[0]), "草地瓦片存在")
	var wall_td := atlas.get_tile_data(TilesetFactory.TILE_WALL, 0)
	_check(wall_td.get_collision_polygons_count(0) == 1, "墙壁瓦片带碰撞")
	await process_frame


func _test_start_room() -> void:
	var room = StartRoomScene.instantiate()
	root.add_child(room)
	await process_frame
	_check(room.cleared, "初始房默认已清理")
	_check(room.ground.get_used_cells().size() >= 20 * 12 - 10, "初始房地砖铺满")
	_check(room.walls.get_used_cells().size() >= 30, "初始房有墙")
	_check(room.grass.get_used_cells().size() > 0, "初始房有草")
	_check(room.get_node_or_null("CenterLight") != null, "初始房中央灯光")
	# 默认南北门洞：北墙中央 3 格被挖空
	var north_open := true
	for x in range(9, 12):
		if room.walls.get_cell_source_id(Vector2i(x, 0)) != -1:
			north_open = false
	_check(north_open, "初始房北门开凿")
	room.queue_free()
	await process_frame


func _test_template_layout() -> void:
	for t in 10:
		var room = TemplateScene.instantiate()
		room.template_type = t
		room.room_width = 40
		room.room_height = 24
		root.add_child(room)
		await process_frame
		var floors: int = room.ground.get_used_cells().size()
		_check(floors >= 40 * 24 - 10, "模板 T%02d 地板铺满" % (t + 1))
		_check(room.enemy_spawn_cells.size() >= 4, "模板 T%02d 有出生点" % (t + 1))
		_check(room.spawn_points.get_child_count() >= 4, "模板 T%02d AutoSpawn 标记" % (t + 1))
		room.queue_free()
		await process_frame


func _test_door_carving() -> void:
	var room = TemplateScene.instantiate()
	room.room_width = 40
	room.room_height = 24
	room.door_openings = [
		{"side": "east", "center": 12.0},
		{"side": "west", "center": 12.0},
	]
	root.add_child(room)
	await process_frame
	var east_open := true
	for y in range(11, 14):
		if room.walls.get_cell_source_id(Vector2i(39, y)) != -1:
			east_open = false
	_check(east_open, "动态东门开凿")
	var west_open := true
	for y in range(11, 14):
		if room.walls.get_cell_source_id(Vector2i(0, y)) != -1:
			west_open = false
	_check(west_open, "动态西门开凿")
	room.queue_free()
	await process_frame


func _test_encounter_lifecycle() -> void:
	var room = TemplateScene.instantiate()
	room.room_width = 40
	room.room_height = 24
	var pool: Array[PackedScene] = [DummyEnemy]
	room.set_enemy_pool(pool)
	room.min_enemies = 3
	room.max_enemies = 5
	root.add_child(room)
	await process_frame
	# 加两扇门
	for side in ["north", "south"]:
		var door = DoorScene.instantiate()
		door.direction = RoomDoor.Direction.NORTH if side == "north" else RoomDoor.Direction.SOUTH
		door.position = Vector2(1280, 64) if side == "north" else Vector2(1280, 1536 - 64)
		room.doors_root.add_child(door)
	await process_frame
	_check(not room.cleared, "普通房未清理")
	room.start_encounter()
	await process_frame
	var enemies: int = room.active_enemy_ids.size()
	_check(enemies >= 3 and enemies <= 5, "进入战斗生成 3~5 怪（%d）" % enemies)
	var locked := true
	for node in room.doors_root.get_children():
		if node is RoomDoor and not node.locked:
			locked = false
	_check(locked, "战斗期间门锁定")
	# 击杀全部敌人
	for node in room.enemy_container.get_children():
		node.queue_free()
	await process_frame
	await process_frame
	_check(room.cleared, "清怪后房间完成")
	var unlocked := true
	for node in room.doors_root.get_children():
		if node is RoomDoor and node.locked:
			unlocked = false
	_check(unlocked, "完成后门解锁")
	room.queue_free()
	await process_frame


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
