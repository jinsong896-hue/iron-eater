class_name RoomData
extends RefCounted
## 房间蓝图数据 —— HD-2D 重构版
## 存储房间的语义数据，由 RoomBuilder 转换为 3D 场景
## 数据来源：JSON 房间数据文件

# 基础信息
var room_id := ""
var room_type := "normal"   # normal / elite / boss / treasure / shop / heal / event / start
var width := 16
var height := 12
var cell_size := 1.0
var theme := "crypt"

# 标签（用于随机匹配）
var tags: Array = []

# 门配置
var doors: Array = []
# 地板数据
var floor_tiles: Array = []
# 墙壁数据
var walls: Array = []
# 实体数据
var entities: Array = []
var interaction: Dictionary = {}


## 从 JSON Dictionary 加载
func load_from_dict(data: Dictionary) -> void:
	room_id = str(data.get("id", data.get("room_id", "")))
	room_type = str(data.get("room_type", "normal"))
	width = int(data.get("width", 16))
	height = int(data.get("height", 12))
	cell_size = float(data.get("cell_size", 1.0))
	theme = str(data.get("theme", "crypt"))
	tags = data.get("tags", [])
	doors = data.get("doors", [])
	floor_tiles = data.get("floor", [])
	walls = data.get("walls", [])
	entities = data.get("entities", [])
	interaction = data.get("interaction", {})


## 导出为 Dictionary
func to_dict() -> Dictionary:
	return {
		"version": 2,
		"room_id": room_id,
		"room_type": room_type,
		"width": width,
		"height": height,
		"cell_size": cell_size,
		"theme": theme,
		"tags": tags,
		"doors": doors,
		"floor": floor_tiles,
		"walls": walls,
		"entities": entities,
		"interaction": interaction,
	}


## 从 JSON 文件加载
static func load_from_file(path: String) -> RoomData:
	if not FileAccess.file_exists(path):
		push_error("RoomData: file not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RoomData: failed to open: %s" % path)
		return null

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("RoomData: JSON parse error: %s" % json.get_error_message())
		return null

	var room := RoomData.new()
	room.load_from_dict(json.data)
	return room


## 获取所有敌人生成点
func get_enemy_spawns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in entities:
		if e.get("type", "") in ["enemy_spawn", "elite_spawn", "boss_spawn"]:
			result.append(e)
	return result


## 获取所有宝箱点
func get_chest_spawns() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in entities:
		if e.get("type", "") == "chest_spawn":
			result.append(e)
	return result


## 获取玩家出生点
func get_player_spawn() -> Dictionary:
	for e in entities:
		if e.get("type", "") == "player_spawn":
			return e
	return {}


## 获取指定方向的门
func get_door(direction: String) -> Dictionary:
	for d in doors:
		if d.get("direction", "") == direction:
			return d
	return {}


## 是否有某个方向的门
func has_door(direction: String) -> bool:
	return not get_door(direction).is_empty()