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

	# 刷怪是概率性的（每个生成点 70%），空房属正常；分别验证"有怪"与"无怪"两条路径
	var spawn_points: int = ctrl._spawn_points.size()
	_check(spawn_points > 0, "房间有生成点（%d 个）" % spawn_points)
	_check(ctrl.enemies_alive > 0 or ctrl.is_cleared,
		"空房已直接放行（生成点 %d / 敌人 %d）" % [spawn_points, ctrl.enemies_alive])

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
		# 空房（全部生成点都未触发）应直接标记清空且门是开的
		_check(ctrl.is_cleared, "空房直接标记清空")
		var door_open := false
		for door in ctrl._doors:
			var trig = door.get_node_or_null("DoorTrigger")
			if trig and not trig.is_locked:
				door_open = true
		_check(door_open, "空房门未锁")

	# 门触发切房验证
	await _test_door_transition(gr)

	# 清空状态跨房间重建保持（战斗房回访不得重新刷怪锁门）
	await _test_cleared_state_persists(gr, target_idx)

	# 特殊房闭环验证
	await _test_special_room(gr)

	_finish()

## 清空状态落盘验证：房间节点每次进入都重建，控制器实例是新的，
## 不落盘的话回访已清房间会重新刷怪/锁门，Boss 房还会重现传送门
func _test_cleared_state_persists(gr, cleared_idx: int) -> void:
	# 先切走再切回，强制走一次完整的"销毁 → 重建"路径
	var other := 0
	for i in gr.dungeon_graph.size():
		if i != cleared_idx:
			other = i
			break
	gr._transition_to_room(other)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(bool(gr.room_state.get(cleared_idx, {}).get("cleared", false)),
		"房间清空状态已落盘 room_state")

	gr._transition_to_room(cleared_idx)
	await get_tree().process_frame
	await get_tree().process_frame

	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	_check(ctrl != null, "[回访] 控制器就绪")
	if ctrl == null:
		return
	_check(ctrl.is_cleared, "[回访] 已清房间保持清空（不重新刷怪）")
	_check(ctrl.enemies_alive == 0, "[回访] 不重新刷怪（敌人 %d）" % ctrl.enemies_alive)

	var any_locked := false
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and trig.is_locked:
			any_locked = true
	_check(not any_locked, "[回访] 不重新锁门")

## 特殊房闭环：切到特殊房 → 有门有墙有实体 → 交互结算 → 开门
## 地牢种子随机，故遍历本层实际分配到的全部特殊房类型（shop/heal/event）
func _test_special_room(gr) -> void:
	var targets: Array[int] = []
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) in ["shop", "heal", "event"]:
			targets.append(i)
	_check(targets.size() > 0, "地牢分配到特殊房（%d 间）" % targets.size())
	if targets.is_empty():
		return

	for idx in targets:
		var special_type := str(gr.dungeon_graph[idx].get("type", ""))
		gr._transition_to_room(idx)
		await get_tree().process_frame
		await get_tree().process_frame
		await _check_one_special_room(gr, special_type)


## 单个特殊房的闭环断言
func _check_one_special_room(gr, special_type: String) -> void:
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	_check(ctrl != null, "[%s] 控制器就绪" % special_type)
	if ctrl == null:
		return

	_check(ctrl._is_special_room(), "[%s] 识别为特殊房" % special_type)
	_check(ctrl._doors.size() > 0, "[%s] 有门（%d 个）" % [special_type, ctrl._doors.size()])

	# 交互物实体已生成（商店 NPC / 泉水 / 祭坛）
	var prop_count := 0
	var props_node = gr.current_room_node.get_node_or_null("SpawnPoints")
	if props_node:
		for child in props_node.get_children():
			if str(child.name).begins_with("SpecialProp_"):
				prop_count += 1
	_check(prop_count > 0, "[%s] 交互物实体已生成（%d 个）" % [special_type, prop_count])

	# 交互前门不应锁——特殊房允许自由进出，不做战斗式封锁。
	# 这是本流程的关键约定：旧设计锁门后靠"已结算回访只解锁"兜底，
	# 商店因金币不足而交互失败时会把玩家永久关在房里
	var locked_before := false
	var locked_dirs: Array[String] = []
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and trig.is_locked:
			locked_before = true
			locked_dirs.append(str(trig.direction))
	_check(not locked_before, "[%s] 未交互时门不锁（可自由进出）%s" % [special_type, locked_dirs])

	# 商店需要金币才能成交，且消耗品背包要有空位；泉水需要未满血
	var gm = gr.get_node_or_null("/root/GameManager")
	if gm:
		gm.gold = 500
		if gm.consumable_inventory:
			gm.consumable_inventory.quantities.clear()
		if gm.attributes:
			gm.attributes.take_damage(100.0)

	var result: Dictionary = ctrl.interact_special()
	_check(result.get("ok", false), "[%s] 交互成功（%s）" % [special_type, result.get("reason", "")])

	# 重复交互不应重复发放奖励
	var before_state = _special_state(gm, special_type)
	var repeat: Dictionary = ctrl.interact_special()
	_check(repeat.get("already_used", false), "[%s] 重复交互不重复发奖" % special_type)
	_check(_special_state(gm, special_type) == before_state, "[%s] 重复交互后状态未变" % special_type)

	# 交互失败不应影响通行：把房间还原成未交互，再验证门仍然通行
	ctrl._special_used = false
	ctrl._on_cleared()
	_check(ctrl.is_cleared, "[%s] 房间标记清空" % special_type)
	var opened := false
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and not trig.is_locked:
			opened = true
	_check(opened, "[%s] 清空后门解锁" % special_type)

	# 回访已结算的特殊房：应保持可通行，不重新锁门
	ctrl.deactivate()
	ctrl.activate()
	var reentry_locked := false
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and trig.is_locked:
			reentry_locked = true
	_check(not reentry_locked, "[%s] 回访已结算特殊房不重新锁门" % special_type)

## 采集特殊房奖励状态快照（金币 / 药水数 / 生命值）
func _special_state(gm, with_type: String):
	if gm == null:
		return null
	match with_type:
		"shop":
			var q := 0
			if gm.consumable_inventory:
				q = gm.consumable_inventory.count("health_potion")
			return [gm.gold, q]
		"heal":
			return gm.attributes.hp if gm.attributes else 0.0
		"event":
			return true
	return null

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
## 门触发切房验证
## 房间模板的门是固定的（南北），地牢拓扑随机 —— 存在"门朝向无邻接房间"的哑门。
## 故在多间房里找一扇真正连通的门再验证切换机制。
func _test_door_transition(gr) -> void:
	var ctrl = null
	var trig = null
	for attempt in 8:
		ctrl = gr.current_room_node.get_node_or_null("RoomController")
		if ctrl:
			for d in ctrl._doors:
				var t = d.get_node_or_null("DoorTrigger")
				if t == null or str(t.direction).is_empty():
					continue
				if gr._find_room_in_direction(str(t.direction)) >= 0:
					trig = t
					break
		if trig != null:
			break
		# 本房无连通门，换一间再找
		var nxt: int = (gr.current_room_index + 1) % gr.dungeon_graph.size()
		if nxt == gr.current_room_index:
			break
		gr._transition_to_room(nxt)
		await get_tree().process_frame
		await get_tree().process_frame

	if trig == null:
		_check(false, "找到连通的门（遍历多间房）")
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
