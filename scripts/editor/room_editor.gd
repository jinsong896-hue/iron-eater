@tool
extends Node2D
## 房间编辑器 @tool 脚本 —— 直接挂在 room_editor.tscn 上
## 打开场景 → 用 Godot TileMap 工具画瓦片 → 用本面板保存/加载
##
## 图层（z 顺序）：
##   FloorLayer(0)  DetailLayer(1)  WallLayer(2)  ObstacleLayer(3)  InteractLayer(4)

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

var _current_file := ""

@onready var _name_input: LineEdit = $UI/Panel/VBox/NameRow/NameInput
@onready var _new_btn: Button = $UI/Panel/VBox/NameRow/NewBtn
@onready var _save_btn: Button = $UI/Panel/VBox/BtnRow/SaveBtn
@onready var _load_btn: Button = $UI/Panel/VBox/BtnRow/LoadBtn
@onready var _clear_btn: Button = $UI/Panel/VBox/BtnRow/ClearBtn
@onready var _next_btn: Button = $UI/Panel/VBox/BtnRow/NextBtn
@onready var _fill_btn: Button = $UI/Panel/VBox/BtnRow/FillBtn
@onready var _room_list: ItemList = $UI/Panel/VBox/RoomList
@onready var _status: Label = $UI/Panel/VBox/Status


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_list()
		_show("就绪 — 在场景树中选择图层，用底部 TileMap 面板画瓦片")


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_S:
			_do_save()
			get_viewport().set_input_as_handled()


## ---- 按钮 ----

func _on_new_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入房间名")
		return
	_clear_all()
	_current_file = name_str
	_write_file(name_str, _make_empty())
	_show("已新建 %s.tres" % name_str)
	_refresh_list()


func _on_save_pressed() -> void:
	_do_save()


func _on_load_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_show("请先在列表中双击一个房间")
		return
	var name_str := _room_list.get_item_text(sel[0])
	_load_room(name_str)


func _on_clear_pressed() -> void:
	_clear_all()
	_current_file = ""
	_show("已清空")


func _on_next_pressed() -> void:
	_clear_all()
	var num := 1
	var old := _name_input.text.strip_edges()
	if old.begins_with("room_"):
		num = int(old.trim_prefix("room_")) + 1
	_name_input.text = "room_%02d" % num
	_current_file = ""
	_show("准备画 %s" % _name_input.text)


func _on_fill_pressed() -> void:
	var layer := _find_layer("floor")
	if layer == null:
		return
	layer.clear()
	for x in 16:
		for y in 12:
			var alt := TilesetFactory.TILE_FLOOR_A if (x * 7 + y * 13) % 9 != 0 else TilesetFactory.TILE_FLOOR_B
			layer.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板 16×12")


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()


## ---- 核心逻辑 ----

func _do_save() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入房间名")
		return
	_current_file = name_str
	var data := _collect_data()
	_write_file(name_str, data)
	_show("已保存 %s.tres" % name_str)
	_refresh_list()


func _load_room(name_str: String) -> void:
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path):
		_show("文件不存在")
		return
	var data: Resource = load(path)
	if data == null:
		_show("加载失败")
		return
	_clear_all()
	_apply_tiles(_find_layer("floor"), data.call("get_floor_dict"))
	_apply_tiles(_find_layer("wall"), data.call("get_wall_dict"))
	_apply_tiles(_find_layer("detail"), data.call("get_detail_dict"))
	_apply_tiles(_find_layer("obstacle"), data.call("get_obstacle_dict"))
	_apply_tiles(_find_layer("interact"), data.call("get_interact_dict"))
	_current_file = name_str
	_name_input.text = name_str
	_show("已加载 %s" % name_str)


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


func _clear_all() -> void:
	for child in get_children():
		if child is TileMapLayer:
			child.clear()


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


func _show(msg: String) -> void:
	_status.text = msg
	print("[RoomEditor] ", msg)


## ---- 手动写文件（不用 ResourceSaver，它在编辑器里会卡死） ----

func _make_empty() -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", _current_file)
	data.set("room_width", 16)
	data.set("room_height", 12)
	return data


func _write_file(name_str: String, data: Resource) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_show("无法创建文件")
		return
	file.store_string(_serialize(data))
	file.close()


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
		if val is String:
			lines.append('%s = "%s"' % [key, val])
		else:
			lines.append("%s = %d" % [key, int(val) if val != null else 0])
	for key in ["floor_cells", "floor_atlas", "wall_cells", "wall_atlas", "detail_cells", "detail_atlas", "obstacle_cells", "obstacle_atlas", "interact_cells", "interact_atlas"]:
		var arr: Array = data.get(key)
		if arr.is_empty():
			continue
		lines.append("%s = Array[Vector2i]([%s])" % [key, _fmt_v2i(arr)])
	return "\n".join(lines) + "\n"


func _fmt_v2i(arr: Array) -> String:
	var parts: PackedStringArray = []
	for v in arr:
		parts.append("(%d, %d)" % [v.x, v.y])
	return ", ".join(parts)
