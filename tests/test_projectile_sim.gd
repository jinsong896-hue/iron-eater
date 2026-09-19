extends Node
## 投射物模拟核 —— 行为回归（双后端）
##
## 覆盖 `ProjectileCore` 的核心行为：
##   ① 直线推进        ② 弧线（y 轴抛物线，命中判定含 y）
##   ③ 命中事件        ④ 穿透        ⑤ 弹射转向
##   ⑥ 引信冻结 + 爆炸  ⑦ 目标阵营过滤  ⑧ 去重（同一目标不重复命中）
##
## **双后端**：有 C++ 扩展时测真扩展（4096 容量），无编译产物时自动改测
## `ProjectileSimFallback`（纯 GDScript，256 容量）。逻辑正确性在两种环境
## 下都被验证，而不是整片 SKIP。
##
## 运行：godot --headless --path . res://tests/test_projectile_sim.tscn

var failed := 0
var cap := 0

## 阵营常量（与 C++ 侧一致：0 = 打敌人，1 = 打玩家）
const FACTION_ENEMY := 0
const FACTION_PLAYER := 1


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 60.0
	guard.timeout.connect(func():
		print("PROJECTILE SIM TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	var sim := ProjectileSimLoader.create()
	if sim == null:
		print("PROJECTILE SIM TESTS FAILED: 两条后端都不可用")
		get_tree().quit(1)
		return
	add_child(sim)
	cap = ProjectileSimLoader.capacity_limit()
	print("后端：%s（容量上限 %d）" % [ProjectileSimLoader.backend_name(), cap])

	_test_spawn_and_advance(sim)
	_test_target_faction_filter(sim)
	_test_pierce(sim)
	_test_dedupe(sim)
	_test_arc_has_y(sim)
	_test_fuse_explode(sim)
	_test_expire_without_fuse(sim)
	_test_split(sim)
	_test_full_capacity(sim)
	_test_packed_events(sim)

	if failed == 0:
		print("ALL PROJECTILE SIM TESTS PASSED")
		get_tree().quit(0)
	else:
		print("PROJECTILE SIM TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 直线推进：位置按 速度×时间 前进
func _test_spawn_and_advance(sim) -> void:
	sim.call("setup", mini(cap, 64))
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 2.0, "faction": FACTION_ENEMY,
	}))
	_check(id >= 0, "spawn 成功（id=%d）" % id)
	_check(int(sim.call("get_active_count")) == 1, "活跃数 1")
	sim.call("step", 0.1)
	var p: Vector3 = sim.call("get_position", id)
	_check(absf(p.x - 1.0) < 0.01, "0.1 秒后前进 1.0（实际 %.2f）" % p.x)
	_check(absf(p.z) < 0.01, "未偏离 z 轴（%.2f）" % p.z)
	# 池满返回 -1
	for i in mini(cap, 64) - 1:
		sim.call("spawn", {"dx": 1.0, "speed": 1.0})
	_check(int(sim.call("spawn", {"dx": 1.0})) == -1, "池满时 spawn 返回 -1")


## 目标阵营过滤：只打同阵营
func _test_target_faction_filter(sim) -> void:
	sim.call("setup", mini(cap, 64))
	sim.call("clear_targets")
	# 一发打敌人的子弹，目标是「玩家阵营」→ 不该命中
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 2.0, "faction": FACTION_ENEMY,
	}))
	# 目标就在路径上（x=1, z=0），但阵营是 PLAYER
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 1.0, 100.0]),
		PackedInt32Array([FACTION_PLAYER]))
	sim.call("step", 0.1)
	var evs: Array = sim.call("drain_events")
	_check(evs.is_empty(), "阵营不符时不产生命中事件（%d 条）" % evs.size())
	sim.call("despawn", id)

	# 换成同阵营 → 应命中
	var id2 := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 2.0, "faction": FACTION_ENEMY,
	}))
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 1.0, 100.0]),
		PackedInt32Array([FACTION_ENEMY]))
	sim.call("step", 0.1)
	var evs2: Array = sim.call("drain_events")
	_check(evs2.size() == 1, "阵营相符时命中（%d 条）" % evs2.size())
	if evs2.size() > 0:
		var e: Dictionary = evs2[0]
		_check(str(e.get("type", "")) == "hit", "事件类型为 hit")
		_check(int(e.get("target_id", -1)) == 100, "事件带目标 ref（%d）" % e.get("target_id"))
		_check(absf(float(e.get("damage", 0.0)) - 5.0) < 0.01, "事件带伤害值")


