extends Node
## 场景管理器 —— HD-2D 重构版
## 统一管理场景切换 + 加载过渡
##
## **加载时长预算（策划总册 11.8 性能预算）**：
##   单房间加载 < 1 秒。此处作为全局唯一真相，
##   LoadingScreen 的两段动画都以它为准。

## 策划硬性预算：单房间加载 < 1 秒（总册 11.8）
const LOAD_BUDGET_SECONDS := 1.0

var _current_scene_path := ""
var _loading: LoadingScreen = null


func _ready() -> void:
	# 过渡屏挂在 SceneManager（autoload）下，**跨场景存活**，
	# 否则 change_scene 会把挂在旧场景里的过渡屏一起销毁，黑屏直接闪掉。
	var packed: PackedScene = load("res://ui/loading/loading_screen.tscn")
	if packed != null:
		_loading = packed.instantiate() as LoadingScreen
		add_child(_loading)
	# 窗口关闭的兜底处理（见 _notification）
	set_process(false)


## 窗口关闭请求的**兜底**处理。
##
## 用户报告「点窗口 X 只关掉边框、进程不退出」。
##
## ## 为什么 _notification 这条路不够
##
## `NOTIFICATION_WM_CLOSE_REQUEST` 只在窗口收到关闭事件时派发，
## 而它在某些情况下**不会到达**（渲染线程仍在跑、窗口已被系统标记为关闭、
## 或 autoload 的节点树在那一刻不活跃）。实测「只关边框不退进程」正是这种：
## 事件到了 OS 层，进程还在跑。
##
## ## 两道保险
##
## ① `_notification`：常规路径（事件正常派发时立即退出）
## ② `_process` 轮询：**兜底**——每帧检查窗口是否已被要求关闭。
##    代价是每帧一次极廉价的比较，换来「点 X 一定退得掉」。
##
## `auto_accept_quit` 保持默认 true，引擎自身的退出流程不受影响。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_now()


func _process(_delta: float) -> void:
	# 兜底：窗口「曾经可见、现在不可见」= 用户点了 X（或系统关掉了窗口），
	# 但退出事件没送达 → 强制退出。
	#
	# **必须先记住曾经可见**：启动瞬间窗口可能尚未显示，
	# 不加这个判断会在开机第一帧就退出。
	var win := get_window()
	if win == null:
		return
	if win.visible:
		_window_was_visible = true
		return
	if _window_was_visible:
		_quit_now()


## 立即退出（幂等——两条路径可能同时触发）
func _quit_now() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().quit()


## 记住窗口是否曾经可见（用于区分「尚未显示」与「已被关闭」）
var _window_was_visible := false
var _quitting := false


## 取过渡屏（GameRoot 的第二段房内进度条要用）
func loading() -> LoadingScreen:
	return _loading


## 切换到指定场景。
## with_transition=true 时走「盖上 → 切场景 → 等满最低时长 → 淡出」。
func change_scene(scene_path: String, with_transition: bool = false) -> void:
	_current_scene_path = scene_path
	if with_transition and _loading != null:
		await _loading.begin(LOAD_BUDGET_SECONDS, "", "正在进入地下城…")
		get_tree().change_scene_to_file(scene_path)
		await _loading.finish()
		return
	get_tree().change_scene_to_file(scene_path)


## 重新加载当前场景
func reload_current() -> void:
	if _current_scene_path.is_empty():
		return
	get_tree().change_scene_to_file(_current_scene_path)


## 回到主菜单
func go_to_main_menu() -> void:
	await change_scene("res://scenes/ui/main_menu.tscn", true)


## 进入地下城
func go_to_dungeon() -> void:
	await change_scene("res://scenes/main.tscn", true)


## 获取当前场景路径
func get_current_scene() -> String:
	return _current_scene_path
