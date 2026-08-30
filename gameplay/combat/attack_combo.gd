class_name AttackCombo
extends RefCounted
## 连段状态机 —— 四段普攻 + 奔跑/跳跃特殊攻击
## 纯逻辑无节点依赖，可独立单测
## 连段树：普攻1→2→3→4；奔跑攻击→3→4；跳跃攻击→3→4
## 窗口内按下一击接段，超时回普攻1

enum AttackKind {
	NORMAL,    # 普攻（四段连击）
	SPRINT,    # 奔跑攻击（冲撞）
	JUMP,      # 跳跃攻击（后跳→俯冲砸地）
}

# 连段状态
var _stage := 0                    # 当前连段位（0=未开始，1-4=普攻段数）
var _window_timer := 0.0           # 剩余连击窗口
var _attack_kind := AttackKind.NORMAL  # 最后一次攻击类型

# 攻击进行状态（由 Player 驱动：攻击动作开始置 true，动作结束置 false）
var attack_in_progress := false

# 配置（注入便于测试；默认取 GameBalance）
var combo_stages: Array = []
var combo_window := 0.45


func _init(p_stages: Array = [], p_window: float = -1.0) -> void:
	combo_stages = p_stages if not p_stages.is_empty() else GameBalance.COMBO_STAGES
	combo_window = p_window if p_window >= 0.0 else GameBalance.COMBO_WINDOW


## 每帧推进（攻击动作冷却由 Player 管理，这里只管连击窗口）
func tick(delta: float) -> void:
	if _window_timer > 0.0:
		_window_timer = maxf(_window_timer - delta, 0.0)
		if _window_timer == 0.0 and _stage > 0:
			_reset()


## 请求一次普攻：返回攻击段位（1-4），0 = 拒绝（动作进行中）
func request_normal() -> int:
	if attack_in_progress:
		return 0
	var stage := _stage + 1
	if stage > combo_stages.size():
		stage = 1  # 理论不可达（窗口超时已重置），防御
	_stage = stage
	_attack_kind = AttackKind.NORMAL
	return stage


## 请求奔跑攻击：返回 true 接受。奔跑/跳跃攻击重置连段并标记接入点
func request_sprint() -> bool:
	if attack_in_progress:
		return false
	_reset()
	_stage = 2  # 接入点：特殊攻击后下一击是普攻3
	_attack_kind = AttackKind.SPRINT
	return true


## 请求跳跃攻击：同奔跑攻击
func request_jump() -> bool:
	if attack_in_progress:
		return false
	_reset()
	_stage = 2
	_attack_kind = AttackKind.JUMP
	return true


## 攻击动作开始（锁定连段，窗口冻结）
func begin_attack() -> void:
	attack_in_progress = true
	_window_timer = 0.0


## 攻击动作结束：开启连击窗口
func end_attack(window_override: float = -1.0) -> void:
	attack_in_progress = false
	var w := window_override if window_override >= 0.0 else combo_window
	_window_timer = w


## 当前连段位
func current_stage() -> int:
	return _stage


## 下一击的段位（不动状态）
func peek_next_stage() -> int:
	return mini(_stage + 1, combo_stages.size())


## 最后一次攻击类型
func last_attack_kind() -> int:
	return _attack_kind


## 连击窗口剩余（秒）
func window_remaining() -> float:
	return _window_timer


## 是否处于连击中（有段位且窗口未超时）
func is_combo_active() -> bool:
	return _stage > 0 and (_window_timer > 0.0 or attack_in_progress)


## 段位参数：[冷却, 倍率, 距离, 半角, 击退]
func stage_params(stage: int) -> Array:
	if stage < 1 or stage > combo_stages.size():
		return combo_stages[0]
	return combo_stages[stage - 1]


## 重置连段
func _reset() -> void:
	_stage = 0
	_window_timer = 0.0
