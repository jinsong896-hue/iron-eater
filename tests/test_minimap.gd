extends Node
## 回归测试：小地图数据链路（连接图 / 探索记录 / 当前房间 / 传送更新）
## 运行：godot --headless --path E:\unity --scene res://tests/test_minimap.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 20.0
	guard.timeout.connect(func():
		print("MINIMAP TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()
	# 固定种子，避免随机地牢导致断言偶发（种子会经 GameState.run_info 传给 DungeonManager）
	GameState.run_info["seed"] = 20260812
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var gen = scene.get_node("DungeonManager/DungeonGenerator")
	var player = scene.get_node("Player")
	_check(gen.room_connections.size() > 0, "房间连接图已建立（%d 个房间）" % gen.room_connections.size())
	_check(gen.explored_rooms.has(gen.current_room_coord), "初始房间已标记为探索")
	_check(gen.current_room_coord == gen.start_room.room_coord, "当前房间为初始房")
	var door = null
	for child in gen._rooms_root.get_children():
		if child.name == "StartRoom01":
			for d in child.doors_root.get_children():
				if d.get("target_room_data") != null:
					door = d
					break
		if door:
			break
	if door:
		player.global_position = door.global_position
		await get_tree().create_timer(1.0).timeout
		var target_coord: Vector2i = door.target_room_data.room_coord
		_check(gen.current_room_coord == target_coord, "传送后当前房间更新为 %s" % target_coord)
		_check(gen.explored_rooms.has(target_coord), "新房间已标记为探索")
	else:
		print("  [SKIP] 初始房没有带目标的门")
	if failed == 0:
		print("ALL MINIMAP TESTS PASSED")
		get_tree().quit(0)
	else:
		print("MINIMAP TESTS FAILED: %d" % failed)
		get_tree().quit(1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
