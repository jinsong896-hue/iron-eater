class_name EquipmentTemplate
extends Resource
## 装备模板 —— 纯数据，运行时不可修改

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity: int = 0
@export var category: int = 0
@export var slot: int = 0
@export var weapon_type: String = ""
@export var armor_class: int = -1
@export var tags: Array[String] = []

@export var base_affix: AffixData = null
@export var devour_affix: AffixData = null
@export var fusion_affix: AffixData = null

@export var icon_path: String = ""
@export var scene_path: String = ""

## 攻击元素（分册 7.1）：仅武器使用。空 = 纯物理。
## 取值 "fire"/"frost"/"static"/"earth"/"wind"/"poison"（ElementDefs）
@export var element: String = ""
## 元素亲和：该件提供的「所有元素伤害 +X%」（分册 4.x 词条），0 = 无
@export var element_affinity: float = 0.0


func _init() -> void:
	resource_name = "EquipmentTemplate"


## 稀有度颜色
func rarity_color() -> Color:
	return EquipmentDefs.RARITY_COLORS.get(rarity, Color.WHITE)


## 是否是单手武器
func is_one_handed_weapon() -> bool:
	if category != EquipmentDefs.Category.WEAPON:
		return false
	return weapon_type in EquipmentDefs.SINGLE_HAND_WEAPONS


## 是否是双手武器
func is_two_handed_weapon() -> bool:
	if category != EquipmentDefs.Category.WEAPON:
		return false
	return not is_one_handed_weapon()


## 能否装备到指定槽位
func can_equip_in(slot_id: int) -> bool:
	return slot == slot_id
