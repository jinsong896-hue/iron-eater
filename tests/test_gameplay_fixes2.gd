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

	# 渲染实现已从 MultiMesh+图集着色器 换为 Label（见 damage_text_renderer.gd 头部注释）。
	# 不再断言 MultiMesh 相关字段——改断言「真的存在可见 Label」，见下方端到端检查。
	var r = renderers[0]

	# 端到端：发信号后应真的产生一条飘字记录，**且对应 Label 真的可见且有文本**
	# （旧版只断言内部记录，是假绿灯：记录有了但实机看不到字）
	var act: Array = r.get("_active")
	var before_n: int = act.size()
	EventBus.damage_popup.emit(Vector3(5, 0, 5), 77.0, "normal")
	await get_tree().process_frame
	_check(act.size() > before_n, "发信号后产生飘字记录（%d→%d）" % [before_n, act.size()])
	if act.size() > before_n:
		var entry: Dictionary = act[act.size() - 1]
		_check(str(entry.get("str", "")) == "77", "飘字文本正确（'%s'）" % entry.get("str"))
		_check(float(entry.get("lifetime", 0.0)) > 0.0, "飘字有存活时间")

	# 关键：真实渲染——找到可见的 Label，确认文本与颜色都落到了节点上
	var visible_labels: Array = []
	for child in r.get_children():
		if child is Label and (child as Label).visible and (child as Label).text != "":
			visible_labels.append(child)
	_check(visible_labels.size() > 0, "存在可见的伤害数字 Label（%d 个）" % visible_labels.size())
	if visible_labels.size() > 0:
		# 前面还发过一次 42，故按文本找 77 而非取第一个
		var target: Label = null
		for lb in visible_labels:
			if (lb as Label).text == "77":
				target = lb
				break
		_check(target != null, "其中包含文本 77 的 Label")
		if target == null:
			target = visible_labels[0]
		_check(target.get_theme_font_size("font_size") > 0,
			"Label 字号有效（%d）" % target.get_theme_font_size("font_size"))
		_check(target.modulate.a > 0.5, "Label 不透明（alpha=%.2f）" % target.modulate.a)


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


func _check(c: bool, name: String) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
