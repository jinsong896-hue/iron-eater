@tool
extends Control
## 房间编辑器启动面板 —— 在标签页中打开房间编辑器场景

var _editor_interface: EditorInterface = null


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _on_open_pressed() -> void:
	if _editor_interface:
		_editor_interface.set_main_screen_editor("2D")
		_editor_interface.open_scene_from_path("res://rooms/editor/room_editor.tscn")
		print("[IronStudio] 已打开房间编辑器")


func _on_refresh_pressed() -> void:
	var dir := DirAccess.open("res://rooms/editor/saved")
	if dir == null: return
	var count := 0
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): count += 1
		f = dir.get_next()
	dir.list_dir_end()
	print("[IronStudio] 已保存房间: %d个" % count)
