extends Node
## CrowdSim 大规模模拟 —— 行为回归测试
##
## 覆盖实施计划「批次 1」的验收点：位置推进、障碍不穿透、邻居斥力、
## 圆/锥查询、批量伤害与死亡事件。
##
## **无扩展时自动跳过**：本套件依赖编译产物（bin/libcrowd_sim.*.dll），
## 在 CI / 新克隆的机器上不存在。此时打印 SKIP 并视为通过——
## 逻辑正确性由批次 2 的 GDScript fallback 覆盖，性能类断言只在本机跑。
##
## 运行：godot --headless --path . res://tests/test_crowd_sim.tscn

var failed := 0
var skipped := false


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 60.0
	guard.timeout.connect(func():
		print("CROWD SIM TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame

	if not ClassDB.class_exists("CrowdSim"):
		print("CROWD SIM TESTS SKIPPED (无 GDExtension 编译产物)")
		get_tree().quit(0)
		return

	var cs = ClassDB.instantiate("CrowdSim")
	_test_spawn_capacity(cs)
	_test_movement(cs)
	_test_obstacle_blocking(cs)
	_test_repulsion(cs)
	_test_queries(cs)
	_test_damage_and_events(cs)
	_test_double_buffer(cs)

	if failed == 0:
		print("ALL CROWD SIM TESTS PASSED")
		get_tree().quit(0)
	else:
		print("CROWD SIM TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 池容量：spawn 到满返回 -1，despawn 后可复用
func _test_spawn_capacity(cs) -> void:
	cs.call("setup", 64, 2.0)
	_check(int(cs.call("get_capacity")) == 64, "容量按 setup 设定")
	var last := -1
	for i in 64:
		last = int(cs.call("spawn", float(i) * 0.5, 0.0, 10.0, 1.0, 0.3, 1.0))
	_check(last >= 0, "第 64 个 spawn 成功（id=%d）" % last)
	_check(int(cs.call("get_active_count")) == 64, "活跃数 = 64")
	_check(int(cs.call("spawn", 0.0, 0.0, 1.0, 1.0, 0.3, 1.0)) == -1,
		"池满时 spawn 返回 -1（不崩、不越界）")
	# 释放一个后可复用
	cs.call("despawn", 0)
	_check(int(cs.call("get_active_count")) == 63, "despawn 后活跃数 -1")
	_check(int(cs.call("spawn", 0.0, 0.0, 1.0, 1.0, 0.3, 1.0)) >= 0,
		"释放后能重新 spawn")


## 移动：朝目标推进，且不会越过目标
func _test_movement(cs) -> void:
	cs.call("setup", 128, 2.0)
	var id := int(cs.call("spawn", 0.0, 0.0, 100.0, 4.0, 0.35, 1.0))
	var p0: Vector3 = cs.call("get_position", id)
	for i in 60:
		cs.call("step", 1.0 / 60.0, 10.0, 0.0)
	var p1: Vector3 = cs.call("get_position", id)
	_check(p1.x > p0.x + 1.0, "朝玩家推进（x %.2f → %.2f）" % [p0.x, p1.x])
	# 长跑后应停在目标附近而不是穿过
	for i in 600:
		cs.call("step", 1.0 / 60.0, 10.0, 0.0)
	var p2: Vector3 = cs.call("get_position", id)
	_check(absf(p2.x - 10.0) < 1.0, "停在目标附近而非越过（x=%.2f）" % p2.x)


## 障碍：单位不得穿过 AABB 墙（薄墙最容易穿，专门测）
func _test_obstacle_blocking(cs) -> void:
	cs.call("setup", 128, 2.0)
	var ids: Array = []
	var k := 0
	for iy in 8:
		for ix in 6:
			if k >= 48:
				break
			# 全部刷在墙的**近侧**（x < 7.0）；墙在 8.0~8.5
			ids.append(int(cs.call("spawn", float(ix) * 1.1, float(iy) * 1.2,
				100.0, 4.0, 0.35, 1.0)))
			k += 1
	cs.call("set_obstacles", PackedFloat32Array([8.0, -5.0, 8.5, 12.0]))
	for f in 400:
		cs.call("step", 1.0 / 60.0, 20.0, 4.0)
	var crossed := 0
	var max_x := -999.0
	for id in ids:
		var p: Vector3 = cs.call("get_position", id)
		if p.x > max_x:
			max_x = p.x
		if p.x > 8.5:
			crossed += 1
	_check(crossed == 0, "48 只挤在薄墙前 400 帧，无一穿过（最大 x=%.2f）" % max_x)
	_check(max_x < 8.5, "最大 x 仍在墙内边界之内")


## 邻居斥力：朝目标行进中成团但保持分离
##
## **为什么目标要放远**：把 20 只半径 0.35 的单位塞在目标点 0.35 米内，
## 几何上就装不下（总面积 20×0.38=7.7 > π×0.35²=0.38），任何斥力都无解。
## 真实场景是"敌人朝玩家移动中成团"，此时 seek 持续给压力、斥力负责分层，
## 两者配合才形成自然的群体感。故测试用远处目标。
func _test_repulsion(cs) -> void:
	cs.call("setup", 128, 2.0)
	var ids: Array = []
	for i in 20:
		ids.append(int(cs.call("spawn", float(i) * 0.05, 0.0, 100.0, 4.0, 0.35, 1.0)))
	# 目标放远，让 seek 持续施压
	for f in 240:
		cs.call("step", 1.0 / 60.0, 100.0, 0.0)
	var min_d := 999.0
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var pa: Vector3 = cs.call("get_position", ids[a])
			var pb: Vector3 = cs.call("get_position", ids[b])
			var d := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if d < min_d:
				min_d = d
	# 半径和 = 0.7。斥力应把初始完全重叠的一堆分开到接近"刚好接触"
	_check(min_d > 0.5,
		"20 只初始重叠，240 帧行进后最小间距 %.3f > 0.5（接近半径和 0.7）" % min_d)
	# 反向：也不该散成互不相干（斥力只在 NEIGHBOR_RADIUS=1.6 内生效）
	var spread := 0.0
	for id in ids:
		var p: Vector3 = cs.call("get_position", id)
		spread = maxf(spread, absf(p.z))
	_check(spread < 4.0, "群体没有被斥力炸散（横向偏移 %.2f < 4）" % spread)


## 圆查询 / 锥形查询
func _test_queries(cs) -> void:
	cs.call("setup", 256, 2.0)
	# 一排单位沿 x 轴，间距 2
	for i in 10:
		cs.call("spawn", float(i) * 2.0, 0.0, 100.0, 1.0, 0.3, 1.0)
	cs.call("step", 1.0 / 60.0, 0.0, 0.0)   # 建一次哈希，查询才有格子数据
	var c = cs.call("query_circle", 0.0, 0.0, 3.5)
	_check(c.size() >= 2 and c.size() <= 4,
		"圆查询半径 3.5 命中 2~4 个（实际 %d）" % c.size())
	# 锥形：朝 +x，半角 30°，射程 10 → 只应命中 x>0 的
	var cone = cs.call("query_cone", 0.0, 0.0, 1.0, 0.0,
		deg_to_rad(30.0), 10.0)
	_check(cone.size() >= 3, "锥形查询命中前方多个（实际 %d）" % cone.size())
	var all_forward := true
	for id in cone:
		var p: Vector3 = cs.call("get_position", id)
		if p.x < -0.01:
			all_forward = false
	_check(all_forward, "锥形查询只命中朝向一侧")


## 批量伤害 + 死亡事件
func _test_damage_and_events(cs) -> void:
	cs.call("setup", 128, 2.0)
	var ids: Array = []
	for i in 5:
		ids.append(int(cs.call("spawn", float(i), 0.0, 50.0, 1.0, 0.3, 1.0)))
	cs.call("step", 1.0 / 60.0, 0.0, 0.0)
	var hits = cs.call("query_circle", 2.0, 0.0, 10.0)
	_check(hits.size() == 5, "查询到全部 5 个")
	# 半死：每个打 30（剩 20）
	var k1 := int(cs.call("apply_damage", hits, 30.0))
	_check(k1 == 0, "打 30 伤害不死（hp 50→20）")
	_check(cs.call("drain_events").size() == 0, "无死亡则无事件")
	# 补刀
	var k2 := int(cs.call("apply_damage", hits, 30.0))
	_check(k2 == 5, "补刀击杀 5 个（实际 %d）" % k2)
	var evs: Array = cs.call("drain_events")
	_check(evs.size() == 5, "产生 5 条死亡事件（实际 %d）" % evs.size())
	if evs.size() > 0:
		var e: Dictionary = evs[0]
		_check(str(e.get("type", "")) == "death", "事件类型为 death")
		_check(e.get("pos") is Vector3, "事件带世界坐标")
	_check(int(cs.call("get_active_count")) == 0, "全部死亡后活跃数为 0")
	_check(cs.call("drain_events").size() == 0, "事件取走后清空（不重复消费）")


## 双缓冲：step 后读缓冲切换，渲染数据取自已完成的那份
func _test_double_buffer(cs) -> void:
	cs.call("setup", 64, 2.0)
	var id := int(cs.call("spawn", 0.0, 0.0, 100.0, 4.0, 0.35, 1.0))
	cs.call("step", 1.0 / 60.0, 10.0, 0.0)
	var after_one: Vector3 = cs.call("get_position", id)
	cs.call("step", 1.0 / 60.0, 10.0, 0.0)
	var after_two: Vector3 = cs.call("get_position", id)
	_check(after_two.x > after_one.x, "连续 step 位置持续推进（双缓冲未丢帧）")
	# 渲染缓冲：12 float/实例，未存活的缩放写 0
	var buf = cs.call("get_render_buffer")
	_check(buf.size() == 64 * 12, "渲染缓冲尺寸 = 容量 × 12")
	_check(absf(buf[id * 12 + 0]) > 0.01, "存活实例的缩放非 0")
	var dead_slot := 63
	_check(absf(buf[dead_slot * 12 + 0]) < 0.001,
		"未存活实例的缩放为 0（MultiMesh 不渲染）")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
