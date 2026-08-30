class_name EquipmentRuntime
extends Node
## 装备运行时 —— 武器融合/吞噬/词条生效
## 文档：ai/框架相关.md Equipment Studio

var weapon: WeaponData
var modifiers: Array[ModifierData] = []


## 装备武器（应用其 Modifier 与吞噬效果）
func equip(w: WeaponData) -> void:
	weapon = w
	modifiers.clear()
	modifiers.append_array(w.modifiers)
	modifiers.append_array(w.devour_effects)


## 融合（提升武器融合等级）
func fuse() -> bool:
	if weapon == null or not weapon.can_fuse():
		return false
	weapon.fuse()
	return true


## 吞噬目标武器（继承其词条）
func devour(target: WeaponData) -> void:
	if weapon == null or target == null:
		return
	weapon.devour_effects.append_array(target.modifiers)
	modifiers.append_array(target.modifiers)


## 当前攻击力
func get_atk() -> int:
	if weapon == null:
		return 0
	return weapon.current_atk()


## 描述文本
func description() -> String:
	if weapon == null:
		return "无装备"
	return weapon.description()
