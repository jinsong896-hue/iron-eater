class_name EquipmentManager
extends RefCounted
## 装备管理器：背包 + 装备栏 + 吞噬/融合/强化/掉落（纯逻辑，不依赖场景）

var inventory: Array[EquipmentInstance] = []
var loadout := EquipmentLoadout.new()
var devour_totals := {}   # stat -> {"flat": float, "percent": float}（本局吞噬累计）


func _init() -> void:
	loadout = EquipmentLoadout.new()


func add_item(item: EquipmentInstance) -> void:
	inventory.append(item)


func remove_item(item: EquipmentInstance) -> bool:
	var idx := inventory.find(item)
	if idx < 0:
		return false
	inventory.remove_at(idx)
	return true


func all_items() -> Array:
	var result: Array = inventory.duplicate()
	for item in loadout.equipped_items():
		if not result.has(item):
			result.append(item)
	return result


func find_item(instance_id: String) -> EquipmentInstance:
	for item in all_items():
		if item.instance_id == instance_id:
			return item
	return null


# ---------------------------------------------------------------------------
# 穿戴 / 卸下
# ---------------------------------------------------------------------------

func equip(instance_id: String, target_slot: int = -1) -> Dictionary:
	var item := _inventory_by_id(instance_id)
	if item == null:
		return {"ok": false, "reason": "装备不在背包"}
	# 双手武器替换单手武器时，先把占槽装备收回背包
	if loadout.is_two_hand_weapon(item):
		for slot in [EquipmentDefs.SlotId.WEAPON_1, EquipmentDefs.SlotId.WEAPON_2]:
			var occupied := loadout.get_item(slot)
			if occupied != null and occupied != item:
				loadout.unequip(slot)
				inventory.append(occupied)
	var result := loadout.equip(item, target_slot)
	if result.ok:
		remove_item(item)
	return result


func unequip(slot: int) -> Dictionary:
	var item := loadout.unequip(slot)
	if item == null:
		return {"ok": false, "reason": "槽位为空"}
	inventory.append(item)
	return {"ok": true}


func _inventory_by_id(instance_id: String) -> EquipmentInstance:
	for item in inventory:
		if item.instance_id == instance_id:
			return item
	return null


# ---------------------------------------------------------------------------
# 吞噬（确定成功，不会失败；支持批量）
# ---------------------------------------------------------------------------

## 返回 {ok, count, totals: {stat: {"flat": x, "percent": y}}}
func devour_many(ids: Array) -> Dictionary:
	var totals := {}
	var removed := 0
	for id in ids:
		var item := _inventory_by_id(id)
		if item == null:
			continue
		if item.is_locked:
			continue
		var t := item.get_template()
		if t == null or t.devour_affix == null:
			continue
		var affix: AffixData = t.devour_affix
		if not totals.has(affix.stat):
			totals[affix.stat] = {"flat": 0.0, "percent": 0.0}
		if affix.operation == EquipmentDefs.ModifierOperation.ADD_PERCENT:
			totals[affix.stat]["percent"] += affix.value
		else:
			totals[affix.stat]["flat"] += affix.value
		remove_item(item)
		removed += 1
	# 合并进本局累计
	for stat in totals:
		if not devour_totals.has(stat):
			devour_totals[stat] = {"flat": 0.0, "percent": 0.0}
		devour_totals[stat]["flat"] += totals[stat]["flat"]
		devour_totals[stat]["percent"] += totals[stat]["percent"]
	return {"ok": removed > 0, "count": removed, "totals": totals}


func devour_one(instance_id: String) -> Dictionary:
	return devour_many([instance_id])


# ---------------------------------------------------------------------------
# 融合（事务式：先校验，再提交）
# ---------------------------------------------------------------------------

