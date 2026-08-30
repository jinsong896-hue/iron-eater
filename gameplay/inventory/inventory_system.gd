class_name InventorySystem
extends RefCounted
## 背包系统 —— HD-2D 重构版
## 管理背包容量、物品排序、快速操作

var max_size := 20
var _items: Array[EquipmentInstance] = []


## 添加物品
func add_item(item: EquipmentInstance) -> bool:
	if _items.size() >= max_size:
		return false
	_items.append(item)
	EventBus.inventory_changed.emit()
	return true


## 移除物品
func remove_item(item: EquipmentInstance) -> bool:
	var removed := _items.has(item)
	if removed:
		_items.erase(item)
		EventBus.inventory_changed.emit()
	return removed


## 按索引获取
func get_item(index: int) -> EquipmentInstance:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


## 获取所有物品
func get_all() -> Array:
	return _items.duplicate()


## 按稀有度排序
func sort_by_rarity() -> void:
	_items.sort_custom(func(a: EquipmentInstance, b: EquipmentInstance) -> bool:
		return a.rarity > b.rarity
	)


## 按分类筛选
func filter_by_category(category: int) -> Array:
	return _items.filter(func(item: EquipmentInstance) -> bool:
		var t := item.get_template()
		return t != null and t.category == category
	)


## 获取物品数量
func size() -> int:
	return _items.size()


## 是否已满
func is_full() -> bool:
	return _items.size() >= max_size


## 清空
func clear() -> void:
	_items.clear()
	EventBus.inventory_changed.emit()