class_name SkillSystem
extends RefCounted
## 技能系统 —— HD-2D 重构版
## 统一管理技能释放、冷却、效果

var _cooldowns: Dictionary = {}   # skill_id -> remaining_time
var _rng := RandomNumberGenerator.new()


## 释放技能
func cast_skill(caster: Node3D, skill_id: String, direction: Vector3) -> Dictionary:
	var skill_data := GameBalance.skill_by_id(skill_id)
	if skill_data.is_empty():
		return {"ok": false, "reason": "未知技能"}

	# 检查冷却
	if _is_on_cooldown(skill_id):
		return {"ok": false, "reason": "技能冷却中"}

	# 应用冷却
	var cd = skill_data.get("cooldown", 1.0)
	_cooldowns[skill_id] = cd

	# 执行技能效果
	var kind = skill_data.get("kind", "projectile")
	match kind:
		"projectile":
			_cast_projectile(caster, skill_data, direction)
		"aoe":
			_cast_aoe(caster, skill_data, direction)
		"melee":
			_cast_melee(caster, skill_data, direction)

	return {"ok": true, "skill": skill_id}


## 投射物技能
func _cast_projectile(caster: Node3D, skill_data: Dictionary, direction: Vector3) -> void:
	var projectile_data := {
		"skill_id": skill_data.get("id", ""),
		"direction": direction.normalized(),
		"speed": skill_data.get("speed", 10.0),
		"damage": skill_data.get("damage", 10.0),
		"lifetime": skill_data.get("lifetime", 2.0),
		"element": skill_data.get("element", "physical"),
		"pierce_count": skill_data.get("pierce_count", 0),
	}

	var projectile := ProjectileSystem.spawn(projectile_data, caster.get_parent())
	projectile.position = caster.global_position + direction.normalized() * 0.5


## AOE 技能
func _cast_aoe(caster: Node3D, skill_data: Dictionary, _direction: Vector3) -> void:
	var damage = skill_data.get("damage", 10.0)
	var radius = skill_data.get("aoe_radius", 3.0)
	var element = skill_data.get("element", "physical")
	CombatSystem.aoe_attack(caster.global_position, radius, damage, element)


## 近战技能
func _cast_melee(caster: Node3D, skill_data: Dictionary, direction: Vector3) -> void:
	var damage = skill_data.get("damage", 10.0)
	var range = skill_data.get("range", 2.0)
	CombatSystem.melee_attack(caster, direction, range, damage)


## 更新冷却
func update_cooldowns(delta: float) -> void:
	for skill_id in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(_cooldowns[skill_id] - delta, 0.0)
		if _cooldowns[skill_id] <= 0.0:
			_cooldowns.erase(skill_id)


func _is_on_cooldown(skill_id: String) -> bool:
	return _cooldowns.has(skill_id) and _cooldowns[skill_id] > 0.0


func get_cooldown_remaining(skill_id: String) -> float:
	return _cooldowns.get(skill_id, 0.0)