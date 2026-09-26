class_name DecorationBuilder
extends RefCounted
## 装饰生成器 —— HD-2D 重构版
## 根据 RoomData 的装饰数据生成装饰物（火把、箱子、柱子等）
##
## ## 三级资源查找（2026-09-26 起）
##
## 每个装饰物的资源按以下顺序解析，**先命中先用**：
##
##   1. `ArtRegistry.prop_model(type)` —— 美术配置表里的模型（`.glb`）
##   2. `PROP_PATHS[type]`             —— 硬编码的场景路径（`.tscn`）
##   3. `_create_placeholder(type)`    —— 程序化占位体（圆柱/方块）
##
## 第 1 级是新增的：让美术能在可视化界面里换模型，不改代码。
## 未配置时**自动退回第 2 级**，所以空配置的行为与接入前完全一致。
##
## ## 为什么 `PROP_PATHS` 只剩 `chest`
##
## 原来 4 条里有 3 条（`torch`/`barrel`/`pillar`）指向**不存在的 .tscn**，
## 每次加载失败后静默回退到占位体——实测确认。
## 这 3 个用途现已配到 castle-kit 的真模型（见 `default_profile.tres`），
## 故删掉悬空项，让「没配」这件事**明确可见**而不是每次白跑一次加载。

const PROP_PATHS := {
	"chest": "res://scenes/props/chest.tscn",
}

const CELL_SIZE := 1.0


## 生成装饰到指定父节点
static func build(parent: Node3D, data) -> void:
	# 实体数据中包含装饰类型
	var entities: Array = data.get("entities", [])
	for entity in entities:
		var type := str(entity.get("type", ""))
		if _is_prop_type(type):
			_create_prop(parent, entity, type)


## 该类型是否是装饰物（美术配置表或硬编码表里有）
##
## 两个来源都要认：`ArtRegistry` 里新配的用途也算——
## 否则美术在界面上加一个新装饰类型、房间 JSON 里写了，
## 却因为不在 `PROP_PATHS` 里而被静默跳过。
static func _is_prop_type(type: String) -> bool:
	if type.is_empty():
		return false
	if PROP_PATHS.has(type):
		return true
	return not ArtRegistry.prop_model(type).is_empty()


## 创建单个装饰物
static func _create_prop(parent: Node3D, data: Dictionary, prop_type: String) -> void:
	var prop := _resolve_prop(prop_type)
	if prop == null:
		return

	var x := int(data.get("x", 0))
	var y := int(data.get("y", 0))

	# 变换在 add_child 之前设好。`grid_to_world` 给的是房间局部坐标，
	# 父节点未做变换，故 position 可直接用。
	# `ArtRegistry` 的 `y_offset` 是**相对地面的抬升**，叠加在网格坐标上。
	var xform := ArtRegistry.prop_transform(prop_type)
	prop.position = RoomBuilder.grid_to_world(x, y, 0.0) \
		+ Vector3(0.0, float(xform["y_offset"]), 0.0)
	var s := float(xform["scale"])
	if not is_equal_approx(s, 1.0):
		prop.scale = Vector3(s, s, s)
	var rot := float(xform["y_rotation_deg"])
	if not is_zero_approx(rot):
		prop.rotation.y = deg_to_rad(rot)

	prop.name = "%s_%d_%d" % [prop_type, x, y]
	parent.add_child(prop)


## 按三级顺序解析装饰物资源，全部失败返回 null
static func _resolve_prop(prop_type: String) -> Node3D:
	# 1. 美术配置表（.glb 或任意 PackedScene）
	var model_path := ArtRegistry.prop_model(prop_type)
	if not model_path.is_empty():
		var inst := _instantiate_scene(model_path)
		if inst != null:
			return inst

	# 2. 硬编码场景路径
	var scene_path: String = PROP_PATHS.get(prop_type, "")
	if not scene_path.is_empty():
		var inst2 := _instantiate_scene(scene_path)
		if inst2 != null:
			return inst2

	# 3. 程序化占位体
	return _create_placeholder(prop_type)


## 加载并实例化一个 PackedScene 路径（失败返回 null）
##
## **用 `load()` 的结果判成败，不用 `ResourceLoader.exists()`**——
## 项目已知陷阱：`.import` 里 `valid=false` 的资源 `exists()` 仍返回 true
## 但 `load()` 返回 null（实测 castle-kit 76 个模型里 30 个如此）。
## 用 `exists()` 会走进「以为有资源、实际拿到 null」的分支。
##
## `.glb` 与 `.tscn` 在这里**同一条路径**：两者导入后都是 `PackedScene`，
## 实测确认，无需分支。
static func _instantiate_scene(path: String) -> Node3D:
	var ps = load(path)
	if ps is PackedScene:
		var node = (ps as PackedScene).instantiate()
		if node is Node3D:
			return node as Node3D
		# 不是 Node3D（理论上不该发生）——释放掉避免泄漏
		if node != null:
			node.free()
	return null


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

	var color := Color(0.5, 0.5, 0.5)
	match prop_type:
		"torch":
			color = Color(0.6, 0.4, 0.2)
		"barrel":
			color = Color(0.5, 0.3, 0.15)
		"pillar":
			color = Color(0.5, 0.5, 0.55)

	mesh.material_override = ToonMaterial.create(color)
	root.add_child(mesh)
	return root