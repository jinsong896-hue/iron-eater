extends SceneTree

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")
const TILE_FLOOR_A := Vector2i(33, 4)
const TILE_FLOOR_B := Vector2i(12, 0)
const TILE_WALL := Vector2i(36, 1)

var f := 0


func _init() -> void:
	await _test_roundtrip()
	if f == 0:
		print("ALL FLOW TESTS PASSED")
		quit(0)
	else:
		print("FLOW TESTS FAILED: %d" % f)
		quit(1)


func _test_roundtrip() -> void:
	# 模拟编辑器操作
	var room := Node2D.new()
	room.name = "RoomEditor"
	var floor := TileMapLayer.new(); floor.name = "FloorLayer"
	var wall := TileMapLayer.new(); wall.name = "WallLayer"
	var doors := Node2D.new(); doors.name = "DoorMarkers"
	room.add_child(floor); room.add_child(wall); room.add_child(doors)
	self.root.add_child(room)
	await process_frame

	# 1. 填充地板
	for x in 16:
		for y in 12:
			floor.set_cell(Vector2i(x, y), 0, TILE_FLOOR_A)
	_chk(floor.get_used_cells().size() == 192, "填充 192格")

	# 2. 画墙
	for x in 16:
		wall.set_cell(Vector2i(x, 0), 0, TILE_WALL)
	_chk(wall.get_used_cells().size() > 0, "墙存在")

	# 3. 保存（模拟 _on_save_pressed）
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", "test_flow")
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.set("room_type", 1)
	data.set("min_enemies", 3)
	data.set("max_enemies", 5)
	for prefix in ["floor", "wall"]:
		var layer: TileMapLayer = floor if prefix == "floor" else wall
		var cells: Array[Vector2i] = []; var atlases: Array[Vector2i] = []; var sources: Array = []
		for cell in layer.get_used_cells():
			cells.append(cell); atlases.append(layer.get_cell_atlas_coords(cell)); sources.append(0)
		data.set(prefix + "_cells", cells); data.set(prefix + "_atlas", atlases); data.set(prefix + "_sources", sources)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/test_flow.tres"
	ResourceSaver.save(data, path)
	_chk(FileAccess.file_exists(path), "文件存在")

	# 4. 加载
	var loaded: Resource = load(path)
	_chk(loaded != null, "加载成功")
	_chk(loaded.get("room_name") == "test_flow", "名称正确")
	var fc: Array = loaded.get("floor_cells")
	_chk(fc.size() == 192, "加载后地板 192格(实际%d)" % fc.size())

	# 5. 清空再还原
	floor.clear(); wall.clear()
	_chk(floor.get_used_cells().size() == 0, "清空 0格")
	var lc: Array = loaded.get("floor_cells"); var la: Array = loaded.get("floor_atlas"); var ls: Array = loaded.get("floor_sources")
	for i in lc.size(): floor.set_cell(lc[i], ls[i] if i < ls.size() else 0, la[i])
	_chk(floor.get_used_cells().size() == 192, "还原 192格")

	# 清理
	DirAccess.remove_absolute(path)
	room.queue_free()


func _chk(cond: bool, msg: String) -> void:
	if cond: print("  [OK] %s" % msg)
	else: print("  [FAIL] %s" % msg); f += 1
