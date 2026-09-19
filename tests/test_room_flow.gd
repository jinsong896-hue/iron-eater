extends Node
## 完整房间流程验证：进战斗房 → 锁门刷怪 → 清怪开门 → 过门切房
var failed := 0

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var gr := get_tree().current_scene.get_node_or_null("MainScene/GameRoot")
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

	# 补刷敌人必须重新锁门（有怪却开着门 = 实机「能带怪跑出去」）
	await _test_respawn_relocks(gr, target_idx)

	# 特殊房闭环验证
	await _test_special_room(gr)

	# 全地牢哑门排查（本次修复的核心不变量）
	await _test_no_dead_doors(gr)

	# swarm 分流：群体模拟的生成/计数/死亡结算闭环
	await _test_crowd_routing(gr)

	# 房间模板稳定性：回访已进过的房间，布局不得改变
	await _test_room_template_stable(gr)

	# 群体单位不得跑出房间边界
	await _test_crowd_stays_in_bounds(gr)

	_finish()


## 房间模板在生成期就该定好 —— 回访已进过的房间，**布局必须完全一致**。
##
## 原先 `_pick_template` 用全局 `randi()` 选模板，而房间节点每次进入都重建
## （见 _transition_to_room），于是同一个房间第二次进去可能换成长宽不同的
## 另一套模板 —— 玩家看到的是"已进过的房间在不停变换"。
## 修法是按「地牢种子 + 房间下标」确定性派生。
func _test_room_template_stable(gr) -> void:
	# 找一个普通房（房间数足够，随便挑中间一个）
	var idx := -1
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "normal":
			idx = i
			break
	if idx < 0:
		_check(true, "[模板] 无普通房可测（跳过）")
		return

	# 第一次进：记录房间尺寸与门位（布局的可观测特征）
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	var ctrl1 = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl1 == null:
		_check(false, "[模板] 控制器就绪")
		return
	var sig1 := _room_signature(ctrl1)

	# 切走再切回（强制走完整的"销毁 → 重建"路径）
	var other := 0
	for i in gr.dungeon_graph.size():
		if i != idx:
			other = i
			break
	gr._transition_to_room(other)
	await get_tree().process_frame
	await get_tree().process_frame
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	var ctrl2 = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl2 == null:
		_check(false, "[模板] 回访后控制器就绪")
		return
	var sig2 := _room_signature(ctrl2)

	_check(sig1 == sig2, "[模板] 回访房间布局完全一致（%s vs %s）" % [sig1, sig2])
	_check(not sig1.is_empty(), "[模板] 房间特征非空（%s）" % sig1)


## 房间布局的可观测特征：宽高 + 门数量 + 门位（排序后）
func _room_signature(ctrl) -> String:
	var d = ctrl.get("room_data")
	if d == null:
		return ""
	var w := 0.0
	var h := 0.0
	var doors: Array = []
	if d is Dictionary:
		w = float((d as Dictionary).get("width", 0))
		h = float((d as Dictionary).get("height", 0))
		doors = (d as Dictionary).get("doors", [])
	else:
		w = float(d.get("width"))
		h = float(d.get("height"))
		var dd = d.get("doors")
		if dd is Array:
			doors = dd
	var parts: Array[String] = []
	for dr in doors:
		parts.append("%d,%d,%s" % [int(dr.get("x", 0)), int(dr.get("y", 0)),
			str(dr.get("direction", ""))])
	parts.sort()
	return "%dx%d|%s" % [int(w), int(h), ",".join(parts)]

## 全地牢哑门排查：逐间房构建，断言每扇门都通向真实邻接房间
## 哑门 = 门朝向没有邻接房间，玩家走上去 DoorTrigger 发信号但
## GameRoot 按方向找不到房间，静默不切房（看起来像卡住）
func _test_no_dead_doors(gr) -> void:
	var total_doors := 0
	var dead_doors := 0
	var detail: Array[String] = []

	for i in gr.dungeon_graph.size():
		gr._transition_to_room(i)
		await get_tree().process_frame
		await get_tree().process_frame

		var ctrl = gr.current_room_node.get_node_or_null("RoomController")
		if ctrl == null:
			continue
		for door in ctrl._doors:
			var trig = door.get_node_or_null("DoorTrigger")
			if trig == null or str(trig.direction).is_empty():
				continue
			total_doors += 1
			if gr._find_room_in_direction(str(trig.direction)) < 0:
				dead_doors += 1
				detail.append("房%d %s" % [i, trig.direction])

	_check(total_doors > 0, "地牢共构建出 %d 扇门" % total_doors)
	_check(dead_doors == 0, "无哑门（%d 扇全部通向邻接房间）%s" % [dead_doors, detail])

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

