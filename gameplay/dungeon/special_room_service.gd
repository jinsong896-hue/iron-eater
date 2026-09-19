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


# ------------------------------------------------------------
# 商店出售装备（策划 总册 5.1「商店也出售装备、增益与折扣券」）
#
# **为什么需要这块**：升级券文案承诺「解锁紫装→红装碎片→全店 9 折」，
# 但此前商店一件装备都不卖——升到满级解锁的是一个**空集**，
# 玩家花 2,500 金买到的东西在界面上不可见。这块把承诺兑现。
# ------------------------------------------------------------

## 商店货架每层摆几件装备
const SHOP_STOCK_SIZE := 3
## 各稀有度底价（金）。索引即稀有度枚举：白/绿/蓝/紫/橙/红。
##
## **红装是例外——用碎片卖，不整件卖**：策划 4.3.2 把「红装碎片」列为
## 2,000 金一片的商店商品，且 5.1 说 9 层才解锁红装掉落。整件卖 15,000
## 会直接绕开这两条设计。碎片玩法（凑几片合成、是否跨局）策划未写，
## 故红装**不出现在货架上**，留待策划给碎片规则后再接。
const SHOP_BASE_PRICE := [150, 320, 700, 1800, 5000, 15000]


## 商店当前允许出售的最高稀有度（策划 4.3.2：升级券解锁紫装）。
## 0~1 级：白~蓝（商店保底）；2 级起：紫；红装见 SHOP_BASE_PRICE 注释。
static func shop_max_rarity(level: int) -> int:
	return EquipmentDefs.Rarity.PURPLE if level >= 2 else EquipmentDefs.Rarity.BLUE


## 商店当前**能卖**的稀有度档位（升序）。
## 货架各件独立抽档——高级档更稀见但并非唯一产出，
## 否则玩家攒了钱也升了级，回来货架上三件全是紫装，蓝装直接断供。
static func shop_rarity_tiers(level: int) -> Array:
	var top := shop_max_rarity(level)
	var out: Array = []
	var r: int = EquipmentDefs.Rarity.GREEN
	while r <= top:
		out.append(r)
		r += 1
	if out.is_empty():
		out.append(EquipmentDefs.Rarity.WHITE)
	return out


## 货架抽一件装备的稀有度。按档位位置加权：越靠前（越低档）越常见。
## 权重 = (档位数 - 位置)，即 2 档 → 2:1，3 档 → 3:2:1。
## rng 为空时取最低档（供测试与无随机源场景，结果确定可断言）。
static func roll_shop_rarity(level: int, rng: RandomNumberGenerator = null) -> int:
	var tiers := shop_rarity_tiers(level)
	if rng == null:
		return int(tiers[0])
	var total := 0
	for i in range(tiers.size()):
		total += tiers.size() - i
	var pick := rng.randi_range(0, total - 1)
	for i in range(tiers.size()):
		pick -= tiers.size() - i
		if pick < 0:
			return int(tiers[i])
	return int(tiers[tiers.size() - 1])


## 装备售价：稀有度底价 × 层数成长 × 商店折扣。
##
## 层数成长用 1 + 0.15×(层-1)：到第 9 层约 2.2 倍。商店卖的是成品，
## 价格必须跟着层数走，否则第 8 层花 1,800 买紫装等于白送。
## 折扣取整数（9 折后 1,620 → 1,458），避免金币出现小数。
static func shop_price(rarity: int, floor_num: int, shop_level: int) -> int:
	var base: int = SHOP_BASE_PRICE[clampi(rarity, 0, SHOP_BASE_PRICE.size() - 1)]
	var floor_mult := 1.0 + 0.15 * float(maxi(floor_num, 1) - 1)
	var raw := float(base) * floor_mult * shop_discount(shop_level)
	return int(round(raw))


## 货架专用随机源：由「本局种子 + 层数 + 商店等级」派生。
##
## **不能借 GameManager.rng 摆货架**——那是全局流，摆一次货架会挪动它，
## 连带改变同一局里后续所有掷骰（赌徒开箱、掉落、暴击……）。
## 实测后果：进过商店再玩赌徒事件，「三只箱子覆盖三种结果」这类
## 依赖固定流的既有断言会随机失败。派生独立流既隔离了影响，
## 又让「同一层商店货架固定」成为可复现行为。
static func shop_stock_rng(run_seed: int, floor_num: int, shop_level: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%d:%d" % [run_seed, floor_num, shop_level])
	return r


## 生成一层商店的货架。
##
## 返回 [{id, slot, rarity, price, name, affix_text}, ...]——
## **只带展示所需字段，不造 EquipmentInstance**。实例由控制器在成交时创建，
## 避免「只看不买」也在内存里堆一批临时装备实例。
##
## 各件独立抽档且**不重复**（同一次货架里不出两把同名武器）：
## 装备库每个稀有度是 36 件全量（12 武器 + 18 护甲 + 6 饰品），
## 抽重复只会让三格货架看起来像一格。
static func roll_shop_stock(floor_num: int, shop_level: int,
		rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	var used_ids := {}
	for i in range(SHOP_STOCK_SIZE):
		var rarity := roll_shop_rarity(shop_level, rng)
		var templates: Array = EquipmentDB.get_templates_by_rarity(rarity)
		if templates.is_empty():
			continue
		var t: EquipmentTemplate = null
		# 先随机抽（重复则重抽）。抽不中时**必须回退线性扫描**：
		# 无 rng 场景下随机索引恒为 0，重抽永远撞同一件，
		# 货架会只摆出 1 件（测试断言与「无随机源仍可用」都依赖这里）。
		var tries: int = 1 if rng == null else templates.size()
		for attempt in range(tries):
			var idx: int = 0 if rng == null else rng.randi_range(0, templates.size() - 1)
			var cand: EquipmentTemplate = templates[idx]
			if not used_ids.has(String(cand.id)):
				t = cand
				break
		if t == null:
			for cand in templates:
				if not used_ids.has(String(cand.id)):
					t = cand
					break
		if t == null:
			continue
		used_ids[String(t.id)] = true
		out.append({
			"id": String(t.id),
			"slot": int(t.slot),
			"rarity": rarity,
			"price": shop_price(rarity, floor_num, shop_level),
			"name": t.display_name,
			"affix_text": describe_affix(t.base_affix),
		})
	return out


## 词条一句话描述（货架与成交提示共用）。
##
## 复刻背包 UI 的写法而不复用它的 `_affix_text`：那个是 UI 私有方法，
## 且额外吃「强化等级」参数——商店卖的是未强化品，强化恒为 0。
static func describe_affix(affix: AffixData) -> String:
	if affix == null:
		return "（无词条）"
	if affix.is_trigger():
		return affix.description()
	var stat_name: String = str(AttributeSystem.STAT_NAMES.get(affix.stat, "属性"))
	if affix.operation == AffixData.Operation.PERCENT:
		return "%s %+.1f%%" % [stat_name, affix.value * 100.0]
	return "%s %+.1f" % [stat_name, affix.value]


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
