@tool
extends Node3D
## 房间编辑专用场景根脚本
## 提供 Floor/Walls/Doors/Spawns 容器节点，由 room_editor_core.gd 操作内容
## GridLines 子节点用 ImmediateMesh 画格子辅助线（按房间尺寸刷新）

const CELL_SIZE := 1.0

## 当前编辑房间的尺寸（由 dock 加载房间时设置）
@export var room_width := 20
@export var room_height := 15


func _ready() -> void:
	_refresh_grid_lines()


## 按房间尺寸刷新格子辅助线 + 定位相机
func refresh_grid(w: int, h: int) -> void:
	room_width = w
	room_height = h
	_refresh_grid_lines()
	_frame_camera(w, h)


## 按房间尺寸把相机移到俯瞰全房间的位置
func _frame_camera(w: int, h: int) -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	var max_dim := float(maxi(w, h))
	var pos := Vector3(float(w) / 2.0, max_dim * 0.9, float(h) / 2.0 + max_dim * 0.6)
	var target := Vector3(float(w) / 2.0, 0.0, float(h) / 2.0)
	var t := Transform3D()
	t.origin = pos
	cam.transform = t.looking_at(target, Vector3.UP)


## 用 ImmediateMesh 画格子线
func _refresh_grid_lines() -> void:
	var grid := get_node_or_null("GridLines")
	if grid == null:
		grid = MeshInstance3D.new()
		grid.name = "GridLines"
		add_child(grid)
		grid.owner = get_tree().get_edited_scene_root() if Engine.is_editor_hint() else owner

	var im := ImmediateMesh.new()
	grid.mesh = im
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var line_color := Color(0.3, 0.3, 0.35, 0.5)
	im.surface_set_color(line_color)

	# 画 X 方向线（沿 Z 轴）
	for x in range(room_width + 1):
		var fx := float(x) * CELL_SIZE
		im.surface_add_vertex(Vector3(fx, 0.01, 0))
		im.surface_add_vertex(Vector3(fx, 0.01, float(room_height) * CELL_SIZE))

	# 画 Z 方向线（沿 X 轴）
	for y in range(room_height + 1):
		var fy := float(y) * CELL_SIZE
		im.surface_add_vertex(Vector3(0, 0.01, fy))
		im.surface_add_vertex(Vector3(float(room_width) * CELL_SIZE, 0.01, fy))

	im.surface_end()

	# 半透明材质
	var mat := StandardMaterial3D.new()
	mat.albedo_color = line_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid.material_override = mat
