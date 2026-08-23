@tool
extends Control
## 房间编辑器底部面板：保存/加载/新建/填充
## 由 plugin.gd 注入 editor_interface 引用

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _editor_interface: EditorInterface = null

@onready var _name_input: LineEdit = $Main/NameBox/NameInput
@onready var _type_opt: OptionButton = $Main/TypeBox/TypeOption
@onready var _min_spin: SpinBox = $Main/EnemyBox/EnemyRow/MinEnemy
@onready var _max_spin: SpinBox = $Main/EnemyBox/EnemyRow/MaxEnemy
@onready var _room_list: ItemList = $Main/RoomList
@onready var _status: Label = $Main/Status


func _ready() -> void:
	_refresh_list()
	_show("就绪：打开 room_editor.tscn → 画瓦片 → 点保存")


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _root() -> Node2D:
	if _editor_interface == null:
		return null
	return _editor_interface.get_edited_scene_root() as Node2D


func _find_layer(hint: String) -> TileMapLayer:
	var root := _root()
	if root == null:
		return null
	for child in root.get_children():
		if child is TileMapLayer and child.name.to_lower().find(hint) >= 0:
			return child
	return null


func _tiles(layer) -> Dictionary:
	var d := {}
	if layer == null:
		return d
	for cell in layer.get_used_cells():
		d[cell] = layer.get_cell_atlas_coords(cell)
	return d


func _apply(layer, d: Dictionary) -> void:
	if layer == null:
		return
	layer.clear()
	for cell in d:
		layer.set_cell(cell, 0, d[cell])


func _show(msg: String) -> void:
	_status.text = msg
	print("[RoomEditor] ", msg)


## ---- 按钮 ----

func _on_new_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()
	var data := _make_data(name_str)
	var err := ResourceSaver.save(data, SAVE_DIR + "/" + name_str + ".tres")
	if err == OK:
		_show("已新建 %s.tres，现在画瓦片" % name_str)
		_refresh_list()
	else:
		_show("新建失败：%d" % err)


func _on_save_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	var data := _make_data(name_str)
	var floor_tiles := _tiles(_find_layer("floor"))
	var wall_tiles := _tiles(_find_layer("wall"))
	var detail_tiles := _tiles(_find_layer("detail"))
	var obstacle_tiles := _tiles(_find_layer("obstacle"))
	var interact_tiles := _tiles(_find_layer("interact"))
	data.call("set_floor_from_dict", floor_tiles)
	data.call("set_wall_from_dict", wall_tiles)
	data.call("set_detail_from_dict", detail_tiles)
	data.call("set_obstacle_from_dict", obstacle_tiles)
	data.call("set_interact_from_dict", interact_tiles)
	var total := floor_tiles.size() + wall_tiles.size() + detail_tiles.size() + obstacle_tiles.size() + interact_tiles.size()
	var err := ResourceSaver.save(data, SAVE_DIR + "/" + name_str + ".tres")
	if err == OK:
		_show("已保存 %s.tres（%d 个瓦片）" % [name_str, total])
		_refresh_list()
	else:
		_show("保存失败：%d" % err)


func _on_load_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_show("请先在列表中双击一个房间")
		return
	var name_str := _room_list.get_item_text(sel[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path):
		_show("文件不存在")
		return
	var data: Resource = load(path)
	if data == null:
		_show("加载失败")
		return
	var root := _root()
	if root == null:
		return
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()
	_apply(_find_layer("floor"), data.call("get_floor_dict"))
	_apply(_find_layer("wall"), data.call("get_wall_dict"))
	_apply(_find_layer("detail"), data.call("get_detail_dict"))
	_apply(_find_layer("obstacle"), data.call("get_obstacle_dict"))
	_apply(_find_layer("interact"), data.call("get_interact_dict"))
	_name_input.text = name_str
	_type_opt.select(int(data.get("room_type")))
	_min_spin.value = float(data.get("min_enemies"))
	_max_spin.value = float(data.get("max_enemies"))
	_show("已加载 %s" % name_str)


func _on_next_pressed() -> void:
	var root := _root()
	if root == null:
		return
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_show("已清空，输入名称 → 新建")


func _on_fill_pressed() -> void:
	var layer := _find_layer("floor")
	if layer == null:
		_show("找不到 FloorLayer")
		return
	layer.clear()
	for x in 16:
		for y in 12:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			layer.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板 16×12")


## ---- 数据 ----

func _make_data(name_str: String) -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.set("room_type", _type_opt.selected)
	data.set("min_enemies", int(_min_spin.value))
	data.set("max_enemies", int(_max_spin.value))
	return data


## ---- 列表 ----

func _refresh_list() -> void:
	_room_list.clear()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			_room_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()
