extends Node
## 战斗系统集成测试（场景模式）：四段普攻 + 特殊攻击判定
## 运行：godot --headless --path E:\unity --scene res://tests/test_combat_system.tscn

var failed := 0
var player: CharacterBody3D


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("COMBAT TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame

	var game_root := get_tree().current_scene.get_node_or_null("MainScene") as Node
	player = game_root.get_node_or_null("Player")
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
	_finish()


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
	player._start_jump_attack()
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
	player._start_sprint_attack()
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
		print("ALL COMBAT TESTS PASSED")
		get_tree().quit(0)
	else:
		print("COMBAT TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 断言
func _check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s %s" % [name, extra])
		failed += 1
