class_name FloorBuilder
extends RefCounted
## 地板生成器 —— HD-2D 重构版
## 根据数据生成 3D 地板 Mesh

const FLOOR_TILE_PATH := "res://scenes/world/floor_tile.tscn"

# 地板类型到材质的映射
static var _material_cache := {}


## 生成地板到指定父节点
static func build(parent: Node3D, data) -> void:
	var tiles: Array = data.get("floor", [])
	if tiles.is_empty():
		_generate_default_floor(parent, data)
		return

	for tile in tiles:
		_create_floor_tile(parent, tile)


## 自动铺满默认地板
static func _generate_default_floor(parent: Node3D, data) -> void:
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	for x in range(w):
		for y in range(h):
			_create_floor_tile(parent, {"x": x, "y": y, "type": "stone"})


## 创建单块地板
static func _create_floor_tile(parent: Node3D, tile: Dictionary) -> void:
	var tile_type := str(tile.get("type", "stone"))
	var x := int(tile.get("x", 0))
	var y := int(tile.get("y", 0))

	var scene: PackedScene
	if ResourceLoader.exists(FLOOR_TILE_PATH):
		scene = ResourceLoader.load(FLOOR_TILE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	else:
		scene = _create_floor_scene()

	if scene == null:
		return

	var instance := scene.instantiate()
	instance.position = RoomBuilder.grid_to_world(x, y, 0.0)
	instance.name = "FloorTile_%d_%d" % [x, y]

	_apply_material(instance, tile_type)
	parent.add_child(instance)


## 创建基础地板场景
static func _create_floor_scene() -> PackedScene:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = PlaneMesh.new()
	root.add_child(mesh)

	var scene := PackedScene.new()
	scene.pack(root)
	return scene


## 应用材质
static func _apply_material(node: Node3D, tile_type: String) -> void:
	var mesh_inst := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = node as MeshInstance3D
	if mesh_inst == null:
		return

	var material := _get_material_for_type(tile_type)
	if material:
		mesh_inst.material_override = material


static func _get_material_for_type(type: String) -> Material:
	if _material_cache.has(type):
		return _material_cache[type]

	var mat := StandardMaterial3D.new()
	match type:
		"stone":
			mat.albedo_color = Color(0.35, 0.35, 0.4)
		"wood":
			mat.albedo_color = Color(0.45, 0.3, 0.2)
		"grass":
			mat.albedo_color = Color(0.2, 0.5, 0.2)
		"ice":
			mat.albedo_color = Color(0.7, 0.8, 1.0)
		"lava":
			mat.albedo_color = Color(0.8, 0.2, 0.1)
		_:
			mat.albedo_color = Color(0.4, 0.4, 0.4)

	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material_cache[type] = mat
	return mat