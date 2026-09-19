extends Node
## 真实物理穿门 + 小地图数据链路集成测试
## 验证：Area3D 信号真实触发（非直接调用）、房间切换、小地图更新
## 运行：godot --headless --path E:\unity --scene res://tests/test_door_physics.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("DOOR PHYSICS TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene/GameRoot")
	if gr == null:
		_check(false, "GameRoot 就绪")
		_finish()
		return

	# --- 小地图初始数据 ---
	var hud = get_tree().current_scene.find_child("HUD", true, false)
	# HUD 是实例化场景，其根节点名带 @（如 @HUD@2），故按节点名找不稳；
	# 改走 hud.gd 暴露的 minimap 引用（@onready 已解析）
	var minimap = hud.get("minimap") if hud else null
	_check(minimap != null, "小地图组件就绪")
	if minimap:
		_check(minimap.dungeon_graph.size() > 0, "小地图拉到地牢图谱",
			str(minimap.dungeon_graph.size()))
		_check(minimap.current_position == Vector2i.ZERO, "初始房坐标 (0,0)")

	# --- 清怪开门（真实流程）---
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl.enemies_alive > 0:
		# 杀光敌人（节点式 + 群体单位，走产品死亡路径）
		ctrl.debug_kill_all_enemies()
		await get_tree().process_frame
		await get_tree().process_frame

	# --- 真实物理穿门（Area3D 信号链）---
	var door = ctrl._doors[0]
	var trig = door.get_node_or_null("DoorTrigger")
	var player = gr.find_child("Player", true, false)
	var room_before: int = gr.current_room_index
	var map_before: Vector2i = minimap.current_position if minimap else Vector2i.ZERO

	player.global_position = trig.global_position + Vector3(0, 0, 1.0)
	for i in range(30):
		await get_tree().physics_frame

	_check(gr.current_room_index != room_before, "真实物理穿门触发房间切换")
	if minimap:
		minimap.notify_room_changed()
		_check(minimap.current_position != map_before, "小地图当前房间更新")
		_check(minimap.explored_rooms.size() >= 2, "已探索房间 ≥2")

	_finish()


func _check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s %s" % [name, extra])
		failed += 1


func _finish() -> void:
	if failed == 0:
		print("ALL DOOR PHYSICS TESTS PASSED")
		get_tree().quit(0)
	else:
		print("DOOR PHYSICS TESTS FAILED: %d" % failed)
		get_tree().quit(1)
