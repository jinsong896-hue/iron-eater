class_name DungeonRoom
extends Node2D
## 物理房间节点：用仓库瓦片铺地板与 2 瓦片墙（含门洞开凿）、类型标识
## 瓦片规格：《关卡设计分册》二、房间尺寸与瓦片数量（64×64 世界瓦片）

const CELL := Vector2(1280.0, 768.0)
const TILE_SIZE := 64
const WALL_TILES := 2      # 墙厚 2 瓦片
const DOOR_TILES := 3      # 门宽 3 瓦片

enum Side { TOP, BOTTOM, LEFT, RIGHT }

const TYPE_COLORS := {
	RoomData.RoomType.START: Color(0.30, 0.60, 0.42),
	RoomData.RoomType.NORMAL: Color(0.80, 0.82, 0.86),
	RoomData.RoomType.ELITE: Color(1.00, 0.68, 0.25),
	RoomData.RoomType.BOSS: Color(0.95, 0.32, 0.28),
	RoomData.RoomType.SHOP: Color(1.00, 0.85, 0.35),
	RoomData.RoomType.CHEST: Color(0.45, 0.62, 0.95),
	RoomData.RoomType.HEAL: Color(0.35, 0.85, 0.85),
	RoomData.RoomType.EVENT: Color(0.75, 0.48, 0.92),
	RoomData.RoomType.HIDDEN: Color(0.90, 0.55, 0.90),
}

var data: RoomData
var config: ChapterConfig
signal room_entered(room: Node2D)


func set_room_data(room_data: RoomData) -> void:
	data = room_data


func get_room_data() -> RoomData:
	return data


func initialize(room_data: RoomData, cfg: ChapterConfig, _usable_world: Rect2) -> void:
	data = room_data
	config = cfg
	_build_floor()
	_build_walls()
	_build_label()
	_build_player_detector()


## 每母网格格 = 20×12 个 64px 瓦片
func _tiles_per_cell() -> Vector2i:
	return Vector2i(int(CELL.x / TILE_SIZE), int(CELL.y / TILE_SIZE))


## 房间整体尺寸（瓦片数）
func _tile_count() -> Vector2i:
	return Vector2i(data.rect.size) * _tiles_per_cell()


func _build_floor() -> void:
	var tiles := _tile_count()
	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = TilesetFactory.get_tileset()
	layer.z_index = 0
	add_child(layer)
	for x in tiles.x:
		for y in tiles.y:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x * 7 + y * 13) % 9 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			layer.set_cell(Vector2i(x, y), 0, alt)


func _build_walls() -> void:
	var tiles := _tile_count()
	var layer := TileMapLayer.new()
	layer.name = "Walls"
	layer.tile_set = TilesetFactory.get_tileset()
	layer.z_index = 2
	add_child(layer)
	# 顶部/底部墙（2 瓦片厚）
	for x in tiles.x:
		for i in WALL_TILES:
			layer.set_cell(Vector2i(x, i), 0, TilesetFactory.TILE_WALL)
			layer.set_cell(Vector2i(x, tiles.y - 1 - i), 0, TilesetFactory.TILE_WALL)
	# 左侧/右侧墙
	for y in tiles.y:
		for i in WALL_TILES:
			layer.set_cell(Vector2i(i, y), 0, TilesetFactory.TILE_WALL)
			layer.set_cell(Vector2i(tiles.x - 1 - i, y), 0, TilesetFactory.TILE_WALL)
	# 按门洞格开凿（擦除墙瓦片）
	for cell in data.door_cells:
		_carve_door(layer, cell, tiles)


## 把门洞格（母网格坐标）映射到本地瓦片坐标，擦除墙上的门洞
func _carve_door(layer: TileMapLayer, cell: Vector2i, tiles: Vector2i) -> void:
	var tpc := _tiles_per_cell()
	var half := DOOR_TILES / 2
	if cell.y == data.rect.position.y - 1:
		# 北墙
		var cx := (cell.x - data.rect.position.x) * tpc.x + tpc.x / 2
		for y in WALL_TILES:
			for x in range(cx - half, cx - half + DOOR_TILES):
				layer.erase_cell(Vector2i(x, y))
	elif cell.y == data.rect.end.y:
		# 南墙
		var cx := (cell.x - data.rect.position.x) * tpc.x + tpc.x / 2
		for y in range(tiles.y - WALL_TILES, tiles.y):
			for x in range(cx - half, cx - half + DOOR_TILES):
				layer.erase_cell(Vector2i(x, y))
	elif cell.x == data.rect.position.x - 1:
		# 西墙
		var cy := (cell.y - data.rect.position.y) * tpc.y + tpc.y / 2
		for x in WALL_TILES:
			for y in range(cy - half, cy - half + DOOR_TILES):
				layer.erase_cell(Vector2i(x, y))
	elif cell.x == data.rect.end.x:
		# 东墙
		var cy := (cell.y - data.rect.position.y) * tpc.y + tpc.y / 2
		for x in range(tiles.x - WALL_TILES, tiles.x):
			for y in range(cy - half, cy - half + DOOR_TILES):
				layer.erase_cell(Vector2i(x, y))


func _build_player_detector() -> void:
	var detector := Area2D.new()
	detector.name = "PlayerDetector"
	detector.collision_layer = 0
	detector.collision_mask = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(data.rect.size) * CELL
	shape.shape = box
	shape.position = box.size * 0.5
	detector.add_child(shape)
	detector.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			room_entered.emit(self))
	add_child(detector)


func _build_label() -> void:
	var label := Label.new()
	label.name = "TypeLabel"
	label.text = data.type_name()
	label.position = Vector2(WALL_TILES * TILE_SIZE + 16, WALL_TILES * TILE_SIZE + 4)
	label.add_theme_font_size_override("font_size", 28)
	label.modulate = TYPE_COLORS.get(data.type, Color.WHITE)
	add_child(label)
