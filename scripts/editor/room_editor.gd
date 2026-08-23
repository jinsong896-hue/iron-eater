@tool
extends Node2D
## 房间编辑器 —— 完全可视化，打开场景即可用
##
## 图层（z 顺序）：
##   Floor(0)  Detail(1)  Wall(2)  Obstacle(3)  Interact(4)
##
## 快捷键：Ctrl+S 保存

const SAVE_DIR := "res://rooms/editor/saved"
const DataScript := preload("res://scripts/editor/room_editor_data.gd")

# 预设模板：名称 -> {floor, walls, detail}
const TEMPLATES := {
	"空地": {},
	"四面墙": {"walls": "border"},
	"十字通道": {"walls": "cross"},
	"双房间": {"walls": "double"},
	"环形柱": {"walls": "ring"},
	"四柱": {"walls": "pillars"},
	"牢笼": {"walls": "prison"},
	"破损": {"walls": "broken"},
}

var _current_file := ""

@onready var _name_input: LineEdit = $UI/Panel/VBox/NameRow/NameInput
@onready var _width_spin: SpinBox = $UI/Panel/VBox/SizeRow/WidthSpin
@onready var _height_spin: SpinBox = $UI/Panel/VBox/SizeRow/HeightSpin
@onready var _type_opt: OptionButton = $UI/Panel/VBox/TypeRow/TypeOption
@onready var _min_spin: SpinBox = $UI/Panel/VBox/TypeRow/MinEnemy
@onready var _max_spin: SpinBox = $UI/Panel/VBox/TypeRow/MaxEnemy
@onready var _template_opt: OptionButton = $UI/Panel/VBox/TemplateRow/TemplateOption
@onready var _room_list: ItemList = $UI/Panel/VBox/RoomList
@onready var _status: Label = $UI/Panel/VBox/Status


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_list()
		_show("就绪")


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_S:
			_do_save()
			get_viewport().set_input_as_handled()


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
		_show("双击列表中的房间来加载")
		return
	_load_room(_room_list.get_item_text(sel[0]))


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
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	_apply_template("空地", w, h)
	# 铺地板
	var layer := _find_layer("floor")
	if layer:
		layer.clear()
		for x in w:
			for y in h:
				var alt := TilesetFactory.TILE_FLOOR_A if (x * 7 + y * 13) % 9 != 0 else TilesetFactory.TILE_FLOOR_B
				layer.set_cell(Vector2i(x, y), 0, alt)
	_show("已填充地板 %dx%d" % [w, h])


func _on_template_pressed() -> void:
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	var key := _template_opt.get_item_text(_template_opt.selected)
	_apply_template(key, w, h)
	_show("已应用模板: %s" % key)


func _on_fill_walls_pressed() -> void:
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	_apply_template("四面墙", w, h)
	_show("已填充墙壁 %dx%d" % [w, h])


func _on_copy_pressed() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入新名称后点另存为")
		return
	_do_save()
	_show("已另存为 %s.tres" % name_str)


