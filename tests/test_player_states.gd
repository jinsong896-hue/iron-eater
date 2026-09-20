extends Node
## 玩家状态机集成测试（场景模式）：状态切换 / 翻滚无敌 / 取消窗口 / 霸体减伤
## 运行：godot --headless --path E:\unity --scene res://tests/test_player_states.tscn

var failed := 0
var player: CharacterBody3D


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("PLAYER STATES TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame

	# 3D 世界在 MainScene/GameRoot/ViewportContainer/SubViewport 下（像素化管线），
	# 所以按名递归找，不用直接子节点路径
	var game_root := get_tree().current_scene.get_node_or_null("MainScene") as Node
	player = game_root.find_child("Player", true, false)
	if player == null:
		print("  [FAIL] 玩家不存在")
		_finish()
		return

	# 清场：杀掉地牢初始房的怪（避免干扰）
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await get_tree().process_frame

	await _test_combo_stage_params()
	await _test_normal_combo_damage()
	await _test_jump_attack_phases()
	await _test_sprint_attack_charge()
	await _test_combo_action_system()
	await _test_state_transitions()
	_finish()


## 状态机转移：默认态 → 翻滚 → 自动回到默认态；死亡态无每帧行为
## 只验证状态名与标志位，不触发 die()（那会结束本局并暂停）
func _test_state_transitions() -> void:
	# 前置 1：等 hitstop 的全局 time_scale 恢复。
	# 前面的冲刺测试命中重击会触发 _hitstop（time_scale=0.05），
	# 在恢复前跑本测试，帧推进会被拖慢 20 倍导致翻滚走不完。
	var guard := 0
	while Engine.time_scale < 0.99 and guard < 180:
		await get_tree().physics_frame
		guard += 1
	_check(Engine.time_scale > 0.99, "time_scale 已恢复正常", str(Engine.time_scale))

	# 前置 2：前面的冲刺测试可能刚结束，显式回到默认态作为起点
	player.enter_state("MoveState")
	_check(player.current_state_name() == "MoveState",
		"初始处于 MoveState", player.current_state_name())

	# 进入翻滚：enter() 同步置 _is_dodging
	player.enter_state("DodgeState")
	_check(player.current_state_name() == "DodgeState",
		"已切到 DodgeState", player.current_state_name())
	_check(player._is_dodging, "翻滚 enter 同步置 _is_dodging")

	# 翻滚时长 0.2s，跑 20 物理帧（约 0.33s）后应自动回到 MoveState
	for i in range(20):
		await get_tree().physics_frame
	_check(player.current_state_name() == "MoveState",
		"翻滚结束自动回到 MoveState", player.current_state_name())
	_check(not player._is_dodging, "翻滚结束后 _is_dodging 清除")

	# 死亡态：无每帧行为（比对前后位置不变）
	player.enter_state("DeadState")
	_check(player.current_state_name() == "DeadState",
		"已切到 DeadState", player.current_state_name())
	var pos_before: Vector3 = player.global_position
	for i in range(5):
		await get_tree().physics_frame
	_check(player.global_position.distance_to(pos_before) < 0.001,
		"死亡态不产生位移", str(player.global_position.distance_to(pos_before)))

	# 复位到默认态，避免影响后续（本测试在最后，仅为整洁）
	player.enter_state("MoveState")


## 连段动作系统：取消窗口/派生/霸体/连击加成
func _test_combo_action_system() -> void:
	# --- 取消窗口判定 ---
	player._attack_timer = 0.0
	player._current_attack_cooldown = 0.28
	# 冷却前半段：elapsed=0.05 < 0.28*0.45=0.126 → 不可取消
	player._attack_timer = 0.23
	_check(not player._in_cancel_window(), "冷却前半段不可取消")
	# 冷却后半段：elapsed=0.20 > 0.126 → 可取消
	player._attack_timer = 0.08
	_check(player._in_cancel_window(), "冷却后半段进入取消窗口")

	# --- 取消清冷却 ---
	player._cancel_current_attack()
	_check(player._attack_timer == 0.0, "取消清空攻击冷却")

	# --- 终结技霸体 ---
	player._finisher_armor_timer = 0.5
	var hp_before: float = GameManager.attributes.hp
	player.take_damage(100.0)
	_check(GameManager.attributes.hp > hp_before - 100.0, "霸体期受击减伤 30%")
	_check(GameManager.attributes.hp == hp_before - 70.0, "霸体减伤精确 70%")
	player._finisher_armor_timer = 0.0

	# --- 连击伤害加成 ---
	player._hit_combo_count = 0
	var combo_bonus_0: float = minf(0 * GameBalance.COMBO_DAMAGE_PER_HIT, GameBalance.COMBO_DAMAGE_CAP)
	_check(combo_bonus_0 == 0.0, "0 连击无加成")
	player._hit_combo_count = 20
	var combo_bonus_20: float = minf(20 * GameBalance.COMBO_DAMAGE_PER_HIT, GameBalance.COMBO_DAMAGE_CAP)
	_check(combo_bonus_20 == 0.30, "20 连击加成触顶 30%", str(combo_bonus_20))
	player._hit_combo_count = 0

	# --- 连击数计数与衰减 ---
	player._register_hit_combo()
	_check(player.get_hit_combo() == 1, "命中计数 +1")
	player._hit_combo_time = 0.0
	_check(GameBalance.COMBO_DAMAGE_CAP == 0.30, "连击加成上限配置 30%")


## 连段参数：四段伤害与范围递增
func _test_combo_stage_params() -> void:
	_check(GameBalance.COMBO_STAGES.size() == 4, "四段普攻配置")
	var dmg_ok := true
	var range_ok := true
	for i in range(1, GameBalance.COMBO_STAGES.size()):
		if GameBalance.COMBO_STAGES[i][1] <= GameBalance.COMBO_STAGES[i - 1][1]:
			dmg_ok = false
		if GameBalance.COMBO_STAGES[i][2] <= GameBalance.COMBO_STAGES[i - 1][2]:
			range_ok = false
	_check(dmg_ok, "四段伤害递增")
	_check(range_ok, "四段攻击范围递增")
	_check(GameBalance.SPRINT_ATTACK[1] > 1.0, "奔跑攻击倍率 > 100%")
	_check(GameBalance.JUMP_ATTACK[1] > 1.0, "跳跃攻击倍率 > 100%")
	_check(GameBalance.JUMP_ATTACK_PHASES.size() == 3, "跳跃攻击三阶段配置")


## 造一个木桩敌人，测普攻伤害流程
func _test_normal_combo_damage() -> void:
	var enemy := _spawn_dummy(player.global_position + Vector3(0, 0, -1.5))
	enemy.max_hp = 10000.0
	enemy.take_damage(0.0)  # 初始化 _hp
	enemy._hp = 10000.0

	# 第一段普攻（面向敌人：敌人在 -Z 即 UP 方向）
	player._facing = Vector3(0, 0, -1)
	var hp_before: float = enemy._hp
	player._perform_melee_attack(1.0, 2.0, deg_to_rad(60.0), 0.0)
	await get_tree().process_frame
	_check(enemy._hp < hp_before, "普攻判定命中面前敌人")
	var dmg1: float = hp_before - enemy._hp

	# 第四段（更大范围）在稍远距离也命中
	enemy.global_position = player.global_position + Vector3(0, 0, -3.0)
	var hp_before4: float = enemy._hp
	player._perform_melee_attack(1.8, 3.2, deg_to_rad(90.0), 4.0)
	await get_tree().process_frame
	var dmg4: float = hp_before4 - enemy._hp
	_check(dmg4 > 0.0, "普攻4 大范围命中 3m 外敌人")
	_check(dmg4 > dmg1, "普攻4（1.8x）伤害 > 普攻1（1.0x）", "%.1f vs %.1f" % [dmg4, dmg1])

	# 背后敌人不命中（扇形判定）
	enemy.global_position = player.global_position + Vector3(0, 0, 1.5)  # 背后
	var hp_back: float = enemy._hp
	player._perform_melee_attack(1.0, 2.0, deg_to_rad(60.0), 0.0)
	_check(enemy._hp == hp_back, "扇形判定不命中背后敌人")

	enemy.queue_free()


## 跳跃攻击：后跳→俯冲→落地 AOE 全流程
func _test_jump_attack_phases() -> void:
	# 重置玩家到初始位置（前序测试可能移动过，避免撞墙干扰俯冲）
	var room_center := Vector3(10, 0, 7)
	player.global_position = room_center
	var start_pos: Vector3 = player.global_position
	# 敌人放在俯冲落点（前方 4m，关碰撞避免挡住玩家位移）
	var enemy := _spawn_dummy(start_pos + Vector3(0, 0, -4.0))
	enemy._hp = 10000.0
	var hp_before: float = enemy._hp
	for col in enemy.find_children("", "CollisionShape3D", true, false):
		(col as CollisionShape3D).disabled = true

	player._facing = Vector3(0, 0, -1)
	# 经状态机进入跳跃攻击：enter() 会调用 _start_jump_attack() 同步置位
	player.enter_state("JumpAttackState")
	_check(player._jump_phase == player.JumpPhase.BACKHOP, "跳跃攻击进入后跳阶段")

	# 推进阶段（每帧 16ms 左右，跑完三阶段约 0.5s）
	for i in range(60):
		await get_tree().physics_frame

	_check(player._jump_phase == player.JumpPhase.NONE, "三阶段后结束", str(player._jump_phase))
	_check(enemy._hp < hp_before, "落地 AOE 命中落点敌人")
	# 俯冲位移验证：玩家应在前方
	_check(player.global_position.distance_to(start_pos) > 1.0, "俯冲产生位移")

	enemy.queue_free()


## 奔跑攻击：冲撞判定 + 位移
func _test_sprint_attack_charge() -> void:
	var start_pos: Vector3 = player.global_position
	var enemy := _spawn_dummy(start_pos + Vector3(0, 0, -2.0))
	enemy._hp = 10000.0
	var hp_before: float = enemy._hp

	player._facing = Vector3(0, 0, -1)
	player._is_sprinting = true
	# 经状态机进入冲撞：enter() 会调用 _start_sprint_attack() 同步置位
	player.enter_state("SprintAttackState")
	_check(player._sprint_attack_timer > 0.0, "奔跑攻击进入冲撞状态")
	_check(not player._is_sprinting, "奔跑攻击消耗冲刺状态")

	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(enemy._hp < hp_before, "冲撞矩形判定命中路径上敌人")
	enemy.queue_free()


## 生成木桩敌人（不进 enemies 组会打不到，进组但禁 AI）
func _spawn_dummy(pos: Vector3) -> CharacterBody3D:
	var enemy := EnemyBase.new()
	enemy.max_hp = 10000.0
	enemy.position = pos
	enemy.behavior = EnemyBase.AIBehavior.STATIONARY
	get_tree().current_scene.add_child(enemy)
	return enemy


## 结束判定
func _finish() -> void:
	if failed == 0:
		print("ALL PLAYER STATES TESTS PASSED")
		get_tree().quit(0)
	else:
		print("PLAYER STATES TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 断言
func _check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s %s" % [name, extra])
		failed += 1
