extends Node
## 场景管理器 —— HD-2D 重构版
## 统一管理场景切换

var _current_scene_path := ""


## 切换到指定场景
func change_scene(scene_path: String, with_transition: bool = false) -> void:
	_current_scene_path = scene_path
	get_tree().change_scene_to_file(scene_path)


## 重新加载当前场景
func reload_current() -> void:
	if _current_scene_path.is_empty():
		return
	get_tree().change_scene_to_file(_current_scene_path)


## 回到主菜单
func go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## 进入地下城
func go_to_dungeon() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 获取当前场景路径
func get_current_scene() -> String:
	return _current_scene_path