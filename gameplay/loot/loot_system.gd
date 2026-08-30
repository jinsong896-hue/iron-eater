class_name LootSystem
extends RefCounted
## 掉落系统 —— HD-2D 重构版
## 根据怪物数据生成掉落（装备 + 金币）
## enemy_data 兼容 MonsterData（.tres）与动态 Dictionary 两种来源

var rng := RandomNumberGenerator.new()


## 生成掉落（enemy_data: MonsterData 或含 hp/gold/loot 字段的 Dictionary）
func generate_loot(enemy_data, position: Vector3, parent: Node3D) -> void:
	# 金币掉落
	var gold := _roll_gold(enemy_data)
	if gold > 0:
		GameManager.gold += gold
		EventBus.gold_changed.emit(GameManager.gold)

	# 装备掉落
	var loot_id := _roll_loot(enemy_data)
	if loot_id.is_empty():
		return

	var template := EquipmentDB.get_template(StringName(loot_id))
	if template == null:
		return

	var item := EquipmentInstance.create(template)
	_spawn_pickup(item, position, parent)


## 金币掉落（基线范围 × 难度权重，来源字段可选）
func _roll_gold(enemy_data) -> int:
	if enemy_data == null:
		return 0
	if enemy_data is Dictionary and enemy_data.has("gold"):
		return int(enemy_data["gold"])
	return rng.randi_range(int(GameBalance.GOLD_DROP_RANGE.x), int(GameBalance.GOLD_DROP_RANGE.y))


## 装备掉落 ID（优先 loot_table 字段）
func _roll_loot(enemy_data) -> String:
	if enemy_data == null:
		return ""
	if enemy_data is Dictionary and enemy_data.has("loot"):
		return str(enemy_data["loot"])
	if "loot_table" in enemy_data and not str(enemy_data.loot_table).is_empty():
		return str(enemy_data.loot_table)
	return ""


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

	var rarity_color: Color = EquipmentDefs.RARITY_COLORS.get(item.rarity, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rarity_color
	mat.emission_enabled = true
	mat.emission = rarity_color
	mat.emission_energy_multiplier = 0.5
	mesh.material_override = mat

	# 旋转动画（item 用元数据传递，避免动态脚本引用全局类名）
	pickup.set_meta("instance_id", item.instance_id)
	pickup.set_meta("template_id", str(item.template_id))
	pickup.set_meta("rarity", item.rarity)
	var anim := pickup_anim_script()
	pickup.set_script(anim)
	pickup.set("item", item)

	pickup.add_child(mesh)
	parent.add_child(pickup)


## 掉落物动画脚本（缓存，避免每次掉落重新编译）
static var _anim_script: GDScript


static func pickup_anim_script() -> GDScript:
	if _anim_script == null:
		var script := GDScript.new()
		script.source_code = """
extends Node3D

var item: Resource

func _process(delta: float) -> void:
	rotate_y(delta * 2.0)
	position.y += sin(Time.get_ticks_msec() * 0.003) * 0.005

func devour() -> void:
	var result: Dictionary = GameManager.devour_item(item)
	if result.ok:
		queue_free()
"""
		script.reload()
		_anim_script = script
	return _anim_script