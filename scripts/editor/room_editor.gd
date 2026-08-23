@tool
extends Node2D
## 房间编辑器 —— 挂在 room_editor.tscn 上
## 插件通过 _editor_interface 找到此节点，调用 save_room/load_room 等方法

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _current_file := ""   # 当前编辑的文件名


func _ready() -> void:
	pass


## 供插件调用的公开方法

func save_room(room_name: String, room_type: int, min_e: int, max_e: int) -> void:
	_current_file = room_name
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", room_name)
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.set("room_type", room_type)
	data.set("min_enemies", min_e)
	data.set("max_enemies", max_e)
	data.call("set_floor_from_dict", _tiles_of("floor"))
	data.call("set_wall_from_dict", _tiles_of("wall"))
	data.call("set_detail_from_dict", _tiles_of("detail"))
	data.call("set_obstacle_from_dict", _tiles_of("obstacle"))
	data.call("set_interact_from_dict", _tiles_of("interact"))
	var err := ResourceSaver.save(data, _file_path(room_name))
	if err == OK:
		print("[RoomEditor] 已保存 %s.tres" % room_name)
	else:
		print("[RoomEditor] 保存失败：%d" % err)


func load_room(room_name: String) -> void:
	_current_file = room_name
	var path := _file_path(room_name)
	if not FileAccess.file_exists(path):
		print("[RoomEditor] 文件不存在：%s" % path)
		return
	var data: Resource = load(path)
	if data == null:
		print("[RoomEditor] 加载失败")
		return
	_clear_all_layers()
	_apply_tiles(_find_layer("floor"), data.call("get_floor_dict"))
	_apply_tiles(_find_layer("wall"), data.call("get_wall_dict"))
	_apply_tiles(_find_layer("detail"), data.call("get_detail_dict"))
	_apply_tiles(_find_layer("obstacle"), data.call("get_obstacle_dict"))
	_apply_tiles(_find_layer("interact"), data.call("get_interact_dict"))
	print("[RoomEditor] 已加载 %s" % room_name)


func new_room(room_name: String) -> void:
	_clear_all_layers()
	_current_file = room_name
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", room_name)
	data.set("room_width", 16)
	data.set("room_height", 12)
	ResourceSaver.save(data, _file_path(room_name))
	print("[RoomEditor] 已新建 %s.tres" % room_name)


func fill_floor() -> void:
	var layer := _find_layer("floor")
	if layer == null:
		return
	layer.clear()
	for x in 16:
		for y in 12:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			layer.set_cell(Vector2i(x, y), 0, alt)
	print("[RoomEditor] 已填充地板 16x12")


func clear_all() -> void:
	_clear_all_layers()
	_current_file = ""
	print("[RoomEditor] 已清空")


## ---- 内部 ----

func _file_path(name_str: String) -> String:
	return SAVE_DIR + "/" + name_str + ".tres"


func _tiles_of(hint: String) -> Dictionary:
	var layer := _find_layer(hint)
	if layer == null:
		return {}
	var d := {}
	for cell in layer.get_used_cells():
		d[cell] = layer.get_cell_atlas_coords(cell)
	return d


func _apply_tiles(layer: TileMapLayer, d: Dictionary) -> void:
	if layer == null:
		return
	layer.clear()
	for cell in d:
		layer.set_cell(cell, 0, d[cell])


func _find_layer(hint: String) -> TileMapLayer:
	for child in get_children():
		if child is TileMapLayer and child.name.to_lower().find(hint) >= 0:
			return child
	return null


func _clear_all_layers() -> void:
	for child in get_children():
		if child is TileMapLayer:
			child.clear()
