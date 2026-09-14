extends Node
## 诊断：奔跑穿门连锁触发 —— 记录每一次 door_opened 与切房时序

var _log: Array[String] = []
var _bus = null


func _ready() -> void:
	var g := Timer.new(); g.wait_time = 30.0
	g.timeout.connect(func(): _dump("超时"); get_tree().quit(1))
	add_child(g); g.start()
	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	if gr == null:
		print("无 MainScene"); get_tree().quit(1); return
	_bus = get_node_or_null("/root/EventBus")

	# 在门信号到达前记录（door_opened 由 door_trigger 发出，GameRoot 也连着它）
	if _bus:
		_bus.door_opened.connect(func(dir, id):
			_log.append("door_opened(方向=%s) 当时房=%d 玩家=%s" % [
				dir, gr.current_room_index,
				str((gr.get_node_or_null("Player") as Node3D).global_position.round())
					if gr.get_node_or_null("Player") else "?"]))

	# 回起始房
	var start_idx := 0
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "start":
			start_idx = i; break
	gr._transition_to_room(start_idx)
	for i in 5:
		await get_tree().process_frame

	var player = gr.get_node_or_null("Player")
	print("起始房:", gr.current_room_index)

	# 找一扇可通行的门，清怪后开门
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	for e in ctrl._living_enemies.duplicate():
		if is_instance_valid(e):
			e.set("dodge_pct", 0.0); e.take_damage(999999.0)
	await get_tree().process_frame

	var door_dir := ""
	var door_pos := Vector3.ZERO
	for d in ctrl._doors:
		var t = d.get_node_or_null("DoorTrigger")
		if t and not t.is_locked and gr._find_room_in_direction(str(t.direction)) >= 0:
			door_dir = str(t.direction); door_pos = (d as Node3D).global_position; break
	if door_dir.is_empty():
		print("无可用门"); get_tree().quit(1); return

	print("目标门方向:", door_dir, " 位置:", door_pos)
	_log.append("=== 开始奔跑穿门 ===")

	var idx_log: Array[int] = [gr.current_room_index]
	var mv := gr._dir_vector(door_dir)

	# 从门前 2 米处，全速奔向门（真实物理 + 真实速度）
	player.global_position = door_pos - mv * 2.0
	var frames := 0
	while frames < 90:
		frames += 1
		player.velocity = mv * 8.0
		await get_tree().physics_frame
		if gr.current_room_index != idx_log[-1]:
			idx_log.append(gr.current_room_index)
			_log.append("  → 切到房 %d (帧%d) 玩家=%s" % [
				gr.current_room_index, frames, str(player.global_position.round())])

	print("=== 结果 ===")
	print("房间序列:", str(idx_log), " (期望恰好 2 个：起点 + 终点)")
	_dump("结束")
	get_tree().quit(0)


func _dump(tag: String) -> void:
	print("--- %s ---" % tag)
	for e in _log:
		print(e)
