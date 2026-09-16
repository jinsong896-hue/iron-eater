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

# 地板类型到材质的映射。键 = "主题色值|tile_type"——
# 同一 tile_type 在不同层主题下的配色不同（第 1 层灰石 vs 第 5 层熔岩色），
# 只按 type 缓存会让先构建的房间把配色钉死给后面所有层。
static var _material_cache := {}


## 生成地板到指定父节点。
## theme_color 为本层主题的地板底色（来自 FloorDefs.color_of(floor, "floor")），
## 传 Color.TRANSPARENT（默认）时回退到旧的无主题配色，兼容既有调用与测试。
## theme_id（如 "prison"）决定用图集里的哪一块地砖；空字符串则退回纯色无贴图。
static func build(parent: Node3D, data, theme_color: Color = Color.TRANSPARENT,
		theme_alt: Color = Color.TRANSPARENT, theme_id: String = "") -> void:
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
		_build_merged_mesh(parent, tile_type, groups[tile_type], theme_color, theme_alt, theme_id)


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
static func _build_merged_mesh(parent: Node3D, tile_type: String, cells: Array,
		theme_color: Color = Color.TRANSPARENT, theme_alt: Color = Color.TRANSPARENT,
		theme_id: String = "") -> void:
	if cells.is_empty():
		return

	# 本主题的地砖在图集里的 UV 范围（空 theme_id = 不贴图，退回纯色）
	var uv_rect := Vector4(0.0, 0.0, 1.0, 1.0)
	if not theme_id.is_empty():
		uv_rect = AtlasDefs.tile_uv_rect(AtlasDefs.floor_tile(theme_id))

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
		# 四个角（俯视，法线朝上）
		# 绕序注意：**Godot 以顺时针为正面**（与右手叉积相反，已实证：
		# 用 SurfaceTool.generate_normals 测定，逆时针绕序会得到朝下的法线）。
		# 故这里必须按顺时针发射，否则从上方看地板是背面、会被整体剔除（地板消失）。
		var base := verts.size()
		verts.push_back(Vector3(x0, FLOOR_Y, z0))
		verts.push_back(Vector3(x0, FLOOR_Y, z1))
		verts.push_back(Vector3(x1, FLOOR_Y, z1))
		verts.push_back(Vector3(x1, FLOOR_Y, z0))
		for _i in 4:
			normals.push_back(Vector3.UP)
		# UV 从「每格 0→1」改为「映射到图集里本主题那一格」。
		# 贴图有 1px 间隔，AtlasDefs.tile_uv_rect 已做半像素内缩防渗色。
		# 顺序对应上面四个顶点（z0,z1 是 v 轴，x0,x1 是 u 轴）。
		uvs.push_back(Vector2(uv_rect.x, uv_rect.y))
		uvs.push_back(Vector2(uv_rect.x, uv_rect.w))
		uvs.push_back(Vector2(uv_rect.z, uv_rect.w))
		uvs.push_back(Vector2(uv_rect.z, uv_rect.y))
		indices.push_back(base + 0)
		indices.push_back(base + 2)
		indices.push_back(base + 1)
		indices.push_back(base + 0)
		indices.push_back(base + 3)
		indices.push_back(base + 2)

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
	node.material_override = _get_material_for_type(tile_type, theme_color, theme_id)
	# 地板不投射阴影：它是场景最底层平面，投射只会自己遮自己。
	# （合并成单网格后，整片地板同时作为投影面与接收面，
	#   开着投影会让每个格子向邻居投影 → 地面全黑。）
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## 取地板材质。
## **缓存键必须含主题色**：同一 tile_type 在不同层的底色不同，
## 只按 type 缓存会让第 1 层构建的材质泄漏给第 5 层（全层同色）。
##
## 贴图与配色**并存**：贴图提供纹理（砖缝/斑点），albedo_color 提供该层的色调。
## 这样 Kenney 图集只有明亮自然色的限制不成问题——暗色层靠染色压暗。
static func _get_material_for_type(type: String, theme_color: Color = Color.TRANSPARENT,
		theme_id: String = "") -> Material:
	var key := "%s|%.3f_%.3f_%.3f|%s" % [
		type, theme_color.r, theme_color.g, theme_color.b, theme_id]
	if _material_cache.has(key):
		return _material_cache[key]

	var mat := StandardMaterial3D.new()
	var has_texture := false
	# 图集贴图（有 theme_id 且文件存在时）
	if not theme_id.is_empty() and ResourceLoader.exists(AtlasDefs.SHEET_PATH):
		var tex := ResourceLoader.load(AtlasDefs.SHEET_PATH, "Texture2D",
			ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex != null:
			mat.albedo_texture = tex
			has_texture = true
			# 像素风：最近邻采样，避免放大后糊成一团
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if has_texture:
		# **贴图在场时不能直接乘主题色**：最终色 = albedo_color × texture，
		# 贴图格自身有亮度（灰砖 0.8 / 暗木 0.48…），直接乘会让亮度失控
		# （实测第 1 层从 0.30 涨到 0.95，画面洗白）。
		# AtlasDefs.tint_for 先量出该格平均亮度，再反解出让结果回到主题色
		# 亮度的那一个系数——纹理保留，明暗归位。
		mat.albedo_color = AtlasDefs.tint_for(theme_color,
			AtlasDefs.floor_tile(theme_id))
	elif theme_color.a > 0.0:
		# 无贴图 + 有主题色：退回纯色配色（保持既有行为）
		match type:
			"stone":
				mat.albedo_color = theme_color
			"wood":
				mat.albedo_color = theme_color.lightened(0.12)
			"grass":
				mat.albedo_color = theme_color.lightened(0.20)
			"ice":
				mat.albedo_color = theme_color.lightened(0.35)
			"lava":
				mat.albedo_color = theme_color.darkened(0.15)
			_:
				mat.albedo_color = theme_color.darkened(0.08)
	else:
		# 无主题（默认）：保持旧配色，兼容未接层主题的调用方
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
	_material_cache[key] = mat
	return mat
