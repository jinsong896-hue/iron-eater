class_name Player
extends CharacterBody3D
## 玩家控制器 —— HD-2D 重构版
## 移动：WASD | 攻击：方向键 | 技能：Q/E/R/F
## 奔跑：Shift 或双击方向 | 翻滚：空格
## 连段：普攻1→2→3→4；奔跑攻击→3→4；空格+方向键=跳跃攻击→3→4

@export var move_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 20.0
@export var deceleration: float = 25.0
@export var base_attack_interval := 0.6
@export var dodge_speed := 12.0
@export var dodge_duration := 0.2
@export var dodge_cooldown := 0.8

var _attack_timer := 0.0          # 当前攻击冷却
var _facing := Vector3.FORWARD
var _is_sprinting := false
var _is_dodging := false
var _dodge_timer := 0.0
var _dodge_cooldown_timer := 0.0
var _last_input_dir := Vector3.ZERO
var _last_input_time := 0.0
var _double_tap_window := 0.3

# 连段状态机
var _combo: AttackCombo = null

# 奔跑攻击：冲撞状态
var _sprint_attack_timer := 0.0
var _sprint_attack_dir := Vector3.ZERO

# 跳跃攻击：三阶段（后跳蓄力→俯冲→落地恢复）
enum JumpPhase { NONE, BACKHOP, DIVE, LAND }
var _jump_phase: JumpPhase = JumpPhase.NONE
var _jump_phase_timer := 0.0
var _jump_attack_dir := Vector3.ZERO

# 连击计数（HUD 显示 + 连击伤害加成）
var _hit_combo_count := 0
var _hit_combo_time := 0.0

# 连段动作状态
var _current_combo_stage := 0        # 正在执行的段位（霸体/朝向锁判定用）
var _current_attack_cooldown := 0.0  # 本次攻击的总冷却（取消窗口比例计算）
var _finisher_armor_timer := 0.0     # 终结技霸体剩余时间

const ATTACK_REACH := 2.0


func _ready() -> void:
	add_to_group("player")
	_combo = AttackCombo.new()
	# 击杀回血（监听全局敌死信号）
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("enemy_died"):
		bus.enemy_died.connect(_on_enemy_killed)


## 击杀回血回调
func _on_enemy_killed(_enemy: Node, _pos: Vector3, _loot: Array) -> void:
	if GameBalance.KILL_HEAL <= 0.0:
		return
	if GameManager.attributes and not GameManager.attributes.is_dead():
		var healed: float = GameManager.attributes.heal(GameBalance.KILL_HEAL)
		# 绿色回血飘字
		var bus := get_node_or_null("/root/EventBus")
		if bus and healed > 0.0:
			bus.damage_popup.emit(global_position, healed, "heal")


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_sprint_attack_timer = maxf(_sprint_attack_timer - delta, 0.0)
	_finisher_armor_timer = maxf(_finisher_armor_timer - delta, 0.0)

	# 连击窗口推进 + 连击数计时
	if _combo:
		_combo.tick(delta)
	if _hit_combo_time > 0.0:
		_hit_combo_time = maxf(_hit_combo_time - delta, 0.0)
		if _hit_combo_time == 0.0:
			_hit_combo_count = 0

	# 跳跃攻击阶段推进（独立于普通移动）
	if _jump_phase != JumpPhase.NONE:
		_update_jump_attack(delta)
		return

	# 奔跑攻击冲撞位移
	if _sprint_attack_timer > 0.0:
		velocity = _sprint_attack_dir * sprint_speed
		move_and_slide()
		_check_dodge()
		return

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

	# 攻击动作期间减速
	if _attack_timer > 0.0:
		speed *= GameBalance.ATTACK_MOVE_SLOWDOWN

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
	# 奔跑攻击冲撞中不可翻滚
	if _sprint_attack_timer > 0.0:
		return
	# 跳跃攻击阶段中不可翻滚
	if _jump_phase != JumpPhase.NONE:
		return
	# 攻击冷却前半段不可翻滚；后摇取消窗口内可翻滚取消（清冷却）
	if _attack_timer > 0.0:
		if not _in_cancel_window():
			return
		_cancel_current_attack()

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


# ============================================================
# 攻击系统：四段普攻 + 奔跑攻击 + 跳跃攻击
# ============================================================

