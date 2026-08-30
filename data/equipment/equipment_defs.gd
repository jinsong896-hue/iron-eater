class_name EquipmentDefs
extends RefCounted
## 装备系统常量定义

enum Rarity {
	WHITE,
	GREEN,
	BLUE,
	PURPLE,
	ORANGE,
	RED,
}

enum Category {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

enum Slot {
	HEAD,
	CHEST,
	SHOULDERS,
	HANDS,
	LEGS,
	FEET,
	ACCESSORY_1,
	ACCESSORY_2,
	WEAPON_1,
	WEAPON_2,
}

enum ArmorClass {
	LIGHT,
	MEDIUM,
	HEAVY,
}

const RARITY_COLORS := {
	Rarity.WHITE: Color(0.85, 0.85, 0.85),
	Rarity.GREEN: Color(0.35, 0.85, 0.35),
	Rarity.BLUE: Color(0.35, 0.65, 0.95),
	Rarity.PURPLE: Color(0.85, 0.35, 0.95),
	Rarity.ORANGE: Color(0.95, 0.65, 0.15),
	Rarity.RED: Color(0.95, 0.15, 0.15),
}

const SINGLE_HAND_WEAPONS := ["sword", "dagger", "axe", "crossbow", "shield"]


static func rarity_name(r: int) -> String:
	match r:
		Rarity.WHITE: return "白色"
		Rarity.GREEN: return "绿色"
		Rarity.BLUE: return "蓝色"
		Rarity.PURPLE: return "紫色"
		Rarity.ORANGE: return "橙色"
		Rarity.RED: return "红色"
	return "未知"


static func category_name(c: int) -> String:
	match c:
		Category.WEAPON: return "武器"
		Category.ARMOR: return "护甲"
		Category.ACCESSORY: return "饰品"
	return "未知"


static func slot_name(s: int) -> String:
	match s:
		Slot.HEAD: return "头盔"
		Slot.CHEST: return "胸甲"
		Slot.SHOULDERS: return "肩甲"
		Slot.HANDS: return "护手"
		Slot.LEGS: return "腿甲"
		Slot.FEET: return "鞋子"
		Slot.ACCESSORY_1: return "饰品 1"
		Slot.ACCESSORY_2: return "饰品 2"
		Slot.WEAPON_1: return "武器 1"
		Slot.WEAPON_2: return "武器 2"
	return "未知"
