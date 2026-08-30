class_name EquipmentManager
extends RefCounted
## 装备管理器 —— HD-2D 重构版
## 管理装备穿戴、吞噬、融合、背包

var rng: RandomNumberGenerator

# 最大强化等级（强化只提升基础词条，固定 +5%/级，无失败）
const MAX_ENHANCEMENT_LEVEL := 10

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
	_emit_bus("inventory_changed")
	return true


## 移除装备
func remove_item(inst: EquipmentInstance) -> void:
	_inventory.erase(inst)
	_emit_bus("inventory_changed")


## 装备到槽位（物品从背包转入槽位，旧装备退回背包）
func equip(slot: int, inst: EquipmentInstance) -> void:
	# 若已穿戴在其他槽位，先卸下
	for s in _equipped.keys():
		if _equipped[s] == inst:
			unequip(s)
	if _equipped.has(slot):
		var old: EquipmentInstance = _equipped[slot]
		unequip(slot)
		if old != inst:
			_inventory.append(old)
	_equipped[slot] = inst
	_inventory.erase(inst)
	_apply_equipment_modifiers(inst)
	var bus = _event_bus()
	if bus:
		bus.equipment_changed.emit(slot, inst.instance_id)
		bus.stats_changed.emit()


## 卸下装备（退回背包）
func unequip(slot: int) -> void:
	if not _equipped.has(slot):
		return
	var inst: EquipmentInstance = _equipped[slot]
	_remove_equipment_modifiers(inst)
	_equipped.erase(slot)
	if _inventory.size() < _max_inventory_size:
		_inventory.append(inst)
	var bus = _event_bus()
	if bus:
		bus.equipment_changed.emit(slot, "")
		bus.stats_changed.emit()


## 吞噬装备（本局永久成长）
func devour(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}

	var template := item.get_template()
	if template == null or template.devour_affix == null:
		return {"ok": false, "reason": "该物品不可吞噬"}

	# 应用吞噬词条
	var affix := template.devour_affix
	var gm = _game_manager()
	if gm and gm.attributes:
		if affix.operation == AffixData.Operation.PERCENT:
			gm.attributes.add_modifier(
				"devour_%s" % item.instance_id,
				affix.stat,
				0.0,
				affix.value
			)
		else:
			gm.attributes.add_modifier(
				"devour_%s" % item.instance_id,
				affix.stat,
				affix.value
			)

	remove_item(item)
	var bus = _event_bus()
	if bus:
		bus.item_devoured.emit(item.instance_id, item.display_name())
		bus.stats_changed.emit()
	return {"ok": true}


## 融合装备（main 吃 material：同槽位校验 + 词条继承 + 金币计费）
func fuse(main: EquipmentInstance, material: EquipmentInstance) -> Dictionary:
	if main == null or material == null:
		return {"ok": false, "reason": "无效物品"}
	if not FusionRules.can_fuse(main.fusion_count):
		return {"ok": false, "reason": "已达最大融合等级"}

	# 同槽位校验（策划口径：同部位装备才能作为融合材料）
	var main_tpl := main.get_template()
	var mat_tpl := material.get_template()
	if main_tpl == null or mat_tpl == null:
		return {"ok": false, "reason": "装备数据异常"}
	if main_tpl.slot != mat_tpl.slot:
		return {"ok": false, "reason": "材料必须为同部位装备"}
	if material.is_locked:
		return {"ok": false, "reason": "材料已锁定"}

	# 金币计费（策划公式：BASE_COST × (1 + 融合数 × 0.3)）
	var cost := FusionRules.fusion_cost(main, material)
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	main.fusion_count = FusionRules.next_fusion_count(main.fusion_count)
	if gm:
		gm.gold -= cost
		gm.fusion_count += 1
	_recalc_fusion_bonus()
	remove_item(material)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "new_tier": main.fusion_tier(), "cost": cost}


## 强化装备（只提升基础词条，固定 +5%/级，无失败）
func enhance(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效物品"}
	if item.enhancement_level >= MAX_ENHANCEMENT_LEVEL:
		return {"ok": false, "reason": "已达最大强化等级"}

	var cost := enhancement_cost(item)
	var gm = _game_manager()
	if gm and gm.gold < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}

	item.enhancement_level += 1
	if gm:
		gm.gold -= cost
	# 若已穿戴，词条数值变化需重挂 Modifier
	if _equipped.values().has(item):
		_remove_equipment_modifiers(item)
		_apply_equipment_modifiers(item)
	_emit_bus("inventory_changed")
	_emit_bus("stats_changed")
	return {"ok": true, "level": item.enhancement_level, "cost": cost}


## 强化费用（基础 20 + 等级 × 15）
func enhancement_cost(item: EquipmentInstance) -> int:
	return 20 + item.enhancement_level * 15


## 卸下装备（按实例查槽位）
func unequip_item(item: EquipmentInstance) -> void:
	for slot in _equipped.keys():
		if _equipped[slot] == item:
			unequip(slot)
			return


## 获取融合攻击总加成
func fusion_attack_bonus() -> float:
	return _fusion_attack_bonus


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


## 发射无参信号（EventBus 不存在时静默跳过）
func _emit_bus(signal_name: String) -> void:
	var bus = _event_bus()
	if bus:
		bus.emit_signal(signal_name)


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
	_emit_bus("inventory_changed")


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
	var gm = _game_manager()
	if gm and gm.attributes:
		gm.attributes.add_modifier(
			"equip_%s" % inst.instance_id,
			affix.stat,
			value,
			percent
		)


## 移除装备词条
func _remove_equipment_modifiers(inst: EquipmentInstance) -> void:
	var gm = _game_manager()
	if gm and gm.attributes:
		gm.attributes.remove_modifiers("equip_%s" % inst.instance_id)


## 重算背包内所有物品的融合加成总和
func _recalc_fusion_bonus() -> void:
	_fusion_attack_bonus = 0.0
	for item in _inventory:
		_fusion_attack_bonus += item.fusion_bonus()