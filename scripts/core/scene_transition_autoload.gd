extends Node
## SceneTransition 全局单例：跨场景存活的过渡层，避免切场景时随旧场景销毁

var transition


func _enter_tree() -> void:
	transition = load("res://scripts/ui/menu/scene_transition.gd").new()
	add_child(transition)
