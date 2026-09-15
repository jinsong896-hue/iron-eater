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