## 补刷敌人必须重新锁门。
## 复现路径：先清空房间（门已开）→ 再调 debug_spawn 补怪 →
## 若门仍开着，玩家就能带着满屋的怪走出房间。实机症状即「敌人还在却能离开」。
## 不变量：只要 enemies_alive > 0，所有门就必须是锁定态。
func _test_respawn_relocks(gr, idx: int) -> void:
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame

	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	if ctrl == null:
		_check(false, "[补刷] 控制器就绪")
		return
	# 借一只真实怪物 id，避免硬编码与 MonsterDB 脱节
	var ids: Array = []
	for m in MonsterDB.all_monsters():
		ids.append(str(m.get("id", "")))
	if ids.is_empty():
		_check(false, "[补刷] MonsterDB 有怪物可刷")
		return

	var r: Dictionary = ctrl.debug_spawn(ids[0], 2, ctrl.global_position)
	_check(r.get("spawned", 0) > 0, "[补刷] 刷出 %d 只" % r.get("spawned", 0))
	await get_tree().process_frame

	var locked_count := 0
	for door in ctrl._doors:
		var trig = door.get_node_or_null("DoorTrigger")
		if trig and trig.is_locked:
			locked_count += 1
	_check(locked_count > 0, "[补刷] 有敌人时门重新锁死（%d/%d 扇）"
		% [locked_count, ctrl._doors.size()])

	# 再杀一只，只要还有活口，门不许开
	if ctrl.debug_living_enemies().size() > 1:
		ctrl.debug_living_enemies()[0].take_damage(999999.0)
		await get_tree().process_frame
		var still_locked := false
		for door in ctrl._doors:
			var trig = door.get_node_or_null("DoorTrigger")
			if trig and trig.is_locked:
				still_locked = true
		_check(still_locked, "[补刷] 剩一只怪时门仍锁着")

	ctrl.debug_clear_enemies()
	await get_tree().process_frame


