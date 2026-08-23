@tool
extends Control
## 房间编辑器底部面板

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
	_show("就绪")


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
		_show("请先打开 room_editor.tscn")
		return
	# 清空图层
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()
	# 确保目录存在
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := _make_data(name_str)
	var err := ResourceSaver.save(data, SAVE_DIR + "/" + name_str + ".tres")
	if err == OK:
		_show("已新建 %s.tres" % name_str)
		_refresh_list()
	else:
		_show("新建失败：%d" % err)


func _on_save_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return

	# 第1步：获取场景根节点
	var root := _root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn（当前未检测到场景）")
		return
	_show("检测到场景：%s，正在收集瓦片..." % root.name)

	# 第2步：收集各层瓦片
	var floor_layer := _find_layer("floor")
	var wall_layer := _find_layer("wall")
	var detail_layer := _find_layer("detail")
	var obstacle_layer := _find_layer("obstacle")
	var interact_layer := _find_layer("interact")

	if floor_layer == null:
		_show("错误：找不到 FloorLayer，场景不对？")
		return

	var floor_tiles := _tiles(floor_layer)
	var wall_tiles := _tiles(wall_layer)
	var detail_tiles := _tiles(detail_layer)
	var obstacle_tiles := _tiles(obstacle_layer)
	var interact_tiles := _tiles(interact_layer)

	var total := floor_tiles.size() + wall_tiles.size() + detail_tiles.size() + obstacle_tiles.size() + interact_tiles.size()
	if total == 0:
		_show("警告：没有检测到任何瓦片！请先在画布上画瓦片再保存")
		return

	# 第3步：创建数据
	var data := _make_data(name_str)
	data.call("set_floor_from_dict", floor_tiles)
	data.call("set_wall_from_dict", wall_tiles)
	data.call("set_detail_from_dict", detail_tiles)
	data.call("set_obstacle_from_dict", obstacle_tiles)
	data.call("set_interact_from_dict", interact_tiles)

	# 第4步：保存文件
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var err := ResourceSaver.save(data, path)
	if err == OK:
		_show("已保存！（地板:%d 墙:%d 装饰:%d 障碍:%d 交互:%d）" % [floor_tiles.size(), wall_tiles.size(), detail_tiles.size(), obstacle_tiles.size(), interact_tiles.size()])
		_refresh_list()
	else:
		_show("保存失败，错误码：%d" % err)


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
	_on_clear_pressed()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num


func _on_clear_pressed() -> void:
	var root := _root()
	if root == null:
		return
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()
	_show("已清空")


func _on_fill_pressed() -> void:
	var layer := _find_layer("floor")
	if layer == null:
		_show("找不到 FloorLayer，请先打开 room_editor.tscn")
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
