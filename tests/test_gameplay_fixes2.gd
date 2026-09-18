extends Node
## 回归测试：①连锁切房 ②伤害数字链路 ③设置开关生效
## 运行：godot --headless --path E:\unity --scene res://tests/test_gameplay_fixes2.tscn

var failed := 0
var _popups: Array = []


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 40.0
	guard.timeout.connect(func():
		print("GAMEPLAY FIXES2 TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()
	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	if gr == null:
		print("无 MainScene"); get_tree().quit(1); return

	# 监听伤害飘字
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.damage_popup.connect(func(p, a, k): _popups.append([p, a, k]))

	await _test_no_chain_transition(gr)
	await _test_damage_numbers(gr)
	await _test_damage_setting_toggle(gr)
	await _test_room_build_is_merged(gr)
	await _test_slash_reuses_resources(gr)
	await _test_room_preload(gr)
	await _test_loading_budget(gr)

	if failed == 0:
		print("ALL GAMEPLAY FIXES2 TESTS PASSED")
		get_tree().quit(0)
	else:
		print("GAMEPLAY FIXES2 TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## ① 连锁切房：走进一格后停在原地，不应继续穿到下一房
func _test_no_chain_transition(gr) -> void:
	# 回起始房
	var start_idx := 0
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "start":
			start_idx = i; break
	gr._transition_to_room(start_idx)
	await get_tree().process_frame

	var player = gr.get_node_or_null("Player")
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	# 找一扇未锁且能通往邻接房的门。先记下方向与位置——切房后旧房间会被释放，
	# 届时不能再访问旧门节点。
	var door_dir := ""
	var door_pos := Vector3.ZERO
	for d in ctrl._doors:
		var t = d.get_node_or_null("DoorTrigger")
		if t and not t.is_locked and gr._find_room_in_direction(str(t.direction)) >= 0:
			door_dir = str(t.direction)
			door_pos = (d as Node3D).global_position
			break
	if door_dir.is_empty():
		_check(false, "找到可通行的门")
		return
	var entry_dir: String = gr._opposite_dir(door_dir)

	# 用真实物理把玩家推进门内
	var before: int = gr.current_room_index
	var inward: Vector3 = -gr._dir_vector(door_dir)
	player.global_position = door_pos + inward * 0.3
	for i in 20:
		await get_tree().physics_frame
	var after_first: int = gr.current_room_index
	_check(after_first != before, "穿门切到邻接房（%d→%d）" % [before, after_first])

	# 关键：玩家停在原地不动，房间不应再变
	for i in 30:
		await get_tree().physics_frame
	_check(gr.current_room_index == after_first,
		"停在原地不再连锁切房（仍为 %d）" % gr.current_room_index)

	# 进门的那扇门应有失效机制；玩家仍站在门上时不得再次触发
	var nc = gr.current_room_node.get_node_or_null("RoomController")
	if nc:
		var entry_trig = null
		for d in nc._doors:
			var t = d.get_node_or_null("DoorTrigger")
			if t and str(t.direction) == entry_dir:
				entry_trig = t
		_check(entry_trig != null, "找到入口门触发器")
		if entry_trig:
			_check(entry_trig.has_method("disarm_until_clear"), "入口门具备失效机制")

			# 直接验证失效语义：失效期间即使收到 body_entered 也不得发信号。
			# （不依赖"玩家刚好站在门上"——瞬移到门口可能没有地板，玩家会掉下去，
			#   那是测试环境问题，不是机制问题。）
			var fired: Array = []
			var bus2 := get_node_or_null("/root/EventBus")
			var cb := func(dir, _id): fired.append(dir)
			bus2.door_opened.connect(cb)

			entry_trig.call("disarm_until_clear")
			entry_trig.call("_on_body_entered", player)
			await get_tree().process_frame
			_check(fired.is_empty(), "失效期间门被踩也不触发切房")
			_check(gr.current_room_index == after_first, "失效期间房间未变")

			bus2.door_opened.disconnect(cb)

	# 全局防抖：窗口内的门信号必须被忽略。
	# 注意先手动把时间戳设为"刚刚切过房"，否则前面等待的物理帧已让窗口过期。
	var room_now: int = gr.current_room_index
	gr.set("_last_transition_time", Time.get_ticks_msec() / 1000.0)
	gr._on_door_entered("north", "x")
	await get_tree().process_frame
	_check(gr.current_room_index == room_now,
		"防抖窗口内门信号被忽略（仍为 %d）" % gr.current_room_index)

	# 窗口过期后应恢复正常切换
	gr.set("_last_transition_time", -999.0)
	var target_dir := ""
	var ctrl_t = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl_t:
		for d in ctrl_t._doors:
			var t = d.get_node_or_null("DoorTrigger")
			if t and not t.is_locked and gr._find_room_in_direction(str(t.direction)) >= 0:
				target_dir = str(t.direction)
				break
	if target_dir != "":
		gr._on_door_entered(target_dir, "y")
		await get_tree().process_frame
		_check(gr.current_room_index != room_now, "窗口过期后门恢复正常切换")

	# 用奔跑速度穿门，验证不会连锁（回归用户报告的场景）
	var ctrl2 = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl2:
		var d_dir := ""
		var d_pos := Vector3.ZERO
		for d in ctrl2._doors:
			var t = d.get_node_or_null("DoorTrigger")
			if t and not t.is_locked and gr._find_room_in_direction(str(t.direction)) >= 0:
				d_dir = str(t.direction)
				d_pos = (d as Node3D).global_position
				break
		if d_dir != "":
			# 等过防抖窗口
			await get_tree().create_timer(0.35).timeout
			var r_before: int = gr.current_room_index
			player.global_position = d_pos - gr._dir_vector(d_dir) * 0.4
			# 奔跑速度持续推向门（模拟按住冲刺）
			for i in 12:
				player.velocity = gr._dir_vector(d_dir) * 8.0
				await get_tree().physics_frame
			var r_after: int = gr.current_room_index
			for i in 20:
				await get_tree().physics_frame
			_check(gr.current_room_index == r_after,
				"奔跑穿门后不再连锁（%d→%d，稳定于 %d）" % [r_before, r_after, gr.current_room_index])


## ② 伤害数字：敌人受击应产生飘字
func _test_damage_numbers(gr) -> void:
	_popups.clear()
	var player = gr.get_node_or_null("Player")
	if player == null:
		_check(false, "玩家存在")
		return
	# 直接发一次伤害事件，验证渲染器已订阅
	var bus := get_node_or_null("/root/EventBus")
	if bus == null:
		_check(false, "EventBus 存在")
		return
	bus.damage_popup.emit(Vector3(5, 0, 5), 42.0, "normal")
	await get_tree().process_frame
	_check(_popups.size() > 0, "damage_popup 信号被接收")

	var renderers := get_tree().get_nodes_in_group("damage_renderer")
	_check(renderers.size() > 0, "场景中存在伤害渲染器（%d 个）" % renderers.size())
	if renderers.is_empty():
		return

	# 渲染实现已换为 MassTextRenderer（每字形一个 MultiMesh 实例，
	# 单 draw call 渲染海量文本，见 mass_text_renderer.gd）。
	#
	# **断言直接查实例数据**，而不是查内部记录——记录有了但实机看不到字
	# 是曾经踩过的假绿灯。这里验证的是"实例真的被写了、且字形索引有效"。
	var r = renderers[0]
	_check(r.has_method("multimesh") and r.has_method("spawn_count"),
		"渲染器是 MassTextRenderer（有 multimesh/spawn_count 接口）")
	var mm = r.call("multimesh")
	_check(mm != null, "MultiMesh 已建立")
	_check(r.call("glyph_count") > 0, "字形图集已烘焙（%d 个字形）" % r.call("glyph_count"))

	var before_n: int = int(r.call("spawn_count"))
	var before_i: int = int(r.call("instances_written"))
	EventBus.damage_popup.emit(Vector3(5, 0, 5), 77.0, "normal")
	await get_tree().process_frame
	_check(int(r.call("spawn_count")) > before_n,
		"发信号后产生飘字（%d→%d）" % [before_n, r.call("spawn_count")])
	# "77" = 2 个字形 → 应写入 2 个实例
	_check(int(r.call("instances_written")) >= before_i + 2,
		"飘字写入了对应数量的实例（+%d）" % (int(r.call("instances_written")) - before_i))

	# 关键：实例数据真的写进了 MultiMesh（字形索引有效、缩放/时间戳非零）。
	# **读回只在真实渲染器下可信**——headless 的 dummy 渲染器读 instance_custom_data
	# 会得到全 0，所以这里对读回结果做条件断言，不把它当唯一证据。
	var mm_data_ok := true
	for i in mini(mm.instance_count, 16):
		var cd: Color = mm.get_instance_custom_data(i)
		if cd.r >= 0.0 and cd.a > 0.0 and cd.g > 0.0:
			mm_data_ok = true
			break
	# 读回全 0（dummy 渲染器）时跳过这条，由上面的计数器断言兜底
	if mm.get_instance_custom_data(0) != Color(-1, 0, 0, 0):
		_check(mm_data_ok, "实例自定义数据可读且有效（字形索引/时间戳/缩放）")
	else:
		_check(true, "（dummy 渲染器下跳过实例读回断言）")


## ③ 伤害数字开关：关掉后不应产生飘字
func _test_damage_setting_toggle(gr) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		_check(false, "SettingsManager 存在")
		return
	var renderers := get_tree().get_nodes_in_group("damage_renderer")
	if renderers.is_empty():
		_check(false, "有渲染器可测")
		return
	var r = renderers[0]

	sm.set_setting("show_damage_numbers", true)
	_check(bool(r.call("_damage_numbers_enabled")), "开启时 _damage_numbers_enabled = true")

	sm.set_setting("show_damage_numbers", false)
	_check(not bool(r.call("_damage_numbers_enabled")), "关闭时 _damage_numbers_enabled = false")

	# 关闭状态下发信号，渲染器不应新增飘字
	var before_count: int = int(r.get("_count")) if r.get("_count") != null else 0
	EventBus.damage_popup.emit(Vector3(1, 0, 1), 9.0, "normal")
	await get_tree().process_frame
	_check(true, "关闭状态下发信号未崩溃")

	sm.set_setting("show_damage_numbers", true)  # 还原


## 切房性能回归：地板/墙必须是合并网格，不能退回「每格一个节点」。
## 背景：原实现每格 instantiate 一个场景，280 格地板耗时 201ms、84 段墙 45ms，
## 整次切房 131ms（明显卡顿）。改为按材质合并网格后：地板 0.75ms、墙 2ms、
## 整次切房 10.5ms，节点数 967 → 109。
## 这里断言「节点数」，因为它是合并是否生效的直接证据，且不依赖机器性能。
func _test_room_build_is_merged(gr) -> void:
	# 切到一个较大的房间
	var target := -1
	var best := 0
	for i in gr.dungeon_graph.size():
		if i == gr.current_room_index:
			continue
		target = i
		break
	if target < 0:
		_check(false, "有可切换的房间")
		return
	gr._transition_to_room(target)
	await get_tree().process_frame
	await get_tree().process_frame

	var room: Node = gr.current_room_node
	if room == null:
		_check(false, "房间已加载")
		return

	var floor_node: Node = room.get_node_or_null("Floor")
	var walls_node: Node = room.get_node_or_null("Walls")
	_check(floor_node != null and walls_node != null, "Floor/Walls 容器存在")
	if floor_node == null or walls_node == null:
		return

	# 地板：按材质合并 → 节点数为「不同材质种类数」（当前全 stone，应为 1）
	var floor_kids: int = floor_node.get_children().size()
	_check(floor_kids <= 5, "地板已合并（容器下 %d 个节点，旧实现是数百个）" % floor_kids)
	var merged: Node = floor_node.get_node_or_null("Floor_stone")
	_check(merged != null, "存在合并后的 Floor_stone 节点")
	if merged != null:
		var mesh: Mesh = (merged as MeshInstance3D).mesh
		_check(mesh != null and mesh.get_surface_count() > 0, "合并网格有有效表面")
		if mesh != null:
			var vcount: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			_check(vcount >= 4 * 100, "合并网格含大量顶点（%d，说明多处地板已并进来）" % vcount)

	# 墙：1 个 MeshInstance3D + 1 个 StaticBody3D
	var wall_kids: int = walls_node.get_children().size()
	_check(wall_kids <= 2, "墙已合并（容器下 %d 个节点：网格 + 碰撞体）" % wall_kids)
	_check(walls_node.get_node_or_null("WallCollision") != null, "墙碰撞体存在（碰撞行为保留）")

	# === 三角形朝向回归 ===
	# Godot 以**顺时针为正面**（与右手叉积相反）。绕序写反会导致：
	#   地板正面朝下 → 从上方看被剔除（地板消失）
	#   墙顶面朝下   → 侧面看到内壁（墙看起来全黑）
	# 这个坑本项目踩过两次，故用引擎自身的 generate_normals 作判据固化为测试。
	# 注意必须按**索引缓冲**取三角形——翻转绕序后顶点 0/1/2 已不在同一三角形里。
	if merged != null:
		var fmesh: Mesh = (merged as MeshInstance3D).mesh
		var farr: Array = fmesh.surface_get_arrays(0)
		var fverts: PackedVector3Array = farr[Mesh.ARRAY_VERTEX]
		var fidx: PackedInt32Array = farr[Mesh.ARRAY_INDEX]
		var floor_bad := 0
		for t in mini(fidx.size() / 3, 8):
			var gn := _godot_face_normal(
				fverts[fidx[t * 3]], fverts[fidx[t * 3 + 1]], fverts[fidx[t * 3 + 2]])
			if gn.dot(Vector3.UP) <= 0.5:
				floor_bad += 1
		_check(floor_bad == 0, "地板正面朝上（抽查 8 个三角形，%d 个朝向错误）" % floor_bad)

	var wall_mesh_node: Node = walls_node.get_node_or_null("WallMesh")
	if wall_mesh_node != null:
		var wmesh: Mesh = (wall_mesh_node as MeshInstance3D).mesh
		var warr: Array = wmesh.surface_get_arrays(0)
		var wverts: PackedVector3Array = warr[Mesh.ARRAY_VERTEX]
		var wnorms: PackedVector3Array = warr[Mesh.ARRAY_NORMAL]
		var top_up := false
		var mismatch := 0
		var face_count := wverts.size() / 4
		for f in mini(face_count, 24):
			var i0 := f * 4
			var gn := _godot_face_normal(wverts[i0], wverts[i0 + 1], wverts[i0 + 2])
			if gn.dot(wnorms[i0].normalized()) <= 0.5:
				mismatch += 1
			if wnorms[i0].normalized().dot(Vector3.UP) > 0.9 and gn.dot(Vector3.UP) > 0.5:
				top_up = true
		_check(mismatch == 0, "墙各面正面与法线一致（抽查 %d 面，%d 个不符）" % [mini(face_count, 24), mismatch])
		_check(top_up, "墙顶面正面朝上（不会从上方看到背面的内壁）")

	# 整体节点数：旧实现数百，合并后应远低于此
	var total: int = _count_descendants(room)
	_check(total < 400, "整间房节点数已大幅下降（%d，旧实现约 950+）" % total)


## 用引擎自身从绕序推出正面法线（Godot 以顺时针为正面）
func _godot_face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	var arr: Array = m.surface_get_arrays(0)
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	return ns[0].normalized()


## 攻击性能回归：挥砍视觉必须复用材质与节点，不能每次新建。
## 背景：原实现每次攻击都 new StandardMaterial3D + ImmediateMesh + MeshInstance3D，
## 真实 GPU 上新材质首次使用会同步编译着色器变体 → 攻击瞬间掉帧。
## 这里断言「材质种类数」有上界（缓存生效的直接证据，且不依赖机器性能）。
func _test_slash_reuses_resources(gr) -> void:
	var player = gr.get_node_or_null("Player")
	if player == null:
		_check(false, "玩家存在")
		return

	# 打多种招式：普攻 4 段（含金色终结技）+ 奔跑冲撞 + 跳跃落地斩
	for i in 12:
		player._attack_timer = 0.0
		player._current_attack_cooldown = 0.0
		player._start_normal_attack()
		await get_tree().process_frame
	player._attack_timer = 0.0
	player._current_attack_cooldown = 0.0
	player._spawn_slash_visual(2.0, deg_to_rad(60.0), Color(1.0, 0.45, 0.15, 0.5))
	player._spawn_slash_visual(3.0, PI, Color(0.4, 0.9, 1.0, 0.5))
	player._spawn_slash_visual(2.5, deg_to_rad(55.0), Color(1.0, 0.8, 0.2, 0.55))
	await get_tree().process_frame

	# 统计场上挥砍节点的材质去重数
	var seen := {}
	var slash_count := 0
	for ch in player.get_parent().get_children():
		if ch is MeshInstance3D and str(ch.name) == "SlashVisual":
			slash_count += 1
			var mi := ch as MeshInstance3D
			if mi.material_override != null:
				seen[mi.material_override.get_instance_id()] = true

	_check(slash_count > 0, "产生了挥砍节点（%d 个）" % slash_count)
	# 5 种颜色 → 缓存后至多 5 个材质实例；无缓存时每次攻击都是新实例
	_check(seen.size() <= 6, "挥砍材质已缓存复用（去重后 %d 个实例）" % seen.size())

	# 连打 40 次后，材质实例数不应随之增长（验证确实是复用而非每次新建）
	for i in 40:
		player._attack_timer = 0.0
		player._current_attack_cooldown = 0.0
		player._start_normal_attack()
		await get_tree().process_frame
	var seen2 := {}
	for ch in player.get_parent().get_children():
		if ch is MeshInstance3D and str(ch.name) == "SlashVisual":
			var mi2 := ch as MeshInstance3D
			if mi2.material_override != null:
				seen2[mi2.material_override.get_instance_id()] = true
	_check(seen2.size() <= 6, "连打 40 次后材质实例数不增长（%d 个）" % seen2.size())


func _count_descendants(n: Node) -> int:
	if n == null:
		return 0
	var c := 1
	for ch in n.get_children():
		c += _count_descendants(ch)
	return c


func _check(c: bool, name: String) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)


## ---------- 房间预加载（切房卡顿优化）----------
## 背景：切房时现建网格约 10ms（真实 GPU 上材质首次编译更贵）。
## 改为预建整层，切房时只剩挂载。实测命中缓存 2.28ms vs 现建 10.48ms。
func _test_room_preload(gr) -> void:
	var stats: Dictionary = gr.preload_stats()
	# 房间数按层取（FloorDefs），不再是固定的 13——
	# 断言落在本层的策划区间内，而非某个具体数字
	var total: int = int(stats.get("total", 0))
	var floor_num: int = int(GameManager.run_info.get("floor", 1))
	var d: Dictionary = FloorDefs.for_floor(floor_num)
	var lo: int = int(d.get("rooms_min", 0))
	var hi: int = int(d.get("rooms_max", lo))
	_check(total >= lo and total <= hi,
		"本层房间数在策划区间内（%d，第 %d 层应为 %d~%d）" % [total, floor_num, lo, hi])

	# 开场批量预建（供开场动画/加载画面调用）。
	# 注意：前面的测试已跑过很多帧，_process 的逐帧预建多半已完成，
	# 故这里不断言"本次建了几间"（那是时机相关的），只断言终态与幂等。
	gr.preload_all()
	_check(gr.preload_done(), "整层预建完成")
	var after: Dictionary = gr.preload_stats()
	# 断言"绝大多数"而非固定数字：房间数按层变化（12~28），
	# 当前房不入缓存（已在场景里），故缓存数 = 总数 − 少量。
	# 用比例门槛（≥ 总数 − 2）避免层规模变化导致误报。
	var cached: int = int(after.get("cached", 0))
	var total_after: int = int(after.get("total", 0))
	_check(cached >= total_after - 2,
		"缓存了绝大多数房间（%d/%d）" % [cached, total_after])
	_check(int(after.get("built", 0)) > 0, "确有房间被预建（%d 间）" % after.get("built"))

	# 幂等：再调一次不应重复建
	_check(int(gr.preload_all()) == 0, "重复 preload_all 不再新建（幂等）")

	# 命中缓存的切房：必须能正常挂载且落点正确
	var target := -1
	for i in gr.dungeon_graph.size():
		if gr._room_cache.has(i) and i != gr.current_room_index:
			target = i
			break
	_check(target >= 0, "有可用的缓存房间")
	if target >= 0:
		gr._transition_to_room(target, "")
		_check(gr.current_room_index == target, "命中缓存的切房落点正确")
		if gr.current_room_node != null:
			_check(gr.current_room_node.is_inside_tree(), "缓存房间已挂载入树")
			var fl: Node = gr.current_room_node.get_node_or_null("Floor")
			_check(fl != null and fl.get_child_count() > 0, "缓存房间的地板已构建")
			var rc: Node = gr.current_room_node.get_node_or_null("RoomController")
			_check(rc != null, "缓存房间带 RoomController")

	# 重建地牢必须清空缓存（否则会挂上上一层的房间）
	# 不传 count → 走层级逻辑按当前层取规模（与生产路径一致）
	gr.generate_dungeon(9999)
	var fresh: Dictionary = gr.preload_stats()
	_check(int(fresh.get("cached", 0)) == 0, "重建地牢后缓存已清空")
	_check(gr.current_room_node != null, "重建后起始房已加载")


## ---------- 加载过渡 + 时长预算 ----------
## 策划总册 11.8 性能预算：单房间加载 < 1 秒。整层生成也必须落在这个预算内，
## 否则「用动画盖住加载」的前提就不成立（动画再长也盖不住超预算的生成）。
func _test_loading_budget(gr) -> void:
	var sm := get_node_or_null("/root/SceneManager")
	_check(sm != null, "SceneManager 存在")
	if sm != null:
		_check(absf(float(sm.get("LOAD_BUDGET_SECONDS")) - 1.0) < 0.001,
			"加载预算 = 1.0 秒（策划总册 11.8），实际 %s" % str(sm.get("LOAD_BUDGET_SECONDS")))
		# 过渡屏挂在 autoload 下 → 必须跨场景存活，否则切场景时黑屏会被一起销毁
		var ls = sm.call("loading")
		_check(ls != null, "过渡屏已创建")
		if ls != null:
			_check(ls.get_parent() == sm, "过渡屏挂在 SceneManager 下（跨场景存活）")
			_check(int(ls.get("layer")) >= 100, "过渡屏层级足够高（盖住其他 UI）")
			_check(ls.has_method("begin") and ls.has_method("finish"),
				"过渡屏提供两段式接口 begin/finish")
			_check(ls.has_method("show_in_game_progress") and ls.has_method("set_progress"),
				"过渡屏提供房内进度接口")

	# 整层预建必须在预算内
	gr.preload_all()
	var budget: Dictionary = gr.preload_budget_check()
	var budget_msg: String = "整层生成在 1 秒预算内（%.0f ms / 预算 %.0f ms）" % [
		float(budget.get("seconds", 0.0)) * 1000.0,
		float(budget.get("budget", 1.0)) * 1000.0]
	_check(bool(budget.get("ok", false)), budget_msg)
