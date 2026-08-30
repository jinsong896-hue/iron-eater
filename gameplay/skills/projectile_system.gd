class_name ProjectileSystem
extends RefCounted
## 投射物系统 —— HD-2D 重构版
## 统一管理所有投射物的飞行、碰撞、生命周期

## 创建投射物
static func spawn(projectile_data: Dictionary, parent: Node3D) -> Node3D:
	var projectile := _create_projectile_node(projectile_data)
	parent.add_child(projectile)
	return projectile


## 创建投射物节点
static func _create_projectile_node(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Projectile_%s" % data.get("skill_id", "unknown")

	# 视觉
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _element_color(data.get("element", "physical"))
	mat.emission_enabled = true
	mat.emission = _element_color(data.get("element", "physical"))
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat

	# 碰撞检测区域
	var area := Area3D.new()
	area.name = "HitArea"
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	area.add_child(collision)

	# 投射物脚本
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var direction := Vector3.FORWARD
var speed := 10.0
var damage := 0.0
var lifetime := 2.0
var element := "physical"
var pierce_count := 0
var _elapsed := 0.0
var _hit_count := 0

func _ready() -> void:
	var area := get_node("HitArea") as Area3D
	if area:
		area.body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > lifetime:
		queue_free()
		return
	position += direction * speed * delta

func _on_hit(body: Node3D) -> void:
	if _hit_count > pierce_count:
		queue_free()
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.call("take_damage", damage, false)
		EventBus.damage_popup.emit(body.global_position, damage, "normal")
		_hit_count += 1
		if _hit_count > pierce_count:
			queue_free()
"""
	script.reload()
	root.set_script(script)

	# 设置参数
	root.set("direction", data.get("direction", Vector3.FORWARD))
	root.set("speed", data.get("speed", 10.0))
	root.set("damage", data.get("damage", 10.0))
	root.set("lifetime", data.get("lifetime", 2.0))
	root.set("element", data.get("element", "physical"))
	root.set("pierce_count", data.get("pierce_count", 0))

	root.add_child(mesh)
	root.add_child(area)
	return root


static func _element_color(element: String) -> Color:
	match element:
		"fire":
			return Color(1.0, 0.3, 0.1)
		"ice":
			return Color(0.3, 0.7, 1.0)
		"lightning":
			return Color(1.0, 0.9, 0.2)
		"poison":
			return Color(0.2, 0.8, 0.2)
		_:
			return Color(0.8, 0.8, 0.8)