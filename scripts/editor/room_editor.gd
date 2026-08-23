@tool
extends Node2D
## 房间编辑器 @tool 脚本 —— 直接挂在 room_editor.tscn 上
## 工作流：输入名称 → 点「新建」→ 画瓦片 → 点「保存」→ 点「下一个」
##
## 图层：
##   FloorLayer(z=0)   DetailLayer(z=1)   WallLayer(z=2)
##   ObstacleLayer(z=3)   InteractLayer(z=4)

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _current_file := ""  # 当前正在编辑的文件名（不含路径和扩展名）

@onready var _name_input: LineEdit = $UI/NameInput
@onready var _status: Label = $UI/Status


func _ready() -> void:
	if Engine.is_editor_hint():
		_status.text = "输入名称 → 点「新建」"


## ---------------------------------------------------------------------------
## 按钮回调
## ---------------------------------------------------------------------------

## 新建：创建空的 .tres 文件
func _on_new_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_status.text = "错误：请输入房间名"
		return
	_clear_all_layers()
	_current_file = name_str
	var data := _make_empty_data(name_str)
	var err := ResourceSaver.save(data, _file_path())
	if err == OK:
		_status.text = "已新建 %s.tres，现在画瓦片" % name_str
	else:
		_status.text = "新建失败：%d" % err


## 保存：把当前瓦片写入当前文件
func _on_save_pressed() -> void:
	if _current_file.is_empty():
		_status.text = "错误：请先点「新建」创建文件"
		return
	var data := _collect_data()
	var err := ResourceSaver.save(data, _file_path())
	if err == OK:
		_status.text = "已保存 %s.tres" % _current_file
	else:
		_status.text = "保存失败：%d" % err


## 加载：从列表双击加载已有房间
func _on_load_pressed() -> void:
	var list: ItemList = $UI/RoomList
	var sel := list.get_selected_items()
	if sel.is_empty():
		_status.text = "请先在列表中双击一个房间"
		return
	var name_str := list.get_item_text(sel[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path):
		_status.text = "文件不存在"
		return
	var data: Resource = load(path)
	if data == null:
		_status.text = "加载失败"
		return
	_clear_all_layers()
	_apply_data(data)
	_current_file = name_str
	_name_input.text = name_str
	_status.text = "已加载 %s" % name_str


## 下一个：清空图层，自动递增名称
func _on_next_pressed() -> void:
	_clear_all_layers()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_current_file = ""
	_status.text = "已清空，输入名称 → 新建"


## 填充地板（16×12）
func _on_fill_pressed() -> void:
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
	_status.text = "已填充地板 16×12"


## 刷新房间列表
func _on_refresh_pressed() -> void:
	_refresh_list()


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()


## ---------------------------------------------------------------------------
## 内部逻辑
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


func _refresh_list() -> void:
	var list: ItemList = $UI/RoomList
	list.clear()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()
