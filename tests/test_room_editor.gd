extends SceneTree
## 房间编辑器保存/加载往返测试

const EditorScene := preload("res://rooms/editor/room_editor.tscn")

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
	var room = EditorScene.instantiate()
	root.add_child(room)
	await process_frame

	# 1. 填充地板
	room.fill_floor()
	await process_frame
	var floor_layer: TileMapLayer = room._find_layer("floor")
	var before_count := floor_layer.get_used_cells().size()
	_check(before_count == 192, "填充16×12地板后应有192格（实际%d）" % before_count)

	# 2. 保存
	room.save_room("__test_room", 1, 3, 5)
	await process_frame

	# 3. 检查文件
	var path := "res://rooms/editor/saved/__test_room.tres"
	var exists := FileAccess.file_exists(path)
	_check(exists, "保存后文件存在")
	var data: Resource = load(path)
	_check(data != null, "文件可加载")
	var floor_dict: Dictionary = data.call("get_floor_dict")
	_check(floor_dict.size() == 192, "保存后地板数据应192格（实际%d）" % floor_dict.size())

	# 4. 清空后加载
	room.clear_all()
	await process_frame
	var after_clear := floor_layer.get_used_cells().size()
	_check(after_clear == 0, "清空后应0格（实际%d）" % after_clear)

	room.load_room("__test_room")
	await process_frame
	var after_load := floor_layer.get_used_cells().size()
	_check(after_load == 192, "加载后应192格（实际%d）" % after_load)

	# 5. 清理测试文件
	DirAccess.remove_absolute(path)
	room.queue_free()


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
