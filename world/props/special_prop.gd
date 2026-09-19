extends Node3D
## 特殊房交互物实体 —— 商店 NPC / 治疗泉水 / 事件祭坛
## 脚本构建占位视觉（按类型着色 + 微光提示可交互），玩家按 E 交互
## 实际结算由 RoomController.interact_special() 完成，本实体只负责表现

## 特殊房类型："shop" | "heal" | "event"
var prop_kind := ""


func _ready() -> void:
	_build_visual()


## 按类型构建占位视觉
func _build_visual() -> void:
	match prop_kind:
		"shop":
			_build_shop_npc()
		"heal":
			_build_heal_shrine()
		"event":
			_build_event_shrine()
		_:
			_build_generic()


## 商店 NPC：方柱躯干 + 头部，暖黄配色（商人感）
func _build_shop_npc() -> void:
	_add_box(Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.5), Color(0.72, 0.55, 0.2), 0.18)
	_add_box(Vector3(0, 1.3, 0), Vector3(0.45, 0.45, 0.45), Color(0.85, 0.7, 0.35), 0.3)
	# 柜台
	_add_box(Vector3(0, 0.2, 0.7), Vector3(1.4, 0.4, 0.5), Color(0.4, 0.28, 0.15), 0.05)
	_add_light(Color(1.0, 0.85, 0.4), 1.2)


## 治疗泉水：矮圆柱基座 + 上方悬浮水球，青蓝配色
func _build_heal_shrine() -> void:
	_add_cylinder(Vector3(0, 0.2, 0), 0.9, 0.4, Color(0.35, 0.45, 0.5), 0.05)
	_add_sphere(Vector3(0, 0.85, 0), 0.32, Color(0.35, 0.85, 0.9), 0.7)
	_add_light(Color(0.4, 0.9, 1.0), 1.4)


## 事件祭坛：四面金字塔尖碑 + 悬浮核心，紫红配色
func _build_event_shrine() -> void:
	_add_box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color(0.4, 0.28, 0.45), 0.08)
	var tip := MeshInstance3D.new()
	tip.name = "Tip"
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.55, 0.6, 0.55)
	tip.mesh = mesh
	tip.position = Vector3(0, 1.3, 0)
	var mat := ToonMaterial.create(Color(0.6, 0.35, 0.7), null, Color.WHITE,
		Color(0.85, 0.45, 1.0), 0.35)
	tip.material_override = mat
	add_child(tip)
	_add_sphere(Vector3(0, 1.75, 0), 0.18, Color(0.9, 0.5, 1.0), 0.9)
	_add_light(Color(0.85, 0.45, 1.0), 1.4)


## 未指定类型的兜底视觉
func _build_generic() -> void:
	_add_box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color(0.6, 0.6, 0.6), 0.1)


## 添加方盒网格
func _add_box(pos: Vector3, size: Vector3, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


## 添加圆柱网格
func _add_cylinder(pos: Vector3, radius: float, height: float, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


## 添加球体网格
func _add_sphere(pos: Vector3, radius: float, color: Color, emission: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.position = pos
	node.material_override = _make_material(color, emission)
	add_child(node)
	return node


## 添加点光源（强化可交互提示）
func _add_light(color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 5.0
	light.position = Vector3(0, 1.2, 0)
	add_child(light)
	return light


## 构建带微光的卡通材质
func _make_material(color: Color, emission: float) -> ShaderMaterial:
	return ToonMaterial.create(color, null, Color.WHITE, color, emission)
