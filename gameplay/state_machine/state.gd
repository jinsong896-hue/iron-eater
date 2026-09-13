class_name State
extends RefCounted
## 状态基类 —— 纯逻辑，不进场景树
##
## 参考 GameDev.tv《Godot Roguelite》课程状态机模式（State.gd），
## 但载体改为 RefCounted：状态可像 AttackCombo 那样 new() 出来直接单测，
## 无需挂到场景树上。
##
## 转移由 finished 信号驱动：状态自己决定何时结束，
## 发出目标状态名（与注册名一致）+ 可选数据，由 StateMachine 完成切换。

## 状态请求转移到下一个状态。next_state 是注册时用的名字。
## 注意：GDScript 不允许信号参数带默认值，故每次 emit 必须显式传两个参数。
signal finished(next_state: String, data: Dictionary)


## 接收未处理的输入事件（由 StateMachine 转发）
func handle_input(_event: InputEvent) -> void:
	pass


## 每物理帧推进（由 StateMachine 转发）
func physics_update(_delta: float) -> void:
	pass


## 进入本状态。previous 是上一状态名，data 是转移时携带的数据
func enter(_previous: String, _data: Dictionary = {}) -> void:
	pass


## 离开本状态，做清理
func exit() -> void:
	pass
