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
## 用户报告「点窗口 X 只关掉边框、进程不退出」。`auto_accept_quit` 默认
## 为 true（本项目的 project.godot 没改它），正常情况下引擎会自行退出，
## 故这多半是 **Windows 下的渲染/窗口层问题**，不是脚本逻辑。
##
## 但这里加一道保险：收到关闭请求时**直接 quit()**，绕过引擎默认流程里
## 可能卡住的环节（例如渲染线程仍在等一帧、或某个 autoload 的
## `_exit_tree` 阻塞）。
##
## **不能反过来造成"退不掉"**：quit() 只是请求退出，引擎仍会走清理流程；
## 若清理本身卡住，这里也救不了——那种情况需要单独定位阻塞源。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


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
