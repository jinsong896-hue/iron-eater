class_name DecorationBuilder
extends RefCounted
## 装饰生成器 —— HD-2D 重构版
## 根据 RoomData 的装饰数据生成装饰物（火把、箱子、柱子等）

const PROP_PATHS := {
	"torch": "res://scenes/props/torch.tscn",
	"chest": "res://scenes/props/chest.tscn",
	"barrel": "res://scenes/props/barrel.tscn",
	"pillar": "res://scenes/props/pillar.tscn",
}

const CELL_SIZE := 1.0


## 生成装饰到指定父节点
static func build(parent: Node3D, data) -> void:
	# 实体数据中包含装饰类型
	var entities: Array = data.get("entities", [])
	for entity in entities:
		var type := str(entity.get("type", ""))
		if type in PROP_PATHS:
			_create_prop(parent, entity, type)


## 创建单个装饰物
static func _create_prop(parent: Node3D, data: Dictionary, prop_type: String) -> void:
	var path: String = PROP_PATHS.get(prop_type, "")
	if path.is_empty():
		return

	var x := int(data.get("x", 0))
	var y := int(data.get("y", 0))

	var prop: Node3D
	if ResourceLoader.exists(path):
		var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
		if scene:
			prop = scene.instantiate()
		else:
			prop = _create_placeholder(prop_type)
	else:
		prop = _create_placeholder(prop_type)

	prop.position = RoomBuilder.grid_to_world(x, y, 0.0)
	prop.name = "%s_%d_%d" % [prop_type, x, y]
	parent.add_child(prop)


## 创建占位装饰物
static func _create_placeholder(prop_type: String) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"

	match prop_type:
		"torch":
			var cylinder := CylinderMesh.new()
			cylinder.height = 1.0
			cylinder.top_radius = 0.05
			cylinder.bottom_radius = 0.1
			mesh.mesh = cylinder
			mesh.position.y = 0.5
		"barrel":
			var cylinder := CylinderMesh.new()
			cylinder.height = 1.0
			cylinder.top_radius = 0.3
			cylinder.bottom_radius = 0.3
			mesh.mesh = cylinder
			mesh.position.y = 0.5
		"pillar":
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 4.0, 0.5)
			mesh.mesh = box
			mesh.position.y = 2.0
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.5, 0.5, 0.5)
			mesh.mesh = box
			mesh.position.y = 0.25

	var mat := StandardMaterial3D.new()
	match prop_type:
		"torch":
			mat.albedo_color = Color(0.6, 0.4, 0.2)
		"barrel":
			mat.albedo_color = Color(0.5, 0.3, 0.15)
		"pillar":
			mat.albedo_color = Color(0.5, 0.5, 0.55)
		_:
			mat.albedo_color = Color(0.5, 0.5, 0.5)

	mesh.material_override = mat
	root.add_child(mesh)
	return root