## 穿透：pierce N ⇒ 可打 N+1 个目标后才消失
func _test_pierce(sim) -> void:
	sim.call("setup", mini(cap, 64))
	# 3 个目标沿路径排开，穿透 1（即可打 2 个）
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 0.5, 1.0,  2.0, 0.0, 0.5, 2.0,  3.0, 0.0, 0.5, 3.0]),
		PackedInt32Array([FACTION_ENEMY, FACTION_ENEMY, FACTION_ENEMY]))
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 20.0, "damage": 5.0, "lifetime": 2.0,
		"faction": FACTION_ENEMY, "pierce": 1,
	}))
	# 跑足够久让它穿过全部目标
	for i in 20:
		sim.call("step", 0.02)
	var evs: Array = sim.call("drain_events")
	var hits := 0
	for e in evs:
		if str((e as Dictionary).get("type", "")) == "hit":
			hits += 1
	_check(hits == 2, "穿透 1 时命中 2 个（实际 %d）" % hits)
	_check(not bool(sim.call("is_alive", id)), "打满 2 个后子弹消失")


## 去重：同一目标只结算一次（即使子弹停在它身上）
func _test_dedupe(sim) -> void:
	sim.call("setup", mini(cap, 64))
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 2.0, 7.0]),
		PackedInt32Array([FACTION_ENEMY]))
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 1.0, "damage": 5.0, "lifetime": 5.0,
		"faction": FACTION_ENEMY, "pierce": 9,
	}))
	# 目标半径 2.0，子弹会长时间停在范围内 —— 但只该命中一次
	for i in 30:
		sim.call("step", 0.05)
	var evs: Array = sim.call("drain_events")
	var hits := 0
	for e in evs:
		if str((e as Dictionary).get("type", "")) == "hit":
			hits += 1
	_check(hits == 1, "同一目标只命中一次（实际 %d）" % hits)
	sim.call("despawn", id)


## 弧线必须有 y：抛物线中途离地，落点回到 0
func _test_arc_has_y(sim) -> void:
	sim.call("setup", mini(cap, 64))
	sim.call("clear_targets")
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 2.0,
		"faction": FACTION_ENEMY, "arc": true, "arc_height": 3.0,
	}))
	# 跑到一半（t=0.5 时 y 应为 4h·0.25 = h）
	sim.call("step", 1.0)
	var mid: Vector3 = sim.call("get_position", id)
	_check(mid.y > 1.0, "弧线中途离地（y=%.2f > 1）" % mid.y)
	_check(absf(mid.y - 3.0) < 0.1, "t=0.5 时 y ≈ 弧高 3.0（实际 %.2f）" % mid.y)
	# 跑到终点 y 应回到 0
	sim.call("step", 1.0)
	var end: Vector3 = sim.call("get_position", id)
	_check(end.y < 0.1, "弧线终点落回地面（y=%.2f）" % end.y)


