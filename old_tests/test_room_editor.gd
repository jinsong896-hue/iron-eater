extends SceneTree
## 房间编辑器保存/加载往返测试 —— 直接测试核心逻辑

const DataScript := preload("res://scripts/editor/room_editor_data.gd")
const TILE_FLOOR_A := Vector2i(33, 4)
const TILE_FLOOR_B := Vector2i(12, 0)
const TILE_WALL := Vector2i(36, 1)

var failed := 0


func _init() -> void:
	await _test_save_load_roundtrip()
	if failed == 0:
		print("ALL EDITOR TESTS PASSED")
		quit(0)
	else:
		print("EDITOR TESTS FAILED: %d" % failed)
		quit(1)


func _test_save_load_roundtrip() -> void:
	# 创建模拟场景
	var root := Node2D.new()
	root.name = "RoomEditor"
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "FloorLayer"
	floor_layer.tile_set = TilesetFactory.get_tileset()
	root.add_child(floor_layer)
	var wall_layer := TileMapLayer.new()
	wall_layer.name = "WallLayer"
	wall_layer.tile_set = TilesetFactory.get_tileset()
	root.add_child(wall_layer)
	var detail_layer := TileMapLayer.new()
	detail_layer.name = "DetailLayer"
	detail_layer.tile_set = TilesetFactory.get_tileset()
	root.add_child(detail_layer)
	self.root.add_child(root)
	await process_frame

	# 1. 填充地板 16×12
	for x in 16:
		for y in 12:
			var alt := TILE_FLOOR_A if (x * 7 + y * 13) % 9 != 0 else TILE_FLOOR_B
			floor_layer.set_cell(Vector2i(x, y), 0, alt)
	# 画一些墙
	for x in 16:
		wall_layer.set_cell(Vector2i(x, 0), 0, TILE_WALL)
		wall_layer.set_cell(Vector2i(x, 11), 0, TILE_WALL)
	await process_frame

	var floor_count := floor_layer.get_used_cells().size()
	var wall_count := wall_layer.get_used_cells().size()
	_check(floor_count == 192, "地板应有192格（实际%d）" % floor_count)
	_check(wall_count == 32, "墙壁应有32格（实际%d）" % wall_count)

	# 2. 收集并保存
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", "__test")
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.call("set_floor_from_dict", _collect(floor_layer))
	data.call("set_wall_from_dict", _collect(wall_layer))
	data.call("set_detail_from_dict", _collect(detail_layer))
	var path := "res://rooms/editor/saved/__test.tres"
	ResourceSaver.save(data, path)
	await process_frame

	# 3. 验证文件
	var loaded: Resource = load(path)
	_check(loaded != null, "文件可加载")
	var loaded_floor: Dictionary = loaded.call("get_floor_dict")
	var loaded_wall: Dictionary = loaded.call("get_wall_dict")
	_check(loaded_floor.size() == 192, "保存后地板应为192格（实际%d）" % loaded_floor.size())
	_check(loaded_wall.size() == 32, "保存后墙壁应为32格（实际%d）" % loaded_wall.size())

	# 4. 清空后加载还原
	floor_layer.clear()
	wall_layer.clear()
	_check(floor_layer.get_used_cells().size() == 0, "清空后地板应为0格")
	_check(wall_layer.get_used_cells().size() == 0, "清空后墙壁应为0格")

	for cell in loaded_floor:
		floor_layer.set_cell(cell, 0, loaded_floor[cell])
	for cell in loaded_wall:
		wall_layer.set_cell(cell, 0, loaded_wall[cell])
	_check(floor_layer.get_used_cells().size() == 192, "加载后地板应为192格（实际%d）" % floor_layer.get_used_cells().size())
	_check(wall_layer.get_used_cells().size() == 32, "加载后墙壁应为32格（实际%d）" % wall_layer.get_used_cells().size())

	# 清理
	DirAccess.remove_absolute(path)


func _collect(layer: TileMapLayer) -> Dictionary:
	var d := {}
	for cell in layer.get_used_cells():
		d[cell] = layer.get_cell_atlas_coords(cell)
	return d


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
