class_name LootSystem
extends RefCounted
## 掉落系统 —— HD-2D 重构版
## 敌人死亡 → 金币直接入账 + 按掉率随机掉白装 → 掉落物可拾取/吞噬
## enemy_data 兼容 MonsterData（.tres）与动态 Dictionary 两种来源

var rng := RandomNumberGenerator.new()


## 生成掉落（enemy_data: MonsterData / EnemyBase / Dictionary）
func generate_loot(enemy_data, position: Vector3, parent: Node3D) -> void:
	# 金币掉落（直接入账）
	var gold := _roll_gold(enemy_data)
	var gm = _game_manager()
	var bus = _event_bus()
	if gold > 0 and gm:
		gm.gold += gold
		if bus:
			bus.gold_changed.emit(gm.gold)

	# 装备掉落：优先显式掉落表，否则按概率从白装池随机
	var template := _roll_template(enemy_data)
	if template == null:
		return

	var item := EquipmentInstance.create(template)
	_spawn_pickup(item, position, parent)


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


## 金币掉落（来源字段优先，否则基线范围随机）
func _roll_gold(enemy_data) -> int:
	if enemy_data == null:
		return 0
	if enemy_data is Dictionary:
		return int(enemy_data.get("gold", rng.randi_range(
			int(GameBalance.GOLD_DROP_RANGE.x), int(GameBalance.GOLD_DROP_RANGE.y))))
	if "gold_min" in enemy_data and "gold_max" in enemy_data:
		return rng.randi_range(int(enemy_data.gold_min), int(enemy_data.gold_max))
	return rng.randi_range(int(GameBalance.GOLD_DROP_RANGE.x), int(GameBalance.GOLD_DROP_RANGE.y))


## 掉落装备模板：显式 loot_table 优先；否则按 BASE_DROP_CHANCE 从白装池随机
func _roll_template(enemy_data) -> EquipmentTemplate:
	# 显式掉落表
	var loot_id := _explicit_loot_id(enemy_data)
	if not loot_id.is_empty():
		return EquipmentDB.get_template(StringName(loot_id))

	# 白装池随机掉落
	if rng.randf() > GameBalance.BASE_DROP_CHANCE:
		return null
	var pool := EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## 显式掉落 ID（loot_table 字段）
func _explicit_loot_id(enemy_data) -> String:
	if enemy_data == null:
		return ""
	if enemy_data is Dictionary:
		return str(enemy_data.get("loot", ""))
	if "loot_table" in enemy_data:
		return str(enemy_data.loot_table)
	return ""


## 创建掉落物节点（走近可拾取，F 可吞噬）
func _spawn_pickup(item: EquipmentInstance, position: Vector3, parent: Node3D) -> void:
	var pickup := Node3D.new()
	pickup.name = "Pickup_%s" % item.display_name()
	pickup.position = position + Vector3(0.0, 0.5, 0.0)
	pickup.add_to_group("pickups")

	# 视觉：稀有度颜色的发光方块
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

	pickup.set_meta("instance_id", item.instance_id)
	pickup.set_meta("template_id", str(item.template_id))
	pickup.set_meta("rarity", item.rarity)
	pickup.set_script(pickup_anim_script())
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
## 掉落物 —— 旋转动画 + 拾取（pick_up）/ 吞噬（devour）

var item: Resource

func _process(delta: float) -> void:
	rotate_y(delta * 2.0)
	position.y += sin(Time.get_ticks_msec() * 0.003) * 0.005

## 拾取进背包
func pick_up() -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	if not GameManager.equipment_manager.add_item(item):
		return {"ok": false, "reason": "背包已满"}
	EventBus.item_picked_up.emit(item.instance_id, item.display_name())
	EventBus.message.emit("拾取：%s" % item.display_name())
	AudioManager.play("pickup")
	queue_free()
	return {"ok": true}

## 原地吞噬（本局永久成长）
func devour() -> Dictionary:
	var result: Dictionary = GameManager.devour_item(item)
	if result.get("ok", false):
		queue_free()
	return result
"""
		script.reload()
		_anim_script = script
	return _anim_script
