extends Node
## 输入管理器 —— HD-2D 重构版
## 抽象所有输入，解耦键盘/手柄与游戏逻辑
## 移动：WASD / 上下左右
## 攻击：方向键 / WASD 方向攻击
## 技能：数字键 1-4 / Q E R F
## 交互：E / 空格

# 输入缓存
var move_direction := Vector2.ZERO
var attack_direction := Vector2.ZERO
var _last_attack_direction := Vector2.DOWN

# 攻击输入缓存（冷却中按下不丢，ATTACK_INPUT_BUFFER 秒内有效）
var _buffered_attack := Vector2.ZERO
var _buffered_attack_time := -999.0

# 跳跃攻击组合：空格后短时间内按攻击（或同时）→ 跳跃攻击
var _dodge_time := -999.0
const DODGE_COMBO_WINDOW := 0.18

# 技能输入
var skill_1_pressed := false
var skill_2_pressed := false
var skill_3_pressed := false
var skill_4_pressed := false

# 交互
var interact_pressed := false
var devour_pressed := false
var inventory_toggle_pressed := false
var pause_pressed := false


func _process(_delta: float) -> void:
	# 移动方向
	move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 翻滚时间戳（跳跃攻击组合判定用）
	if Input.is_action_just_pressed("dodge"):
		_dodge_time = Time.get_ticks_msec() / 1000.0

	# 攻击方向（立即响应，不持续）+ 缓存
	attack_direction = Vector2.ZERO
	if Input.is_action_just_pressed("attack_up"):
		attack_direction = Vector2.UP
	elif Input.is_action_just_pressed("attack_down"):
		attack_direction = Vector2.DOWN
	elif Input.is_action_just_pressed("attack_left"):
		attack_direction = Vector2.LEFT
	elif Input.is_action_just_pressed("attack_right"):
		attack_direction = Vector2.RIGHT

	if attack_direction != Vector2.ZERO:
		_last_attack_direction = attack_direction
		# 记录缓存（带时间戳）
		_buffered_attack = attack_direction
		_buffered_attack_time = Time.get_ticks_msec() / 1000.0

	# 技能
	skill_1_pressed = Input.is_action_just_pressed("skill_1")
	skill_2_pressed = Input.is_action_just_pressed("skill_2")
	skill_3_pressed = Input.is_action_just_pressed("skill_3")
	skill_4_pressed = Input.is_action_just_pressed("skill_4")

	# 交互
	interact_pressed = Input.is_action_just_pressed("interact")
	devour_pressed = Input.is_action_just_pressed("devour")
	inventory_toggle_pressed = Input.is_action_just_pressed("toggle_inventory")
	pause_pressed = Input.is_action_just_pressed("pause")


## 当前帧是否有攻击请求（新按下）
func has_attack_request() -> bool:
	return attack_direction != Vector2.ZERO


## 取缓存攻击方向（ATTACK_INPUT_BUFFER 内有效；过期返回 ZERO）
func take_buffered_attack(buffer_time: float = 0.2) -> Vector2:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _buffered_attack_time <= buffer_time:
		return _buffered_attack
	return Vector2.ZERO


## 攻击是否属于跳跃攻击组合（本次攻击按键落在空格后 DODGE_COMBO_WINDOW 内）
func attack_is_jump_combo() -> bool:
	if attack_direction == Vector2.ZERO:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	return now - _dodge_time <= DODGE_COMBO_WINDOW


## 获取当前攻击方向（如果没有攻击输入，返回最后攻击方向）
func get_attack_direction() -> Vector2:
	if attack_direction != Vector2.ZERO:
		return attack_direction
	return _last_attack_direction


## 获取移动方向，归一化
func get_move_direction() -> Vector2:
	return move_direction.normalized() if move_direction.length() > 0.0 else Vector2.ZERO


## 2D 方向转 3D 世界方向（XZ 平面）
func direction_2d_to_3d(dir_2d: Vector2) -> Vector3:
	return Vector3(dir_2d.x, 0.0, dir_2d.y)


## 获取 3D 世界移动方向
func get_move_direction_3d() -> Vector3:
	return direction_2d_to_3d(get_move_direction())


## 获取 3D 世界攻击方向
func get_attack_direction_3d() -> Vector3:
	return direction_2d_to_3d(get_attack_direction())


## 4 方向 → 8 方向（支持斜角）
func get_attack_direction_8way() -> Vector2:
	var d := get_attack_direction()
	if d == Vector2.ZERO:
		d = Vector2.DOWN
	return d.normalized()