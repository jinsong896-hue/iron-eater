extends Node
## 回归测试：走出当前房间 → 传送进入相邻房间 → 刷怪无物理崩溃
## 运行：godot --headless --path E:\unity --scene res://tests/test_room_transition.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 25.0
	guard.timeout.connect(func():
		print("ROOM TRANSITION TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var gen = scene.get_node("DungeonManager/DungeonGenerator")
	var player = scene.get_node("Player")
	var rooms_root = gen._rooms_root

	# 找一个门（任意房间，优先初始房）并验证有目标房间
	var door = null
	var start_node = null
	for child in rooms_root.get_children():
		if child.name == "StartRoom01":
			start_node = child
			break
	if start_node == null:
		for child in rooms_root.get_children():
			if child.has_method("get_player_spawn_position"):
				start_node = child
				break
	if start_node:
		for d in start_node.doors_root.get_children():
			if d.get("target_room_data") != null:
				door = d
				break
	_check(door != null, "找到带目标房间的门")
	if door == null:
		_finish()
		return
	var target: RoomData = door.target_room_data
	var target_node = gen._room_node_of(target)
	_check(target_node != null, "目标房间节点存在")

	# 把玩家放到门前，模拟走进门
	player.global_position = door.global_position
	await get_tree().create_timer(1.0).timeout
	var after_walk: Vector2 = player.global_position
	var spawned := false
	var expected_spawn: Vector2 = gen._usable_rect(target).get_center()
	if target_node != null and target_node.has_method("get_player_spawn_position"):
		expected_spawn = target_node.get_player_spawn_position()
		_check(after_walk.distance_to(expected_spawn) < 50.0,
			"走进门后传送进目标房间（距离 %.0f）" % after_walk.distance_to(expected_spawn))
		_check(target_node.encounter_active or target_node.cleared, "目标房间战斗状态已启动")
		spawned = target_node.enemy_container != null and target_node.enemy_container.get_child_count() > 0
		_check(spawned, "目标房间已刷出敌人")
	else:
		_check(after_walk.distance_to(expected_spawn) < 200.0,
			"走进门后传送进目标房间可用区")
	# 等 1 秒确认无物理报错导致的崩溃（进程能继续运行本身就是验证）
	await get_tree().create_timer(1.0).timeout
	print("玩家仍存活：", player.visible and player.global_position != Vector2.ZERO)
	_finish()


func _finish() -> void:
	if failed == 0:
		print("ALL ROOM TRANSITION TESTS PASSED")
		get_tree().quit(0)
	else:
		print("ROOM TRANSITION TESTS FAILED: %d" % failed)
		get_tree().quit(1)


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