## 攻击入口：判定攻击类型（跳跃组合/奔跑/普攻）并派发
## 支持连段派生：普攻 2/3 段后摇中可派生奔跑/跳跃攻击
func _attack() -> void:
	# 新按下或缓存的攻击输入
	var dir_2d := InputManager.attack_direction
	if dir_2d == Vector2.ZERO:
		if _attack_timer > 0.0 and _combo and not _combo.attack_in_progress:
			# 冷却中尝试取缓存输入
			dir_2d = InputManager.take_buffered_attack(GameBalance.ATTACK_INPUT_BUFFER)
		if dir_2d == Vector2.ZERO:
			return

	var in_recovery := _attack_timer > 0.0 and _in_cancel_window()
	var blocked := _attack_timer > 0.0 and not in_recovery
	if blocked or (_combo and _combo.attack_in_progress):
		return
	# 跳跃攻击阶段中不接受新攻击
	if _jump_phase != JumpPhase.NONE:
		return
	# 冲撞位移中不接受
	if _sprint_attack_timer > 0.0:
		return

	_facing = InputManager.direction_2d_to_3d(dir_2d.normalized())
	if _facing.length_squared() < 0.001:
		_facing = Vector3.FORWARD

	# 1) 跳跃攻击：空格+方向键组合（连段派生：清冷却直接起手）
	if InputManager.attack_is_jump_combo():
		if in_recovery:
			_cancel_current_attack()
		_start_jump_attack()
		return

	# 2) 奔跑攻击：奔跑状态中攻击（连段派生）
	if _is_sprinting:
		if in_recovery:
			_cancel_current_attack()
		_start_sprint_attack()
		return

	# 3) 普攻连段（后摇取消窗口内允许下一击——连段提速）
	if in_recovery:
		_cancel_current_attack()
	_start_normal_attack()


## 是否处于攻击后摇取消窗口（冷却后半段）
func _in_cancel_window() -> bool:
	if _current_attack_cooldown <= 0.0:
		return false
	var elapsed := _current_attack_cooldown - _attack_timer
	return elapsed >= _current_attack_cooldown * GameBalance.CANCEL_WINDOW_RATIO


## 取消当前攻击后摇（清冷却；连段保持——下一击按段位推进）
func _cancel_current_attack() -> void:
	_attack_timer = 0.0
	_current_attack_cooldown = 0.0


## 普攻：取段位参数 → 判定 → 冷却
func _start_normal_attack() -> void:
	if _combo == null:
		return
	var stage: int = _combo.request_normal()
	if stage == 0:
		return
	var params: Array = _combo.stage_params(stage)
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)
	_current_attack_cooldown = _attack_timer
	_current_combo_stage = stage
	# 终结技（第 4 段）霸体
	if stage == combo_stages_size() and GameBalance.FINISHER_SUPERARMOR:
		_finisher_armor_timer = _attack_timer
		_spawn_armor_visual()
	_perform_melee_attack(params[1], params[2], deg_to_rad(params[3]), params[4])
	# 挥砍视觉：终结技（第 4 段）金色大扇形，其余白
	if stage == combo_stages_size():
		_spawn_slash_visual(params[2], deg_to_rad(params[3]), Color(1.0, 0.8, 0.2, 0.55))
	else:
		_spawn_slash_visual(params[2], deg_to_rad(params[3]))
	_combo.end_attack()


## 连段总段数（从 GameBalance 取，终结技判定用）
func combo_stages_size() -> int:
	return GameBalance.COMBO_STAGES.size()


## 霸体视觉：玩家金色描边光（终结技期间）
func _spawn_armor_visual() -> void:
	var aura := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.7
	mesh.height = 1.4
	aura.mesh = mesh
	aura.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura.material_override = mat
	add_child(aura)
	# 随霸体计时消失
	var tween := create_tween()
	tween.tween_interval(_finisher_armor_timer)
	tween.tween_callback(aura.queue_free)


## 奔跑攻击：突进冲撞（矩形判定），攻击后退出奔跑
func _start_sprint_attack() -> void:
	if _combo == null or not _combo.request_sprint():
		return
	var params: Array = GameBalance.SPRINT_ATTACK
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)

	# 冲撞：朝面向方向冲刺
	_sprint_attack_dir = _facing
	_sprint_attack_timer = 0.18
	_is_sprinting = false  # 消耗冲刺惯性

	_perform_charge_attack(params[1], params[2], params[3], params[4])
	# 冲撞视觉：橙红色宽扇形
	_spawn_slash_visual(params[2], deg_to_rad(55.0), Color(1.0, 0.45, 0.15, 0.5))
	_combo.end_attack()


## 跳跃攻击启动：后跳蓄力 → 俯冲 → 落地 AOE
func _start_jump_attack() -> void:
	if _combo == null or not _combo.request_jump():
		return
	var params: Array = GameBalance.JUMP_ATTACK
	_combo.begin_attack()
	var aspd := GameManager.stat_value("aspd")
	_attack_timer = params[0] / maxf(aspd, 0.1)

	_jump_attack_dir = _facing
	_jump_phase = JumpPhase.BACKHOP
	_jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[0]
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer, params[0])  # 复用冷却防连发