## 引信：到期后冻结移动，倒计时结束爆炸并消失
func _test_fuse_explode(sim) -> void:
	sim.call("setup", mini(cap, 64))
	sim.call("clear_targets")
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 0.5,
		"faction": FACTION_ENEMY, "fuse": 1.0,
		"explode_radius": 3.0, "explode_damage": 20.0,
	}))
	# 跑到 lifetime 耗尽 → 进入引信（冻结）
	sim.call("step", 0.6)
	_check(bool(sim.call("is_fuse_armed", id)), "lifetime 耗尽后进入引信")
	var frozen: Vector3 = sim.call("get_position", id)
	sim.call("step", 0.3)
	var still: Vector3 = sim.call("get_position", id)
	_check(frozen.distance_to(still) < 0.01, "引信期冻结移动（%.3f）" % frozen.distance_to(still))
	# 引信倒计时结束 → 爆炸
	sim.call("step", 0.8)
	var evs: Array = sim.call("drain_events")
	var exploded := false
	for e in evs:
		if str((e as Dictionary).get("type", "")) == "explode":
			exploded = true
			_check(absf(float((e as Dictionary).get("explode_radius", 0.0)) - 3.0) < 0.01,
				"爆炸事件带半径")
	_check(exploded, "引信到期触发爆炸")
	_check(not bool(sim.call("is_alive", id)), "爆炸后子弹消失")


## 无引信的子弹到期直接消失（发 expire 事件）
func _test_expire_without_fuse(sim) -> void:
	sim.call("setup", mini(cap, 64))
	sim.call("clear_targets")
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 10.0, "damage": 5.0, "lifetime": 0.2, "faction": FACTION_ENEMY,
	}))
	sim.call("step", 0.3)
	var evs: Array = sim.call("drain_events")
	var expired := false
	for e in evs:
		if str((e as Dictionary).get("type", "")) == "expire":
			expired = true
	_check(expired, "到期发 expire 事件")
	_check(not bool(sim.call("is_alive", id)), "到期后子弹消失")
	_check(int(sim.call("get_active_count")) == 0, "活跃数归零")


## 分裂：命中时散射 N 枚小弹，且**只分裂一次**（防无限繁殖）
func _test_split(sim) -> void:
	sim.call("setup", mini(cap, 64))
	# 一个目标在路径上，让母弹命中触发分裂
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 0.5, 1.0]),
		PackedInt32Array([FACTION_ENEMY]))
	var id := int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 20.0, "damage": 10.0, "lifetime": 2.0,
		"faction": FACTION_ENEMY, "pierce": 9,
		"split_count": 3, "split_pct": 0.5, "split_spread": 0.35,
	}))
	_check(int(sim.call("get_active_count")) == 1, "分裂前只有母弹")
	sim.call("step", 0.05)
	# 命中后应多出 3 枚小弹
	var n := int(sim.call("get_active_count"))
	_check(n == 4, "命中后散射出 3 枚小弹（活跃 %d，期望 4）" % n)
	# 小弹伤害是母弹的一半
	var child_dmg := -1.0
	for i in mini(cap, 64):
		if i != id and bool(sim.call("is_alive", i)):
			child_dmg = float(sim.call("get_damage", i))
			break
	_check(absf(child_dmg - 5.0) < 0.01,
		"小弹伤害 = 母弹 × 50%%（实际 %.1f）" % child_dmg)
	# 小弹不该再分裂（否则无限繁殖）——再跑一段，数量只减不增
	for i in 30:
		sim.call("step", 0.05)
	_check(int(sim.call("get_active_count")) <= 4,
		"小弹不再分裂（活跃 %d ≤ 4）" % int(sim.call("get_active_count")))


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)


