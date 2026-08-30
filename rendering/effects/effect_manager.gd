class_name EffectManager
extends RefCounted
## 特效管理器 —— HD-2D 重构版
## 统一管理视觉特效的创建和回收

# 特效缓存池
static var _effect_pools := {}


## 创建伤害飘字（优先用 MassiveText 渲染器，降级到 DamagePopup）
static func spawn_damage_number(
	parent: Node3D, position: Vector3, amount: float, kind: String
) -> void:
	# 优先找场景里的 DamageTextRenderer
	var tree := parent.get_tree()
	if tree:
		var renderers := tree.get_nodes_in_group("damage_renderer")
		if renderers.size() > 0:
			var r := renderers[0] as Node
			if r and r.has_method("spawn"):
				r.spawn(position, amount, kind)
				return
	# 降级：旧的 Label3D 实现
	var popup_script = load("res://rendering/effects/damage_popup.gd")
	popup_script.create(parent, position, amount, kind)


## 创建命中特效
static func spawn_hit_effect(parent: Node3D, position: Vector3, element: String) -> void:
	var effect := _create_spark_effect(position, element)
	if effect:
		parent.add_child(effect)
		# 自动销毁
		effect.get_tree().create_timer(0.5).timeout.connect(effect.queue_free)


## 创建死亡特效
static func spawn_death_effect(parent: Node3D, position: Vector3) -> void:
	# 粒子爆发
	for i in 8:
		var spark := _create_spark_effect(position + Vector3(0, 0.5, 0), "physical")
		if spark:
			parent.add_child(spark)
			spark.get_tree().create_timer(0.8).timeout.connect(spark.queue_free)


## 创建火花粒子
static func _create_spark_effect(position: Vector3, _element: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	mesh.mesh = sphere
	mesh.position = position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat

	# 随机飞散
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "position", position + Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.5, 2.0),
		randf_range(-1.0, 1.0),
	), 0.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mesh, "scale", Vector3.ZERO, 0.5)

	return mesh