## 跳跃攻击阶段推进
func _update_jump_attack(delta: float) -> void:
	_jump_phase_timer -= delta
	match _jump_phase:
		JumpPhase.BACKHOP:
			# 后跳：向面向反方向
			velocity = -_jump_attack_dir * (GameBalance.JUMP_ATTACK[2] / GameBalance.JUMP_ATTACK_PHASES[0])
			move_and_slide()
			if _jump_phase_timer <= 0.0:
				_jump_phase = JumpPhase.DIVE
				_jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[1]
		JumpPhase.DIVE:
			# 俯冲：向前高速位移（无敌帧）
			velocity = _jump_attack_dir * (GameBalance.JUMP_ATTACK[3] / GameBalance.JUMP_ATTACK_PHASES[1])
			move_and_slide()
			if _jump_phase_timer <= 0.0:
				_jump_phase = JumpPhase.LAND
				_jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[2]
				_perform_jump_landing()
		JumpPhase.LAND:
			velocity = Vector3.ZERO
			if _jump_phase_timer <= 0.0:
				_jump_phase = JumpPhase.NONE
				if _combo:
					_combo.end_attack()


## 跳跃攻击落地：圆形 AOE 判定
func _perform_jump_landing() -> void:
	var params: Array = GameBalance.JUMP_ATTACK
	_perform_aoe_attack(params[1], params[4], params[5])
	# 落地视觉：青色全向扇形（360°）+ 强震屏
	_spawn_slash_visual(params[4], PI, Color(0.4, 0.9, 1.0, 0.5))
	_screen_shake(0.3)
	# 视觉反馈：落地消息
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.message.emit("落地斩！")


