extends Node
## 复现 #4：真实流程（杀怪→掉落→按 E 拾取）
func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	var p = gr.get_node_or_null("Player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	# 走到一个普通房（非特殊房），模拟正常捡装备
	var EB = load("res://entities/enemies/enemy_base.gd")
	var e = EB.new()
	get_tree().current_scene.add_child(e)
	e.global_position = p.global_position + Vector3(1.5, 0, 0)
	e.max_hp = 1.0
	await get_tree().process_frame
	print("敌人 hp=", e._hp, " 房间类型=", gr.current_room_node.get_node_or_null("RoomController")._room_type())

	# 杀掉 → 应掉落
	e.take_damage(999.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var picks = get_tree().get_nodes_in_group("pickups")
	print("掉落物数: ", picks.size())
	if picks.is_empty():
		print("!! 没掉落——掉落概率 30%，多试几次")
		for i in 5:
			var e2 = EB.new(); get_tree().current_scene.add_child(e2)
			e2.global_position = p.global_position + Vector3(1.2, 0, 0); e2.max_hp = 1.0
			await get_tree().process_frame
			e2.take_damage(999.0)
			await get_tree().process_frame
			if get_tree().get_nodes_in_group("pickups").size() > 0: break
		picks = get_tree().get_nodes_in_group("pickups")
		print("重试后掉落物数: ", picks.size())

	if picks.size() > 0:
		var it = picks[0]
		print("掉落物 item = ", it.get("item"))
		print("掉落物与玩家距离 = %.2f  (拾取上限 2.5)" % it.global_position.distance_to(p.global_position))
		# 走 E 键的真实入口
		var handled = p._interact_special_room()
		print("_interact_special_room 返回 = ", handled, " (false 才会走拾取)")
		var inv0: int = GameManager.equipment_manager.get_inventory().size()
		p._pickup_nearby()
		await get_tree().process_frame
		print("背包 %d -> %d" % [inv0, GameManager.equipment_manager.get_inventory().size()])
		print("剩余掉落物: ", get_tree().get_nodes_in_group("pickups").size())
	get_tree().quit(0)
