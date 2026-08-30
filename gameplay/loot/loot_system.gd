class_name LootSystem
extends RefCounted
## 掉落系统 —— HD-2D 重构版
## 根据敌人类型和难度生成掉落（装备 + 金币）

var rng := RandomNumberGenerator.new()


## 生成掉落
func generate_loot(enemy_data: EnemyData, position: Vector3, parent: Node3D) -> void:
	# 金币掉落
	var gold := enemy_data.get_random_gold(rng)
	if gold > 0:
		GameManager.gold += gold
		EventBus.gold_changed.emit(GameManager.gold)

	# 装备掉落
	var loot_id := enemy_data.get_random_loot(rng)
	if loot_id.is_empty():
		return

	var template := EquipmentDB.get_template(loot_id)
	if template == null:
		return

	var item := EquipmentInstance.create(template)
	# TODO: 创建 3D 掉落物
	_spawn_pickup(item, position, parent)


## 创建掉落物节点
func _spawn_pickup(item: EquipmentInstance, position: Vector3, parent: Node3D) -> void:
	# 创建简单的 3D 掉落物
	var pickup := Node3D.new()
	pickup.name = "Pickup_%s" % item.display_name()
	pickup.position = position + Vector3(0.0, 0.5, 0.0)
	pickup.add_to_group("pickups")

	# 视觉
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = EquipmentDefs.rarity_color(item.rarity)
	mat.emission_enabled = true
	mat.emission = EquipmentDefs.rarity_color(item.rarity)
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat

	# 旋转动画
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var item: EquipmentInstance

func _process(delta: float) -> void:
	rotate_y(delta * 2.0)
	position.y += sin(Time.get_ticks_msec() * 0.003) * 0.005

func devour() -> void:
	var result := GameManager.devour_item(item)
	if result.ok:
		queue_free()
"""
	script.reload()
	pickup.set_script(script)
	pickup.set("item", item)

	pickup.add_child(mesh)
	parent.add_child(pickup)