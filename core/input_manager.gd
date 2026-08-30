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

	# 攻击方向（立即响应，不持续）
	attack_direction = Vector2.ZERO
	if Input.is_action_just_pressed("attack_up"):
		attack_direction = Vector2.UP
	elif Input.is_action_just_pressed("attack_down"):
		attack_direction = Vector2.DOWN
	elif Input.is_action_just_pressed("attack_left"):
		attack_direction = Vector2.LEFT
	elif Input.is_action_just_pressed("attack_right"):
		attack_direction = Vector2.RIGHT

	# 更新最后攻击方向
	if attack_direction != Vector2.ZERO:
		_last_attack_direction = attack_direction

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