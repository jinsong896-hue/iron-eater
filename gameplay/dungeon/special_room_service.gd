class_name SpecialRoomService
extends RefCounted
## 特殊房交互服务：商店、泉水和事件房规则。

## 使用泉水治疗玩家属性，并返回实际治疗量。
func use_healing_spring(attributes) -> Dictionary:
	if attributes == null:
		return {"ok": false, "reason": "属性不可用", "healed": 0.0}
	var healed := float(attributes.heal(attributes.max_hp))
	return {"ok": true, "healed": healed}

## 从商店状态购买一件商品。
func buy_shop_item(state: Dictionary, price: int) -> Dictionary:
	if state == null or price < 0:
		return {"ok": false, "reason": "商品不可购买"}
	if bool(state.get("purchased", false)):
		return {"ok": false, "reason": "商品已售出"}
	var gold := int(state.get("gold", 0))
	if gold < price:
		return {"ok": false, "reason": "金币不足", "gold": gold}
	state["gold"] = gold - price
	state["purchased"] = true
	return {"ok": true, "gold": state["gold"]}

## 购买生命药水并放入消耗品背包。
func buy_health_potion(state: Dictionary, price: int, heal_amount: float) -> Dictionary:
	if state == null or price < 0 or heal_amount <= 0.0:
		return {"ok": false, "reason": "商品不可购买"}
	var gold := int(state.get("gold", 0))
	var quantity := int(state.get("potions", 0))
	var capacity := int(state.get("capacity", 3))
	if quantity >= capacity:
		return {"ok": false, "reason": "消耗品背包已满", "quantity": quantity}
	if gold < price:
		return {"ok": false, "reason": "金币不足", "gold": gold}
	state["gold"] = gold - price
	state["potions"] = quantity + 1
	state["potion_heal"] = heal_amount
	return {"ok": true, "gold": state["gold"], "quantity": state["potions"]}

## 使用一瓶生命药水并返回实际治疗量。
func use_health_potion(state: Dictionary, attributes) -> Dictionary:
	if state == null or int(state.get("potions", 0)) <= 0:
		return {"ok": false, "reason": "没有生命药水"}
	if attributes == null:
		return {"ok": false, "reason": "属性不可用"}
	var healed := float(attributes.heal(float(state.get("potion_heal", 80.0))))
	if healed <= 0.0:
		return {"ok": false, "reason": "生命值已满"}
	state["potions"] = int(state.get("potions", 0)) - 1
	return {"ok": true, "healed": healed, "quantity": state["potions"]}

## 领取事件奖励；每个事件状态只能领取一次。
func claim_event_reward(state: Dictionary, reward: int) -> Dictionary:
	if state == null or bool(state.get("claimed", false)):
		return {"ok": false, "reason": "事件奖励已领取"}
	state["claimed"] = true
	state["reward"] = reward
	return {"ok": true, "reward": reward}
