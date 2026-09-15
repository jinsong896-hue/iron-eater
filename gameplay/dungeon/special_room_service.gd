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


# ============================================================
# 事件房规则（策划 总册 5.2 的 9 种）
# ============================================================
# 分工：本服务只做**纯规则**（可单测、不碰游戏对象）；
# 涉及金币/背包/装备数据库的副作用由 RoomController 施加。
# 与已有的 use_healing_spring / claim_event_reward 同口径。

## 瘟疫之泉：回满生命，但随机一项属性 -10%（本局）。
## 策划原文「生命恢复至满，但随机一项属性 -10%（本局）」——
## 高风险高回报：满血换一个永久减益。
##
## 返回 {ok, healed, cursed_stat, cursed_pct}；
## 属性减益由调用方按 cursed_stat 施加（本服务不碰属性系统）。
## 可诅咒的属性：攻击/防御/移速（不含生命——生命已回满，再减会自相矛盾）。
const PLAGUE_CURSE_STATS := ["atk", "def", "spd"]


func use_plague_spring(attributes, claimed: Dictionary = {},
		rng: RandomNumberGenerator = null) -> Dictionary:
	if not claimed.is_empty() and bool(claimed.get("value", false)):
		return {"ok": false, "reason": "此处已使用过"}
	if attributes == null:
		return {"ok": false, "reason": "属性不可用"}
	# 先回满
	var healed := float(attributes.heal(float(attributes.max_hp)))
	# 再随机诅咒一项属性
	var idx: int = 0 if rng == null else rng.randi_range(0, PLAGUE_CURSE_STATS.size() - 1)
	var stat_name: String = PLAGUE_CURSE_STATS[idx]
	if not claimed.is_empty():
		claimed["value"] = true
	return {
		"ok": true,
		"healed": healed,
		"cursed_stat": stat_name,
		"cursed_pct": -0.10,
	}


## 锻造炉：免费把 1 件装备的稀有度提升 1 级（策划：白→绿→蓝…）。
## 上限由调用方按 rarity 判断（策划写"白→绿→蓝"，即只到蓝装就够；
## 但更高稀有度封顶由 EquipmentDefs.Rarity 决定，这里只做 +1 与合法性校验）。
##
## 参数 rarity 为当前稀有度（EquipmentDefs.Rarity 枚举值）。
## 返回 {ok, new_rarity} 或 {ok:false, reason}。
func forge_upgrade(rarity: int, max_rarity: int) -> Dictionary:
	if rarity >= max_rarity:
		return {"ok": false, "reason": "已达该装备的锻造上限"}
	return {"ok": true, "new_rarity": rarity + 1}


## 古代祭坛：献祭一件装备，换同部位、稀有度高 1 级的随机装备（上限紫）。
## 策划原文「献祭一件装备，获得同部位高 1 稀有度的随机装备（最高至紫）」。
##
## 返回 {ok, want_rarity, slot} 供调用方去装备库抽同部位同稀有度的模板。
func altar_sacrifice(current_rarity: int, slot: int, purple_rarity: int) -> Dictionary:
	# 已是紫装或更高 → 无法再升（策划明写"最高至紫"）
	if current_rarity >= purple_rarity:
		return {"ok": false, "reason": "该装备已是紫色或更高，祭坛无法提升"}
	return {"ok": true, "want_rarity": current_rarity + 1, "slot": slot}


