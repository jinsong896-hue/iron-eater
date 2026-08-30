class_name EquipmentDB
extends RefCounted
## 装备数据库 —— HD-2D 重构版
## 管理所有装备模板的注册和查询

static var _templates: Dictionary = {}


## 注册模板
static func register(template: EquipmentTemplate) -> void:
	if template.id.is_empty():
		push_warning("EquipmentDB: template id is empty")
		return
	_templates[template.id] = template


## 获取模板
static func get_template(id: String) -> EquipmentTemplate:
	return _templates.get(id, null)


## 获取所有模板
static func all_templates() -> Array:
	var result: Array = []
	for key in _templates:
		result.append(_templates[key])
	return result


## 按分类筛选
static func by_category(category: int) -> Array:
	var result: Array = []
	for t in all_templates():
		if t.category == category:
			result.append(t)
	return result


## 按稀有度筛选
static func by_rarity(rarity: int) -> Array:
	var result: Array = []
	for t in all_templates():
		if t.rarity == rarity:
			result.append(t)
	return result


## 随机获取一个模板
static func random_template(rng: RandomNumberGenerator, category: int = -1, rarity: int = -1) -> EquipmentTemplate:
	var pool: Array = all_templates()
	if category >= 0:
		pool = pool.filter(func(t: EquipmentTemplate) -> bool: return t.category == category)
	if rarity >= 0:
		pool = pool.filter(func(t: EquipmentTemplate) -> bool: return t.rarity == rarity)
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]


## 根据 ID 列表批量获取
static func get_templates_by_ids(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		var t := get_template(id)
		if t != null:
			result.append(t)
	return result


## 清空数据库（测试用）
static func clear() -> void:
	_templates.clear()