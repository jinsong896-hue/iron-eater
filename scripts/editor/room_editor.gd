@tool
class_name RoomEditor
extends Node2D
## 房间编辑器：在 Godot 编辑器中直接画房间地形
## 用法：打开 rooms/editor/room_editor.tscn → 选图层 → 用 TileMap 工具画 → 保存
##
## 图层说明：
##   FloorLayer（z=0）：地板
##   WallLayer（z=2）：墙壁（带碰撞）
##   DetailLayer（z=1）：装饰（草地/血迹/碎石）
##
## 操作流程：
##   1. 在场景树中选中 FloorLayer / WallLayer / DetailLayer
##   2. 在底部 TileMap 面板选瓦片（点一下就能看到所有可用瓦片）
##   3. 在画布上点击绘制
##   4. 点右上角面板的「保存」→ 存为 .tres
##   5. 游戏运行时 DungeonGenerator 自动加载
##
## 替换素材（换成你自己的瓦片图）：
##   1. 打开 rooms/editor/editor_tileset.tres
##   2. 在 TileSet 底部面板找到 "Atlas" 源
##   3. 把 Texture 替换为你的 PNG 素材
##   4. 如果 PNG 的瓦片排列不同，调整 Texture Region Size
##   5. 重新打开 room_editor.tscn 即可看到新素材

const SAVE_DIR := "res://rooms/editor/saved"

@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var wall_layer: TileMapLayer = $WallLayer
@onready var detail_layer: TileMapLayer = $DetailLayer
@onready var spawn_markers: Node2D = $SpawnMarkers
@onready var chest_markers: Node2D = $ChestMarkers
@onready var player_marker: Marker2D = $PlayerSpawn
@onready var room_name_input: LineEdit = $EditorUI/Panel/VBox/RoomName/LineEdit
@onready var width_spin: SpinBox = $EditorUI/Panel/VBox/Size/Width
@onready var height_spin: SpinBox = $EditorUI/Panel/VBox/Size/Height
@onready var room_list: ItemList = $EditorUI/Panel/VBox/RoomList
@onready var status_label: Label = $EditorUI/Panel/VBox/Status


func _ready() -> void:
	# 瓦片集已预分配在场景中（editor_tileset.tres），无需运行时赋值
	_refresh_room_list()
	_show_status("就绪：选图层 → 选瓦片 → 画 → 保存")


## ---------------------------------------------------------------------------
## 按钮回调
## ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var name_str := room_name_input.text.strip_edges()
	if name_str.is_empty():
		_show_status("错误：房间名不能为空")
		return
	var data := _collect_data()
	var path := SAVE_DIR + "/" + name_str + ".tres"
	var err := ResourceSaver.save(data, path)
	if err == OK:
		_show_status("已保存：%s" % path)
		_refresh_room_list()
	else:
		_show_status("保存失败：%d" % err)


func _on_load_pressed() -> void:
	var selected := room_list.get_selected_items()
	if selected.is_empty():
		_show_status("请先从列表中选择一个房间")
		return
	var name_str := room_list.get_item_text(selected[0])
	var path := SAVE_DIR + "/" + name_str + ".tres"
	if not FileAccess.file_exists(path):
		_show_status("文件不存在：%s" % path)
		return
	var data: Resource = load(path)
	if data == null:
		_show_status("加载失败：%s" % path)
		return
	_apply_data(data)
	_show_status("已加载：%s" % name_str)


func _on_clear_pressed() -> void:
	floor_layer.clear()
	wall_layer.clear()
	detail_layer.clear()
	for child in spawn_markers.get_children():
		child.queue_free()
	for child in chest_markers.get_children():
		child.queue_free()
	room_name_input.text = ""
	_show_status("已清空所有图层")


func _on_fill_floor_pressed() -> void:
	var w := int(width_spin.value)
	var h := int(height_spin.value)
	for x in w:
		for y in h:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			floor_layer.set_cell(Vector2i(x, y), 0, alt)
	_show_status("已填充地板：%d×%d" % [w, h])


func _on_add_spawn_pressed() -> void:
	var marker := Marker2D.new()
	marker.name = "Spawn_%d" % spawn_markers.get_child_count()
	marker.position = Vector2(float(width_spin.value) * 32.0, float(height_spin.value) * 32.0)
	spawn_markers.add_child(marker)
	marker.owner = spawn_markers
	_show_status("已添加敌人出生点，拖拽到目标位置")


func _on_add_chest_pressed() -> void:
	var marker := Marker2D.new()
	marker.name = "Chest_%d" % chest_markers.get_child_count()
	marker.position = Vector2(float(width_spin.value) * 32.0, float(height_spin.value) * 32.0)
	chest_markers.add_child(marker)
	marker.owner = chest_markers
	_show_status("已添加宝箱点，拖拽到目标位置")


## ---------------------------------------------------------------------------
## 数据收集 / 还原（使用 Resource 基类，避免 class_name 解析问题）
## ---------------------------------------------------------------------------

func _collect_data() -> Resource:
	var data := RoomEditorData.new()
	data.room_name = room_name_input.text.strip_edges()
	data.room_width = int(width_spin.value)
	data.room_height = int(height_spin.value)
	data.set_floor_from_dict(_collect_tiles(floor_layer))
	data.set_wall_from_dict(_collect_tiles(wall_layer))
	data.set_detail_from_dict(_collect_tiles(detail_layer))
	data.player_spawn = player_marker.position
	for child in spawn_markers.get_children():
		if child is Marker2D:
			data.enemy_spawns.append(child.position)
	for child in chest_markers.get_children():
		if child is Marker2D:
			data.chest_spawns.append(child.position)
	return data


func _collect_tiles(layer: TileMapLayer) -> Dictionary:
	var result := {}
	for cell in layer.get_used_cells():
		result[cell] = layer.get_cell_atlas_coords(cell)
	return result


func _apply_data(data: Resource) -> void:
	if data == null:
		return
	floor_layer.clear()
	wall_layer.clear()
	detail_layer.clear()
	for child in spawn_markers.get_children():
		child.queue_free()
	for child in chest_markers.get_children():
		child.queue_free()
	_apply_tiles(floor_layer, data.call("get_floor_dict"))
	_apply_tiles(wall_layer, data.call("get_wall_dict"))
	_apply_tiles(detail_layer, data.call("get_detail_dict"))
	room_name_input.text = str(data.get("room_name"))
	width_spin.value = float(data.get("room_width"))
	height_spin.value = float(data.get("room_height"))
	player_marker.position = data.get("player_spawn")
	for pos in data.get("enemy_spawns"):
		var marker := Marker2D.new()
		marker.position = pos
		spawn_markers.add_child(marker)
	for pos in data.get("chest_spawns"):
		var marker := Marker2D.new()
		marker.position = pos
		chest_markers.add_child(marker)


func _apply_tiles(layer: TileMapLayer, dict: Dictionary) -> void:
	for cell in dict:
		layer.set_cell(cell, 0, dict[cell])


## ---------------------------------------------------------------------------
## 房间列表
## ---------------------------------------------------------------------------

func _refresh_room_list() -> void:
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


func _on_room_list_item_activated(_index: int) -> void:
	_on_load_pressed()


## ---------------------------------------------------------------------------
## 状态显示
## ---------------------------------------------------------------------------

func _show_status(text: String) -> void:
	if status_label:
		status_label.text = text
	print("[RoomEditor] %s" % text)