## 时空裂隙：传送到本层一个已探索房间。
## 纯选择逻辑——从已探索房列表里挑一个（排除当前房）。
## 返回 {ok, target_index} 或 {ok:false, reason}。
func rift_pick_target(explored: Array, current_index: int,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var candidates: Array = []
	for i in explored:
		if int(i) != current_index:
			candidates.append(int(i))
	if candidates.is_empty():
		return {"ok": false, "reason": "本层没有其它已探索的房间"}
	var pick: int = 0 if rng == null else rng.randi_range(0, candidates.size() - 1)
	return {"ok": true, "target_index": int(candidates[pick])}


# ============================================================
# 商店消费模块（策划 总册 4.3.2「防溢出深坑」）
# ============================================================

## 属性灌注价格：300 起，每次 +50（策划 4.3.2）。
## 已灌注次数越多越贵——这是有意为之的「金币终极黑洞」，
## 防止后期金币溢出无处可花。
const INFUSE_BASE_COST := 300
const INFUSE_COST_STEP := 50
## 每次灌注随机 +1~3 攻击 或 +3~8 生命（策划原文）
const INFUSE_ATK_RANGE := [1, 3]
const INFUSE_HP_RANGE := [3, 8]
## 单件装备附魔可叠 3 次（策划：可叠 3 次）
const ENCHANT_MAX_STACKS := 3


## 属性灌注当前价格（第 n 次灌注的价格，n 从 0 计）
static func infuse_cost(infused_count: int) -> int:
	return INFUSE_BASE_COST + INFUSE_COST_STEP * maxi(infused_count, 0)


## 执行一次属性灌注的**掷骰**（纯函数）。
## 返回 {stat, amount}；stat 为 "atk" 或 "hp"。
## 副作用（改属性/扣金币）由调用方施加。
## rng 为空时按中点返回（供测试与无随机源场景），保证不返回 0 值——
## 灌注出 0 点属性会让玩家白花钱。
static func roll_infusion(rng: RandomNumberGenerator = null) -> Dictionary:
	var use_atk: bool = true if rng == null else rng.randf() < 0.5
	if use_atk:
		var lo: int = INFUSE_ATK_RANGE[0]
		var hi: int = INFUSE_ATK_RANGE[1]
		var amt: int = int((lo + hi) / 2) if rng == null else rng.randi_range(lo, hi)
		return {"stat": "atk", "amount": amt}
	var hlo: int = INFUSE_HP_RANGE[0]
	var hhi: int = INFUSE_HP_RANGE[1]
	var hamt: int = int((hlo + hhi) / 2) if rng == null else rng.randi_range(hlo, hhi)
	return {"stat": "hp", "amount": hamt}


## 商店升级券：三级累计（500 / 800 / 1,200），解锁紫装→红装碎片→全店 9 折。
## 返回 {ok, level, cost} 或 {ok:false, reason}。
const SHOP_UPGRADE_COSTS := [500, 800, 1200]
const SHOP_MAX_LEVEL := 3


static func shop_upgrade(current_level: int) -> Dictionary:
	if current_level >= SHOP_MAX_LEVEL:
		return {"ok": false, "reason": "商店已达最高等级"}
	var cost: int = SHOP_UPGRADE_COSTS[clampi(current_level, 0, SHOP_MAX_LEVEL - 1)]
	return {"ok": true, "level": current_level + 1, "cost": cost}


## 商店等级带来的折扣（3 级解锁全店 9 折）
static func shop_discount(level: int) -> float:
	return 0.9 if level >= SHOP_MAX_LEVEL else 1.0


## 融合折扣券：下一次融合费用减半（策划 4.3.2，300 金）
const FUSION_COUPON_PRICE := 300
const FUSION_COUPON_DISCOUNT := 0.5


## 用折扣券折算融合费用
static func apply_fusion_coupon(cost: int, has_coupon: bool) -> int:
	if not has_coupon:
		return cost
	return int(ceil(float(cost) * FUSION_COUPON_DISCOUNT))


## 装备附魔费用档位（策划 4.3.2：低级 800 / 中级 2,000 / 高级 5,000）
const ENCHANT_COSTS := {"low": 800, "mid": 2000, "high": 5000}


## 附魔合法性：可叠 3 次
static func can_enchant(current_stacks: int) -> bool:
	return current_stacks < ENCHANT_MAX_STACKS


## 贷款服务：借 2,000 还 4,000（策划 4.3.2）
const LOAN_AMOUNT := 2000
const LOAN_REPAY := 4000
