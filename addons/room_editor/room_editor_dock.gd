@tool
extends Control
## 房间编辑器停靠面板：保存 / 加载 / 清空 / 填充地板
## 通过 EditorPlugin 获取当前场景的 RoomEditor 节点

const SAVE_DIR := "res://rooms/editor/saved"

@onready var name_input: LineEdit = $VBox/NameBox/LineEdit
@onready var type_opt: OptionButton = $VBox/TypeBox/TypeOption
@onready var min_spin: SpinBox = $VBox/EnemyBox/MinEnemy
@onready var max_spin: SpinBox = $VBox/EnemyBox/MaxEnemy
@onready var room_list: ItemList = $VBox/RoomList
@onready var status: Label = $VBox/Status


func _ready() -> void:
	_refresh_list()
	_show("就绪：打开 room_editor.tscn → 画瓦片 → 点保存")


func _get_editor_root() -> Node2D:
	var iface := EditorInterface.get_singleton()
	if iface == null:
		return null
	return iface.get_edited_scene_root() as Node2D


func _get_tilemap_layers() -> Array:
	var root := _get_editor_root()
	if root == null:
		return []
	var layers: Array = []
	for child in root.get_children():
		if child is TileMapLayer:
			layers.append(child)
	return layers


func _find_layer(layers: Array, name_hint: String) -> TileMapLayer:
	for layer in layers:
		if layer.name.to_lower().find(name_hint) >= 0:
			return layer
	return null


func _collect_tiles(layer: TileMapLayer) -> Dictionary:
	var result := {}
	if layer == null:
		return result
	for cell in layer.get_used_cells():
		result[cell] = layer.get_cell_atlas_coords(cell)
	return result


func _apply_tiles(layer: TileMapLayer, dict: Dictionary) -> void:
	if layer == null:
		return
	layer.clear()
	for cell in dict:
		layer.set_cell(cell, 0, dict[cell])


## ---------------------------------------------------------------------------
## 按钮回调
## ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var root := _get_editor_root()
	if root == null:
		_show("错误：请先打开 rooms/editor/room_editor.tscn")
		return
	var name_str := name_input.text.strip_edges()
	if name_str.is_empty():
		_show("错误：请输入房间名")
		return

	var layers := _get_tilemap_layers()
	var floor_layer := _find_layer(layers, "floor")
	var wall_layer := _find_layer(layers, "wall")
	var detail_layer := _find_layer(layers, "detail")
	var obstacle_layer := _find_layer(layers, "obstacle")
	var interact_layer := _find_layer(layers, "interact")

	var data := RoomEditorData.new()
	data.room_name = name_str
	data.room_width = int(root.get("room_width") if root.get("room_width") != null else 40)
	data.room_height = int(root.get("room_height") if root.get("room_height") != null else 24)
	data.room_type = type_opt.selected
	data.min_enemies = int(min_spin.value)
	data.max_enemies = int(max_spin.value)
	data.set_floor_from_dict(_collect_tiles(floor_layer))
	data.set_wall_from_dict(_collect_tiles(wall_layer))
	data.set_detail_from_dict(_collect_tiles(detail_layer))
	data.set_obstacle_from_dict(_collect_tiles(obstacle_layer))
	data.set_interact_from_dict(_collect_tiles(interact_layer))

	var path := SAVE_DIR + "/" + name_str + ".tres"
	var err := ResourceSaver.save(data, path)
	if err == OK:
		_show("已保存：%s" % path)
		_refresh_list()
	else:
		_show("保存失败：%d" % err)


func _on_load_pressed() -> void:
	var root := _get_editor_root()
	if root == null:
		_show("错误：请先打开 room_editor.tscn")
		return
	var selected := room_list.get_selected_items()
	if selected.is_empty():
		_show("请先从列表中选择一个房间")
		return
	var name_str := room_list.get_item_text(selected[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path):
		_show("文件不存在：%s" % path)
		return
	var data: Resource = load(path)
	if data == null:
		_show("加载失败")
		return

	var layers := _get_tilemap_layers()
	var floor_layer := _find_layer(layers, "floor")
	var wall_layer := _find_layer(layers, "wall")
	var detail_layer := _find_layer(layers, "detail")
	var obstacle_layer := _find_layer(layers, "obstacle")
	var interact_layer := _find_layer(layers, "interact")

	_apply_tiles(floor_layer, data.call("get_floor_dict"))
	_apply_tiles(wall_layer, data.call("get_wall_dict"))
	_apply_tiles(detail_layer, data.call("get_detail_dict"))
	_apply_tiles(obstacle_layer, data.call("get_obstacle_dict"))
	_apply_tiles(interact_layer, data.call("get_interact_dict"))

	name_input.text = str(data.get("room_name"))
	type_opt.select(int(data.get("room_type")))
	min_spin.value = float(data.get("min_enemies"))
	max_spin.value = float(data.get("max_enemies"))
	_show("已加载：%s" % name_str)


func _on_clear_pressed() -> void:
	var root := _get_editor_root()
	if root == null:
		return
	var layers := _get_tilemap_layers()
	for layer in layers:
		layer.clear()
	# 自动递增房间名
	var old_name := name_input.text.strip_edges()
	var num := 1
	if old_name.begins_with("room_"):
		num = int(old_name.trim_prefix("room_")) + 1
	name_input.text = "room_%02d" % num
	_show("已清空，准备画新房间")


func _on_fill_floor_pressed() -> void:
	var root := _get_editor_root()
	if root == null:
		return
	var layers := _get_tilemap_layers()
	var floor_layer := _find_layer(layers, "floor")
	if floor_layer == null:
		_show("找不到 FloorLayer")
		return
	var w := 40
	var h := 24
	if root.get("room_width") != null:
		w = int(root.get("room_width"))
	if root.get("room_height") != null:
		h = int(root.get("room_height"))
	for x in w:
		for y in h:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			floor_layer.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板：%d×%d" % [w, h])


## ---------------------------------------------------------------------------
## 房间列表
## ---------------------------------------------------------------------------

func _refresh_list() -> void:
	room_list.clear()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			room_list.add_item(file.trim_suffix(".tres"))
		file = dir.get_next()
	dir.list_dir_end()


func _on_room_list_item_activated(_idx: int) -> void:
	_on_load_pressed()


func _show(text: String) -> void:
	if status:
		status.text = text
	print("[RoomEditor] %s" % text)
