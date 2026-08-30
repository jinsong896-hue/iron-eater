extends Node
## 完整一层流程集成测试（场景模式，autoload 可用）
## 开局 → 切到 Boss 房 → 杀 Boss → 触传送门 → 下一层
## 运行：godot --headless --path E:\unity --scene res://tests/test_floor_flow.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("FLOOR FLOW TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame

	# main.tscn 根节点即 GameRoot（场景实例名为 MainScene）
	var game_root := get_tree().current_scene.get_node_or_null("MainScene") as Node
	if game_root == null and get_tree().current_scene.name == "GameRoot":
		game_root = get_tree().current_scene
	_check(game_root != null and game_root.has_method("next_floor"), "GameRoot 就绪")

	if game_root == null or not game_root.has_method("next_floor"):
		_finish()
		return

	# 等地牢生成（call_deferred）
	await get_tree().process_frame
	await get_tree().process_frame

	_check(int(GameManager.run_info.get("floor", 1)) == 1, "初始为第 1 层")

	# 找 boss 房
	var graph: Array = game_root.get("dungeon_graph")
	var boss_idx := -1
	for i in graph.size():
		if str(graph[i].get("type", "")) == "boss":
			boss_idx = i
			break
	_check(boss_idx >= 0, "地牢含 Boss 房")

	if boss_idx >= 0:
		# 切到 Boss 房
		game_root.call("_transition_to_room", boss_idx)
		await get_tree().process_frame
		await get_tree().process_frame

		var room_node: Node = game_root.get("current_room_node")
		var controller = room_node.get_node_or_null("RoomController") if room_node else null
		_check(controller != null and controller.is_boss_room, "进入 Boss 房")
		_check(controller.enemies_alive == 1, "Boss 已刷出")

		# 杀 Boss
		var boss = controller.get("_boss")
		if boss:
			boss.take_damage(999999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(controller.is_cleared, "Boss 死后房间清空")
		_check(GameManager.boss_kills == 1, "boss_kills 计数 +1")

		# 触传送门 → 下一层
		var portal = controller.get("_portal")
		_check(portal != null and is_instance_valid(portal), "传送门已生成")
		if portal:
			var floor_before := int(GameManager.run_info.get("floor", 1))
			portal.body_entered.emit(game_root.get("player"))
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var floor_after := int(GameManager.run_info.get("floor", 1))
			_check(floor_after == floor_before + 1, "层数 +1")
			var new_room: Node = game_root.get("current_room_node")
			_check(new_room != null, "下一层房间已加载")

	_finish()


## 结束判定
func _finish() -> void:
	if failed == 0:
		print("ALL FLOOR FLOW TESTS PASSED")
		get_tree().quit(0)
	else:
		print("FLOOR FLOW TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 断言
func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
