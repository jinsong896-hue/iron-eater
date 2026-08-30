class_name EquipmentDB
extends RefCounted
## 装备模板数据库

static var _templates: Dictionary = {}  ## id -> EquipmentTemplate
static var _initialized: bool = false


## 注册模板
static func register(template: EquipmentTemplate) -> void:
	if template == null:
		return
	_templates[template.id] = template


## 获取模板
static func get_template(id: StringName) -> EquipmentTemplate:
	return _templates.get(id)


## 创建并注册模板
static func create_template(id: StringName, display_name: String, rarity: int, category: int, slot: int) -> EquipmentTemplate:
	var t := EquipmentTemplate.new()
	t.id = id
	t.display_name = display_name
	t.rarity = rarity
	t.category = category
	t.slot = slot
	register(t)
	return t


## 按稀有度获取所有模板
static func get_templates_by_rarity(rarity: int) -> Array:
	var result: Array = []
	for t in _templates.values():
		if t.rarity == rarity:
			result.append(t)
	return result


## 按槽位分类
static func get_templates_by_slot(slot: int) -> Array:
	var result: Array = []
	for t in _templates.values():
		if t.slot == slot:
			result.append(t)
	return result


## 初始化白装数据（最小可用版本）
static func init_white_equipment() -> void:
	if _initialized:
		return
	_initialized = true

	# 武器
	var w1 := create_template(&"white_sword", "铁制单手剑", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.WEAPON, EquipmentDefs.Slot.WEAPON_1)
	w1.weapon_type = "sword"
	w1.base_affix = AffixData.new(AttributeSystem.Stat.ATK, 35.0)
	w1.devour_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.5)
	w1.fusion_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.03, AffixData.Operation.PERCENT)

	var w2 := create_template(&"white_dagger", "短匕首", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.WEAPON, EquipmentDefs.Slot.WEAPON_1)
	w2.weapon_type = "dagger"
	w2.base_affix = AffixData.new(AttributeSystem.Stat.ATK, 26.0)
	w2.devour_affix = AffixData.new(AttributeSystem.Stat.ASPD, 0.002)
	w2.fusion_affix = AffixData.new(AttributeSystem.Stat.ASPD, 0.03, AffixData.Operation.PERCENT)

	var w3 := create_template(&"white_shield", "铁制圆盾", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.WEAPON, EquipmentDefs.Slot.WEAPON_1)
	w3.weapon_type = "shield"
	w3.base_affix = AffixData.new(AttributeSystem.Stat.DEF, 12.0)
	w3.devour_affix = AffixData.new(AttributeSystem.Stat.DEF, 0.5)
	w3.fusion_affix = AffixData.new(AttributeSystem.Stat.DEF, 0.04, AffixData.Operation.PERCENT)

	var w4 := create_template(&"white_greatsword", "铁制巨剑", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.WEAPON, EquipmentDefs.Slot.WEAPON_1)
	w4.weapon_type = "greatsword"
	w4.base_affix = AffixData.new(AttributeSystem.Stat.ATK, 56.0)
	w4.devour_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.7)
	w4.fusion_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.04, AffixData.Operation.PERCENT)

	# 护甲
	var a1 := create_template(&"white_helm", "铁制头盔", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.ARMOR, EquipmentDefs.Slot.HEAD)
	a1.armor_class = EquipmentDefs.ArmorClass.HEAVY
	a1.base_affix = AffixData.new(AttributeSystem.Stat.DEF, 6.0)
	a1.devour_affix = AffixData.new(AttributeSystem.Stat.DEF, 0.3)
	a1.fusion_affix = AffixData.new(AttributeSystem.Stat.DEF, 0.03, AffixData.Operation.PERCENT)

	var a2 := create_template(&"white_chest", "铁制胸甲", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.ARMOR, EquipmentDefs.Slot.CHEST)
	a2.armor_class = EquipmentDefs.ArmorClass.HEAVY
	a2.base_affix = AffixData.new(AttributeSystem.Stat.HP, 40.0)
	a2.devour_affix = AffixData.new(AttributeSystem.Stat.HP, 2.0)
	a2.fusion_affix = AffixData.new(AttributeSystem.Stat.HP, 0.04, AffixData.Operation.PERCENT)

	# 饰品
	var j1 := create_template(&"white_ring", "铁戒指", EquipmentDefs.Rarity.WHITE, EquipmentDefs.Category.ACCESSORY, EquipmentDefs.Slot.ACCESSORY_1)
	j1.base_affix = AffixData.new(AttributeSystem.Stat.ATK, 4.0)
	j1.devour_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.3)
	j1.fusion_affix = AffixData.new(AttributeSystem.Stat.ATK, 0.03, AffixData.Operation.PERCENT)
