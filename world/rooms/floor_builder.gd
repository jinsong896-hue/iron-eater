class_name FloorBuilder
extends RefCounted
## 地板生成器 —— HD-2D 重构版
##
## 实现方式：把所有地板格合并成「每种材质一个 MeshInstance3D」。
##
## 为什么这么做：原实现是每格 instantiate 一个 floor_tile.tscn 场景
## （280 格 → 280 个节点、280 次材质赋值），实测单次建房地板耗时 201ms，
## 是切房卡顿的压倒性瓶颈（墙 45ms，其余环节均 <1ms）。
## 地板是无碰撞的纯视觉方块，完全不需要按格拆节点：合并后
## 单材质房间从 280 个节点降到 1 个，相邻格之间的三角带连成整片地板，
## 视觉一致、重建接近瞬时。
##
## 按材质分组而非全部合并：这样地板材质的扩展（石/木/草/冰/熔岩）
## 与「每格独立材质」在视觉上完全等价，不会引入回归。

const FLOOR_TILE_PATH := "res://scenes/world/floor_tile.tscn"

const CELL_SIZE := 1.0
## 地板平面所在高度（原先每块 PlaneMesh 位于格子中心 y=0）
const FLOOR_Y := 0.0

# 地板类型到材质的映射
static var _material_cache := {}


## 生成地板到指定父节点
static func build(parent: Node3D, data) -> void:
	var tiles: Array = data.get("floor", [])
	if tiles.is_empty():
		tiles = _default_tiles(data)
	if tiles.is_empty():
		return

	# 按材质分组：{type: [Vector2i, ...]}
	var groups := {}
	for tile in tiles:
		var t := str(tile.get("type", "stone"))
		if not groups.has(t):
			groups[t] = []
		groups[t].append(Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0))))

	for tile_type in groups:
		_build_merged_mesh(parent, tile_type, groups[tile_type])


## 自动铺满默认地板（数据无 floor 时）
static func _default_tiles(data) -> Array:
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	var out: Array = []
	for y in range(h):
		for x in range(w):
			out.append({"x": x, "y": y, "type": "stone"})
	return out


## 把一组同材质地板格合并为一个 MeshInstance3D
## 直接用 ArrayMesh 的 surface 数组（比 SurfaceTool 逐顶点调用快得多）
static func _build_merged_mesh(parent: Node3D, tile_type: String, cells: Array) -> void:
	if cells.is_empty():
		return

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := CELL_SIZE * 0.5

	for cell in cells:
		var cx := float(cell.x) * CELL_SIZE
		var cz := float(cell.y) * CELL_SIZE
		var x0 := cx - half
		var x1 := cx + half
		var z0 := cz - half
		var z1 := cz + half
		# 四个角，法线朝上；逆时针（俯视）保证正面朝上
		var base := verts.size()
		verts.push_back(Vector3(x0, FLOOR_Y, z0))
		verts.push_back(Vector3(x0, FLOOR_Y, z1))
		verts.push_back(Vector3(x1, FLOOR_Y, z1))
		verts.push_back(Vector3(x1, FLOOR_Y, z0))
		for _i in 4:
			normals.push_back(Vector3.UP)
		uvs.push_back(Vector2(0, 0))
		uvs.push_back(Vector2(0, 1))
		uvs.push_back(Vector2(1, 1))
		uvs.push_back(Vector2(1, 0))
		indices.push_back(base + 0)
		indices.push_back(base + 1)
		indices.push_back(base + 2)
		indices.push_back(base + 0)
		indices.push_back(base + 2)
		indices.push_back(base + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var node := MeshInstance3D.new()
	node.name = "Floor_%s" % tile_type
	node.mesh = mesh
	node.material_override = _get_material_for_type(tile_type)
	# 地板不投射阴影：它是场景最底层平面，投射只会自己遮自己。
	# （合并成单网格后，整片地板同时作为投影面与接收面，
	#   开着投影会让每个格子向邻居投影 → 地面全黑。）
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


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
