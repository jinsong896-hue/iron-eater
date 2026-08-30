@tool
extends EditorPlugin

var _dock: Control


func _enter_tree() -> void:
	_dock = preload("res://addons/room_editor/room_editor_dock.tscn").instantiate()
	_dock.setup(get_editor_interface())
	add_control_to_bottom_panel(_dock, "房间编辑器")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
