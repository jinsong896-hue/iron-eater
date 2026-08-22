class_name Layer1RoomTemplate
extends RoomBase
## 第一层普通战斗房统一模板：《房间生成.md》
## 标准 40×24 格（2×2 母网格）、10 种布局、可配置门、草地装饰、敌人出生点

enum TemplateType {
	T01_OPEN_ARENA, T02_HORIZONTAL_CORRIDOR, T03_VERTICAL_CORRIDOR,
	T04_L_SHAPE, T05_CROSS, T06_DOUBLE_CHAMBER, T07_RING,
	T08_FOUR_PILLARS, T09_PRISON_BARS, T10_BROKEN_ROOM,
}

const RoomDecoratorScript := preload("res://scripts/dungeon/room_decorator.gd")

@export_category("Template")
@export var template_type: TemplateType = TemplateType.T01_OPEN_ARENA

@export var editor_data: Resource = null

@export_category("Room Size")
@export var room_width := 40
@export var room_height := 24
@export var wall_thickness := 2

@export_category("Tiles")
@export var floor_tile := TilesetFactory.TILE_FLOOR_A
@export var wall_tile := TilesetFactory.TILE_WALL
@export var prison_bar_tile := TilesetFactory.TILE_BAR
@export var grass_tiles := TilesetFactory.TILE_GRASS

@export_category("Doors")
@export var north_door := true
@export var south_door := true
@export var east_door := false
@export var west_door := false
@export var door_width := 3

@export_category("Decoration")
@export var grass_density := 0.22
@export var grass_edge_depth := 3

@export_category("Enemies")
@export var enemy_pool: Array[PackedScene] = []
@export var min_enemies := 3
@export var max_enemies := 5
@export var elite_override := false
@export var room_kind_override := -1

# 动态门洞：由地牢生成器按走廊入口写入 {side, center}
var door_openings: Array = []

var rng := RandomNumberGenerator.new()
var enemy_spawn_cells: Array[Vector2i] = []


func _ready() -> void:
	if room_kind_override >= 0:
		room_type = room_kind_override
	else:
		room_type = RoomType.ELITE if elite_override else RoomType.NORMAL
	starts_cleared = false
	rng.randomize()
	_ensure_structure()
	generate_room()
	_decorate()
	super._ready()


func generate_room() -> void:
	ground.clear()
	grass.clear()
	walls.clear()
	enemy_spawn_cells.clear()
	if editor_data != null:
		_apply_editor_data()
		return
	_generate_floor()
	_generate_outer_walls()
	_generate_layout()
	_carve_doors()
	_generate_grass()
	_generate_spawn_points()


func _generate_floor() -> void:
	for x in room_width:
		for y in room_height:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			set_cell(ground, Vector2i(x, y), alt)


func _generate_outer_walls() -> void:
	for x in room_width:
		for i in wall_thickness:
			set_cell(walls, Vector2i(x, i), wall_tile)
			set_cell(walls, Vector2i(x, room_height - 1 - i), wall_tile)
	for y in room_height:
		for i in wall_thickness:
			set_cell(walls, Vector2i(i, y), wall_tile)
			set_cell(walls, Vector2i(room_width - 1 - i, y), wall_tile)


