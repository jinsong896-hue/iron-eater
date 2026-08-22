class_name RoomEditorData
extends Resource
## 房间编辑器保存的数据：瓦片坐标数组 + 标记点
## 由 RoomEditor 保存/加载，Layer1RoomTemplate 读取还原

@export var room_name := "untitled"
@export var room_width := 40
@export var room_height := 24
@export var room_type := 0  ## RoomBase.RoomType: 0=START 1=NORMAL 2=ELITE 3=SPECIAL 4=BOSS

## 地板层：cell_positions[i] 使用 atlas_coords[i]
@export var floor_cells: Array[Vector2i] = []
@export var floor_atlas: Array[Vector2i] = []

## 墙壁层
@export var wall_cells: Array[Vector2i] = []
@export var wall_atlas: Array[Vector2i] = []

## 细节层（草地、血迹等）
@export var detail_cells: Array[Vector2i] = []
@export var detail_atlas: Array[Vector2i] = []

## 标记点
@export var enemy_spawns: Array[Vector2] = []
@export var chest_spawns: Array[Vector2] = []
@export var player_spawn := Vector2.ZERO
@export var min_enemies := 3
@export var max_enemies := 5


## 把 Dictionary（Vector2i → Vector2i）写入并行数组
func set_floor_from_dict(dict: Dictionary) -> void:
	floor_cells.clear()
	floor_atlas.clear()
	for cell in dict:
		floor_cells.append(cell)
		floor_atlas.append(dict[cell])


func set_wall_from_dict(dict: Dictionary) -> void:
	wall_cells.clear()
	wall_atlas.clear()
	for cell in dict:
		wall_cells.append(cell)
		wall_atlas.append(dict[cell])


func set_detail_from_dict(dict: Dictionary) -> void:
	detail_cells.clear()
	detail_atlas.clear()
	for cell in dict:
		detail_cells.append(cell)
		detail_atlas.append(dict[cell])


## 还原为 Dictionary（Vector2i → Vector2i）
func get_floor_dict() -> Dictionary:
	var d := {}
	for i in floor_cells.size():
		d[floor_cells[i]] = floor_atlas[i]
	return d


func get_wall_dict() -> Dictionary:
	var d := {}
	for i in wall_cells.size():
		d[wall_cells[i]] = wall_atlas[i]
	return d


func get_detail_dict() -> Dictionary:
	var d := {}
	for i in detail_cells.size():
		d[detail_cells[i]] = detail_atlas[i]
	return d