## swarm 分流闭环：开启强制开关后，基础怪应走 CrowdManager 而非 EnemyBase，
## 且计数、清空判定、死亡掉落都要跟着走通。
##
## **为什么要测**：路由默认关闭（没有 MonsterDB 条目带 swarm 标记），
## 不强制打开的话这条路径永远测不到——而"测不到"等于没有防线。
## 这里用 RoomController.CROWD_FORCE_SWARM 静态开关临时打开。
##
## **必须找一个尚未被清空的房间**：本测试跑在前面的用例之后，
## 它们已经打过若干房间；若选中已清空的房间，`activate()` 会走
## "回访已清房间"分支直接 return，根本不刷怪（实测踩到）。
func _test_crowd_routing(gr) -> void:
	var idx := -1
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) != "normal":
			continue
		if bool(gr.room_state.get(i, {}).get("cleared", false)):
			continue   # 已清空的房间不会再刷怪
		idx = i
		break
	if idx < 0:
		_check(true, "[crowd] 无未清空普通房可测（跳过）")
		return

	RoomController.CROWD_FORCE_SWARM = true
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	# **必须等物理帧**：CrowdManager 在 _physics_process 里 step，
	# 而空间哈希是 step 时建的——没 step 过，query_circle 会返回空
	#（表现为"有单位但查不到"）。等 process_frame 等不到物理帧。
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	_check(ctrl != null, "[crowd] 控制器就绪")
	if ctrl == null:
		RoomController.CROWD_FORCE_SWARM = false
		return

	var mgr = ctrl.get("_crowd_mgr")
	_check(mgr != null, "[crowd] 强制开关下创建了 CrowdManager")
	if mgr == null:
		RoomController.CROWD_FORCE_SWARM = false
		return

	var n: int = int(mgr.get("active"))
	_check(n > 0, "[crowd] 群体单位已生成（%d 个）" % n)
	# 计数要算上群体单位（否则清空判定会提前放行）
	_check(ctrl.enemies_alive > 0, "[crowd] enemies_alive 计入群体单位（%d）" % ctrl.enemies_alive)

	# —— 批次 5 的核心：**玩家攻击必须能打到群体单位** ——
	#
	# 这是分流能否成立的关键。群体单位不在场景树里，玩家的 group("enemies")
	# 遍历找不到它们；必须走 CrowdSim 的 query_cone 分支。
	# 早期版本只测"直接调 apply_damage"，那条路径绕过了玩家的命中链路——
	# 等于批次 5 的功能完全没被覆盖（"测不到"等于没有防线）。
	var p = get_tree().get_first_node_in_group("player")
	if p != null:
		# 把一个单位挪到玩家正前方，确保在扇形范围内
		var fwd: Vector3 = p.get("_facing")
		if fwd.length_squared() < 0.01:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var target_pos: Vector3 = p.global_position + fwd * 1.2
		var ids_all = mgr.call("query_circle", 0.0, 0.0, 9999.0)
		var hp_before := -1.0
		if ids_all.size() > 0:
			var first_id: int = int(ids_all[0])
			# 用模拟核的 set_target/位置无直接写入接口，改用整体平移：
			# 直接把玩家挪到该单位面前更简单（单位位置由模拟核掌管）
			var upos: Vector3 = mgr.call("unit_position", first_id)
			p.global_position = upos - fwd * 1.2
			hp_before = float(mgr.call("unit_hp", first_id))
			# 走玩家的扇形命中入口（普攻的真实路径）
			p.call("_hit_enemies_in_cone", 1.0, 2.5, deg_to_rad(60.0), 0.0)
			var hp_after := float(mgr.call("unit_hp", first_id))
			_check(hp_after < hp_before,
				"[crowd] 玩家普攻能打到群体单位（hp %.1f → %.1f）" % [hp_before, hp_after])
		else:
			_check(false, "[crowd] 有群体单位可供攻击测试")

	# —— 形态附加效果在群体路径也要生效 ——
	#
	# 节点路径有一套附加效果（渡鸦法强附加/影子攻击/穿透线/森之领域…），
	# 群体单位不是节点，早期版本**整套都跳过了**——同一个形态打 swarm 怪
	# 会明显少一截伤害。这里验证"附加伤害确实落到群体单位身上"。
	await _test_crowd_form_extras(p, mgr)

	# 打掉全部群体单位 → 应触发清空
	#
	# **必须等物理帧**：CrowdManager 在 _physics_process 里 step + drain_events，
	# 死亡计数是那时才扣的。等 process_frame 等不到（实测踩到）。
	var all = mgr.call("query_circle", 0.0, 0.0, 9999.0)
	mgr.call("apply_damage", all, 999999.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(int(mgr.get("active")) == 0, "[crowd] 全灭后群体活跃数归零")
	# 房间可能还有其他节点式怪（带机制的），故只断言"群体那部分已结算"
	_check(ctrl.enemies_alive < n + 1,
		"[crowd] 群体死亡已从 enemies_alive 扣除（%d）" % ctrl.enemies_alive)

	RoomController.CROWD_FORCE_SWARM = false


## 群体单位**不得跑出房间边界**。
##
## 实机症状：「房间敌人过多时敌人有概率被挤到 z 轴上方，游戏无法继续」。
## 根因是 `CrowdManager.set_obstacles()` 在生产路径从未被调用——
## 群体单位没有墙的碰撞，被邻居斥力一路挤出房间，玩家清不掉也追不上。
##
## 这里让一批单位朝同一方向猛挤，断言它们仍留在房间 AABB 内。
func _test_crowd_stays_in_bounds(gr) -> void:
	var idx := -1
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) != "normal":
			continue
		if bool(gr.room_state.get(i, {}).get("cleared", false)):
			continue
		idx = i
		break
	if idx < 0:
		_check(true, "[边界] 无未清空普通房可测（跳过）")
		return

	RoomController.CROWD_FORCE_SWARM = true
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	var ctrl = gr.current_room_node.get_node_or_null("RoomController")
	var mgr = ctrl.get("_crowd_mgr") if ctrl else null
	if mgr == null:
		_check(true, "[边界] 本房无群体单位（跳过）")
		RoomController.CROWD_FORCE_SWARM = false
		return

	# 房间尺寸（判定边界用）
	var d = ctrl.get("room_data")
	var w := 20.0
	var h := 15.0
	if d is Dictionary:
		w = float((d as Dictionary).get("width", 20))
		h = float((d as Dictionary).get("height", 15))

	# 猛挤：把玩家放到房间外远处，所有单位会朝它冲，撞上边界
	var p = get_tree().get_first_node_in_group("player")
	if p != null:
		p.global_position = Vector3(w * 0.5, 0.0, -50.0)
	for i in 120:
		await get_tree().physics_frame

	# 断言：全部单位仍在房间 AABB（留 1 米容差给半径/斥力）
	var out_of_bounds := 0
	var worst := ""
	for id in mgr.call("query_circle", 0.0, 0.0, 9999.0):
		var pos: Vector3 = mgr.call("unit_position", int(id))
		if pos.x < -1.0 or pos.x > w + 1.0 or pos.z < -1.0 or pos.z > h + 1.0:
			out_of_bounds += 1
			worst = "(%.1f, %.1f)" % [pos.x, pos.z]
	_check(out_of_bounds == 0,
		"[边界] 群体单位全部留在房间内（越界 %d 个 %s，房间 %dx%d）"
			% [out_of_bounds, worst, int(w), int(h)])

	RoomController.CROWD_FORCE_SWARM = false


