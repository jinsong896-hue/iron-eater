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


## 调试控制台是否在接收文本（打字时不应翻滚/奔跑）
func _typing() -> bool:
	var dm := Engine.get_main_loop() as SceneTree
	if dm == null or dm.root == null:
		return false
	var m := dm.root.get_node_or_null("DebugManager")
	if m != null and m.has_method("is_text_input_active"):
		return bool(m.call("is_text_input_active"))
	return false


## 移动：搬移自 _move()
func _core_movement(delta: float) -> void:
	var p := player
	var input_dir := InputManager.get_move_direction_3d()

	# 双击检测：同一方向快速按两次触发奔跑。
	#
	# 关键：必须在「方向键的按下沿」上判定，而不是每帧。
	# 原实现在每帧都刷新 _last_input_time，导致 (now - _last_input_time) 恒为
	# 一帧时长 → 窗口退化成「任意两帧方向一致」，持续按住方向第 3 帧就自动奔跑，
	# 于是玩家一按方向就是冲刺态、一按攻击就误出冲撞。
	# 现在改为：方向从「无」变「有」（或换成不同方向）时才算一次按下沿，
	# 记录该时刻，两次按下沿间隔小于窗口才算双击。
	var raw := input_dir
	var pressed_edge := raw != Vector3.ZERO and p.prev_raw_input == Vector3.ZERO
	p.since_dir_press += delta
	if pressed_edge:
		# 本次按下沿与上一次按下沿间隔够短 → 判定双击
		if p.since_dir_press <= DOUBLE_TAP_WINDOW:
			p._is_sprinting = true
		p.since_dir_press = 0.0
	p.prev_raw_input = raw

	# Shift 键奔跑（主动触发，与双击并行）
	# 控制台打字时不响应（这处绕过了 InputManager 的闸门）
	if not _typing() and Input.is_action_pressed("sprint"):
		p._is_sprinting = true
	if Input.is_action_just_released("sprint"):
		p._is_sprinting = false

	# 奔跑持续计时：冲撞需要持续奔跑一段时间（见 SPRINT_ATTACK_MIN_HOLD）
	if p._is_sprinting:
		p.sprint_hold += delta
	else:
		p.sprint_hold = 0.0

	var speed := p.sprint_speed if p._is_sprinting else p.move_speed
	# 形态·脱战加速（策划 6.2 斥候「脱战 3 秒后移速 +30%」）。
	# 未声明该机制的形态返回 1.0，无副作用。
	speed *= p.out_of_combat_speed_mult()

	# 攻击动作期间减速。
	# 形态·追猎者「远近切换无冷却」（策划 6.1）落成"攻击后不被拖慢"——
	# 玩家没有真正的换武器动作，攻击后的移速惩罚就是这条机制能作用的地方。
	if p._attack_timer > 0.0 and not p.weapon_swap_free():
		speed *= GameBalance.ATTACK_MOVE_SLOWDOWN

	if input_dir != Vector3.ZERO:
		p.velocity.x = move_toward(p.velocity.x, input_dir.x * speed, p.acceleration * delta)
		p.velocity.z = move_toward(p.velocity.z, input_dir.z * speed, p.acceleration * delta)
	else:
		p.velocity.x = move_toward(p.velocity.x, 0.0, p.deceleration * delta)
		p.velocity.z = move_toward(p.velocity.z, 0.0, p.deceleration * delta)
		p._is_sprinting = false
		p.sprint_hold = 0.0

	p.move_and_slide()

	if p.velocity.length() > 0.1:
		EventBus.player_moved.emit(p.global_position, p.velocity.normalized())


## 翻滚检测：搬移自 _check_dodge()
## 校验通过则转发到 DodgeState（方向通过 data 传递）
func _check_dodge() -> void:
	var p := player
	if not Input.is_action_just_pressed("dodge") or _typing():
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
##
## 输入读取修复：原先直接读 InputManager.attack_direction，而该值在
## InputManager._process 开头清零、由本状态机在 _physics_process 读取，
## 两者不同频时按键被静默丢弃（表现为「按好几次才出一次攻击」）。
## 改为走时间戳缓存 has_pending_attack()，任何调用时机都可靠。
func _attack() -> void:
	var p := player
	# 攻击缓存窗口 = GameBalance.ATTACK_INPUT_BUFFER（与连段窗口一致）
	var buffer: float = GameBalance.ATTACK_INPUT_BUFFER
	var dir_2d := InputManager.take_buffered_attack(buffer)
	if dir_2d == Vector2.ZERO:
		return

	# 冷却前半段锁定，后摇取消窗口内可接下一击
	var in_recovery := p._attack_timer > 0.0 and p._in_cancel_window()
	var blocked := p._attack_timer > 0.0 and not in_recovery
	if blocked or (p._combo and p._combo.attack_in_progress):
		return  # 不消费输入：等冷却结束后缓存仍可生效
	# 跳跃攻击阶段中不接受新攻击
	if p._jump_phase != Player.JumpPhase.NONE:
		return
	# 冲撞位移中不接受
	if p._sprint_attack_timer > 0.0:
		return

	# 到这里确定要出招。注意：attack_is_jump_combo 依赖 attack_direction 非零，
	# 故必须在消费输入之前判定。
	var is_jump_combo := InputManager.attack_is_jump_combo()
	InputManager.consume_attack()

	p._facing = InputManager.direction_2d_to_3d(dir_2d.normalized())
	if p._facing.length_squared() < 0.001:
		p._facing = Vector3.FORWARD

	# 1) 跳跃攻击：空格+方向键组合（连段派生：清冷却直接起手）
	if is_jump_combo:
		if in_recovery:
			p._cancel_current_attack()
		finished.emit("JumpAttackState", {})
		return

	# 2) 奔跑攻击（冲撞）：需**持续奔跑超过 SPRINT_ATTACK_MIN_HOLD** 才算数。
	# 刚起步就按攻击走普攻——这就是「一边跑动一边普攻」的宽限：
	# 玩家想普攻时不必先停下来，只要不是长期保持冲刺态即可。
	# 同时避免误触冲撞白白消耗掉冲刺惯性。
	if p._is_sprinting and p.sprint_hold >= GameBalance.SPRINT_ATTACK_MIN_HOLD:
		if in_recovery:
			p._cancel_current_attack()
		finished.emit("SprintAttackState", {})
		return

	# 3) 普攻连段（后摇取消窗口内允许下一击——连段提速）
	if in_recovery:
		p._cancel_current_attack()
	p._start_normal_attack()
