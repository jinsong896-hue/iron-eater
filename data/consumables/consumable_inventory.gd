class_name ConsumableInventory
extends RefCounted
## 局内消耗品背包：当前只实现生命药水。

const HEALTH_POTION_ID := "health_potion"
const DEFAULT_CAPACITY := 3

var capacity := DEFAULT_CAPACITY
var quantities: Dictionary = {}

## 添加指定数量的生命药水，受容量限制。
func add_health_potion(amount: int = 1) -> Dictionary:
	var current := int(quantities.get(HEALTH_POTION_ID, 0))
	if amount <= 0:
		return {"ok": false, "reason": "数量无效", "quantity": current}
	if current + amount > capacity:
		return {"ok": false, "reason": "消耗品背包已满", "quantity": current}
	quantities[HEALTH_POTION_ID] = current + amount
	return {"ok": true, "quantity": current + amount}

## 消耗一瓶生命药水并恢复玩家生命。
func use_health_potion(attributes, amount: float) -> Dictionary:
	var current := int(quantities.get(HEALTH_POTION_ID, 0))
	if current <= 0:
		return {"ok": false, "reason": "没有生命药水", "quantity": 0}
	if attributes == null:
		return {"ok": false, "reason": "属性不可用", "quantity": current}
	var healed := float(attributes.heal(amount))
	if healed <= 0.0:
		return {"ok": false, "reason": "生命值已满", "quantity": current}
	quantities[HEALTH_POTION_ID] = current - 1
	return {"ok": true, "healed": healed, "quantity": current - 1}

## 返回指定消耗品数量。
func count(item_id: String) -> int:
	return int(quantities.get(item_id, 0))