## 返回 {ok, status, reason, cost, main_fusion_before, main_fusion_after, new_affix}
func fuse(main_id: String, material_id: String, gold: int) -> Dictionary:
	var main_item := find_item(main_id)
	var material := _inventory_by_id(material_id)
	var validation := FusionRules.validate(
		main_item, material, gold,
		main_item != null, material != null)
	if validation.status != FusionRules.FuseStatus.OK:
		return {"ok": false, "status": validation.status, "reason": validation.reason, "cost": validation.cost}
	var main_t: EquipmentTemplate = main_item.get_template()
	var mat_t: EquipmentTemplate = material.get_template()
	var before_count := main_item.fusion_count
	var new_affix: AffixInstance = null
	# 同名 → 随机升级已有融合词条；异名 → 继承材料融合词条
	if mat_t.id == main_t.id and not main_item.gained_fusion_affixes.is_empty():
		var target: AffixInstance = main_item.gained_fusion_affixes[randi() % main_item.gained_fusion_affixes.size()]
		target.stack_count += 1
		new_affix = target
	else:
		new_affix = AffixInstance.from_data(mat_t.fusion_affix)
		var existing: AffixInstance = null
		for a in main_item.gained_fusion_affixes:
			if a.affix_id == new_affix.affix_id:
				existing = a
				break
		if existing != null:
			existing.stack_count += 1
			new_affix = existing
		else:
			main_item.gained_fusion_affixes.append(new_affix)
	main_item.fusion_count += 1
	remove_item(material)
	return {
		"ok": true, "status": FusionRules.FuseStatus.OK,
		"cost": validation.cost, "main_fusion_before": before_count,
		"main_fusion_after": main_item.fusion_count, "new_affix": new_affix,
	}


# ---------------------------------------------------------------------------
# 强化（只提升基础词条，固定百分比，无失败）
# ---------------------------------------------------------------------------

func enhance(instance_id: String, gold: int) -> Dictionary:
	var item := find_item(instance_id)
	if item == null:
		return {"ok": false, "reason": "装备不存在"}
	var cost := EnhancementRules.cost(item.enhancement_level)
	if gold < cost:
		return {"ok": false, "reason": "金币不足，还差 %d" % (cost - gold), "cost": cost}
	item.enhancement_level += 1
	return {"ok": true, "cost": cost, "level_before": item.enhancement_level - 1, "level_after": item.enhancement_level}


# ---------------------------------------------------------------------------
# 掉落 / 序列化
# ---------------------------------------------------------------------------

## 按稀有度权重生成一件装备实例（现阶段白装池，权重预留绿+）
func create_loot() -> EquipmentInstance:
	var templates: Array = EquipmentDB.all_templates()
	if templates.is_empty():
		return null
	var t: EquipmentTemplate = templates[randi() % templates.size()]
	return EquipmentInstance.create(t)


func serialize() -> Dictionary:
	var items: Array = []
	var equipped_ids := {}
	for item in all_items():
		items.append(item.to_dict())
	for slot in EquipmentDefs.SlotId.values():
		var item := loadout.get_item(slot)
		equipped_ids[str(slot)] = item.instance_id if item != null else ""
	return {
		"inventory": items, "equipped": equipped_ids,
		"devour_totals": devour_totals,
	}


func deserialize(data: Dictionary) -> void:
	inventory.clear()
	var all_instances := {}
	for d in data.get("inventory", []):
		var item := EquipmentInstance.from_dict(d)
		all_instances[item.instance_id] = item
	loadout = EquipmentLoadout.new()
	var equipped_ids: Dictionary = data.get("equipped", {})
	var equipped_used := {}
	for slot_str in equipped_ids:
		var id: String = equipped_ids[slot_str]
		if id != "" and all_instances.has(id):
			loadout.slots[int(slot_str)] = all_instances[id]
			equipped_used[id] = true
	for id in all_instances:
		if not equipped_used.has(id):
			inventory.append(all_instances[id])
	devour_totals = data.get("devour_totals", {}).duplicate(true)
