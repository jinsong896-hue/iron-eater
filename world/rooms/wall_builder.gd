class_name WallBuilder
extends RefCounted
## 墙壁生成器 —— HD-2D 重构版
## 根据数据生成 3D 墙壁（带碰撞）

const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.2
const CELL_SIZE := 1.0


## 生成墙壁到指定父节点
## 合并策略：所有墙段并成「1 个 MeshInstance3D + 1 个 StaticBody3D」。
## 每段墙原先是独立的 Node3D（MeshInstance3D + StaticBody3D + CollisionShape3D），
## 84 段即 84 个节点树；实测单次建房 45ms。位置/旋转直接烘焙进顶点，
## 碰撞体仍按段保留（StaticBody3D 下挂多个 CollisionShape3D），行为不变。
static func build(parent: Node3D, data) -> void:
	var walls: Array = data.get("walls", [])
	if walls.is_empty():
		walls = _boundary_walls(data)

	# 门格留洞：门与同格墙（含角落双面墙）互斥。
	# 房间模板的墙圈是连着门格的，门改为按拓扑重算后必须在这里放行，
	# 否则门会封在一段实心墙里。
	var door_cells := _door_cell_set(data)
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)

	# 收集通过校验的墙段
	var kept: Array = []
	for wall in walls:
		var wx := int(wall.get("x", 0))
		var wy := int(wall.get("y", 0))
		var wdir := str(wall.get("direction", ""))
		if door_cells.has("%d_%d_%s" % [wx, wy, wdir]):
			continue
		# 旧数据无 direction 时，按墙在房间的位置推断朝向
		if not wall.has("direction"):
			wall["direction"] = _infer_direction(wx, wy, w, h)
		kept.append(wall)

	if kept.is_empty():
		return

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "WallMesh"
	mesh_node.mesh = _build_merged_wall_mesh(kept)
	mesh_node.material_override = _wall_material()
	parent.add_child(mesh_node)

	var body := StaticBody3D.new()
	body.name = "WallCollision"
	parent.add_child(body)
	for wall in kept:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(CELL_SIZE, WALL_HEIGHT, WALL_THICKNESS)
		col.shape = shape
		col.position = _get_edge_position(
			int(wall.get("x", 0)), int(wall.get("y", 0)), str(wall.get("direction", "north"))
		)
		col.rotation = _get_edge_rotation(str(wall.get("direction", "north")))
		body.add_child(col)


## 兼容数据缺 walls 时的边界墙生成（返回数组，不再直接建节点）
static func _boundary_walls(data) -> Array:
	var w: int = data.get("width", 16)
	var h: int = data.get("height", 12)
	var out: Array = []
	for x in range(w):
		if not _has_door(data, "north"):
			out.append({"x": x, "y": 0, "direction": "north", "type": "normal_wall"})
		if not _has_door(data, "south"):
			out.append({"x": x, "y": h - 1, "direction": "south", "type": "normal_wall"})
	for y in range(h):
		if not _has_door(data, "west"):
			out.append({"x": 0, "y": y, "direction": "west", "type": "normal_wall"})
		if not _has_door(data, "east"):
			out.append({"x": w - 1, "y": y, "direction": "east", "type": "normal_wall"})
	return out


