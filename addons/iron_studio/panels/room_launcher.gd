@tool
extends Control
## 房间编辑器启动面板

var _editor_interface: EditorInterface = null


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _on_open_pressed() -> void:
	print("[RoomLauncher] 按钮被点击")
	var iface := _editor_interface
	if iface == null:
		iface = EditorInterface.get_singleton()
		print("[RoomLauncher] fallback to singleton: %s" % str(iface))
	if iface == null:
		print("[RoomLauncher] ERROR: no editor interface")
		return
	iface.set_main_screen_editor("2D")
	iface.open_scene_from_path("res://rooms/editor/room_editor.tscn")
	print("[RoomLauncher] 场景已打开")


func _on_refresh_pressed() -> void:
	print("[RoomLauncher] 刷新按钮被点击")
	var dir := DirAccess.open("res://rooms/editor/saved")
	if dir == null:
		print("[RoomLauncher] 目录不存在")
		return
	var count := 0
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): count += 1
		f = dir.get_next()
	dir.list_dir_end()
	print("[RoomLauncher] 已保存房间: %d个" % count)
