class_name EquipmentManager
extends RefCounted
## 装备管理器 —— HD-2D 重构版
## 管理装备穿戴、吞噬、融合、背包

var rng: RandomNumberGenerator

# 装备槽位
var _equipped: Dictionary = {}          # slot -> EquipmentInstance
var _inventory: Array[EquipmentInstance] = []
var _max_inventory_size := 20

# 融合攻击加成缓存
var _fusion_attack_bonus: float = 0.0


## 添加装备到背包
func add_item(inst: EquipmentInstance) -> bool:
	if _inventory.size() >= _max_inventory_size:
		return false
	_inventory.append(inst)
	EventBus.inventory_changed.emit()
	return true


## 移除装备
func remove_item(inst: EquipmentInstance) -> void:
	_inventory.erase(inst)
	EventBus.inventory_changed.emit()


## 装备到槽位
func equip(slot: int, inst: EquipmentInstance) -> void:
	if _equipped.has(slot):
		unequip(slot)
	_equipped[slot] = inst
	_apply_equipment_modifiers(inst)
	EventBus.equipment_changed.emit(slot, inst.instance_id)
	EventBus.stats_changed.emit()


## 卸下装备
func unequip(slot: int) -> void:
	if not _equipped.has(slot):
		return
	var inst: EquipmentInstance = _equipped[slot]
	_remove_equipment_modifiers(inst)
	_equipped.erase(slot)
	EventBus.equipment_changed.emit(slot, "")
	EventBus.stats_changed.emit()


## 吞噬装备（本局永久成长）
func devour(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}

	var template := item.get_template()
	if template == null or template.devour_affix == null:
		return {"ok": false, "reason": "该物品不可吞噬"}

	# 应用吞噬词条
	var affix := template.devour_affix
	if affix.operation == AffixData.Operation.PERCENT:
		GameManager.attributes.add_modifier(
			"devour_%s" % item.instance_id,
			affix.stat,
			0.0,
			affix.value
		)
	else:
		GameManager.attributes.add_modifier(
			"devour_%s" % item.instance_id,
			affix.stat,
			affix.value
		)

	remove_item(item)
	EventBus.item_devoured.emit(item.instance_id, item.display_name())
	EventBus.stats_changed.emit()
	return {"ok": true}


## 融合装备
func fuse(main: EquipmentInstance, material: EquipmentInstance) -> Dictionary:
	if not FusionRules.can_fuse(main.fusion_count):
		return {"ok": false, "reason": "已达最大融合等级"}

	main.fusion_count = FusionRules.next_fusion_count(main.fusion_count)
	_recalc_fusion_bonus()
	remove_item(material)
	EventBus.inventory_changed.emit()
	EventBus.stats_changed.emit()
	return {"ok": true, "new_tier": main.fusion_tier()}


## 获取融合攻击总加成
func fusion_attack_bonus() -> float:
	return _fusion_attack_bonus


## 获取背包所有物品
func get_inventory() -> Array:
	return _inventory.duplicate()


## 交换背包内两个物品的顺序（拖拽排序用）
func swap_items(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= _inventory.size() or to >= _inventory.size():
		return
	if from == to:
		return
	var tmp = _inventory[from]
	_inventory[from] = _inventory[to]
	_inventory[to] = tmp
	EventBus.inventory_changed.emit()


## 获取已装备物品
func get_equipped() -> Dictionary:
	return _equipped.duplicate()


## 应用装备基础词条到属性系统
func _apply_equipment_modifiers(inst: EquipmentInstance) -> void:
	var template := inst.get_template()
	if template == null or template.base_affix == null:
		return
	var affix := template.base_affix
	var value := inst.base_affix_value()
	var percent := 0.0
	if affix.operation == AffixData.Operation.PERCENT:
		percent = affix.value * inst.enhancement_mult()
	GameManager.attributes.add_modifier(
		"equip_%s" % inst.instance_id,
		affix.stat,
		value,
		percent
	)


## 移除装备词条
func _remove_equipment_modifiers(inst: EquipmentInstance) -> void:
	GameManager.attributes.remove_modifiers("equip_%s" % inst.instance_id)


## 重算背包内所有物品的融合加成总和
func _recalc_fusion_bonus() -> void:
	_fusion_attack_bonus = 0.0
	for item in _inventory:
		_fusion_attack_bonus += item.fusion_bonus()