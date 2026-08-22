class_name TilesetFactory
extends RefCounted
## 瓦片集工厂：《房间生成.md》方案 —— 从 Kenney roguelike 精灵表构建 64×64 瓦片集
## 精灵表本身是 16×16（带 1px 边距），这里先剥离边距、再最近邻放大到 64×64，
## 使 TileSet 的世界瓦片原生为 64×64，TileMapLayer 无需再 scale（scale=1）。

const SHEET_PATH := "res://assets/roguelike-rpg-pack/Spritesheet/roguelikeSheet_transparent.png"
const SOURCE_TILE := 16
const SOURCE_STEP := 17
const TILE_SIZE := 64

# 瓦片坐标（精灵表内的 16×16 格坐标，放大后即 64×64 世界瓦片）
const TILE_FLOOR_A := Vector2i(33, 4)
const TILE_FLOOR_B := Vector2i(12, 0)
const TILE_WALL := Vector2i(36, 1)
const TILE_BAR := Vector2i(51, 16)
const TILE_GRASS := [Vector2i(0, 16), Vector2i(3, 16), Vector2i(10, 26), Vector2i(11, 27)]

static var _tileset: TileSet


static func get_tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	_tileset = _build()
	return _tileset


static func _build() -> TileSet:
	var sheet := load(SHEET_PATH) as Texture2D
	var sheet_image := sheet.get_image()
	# 精灵表每瓦片 16px、瓦片间 1px 间隙、四周无外边框（968=57×16+56×1）。
	# 瓦片数 N 满足 N×17−1=W，即 N=(W+1)/17；直接 W/17 会丢掉最右一列/最下一行。
	var cols := (sheet_image.get_width() + 1) / SOURCE_STEP
	var rows := (sheet_image.get_height() + 1) / SOURCE_STEP
	# 剥离 1px 间隙
	var stripped := Image.create(cols * SOURCE_TILE, rows * SOURCE_TILE, false, Image.FORMAT_RGBA8)
	for cy in rows:
		for cx in cols:
			var src_rect := Rect2i(cx * SOURCE_STEP, cy * SOURCE_STEP, SOURCE_TILE, SOURCE_TILE)
			stripped.blit_rect(sheet_image, src_rect, Vector2i(cx * SOURCE_TILE, cy * SOURCE_TILE))
	# 最近邻放大到 64×64（保持像素风锐利），使 atlas 瓦片与世界瓦片同为 64×64
	stripped.resize(cols * TILE_SIZE, rows * TILE_SIZE, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(stripped)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer()
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(atlas, 0)

	_create_tile(atlas, TILE_FLOOR_A, false)
	_create_tile(atlas, TILE_FLOOR_B, false)
	_create_tile(atlas, TILE_WALL, true)
	_create_tile(atlas, TILE_BAR, true)
	for g in TILE_GRASS:
		_create_tile(atlas, g, false)
	return ts


static func _create_tile(atlas: TileSetAtlasSource, coord: Vector2i, has_collision: bool) -> void:
	var tex_size := atlas.texture.get_size()
	if (coord.x + 1) * TILE_SIZE > tex_size.x or (coord.y + 1) * TILE_SIZE > tex_size.y:
		return
	if not atlas.has_tile(coord):
		atlas.create_tile(coord)
	if has_collision:
		var td := atlas.get_tile_data(coord, 0)
		td.set_collision_polygons_count(0, 1)
		td.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2.ZERO, Vector2(TILE_SIZE, 0),
			Vector2(TILE_SIZE, TILE_SIZE), Vector2(0, TILE_SIZE),
		]))