func _on_delete_pressed() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_show("请先在列表中选中要删除的房间")
		return
	var name_str := _room_list.get_item_text(sel[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_show("已删除 %s" % name_str)
	_refresh_list()


func _on_list_activated(_idx: int) -> void:
	_on_load_pressed()


func _do_save() -> void:
	var name_str := _name_input.text.strip_edges()
	if name_str.is_empty():
		_show("请输入房间名")
		return
	_current_file = name_str
	var data := _collect_data()
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if FileAccess.file_exists(path):
		var bak_path := path + ".bak"
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		DirAccess.rename_absolute(path, bak_path)
	_write_file(name_str, data)
	var stats := _tile_stats()
	_show("已保存 %s.tres (地板:%d 墙:%d 装饰:%d 障碍:%d 交互:%d)" % [name_str, stats[0], stats[1], stats[2], stats[3], stats[4]])
	_refresh_list()


func _tile_stats() -> Array:
	var counts := [0, 0, 0, 0, 0]
	var hints := ["floor", "wall", "detail", "obstacle", "interact"]
	for i in hints.size():
		var layer := _find_layer(hints[i])
		if layer:
			counts[i] = layer.get_used_cells().size()
	return counts


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
	_width_spin.value = int(data.get("room_width"))
	_height_spin.value = int(data.get("room_height"))
	_type_opt.select(int(data.get("room_type")))
	_min_spin.value = float(data.get("min_enemies"))
	_max_spin.value = float(data.get("max_enemies"))
	var stats := _tile_stats()
	_show("已加载 %s (地板:%d 墙:%d)" % [name_str, stats[0], stats[1]])


func _collect_data() -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", _current_file)
	data.set("room_width", int(_width_spin.value))
	data.set("room_height", int(_height_spin.value))
	data.set("room_type", _type_opt.selected)
	data.set("min_enemies", int(_min_spin.value))
	data.set("max_enemies", int(_max_spin.value))
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


## ---- 模板系统 ----

func _apply_template(key: String, w: int, h: int) -> void:
	var wall_layer := _find_layer("wall")
	var detail_layer := _find_layer("detail")
	if wall_layer:
		wall_layer.clear()
	if detail_layer:
		detail_layer.clear()

	match key:
		"四面墙":
			# 2 格厚的外墙
			for x in w:
				for i in 2:
					wall_layer.set_cell(Vector2i(x, i), 0, TilesetFactory.TILE_WALL)
					wall_layer.set_cell(Vector2i(x, h - 1 - i), 0, TilesetFactory.TILE_WALL)
			for y in h:
				for i in 2:
					wall_layer.set_cell(Vector2i(i, y), 0, TilesetFactory.TILE_WALL)
					wall_layer.set_cell(Vector2i(w - 1 - i, y), 0, TilesetFactory.TILE_WALL)

		"十字通道":
			_apply_template("四面墙", w, h)
			# 十字隔墙
			var cx := w / 2
			var cy := h / 2
			for x in range(4, w - 4):
				wall_layer.set_cell(Vector2i(x, cy), 0, TilesetFactory.TILE_WALL)
			for y in range(4, h - 4):
				wall_layer.set_cell(Vector2i(cx, y), 0, TilesetFactory.TILE_WALL)

		"双房间":
			_apply_template("四面墙", w, h)
			var cx := w / 2
			for y in range(2, h - 2):
				if y < h / 2 - 2 or y > h / 2 + 1:
					wall_layer.set_cell(Vector2i(cx, y), 0, TilesetFactory.TILE_WALL)

		"环形柱":
			_apply_template("四面墙", w, h)
			var cx := w / 2
			var cy := h / 2
			# 画 4 个柱子在中间围成环形
			for x in range(cx - 3, cx + 4):
				wall_layer.set_cell(Vector2i(x, cy - 3), 0, TilesetFactory.TILE_WALL)
				wall_layer.set_cell(Vector2i(x, cy + 3), 0, TilesetFactory.TILE_WALL)
			for y in range(cy - 3, cy + 4):
				wall_layer.set_cell(Vector2i(cx - 3, y), 0, TilesetFactory.TILE_WALL)
				wall_layer.set_cell(Vector2i(cx + 3, y), 0, TilesetFactory.TILE_WALL)

		"四柱":
			_apply_template("四面墙", w, h)
			for px in [w / 4, 3 * w / 4]:
				for py in [h / 4, 3 * h / 4]:
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							wall_layer.set_cell(Vector2i(px + dx, py + dy), 0, TilesetFactory.TILE_WALL)

		"牢笼":
			_apply_template("四面墙", w, h)
			var bar := TilesetFactory.TILE_BAR
			for y in range(3, h - 3):
				if y < h / 2 - 2 or y > h / 2 + 1:
					wall_layer.set_cell(Vector2i(w / 3, y), 0, bar)
					wall_layer.set_cell(Vector2i(2 * w / 3, y), 0, bar)

		"破损":
			_apply_template("四面墙", w, h)
			# 随机挖掉一些墙，放碎石
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var grasstiles := TilesetFactory.TILE_GRASS
			for x in range(2, w - 2):
				for y in [1, h - 2]:
					if rng.randf() < 0.3:
						wall_layer.erase_cell(Vector2i(x, y))
						if detail_layer and not grasstiles.is_empty():
							detail_layer.set_cell(Vector2i(x, y), 0, grasstiles[rng.randi() % grasstiles.size()])


func _make_empty() -> Resource:
	var data := Resource.new()
	data.set_script(DataScript)
	data.set("room_name", _current_file)
	data.set("room_width", int(_width_spin.value))
	data.set("room_height", int(_height_spin.value))
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
## ---- 房间预览 ----

func _on_preview_pressed() -> void:
	var preview: Control = $UI/Panel/VBox/PreviewRect
	preview.queue_redraw()
	_show("已刷新预览")


func _draw_preview(preview: Control) -> void:
	var w := int(_width_spin.value)
	var h := int(_height_spin.value)
	if w <= 0 or h <= 0:
		return
	var cell_w := preview.size.x / float(w)
	var cell_h := preview.size.y / float(h)
	var cell_size := minf(cell_w, cell_h)

	# 地板
	var floor_layer := _find_layer("floor")
	if floor_layer:
		for cell in floor_layer.get_used_cells():
			var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
			preview.draw_rect(rect, Color(0.4, 0.35, 0.3), true)

	# 墙
	var wall_layer := _find_layer("wall")
	if wall_layer:
		for cell in wall_layer.get_used_cells():
			var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
			preview.draw_rect(rect, Color(0.5, 0.45, 0.4), true)

	# 装饰
	var detail_layer := _find_layer("detail")
	if detail_layer:
		for cell in detail_layer.get_used_cells():
			var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
			preview.draw_rect(rect, Color(0.3, 0.6, 0.3), true)

	# 障碍
	var obstacle_layer := _find_layer("obstacle")
	if obstacle_layer:
		for cell in obstacle_layer.get_used_cells():
			var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
			preview.draw_rect(rect, Color(0.6, 0.3, 0.2), true)

	# 交互
	var interact_layer := _find_layer("interact")
	if interact_layer:
		for cell in interact_layer.get_used_cells():
			var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
			preview.draw_rect(rect, Color(1.0, 0.8, 0.2), true)
