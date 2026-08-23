class_name EquipmentRuntime
extends Node
## 装备运行时 —— 武器融合/吞噬/词条生效
## 文档：ai/框架相关.md Equipment Studio

var weapon: WeaponData
var modifiers: Array[ModifierData] = []


func equip(w: WeaponData) -> void:
	weapon = w
	modifiers.clear()
	modifiers.append_array(w.modifiers)
	modifiers.append_array(w.devour_effects)


func fuse() -> bool:
	if weapon == null or not weapon.can_fuse():
		return false
	weapon.fuse()
	return true


func devour(target: WeaponData) -> void:
	if weapon == null or target == null:
		return
	weapon.devour_effects.append_array(target.modifiers)
	modifiers.append_array(target.modifiers)


func get_atk() -> int:
	if weapon == null:
		return 0
	return weapon.current_atk()


func description() -> String:
	if weapon == null:
		return "无装备"
	return weapon.description()
