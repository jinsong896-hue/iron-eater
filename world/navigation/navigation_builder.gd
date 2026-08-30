class_name NavigationBuilder
extends RefCounted
## 导航网格生成器 —— HD-2D 重构版
## 根据房间的地板数据自动生成 NavigationMesh

## 为房间生成导航网格
static func build(parent: Node3D, data: RoomData) -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.3
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 45.0

	# 设置导航区域边界
	var bounds := AABB(
		Vector3.ZERO,
		Vector3(float(data.width) * RoomBuilder.CELL_SIZE, 0.1, float(data.height) * RoomBuilder.CELL_SIZE)
	)
	nav_mesh.filter_baking_aabb = bounds

	region.navigation_mesh = nav_mesh
	parent.add_child(region)

	# 烘焙导航网格
	region.bake_navigation_mesh()


## 为整个地下城生成导航
static func build_for_dungeon(parent: Node3D, rooms: Array[Dictionary], room_size: float) -> void:
	for room_data in rooms:
		var region := NavigationRegion3D.new()
		var nav_mesh := NavigationMesh.new()
		nav_mesh.agent_radius = 0.3
		nav_mesh.agent_height = 2.0

		var pos: Vector2i = room_data.get("position", Vector2i.ZERO)
		var world_pos := Vector3(float(pos.x) * room_size, 0.0, float(pos.y) * room_size)

		region.position = world_pos
		region.navigation_mesh = nav_mesh
		parent.add_child(region)
		region.bake_navigation_mesh()