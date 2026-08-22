class_name StartRoom01
extends RoomBase
## 第一层初始安全房：《房间生成.md》
## 规格：20×12 格（1×1 母网格）、中央暖光、四周草地、南入口/北出口、无刷怪

const RoomDecoratorScript := preload("res://scripts/dungeon/room_decorator.gd")

@export_category("Room Size")
@export var room_width := 20
@export var room_height := 12
@export var wall_thickness := 2

@export_category("Tiles")
@export var floor_tile := TilesetFactory.TILE_FLOOR_A
@export var wall_tile := TilesetFactory.TILE_WALL
@export var grass_tiles := TilesetFactory.TILE_GRASS

@export_category("Grass")
@export var grass_depth := 3
@export var grass_density := 0.7
@export var center_clear_radius := 3.5

@export_category("Lighting")
@export var light_energy := 1.4
@export var light_scale := 4.0

# 动态门洞：由地牢生成器按走廊入口写入 {side, center}
var door_openings: Array = []

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	room_id = "L1_START_01"
	room_type = RoomType.START
	starts_cleared = true
	rng.randomize()
	_ensure_structure()
	generate_room()
	_setup_light()
	_decorate()
	super._ready()


func _decorate() -> void:
	var decorator := RoomDecoratorScript.new()
	decorator.rng = rng
	decorator.decorate(self)


func generate_room() -> void:
	ground.clear()
	grass.clear()
	walls.clear()
	_generate_floor()
	_generate_walls()
	_carve_doors()
	_generate_grass()
	_setup_spawn()


func _generate_floor() -> void:
	for x in room_width:
		for y in room_height:
			var alt := TilesetFactory.TILE_FLOOR_A
			if (x + y) % 5 == 0:
				alt = TilesetFactory.TILE_FLOOR_B
			set_cell(ground, Vector2i(x, y), alt)


func _generate_walls() -> void:
	for x in room_width:
		for y in room_height:
			var is_wall := x < wall_thickness or x >= room_width - wall_thickness \
				or y < wall_thickness or y >= room_height - wall_thickness
			if is_wall:
				set_cell(walls, Vector2i(x, y), wall_tile)


func _carve_doors() -> void:
	if not door_openings.is_empty():
		for opening in door_openings:
			RoomBaseCarve.carve_opening(self, opening)
		return
	# 默认：南入口 + 北出口（3 格宽）
	var center_x := room_width / 2
	for x in range(center_x - 1, center_x + 2):
		for y in range(wall_thickness):
			erase_cell(walls, Vector2i(x, y))
		for y in range(room_height - wall_thickness, room_height):
			erase_cell(walls, Vector2i(x, y))


func _generate_grass() -> void:
	var center := Vector2(room_width * 0.5, room_height * 0.5)
	for x in range(wall_thickness, room_width - wall_thickness):
		for y in range(wall_thickness, room_height - wall_thickness):
			var cell := Vector2i(x, y)
			if walls.get_cell_source_id(cell) != -1:
				continue
			var edge := mini(mini(x - wall_thickness, room_width - wall_thickness - 1 - x),
				mini(y - wall_thickness, room_height - wall_thickness - 1 - y))
			if edge >= grass_depth:
				continue
			if Vector2(x, y).distance_to(center) < center_clear_radius:
				continue
			var probability := grass_density * (1.0 - float(edge) / float(grass_depth))
			if rng.randf() > probability:
				continue
			set_cell(grass, cell, grass_tiles[rng.randi_range(0, grass_tiles.size() - 1)])


func _setup_spawn() -> void:
	if player_spawn == null:
		player_spawn = get_node_or_null("PlayerSpawn") as Marker2D
	if player_spawn:
		player_spawn.position = Vector2(room_width * WORLD_TILE * 0.5, room_height * WORLD_TILE * 0.5 + WORLD_TILE)


func _setup_light() -> void:
	var light := get_node_or_null("CenterLight") as PointLight2D
	if light == null:
		light = PointLight2D.new()
		light.name = "CenterLight"
		add_child(light)
	light.energy = light_energy
	light.texture_scale = light_scale
	light.position = Vector2(room_width * WORLD_TILE * 0.5, room_height * WORLD_TILE * 0.5)
