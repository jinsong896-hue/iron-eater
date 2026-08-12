extends CanvasLayer
## 统一 Toast 通知：《页面相关2.md》——右下角淡入淡出，2~3 秒消失

var _container: VBoxContainer
var _active_toasts: Array = []


func _ready() -> void:
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS
	_container = VBoxContainer.new()
	_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_container.position = Vector2(-330, -90)
	_container.custom_minimum_size = Vector2(300, 0)
	_container.add_theme_constant_override("separation", 8)
	add_child(_container)


func notify(text: String) -> void:
	var panel := PanelContainer.new()
	panel.modulate.a = 0.0
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(0.93, 0.92, 0.9)
	panel.add_child(label)
	_container.add_child(panel)
	_active_toasts.append(panel)
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.2)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func():
		_active_toasts.erase(panel)
		panel.queue_free())