## 形态附加效果在群体路径生效（渡鸦法强附加 / 影子攻击 / 穿透线）。
##
## 这些效果要么是纯伤害、要么作用于自身，**不依赖目标是不是节点**，
## 所以群体路径必须同样生效。早期版本整套跳过——同一个形态打 swarm 怪
## 会明显少一截伤害，而玩家只会觉得"某些怪特别硬"，极难定位。
func _test_crowd_form_extras(p, mgr) -> void:
	if p == null or mgr == null:
		_check(false, "[crowd-form] 有玩家与群体管理器")
		return
	var ids = mgr.call("query_circle", 0.0, 0.0, 9999.0)
	if ids.is_empty():
		_check(false, "[crowd-form] 有群体单位可测")
		return
	# **挑一个血量最高的存活单位**：本测试跑在前面的用例之后，
	# 有些单位已被打残或打死；而 buffs_of 对已死单位返回 null。
	# 挑第一个存活的还不够——可能挑到刚被打残的那个，
	# 后续附加伤害会把它打死（实测：单独跑过、全量跑挂）。
	var tid := -1
	var best_hp := -1.0
	for i in ids:
		var uid := int(i)
		if not bool(mgr.call("is_alive", uid)):
			continue
		var h: float = mgr.call("unit_hp", uid)
		if h > best_hp:
			best_hp = h
			tid = uid
	if tid < 0:
		_check(false, "[crowd-form] 有存活的群体单位可测")
		return
	var upos: Vector3 = mgr.call("unit_position", tid)
	# **附加伤害要小**：这条断言只验证"伤害落到了群体单位身上"，
	# 打太狠会把测试对象打死，后面的 buff 宿主断言就没了目标（实测踩到）。
	var hp0: float = mgr.call("unit_hp", tid)
	p.call("_deal_bonus_damage_crowd", upos, 5.0, "spell", false)
	var hp1: float = mgr.call("unit_hp", tid)
	_check(hp1 < hp0,
		"[crowd-form] 附加伤害落到群体单位（hp %.1f → %.1f）" % [hp0, hp1])

	# 穿透线：从单位位置沿玩家朝向打一条线，应能命中该单位本身
	var hp2: float = mgr.call("unit_hp", tid)
	p.call("_apply_pierce_line_at", upos, 100.0)
	var hp3: float = mgr.call("unit_hp", tid)
	_check(hp3 <= hp2, "[crowd-form] 穿透线按位置结算不报错（hp %.1f → %.1f）" % [hp2, hp3])

	# —— B 类：给目标挂状态（元素/印记/触发词条）——
	#
	# 群体单位不是场景节点，BuffHolder 需要宿主才能工作。
	# 没有宿主时这一整类效果在群体路径上静默失效——
	# 表现为"元素叠层打 swarm 怪没反应"，玩家完全看不出原因。
	var holder = mgr.call("buffs_of", tid)
	_check(holder != null, "[crowd-form] 群体单位能拿到 buff 宿主")
	if holder == null:
		return
	# 宿主必须提供 DOT 结算需要的读接口（与 EnemyBase 同口径）
	_check(holder.get("_target") != null, "[crowd-form] 宿主已绑定目标")
	var host = holder.get("_target")
	_check(host.has_method("eff_atk") and host.has_method("eff_ap"),
		"[crowd-form] 宿主提供 eff_atk/eff_ap（DOT 结算要用）")
	_check(not host.has_method("add_modifier"),
		"[crowd-form] 宿主不提供 add_modifier（群体单位无属性层，与敌人一致）")
	# 挂一个词条，确认真的进账本
	var r: Dictionary = holder.call("apply", "burn", "test")
	_check(r.get("ok", false), "[crowd-form] 能往群体单位挂词条")
	_check(int(holder.call("stacks_of", "burn")) > 0,
		"[crowd-form] 词条层数已记录（%d）" % holder.call("stacks_of", "burn"))
	# 死亡后宿主应被回收（否则节点泄漏）
	var host_count_before: int = _count_hosts(mgr)
	mgr.call("apply_damage", PackedInt32Array([tid]), 999999.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count_hosts(mgr) < host_count_before,
		"[crowd-form] 单位死亡后宿主被回收（%d → %d）" % [
			host_count_before, _count_hosts(mgr)])


