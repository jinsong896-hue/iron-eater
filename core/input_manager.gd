extends Node
## 输入管理器 —— HD-2D 重构版
## 抽象所有输入，解耦键盘/手柄与游戏逻辑
## 移动：WASD / 上下左右 / 左摇杆 + 十字键
## 攻击：方向键 / WASD 方向攻击 / 右摇杆（八方向）
## 技能：数字键 1-4 / Q E R F / X Y LB RB
## 交互：E / 空格 / A
##
## **手柄映射写在 `project.godot` 的 InputMap 里**（不在此处硬编码）：
## 这样编辑器「项目设置 → 输入映射」能看到并改，且本文件对两者一视同仁——
## 下面全部走 `Input.is_action_*`，天然同时支持键盘与手柄。
##
## 手柄布局（Xbox）：移动左摇杆+十字键 / 攻击右摇杆 / 交互 A / 翻滚 B /
## 技能 X·Y·LB·RB / 冲刺 L3 / 吞噬 R3 / 背包 BACK / 暂停 START。
## 攻击刻意走右摇杆而非 ABXY——攻击是八方向扇形判定，摇杆能表达方向、
## 按钮不能（详见 README「操作」节）。

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

## 技能按下的时间戳（槽位 0~3）。
## **不能只靠 skill_N_pressed 标记**：那个标记在 _process 每帧重写，
## 而消费者（Player._physics_process）与它不同频，跨节点读取必然漏帧——
## 这正是攻击输入曾经踩过的坑（见 has_pending_attack 的注释）。
## 时间戳让任何调用时机都可靠，且能实现「输入缓冲」。
var _skill_press_time := {0: -999.0, 1: -999.0, 2: -999.0, 3: -999.0}
## 技能输入缓冲窗口（秒）：按下后这段时间内消费都算数
const SKILL_INPUT_BUFFER := 0.25

# 交互
var interact_pressed := false
var devour_pressed := false
var inventory_toggle_pressed := false
var pause_pressed := false


func _process(_delta: float) -> void:
	# 调试控制台打开时：打字不能操作角色。
	# LineEdit 只吞**事件**，而这里是**每帧轮询** Input 单例，两者互不影响——
	# 不早退的话，输入 `spawn rat_king` 时 w/a/s/d 会边走边打字、1-4 会放技能。
	if _debug_text_input_active():
		_clear_all_input()
		return

	# 移动方向
	move_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# 翻滚时间戳（跳跃攻击组合判定用）
	if Input.is_action_just_pressed("dodge"):
		_dodge_time = Time.get_ticks_msec() / 1000.0

	# 攻击方向（立即响应，不持续）+ 缓存；方向键组合 = 斜向 45°
	attack_direction = Vector2.ZERO
	if Input.is_action_just_pressed("attack_up"):
		attack_direction.y -= 1.0
	elif Input.is_action_just_pressed("attack_down"):
		attack_direction.y += 1.0
	if Input.is_action_just_pressed("attack_left"):
		attack_direction.x -= 1.0
	elif Input.is_action_just_pressed("attack_right"):
		attack_direction.x += 1.0

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
	# 技能按下也要打时间戳：玩家在 _physics_process 消费，而本函数在 _process，
	# 两者不同频会漏帧（与攻击输入同一个坑，见 has_pending_attack 的注释）。
	for i in range(4):
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			_skill_press_time[i] = Time.get_ticks_msec() / 1000.0

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


## 是否有未被消费的攻击输入（含缓存）。
## 与 has_attack_request() 的区别：后者只看当前帧且与 _process 同频，
## 跨节点调用必然漏帧；本方法以时间戳判定，任何调用时机都可靠。
func has_pending_attack(buffer_time: float = 0.2) -> bool:
	return take_buffered_attack(buffer_time) != Vector2.ZERO


## 消费攻击输入（清除缓存与当前帧标记）。
## 修复「按五次才出一次」：原先 attack_direction 在 _process 开头清零、
## 由 _physics_process 读取，两者不同频时按键被静默丢弃，且缓存只在
## 冷却中才被查询。改为「读时间戳 → 消费时清除」，不再依赖帧对齐。
func consume_attack() -> void:
	_buffered_attack = Vector2.ZERO
	_buffered_attack_time = -999.0
	attack_direction = Vector2.ZERO


# ============================================================
# 技能输入（时间戳缓存，与攻击同一模式）
# ============================================================

## 该槽位是否有未消费的技能按下（缓冲窗口内）
func skill_pressed(slot: int) -> bool:
	var t := float(_skill_press_time.get(slot, -999.0))
	return (Time.get_ticks_msec() / 1000.0) - t <= SKILL_INPUT_BUFFER


## 消费技能输入（清除该槽位的时间戳，避免一次按键放两次）
func consume_skill(slot: int) -> void:
	_skill_press_time[slot] = -999.0


## 清空全部技能输入缓存（切形态/打开面板时用）
func clear_skill_inputs() -> void:
	for k in _skill_press_time.keys():
		_skill_press_time[k] = -999.0


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


## 调试控制台是否正在接收文本输入（无 DebugManager 时为 false，测试场景友好）
func _debug_text_input_active() -> bool:
	var dm := get_node_or_null("/root/DebugManager")
	if dm != null and dm.has_method("is_text_input_active"):
		return bool(dm.call("is_text_input_active"))
	return false


## 清空本帧的全部输入输出（控制台打字期间调用）
func _clear_all_input() -> void:
	move_direction = Vector2.ZERO
	attack_direction = Vector2.ZERO
	skill_1_pressed = false
	skill_2_pressed = false
	skill_3_pressed = false
	skill_4_pressed = false
	interact_pressed = false
	devour_pressed = false
	inventory_toggle_pressed = false
	pause_pressed = false


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