func _generate_layout() -> void:
	if room_width != 40 or room_height != 24:
		# 非 2×2 房间统一使用开阔布局，出生点缩放到安全范围
		template_type = TemplateType.T01_OPEN_ARENA
		if room_width <= 24 or room_height <= 14:
			enemy_spawn_cells = [Vector2i(5, 3), Vector2i(10, 3), Vector2i(6, 7), Vector2i(11, 7), Vector2i(8, 5)]
		else:
			enemy_spawn_cells = [Vector2i(14, 8), Vector2i(25, 8), Vector2i(14, 15), Vector2i(25, 15), Vector2i(20, 11)]
		return
	match template_type:
		TemplateType.T01_OPEN_ARENA:
			enemy_spawn_cells = [Vector2i(14, 8), Vector2i(25, 8), Vector2i(14, 15), Vector2i(25, 15), Vector2i(20, 11)]
		TemplateType.T02_HORIZONTAL_CORRIDOR:
			_paint_wall_rect(Rect2i(4, 4, 10, 5))
			_paint_wall_rect(Rect2i(26, 4, 10, 5))
			_paint_wall_rect(Rect2i(4, 15, 10, 5))
			_paint_wall_rect(Rect2i(26, 15, 10, 5))
			enemy_spawn_cells = [Vector2i(10, 12), Vector2i(16, 10), Vector2i(23, 13), Vector2i(30, 11), Vector2i(20, 12)]
		TemplateType.T03_VERTICAL_CORRIDOR:
			_paint_wall_rect(Rect2i(4, 4, 8, 6))
			_paint_wall_rect(Rect2i(28, 4, 8, 6))
			_paint_wall_rect(Rect2i(4, 14, 8, 6))
			_paint_wall_rect(Rect2i(28, 14, 8, 6))
			enemy_spawn_cells = [Vector2i(18, 6), Vector2i(22, 8), Vector2i(18, 12), Vector2i(22, 15), Vector2i(20, 18)]
		TemplateType.T04_L_SHAPE:
			_paint_wall_rect(Rect2i(23, 3, 14, 10))
			enemy_spawn_cells = [Vector2i(8, 6), Vector2i(14, 9), Vector2i(19, 15), Vector2i(28, 17), Vector2i(10, 18)]
		TemplateType.T05_CROSS:
			_paint_wall_rect(Rect2i(3, 3, 10, 6))
			_paint_wall_rect(Rect2i(27, 3, 10, 6))
			_paint_wall_rect(Rect2i(3, 15, 10, 6))
			_paint_wall_rect(Rect2i(27, 15, 10, 6))
			enemy_spawn_cells = [Vector2i(20, 6), Vector2i(10, 12), Vector2i(30, 12), Vector2i(20, 18), Vector2i(20, 12)]
		TemplateType.T06_DOUBLE_CHAMBER:
			var center_x := room_width / 2
			for y in range(wall_thickness + 1, room_height - wall_thickness - 1):
				if y >= 10 and y <= 13:
					continue
				set_cell(walls, Vector2i(center_x, y), wall_tile)
			enemy_spawn_cells = [Vector2i(9, 7), Vector2i(12, 16), Vector2i(28, 7), Vector2i(30, 16), Vector2i(24, 12)]
		TemplateType.T07_RING:
			_paint_wall_rect(Rect2i(15, 8, 10, 8))
			enemy_spawn_cells = [Vector2i(10, 6), Vector2i(30, 6), Vector2i(9, 18), Vector2i(30, 18), Vector2i(20, 5)]
		TemplateType.T08_FOUR_PILLARS:
			_paint_wall_rect(Rect2i(10, 7, 3, 3))
			_paint_wall_rect(Rect2i(27, 7, 3, 3))
			_paint_wall_rect(Rect2i(10, 15, 3, 3))
			_paint_wall_rect(Rect2i(27, 15, 3, 3))
			enemy_spawn_cells = [Vector2i(20, 6), Vector2i(8, 12), Vector2i(32, 12), Vector2i(20, 18), Vector2i(20, 12)]
		TemplateType.T09_PRISON_BARS:
			for y in range(4, 20):
				if y >= 10 and y <= 13:
					continue
				set_cell(walls, Vector2i(13, y), prison_bar_tile)
				set_cell(walls, Vector2i(27, y), prison_bar_tile)
			enemy_spawn_cells = [Vector2i(7, 7), Vector2i(20, 7), Vector2i(33, 7), Vector2i(12, 17), Vector2i(28, 17)]
		TemplateType.T10_BROKEN_ROOM:
			_paint_wall_rect(Rect2i(5, 5, 4, 3))
			_paint_wall_rect(Rect2i(13, 16, 6, 3))
			_paint_wall_rect(Rect2i(27, 5, 5, 3))
			_paint_wall_rect(Rect2i(31, 15, 4, 4))
			_paint_wall_rect(Rect2i(19, 8, 3, 3))
			enemy_spawn_cells = [Vector2i(10, 11), Vector2i(17, 6), Vector2i(27, 11), Vector2i(23, 18), Vector2i(34, 10)]


func _carve_doors() -> void:
	if not door_openings.is_empty():
		for opening in door_openings:
			RoomBaseCarve.carve_opening(self, opening)
		return
	var center_x := room_width / 2
	var center_y := room_height / 2
	var half := door_width / 2
	if north_door:
		for x in range(center_x - half, center_x + half + 1):
			for y in range(wall_thickness):
				erase_cell(walls, Vector2i(x, y))
	if south_door:
		for x in range(center_x - half, center_x + half + 1):
			for y in range(room_height - wall_thickness, room_height):
				erase_cell(walls, Vector2i(x, y))
	if west_door:
		for y in range(center_y - half, center_y + half + 1):
			for x in range(wall_thickness):
				erase_cell(walls, Vector2i(x, y))
	if east_door:
		for y in range(center_y - half, center_y + half + 1):
			for x in range(room_width - wall_thickness, room_width):
				erase_cell(walls, Vector2i(x, y))


func _generate_grass() -> void:
	if grass_tiles.is_empty():
		return
	for x in range(wall_thickness, room_width - wall_thickness):
		for y in range(wall_thickness, room_height - wall_thickness):
			var cell := Vector2i(x, y)
			if walls.get_cell_source_id(cell) != -1:
				continue
			var edge := mini(mini(x - wall_thickness, room_width - wall_thickness - 1 - x),
				mini(y - wall_thickness, room_height - wall_thickness - 1 - y))
			if edge >= grass_edge_depth:
				continue
			var probability := grass_density * (1.0 - float(edge) / float(grass_edge_depth))
			if rng.randf() > probability:
				continue
			set_cell(grass, cell, grass_tiles[rng.randi_range(0, grass_tiles.size() - 1)])


