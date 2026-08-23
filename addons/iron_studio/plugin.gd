@tool
extends EditorPlugin

var _dock: Control


func _enter_tree() -> void:
	_dock = preload("res://addons/iron_studio/studio_tabs.tscn").instantiate()
	_dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	# 添加菜单项
	add_tool_menu_item("IronEater: 打开房间编辑器", _open_room_editor)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	remove_tool_menu_item("IronEater: 打开房间编辑器")


func _open_room_editor() -> void:
	get_editor_interface().set_main_screen_editor("2D")
	var scene := load("res://rooms/editor/room_editor.tscn")
	if scene:
		get_editor_interface().open_scene_from_path("res://rooms/editor/room_editor.tscn")
