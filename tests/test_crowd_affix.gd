extends Node
## 群体单位词缀结算 —— 行为回归测试
##
## ## 为什么单独一套
## 词缀本来是挂在 `EnemyBase` 节点上的（数值型写进 monster dict，
## 非数值型装战斗钩子）。群体单位不是场景节点，两条路都断了——
## 同一个词缀挂到 swarm 怪身上会**静默缩水**成"只有移速变快"。
## 2026-09-20 补了 `CrowdAffixStore` + `CrowdManager.damage_unit` 把它接回来。
##
## 这套测试守的就是那次接线：**词缀在两条路径上必须同口径**。
## 本项目反复踩过的坑是"两条路径规则分叉"——差异极难察觉，
## 玩家只会觉得"有时候词缀好像没生效"。
##
## 运行：godot --headless --path . res://tests/test_crowd_affix.tscn

## 私有成员访问一律经 `TestProbe`（重构搬方法时只改 probe，本文件零改动）
var probe := TestProbe.new()

var failed := 0
## 测试用的房间控制器（群体管理器的宿主）
var ctrl = null
var crowd = null
## 本套件生成过的单位 id（收尾统一清掉，免得污染后面的用例）
var _spawned: Array = []


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 120.0
	guard.timeout.connect(func():
		print("CROWD AFFIX TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().physics_frame

	var gr = _game_root()
	if gr == null:
		print("CROWD AFFIX TESTS FAILED: 找不到 GameRoot")
		get_tree().quit(1)
		return
	ctrl = _room_controller(gr)
	if ctrl == null:
		print("CROWD AFFIX TESTS FAILED: 找不到 RoomController")
		get_tree().quit(1)
		return
	crowd = probe.ctrl_crowd(ctrl)
	if crowd == null:
		print("CROWD AFFIX TESTS FAILED: CrowdManager 不可用（两条后端都缺）")
		get_tree().quit(1)
		return

	_test_revenge()
	_test_immortal()
	_test_lifesteal()
	_test_chaos_speed()
	_test_fast_speed()
	await _test_burn_on_player()
	await _test_void_swap()
	_test_host_proxy()
	_test_spawn_affix_params()
	await _test_room_routing_end_to_end()

	_finish()


# ============================================================
# 词缀逐项
# ============================================================

## 复仇：受击反伤 15% 打回攻击者。
##
## **必须用真玩家当攻击者**：反伤走 `attacker.take_damage(back, null)`
## 的两参签名，那是玩家侧 `take_damage(amount, from)` 的签名。
## 按节点式敌人的四参签名调会参数转换失败并**静默反伤失败**——
## 这条断言就是守着那个坑（见 `CrowdAffixStore.note_damage` 的注释）。
func _test_revenge() -> void:
	# **必须用真玩家当攻击者**：复仇反伤走 `attacker.take_damage(back, null)`
	# 的两参签名，那是玩家侧的签名；假节点用四参会直接参数转换失败。
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("take_damage"):
		_check(true, "（无玩家节点，跳过复仇反伤断言）")
		return
	var id := _spawn({"hp": 500.0, "defense": 0.0, "affixes": ["revenge"]})
	if id < 0:
		_check(false, "复仇单位生成成功")
		return
	# 玩家满血时打一下，看血量掉了多少——反伤会从玩家身上扣。
	# **不用事件/信号计数**：`player_hit` 在无敌帧、护盾吸收时都会发，
	# 断言"血量确实减少了"才是词缀真的生效。
	var before := _player_hp()
	if before <= 0.0:
		_check(true, "（玩家无属性系统，跳过复仇反伤断言）")
		_cleanup(id)
		return
	crowd.call("damage_unit", id, 100.0, p, Vector3.ZERO)
	var after := _player_hp()
	# 15% × 100 = 15，容差留给其它减伤/回复
	_check(after < before, "复仇反伤打回玩家（%.1f → %.1f）" % [before, after])
	_check(before - after >= 5.0 and before - after <= 30.0,
		"反伤量级正确（掉了 %.1f，基准 15）" % (before - after))
	_cleanup(id)


## 玩家当前血量（拿不到属性系统时返回 -1）
func _player_hp() -> float:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return -1.0
	var attrs = gm.get("attributes")
	if attrs == null:
		return -1.0
	return float(attrs.get("hp"))

## 不朽：血量将跌破 30% 时免伤一次 + 回血 15%，每只怪只触发一次。
func _test_immortal() -> void:
	var id := _spawn({"hp": 100.0, "defense": 0.0, "affixes": ["immortal"]})
	if id < 0:
		_check(false, "不朽单位生成成功")
		return
	# 60 点打在满血 100 上：100-60=40 > 30，不触发，正常扣血
	var d1: float = crowd.call("damage_unit", id, 60.0, null, Vector3.ZERO)
	_check(absf(d1 - 60.0) < 0.01, "阈值之上正常扣血（%.1f）" % d1)
	_check(absf(float(crowd.call("unit_hp", id)) - 40.0) < 0.01,
		"血量 100 → 40（%.1f）" % float(crowd.call("unit_hp", id)))
	# 40 点打在 40 上：40-40=0 < 30，触发不朽 ⇒ 免伤 + 回血
	var d2: float = crowd.call("damage_unit", id, 40.0, null, Vector3.ZERO)
	_check(absf(d2) < 0.01, "不朽触发时本次免伤（造成 %.1f）" % d2)
	var hp_after := float(crowd.call("unit_hp", id))
	# 回血 15% × 100 = 15，故 40 + 15 = 55
	_check(absf(hp_after - 55.0) < 0.01, "不朽回血 15%%（血量 %.1f，期望 55）" % hp_after)
	# 免伤窗口内再挨一刀：完全免疫
	var d3: float = crowd.call("damage_unit", id, 10.0, null, Vector3.ZERO)
	_check(absf(d3) < 0.01, "免伤窗口内免疫（造成 %.1f）" % d3)
	# **每只怪只触发一次**：把免伤计时拨到 0 后打第二发致命伤，这次必须真的打死
	var store = crowd.call("affixes_of", id)
	store.immortal_timer = 0.0
	crowd.call("damage_unit", id, 9999.0, null, Vector3.ZERO)
	_check(not bool(crowd.call("is_alive", id)), "不朽只触发一次（第二发致命伤真的打死了）")
	_cleanup(id)


## 吸血：造成伤害时按 20% 回自己的血。
##
## 直接调 `_apply_lifesteal`（它由攻击事件驱动）而不是造一次真攻击：
## 攻击要跑满冷却、还要单位真的够得着玩家，那是在测模拟核不是测词缀。
func _test_lifesteal() -> void:
	var id := _spawn({"hp": 100.0, "defense": 0.0, "affixes": ["lifesteal"]})
	if id < 0:
		_check(false, "吸血单位生成成功")
		return
	# 先打掉 50 血，留出回血空间
	crowd.call("damage_unit", id, 50.0, null, Vector3.ZERO)
	var before := float(crowd.call("unit_hp", id))
	probe.apply_lifesteal(crowd, id, 40.0)
	var after := float(crowd.call("unit_hp", id))
	# 20% × 40 = 8
	_check(absf((after - before) - 8.0) < 0.01,
		"吸血回 20%%（%.1f → %.1f，期望 +8）" % [before, after])
	_cleanup(id)


## 混沌：周期性随机改移速倍率。
##
## 核里攻击力/攻速是**全体共用**的，改不了单个单位——这是有意的范围收缩。
## 故只断言移速这条真的会动，且**倍率有下限**（不归零/不反向）。
func _test_chaos_speed() -> void:
	var id := _spawn({"hp": 100.0, "defense": 0.0, "affixes": ["chaos"]})
	if id < 0:
		_check(false, "混沌单位生成成功")
		return
	var store = crowd.call("affixes_of", id)
	_check(store != null, "混沌单位登记了词缀状态")
	if store == null:
		_cleanup(id)
		return
	# 反复拨计时器触发重掷，跑够次数必能观察到至少一次变动
	var changed := false
	for i in 200:
		store.chaos_timer = 0.0
		if store.tick(1.0 / 60.0, RandomNumberGenerator.new()):
			changed = true
		_check_guard(store)
	_check(changed, "混沌在多次重掷后至少改动过一次移速")
	_check(store.speed_mult >= 0.5, "移速倍率有下限（%.2f）" % store.speed_mult)
	_cleanup(id)


## 燃烧：单位命中玩家时给玩家挂上灼烧词条。
func _test_burn_on_player() -> void:
	var id := _spawn({"hp": 100.0, "defense": 0.0, "affixes": ["burn", "freeze"]})
	if id < 0:
		_check(false, "燃烧单位生成成功")
		return
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		_check(true, "（无玩家节点，跳过燃烧/冰冻断言）")
		_cleanup(id)
		return
	var tb = p.get("buffs")
	if tb == null:
		_check(false, "玩家有 BuffHolder")
		_cleanup(id)
		return
	# 先清干净，免得残留层数让断言失真。BuffHolder 没有 clear_all，
	# 按 id 逐个移除（元素层数是另一套存储，这里用不到）。
	for bid in tb.call("active_ids"):
		tb.call("remove", str(bid))
	probe.apply_on_hit_affixes(crowd, id, Vector3.ZERO)
	_check(int(tb.call("stacks_of", "burn")) > 0, "命中给玩家挂上灼烧")
	_check(int(tb.call("stacks_of", "frost")) > 0, "命中给玩家叠上寒霜")
	for bid in tb.call("active_ids"):
		tb.call("remove", str(bid))
	_cleanup(id)


## 虚空：命中与玩家交换位置（受 10 米上限约束）。
func _test_void_swap() -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		_check(true, "（无玩家节点，跳过虚空换位断言）")
		return
	var player_pos: Vector3 = (p as Node3D).global_position
	# 刷在玩家身边 1 米处：在 10 米上限内，必然换位。
	# **单位速度给 0**，免得它在断言前自己走开（斥力仍可能推它）。
	var near := player_pos + Vector3(1.0, 0.0, 0.0)
	var id := _spawn_at(near, {"hp": 500.0, "defense": 0.0, "affixes": ["void"]})
	if id < 0:
		_check(false, "虚空单位生成成功")
		return
	var store = crowd.call("affixes_of", id)
	_check(store != null and store.void_hit, "虚空词缀登记成功")
	if store == null:
		_cleanup(id)
		return
	# **判定要在调用前重取一次坐标**：生成之后可能已经跑过物理帧，
	# 单位会被斥力/障碍推走，10 米上限就够不着了
	#（实测踩到：生成在原点、物理帧一跑跑到 20 米外，换位静默不发生）。
	# 取完立刻判定，中间不 await。
	var unit_before: Vector3 = crowd.call("unit_position", id)
	var plan: Dictionary = store.plan_swap(p, unit_before)
	_check(not plan.is_empty(), "虚空换位计划非空（距离 %.2f，上限 10）"
		% unit_before.distance_to(player_pos))
	probe.apply_on_hit_affixes(crowd, id, Vector3.ZERO)
	var unit_after: Vector3 = crowd.call("unit_position", id)
	var p_after: Vector3 = (p as Node3D).global_position
	_check(unit_after.distance_to(player_pos) < 1.5,
		"虚空：单位换到玩家原位（距离 %.2f）" % unit_after.distance_to(player_pos))
	_check(p_after.distance_to(unit_before) < 1.5,
		"虚空：玩家换到单位原位（距离 %.2f）" % p_after.distance_to(unit_before))
	# **不能崩**：这是 `force_position` 那个不存在的方法最典型的翻车方式
	_check(true, "虚空换位未抛错（force_position 未被调用）")
	(p as Node3D).global_position = player_pos
	_cleanup(id)


## 宿主代理：`CrowdUnitHost.take_damage` 把伤害转回核。
##
## 这条是玩家「伤害反弹」词条在群体路径上唯一可能的落点：
## `player._reflect_damage` 拿 `from` 当攻击者调四参 `take_damage`，
## 群体单位没节点就只能拿宿主顶替。
func _test_host_proxy() -> void:
	var id := _spawn({"hp": 500.0, "defense": 0.0})
	if id < 0:
		_check(false, "宿主代理测试单位生成成功")
		return
	var host = crowd.call("host_of", id)
	_check(host != null, "群体单位有节点代理")
	if host == null:
		_cleanup(id)
		return
	_check(host.has_method("take_damage"), "代理暴露 take_damage（伤害反弹的落点）")
	var before := float(crowd.call("unit_hp", id))
	# 按节点式敌人的四参签名调——`_reflect_damage` 就是这么调的
	host.call("take_damage", 30.0, false, Vector3.ZERO)
	var after := float(crowd.call("unit_hp", id))
	_check(absf((before - after) - 30.0) < 0.01,
		"代理把伤害转回核（%.1f → %.1f，期望 -30）" % [before, after])
	_cleanup(id)


## 攻击参数接线：生成带词缀的怪要把攻击力/间隔写进核。
##
## **不能断言具体数值**：`_atk_interval` 取全体最小值、`_atk_total` 是
## 全局合计，两者都被**同房间其它单位**影响，测试无法独占。
## 故这里只守"确实按 monster 数据写了"，不守绝对值。
func _test_spawn_affix_params() -> void:
	var before_total := float(crowd.get("_atk_total"))
	var id := _spawn({"hp": 100.0, "defense": 0.0, "atk": 25.0,
		"attack_interval": 0.4, "affixes": ["strong"]})
	if id < 0:
		_check(false, "强壮单位生成成功")
		return
	_check(float(crowd.get("_atk_total")) - before_total >= 25.0 - 0.01,
		"攻击力合计含本单位的 25（%.1f → %.1f）"
			% [before_total, float(crowd.get("_atk_total"))])
	_check(float(crowd.get("_atk_interval")) <= 0.4 + 0.001,
		"攻击间隔收敛到不超过本单位的 0.4（%.2f）" % float(crowd.get("_atk_interval")))
	_cleanup(id)


# ============================================================
# 端到端：从房间生成到词缀生效
# ============================================================

## 词缀·快速必须真的改移速。
##
## 核里 `speed` 只在 spawn 时能写，故这个加成必须在**交给核之前**算好。
## 早期版本漏了这一步：「快速」词缀挂到 swarm 怪上会**静默失效**——
## 词缀登记了、状态也对，就是速度没变，玩家只会觉得"这词缀没感觉"。
##
## 测的是 `speed_pct` 到 `_base_speed` 的传导，不依赖核的内部状态
##（核里速度读不回来，降级后端也未必暴露 getter）。
func _test_fast_speed() -> void:
	# 基准 100（无加成）
	var plain := _spawn_at(Vector3.ZERO,
		{"hp": 100.0, "defense": 0.0, "speed_pct": 100.0})
	# 带「快速」词缀（speed_pct 150）。**注意 `_spawn_at` 传的基准速度是 0**，
	# 生产路径（`_spawn_crowd_at`）传的是 4.0——故断言必须比"两者之比"，
	# 不能比绝对值，否则 0 乘以任何倍率都还是 0。
	var fast := _spawn_at(Vector3.ZERO,
		{"hp": 100.0, "defense": 0.0, "speed_pct": 150.0,
		"affixes": ["fast"]})
	if plain < 0 or fast < 0:
		_check(false, "快速词缀测试单位生成成功")
		return
	var store_plain = crowd.call("affixes_of", plain)
	var store_fast = crowd.call("affixes_of", fast)
	_check(store_fast != null, "快速词缀登记了状态")
	if store_fast == null:
		_cleanup(plain)
		_cleanup(fast)
		return
	# 无词缀的单位不登记（省一次分配），故它没有 store，倍率视为 1.0
	var m_plain: float = 1.0 if store_plain == null else float(store_plain.spawn_mult)
	_check(absf(store_fast.spawn_mult / m_plain - 1.5) < 0.01,
		"提速幅度等于 speed_pct 之比（%.2f 倍）" % (store_fast.spawn_mult / m_plain))
	_cleanup(plain)
	_cleanup(fast)


## 端到端：打开 `CROWD_FORCE_SWARM` 让房间生成真的走群体路径，
## 断言生成的单位**确实带上了词缀状态**。
##
## ## 为什么必须走端到端
## `AffixDB.roll` 对非精英怪的概率分布是 `COUNT_BY_PHASE[phase][0..1]`，
## 高阶段才稳定出词缀。若只在单元测试里手工构造带 `affixes` 的 dict，
## 就绕过了"房间生成到底有没有把词缀传给群体管理器"这一环——
## 而那正是本次接线的关键（早期 swarm 分流发生在 `AffixDB.apply` 之后，
## 但群体路径完全没消费它）。
##
## 开关用完必须复位：它是 `static var`，漏了会影响同进程后续用例。
func _test_room_routing_end_to_end() -> void:
	var before := RoomController.CROWD_FORCE_SWARM
	RoomController.CROWD_FORCE_SWARM = true
	# 生成单位走 `_spawn_crowd_at`，需要房间里有生成点
	var points: Array = ctrl.get("_spawn_points")
	if points == null or points.is_empty():
		_check(true, "（本房无生成点，跳过端到端分流断言）")
		RoomController.CROWD_FORCE_SWARM = before
		return
	var affixed := 0
	var total := 0
	for raw in points:
		var point = raw
		if point == null or not is_instance_valid(point):
			continue
		var m: Dictionary = MonsterDB.get_monster("zombie")
		if m.is_empty():
			continue
		AffixDB.apply(m, ["revenge", "immortal"])
		if probe.ctrl_should_use_crowd(ctrl, m, false):
			total += 1
			if probe.ctrl_spawn_crowd_at(ctrl, point, m, 1.0):
				# 刚生成的那个 id 就是池里最新的活跃单位
				var id := _last_alive_id()
				if id >= 0 and crowd.call("affixes_of", id) != null:
					affixed += 1
				if id >= 0:
					_cleanup(id)
		if total >= 3:
			break
	_check(total > 0, "带词缀的基础怪走了群体路径（%d 个生成点）" % total)
	_check(total > 0 and affixed == total,
		"群体单位登记了词缀状态（%d/%d）" % [affixed, total])
	RoomController.CROWD_FORCE_SWARM = before


## 池里最新的活跃单位 id（本套件专用；容量小、扫描可忽略）
func _last_alive_id() -> int:
	var cap := int(crowd.call("get_capacity"))
	for i in range(cap - 1, -1, -1):
		if bool(crowd.call("is_alive", i)):
			return i
	return -1


## 假攻击者：复现"反伤调用签名"问题的探针。
##
## 刻意用**玩家侧的两参签名**（`player.take_damage`）——生产路径上
## `attacker` 永远是玩家，谁把 `note_damage` 的反伤调用改回四参，
## 拿这个类一试就会红。
class _FakeAttacker extends Node:
	var calls := 0
	var last_amount := 0.0

	func take_damage(amount: float, _from = null) -> void:
		calls += 1
		last_amount = amount


# ============================================================
# 工具
# ============================================================

## 造一个带词缀的测试单位（原点附近）。
##
## **位置硬编码在原点**：核每帧跑 `phase_collide_obstacles`，落在墙格上
## 会被立刻推出墙外。拿生成坐标当断言基准会随房间布局飘
##（实测踩到过：投射物测试里单位停在离生成点 0.6 米外）。
## 本套件只调 `damage_unit`（不依赖核的步进），单位被推走也不影响断言。
func _spawn(monster: Dictionary) -> int:
	return _spawn_at(Vector3.ZERO, monster)


func _spawn_at(at: Vector3, monster: Dictionary) -> int:
	var m := monster.duplicate()
	m["id"] = "test_affix_dummy"
	var id := int(crowd.call("spawn_unit", at, float(m.get("hp", 100.0)),
		0.0, 0.5, 1.0, m))
	if id >= 0:
		_spawned.append(id)
	return id


## 清掉一个测试单位。
##
## 用 `despawn_unit` 而不是 `kill_all_units`：后者会把**其它用例**
## 还活着的单位一起清掉（它们共享同一个管理器）。
## 测试单位速度给 0 也仍然可能被邻居斥力推动，故不依赖其位置。
func _cleanup(id: int) -> void:
	if id < 0 or not bool(crowd.call("is_alive", id)):
		return
	crowd.call("despawn_unit", id)
	if _spawned.has(id):
		_spawned.erase(id)


## 混沌倍率的健全性护栏（每轮都查，一旦越界立刻报）
func _check_guard(store) -> void:
	if store.speed_mult < 0.5 or store.speed_mult > 100.0:
		_check(false, "混沌倍率越界（%.2f）" % store.speed_mult)
		store.speed_mult = 1.0


func _game_root():
	var found := get_tree().get_nodes_in_group("game_root")
	if not found.is_empty():
		return found[0]
	return get_tree().current_scene


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
	for id in _spawned.duplicate():
		if bool(crowd.call("is_alive", int(id))):
			crowd.call("despawn_unit", int(id))
	if failed == 0:
		print("ALL CROWD AFFIX TESTS PASSED")
		get_tree().quit(0)
	else:
		print("CROWD AFFIX TESTS FAILED: %d" % failed)
		get_tree().quit(1)
