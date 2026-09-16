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
		_check(controller.enemies_alive >= 1, "Boss 已刷出（enemies_alive=%d）" % controller.enemies_alive)

		# 杀 Boss（连同它的召唤物——Boss 带 summon 机制时会召小怪，
		# 只要还有活的敌人，房间就不该清空，这是正确行为）
		var boss = controller.get("_boss")
		if boss:
			boss.take_damage(999999.0)
		await get_tree().process_frame
		# 清掉残余召唤物，让房间真正满足清空条件
		for e in controller.get("_living_enemies").duplicate():
			if is_instance_valid(e) and e.get("_hp") != null and float(e.get("_hp")) > 0.0:
				e.take_damage(999999.0)
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

			# 层主题与规模必须随层变化——这是层级系统的核心不变量。
			# 回归：生产路径曾硬编码 generate_dungeon(seed, 13)，
			# 绕过按层取数的逻辑，导致 9 层房间数/规模完全相同。
			var graph_after: Array = game_root.get("dungeon_graph")
			_check(_rooms_in_range(graph_after.size(), floor_after),
				"第 %d 层房间数在策划区间内（实际 %d）" % [floor_after, graph_after.size()])
			# 本层房间的地板材质必须是该层主题色（而非上一层残留）
			_check(_floor_matches_theme(new_room, floor_after),
				"第 %d 层房间使用本层主题配色%s" % [floor_after, _floor_color_diag(new_room, floor_after)])

	# 逐层验证 2~5 层：主题色各不相同、房间数按层取
	await _verify_floors_2_to_5(game_root)

	_finish()


## 逐层切到 2~5 层，验证主题配色与房间数随层变化
func _verify_floors_2_to_5(game_root: Node) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		_check(false, "GameManager 可用")
		return
	var seen_themes := {}
	for f in range(2, 6):
		gm.run_info["floor"] = f
		game_root.call("next_floor")
		await get_tree().process_frame
		await get_tree().process_frame

		var g: Array = game_root.get("dungeon_graph")
		_check(_rooms_in_range(g.size(), f),
			"切到第 %d 层后房间数在策划区间内（实际 %d）" % [f, g.size()])
		_check(_floor_matches_theme(game_root.get("current_room_node"), f),
			"第 %d 层房间配色 = 本层主题（%s）" % [f, FloorDefs.theme_name(f)])
		var tid := FloorDefs.theme_id(f)
		_check(not seen_themes.has(tid), "第 %d 层主题 %s 未重复出现" % [f, tid])
		seen_themes[tid] = true


## 房间地板是否用了**该层主题的图集格**。
##
## 行为变更说明：地板从「纯色」改为「图集贴图 + 亮度调制」。原先这里比的是
## albedo_color == FloorDefs 主题色；现在贴图提供纹理与材质色，
## albedo_color 只承载该层的明暗调制，**层间差异体现在 UV（选了哪块砖）上**。
## 故改为校验 mesh 的 UV 落在 AtlasDefs.floor_tile(theme) 对应的范围内。
func _floor_matches_theme(room_node: Node, floor_num: int) -> bool:
	if room_node == null:
		return false
	var fl: Node = room_node.get_node_or_null("Floor")
	if fl == null or fl.get_child_count() == 0:
		return false
	var mi := fl.get_child(0) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		return false
	var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
	if arrays.is_empty():
		return false
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return false
	var rect := AtlasDefs.tile_uv_rect(
		AtlasDefs.floor_tile(FloorDefs.theme_id(floor_num)))
	# 取第一个 UV 与其对角，应落在该格范围内（已在 AtlasDefs 里做过半像素内缩）
	var u := uvs[0].x
	var v := uvs[0].y
	return u >= rect.x - 0.001 and u <= rect.z + 0.001 \
		and v >= rect.y - 0.001 and v <= rect.w + 0.001


## 房间数是否落在该层的策划区间内（FloorDefs 的 rooms_min ~ rooms_max）
## 注意不能跟 room_count() 的返回值比——那个在不传 rng 时给的是区间中点，
## 而实际生成是按种子随机取的区间内值。
func _rooms_in_range(count: int, floor_num: int) -> bool:
	var d: Dictionary = FloorDefs.for_floor(floor_num)
	var lo: int = int(d.get("rooms_min", 0))
	var hi: int = int(d.get("rooms_max", lo))
	return count >= lo and count <= hi


## 诊断串：实际地板色 vs 期望主题色（断言失败时定位用）
func _floor_color_diag(room_node: Node, floor_num: int) -> String:
	if room_node == null:
		return "（房间为空）"
	var fl: Node = room_node.get_node_or_null("Floor")
	if fl == null or fl.get_child_count() == 0:
		return "（无 Floor 子节点）"
	var mi := fl.get_child(0) as MeshInstance3D
	if mi == null:
		return "（首子节点非 MeshInstance3D）"
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		return "（无材质）"
	var want := FloorDefs.color_of(floor_num, "floor")
	var got := mat.albedo_color
	return "（实际 %.2f,%.2f,%.2f / 期望 %.2f,%.2f,%.2f）" % [
		got.r, got.g, got.b, want.r, want.g, want.b]


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
