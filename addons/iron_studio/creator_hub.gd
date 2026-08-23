@tool
extends Control
## IronEater Creator Hub

var _editor_interface: EditorInterface = null


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _load_editor(scene_path: String) -> void:
	var content: Control = $Main/Content
	for child in content.get_children():
		child.queue_free()
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return
	var ed := scene.instantiate()
	if ed.has_method("setup"):
		ed.setup(_editor_interface)
	content.add_child(ed)


func _on_character_pressed(): _load_editor("res://addons/iron_studio/character_dock.tscn")
func _on_equipment_pressed(): _load_editor("res://addons/iron_studio/panels/equipment_dock.tscn")
func _on_skill_pressed(): _load_editor("res://addons/iron_studio/panels/skill_dock.tscn")
func _on_monster_pressed(): _load_editor("res://addons/iron_studio/panels/monster_dock.tscn")
func _on_balance_pressed(): _load_editor("res://addons/iron_studio/panels/balance_dock.tscn")
func _on_asset_pressed(): _load_editor("res://addons/iron_studio/panels/asset_dock.tscn")
func _on_buff_pressed(): _load_editor("res://addons/iron_studio/panels/buff_dock.tscn")
func _on_room_pressed():
	if _editor_interface:
		_editor_interface.set_main_screen_editor("2D")
		_editor_interface.open_scene_from_path("res://rooms/editor/room_editor.tscn")
func _on_home_pressed():
	var content: Control = $Main/Content
	for child in content.get_children():
		child.queue_free()
