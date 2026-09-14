extends Node
## 复现：掉落物存在时，模拟真实按 E 的入口
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	var p = gr.get_node_or_null("Player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	# 造一个掉落物
	var LS = load("res://gameplay/loot/loot_system.gd")
	var l = LS.new()
	l.generate_chest_loot(p.global_position + Vector3(0.8, 0, 0), gr.current_room_node, 1)
	await get_tree().process_frame
	var picks = get_tree().get_nodes_in_group("pickups")
	print("掉落物数=", picks.size(), " 距离=%.2f" % picks[0].global_position.distance_to(p.global_position))
	print("item=", picks[0].get("item"))

	# 模拟真实按 E：构造 InputEventAction 走 _unhandled_input
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	ev.is_action_pressed("interact")
	print("--- 调 _unhandled_input ---")
	p._unhandled_input(ev)
	await get_tree().process_frame
	print("按 E 后：背包=%d 剩余掉落物=%d" % [
		GameManager.equipment_manager.get_inventory().size(),
		get_tree().get_nodes_in_group("pickups").size()])

	# 对照：直接调 _pickup_nearby
	if get_tree().get_nodes_in_group("pickups").size() > 0:
		print("--- 对照：直接调 _pickup_nearby ---")
		p._pickup_nearby()
		await get_tree().process_frame
		print("直接调后：背包=%d 剩余=%d" % [
			GameManager.equipment_manager.get_inventory().size(),
			get_tree().get_nodes_in_group("pickups").size()])
	get_tree().quit(0)
