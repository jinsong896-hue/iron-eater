@tool
extends Control
## 房间编辑器 vFinal —— 完整功能集成到 IronEater Studio

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _editor_interface: EditorInterface = null

@onready var _name_input: LineEdit = $Main/NameRow/NameInput
@onready var _width_spin: SpinBox = $Main/SizeRow/WidthSpin
@onready var _height_spin: SpinBox = $Main/SizeRow/HeightSpin
@onready var _type_opt: OptionButton = $Main/TypeRow/TypeOption
@onready var _min_spin: SpinBox = $Main/TypeRow/MinEnemy
@onready var _max_spin: SpinBox = $Main/TypeRow/MaxEnemy
@onready var _template_opt: OptionButton = $Main/TemplateRow/TemplateOption
@onready var _room_list: ItemList = $Main/RoomList
@onready var _status: Label = $Main/Status


func _ready() -> void:
	_refresh_list()
	_show("就绪 - 打开 room_editor.tscn 开始画瓦片")


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
	if dir == null: return
	dir.list_dir_begin(); var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"): _room_list.add_item(f.trim_suffix(".tres"))
		f = dir.get_next()
	dir.list_dir_end()


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()


func _safe_arr(arr) -> Array:
	return arr if arr is Array else []


func _collect_tiles(root: Node2D, hint: String) -> Dictionary:
	var result := {}
	for c in root.get_children():
		if c is TileMapLayer and c.name.to_lower().find(hint) >= 0:
			var layer := c as TileMapLayer
			for cell in layer.get_used_cells():
				result[cell] = {
					"s": layer.get_cell_source_id(cell),
					"a": layer.get_cell_atlas_coords(cell),
				}
	return result


func _apply_tiles(root: Node2D, hint: String, cells: Array, atlas: Array, sources: Array) -> void:
	for c in root.get_children():
		if c is TileMapLayer and c.name.to_lower().find(hint) >= 0:
			var layer := c as TileMapLayer
			layer.clear()
			for i in cells.size():
				var sid: int = sources[i] if i < sources.size() else 0
				layer.set_cell(cells[i], sid, atlas[i])


func _clear_all(root: Node2D) -> void:
	for c in root.get_children():
		if c is TileMapLayer:
			(c as TileMapLayer).clear()


func _on_new_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty(): _show("请输入房间名"); return
	_clear_all(root)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(_serialize(_make_empty(name_str)))
		file.close()
	_show("已新建 %s.tres" % name_str)
	_refresh_list()


func _on_save_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty(): _show("请输入房间名"); return

	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", int(_width_spin.value))
	data.set("room_height", int(_height_spin.value))
	data.set("room_type", _type_opt.selected)
	data.set("min_enemies", int(_min_spin.value))
	data.set("max_enemies", int(_max_spin.value))

	var layers := ["floor", "wall", "detail", "obstacle", "interact"]
	var counts := []
	for prefix in layers:
		var tiles := _collect_tiles(root, prefix)
		var cells: Array[Vector2i] = []
		var atlases: Array[Vector2i] = []
		var sources: Array = []
		for cell in tiles:
			var info: Dictionary = tiles[cell]
			cells.append(cell)
			atlases.append(info.get("a", Vector2i.ZERO))
			sources.append(info.get("s", 0))
		data.set(prefix + "_cells", cells)
		data.set(prefix + "_atlas", atlases)
		data.set(prefix + "_sources", sources)
		counts.append(cells.size())

	var doors: Array[Vector2] = []
	var door_node := root.get_node_or_null("DoorMarkers") as Node2D
	if door_node:
		for c in door_node.get_children():
			if c is Marker2D:
				doors.append(c.position)
	data.set("door_markers", doors)

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: _show("保存失败"); return
	file.store_string(_serialize(data))
	file.close()
	_show("已保存！(地板:%d 墙:%d 装饰:%d 障碍:%d 交互:%d)" % [counts[0], counts[1], counts[2], counts[3], counts[4]])
	_refresh_list()


