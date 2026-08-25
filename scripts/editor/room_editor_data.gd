@tool
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
@export var floor_sources: Array = []  ## source_id

## 墙壁层
@export var wall_cells: Array[Vector2i] = []
@export var wall_atlas: Array[Vector2i] = []
@export var wall_sources: Array = []

## 细节层（草地、血迹等）
@export var detail_cells: Array[Vector2i] = []
@export var detail_atlas: Array[Vector2i] = []
@export var detail_sources: Array = []

## 障碍物层（柱子、木桶、碎石等，带碰撞）
@export var obstacle_cells: Array[Vector2i] = []
@export var obstacle_atlas: Array[Vector2i] = []
@export var obstacle_sources: Array = []

## 交互层（门、宝箱、火炬等可交互对象的位置标记）
@export var interact_cells: Array[Vector2i] = []
@export var interact_atlas: Array[Vector2i] = []
@export var interact_sources: Array = []

## 标记点
@export var enemy_spawns: Array[Vector2] = []
@export var chest_spawns: Array[Vector2] = []
@export var door_markers: Array[Vector2] = []  ## 门生成点，x=瓦片坐标.x, y=瓦片坐标.y
@export var door_sprite_path: String = ""  ## 门精灵图目录（含door_north/south/east/west.png）
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


func set_obstacle_from_dict(dict: Dictionary) -> void:
	obstacle_cells.clear()
	obstacle_atlas.clear()
	for cell in dict:
		obstacle_cells.append(cell)
		obstacle_atlas.append(dict[cell])


func set_interact_from_dict(dict: Dictionary) -> void:
	interact_cells.clear()
	interact_atlas.clear()
	for cell in dict:
		interact_cells.append(cell)
		interact_atlas.append(dict[cell])


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


func get_obstacle_dict() -> Dictionary:
	var d := {}
	for i in obstacle_cells.size():
		d[obstacle_cells[i]] = obstacle_atlas[i]
	return d


func get_interact_dict() -> Dictionary:
	var d := {}
	for i in interact_cells.size():
		d[interact_cells[i]] = interact_atlas[i]
	return d
