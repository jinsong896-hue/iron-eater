class_name SceneTransition
extends CanvasLayer
## 场景切换过渡：《开始页面相关.md》——淡入淡出 + 过渡期输入锁

var _fade: ColorRect
var _transitioning := false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.visible = false
	add_child(_fade)


func transition_to(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_fade.visible = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.35)
	await tween.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var tween2 := create_tween()
	tween2.tween_property(_fade, "color:a", 0.0, 0.35)
	await tween2.finished
	_fade.visible = false
	_transitioning = false


func _input(event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()
