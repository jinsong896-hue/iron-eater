extends Node
## 运行时行为回归：穿门落点 / 拾取 / 门重入 / HP 刷新 / 受击反馈 / hitstop
## 这些是门禁漏掉的运行时行为（纯逻辑单测覆盖不到），专门固化防回归
##
## 私有成员访问一律经 `TestProbe`（重构时只改 probe，本文件零改动）。
var failed := 0
var probe := TestProbe.new()
func _c(cond: bool, name: String, extra := "") -> void:
	if cond: print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s %s" % [name, extra])

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var gr := get_tree().current_scene.get_node_or_null("MainScene/GameRoot")
	var p = gr.find_child("Player", true, false)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	# --- #8 穿门落点：进房后必须在门内侧，不能是房中央/房外 ---
	#
	# **四个方向都试**：地牢是随机生成的，起始房未必有南北邻接房。
	# 原先只试 north/south，地图恰好没这两向时测试会**随机失败**
	# （间歇性红，与代码无关，属测试脆弱性）。
	var dir := ""
	var tr := -1
	for d in ["north", "south", "east", "west"]:
		tr = probe.gr_find_room_in_direction(gr, d)
		if tr >= 0:
			dir = d
			break
	if tr >= 0:
		probe.gr_transition_to_room(gr, tr, dir)
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
		# 靠入口那一侧（四个方向都要覆盖）
		# 约定：北 = -Z、南 = +Z、西 = -X、东 = +X。
		# 向北走进入的是本房的**南门**（z 大的一侧），故落点应在 z > H/2；其余同理。
		match dir:
			"north":
				_c(pos.z > H * 0.5, "从北进入→落在南门内侧", "z=%.1f H=%.1f" % [pos.z, H])
			"south":
				_c(pos.z < H * 0.5, "从南进入→落在北门内侧", "z=%.1f" % pos.z)
			"west":
				_c(pos.x > W * 0.5, "从西进入→落在东门内侧", "x=%.1f W=%.1f" % [pos.x, W])
			"east":
				_c(pos.x < W * 0.5, "从东进入→落在西门内侧", "x=%.1f" % pos.x)
	else:
		_c(false, "找到可通行邻接房")

	# --- #3 拾取 ---
	var LS = load("res://gameplay/loot/loot_system.gd")
	var loot = LS.new()
	var room = gr.current_room_node
	loot.generate_chest_loot(p.global_position + Vector3(0.8, 0, 0), room, 1)
	await get_tree().process_frame
	var inv0: int = GameManager.equipment_manager.get_inventory().size()
	probe.pickup_nearby(p)
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
			_c(not probe.door_trigger_triggered(trig), "门触发器初始未触发")
			# 模拟真实穿门：玩家先站进触发区再触发。
			# 门触发器有几何复核（玩家不在触发区内 → 判为幽灵派发丢弃），
			# 远距离直调会被拦掉。
			p.global_position = (trig as Node3D).global_position + Vector3(0, -1.5, 0)
			# 数 door_opened 的发射次数，而不是看房间号。
			# 房间号断言会被 GameRoot 的**全局防抖**（TRANSITION_COOLDOWN）兜住，
			# 即使 `_triggered` 重入保护失效也照样"不叠加"——测不到本机制。
			# 信号次数直接反映 `_triggered` 这道闸，两者互不遮蔽。
			var bus := get_node_or_null("/root/EventBus")
			var fired := [0]
			var cb := func(_d, _i): fired[0] += 1
			bus.door_opened.connect(cb)
			probe.door_trigger_body_entered(trig, p)
			_c(probe.door_trigger_triggered(trig), "门触发后置位")
			_c(fired[0] == 1, "首次触发发出门信号", "次数=%d" % fired[0])
			var idx_before: int = gr.current_room_index
			probe.door_trigger_body_entered(trig, p)   # 二次触发应当被忽略
			await get_tree().process_frame
			_c(fired[0] == 1, "二次触发不叠加（door_opened 只发一次）", "次数=%d" % fired[0])
			_c(gr.current_room_index == idx_before, "二次触发未再次切房")
			bus.door_opened.disconnect(cb)

	# --- #6 HUD 血量刷新 ---
	var hud = get_tree().current_scene.find_child("HUD", true, false)
	if hud:
		GameManager.attributes.hp = 400.0
		probe.hud_on_player_hit(hud, 100.0, Vector3.ZERO)
		await get_tree().process_frame
		var shown: String = hud.health_label.text if hud.health_label else ""
		_c(shown == "400", "玩家受伤后 HUD 血量刷新", "显示=%s" % shown)

		# 毒气层数必须显示到 HUD。
		# 层数住在 GameRoot 的 FloorMechanic 上，而 GameRoot 是
		# current_scene(MainScene) 的**子节点**——旧实现用 current_scene 取，
		# 恒为 null，标签永远空白（毒气照常扣真伤，玩家却看不到数字）。
		var fm = gr.get("floor_mechanic")
		_c(fm != null, "本层有 FloorMechanic")
		if fm:
			fm.set("gas_layers", 3)
			probe.hud_update_gas_label(hud)
			_c(hud.gas_label.text.contains("毒气") and hud.gas_label.text.contains("3/"),
				"毒气层数显示到 HUD", "实际=%s" % hud.gas_label.text)
			fm.set("gas_layers", 0)
			probe.hud_update_gas_label(hud)
			_c(hud.gas_label.text == "", "无层数时毒气标签清空",
				"实际=%s" % hud.gas_label.text)

	# --- #5/#7 敌人闪红 + 血条 ---
	var EB = load("res://entities/enemies/enemy_base.gd")
	var e = EB.new()
	get_tree().current_scene.add_child(e)
	e.global_position = p.global_position + Vector3(2, 0, 0)
	await get_tree().process_frame
	# 满血也显示血条（旧版懒显示让首击血条「凭空出现在半血位」，
	# 玩家看不到从 100% 掉下来的过程，被当成「血条不是实时血量」）
	var full_mesh := probe.hp_bar_fill(e).mesh as QuadMesh
	_c(probe.hp_bar(e) != null and probe.hp_bar(e).visible, "满血时血条已显示")
	_c(full_mesh != null and absf(full_mesh.size.x - 1.1) < 0.01, "满血血条为满宽",
		"size.x=%.2f" % (full_mesh.size.x if full_mesh else -1.0))
	# **左缘必须落在背景条左端**（曾漏测位置只测宽度，导致「60% 血量看起来
	# 只有 30%」的偏移 bug 一路放行——center_offset 未随 size 同步更新）
	_c(absf(full_mesh.center_offset.x) < 0.01, "满血时填充与背景条对齐",
		"center_offset.x=%.3f" % full_mesh.center_offset.x)
	# **断言紧接在 take_damage 之后，不 await**。
	#
	# `take_damage` 同步调 `visuals.flash_hit()`，而后者同步把
	# `_flash_timer` 置为 `HIT_FLASH_DURATION`（0.18）。故此刻读它必然 > 0。
	#
	# 旧写法先 `await process_frame` 再断言，会**偶发失败**：
	# `_flash_timer` 每帧递减，而 headless 下进程帧耗时不受限——
	# 若那一帧恰好 > 0.18s（机器抖动），计时器已归零。
	# 实测 1/6 概率失败（跑 6 次挂 1 次），且与产品行为无关。
	e.take_damage(10.0)
	var flash_after_hit: float = probe.enemy_flash_timer(e)
	_c(flash_after_hit > 0.0, "受击进入闪红状态",
		"flash_timer=%.3f" % flash_after_hit)
	await get_tree().process_frame
	# 断言 **mesh.size.x**（真实渲染量）而非节点 scale：billboard 材质
	# 渲染时忽略节点 scale（实测 scale 改了屏幕像素宽纹丝不动），
	# 旧断言读 scale.x 时曾把这种视觉冻结放行成绿灯。
	var fill_mesh := probe.hp_bar_fill(e).mesh as QuadMesh
	_c(fill_mesh != null and fill_mesh.size.x < 1.09, "血条长度按血量收缩（mesh.size）",
		"size.x=%.2f" % (fill_mesh.size.x if fill_mesh else -1.0))
	# 填充必须**压过背景条**（否则整条血条发暗、看不清血量）。
	# 两个 quad 同位置、俯视下深度差不足以裁决先后 → 排序会翻转。
	# 用 render_priority 钉死，这里断言它确实生效。
	var fill_mat := probe.hp_bar_fill(e).material_override as StandardMaterial3D
	var bg_mat := probe.hp_bar_bg(e).material_override as StandardMaterial3D
	_c(fill_mat != null and bg_mat != null and fill_mat.render_priority > bg_mat.render_priority,
		"填充渲染优先级高于背景（血条不发暗）",
		"fill=%d bg=%d" % [
			fill_mat.render_priority if fill_mat else -999,
			bg_mat.render_priority if bg_mat else -999])
	# 收缩后左缘仍须钉死（左对齐正确性）
	var left_edge: float = fill_mesh.center_offset.x - fill_mesh.size.x * 0.5
	_c(absf(left_edge - (-1.1 * 0.5)) < 0.02, "收缩后左缘仍对齐背景条左端",
		"左缘=%.3f 期望=%.3f" % [left_edge, -0.55])
	# 连续受击必须持续收缩（回归：曾出现首击后视觉冻结）
	var size1: float = fill_mesh.size.x
	e.take_damage(20.0)
	await get_tree().process_frame
	var fill_mesh2 := probe.hp_bar_fill(e).mesh as QuadMesh
	_c(fill_mesh2.size.x < size1 - 0.05, "再次受击血条继续收缩",
		"%.2f → %.2f" % [size1, fill_mesh2.size.x])
	e.take_damage(999999.0)
	await get_tree().process_frame

	# --- #1 hitstop 不泄漏 ---
	probe.hitstop(p, 0.05)
	await get_tree().physics_frame
	for i in range(30): await get_tree().physics_frame
	_c(absf(Engine.time_scale - 1.0) < 0.01, "hitstop 后 time_scale 还原", "=%.3f" % Engine.time_scale)

	# --- 屏幕震动接线 ---
	# 旧实现：`EventBus.screen_shake` 有 2 处 emit（投射物命中/引信爆炸）但
	# **零订阅者**，`CameraRig.shake()` 也无人调用 —— 爆炸没有任何画面反馈。
	# 且 `shake()` 本身是坏的：`_shake_offset` 把相机局部 y 写成
	# `camera_height ± y`（20 上下），而 `_setup_camera` 已把局部位置归零，
	# 一旦被调用相机会瞬间弹到 20 米高再掉回来。
	var rig = gr.find_child("CameraRig", true, false)
	if rig:
		var cam: Node3D = rig.get_node_or_null("Camera3D")
		_c(cam != null, "相机架下有 Camera3D")
		var bus := get_node_or_null("/root/EventBus")
		_c(bus != null and bus.screen_shake.is_connected(Callable(rig, "shake")),
			"CameraRig 已订阅 EventBus.screen_shake")
		if cam:
			rig.call("shake", 0.2, 0.15)
			await get_tree().process_frame
			_c(absf(cam.position.y) < 0.5,
				"震动不改变相机高度（旧实现在此处弹到 20）", "y=%.2f" % cam.position.y)
			# 等震动播完，相机必须精确回到零基
			for i in range(40): await get_tree().process_frame
			_c(cam.position.distance_to(Vector3.ZERO) < 0.01,
				"震动结束后相机回到零基", "pos=%s" % str(cam.position))

	# --- #2 玩家受击闪红 ---
	# 玩家此前完全没有受击视觉：扣了血却看不出来
	GameManager.attributes.hp = GameManager.attributes.max_hp
	p.take_damage(50.0)
	await get_tree().process_frame
	_c(probe.flash_timer(p) > 0.0, "玩家受击进入闪红状态")
	var pmat = probe.model(p).material_override if probe.model(p) else null
	_c(pmat != null, "玩家模型有独立材质（闪红可控）")
	# 模型已换用卡通着色器（ToonMaterial），本色存在 ShaderMaterial 参数里，
	# 没有 `albedo_color` 属性可读——统一走 ToonMaterial.get_color
	if pmat:
		var pcol := ToonMaterial.get_color(pmat)
		_c(pcol.r > pcol.g, "闪红时偏红",
			"color=%s" % str(pcol))

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
			probe.gr_transition_to_room(gr, i)
			await get_tree().process_frame
			await get_tree().process_frame
			start_ctrl = gr.current_room_node.get_node_or_null("RoomController")
			break
	if start_ctrl:
		_c(probe.ctrl_spawn_points(start_ctrl).size() == 0, "起始房无刷怪点（player_spawn 不再被误收）",
			"点数=%d" % probe.ctrl_spawn_points(start_ctrl).size())
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
		if probe.is_sprinting(p) and false_trigger < 0:
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
	_c(probe.is_sprinting(p), "快速双击同方向触发奔跑")
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
	while p.sprint_hold < 0.10 and frames < 60:
		await get_tree().physics_frame
		frames += 1
	_c(p.sprint_hold < threshold, "短奔跑未达冲撞阈值",
		"hold=%.3f 阈值=%.2f" % [p.sprint_hold, threshold])
	await _fire_attack(p)
	_c(probe.state_machine(p).current_state_name() == "MoveState",
		"短奔跑时攻击走普攻（不误触冲撞）",
		"实际状态=%s" % probe.state_machine(p).current_state_name())
	_release_all()

	# 奔跑超过阈值 → 应进 SprintAttackState（冲撞）
	_sprint_reset(p)
	Input.action_press("sprint")
	Input.action_press("move_right")
	frames = 0
	while p.sprint_hold < threshold + 0.15 and frames < 120:
		await get_tree().physics_frame
		frames += 1
	await _fire_attack(p)
	_c(probe.state_machine(p).current_state_name() == "SprintAttackState",
		"持续奔跑后攻击走冲撞",
		"hold=%.3f 状态=%s" % [p.sprint_hold, probe.state_machine(p).current_state_name()])
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
	probe.set_sprinting(p, false)
	p.sprint_hold = 0.0
	p.prev_raw_input = Vector3.ZERO
	p.since_dir_press = 99.0
	probe.set_attack_timer(p, 0.0)
	probe.set_current_attack_cooldown(p, 0.0)
	p.velocity = Vector3.ZERO
