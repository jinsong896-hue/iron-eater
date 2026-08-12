class_name EquipmentTemplate
extends Resource
## 装备模板（.tres）：只描述“装备是什么”，运行时数据一律放 EquipmentInstance
## 对应《ai/基础装备相关.md》——Resource 模板与运行时实例严格分离

@export var id := ""
@export var display_name := ""
@export var rarity := EquipmentDefs.Rarity.WHITE
@export var category := EquipmentDefs.Category.WEAPON
@export var slot_category := EquipmentDefs.SlotCategory.WEAPON
@export var weapon_type := EquipmentDefs.WeaponType.SWORD
@export var weapon_traits: Array = []          # 近战/远程/长杆/物理/法术/其他
@export var armor_class := EquipmentDefs.ArmorClass.LIGHT

@export var base_affix: AffixData      # 穿戴生效
@export var devour_affix: AffixData    # 吞噬生效（本局永久）
@export var fusion_affix: AffixData    # 作为融合材料时贡献给主装备

# 预留接口：角色动作/战斗系统接入后再注册执行
@export var attack_pattern_id := ""
@export var mechanic_ids: Array[String] = []
@export var skill_ids: Array[String] = []


func rarity_name() -> String:
	return EquipmentDefs.rarity_name(rarity)


## 完整分类标签（含自动的单手/双手与稀有度）
func all_tags() -> Array:
	var tags: Array = [EquipmentDefs.TAG_WHITE]
	match category:
		EquipmentDefs.Category.WEAPON:
			tags.append_array(EquipmentDefs.weapon_tags(weapon_type, weapon_traits))
		EquipmentDefs.Category.ARMOR:
			tags.append(EquipmentDefs.ARMOR_CLASS_NAMES[armor_class])
		_:
			pass  # 饰品仅稀有度
	return tags


func category_name() -> String:
	return EquipmentDefs.CATEGORY_NAMES[category]


func slot_name() -> String:
	return EquipmentDefs.SLOT_CATEGORY_NAMES[slot_category]
