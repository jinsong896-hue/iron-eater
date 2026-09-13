class_name StateMachine
extends RefCounted
## 状态机 —— 持有状态表，转发输入与物理帧
##
## 参考 GameDev.tv《Godot Roguelite》课程状态机模式（StateMachine.gd），
## 载体改为 RefCounted，由持有者（如 Player）在自己的 _physics_process 里调用。
##
## 状态用字符串名注册（与课件一致），状态通过 finished 信号发出目标名完成转移。

## 状态表：名字 → State 实例
var _states: Dictionary = {}
var _current: State = null
var _current_name := ""


## 注册一个状态
func add_state(state_name: String, state: State) -> void:
	if state == null:
		return
	_states[state_name] = state
	# 状态自行决定何时结束，这里统一接管其 finished 信号
	if not state.finished.is_connected(_on_state_finished):
		state.finished.connect(_on_state_finished)


## 设置初始状态并进入（在 _ready 中调用）
func set_initial(state_name: String) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: 初始状态不存在：%s" % state_name)
		return
	_current = _states[state_name]
	_current_name = state_name
	_current.enter("")


## 转移到一个状态（供外部主动调用）
func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: 目标状态不存在：%s" % state_name)
		return
	var previous := _current_name
	if _current != null:
		_current.exit()
	_current = _states[state_name]
	_current_name = state_name
	_current.enter(previous, data)


## 每物理帧推进当前状态
func physics_update(delta: float) -> void:
	if _current != null:
		_current.physics_update(delta)


## 转发未处理输入
func handle_input(event: InputEvent) -> void:
	if _current != null:
		_current.handle_input(event)


## 当前状态名（空串 = 尚未初始化）
func current_state_name() -> String:
	return _current_name


## 是否处于指定状态
func is_in(state_name: String) -> bool:
	return _current_name == state_name


## 状态发来的转移请求
func _on_state_finished(next_state: String, data: Dictionary) -> void:
	transition_to(next_state, data)
