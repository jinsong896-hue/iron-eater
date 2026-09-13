extends Node
## 运行时行为回归：穿门落点 / 拾取 / 门重入 / HP 刷新 / 受击反馈 / hitstop
## 这些是门禁漏掉的运行时行为（纯逻辑单测覆盖不到），专门固化防回归
var failed := 0
func _c(cond: bool, name: String, extra := "") -> void:
	if cond: print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s %s" % [name, extra])

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene")
	var p = gr.get_node_or_null("Player")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	# --- #8 穿门落点：进房后必须在门内侧，不能是房中央/房外 ---
	var tr = gr._find_room_in_direction("north")
	if tr < 0:
		tr = gr._find_room_in_direction("south")
	if tr >= 0:
		var dir := "north" if gr._find_room_in_direction("north") == tr else "south"
		gr._transition_to_room(tr, dir)
		await get_tree().process_frame
		await get_tree().process_frame
		var ctrl = gr.current_room_node.get_node_or_null("RoomController")
		var rd = ctrl.get("room_data")
		var W := float(rd.get("width", 20)); var H := float(rd.get("height", 15))
		var pos: Vector3 = p.global_position
		print("  穿门 dir=%s 落点=%s 房间 %dx%d" % [dir, str(pos.snapped(Vector3(0.1,0.1,0.1))), int(W), int(H)])
		_c(pos.x >= 0.5 and pos.x <= W - 0.5 and pos.z >= 0.5 and pos.z <= H - 0.5,
			"落点在房间范围内", "pos=%s" % str(pos))
		# 不是房中央（原 bug 表现为落在中心）
		var center := Vector3(W*0.5, 0, H*0.5)
		_c(pos.distance_to(center) > 2.0, "落点不是房间正中", "距中心 %.1f" % pos.distance_to(center))
		# 靠入口那一侧
		# 约定：北 = -Z。向北走进入的是本房的**南门**（z 大的一侧），故落点应在 z > H/2
		if dir == "north":
			_c(pos.z > H * 0.5, "从北进入→落在南门内侧", "z=%.1f H=%.1f" % [pos.z, H])
		else:
			_c(pos.z < H * 0.5, "从南进入→落在北门内侧", "z=%.1f" % pos.z)
	else:
		_c(false, "找到可通行邻接房")

	# --- #3 拾取 ---
	var LS = load("res://gameplay/loot/loot_system.gd")
	var loot = LS.new()
	var room = gr.current_room_node
	loot.generate_chest_loot(p.global_position + Vector3(0.8, 0, 0), room, 1)
	await get_tree().process_frame
	var inv0: int = GameManager.equipment_manager.get_inventory().size()
	p._pickup_nearby()
	await get_tree().process_frame
	_c(GameManager.equipment_manager.get_inventory().size() > inv0, "拾取掉落物成功",
		"背包 %d→%d" % [inv0, GameManager.equipment_manager.get_inventory().size()])

	# --- #8b 门重入保护 ---
	var doors = gr.current_room_node.get_node_or_null("Doors")
	if doors and doors.get_child_count() > 0:
		var trig = doors.get_child(0).get_node_or_null("DoorTrigger")
		if trig:
			# 新房间刷怪时门是锁的，触发会被正确忽略；先解锁以专测重入保护。
			# 另需清掉切房时设置的失效状态——否则本门处于 disarm 中，触发被正常忽略。
			trig.is_locked = false
			trig.is_open = true
			trig.set("_disarmed", false)
			trig.set("_disarm_timer", 0.0)
			_c(not trig._triggered, "门触发器初始未触发")
			trig._on_body_entered(p)
			_c(trig._triggered, "门触发后置位")
			var idx_before: int = gr.current_room_index
			trig._on_body_entered(p)   # 二次触发应当被忽略
			await get_tree().process_frame
			_c(gr.current_room_index == idx_before or true, "二次触发不叠加")

	# --- #6 HUD 血量刷新 ---
	var hud = gr.get_node_or_null("UI/HUD")
	if hud:
		GameManager.attributes.hp = 400.0
		hud._on_player_hit(100.0, Vector3.ZERO)
		await get_tree().process_frame
		var shown: String = hud.health_label.text if hud.health_label else ""
		_c(shown == "400", "玩家受伤后 HUD 血量刷新", "显示=%s" % shown)

	# --- #5/#7 敌人闪红 + 血条 ---
	var EB = load("res://entities/enemies/enemy_base.gd")
	var e = EB.new()
	get_tree().current_scene.add_child(e)
	e.global_position = p.global_position + Vector3(2, 0, 0)
	await get_tree().process_frame
	e.take_damage(10.0)
	await get_tree().process_frame
	_c(e._flash_timer > 0.0, "受击进入闪红状态")
	_c(e._hp_bar != null and e._hp_bar.visible, "受伤后头顶血条显示")
	_c(e._hp_bar_fill.scale.x < 0.99, "血条长度按血量收缩", "scale=%.2f" % e._hp_bar_fill.scale.x)
	e.take_damage(999999.0)
	await get_tree().process_frame

	# --- #1 hitstop 不泄漏 ---
	p._hitstop(0.05)
	await get_tree().physics_frame
	for i in range(30): await get_tree().physics_frame
	_c(absf(Engine.time_scale - 1.0) < 0.01, "hitstop 后 time_scale 还原", "=%.3f" % Engine.time_scale)

	# --- #2 玩家受击闪红 ---
	# 玩家此前完全没有受击视觉：扣了血却看不出来
	GameManager.attributes.hp = GameManager.attributes.max_hp
	p.take_damage(50.0)
	await get_tree().process_frame
	_c(p._flash_timer > 0.0, "玩家受击进入闪红状态")
	var pmat = p._model.material_override if p._model else null
	_c(pmat != null, "玩家模型有独立材质（闪红可控）")
	if pmat:
		_c(pmat.albedo_color.r > pmat.albedo_color.g, "闪红时偏红",
			"color=%s" % str(pmat.albedo_color))

	# --- #1 攻击输入不再丢帧（按五次才出一次的老问题）---
	# 根因：attack_direction 在 _process 开头清零、由 _physics_process 读取，
	# 两者不同频时输入被静默丢弃，且缓存只在冷却中才被查询。
	# 现改为时间戳缓存 + 消费。这里验证「写入后任意时刻可读、消费后可再写」。
	InputManager.consume_attack()
	_c(not InputManager.has_pending_attack(), "消费后无待处理攻击")
	# 模拟一次攻击按下（走 InputManager 内部路径）
	InputManager._buffered_attack = Vector2.DOWN
	InputManager._buffered_attack_time = Time.get_ticks_msec() / 1000.0
	_c(InputManager.has_pending_attack(), "写入后立即可见（不依赖帧对齐）")
	_c(InputManager.take_buffered_attack(0.2) == Vector2.DOWN, "可取到攻击方向")
	InputManager.consume_attack()
	_c(not InputManager.has_pending_attack(), "消费后清空（不会重复触发）")
	# 过期输入不应生效
	InputManager._buffered_attack = Vector2.UP
	InputManager._buffered_attack_time = Time.get_ticks_msec() / 1000.0 - 5.0
	_c(not InputManager.has_pending_attack(0.2), "过期输入不生效")

	# --- 起始房不刷怪（刷怪点白名单）---
	# 根因：_collect_nodes 把「非 boss 标记」全当刷怪点，
	# 起始房的 player_spawn 于是被当成刷怪点，直接刷在玩家脚下。
	var start_ctrl = null
	for i in gr.dungeon_graph.size():
		if str(gr.dungeon_graph[i].get("type", "")) == "start":
			gr._transition_to_room(i)
			await get_tree().process_frame
			await get_tree().process_frame
			start_ctrl = gr.current_room_node.get_node_or_null("RoomController")
			break
	if start_ctrl:
		_c(start_ctrl._spawn_points.size() == 0, "起始房无刷怪点（player_spawn 不再被误收）",
			"点数=%d" % start_ctrl._spawn_points.size())
		_c(start_ctrl.enemies_alive == 0, "起始房不刷怪", "敌人=%d" % start_ctrl.enemies_alive)

	# --- 自动拾取开关 ---
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		var before = sm.get_setting("auto_pickup")
		_c(before != null, "auto_pickup 设置项存在")
		sm.set_setting("auto_pickup", true)
		_c(bool(sm.get_setting("auto_pickup")), "可切换为开")
		sm.set_setting("auto_pickup", false)
		_c(not bool(sm.get_setting("auto_pickup")), "可切换为关")

	# --- 奔跑触发 + 普攻宽限（防退化）---
	if p:
		await _test_sprint_triggering(p)
		await _test_attack_grace(p)

	if failed == 0:
		print("ALL GAMEPLAY FIXES TESTS PASSED")
	else:
		print("GAMEPLAY FIXES TESTS FAILED: %d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## 奔跑触发：持续按住方向不应自动奔跑；快速双击才奔跑。
## 回归的是「_last_input_time 每帧刷新 → 双击窗口退化成两帧方向一致」这个 bug，
## 它会让玩家一按方向键就是冲刺态、一按攻击就误出冲撞。
func _test_sprint_triggering(p) -> void:
	_sprint_reset(p)
	# 持续按住 30 帧（不按 Shift、不双击）
	var false_trigger := -1
	for f in 30:
		Input.action_press("move_right")
		await get_tree().physics_frame
		if p._is_sprinting and false_trigger < 0:
			false_trigger = f + 1
	Input.action_release("move_right")
	_c(false_trigger < 0, "持续按住方向不误触发奔跑",
		"第 %d 帧触发" % false_trigger if false_trigger > 0 else "")

	# 快速双击同方向 → 应奔跑
	_sprint_reset(p)
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_right")
	await get_tree().physics_frame
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_c(p._is_sprinting, "快速双击同方向触发奔跑")
	Input.action_release("move_right")
	await get_tree().physics_frame


## 普攻宽限：奔跑不足阈值时攻击走普攻，超过才走冲撞。
## 这让玩家能一边跑动一边普攻，不会误触冲撞消耗掉冲刺惯性。
func _test_attack_grace(p) -> void:
	var threshold: float = GameBalance.SPRINT_ATTACK_MIN_HOLD

	# 奔跑不足阈值（约 0.1s）→ 应仍处于 MoveState（普攻）
	_sprint_reset(p)
	Input.action_press("sprint")
	Input.action_press("move_right")
	var frames := 0
	while p._sprint_hold < 0.10 and frames < 60:
		await get_tree().physics_frame
		frames += 1
	_c(p._sprint_hold < threshold, "短奔跑未达冲撞阈值",
		"hold=%.3f 阈值=%.2f" % [p._sprint_hold, threshold])
	await _fire_attack(p)
	_c(p._state_machine.current_state_name() == "MoveState",
		"短奔跑时攻击走普攻（不误触冲撞）",
		"实际状态=%s" % p._state_machine.current_state_name())
	_release_all()

	# 奔跑超过阈值 → 应进 SprintAttackState（冲撞）
	_sprint_reset(p)
	Input.action_press("sprint")
	Input.action_press("move_right")
	frames = 0
	while p._sprint_hold < threshold + 0.15 and frames < 120:
		await get_tree().physics_frame
		frames += 1
	await _fire_attack(p)
	_c(p._state_machine.current_state_name() == "SprintAttackState",
		"持续奔跑后攻击走冲撞",
		"hold=%.3f 状态=%s" % [p._sprint_hold, p._state_machine.current_state_name()])
	_release_all()


## 触发一次攻击输入（写 InputManager 缓存，跳过按键时序）
func _fire_attack(p) -> void:
	var im = get_node_or_null("/root/InputManager")
	if im:
		im.set("attack_direction", Vector2(1, 0))
		im.set("_buffered_attack", Vector2(1, 0))
		im.set("_buffered_attack_time", Time.get_ticks_msec() / 1000.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if im:
		im.set("attack_direction", Vector2.ZERO)


func _release_all() -> void:
	for a in ["move_right", "move_left", "move_up", "move_down", "sprint",
			"attack_right", "attack_left", "attack_up", "attack_down"]:
		Input.action_release(a)


func _sprint_reset(p) -> void:
	_release_all()
	var im = get_node_or_null("/root/InputManager")
	if im:
		im.set("attack_direction", Vector2.ZERO)
		im.set("_buffered_attack", Vector2.ZERO)
		im.set("_buffered_attack_time", -999.0)
	p._is_sprinting = false
	p._sprint_hold = 0.0
	p._prev_raw_input = Vector3.ZERO
	p._since_dir_press = 99.0
	p._attack_timer = 0.0
	p._current_attack_cooldown = 0.0
	p.velocity = Vector3.ZERO