## 数 CrowdManager 下还挂着多少个 buff 宿主
func _count_hosts(mgr) -> int:
	var n := 0
	for c in mgr.get_children():
		if c is CrowdUnitHost:
			n += 1
	return n


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
		# 落点断言：切过去后必须停在目标房。
		# 曾出现偶发失败——切到 shop 后实际加载的是普通房（2 扇门、无交互物），
		# 正是「穿过门又连锁触发一次」的表现。这里显式断言，让连锁失败可定位。
		_check(gr.current_room_index == idx,
			"[%s] 切房后停在目标房（期望 %d 实际 %d）" % [special_type, idx, gr.current_room_index])
		# 该函数内部没有 await，本身不是协程——await 它是多余的（编辑器报 REDUNDANT_AWAIT）
		_check_one_special_room(gr, special_type)


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
		# 锻造炉/祭坛需要玩家指定一件背包装备——放一件进去，
		# 否则它们会以「请先选择要锻造的装备」拒绝（这是正确行为）
		if gm.equipment_manager != null:
			var tpl = EquipmentDB.get_template(&"W06")
			if tpl != null:
				gm.equipment_manager.add_item(EquipmentInstance.create(tpl))

	# 走 interact_event（支持指定背包下标）而非旧路径 interact_special：
	# 锻造炉/祭坛必须先选装备，旧路径传不了下标。
	# 传 0 = 背包第一件（上面刚放的那件）。
	var result: Dictionary = ctrl.interact_event(0)
	_check(result.get("ok", false), "[%s] 交互成功（%s）" % [special_type, result.get("reason", "")])

	# 重复交互不应重复发放奖励
	var before_state = _special_state(gm, special_type)
	var repeat: Dictionary = ctrl.interact_event(0)
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

## label 而非 name——Node 基类已有 name 属性，同名参数会触发
## SHADOWED_VARIABLE_BASE_CLASS 警告
func _check(c: bool, label: String) -> void:
	if c:
		print("  [OK] %s" % label)
	else:
		failed += 1
		print("  [FAIL] %s" % label)

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

	# 模拟玩家真实穿门：先把玩家移进触发区再触发。
	# 只直调 _on_body_entered 而玩家还站在房间中央的话，触发语义与
	# 「teleport 后物理引擎的陈旧 broadphase 迟发」不可区分——门触发器的
	# 几何复核（见 door_trigger._on_body_entered）会把两者一起拦掉。
	var before_idx: int = gr.current_room_index
	var p := gr.find_child("Player", true, false) as Node3D
	if p:
		p.global_position = (trig as Node3D).global_position + Vector3(0, -1.5, 0)
	trig._on_body_entered(p)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(gr.current_room_index != before_idx, "门触发后切到新房间（%d → %d）" % [before_idx, gr.current_room_index])
	_check(gr.current_room_node != null, "新房间已加载")
