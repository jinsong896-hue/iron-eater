extends PlayerState
## 默认状态：移动 + 攻击派发 + 翻滚检测
##
## 逐行搬移自 player.gd 的 _physics_process 默认路径（_move + _attack + _check_dodge）。
## 进入本状态即"正常游玩"，三个特殊模式（翻滚/冲撞/跳跃）各自转发到对应状态。

## 双击检测窗口（秒）
const DOUBLE_TAP_WINDOW := 0.3


func physics_update(delta: float) -> void:
	_core_movement(delta)
	_attack()
	_check_dodge()


## 移动：搬移自 _move()
func _core_movement(delta: float) -> void:
	var p := player
	var input_dir := InputManager.get_move_direction_3d()

	# 双击检测：同一方向快速按两次触发奔跑
	if input_dir != Vector3.ZERO:
		var now := Time.get_ticks_msec() / 1000.0
		if input_dir.dot(p._last_input_dir) > 0.8 and (now - p._last_input_time) < DOUBLE_TAP_WINDOW:
			p._is_sprinting = true
		elif input_dir.dot(p._last_input_dir) < 0.5:
			p._is_sprinting = false
		p._last_input_dir = input_dir
		p._last_input_time = now

	# Shift 键奔跑
	if Input.is_action_pressed("sprint"):
		p._is_sprinting = true
	if Input.is_action_just_released("sprint"):
		p._is_sprinting = false

	var speed := p.sprint_speed if p._is_sprinting else p.move_speed

	# 攻击动作期间减速
	if p._attack_timer > 0.0:
		speed *= GameBalance.ATTACK_MOVE_SLOWDOWN

	if input_dir != Vector3.ZERO:
		p.velocity.x = move_toward(p.velocity.x, input_dir.x * speed, p.acceleration * delta)
		p.velocity.z = move_toward(p.velocity.z, input_dir.z * speed, p.acceleration * delta)
	else:
		p.velocity.x = move_toward(p.velocity.x, 0.0, p.deceleration * delta)
		p.velocity.z = move_toward(p.velocity.z, 0.0, p.deceleration * delta)
		p._is_sprinting = false

	p.move_and_slide()

	if p.velocity.length() > 0.1:
		EventBus.player_moved.emit(p.global_position, p.velocity.normalized())


## 翻滚检测：搬移自 _check_dodge()
## 校验通过则转发到 DodgeState（方向通过 data 传递）
func _check_dodge() -> void:
	var p := player
	if not Input.is_action_just_pressed("dodge"):
		return
	if p._dodge_cooldown_timer > 0.0:
		return
	# 奔跑攻击冲撞中不可翻滚
	if p._sprint_attack_timer > 0.0:
		return
	# 跳跃攻击阶段中不可翻滚
	if p._jump_phase != Player.JumpPhase.NONE:
		return
	# 攻击冷却前半段不可翻滚；后摇取消窗口内可翻滚取消（清冷却）
	if p._attack_timer > 0.0:
		if not p._in_cancel_window():
			return
		p._cancel_current_attack()

	# 翻滚方向：面朝方向或移动方向
	var dodge_dir := p._facing
	var input_dir := InputManager.get_move_direction_3d()
	if input_dir != Vector3.ZERO:
		dodge_dir = input_dir

	finished.emit("DodgeState", {"direction": dodge_dir})


## 攻击派发：搬移自 _attack()
## 命中特殊攻击时转发到对应状态；普攻仍同步结算（单帧，不进状态机）
func _attack() -> void:
	var p := player
	# 新按下或缓存的攻击输入
	var dir_2d := InputManager.attack_direction
	if dir_2d == Vector2.ZERO:
		if p._attack_timer > 0.0 and p._combo and not p._combo.attack_in_progress:
			# 冷却中尝试取缓存输入
			dir_2d = InputManager.take_buffered_attack(GameBalance.ATTACK_INPUT_BUFFER)
		if dir_2d == Vector2.ZERO:
			return

	var in_recovery := p._attack_timer > 0.0 and p._in_cancel_window()
	var blocked := p._attack_timer > 0.0 and not in_recovery
	if blocked or (p._combo and p._combo.attack_in_progress):
		return
	# 跳跃攻击阶段中不接受新攻击
	if p._jump_phase != Player.JumpPhase.NONE:
		return
	# 冲撞位移中不接受
	if p._sprint_attack_timer > 0.0:
		return

	p._facing = InputManager.direction_2d_to_3d(dir_2d.normalized())
	if p._facing.length_squared() < 0.001:
		p._facing = Vector3.FORWARD

	# 1) 跳跃攻击：空格+方向键组合（连段派生：清冷却直接起手）
	if InputManager.attack_is_jump_combo():
		if in_recovery:
			p._cancel_current_attack()
		finished.emit("JumpAttackState", {})
		return

	# 2) 奔跑攻击：奔跑状态中攻击（连段派生）
	if p._is_sprinting:
		if in_recovery:
			p._cancel_current_attack()
		finished.emit("SprintAttackState", {})
		return

	# 3) 普攻连段（后摇取消窗口内允许下一击——连段提速）
	if in_recovery:
		p._cancel_current_attack()
	p._start_normal_attack()
