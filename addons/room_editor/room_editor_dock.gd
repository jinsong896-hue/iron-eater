@tool
extends Control
## 房间编辑器 —— 直接从场景节点读写瓦片，不依赖任何中间方法

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


func _show(msg: String) -> void:
	_status.text = msg
	print("[RoomEditor] ", msg)


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


## ---- 直接从场景收集瓦片 ----

func _collect_layer(root: Node2D, hint: String) -> Dictionary:
	var d := {}
	for child in root.get_children():
		if child is TileMapLayer and child.name.to_lower().find(hint) >= 0:
			for cell in child.get_used_cells():
				d[cell] = child.get_cell_atlas_coords(cell)
	return d


func _apply_layer(root: Node2D, hint: String, d: Dictionary) -> void:
	for child in root.get_children():
		if child is TileMapLayer and child.name.to_lower().find(hint) >= 0:
			child.clear()
			for cell in d:
				child.set_cell(cell, 0, d[cell])


func _clear_layers(root: Node2D) -> void:
	for child in root.get_children():
		if child is TileMapLayer:
			child.clear()


## ---- 按钮 ----

func _on_new_pressed() -> void:
	var root := _root()
	if root == null:
		_show("请先打开 room_editor.tscn")
		return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入房间名")
		return
	_clear_layers(root)
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", 16)
	data.set("room_height", 12)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	ResourceSaver.save(data, SAVE_DIR + "/" + name_str + ".tres")
	_show("已新建 %s.tres" % name_str)
	_refresh_list()


func _on_save_pressed() -> void:
	var root := _root()
	if root == null:
		_show("请先打开 room_editor.tscn")
		return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入房间名")
		return

	_show("正在收集瓦片...")
	var floor_tiles := _collect_layer(root, "floor")
	var wall_tiles := _collect_layer(root, "wall")
	var detail_tiles := _collect_layer(root, "detail")
	var obstacle_tiles := _collect_layer(root, "obstacle")
	var interact_tiles := _collect_layer(root, "interact")
	var total := floor_tiles.size() + wall_tiles.size() + detail_tiles.size() + obstacle_tiles.size() + interact_tiles.size()
	_show("收集到 %d 个瓦片，正在写入..." % total)

	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", 16)
	data.set("room_height", 12)
	data.set("room_type", _type_opt.selected)
	data.set("min_enemies", int(_min_spin.value))
	data.set("max_enemies", int(_max_spin.value))
	data.call("set_floor_from_dict", floor_tiles)
	data.call("set_wall_from_dict", wall_tiles)
	data.call("set_detail_from_dict", detail_tiles)
	data.call("set_obstacle_from_dict", obstacle_tiles)
	data.call("set_interact_from_dict", interact_tiles)

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var err := ResourceSaver.save(data, SAVE_DIR + "/" + name_str + ".tres")
	if err == OK:
		_show("已保存！(地板:%d 墙:%d 装饰:%d 障碍:%d 交互:%d)" % [floor_tiles.size(), wall_tiles.size(), detail_tiles.size(), obstacle_tiles.size(), interact_tiles.size()])
		_refresh_list()
	else:
		_show("保存失败：%d" % err)


func _on_load_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_show("双击列表中的房间来加载")
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
	_clear_layers(root)
	_apply_layer(root, "floor", data.call("get_floor_dict"))
	_apply_layer(root, "wall", data.call("get_wall_dict"))
	_apply_layer(root, "detail", data.call("get_detail_dict"))
	_apply_layer(root, "obstacle", data.call("get_obstacle_dict"))
	_apply_layer(root, "interact", data.call("get_interact_dict"))
	_name_input.text = name_str
	_type_opt.select(int(data.get("room_type")))
	_min_spin.value = float(data.get("min_enemies"))
	_max_spin.value = float(data.get("max_enemies"))
	_show("已加载 %s" % name_str)


func _on_clear_pressed() -> void:
	var root := _root()
	if root != null:
		_clear_layers(root)
	_show("已清空")


func _on_next_pressed() -> void:
	_on_clear_pressed()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_show("准备画新房间：%s" % _name_input.text)


func _on_fill_pressed() -> void:
	var root := _root()
	if root == null:
		_show("请先打开 room_editor.tscn")
		return
	# 直接操作 FloorLayer
	for child in root.get_children():
		if child is TileMapLayer and child.name.to_lower().find("floor") >= 0:
			child.clear()
			for x in 16:
				for y in 12:
					var alt := TilesetFactory.TILE_FLOOR_A
					if (x * 7 + y * 13) % 9 == 0:
						alt = TilesetFactory.TILE_FLOOR_B
					child.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板 16x12")