func _on_load_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty(): _show("双击列表中的房间来加载"); return
	var name_str := _room_list.get_item_text(sel[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path): _show("文件不存在"); return
	var data: Resource = load(path)
	if data == null: _show("加载失败"); return
	var root := _root()
	if root == null: return
	_clear_all(root)
	var layers := ["floor", "wall", "detail", "obstacle", "interact"]
	for prefix in layers:
		_apply_tiles(root, prefix, _safe_arr(data.get(prefix + "_cells")), _safe_arr(data.get(prefix + "_atlas")), _safe_arr(data.get(prefix + "_sources")))
	_name_input.text = name_str
	_width_spin.value = float(data.get("room_width"))
	_height_spin.value = float(data.get("room_height"))
	_type_opt.select(int(data.get("room_type")))
	_min_spin.value = float(data.get("min_enemies"))
	_max_spin.value = float(data.get("max_enemies"))
	_show("已加载 %s" % name_str)


func _on_clear_pressed() -> void:
	var root := _root()
	if root != null: _clear_all(root)
	_show("已清空")


func _on_next_pressed() -> void:
	_on_clear_pressed()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"): num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_show("准备画 %s" % _name_input.text)


func _on_fill_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	for c in root.get_children():
		if c is TileMapLayer and c.name.to_lower().find("floor") >= 0:
			var layer := c as TileMapLayer
			layer.clear()
			for x in w:
				for y in h:
					var alt := TilesetFactory.TILE_FLOOR_A if (x * 7 + y * 13) % 9 != 0 else TilesetFactory.TILE_FLOOR_B
					layer.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板 %dx%d" % [w, h])


func _on_fill_walls_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	for c in root.get_children():
		if c is TileMapLayer and c.name.to_lower().find("wall") >= 0:
			var layer := c as TileMapLayer
			layer.clear()
			_draw_border(layer, w, h)
	_show("已填充墙壁 %dx%d" % [w, h])


func _on_template_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	var key := _template_opt.get_item_text(_template_opt.selected)
	var wall_layer: TileMapLayer = null
	for c in root.get_children():
		if c is TileMapLayer and c.name.to_lower().find("wall") >= 0:
			wall_layer = c as TileMapLayer; break
	if wall_layer == null: return
	wall_layer.clear()
	match key:
		"四面墙": _draw_border(wall_layer, w, h)
		"十字通道":
			_draw_border(wall_layer, w, h)
			for x in range(4, w - 4): wall_layer.set_cell(Vector2i(x, h / 2), 0, TilesetFactory.TILE_WALL)
			for y in range(4, h - 4): wall_layer.set_cell(Vector2i(w / 2, y), 0, TilesetFactory.TILE_WALL)
		"双房间":
			_draw_border(wall_layer, w, h)
			for y in range(2, h - 2):
				if y < h / 2 - 2 or y > h / 2 + 1:
					wall_layer.set_cell(Vector2i(w / 2, y), 0, TilesetFactory.TILE_WALL)
		"四柱":
			_draw_border(wall_layer, w, h)
			for px in [w / 4, 3 * w / 4]:
				for py in [h / 4, 3 * h / 4]:
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							wall_layer.set_cell(Vector2i(px + dx, py + dy), 0, TilesetFactory.TILE_WALL)
		"牢笼":
			_draw_border(wall_layer, w, h)
			for y in range(3, h - 3):
				if y < h / 2 - 2 or y > h / 2 + 1:
					wall_layer.set_cell(Vector2i(w / 3, y), 0, TilesetFactory.TILE_BAR)
					wall_layer.set_cell(Vector2i(2 * w / 3, y), 0, TilesetFactory.TILE_BAR)
	_show("已应用模板: %s" % key)


func _draw_border(layer: TileMapLayer, w: int, h: int) -> void:
	for x in w:
		for i in 2:
			layer.set_cell(Vector2i(x, i), 0, TilesetFactory.TILE_WALL)
			layer.set_cell(Vector2i(x, h - 1 - i), 0, TilesetFactory.TILE_WALL)
	for y in h:
		for i in 2:
			layer.set_cell(Vector2i(i, y), 0, TilesetFactory.TILE_WALL)
			layer.set_cell(Vector2i(w - 1 - i, y), 0, TilesetFactory.TILE_WALL)


func _on_delete_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty(): _show("请先选中要删除的房间"); return
	var name_str := _room_list.get_item_text(sel[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_show("已删除 %s" % name_str); _refresh_list()


func _on_copy_pressed() -> void:
	_on_save_pressed()
	_show("已另存为 %s.tres" % _name_input.text.strip_edges())


func _on_save_template_pressed() -> void:
	_on_save_pressed()
	_show("已保存当前房间为模板")


func _on_add_door_pressed() -> void:
	var root := _root()
	if root == null: _show("请先打开 room_editor.tscn"); return
	var door_node := root.get_node_or_null("DoorMarkers") as Node2D
	if door_node == null: _show("场景缺少 DoorMarkers 节点"); return
	var marker := Marker2D.new()
	marker.name = "Door_%d" % door_node.get_child_count()
	marker.position = Vector2(float(_width_spin.value) * 32.0, float(_height_spin.value) * 32.0)
	door_node.add_child(marker)
	_show("已添加门生成点，拖拽到目标位置")


func _make_empty(name_str: String) -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", name_str)
	data.set("room_width", int(_width_spin.value))
	data.set("room_height", int(_height_spin.value))
	return data


func _serialize(data: Resource) -> String:
	var lines: Array = []
	lines.append('[gd_resource type="Resource" script_class="RoomEditorData" format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://scripts/editor/room_editor_data.gd" id="1"]')
	lines.append("")
	lines.append("[resource]")
	lines.append("script = ExtResource(\"1\")")
	for key in ["room_name", "room_width", "room_height", "room_type", "min_enemies", "max_enemies"]:
		var val = data.get(key)
		if val is String: lines.append('%s = "%s"' % [key, val])
		else: lines.append("%s = %d" % [key, int(val) if val != null else 0])
	for key in ["floor_cells", "floor_atlas", "wall_cells", "wall_atlas", "detail_cells", "detail_atlas", "obstacle_cells", "obstacle_atlas", "interact_cells", "interact_atlas"]:
		var arr: Array = data.get(key)
		if arr.is_empty(): continue
		lines.append("%s = Array[Vector2i]([%s])" % [key, _fmt_v2i(arr)])
	for key in ["floor_sources", "wall_sources", "detail_sources", "obstacle_sources", "interact_sources"]:
		var arr: Array = data.get(key)
		if arr.is_empty(): continue
		lines.append("%s = Array[int]([%s])" % [key, _fmt_int(arr)])
	var doors: Array = data.get("door_markers")
	if not doors.is_empty():
		lines.append("door_markers = Array[Vector2]([%s])" % _fmt_v2(doors))
	return "\n".join(lines) + "\n"


func _fmt_v2i(arr: Array) -> String:
	var parts: PackedStringArray = []
	for v in arr: parts.append("Vector2i(%d, %d)" % [v.x, v.y])
	return ", ".join(parts)


func _fmt_v2(arr: Array) -> String:
	var parts: PackedStringArray = []
	for v in arr: parts.append("Vector2(%f, %f)" % [v.x, v.y])
	return ", ".join(parts)


func _fmt_int(arr: Array) -> String:
	var parts: PackedStringArray = []
	for v in arr: parts.append(str(v))
	return ", ".join(parts)