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

## 触发型词条（名词分册第 5 章「通用词条池（装备可附加）」的 9 种触发型）。
## 与上面三条数值型词条并列：那些改面板属性，这些在**命中时按概率施加词条**
## （眩晕/破甲/致盲/缴械/范围伤害）。数量与概率档位由稀有度决定
## （见 EquipmentDB.TRIGGER_POOL_BY_RARITY），白装没有、橙装才有 2 条。
@export var trigger_affixes: Array[AffixData] = []

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
