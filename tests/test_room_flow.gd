extends Node
## 完整房间流程验证：进战斗房 → 锁门刷怪 → 清怪开门 → 过门切房
var failed := 0

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	if gr == null:
		_check(false, "GameRoot 就绪")
		_finish(); return
	_check(true, "GameRoot 就绪")

	# 找一个 normal 房间
	var target_idx := -1
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "normal":
			target_idx = i
			break
	_check(target_idx >= 0, "地牢有普通房")

	if target_idx < 0:
		_finish(); return

	# 切过去
	gr._transition_to_room(target_idx)
	await get_tree().process_frame
	await get_tree().process_frame

	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	_check(ctrl != null, "新房间控制器就绪")
	_check(ctrl.is_active, "房间激活")
	_check(ctrl._doors.size() > 0, "门已收集（%d 个）" % ctrl._doors.size())

	if ctrl.enemies_alive > 0:
		_check(true, "刷出敌人（%d 只）" % ctrl.enemies_alive)
		# 验证锁门
		var any_locked := false
		for door in ctrl._doors:
			var trig = door.get_node_or_null("DoorTrigger")
			if trig and trig.is_locked:
				any_locked = true
		_check(any_locked, "战斗中门已锁")

		# 杀光敌人
		for e in ctrl._living_enemies.duplicate():
			if is_instance_valid(e):
				e.set("dodge_pct", 0.0)
				e.take_damage(999999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(ctrl.is_cleared, "清怪后房间标记清空")

		var any_open := false
		for door in ctrl._doors:
			var trig = door.get_node_or_null("DoorTrigger")
			if trig and not trig.is_locked:
				any_open = true
		_check(any_open, "清怪后门解锁")
	else:
		_check(false, "刷出敌人（0 只——start 房无怪属正常，但此房应有）")

	# 门触发切房验证
	await _test_door_transition(gr)

	# 特殊房闭环验证
	await _test_special_room(gr)

	_finish()

## 特殊房闭环：切到特殊房 → 有门有墙有实体 → 交互结算 → 开门
func _test_special_room(gr) -> void:
	var special_idx := -1
	var special_type := ""
	for i in gr.dungeon_graph.size():
		var t := str(gr.dungeon_graph[i].get("type", ""))
		if t in ["shop", "heal", "event"]:
			special_idx = i
			special_type = t
			break
	_check(special_idx >= 0, "地牢分配到特殊房（%s）" % special_type)
	if special_idx < 0:
		return

	gr._transition_to_room(special_idx)
	await get_tree().process_frame
	await get_tree().process_frame

	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	_check(ctrl != null, "特殊房控制器就绪")
	if ctrl == null:
		return

	_check(ctrl._is_special_room(), "识别为特殊房（%s）" % special_type)
	_check(ctrl._doors.size() > 0, "特殊房有门（%d 个）" % ctrl._doors.size())

	# 交互物实体已生成（商店 NPC / 泉水 / 祭坛）
	var props_node = gr.current_room_node.get_node_or_null("SpawnPoints")
	var prop_count := 0
	if props_node:
		for child in props_node.get_children():
			if str(child.name).begins_with("SpecialProp_"):
				prop_count += 1
	_check(prop_count > 0, "特殊房交互物已生成（%d 个）" % prop_count)

	# 交互前门是锁的
	var locked_before := false
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and trig.is_locked:
			locked_before = true
	_check(locked_before, "特殊房交互前门已锁")

	# 执行交互（服务层直接结算，不依赖玩家输入）
	var result: Dictionary = ctrl.interact_special()
	_check(result.get("ok", false), "特殊房交互成功（%s: %s）" % [special_type, result.get("reason", "")])
	_check(ctrl.is_cleared, "交互后房间标记清空")

	var opened := false
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and not trig.is_locked:
			opened = true
	_check(opened, "交互后门解锁")

	# 重复交互应被拒绝
	var repeat: Dictionary = ctrl.interact_special()
	_check(not repeat.get("ok", false), "特殊房不可重复交互")

func _check(c: bool, name: String) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)

func _finish() -> void:
	if failed == 0:
		print("ALL ROOM FLOW TESTS PASSED")
	else:
		print("ROOM FLOW TESTS FAILED: %d" % failed)
	get_tree().quit(1 if failed > 0 else 0)

## 追加：门触发切房验证（_check2 系列由主流程结束后调用）
func _test_door_transition(gr) -> void:
	# 回到已清空的房间，站到门触发器上模拟 body_entered
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	var door = ctrl._doors[0]
	var trig = door.get_node_or_null("DoorTrigger")
	if trig == null:
		_check(false, "门触发器存在")
		return
	_check(true, "门触发器存在")
	_check(trig.direction != "", "门方向有效（%s）" % trig.direction)

	# 模拟玩家进入门区域
	var before_idx: int = gr.current_room_index
	trig._on_body_entered(gr.get_node_or_null("Player"))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(gr.current_room_index != before_idx, "门触发后切到新房间（%d → %d）" % [before_idx, gr.current_room_index])
	_check(gr.current_room_node != null, "新房间已加载")
