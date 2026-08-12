class_name EquipmentLoadout
extends RefCounted
## 10 槽位装备栏：头/胸/肩/手/腿/鞋 + 饰品×2 + 武器×2
## 双手武器占用武器1+武器2，但属性只计算一次

var slots: Dictionary = {}   # SlotId -> EquipmentInstance


func _init() -> void:
	for slot in EquipmentDefs.SlotId.values():
		slots[slot] = null


func get_item(slot: int) -> EquipmentInstance:
	return slots.get(slot)


func is_occupied(slot: int) -> bool:
	return slots.get(slot) != null


func is_two_hand_weapon(item: EquipmentInstance) -> bool:
	var t := item.get_template()
	return t != null and t.category == EquipmentDefs.Category.WEAPON \
		and not (t.weapon_type in EquipmentDefs.ONE_HAND_WEAPONS)


## 尝试装备到指定槽位；返回 {ok, reason, slots_used}
func equip(item: EquipmentInstance, target_slot: int) -> Dictionary:
	var t := item.get_template()
	if t == null:
		return {"ok": false, "reason": "模板缺失"}
	var is_two_hand := is_two_hand_weapon(item)
	if is_two_hand:
		# 双手武器：清空武器1/2 后占用两槽
		slots[EquipmentDefs.SlotId.WEAPON_1] = null
		slots[EquipmentDefs.SlotId.WEAPON_2] = null
		slots[EquipmentDefs.SlotId.WEAPON_1] = item
		slots[EquipmentDefs.SlotId.WEAPON_2] = item
		return {"ok": true, "slots_used": [EquipmentDefs.SlotId.WEAPON_1, EquipmentDefs.SlotId.WEAPON_2]}
	if t.slot_category == EquipmentDefs.SlotCategory.ACCESSORY:
		if target_slot != EquipmentDefs.SlotId.ACCESSORY_1 and target_slot != EquipmentDefs.SlotId.ACCESSORY_2:
			target_slot = _first_empty_accessory()
	elif t.slot_category == EquipmentDefs.SlotCategory.WEAPON:
		if target_slot != EquipmentDefs.SlotId.WEAPON_1 and target_slot != EquipmentDefs.SlotId.WEAPON_2:
			target_slot = _first_empty_weapon()
	# 单手武器不可与双手武器并存
	if t.slot_category == EquipmentDefs.SlotCategory.WEAPON:
		var other_slot := EquipmentDefs.SlotId.WEAPON_2 if target_slot == EquipmentDefs.SlotId.WEAPON_1 else EquipmentDefs.SlotId.WEAPON_1
		var other: EquipmentInstance = slots.get(other_slot)
		if other != null and is_two_hand_weapon(other):
			return {"ok": false, "reason": "另一武器槽被双手武器占用"}
	if target_slot < 0 or target_slot >= EquipmentDefs.SlotId.values().size():
		return {"ok": false, "reason": "无效槽位"}
	slots[target_slot] = item
	return {"ok": true, "slots_used": [target_slot]}


func unequip(slot: int) -> EquipmentInstance:
	var item: EquipmentInstance = slots.get(slot)
	if item == null:
		return null
	# 双手武器：两个槽指向同一实例，一次卸下同时清空
	var other_slot := EquipmentDefs.SlotId.WEAPON_2 if slot == EquipmentDefs.SlotId.WEAPON_1 else EquipmentDefs.SlotId.WEAPON_1
	if slots.get(other_slot) == item:
		slots[other_slot] = null
	slots[slot] = null
	return item


func equipped_items() -> Array:
	var seen := {}
	var result: Array = []
	for slot in slots:
		var item: EquipmentInstance = slots[slot]
		if item != null and not seen.has(item):
			seen[item] = true
			result.append(item)
	return result


func is_equipped(item: EquipmentInstance) -> bool:
	for slot in slots:
		if slots[slot] == item:
			return true
	return false


func _first_empty_accessory() -> int:
	if slots.get(EquipmentDefs.SlotId.ACCESSORY_1) == null:
		return EquipmentDefs.SlotId.ACCESSORY_1
	return EquipmentDefs.SlotId.ACCESSORY_2


func _first_empty_weapon() -> int:
	if slots.get(EquipmentDefs.SlotId.WEAPON_1) == null:
		return EquipmentDefs.SlotId.WEAPON_1
	return EquipmentDefs.SlotId.WEAPON_2
