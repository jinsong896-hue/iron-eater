extends Node
## 输入设备识别：《页面相关2.md》——最近使用键鼠还是手柄，驱动底部操作提示

signal device_changed(using_gamepad: bool)

var using_gamepad := false


func _input(event: InputEvent) -> void:
	var new_state := false
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		new_state = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		new_state = false
	if new_state != using_gamepad:
		using_gamepad = new_state
		device_changed.emit(using_gamepad)


func hint_text() -> String:
	return "A 选择　B 返回" if using_gamepad else "Enter 选择　Esc 返回"
