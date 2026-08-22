@tool
extends EditorPlugin
## 房间编辑器插件：在 Godot 编辑器底部添加一个房间编辑面板

var _dock: Control


func _enter_tree() -> void:
	_dock = preload("res://addons/room_editor/room_editor_dock.tscn").instantiate()
	_dock.set("editor_interface", get_editor_interface())
	add_control_to_bottom_panel(_dock, "房间编辑器")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()