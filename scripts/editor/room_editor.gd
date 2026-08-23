@tool
extends Node2D
## 房间编辑器——直接在 Godot 2D 视口中画瓦片，通过检查器或快捷键保存
##
## 用法：
##   1. 双击 rooms/editor/room_editor.tscn
##   2. 在场景树中选图层（FloorLayer/WallLayer...）
##   3. 用底部 TileMap 面板画瓦片
##   4. 按 Ctrl+S 保存，或在检查器中设置"保存动作"
##
## 检查器操作：
##   - 房间名称：输入名称
##   - 新建：设为 true 创建新文件
##   - 保存动作：选「保存」→ 写入当前文件
##   - 加载动作：选「加载」→ 从列表加载
##   - 下一个：选「下一个」→ 清空并递增名称

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _current_file := ""  # 当前正在编辑的文件名

@export var 房间名称 := "room_01":
	set(v):
		房间名称 = v
@export var 新建 := false:
	set(v):
		if v:
			_do_new()
			新建 = false
@export var 保存动作 := 0:
	set(v):
		match v:
			1: _do_save()
			2: _do_load()
			3: _do_next()
			4: _do_fill()
		保存动作 = 0
@export_multiline var 状态 := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		状态 = "输入名称 → 新建 → 画瓦片 → 保存"


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				_do_save()
				get_viewport().set_input_as_handled()
			KEY_N:
				_do_new()
				get_viewport().set_input_as_handled()


func _do_new() -> void:
	var name_str := 房间名称.strip_edges()
	if name_str.is_empty():
		状态 = "错误：请输入房间名"
		return
	_clear_all_layers()
	_current_file = name_str
	var data := _make_empty_data(name_str)
	var err := ResourceSaver.save(data, _file_path())
	状态 = "已新建 %s.tres，画瓦片后保存" % name_str if err == OK else "新建失败"


func _do_save() -> void:
	if _current_file.is_empty():
		状态 = "错误：请先新建"
		return
	var data := _collect_data()
	var err := ResourceSaver.save(data, _file_path())
	状态 = "已保存 %s.tres" % _current_file if err == OK else "保存失败"


func _do_load() -> void:
	# 加载列表中的第一个房间（或按名称匹配）
	var load_name := 房间名称.strip_edges()
	# 先尝试按当前名称加载
	var path := SAVE_DIR + "/" + load_name + ".tres"
	if not FileAccess.file_exists(path):
		# 加载任意第一个房间
		var dir := DirAccess.open(SAVE_DIR)
		if dir == null:
			状态 = "没有已保存的房间"
			return
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				load_name = f.trim_suffix(".tres")
				path = SAVE_DIR + "/" + f
				break
			f = dir.get_next()
		dir.list_dir_end()
		if load_name == "":
			状态 = "没有已保存的房间"
			return
	var data: Resource = load(path)
	if data == null:
		状态 = "加载失败"
		return
	_clear_all_layers()
	_apply_data(data)
	_current_file = load_name
	房间名称 = load_name
	状态 = "已加载 %s" % load_name


func _do_next() -> void:
	_clear_all_layers()
	var num := 1
	var old := 房间名称.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	房间名称 = "room_%02d" % num
	_current_file = ""
	状态 = "已清空，输入名称 → 新建"


func _do_fill() -> void:
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
	状态 = "已填充地板 16×12"


## ---------------------------------------------------------------------------
## 内部
## ---------------------------------------------------------------------------

func _file_path() -> String:
	return SAVE_DIR + "/" + _current_file + ".tres"


func _make_empty_data(name_str: String) -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", 16)
	data.set("room_height", 12)
	return data


func _collect_data() -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", _current_file)
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.call("set_floor_from_dict", _tiles_of("floor"))
	data.call("set_wall_from_dict", _tiles_of("wall"))
	data.call("set_detail_from_dict", _tiles_of("detail"))
	data.call("set_obstacle_from_dict", _tiles_of("obstacle"))
	data.call("set_interact_from_dict", _tiles_of("interact"))
	return data


func _apply_data(data: Resource) -> void:
	_apply_tiles(_find_layer("floor"), data.call("get_floor_dict"))
	_apply_tiles(_find_layer("wall"), data.call("get_wall_dict"))
	_apply_tiles(_find_layer("detail"), data.call("get_detail_dict"))
	_apply_tiles(_find_layer("obstacle"), data.call("get_obstacle_dict"))
	_apply_tiles(_find_layer("interact"), data.call("get_interact_dict"))


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
