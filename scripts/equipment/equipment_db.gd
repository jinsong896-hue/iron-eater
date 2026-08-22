class_name EquipmentDB
extends RefCounted
## 装备数据库：白装模板注册表（模板缓存 + 按 id 查询）
## 模板数据来源：data/equipment/white_equipment_data.gd 常量表

const WhiteData := preload("res://data/equipment/white_equipment_data.gd")
const TemplateScript := preload("res://scripts/equipment/equipment_template.gd")
const AffixScript := preload("res://scripts/equipment/affix_data.gd")

static var _cache := {}


static func ensure_built() -> void:
	if not _cache.is_empty():
		return
	for row in WhiteData.ROWS:
		_cache[row[0]] = _build_template(row)


static func _build_template(row: Array) -> EquipmentTemplate:
	var t: EquipmentTemplate = TemplateScript.new()
	t.id = row[0]
	t.display_name = row[1]
	t.category = row[2]
	t.slot_category = row[3]
	t.weapon_type = row[4]
	t.weapon_traits = row[5].duplicate()
	t.armor_class = row[6]
	t.base_affix = _make_affix("%s_base" % row[0], "%s·基础" % row[1], AffixData.Kind.BASE, row[7])
	t.devour_affix = _make_affix("%s_devour" % row[0], "%s·吞噬" % row[1], AffixData.Kind.DEVOUR, row[8])
	t.fusion_affix = _make_affix("%s_fusion" % row[0], "%s·融合" % row[1], AffixData.Kind.FUSION, row[9])
	return t


static func _make_affix(affix_id: String, name: String, kind: int, cell: Array) -> AffixData:
	var a: AffixData = AffixScript.new()
	a.id = affix_id
	a.display_name = name
	a.kind = kind
	a.stat = cell[0]
	a.operation = cell[1]
	a.value = cell[2]
	return a


static func get_template(id: String) -> EquipmentTemplate:
	ensure_built()
	return _cache.get(id)


static func all_templates() -> Array:
	ensure_built()
	var list: Array = []
	for id in _cache:
		list.append(_cache[id])
	return list
