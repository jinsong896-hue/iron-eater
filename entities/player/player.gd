class_name Player
extends CharacterBody3D
## 玩家控制器 —— HD-2D 重构版
## 移动：WASD | 攻击：方向键 | 技能：Q/E/R/F
## 奔跑：Shift 或双击方向 | 翻滚：空格

@export var move_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 20.0
@export var deceleration: float = 25.0
@export var base_attack_interval := 0.6
@export var dodge_speed := 12.0
@export var dodge_duration := 0.2
@export var dodge_cooldown := 0.8

var _attack_timer := 0.0
var _facing := Vector3.FORWARD
var _is_sprinting := false
var _is_dodging := false
var _dodge_timer := 0.0
var _dodge_cooldown_timer := 0.0
var _last_input_dir := Vector3.ZERO
var _last_input_time := 0.0
var _double_tap_window := 0.3

const ATTACK_REACH := 2.0


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)

	if _is_dodging:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0:
			_is_dodging = false
		else:
			move_and_slide()
			return

	# 移动
	_move(delta)
	# 攻击
	_attack()
	# 翻滚
	_check_dodge()


func _move(delta: float) -> void:
	var input_dir := InputManager.get_move_direction_3d()

	# 双击检测：同一方向快速按两次触发奔跑
	if input_dir != Vector3.ZERO:
		var now := Time.get_ticks_msec() / 1000.0
		if input_dir.dot(_last_input_dir) > 0.8 and (now - _last_input_time) < _double_tap_window:
			_is_sprinting = true
		elif input_dir.dot(_last_input_dir) < 0.5:
			_is_sprinting = false
		_last_input_dir = input_dir
		_last_input_time = now

	# Shift 键奔跑
	if Input.is_action_pressed("sprint"):
		_is_sprinting = true
	if Input.is_action_just_released("sprint"):
		_is_sprinting = false

	var speed := sprint_speed if _is_sprinting else move_speed

	if input_dir != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, input_dir.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, input_dir.z * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		_is_sprinting = false

	move_and_slide()

	if velocity.length() > 0.1:
		EventBus.player_moved.emit(global_position, velocity.normalized())


func _check_dodge() -> void:
	if not Input.is_action_just_pressed("dodge"):
		return
	if _dodge_cooldown_timer > 0.0:
		return

	# 翻滚方向：面朝方向或移动方向
	var dodge_dir := _facing
	var input_dir := InputManager.get_move_direction_3d()
	if input_dir != Vector3.ZERO:
		dodge_dir = input_dir

	velocity = dodge_dir * dodge_speed
	_is_dodging = true
	_dodge_timer = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown
	EventBus.player_moved.emit(global_position, dodge_dir)


func _attack() -> void:
	var attack_dir_2d := InputManager.attack_direction
	if attack_dir_2d == Vector2.ZERO:
		return

	_facing = InputManager.direction_2d_to_3d(attack_dir_2d.normalized())
	if _facing.length_squared() < 0.001:
		_facing = Vector3.FORWARD

	if _attack_timer > 0.0:
		return

	var aspd := GameManager.stat_value("aspd")
	_attack_timer = base_attack_interval / maxf(aspd, 0.1)

	_perform_melee_attack()


func _perform_melee_attack() -> void:
	var atk := GameManager.stat_value("atk")
	var attack_range := ATTACK_REACH * maxf(GameManager.stat_value("rng"), 0.1)
	var crt := GameManager.stat_value("crt")
	var crd := GameManager.stat_value("crd")
	var fusion_bonus := GameManager.fusion_attack_bonus()
	var hit_any := false

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		if not enemy.has_method("take_damage"):
			continue

		var to_enemy: Vector3 = (enemy as Node3D).global_position - global_position
		if to_enemy.length() > attack_range:
			continue
		if to_enemy.normalized().dot(_facing) < 0.3:
			continue

		var target_def: float = enemy.get("defense") if enemy.get("defense") != null else 0.0
		var result := DamagePipeline.physical(atk, 1.0, fusion_bonus, target_def)
		var crit := GameManager.rng.randf() < crt
		var total := DamagePipeline.with_crit(result.damage, crit, crd)

		enemy.call("take_damage", total, crit)
		EventBus.damage_popup.emit((enemy as Node3D).global_position, total, "crit" if crit else "normal")
		hit_any = true

	if hit_any:
		EventBus.player_attacked.emit(_facing, "")
		EventBus.message.emit("攻击命中（ATK %.0f）" % atk)
		AudioManager.play("hit")


func cast_skill(skill_id: String) -> Dictionary:
	var skill_data := GameBalance.skill_by_id(skill_id)
	if skill_data.is_empty():
		return {"ok": false, "reason": "未知技能"}

	var direction := InputManager.get_attack_direction_3d()
	if direction == Vector3.ZERO:
		direction = _facing

	EventBus.player_skill_cast.emit(skill_id, direction)
	return {"ok": true, "skill": skill_id, "direction": direction}


func take_damage(amount: float) -> void:
	if _is_dodging:
		return  # 翻滚无敌帧
	GameManager.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount, global_position)
	EventBus.damage_popup.emit(global_position, amount, "player")
	AudioManager.play("hit")

	if GameManager.attributes.is_dead():
		die()


func die() -> void:
	if not is_inside_tree():
		return
	AudioManager.play("death")
	var result := GameManager.finish_run("defeated")
	EventBus.run_finished.emit(result)
	set_physics_process(false)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		EventBus.message.emit("背包")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("devour"):
		_devour_nearby()
		get_viewport().set_input_as_handled()


func _devour_nearby() -> void:
	var nearest: Node3D = null
	var nearest_d := INF
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node):
			continue
		var d := (node as Node3D).global_position.distance_to(global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = node

	if nearest == null:
		EventBus.message.emit("附近没有可吞噬的掉落物")
		return

	if nearest.has_method("devour"):
		nearest.call("devour")
		EventBus.message.emit("吞噬成功！")
		AudioManager.play("pickup")