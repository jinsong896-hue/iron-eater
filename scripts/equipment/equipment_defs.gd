class_name EquipmentDefs
extends RefCounted
## 装备系统基础定义：《ai/基础装备相关.md》确定的装备分类体系
## 10 槽位：头/胸/肩/手/腿/鞋 + 饰品×2 + 武器×2

enum Rarity { WHITE, GREEN, BLUE, PURPLE, ORANGE, RED }

enum Category { WEAPON, ARMOR, ACCESSORY }

enum SlotCategory { HEAD, CHEST, SHOULDERS, HANDS, LEGS, FEET, ACCESSORY, WEAPON }

enum SlotId { HEAD, CHEST, SHOULDERS, HANDS, LEGS, FEET, ACCESSORY_1, ACCESSORY_2, WEAPON_1, WEAPON_2 }

enum WeaponType { SWORD, DAGGER, CROSSBOW, AXE, SHIELD, GREATSWORD, GREATAXE, SPEAR, BOW, HEAVY_CROSSBOW, STAFF, SCYTHE }

enum ArmorClass { LIGHT, MEDIUM, HEAVY }

enum ModifierOperation { FLAT, ADD_PERCENT, MULTIPLY }

## 单手武器白名单：其余武器类型自动视为双手
const ONE_HAND_WEAPONS := [
	WeaponType.SWORD, WeaponType.DAGGER, WeaponType.CROSSBOW,
	WeaponType.AXE, WeaponType.SHIELD,
]

const RARITY_NAMES := ["白", "绿", "蓝", "紫", "橙", "红"]
const CATEGORY_NAMES := ["武器", "护甲", "饰品"]
const SLOT_CATEGORY_NAMES := ["头盔", "胸甲", "肩甲", "护手", "腿甲", "鞋子", "饰品", "武器"]
const SLOT_NAMES := ["头盔", "胸甲", "肩甲", "护手", "腿甲", "鞋子", "饰品1", "饰品2", "武器1", "武器2"]
const WEAPON_TYPE_NAMES := ["单手剑", "匕首", "单手弩", "单手斧", "盾牌", "巨剑", "巨斧", "长枪", "长弓", "重弩", "法杖", "战镰"]
const ARMOR_CLASS_NAMES := ["轻甲", "中甲", "重甲"]
const OPERATION_NAMES := ["固定", "百分比", "乘算"]

const TAG_WHITE := "白色"
const TAG_ONE_HAND := "单手"
const TAG_TWO_HAND := "双手"
const TAG_MELEE := "近战"
const TAG_RANGED := "远程"
const TAG_POLE := "长杆"
const TAG_PHYSICAL := "物理"
const TAG_MAGIC := "法术"
const TAG_OTHER := "其他"
const TAG_LIGHT := "轻甲"
const TAG_MEDIUM := "中甲"
const TAG_HEAVY := "重甲"

const STAT_NAMES := {
	"atk": "攻击力", "def": "防御", "spd": "移动速度", "aspd": "攻速",
	"rng": "射程", "ap": "法术强度", "mp": "法力值", "cdr": "冷却缩减",
	"crt": "暴击率", "crd": "暴击伤害加成", "hp": "生命值",
}


## 武器分类标签：单手/双手自动生成，其余由武器特质提供
static func weapon_tags(weapon_type: int, traits: Array) -> Array:
	var tags: Array = []
	tags.append(TAG_ONE_HAND if weapon_type in ONE_HAND_WEAPONS else TAG_TWO_HAND)
	for t in traits:
		tags.append(t)
	return tags


static func rarity_name(r: int) -> String:
	return RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)]


static func stat_label(stat: String) -> String:
	return STAT_NAMES.get(stat, stat)


static func format_modifier(stat: String, operation: int, value: float) -> String:
	var label := stat_label(stat)
	if operation == ModifierOperation.ADD_PERCENT:
		return "%s +%.1f%%" % [label, value * 100.0]
	if operation == ModifierOperation.MULTIPLY:
		return "%s ×%.2f" % [label, value]
	return "%s +%.2f" % [label, value]