## 扇形近战判定（普攻/连段用）
func _perform_melee_attack(multiplier: float, reach: float, half_angle: float, knockback: float) -> void:
	var hit_any := _hit_enemies_in_cone(multiplier, reach, half_angle, knockback)
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 冲撞判定（奔跑攻击）：面向矩形区域
func _perform_charge_attack(multiplier: float, length: float, width: float, knockback: float) -> void:
	var hit_any := false
	var width_sq := (width / 2.0) * (width / 2.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - global_position
		# 矩形判定：沿面向投影在 [0, length]，侧向偏移 < width/2
		var forward_dist := to_enemy.dot(_facing)
		if forward_dist < 0.0 or forward_dist > length:
			continue
		var lateral := to_enemy - _facing * forward_dist
		if lateral.length_squared() > width_sq:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 圆形 AOE 判定（跳跃攻击落地）
func _perform_aoe_attack(multiplier: float, radius: float, knockback: float) -> void:
	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var dist: float = (enemy as Node3D).global_position.distance_to(global_position)
		if dist > radius:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	if hit_any:
		_register_hit_combo()
	_finish_attack_feedback(hit_any)


## 扇形内的敌人命中
func _hit_enemies_in_cone(multiplier: float, reach: float, half_angle: float, knockback: float) -> bool:
	var hit_any := false
	var cos_threshold := cos(half_angle)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not _is_valid_enemy(enemy):
			continue
		var to_enemy: Vector3 = (enemy as Node3D).global_position - global_position
		if to_enemy.length() > reach:
			continue
		if to_enemy.normalized().dot(_facing) < cos_threshold:
			continue
		_apply_hit(enemy as Node3D, multiplier, knockback)
		hit_any = true
	return hit_any


## 对单个敌人结算伤害与击退
func _apply_hit(enemy: Node3D, multiplier: float, knockback: float) -> void:
	var atk := GameManager.stat_value("atk")
	var crt := GameManager.stat_value("crt")
	var crd := GameManager.stat_value("crd")
	var fusion_bonus := GameManager.fusion_attack_bonus()
	# 连击数伤害加成（每击 +2%，上限 +30%）
	var combo_bonus: float = minf(
		_hit_combo_count * GameBalance.COMBO_DAMAGE_PER_HIT,
		GameBalance.COMBO_DAMAGE_CAP
	)
	var target_def: float = enemy.get("defense") if enemy.get("defense") != null else 0.0
	var result := DamagePipeline.physical(atk, multiplier, fusion_bonus + combo_bonus, target_def)
	var crit := GameManager.rng.randf() < crt
	var total := DamagePipeline.with_crit(result.damage, crit, crd)

	# 击退向量（EnemyBase 硬直期间消费）
	var push: Vector3 = Vector3.ZERO
	if knockback > 0.0:
		push = (enemy.global_position - global_position)
		push.y = 0.0
		if push.length_squared() > 0.001:
			push = push.normalized() * knockback
		else:
			push = _facing * knockback
	enemy.call("take_damage", total, crit, push)
	EventBus.damage_popup.emit(enemy.global_position, total, "crit" if crit else "normal")
	# 暴击/重击 hitstop 顿帧
	if crit or multiplier >= 1.5:
		_hitstop(0.06)


## 攻击收尾反馈
func _finish_attack_feedback(hit_any: bool) -> void:
	if hit_any:
		EventBus.player_attacked.emit(_facing, "")
		AudioManager.play("hit")
		_screen_shake(0.15)


## Hitstop：短暂全局减速制造顿帧感
func _hitstop(duration: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false

var _hitstop_active := false


## 屏幕震动：相机 rig 短促偏移衰减
func _screen_shake(strength: float) -> void:
	var rig := get_node_or_null("../CameraRig")
	if rig == null:
		return
	var tween := create_tween()
	var offset := Vector3(
		rng_shake.randf_range(-strength, strength),
		0.0,
		rng_shake.randf_range(-strength, strength)
	)
	rig.position += offset
	tween.tween_property(rig, "position", rig.position - offset, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

var rng_shake := RandomNumberGenerator.new()


## 挥砍视觉：面前渐隐扇形 mesh（普攻/奔跑/跳跃攻击调用）
func _spawn_slash_visual(reach: float, half_angle: float, color: Color = Color(1, 1, 0.85, 0.5)) -> void:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	slash.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slash.material_override = mat

	# 扇形几何（在局部 Z+ 方向画弧，节点朝向 = 攻击面向；三角形条带拼扇形）
	var steps := 12
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(steps):
		var a0 := -half_angle + (2.0 * half_angle * i / steps)
		var a1 := -half_angle + (2.0 * half_angle * (i + 1) / steps)
		var v0 := Vector3(sin(a0) * reach, 0.0, cos(a0) * reach)
		var v1 := Vector3(sin(a1) * reach, 0.0, cos(a1) * reach)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(v1)
		mesh.surface_add_vertex(v0)
	mesh.surface_end()

	var rot_y := atan2(_facing.x, _facing.z)
	slash.position = global_position + Vector3(0, 1.0, 0)
	slash.rotation.y = rot_y

	get_parent().add_child(slash)
	# 渐隐销毁
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(slash.queue_free)


## 敌人有效性检查
func _is_valid_enemy(enemy: Node) -> bool:
	return is_instance_valid(enemy) and enemy is Node3D and enemy.has_method("take_damage")


## 连击计数（命中即计，2 秒无命中清零）
func _register_hit_combo() -> void:
	_hit_combo_count += 1
	_hit_combo_time = 2.0


## 当前连击数（HUD 用）
func get_hit_combo() -> int:
	return _hit_combo_count


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
	# 翻滚/俯冲无敌帧
	if _is_dodging or _jump_phase == JumpPhase.DIVE:
		return
	# 终结技霸体：减伤 30%，不掉连段节奏（无硬直状态，攻击照常续接）
	var armor := _finisher_armor_timer > 0.0
	if armor:
		amount *= 0.7
	GameManager.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount, global_position)
	EventBus.damage_popup.emit(global_position, amount, "player" if not armor else "armor")
	AudioManager.play("hit")

	if GameManager.attributes.is_dead():
		die()


func die() -> void:
	if not is_inside_tree():
		return
	AudioManager.play("death")
	# finish_run 内部已发 run_finished（结算面板监听显示）
	GameManager.finish_run("defeated")
	set_physics_process(false)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		EventBus.message.emit("背包")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if not _interact_special_room():
			_pickup_nearby()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("devour"):
		_devour_nearby()
		get_viewport().set_input_as_handled()

## 交互当前房间的商店、泉水或事件服务。
func _interact_special_room() -> bool:
	var controller := get_tree().get_first_node_in_group("current_room_controller")
	if controller == null or not controller.has_method("interact_special"):
		return false
	var result: Dictionary = controller.interact_special()
	if result.get("ok", false):
		EventBus.message.emit("特殊房交互完成")
	else:
		EventBus.message.emit(result.get("reason", "无法交互"))
	return true


## 查找最近的掉落物（拾取/吞噬共用）
func _nearest_pickup() -> Node3D:
	var nearest: Node3D = null
	var nearest_d := INF
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node):
			continue
		var d := (node as Node3D).global_position.distance_to(global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = node
	return nearest


## 拾取最近掉落物进背包
func _pickup_nearby() -> void:
	var nearest := _nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可拾取的掉落物")
		return

	if nearest.has_method("pick_up"):
		var result: Dictionary = nearest.call("pick_up")
		if not result.get("ok", false):
			EventBus.message.emit(result.get("reason", "拾取失败"))


## 吞噬最近掉落物（本局永久成长）
func _devour_nearby() -> void:
	var nearest := _nearest_pickup()
	if nearest == null:
		EventBus.message.emit("附近没有可吞噬的掉落物")
		return

	if nearest.has_method("devour"):
		var result: Dictionary = nearest.call("devour")
		if result.get("ok", false):
			EventBus.message.emit("吞噬成功！")
			AudioManager.play("pickup")
		else:
			EventBus.message.emit(result.get("reason", "吞噬失败"))
