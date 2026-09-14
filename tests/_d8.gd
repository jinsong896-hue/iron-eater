extends Node
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	var p = gr.get_node_or_null("Player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	var EB = load("res://entities/enemies/enemy_base.gd")
	# 杀 20 个怪，数掉落
	var dropped := 0
	for i in 20:
		var e = EB.new()
		e.max_hp = 1.0            # 必须在入树前设，_ready 里 _hp = max_hp
		gr.current_room_node.add_child(e)
		e.global_position = p.global_position + Vector3(1.0, 0, 0)
		await get_tree().process_frame
		e.take_damage(999.0)
		await get_tree().process_frame
		dropped = get_tree().get_nodes_in_group("pickups").size()
		if dropped > 0:
			print("第 %d 个敌人掉落！掉落物=%d 距离=%.2f item=%s" % [
				i + 1, dropped,
				get_tree().get_nodes_in_group("pickups")[0].global_position.distance_to(p.global_position),
				str(get_tree().get_nodes_in_group("pickups")[0].get("item"))])
			break
	print("20 次击杀后掉落物总数 = ", dropped, " (30%% 概率期望约 6)")

	# 若没掉，直接放一个，测按 E
	if dropped == 0:
		var LS = load("res://gameplay/loot/loot_system.gd")
		LS.new().generate_chest_loot(p.global_position + Vector3(1.0, 0, 0), gr.current_room_node, 1)
		await get_tree().process_frame
		print("手动放置掉落物 = ", get_tree().get_nodes_in_group("pickups").size())

	var picks = get_tree().get_nodes_in_group("pickups")
	if picks.size() > 0:
		var it = picks[0]
		print("拾取前：item=%s 距离=%.2f 父节点=%s" % [str(it.get("item")),
			it.global_position.distance_to(p.global_position), it.get_parent().name])
		var ev := InputEventAction.new(); ev.action = "interact"; ev.pressed = true
		p._unhandled_input(ev)
		await get_tree().process_frame
		print("按 E 后：背包=%d 剩余=%d" % [GameManager.equipment_manager.get_inventory().size(),
			get_tree().get_nodes_in_group("pickups").size()])
	get_tree().quit(0)
