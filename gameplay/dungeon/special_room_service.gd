class_name SpecialRoomService
extends RefCounted
## 特殊房交互服务：商店、泉水和事件房规则。

## 使用泉水治疗玩家属性，并返回实际治疗量。
## amount <= 0 表示按配置全额（上限 max_hp）。
## claimed 为单次性共享标记 {"value": bool}：已用过则拒绝，治疗成功才置位。
## 满血时返回 healed=0 且不置 claimed（玩家没消耗掉这次机会，可稍后回来用）。
func use_healing_spring(attributes, amount: float = -1.0, claimed: Dictionary = {}) -> Dictionary:
	if not claimed.is_empty() and bool(claimed.get("value", false)):
		return {"ok": false, "reason": "此处已使用过", "healed": 0.0}
	if attributes == null:
		return {"ok": false, "reason": "属性不可用", "healed": 0.0}
	var heal_amount: float = amount if amount > 0.0 else float(attributes.max_hp)
	var healed := float(attributes.heal(heal_amount))
	if healed <= 0.0:
		return {"ok": true, "healed": 0.0, "reason": "生命值已满"}
	if not claimed.is_empty():
		claimed["value"] = true
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
## claimed 为单次性共享标记 {"value": bool}：与 state 二选一（UI 路径用 claimed
## 落盘到房间状态，legacy 路径仍用 state），两者都检查。
func claim_event_reward(state: Dictionary, reward: int, claimed: Dictionary = {}) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "事件状态不可用"}
	if bool(state.get("claimed", false)):
		return {"ok": false, "reason": "事件奖励已领取"}
	if not claimed.is_empty() and bool(claimed.get("value", false)):
		return {"ok": false, "reason": "事件奖励已领取"}
	state["claimed"] = true
	state["reward"] = reward
	if not claimed.is_empty():
		claimed["value"] = true
	return {"ok": true, "reward": reward}


## 洗牌赌徒的箱子（纯函数，用调用方传入的 rng 保证可测）。
## boxes 是配置里的奖励数组；返回打乱后的新数组——位置随机但奖励内容固定，
## 保证「3 选 1 各不同」的公平性（配置保证三种奖励互异）。
static func shuffle_gambler_boxes(boxes: Array, rng: RandomNumberGenerator) -> Array:
	var pool := boxes.duplicate()
	var out: Array = []
	while not pool.is_empty():
		var i: int = 0 if rng == null else rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


## 结算赌徒所选箱子。
## picked 是已洗牌的箱子数组，index 为玩家选择。
## 已结算（claimed）则拒绝；成功后置 claimed。
func resolve_gambler_box(picked: Array, index: int, claimed: Dictionary = {}) -> Dictionary:
	if not claimed.is_empty() and bool(claimed.get("value", false)):
		return {"ok": false, "reason": "已结算"}
	if index < 0 or index >= picked.size():
		return {"ok": false, "reason": "无效的选择"}
	if not claimed.is_empty():
		claimed["value"] = true
	var box: Dictionary = picked[index]
	return {
		"ok": true,
		"outcome": str(box.get("kind", "empty")),
		"amount": int(box.get("amount", 0)),
	}