## 满容量：打满池子后 step 仍正确推进、不崩、事件可消费。
##
## 加这条的背景：核容量 4096，但此前所有测试最多只跑到 64 发，
## **弹幕规模从未被验证过**。压测时发现逐事件 Dictionary 编组
## 在 4096 发下要 15 ms/帧（见 _test_packed_events），
## 这条则守住"满容量下行为仍正确"这一底线。
func _test_full_capacity(sim) -> void:
	sim.call("setup", cap)
	sim.call("set_targets", PackedFloat32Array(), PackedInt32Array())
	var spawned := 0
	for i in cap:
		var a := TAU * float(i) / float(cap)
		var id := int(sim.call("spawn", {
			"x": 0.0, "y": 0.0, "z": 0.0,
			"dx": cos(a), "dz": sin(a),
			"speed": 12.0, "damage": 10.0, "lifetime": 5.0,
			"faction": FACTION_ENEMY, "pierce": 0,
		}))
		if id >= 0:
			spawned += 1
	_check(spawned == cap, "满容量可全部生成（%d/%d）" % [spawned, cap])
	_check(int(sim.call("get_active_count")) == cap, "活跃数 = 容量")

	# 满容量 step 不应崩，且事件量级合理
	var t0 := Time.get_ticks_usec()
	sim.call("step", 1.0 / 60.0)
	var step_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(step_ms < 50.0, "满容量 step 未卡死（%.2f ms）" % step_ms)

	# 池满时再生成应被拒绝而不是越界
	_check(int(sim.call("spawn", {
		"x": 0.0, "y": 0.0, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 1.0, "damage": 1.0, "lifetime": 1.0,
		"faction": FACTION_ENEMY, "pierce": 0,
	})) == -1, "池满时 spawn 返回 -1（不越界）")
	sim.call("clear")


## 扁平事件流与逐事件 Dictionary **语义等价**。
##
## 两条接口会并存一段时间（旧测试仍用 Dictionary），必须保证
## 同一局面下两者报出的内容一致，否则调用方切到扁平接口会静默丢字段。
func _test_packed_events(sim) -> void:
	var stride := ProjectileManager.EVENT_STRIDE
	sim.call("setup", mini(cap, 64))
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 0.5, 7.0]),
		PackedInt32Array([FACTION_ENEMY]))
	sim.call("spawn", {
		"x": 0.0, "y": 0.5, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 20.0, "damage": 7.0, "lifetime": 5.0,
		"faction": FACTION_ENEMY, "pierce": 0, "elem": 3,
	})
	sim.call("step", 0.05)

	var dicts: Array = sim.call("drain_events")
	# 重放同一发子弹，取扁平流
	sim.call("setup", mini(cap, 64))
	sim.call("set_targets",
		PackedFloat32Array([1.0, 0.0, 0.5, 7.0]),
		PackedInt32Array([FACTION_ENEMY]))
	sim.call("spawn", {
		"x": 0.0, "y": 0.5, "z": 0.0, "dx": 1.0, "dz": 0.0,
		"speed": 20.0, "damage": 7.0, "lifetime": 5.0,
		"faction": FACTION_ENEMY, "pierce": 0, "elem": 3,
	})
	sim.call("step", 0.05)
	var flat: PackedFloat32Array = sim.call("drain_events_packed")

	_check(dicts.size() > 0, "逐事件接口报出了事件（%d 个）" % dicts.size())
	_check(flat.size() == dicts.size() * stride,
		"扁平流长度 = 事件数 × %d（%d = %d × %d）"
		% [stride, flat.size(), dicts.size(), stride])
	if flat.size() != dicts.size() * stride or dicts.is_empty():
		return

	# 逐字段核对第一对
	var d: Dictionary = dicts[0]
	var p: Vector3 = d.get("pos", Vector3.ZERO)
	var type_id: int = {"hit": 0, "explode": 1, "expire": 2}.get(str(d.get("type", "")), 2)
	_check(int(flat[0]) == type_id, "type 一致（%d）" % type_id)
	_check(int(flat[1]) == int(d.get("id", -1)), "id 一致")
	_check(absf(flat[2] - p.x) < 0.001 and absf(flat[3] - p.y) < 0.001
			and absf(flat[4] - p.z) < 0.001, "位置一致")
	_check(int(flat[5]) == int(d.get("target_id", -1)), "target_id 一致")
	_check(absf(flat[6] - float(d.get("damage", 0.0))) < 0.001, "damage 一致")
	_check(int(flat[7]) == int(d.get("elem", -1)), "elem 一致")
	_check((flat[10] != 0.0) == bool(d.get("has_zone", false)), "has_zone 一致")

	# 取走后必须清空（两条接口共用同一队列）
	var again: PackedFloat32Array = sim.call("drain_events_packed")
	_check(again.size() == 0, "扁平流取走后队列清空")
	sim.call("clear")
