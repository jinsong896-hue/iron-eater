extends Node
## 投射物管理器接线 —— 端到端（需要真实房间与 autoload）
##
## 覆盖「核 ↔ 场景」之间的接线，这是 `test_projectile_sim`（测核本身）
## 与 `test_element_buff`（测旧 Area3D 路径）都覆盖不到的一层：
##   · ProjectileManager 是否随房间创建并加入 group
##   · 分流开关打开后，Projectile.spawn 是否真的走核
##   · 目标表是否正确组装（节点式敌人 / 群体单位批量坐标）
##   · 命中事件是否正确接回伤害链路（敌人真的掉血）
##
## **为什么单独一个套件**：核的单元测试证明"核算得对"，
## 但"核算的结果有没有接回游戏"是另一回事——接错了核照样全绿。
##
## 运行：godot --headless --path . res://tests/test_projectile_manager.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 60.0
	guard.timeout.connect(func():
		print("PROJECTILE MANAGER TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	if gr == null:
		_check(false, "GameRoot 就绪")
		_finish(); return
	_check(true, "GameRoot 就绪")

	# 找一个普通房并进入（投射物管理器在 activate() 里创建）
	var idx := -1
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "normal":
			idx = i
			break
	if idx < 0:
		_check(false, "有普通房可测")
		_finish(); return
	gr._transition_to_room(idx)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	await _test_manager_exists(gr)
	await _test_spawn_routes_to_core(gr)
	await _test_hit_damages_enemy(gr)
	await _test_hit_damages_crowd(gr)
	await _test_explode_damages_crowd(gr)

	# 恢复默认（避免影响同进程内的其他测试）
	Projectile.USE_SIM_CORE = false
	_finish()


## 管理器随房间创建并加入组（分流靠这个组找它）
func _test_manager_exists(gr) -> void:
	var found := get_tree().get_nodes_in_group("projectile_manager")
	_check(found.size() > 0, "房间激活后存在投射物管理器（%d 个）" % found.size())
	if found.is_empty():
		return
	var mgr = found[0]
	_check(mgr.has_method("spawn_from_data"), "管理器暴露 spawn_from_data")
	_check(mgr.call("backend_name") != "", "后端可用（%s）" % mgr.call("backend_name"))


## 分流开关打开后，Projectile.spawn 走核（返回 null，但核里有活跃投射物）
func _test_spawn_routes_to_core(gr) -> void:
	var found := get_tree().get_nodes_in_group("projectile_manager")
	if found.is_empty():
		_check(false, "有管理器可测")
		return
	var mgr = found[0]
	var before := int(mgr.get("active"))
	Projectile.USE_SIM_CORE = true
	var host := Node3D.new()
	add_child(host)
	# 朝无目标方向发射，只验证"进了核"
	var ret = Projectile.spawn({
		"direction": Vector3(1, 0, 0), "position": Vector3(0, 1, 0),
		"speed": 5.0, "damage": 7.0, "lifetime": 2.0,
	}, host, Projectile.TARGET_ENEMY)
	await get_tree().physics_frame
	var after := int(mgr.get("active"))
	_check(ret == null, "分流后 Projectile.spawn 返回 null（核里不是节点）")
	_check(after > before, "核里活跃投射物增加（%d → %d）" % [before, after])
	host.queue_free()


## 命中事件接回伤害链路：敌人在子弹路径上时应掉血
func _test_hit_damages_enemy(gr) -> void:
	var found := get_tree().get_nodes_in_group("projectile_manager")
	if found.is_empty():
		_check(false, "有管理器可测")
		return
	var mgr = found[0]
	# 造一只测试敌人
	var enemies := get_tree().get_nodes_in_group("enemies")
	var target = null
	for e in enemies:
		if e is Node3D and is_instance_valid(e) and e.has_method("take_damage"):
			if e.get("prop_kind") == null:
				target = e
				break
	if target == null:
		_check(true, "（本房无敌人，跳过命中结算测试）")
		return
	var hp_before := float(target.get("_hp"))
	# 在敌人位置发射一发（起点就在它身上，立刻命中）
	var host := Node3D.new()
	add_child(host)
	Projectile.spawn({
		"direction": Vector3(1, 0, 0), "position": target.global_position,
		"speed": 1.0, "damage": 15.0, "lifetime": 1.0,
	}, host, Projectile.TARGET_ENEMY)
	# 等几个物理帧让核 step + 事件回流
	for i in 4:
		await get_tree().physics_frame
	var hp_after := float(target.get("_hp"))
	_check(hp_after < hp_before,
		"核的命中事件接回了伤害链路（hp %.1f → %.1f）" % [hp_before, hp_after])
	host.queue_free()


## 投射物必须能打死**群体单位**（不是场景节点）。
##
## 这条覆盖一个真实断链：`_sync_targets` 早就把群体单位喂进了核的目标表，
## 但 (a) `CrowdManager` 没有 `get_position_buffer` 转发方法，
## (b) 命中事件回来时 `_resolve("crowd")` 返回 null——
## 子弹会**命中并消失但零伤害**，玩家看到弹幕穿群而过毫无反应。
## 两条都在 2026-09-19 修掉，这条守住。
func _test_hit_damages_crowd(gr) -> void:
	var found := get_tree().get_nodes_in_group("projectile_manager")
	if found.is_empty():
		_check(false, "有管理器可测")
		return
	var mgr = found[0]
	var ctrl = _room_controller(gr)
	if ctrl == null:
		_check(true, "（无 RoomController，跳过群体命中测试）")
		return
	var crowd = ctrl.call("_crowd")
	if crowd == null:
		_check(true, "（无 CrowdManager，跳过群体命中测试）")
		return

	# 群体管理器必须有批量坐标接口——没有它投射物看不到群体单位
	_check(crowd.has_method("get_position_buffer"),
		"CrowdManager 暴露 get_position_buffer")

	# 在玩家附近刷一个群体单位（离原点远一点，避免与地图自带怪重叠）
	var at := Vector3(6.0, 0.0, 6.0)
	var id := int(crowd.call("spawn_unit", at, 500.0, 0.0, 0.5, 1.0,
		{"id": "test_crowd_dummy", "hp": 500.0, "defense": 0.0}))
	if id < 0:
		_check(false, "群体单位生成成功")
		return
	_check(true, "群体单位生成成功（id=%d）" % id)

	# 等一帧让 _sync_targets 把它收进目标表
	await get_tree().physics_frame
	var buf: PackedFloat32Array = crowd.call("get_position_buffer")
	_check(buf.size() >= 4, "批量坐标缓冲非空（%d 个 float）" % buf.size())

	var hp_before := float(crowd.call("unit_hp", id))
	var host := Node3D.new()
	add_child(host)
	# 起点就在单位身上，立刻命中
	Projectile.spawn({
		"direction": Vector3(1, 0, 0), "position": at,
		"speed": 1.0, "damage": 25.0, "lifetime": 1.0,
	}, host, Projectile.TARGET_ENEMY)
	for i in 6:
		await get_tree().physics_frame
	var hp_after := float(crowd.call("unit_hp", id))
	_check(hp_after < hp_before,
		"投射物对群体单位造成伤害（hp %.1f → %.1f）" % [hp_before, hp_after])
	host.queue_free()
	crowd.call("despawn_unit", id)


## 引信爆炸必须波及**群体单位**。
##
## 覆盖另一条真实断链：`_deal_explode` 只遍历 `_all_targets()`（场景节点），
## 群体单位不在场景树里 → 炸弹在怪堆中心炸开，节点式精英掉血、
## 群体单位毫发无伤。近战的 AOE 早就打群体单位了，只有投射物爆炸漏了。
func _test_explode_damages_crowd(gr) -> void:
	var found := get_tree().get_nodes_in_group("projectile_manager")
	if found.is_empty():
		_check(false, "有管理器可测")
		return
	var mgr = found[0]
	var ctrl = _room_controller(gr)
	if ctrl == null:
		_check(true, "（无 RoomController，跳过爆炸波及测试）")
		return
	var crowd = ctrl.call("_crowd")
	if crowd == null:
		_check(true, "（无 CrowdManager，跳过爆炸波及测试）")
		return

	# 两个单位：一个在爆心 0.5 米内（应被波及），一个在 6 米外（不该被波及）
	var at := Vector3(14.0, 0.0, 14.0)
	var near_id := int(crowd.call("spawn_unit", at, 500.0, 0.0, 0.5, 1.0,
		{"id": "test_boom_near", "hp": 500.0, "defense": 0.0}))
	var far_id := int(crowd.call("spawn_unit", at + Vector3(6.0, 0.0, 0.0), 500.0, 0.0, 0.5, 1.0,
		{"id": "test_boom_far", "hp": 500.0, "defense": 0.0}))
	if near_id < 0 or far_id < 0:
		_check(false, "爆炸测试的两个群体单位生成成功")
		return
	_check(true, "爆炸测试的两个群体单位生成成功")

	await get_tree().physics_frame
	var near_before := float(crowd.call("unit_hp", near_id))
	var far_before := float(crowd.call("unit_hp", far_id))

	var host := Node3D.new()
	add_child(host)
	# 极短引信：出生即炸（与 4-16 炎骨弓手 arrow_explode 同款参数）
	Projectile.spawn({
		"direction": Vector3(1, 0, 0), "position": at,
		"speed": 1.0, "damage": 5.0, "lifetime": 1.0,
		"fuse": 0.05, "explode_radius": 2.0, "explode_damage": 30.0,
	}, host, Projectile.TARGET_ENEMY)
	for i in 8:
		await get_tree().physics_frame

	var near_after := float(crowd.call("unit_hp", near_id))
	var far_after := float(crowd.call("unit_hp", far_id))
	_check(near_after < near_before,
		"爆炸波及半径内的群体单位（hp %.1f → %.1f）" % [near_before, near_after])
	_check(is_equal_approx(far_after, far_before),
		"爆炸不波及半径外的群体单位（hp %.1f）" % far_after)
	host.queue_free()
	crowd.call("despawn_unit", near_id)
	crowd.call("despawn_unit", far_id)


## 从 GameRoot 取当前房的 RoomController
func _room_controller(gr):
	var room = gr.get("current_room_node")
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null("RoomController")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)


func _finish() -> void:
	if failed == 0:
		print("ALL PROJECTILE MANAGER TESTS PASSED")
		get_tree().quit(0)
	else:
		print("PROJECTILE MANAGER TESTS FAILED: %d" % failed)
		get_tree().quit(1)