func _apply_editor_data() -> void:
	## 从 RoomEditorData 还原所有层的瓦片与标记点
	if editor_data == null:
		return
	room_width = int(editor_data.get("room_width"))
	room_height = int(editor_data.get("room_height"))
	_apply_tiles_from_dict(ground, editor_data.call("get_floor_dict"))
	_apply_tiles_from_dict(walls, editor_data.call("get_wall_dict"))
	_apply_tiles_from_dict(grass, editor_data.call("get_detail_dict"))
	# 障碍物层：创建或复用 Obstacles TileMapLayer
	var obstacle_layer := _ensure_layer("Obstacles", 3)
	_apply_tiles_from_dict(obstacle_layer, editor_data.call("get_obstacle_dict"))
	# 交互层：按标记瓦片坐标放置实际对象
	_apply_interact_layer(editor_data.call("get_interact_dict"))
	# 编辑器出生点
	if spawn_points:
		for child in spawn_points.get_children():
			child.queue_free()
		for pos in editor_data.get("enemy_spawns"):
			var marker := Marker2D.new()
			marker.position = pos
			spawn_points.add_child(marker)
	# 编辑器宝箱点
	var objects := get_node_or_null("Objects") as Node2D
	if objects:
		for pos in editor_data.get("chest_spawns"):
			var chest: Node = load("res://scenes/objects/chest.tscn").instantiate()
			chest.position = pos
			objects.add_child(chest)


## 确保有指定名称的 TileMapLayer，不存在则创建
func _ensure_layer(layer_name: String, z: int) -> TileMapLayer:
	var layer := get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TilesetFactory.get_tileset()
		layer.z_index = z
		add_child(layer)
	return layer


## 交互层：按瓦片坐标放置门、火炬、宝箱等对象
func _apply_interact_layer(dict: Dictionary) -> void:
	if dict.is_empty():
		return
	var objects := get_node_or_null("Objects") as Node2D
	if objects == null:
		return
	# 墙壁瓦片(36,1) → 门   栏杆瓦片(51,16) → 宝箱   其他瓦片 → 火炬
	for cell in dict:
		var atlas: Vector2i = dict[cell]
		var pos := Vector2((cell.x + 0.5) * WORLD_TILE, (cell.y + 0.5) * WORLD_TILE)
		var obj: Node = null
		if atlas == TilesetFactory.TILE_WALL:
			obj = load("res://scenes/objects/door.tscn").instantiate()
		elif atlas == TilesetFactory.TILE_BAR:
			obj = load("res://scenes/objects/chest.tscn").instantiate()
		else:
			obj = load("res://scenes/objects/torch.tscn").instantiate()
		if obj != null:
			obj.position = pos
			objects.add_child(obj)


func _apply_tiles_from_dict(layer: TileMapLayer, dict: Dictionary) -> void:
	for cell in dict:
		layer.set_cell(cell, 0, dict[cell])


func _decorate() -> void:
	var decorator := RoomDecoratorScript.new()
	decorator.rng = rng
	decorator.decorate(self)


func _generate_spawn_points() -> void:
	if spawn_points == null:
		return
	for child in spawn_points.get_children():
		if str(child.name).begins_with("AutoSpawn"):
			child.queue_free()
	for i in enemy_spawn_cells.size():
		var marker := Marker2D.new()
		marker.name = "AutoSpawn%02d" % (i + 1)
		spawn_points.add_child(marker)
		var cell := enemy_spawn_cells[i]
		marker.position = Vector2((cell.x + 0.5) * WORLD_TILE, (cell.y + 0.5) * WORLD_TILE)


func _spawn_room_enemies() -> void:
	if enemy_pool.is_empty() or spawn_points == null:
		return
	var points: Array = []
	for child in spawn_points.get_children():
		if child is Marker2D and str(child.name).begins_with("AutoSpawn"):
			points.append(child)
	if points.is_empty():
		return
	var target_count := mini(rng.randi_range(min_enemies, max_enemies), points.size())
	for i in target_count:
		var idx := rng.randi_range(0, points.size() - 1)
		var spawn_point: Marker2D = points[idx]
		points.remove_at(idx)
		var scene: PackedScene = enemy_pool[rng.randi_range(0, enemy_pool.size() - 1)]
		_spawn_enemy(scene, spawn_point)


func set_enemy_pool(pool: Array[PackedScene]) -> void:
	enemy_pool = pool


func _spawn_enemy(scene: PackedScene, spawn_point: Marker2D) -> void:
	if scene == null or enemy_container == null:
		return
	var enemy := scene.instantiate()
	enemy_container.add_child(enemy)
	if enemy is Node2D:
		enemy.global_position = spawn_point.global_position
	register_enemy(enemy)


func _paint_wall_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			set_cell(walls, Vector2i(x, y), wall_tile)
