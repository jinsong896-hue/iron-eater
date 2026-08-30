class_name CombatSystem
extends RefCounted
## 战斗系统 —— HD-2D 重构版
## 统一管理攻击、伤害结算、死亡处理

## 近战攻击检测
static func melee_attack(attacker: Node3D, attack_direction: Vector3, attack_range: float, damage: float, element: String = "physical") -> int:
	var hit := 0
	for enemy in attacker.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node3D):
			continue
		if not enemy.has_method("take_damage"):
			continue

		var to_enemy := (enemy as Node3D).global_position - attacker.global_position
		if to_enemy.length() > attack_range:
			continue
		if attack_direction.length() > 0.01 and to_enemy.normalized().dot(attack_direction.normalized()) < 0.3:
			continue

		enemy.call("take_damage", damage, false)
		DamagePipeline.emit_damage_result(enemy, damage, "normal")
		hit += 1

	return hit


## AOE 范围攻击检测
static func aoe_attack(center: Vector3, radius: float, damage: float, element: String = "physical") -> int:
	var hit := 0
	var space := (Engine.get_main_loop() as SceneTree).root.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform.origin = center

	var results := space.intersect_shape(query)
	for result in results:
		var collider = result.get("collider")
		if collider == null or not is_instance_valid(collider):
			continue
		var parent := (collider as Node).get_parent()
		if parent != null and parent.has_method("take_damage"):
			parent.call("take_damage", damage, false)
			DamagePipeline.emit_damage_result(parent as Node3D, damage, "aoe")
			hit += 1

	return hit


## 远程投射物命中检测
static func check_projectile_hit(projectile: Node3D, hit_radius: float) -> Node:
	var space := projectile.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = hit_radius
	query.shape = sphere
	query.transform.origin = projectile.global_position
	query.exclude = [projectile.get_rid()]

	var results := space.intersect_shape(query)
	for result in results:
		var collider = result.get("collider")
		if collider == null or not is_instance_valid(collider):
			continue
		return collider
	return null