class_name EquipmentTemplate
extends Resource
## 装备模板 —— 纯数据，运行时不可修改
## 参考：ai/基础装备相关.md

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var rarity: int = 0  ## EquipmentDefs.Rarity
@export var category: int = 0  ## EquipmentDefs.Category
@export var slot: int = 0  ## EquipmentDefs.Slot
@export var weapon_type: String = ""  ## 单手剑/匕首/单手弩/单手斧/盾牌/双手剑等
@export var armor_class: int = -1  ## EquipmentDefs.ArmorClass
@export var tags: Array[String] = []

## 三个核心词条
@export var base_affix: AffixData = null
@export var devour_affix: AffixData = null
@export var fusion_affix: AffixData = null

##  visuals
@export var icon_path: String = ""
@export var scene_path: String = ""


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