## 所有墙段合并为一个网格（位置与旋转烘焙进顶点）
static func _build_merged_wall_mesh(walls: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var hw := CELL_SIZE * 0.5
	var hh := WALL_HEIGHT * 0.5
	var ht := WALL_THICKNESS * 0.5

	# 轴对齐盒子的 8 个角（局部坐标，中心在原点）
	var corners := [
		Vector3(-hw, -hh, -ht), Vector3(hw, -hh, -ht), Vector3(hw, hh, -ht), Vector3(-hw, hh, -ht),
		Vector3(-hw, -hh, ht), Vector3(hw, -hh, ht), Vector3(hw, hh, ht), Vector3(-hw, hh, ht),
	]
	# 6 个面，每个面 4 个角索引 + 该面法线。
	# 绕序注意：**Godot 以顺时针为正面**（与右手叉积相反，已实证）。
	# 故每个面按「从外侧看顺时针」排列，法线仍按几何外法线给出。
	# 若写成逆时针，面朝外的一侧会变成背面：墙顶面朝下 → 侧面看到内壁 → 全黑。
	var faces := [
		[0, 1, 2, 3, Vector3(0, 0, -1)],   # -Z
		[4, 7, 6, 5, Vector3(0, 0, 1)],    # +Z
		[3, 2, 6, 7, Vector3(0, 1, 0)],    # +Y（顶面：从上方看顺时针）
		[0, 4, 5, 1, Vector3(0, -1, 0)],   # -Y
		[0, 3, 7, 4, Vector3(-1, 0, 0)],   # -X
		[1, 5, 6, 2, Vector3(1, 0, 0)],    # +X
	]

	for wall in walls:
		var pos := _get_edge_position(
			int(wall.get("x", 0)), int(wall.get("y", 0)), str(wall.get("direction", "north"))
		)
		var dir := str(wall.get("direction", "north"))
		# 东西向墙需要绕 Y 轴转 90°。**不能用「交换 x/z 分量」实现**——
		# 那是镜像变换（行列式 -1），会翻转手性，导致绕序与法线矛盾、法线朝内。
		# 正确的 Y 轴旋转 90°：(x,y,z) → (z, y, -x)，行列式 +1。
		var rotate := dir == "east" or dir == "west"

		for face in faces:
			var n: Vector3 = face[4]
			var base := verts.size()
			for k in 4:
				var local: Vector3 = corners[face[k]]
				if rotate:
					local = Vector3(local.z, local.y, -local.x)
				verts.push_back(pos + local)
				var nn := Vector3(n.z, n.y, -n.x) if rotate else n
				normals.push_back(nn)
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
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 墙材质（缓存复用）
static var _wall_mat: StandardMaterial3D = null

static func _wall_material() -> StandardMaterial3D:
	if _wall_mat == null:
		_wall_mat = StandardMaterial3D.new()
		_wall_mat.albedo_color = Color(0.3, 0.3, 0.35)
		_wall_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return _wall_mat


## 门所占的「格+方向」集合（运行时防线，与 GameRoot._apply_topology_doors 同口径）
## 只按方向精确匹配：门替换的是同名方位的墙段，角落格的反向墙要保留
static func _door_cell_set(data) -> Dictionary:
	var set := {}
	for d in data.get("doors", []):
		var dx := int(d.get("x", -1))
		var dy := int(d.get("y", -1))
		if dx < 0 or dy < 0:
			continue
		set["%d_%d_%s" % [dx, dy, str(d.get("direction", ""))]] = true
	return set


static func _has_door(data, direction: String) -> bool:
	var doors: Array = data.get("doors", [])
	for d in doors:
		if d.get("direction", "") == direction:
			return true
	return false


## 获取墙壁在格子边缘的位置
static func _get_edge_position(x: int, y: int, direction: String) -> Vector3:
	var p := RoomBuilder.grid_to_world(x, y, WALL_HEIGHT / 2.0)
	match direction:
		"north":
			p.z -= CELL_SIZE * 0.5
		"south":
			p.z += CELL_SIZE * 0.5
		"west":
			p.x -= CELL_SIZE * 0.5
		"east":
			p.x += CELL_SIZE * 0.5
	return p


## 获取墙壁旋转角度
static func _get_edge_rotation(direction: String) -> Vector3:
	match direction:
		"east", "west":
			return Vector3(0.0, deg_to_rad(90.0), 0.0)
	return Vector3.ZERO


## 旧数据无 direction 时，根据墙的位置推断朝向
## 房间边界墙：y=0→north，y=max→south，x=0→west，x=max→east；内部墙默认 north
static func _infer_direction(x: int, y: int, w: int, h: int) -> String:
	if y == 0:
		return "north"
	if y == h - 1:
		return "south"
	if x == 0:
		return "west"
	if x == w - 1:
		return "east"
	return "north"