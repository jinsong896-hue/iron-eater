class_name ShopController
extends Node
## 特殊房业务 —— 商店 / 泉水 / 事件房 / 赌徒 / 记忆碎片。
##
## ## 为什么独立成组件
##
## `room_controller.gd` 里这块约 **650 行**（占原文件 40%），是"特殊房里
## 发生什么"的全部规则：交互分派、9 种事件、7 个购买入口、货架管理、
## 赌徒开箱。它与房间的战斗流程（刷怪/锁门/传送门）**没有交集**——
## 拆开后改一个商店价格不必翻 1600 行的房间控制器。
##
## ## 字段归属
##
## 商业区专属字段（`_special_used` / `_special_service` / `_gambler_boxes` /
## `_shop_stock` / `_shop_stock_key`）**留在 RoomController 上**——
## `activate()` 要读 `_special_used` 决定是否恢复"已探索"状态（见其注释）。
## 故本组件按 `room.xxx` 访问，字段归属不变。
##
## 房间身份方法（`_room_type` / `_is_special_room`）同样留在 RoomController：
## 刷怪与锁门逻辑也读它们（`_room_type() == "boss"` 等），搬走会制造两份真相。

## 宿主 RoomController（构造时注入）
var room = null


## 装配：注入宿主房间控制器
func setup(owner_room) -> void:
	room = owner_room


## 执行特殊房交互（不锁门，可重复进入；奖励只结算一次）
## 返回 {ok, reason?, already_used?}，UI / 输入层据 ok 决定是否提示
func interact_special() -> Dictionary:
	if not room._is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	if room._special_used:
		return {"ok": false, "already_used": true, "reason": "这里已经探索过了"}
	var result: Dictionary
	match room._room_type():
		"heal":
			var gm = room._game_manager()
			result = room._special_service.use_healing_spring(gm.attributes if gm else null)
			# 泉水清空硫磺毒气（策划 6.7：减层方式之一是「泉水清空」）。
			# 挂在结算成功之后——没喝到水不该白清层。
			if result.get("ok", false):
				room._clear_gas_if_any()
		"shop":
			var gm_shop = room._game_manager()
			var config: Dictionary = _room_interaction()
			var state := {"gold": gm_shop.gold if gm_shop else 0}
			result = room._special_service.buy_health_potion(state, int(config.get("price", 25)), float(config.get("heal", 80.0)))
			if result.get("ok", false) and gm_shop:
				gm_shop.gold = result.gold
				if gm_shop.consumable_inventory:
					gm_shop.consumable_inventory.add_health_potion(1)
		"event":
			var config_event: Dictionary = _room_interaction()
			# 事件按 event_type 分派到各自的规则（策划 总册 5.2 共 9 种）。
			# 未识别的类型退回「直接领奖」的旧行为，保证老模板仍可用。
			result = _handle_event(str(config_event.get("event_type", "memory_shard")), config_event)
	if result.get("ok", false):
		room._special_used = true
		room._mark_special_used()
	return result


## 事件房分派（对应策划 总册 5.2 的事件池）。
## 返回统一格式 {ok, reason?, ...}，具体字段按事件类型不同。
## selected_index 供锻造炉/祭坛指定背包里的装备（旧路径不传时取 -1）。
func _handle_event(event_type: String, config: Dictionary,
		selected_index: int = -1) -> Dictionary:
	match event_type:
		"plague":
			return _event_plague(config)
		"forge":
			return _event_forge(config, selected_index)
		"altar":
			return _event_altar(config, selected_index)
		"rift":
			return _event_rift(config)
		_:
			# 记忆碎片等「自动获得」型：直接结算奖励
			return room._special_service.claim_event_reward(config, int(config.get("reward", 12)))


## 事件交互的公开入口（UI 用）。
## **不走 interact_special()**：那个是「按 E 直接结算」的旧路径，
## 无法传 selected_index——而锻造炉/祭坛必须先指定一件装备。
## 返回统一格式；成功后自动置 room._special_used 并落盘。
func interact_event(selected_index: int = -1) -> Dictionary:
	if not room._is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	if room._special_used:
		return {"ok": false, "already_used": true, "reason": "这里已经探索过了"}
	var config: Dictionary = _room_interaction()
	var result: Dictionary = _handle_event(
		str(config.get("event_type", "memory_shard")), config, selected_index)
	if result.get("ok", false):
		room._special_used = true
		room._mark_special_used()
	return result


## 瘟疫之泉：回满生命 + 随机一项属性 -10%（本局）。
func _event_plague(config: Dictionary) -> Dictionary:
	var gm = room._game_manager()
	if gm == null or gm.attributes == null:
		return {"ok": false, "reason": "状态不可用"}
	var claimed := {"value": room._special_used}
	var r: Dictionary = room._special_service.use_plague_spring(gm.attributes, claimed, gm.rng)
	if not r.get("ok", false):
		return r
	# 施加永久减益（本局）——用独立源名，避免与装备/吞噬的 modifier 混淆
	var stat_key := str(r.get("cursed_stat", "atk"))
	var stat_id: int = gm.attributes.STAT_BY_NAME.get(stat_key, 0)
	gm.attributes.add_modifier("plague_curse", stat_id, 0.0, float(r.get("cursed_pct", -0.10)))
	room._special_used = true
	room._mark_special_used()
	var bus = room._event_bus()
	if bus:
		bus.stats_changed.emit()
		bus.message.emit("瘟疫之泉：生命已恢复，但 %s 永久降低 10%%" % _stat_label(stat_key))
	return {"ok": true, "healed": r.get("healed", 0.0), "cursed_stat": stat_key}


## 锻造炉：免费把 1 件装备的稀有度 +1（策划：白→绿→蓝…）。
## 需要玩家指定装备——由 UI 传入 selected_index（背包下标）。
func _event_forge(config: Dictionary, selected_index: int = -1) -> Dictionary:
	var gm = room._game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备系统不可用"}
	var inv: Array = gm.equipment_manager.get_inventory()
	var idx := selected_index
	if idx < 0 or idx >= inv.size():
		return {"ok": false, "reason": "请先选择要锻造的装备"}
	var inst = inv[idx]
	if inst.rarity >= EquipmentDefs.Rarity.BLUE:
		return {"ok": false, "reason": "锻造炉最高只能把装备提升到蓝装"}
	var r: Dictionary = room._special_service.forge_upgrade(inst.rarity, EquipmentDefs.Rarity.BLUE)
	if not r.get("ok", false):
		return r
	inst.rarity = int(r.get("new_rarity", inst.rarity))
	room._special_used = true
	room._mark_special_used()
	_emit_bus_inventory_changed()
	return {"ok": true, "new_rarity": inst.rarity}


## 古代祭坛：献祭一件装备 → 同部位高 1 稀有度的随机装备（上限紫）。
func _event_altar(config: Dictionary, selected_index: int = -1) -> Dictionary:
	var gm = room._game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备系统不可用"}
	var inv: Array = gm.equipment_manager.get_inventory()
	var idx := selected_index
	if idx < 0 or idx >= inv.size():
		return {"ok": false, "reason": "请先选择要献祭的装备"}
	var inst = inv[idx]
	var tpl = inst.get_template()
	if tpl == null:
		return {"ok": false, "reason": "装备数据异常"}
	var r: Dictionary = room._special_service.altar_sacrifice(
		inst.rarity, int(tpl.slot), EquipmentDefs.Rarity.PURPLE)
	if not r.get("ok", false):
		return r
	# 抽同部位、目标稀有度的随机装备
	var pool: Array = EquipmentDB.get_templates_by_rarity(int(r.get("want_rarity", 1)))
	var matched: Array = []
	for t in pool:
		if int(t.slot) == int(tpl.slot):
			matched.append(t)
	if matched.is_empty():
		return {"ok": false, "reason": "没有可献祭换取的装备"}
	var picked = matched[gm.rng.randi_range(0, matched.size() - 1)]
	# 移除献祭品、加入新装备
	gm.equipment_manager.remove_item(inst)
	gm.equipment_manager.add_item(EquipmentInstance.create(picked))
	room._special_used = true
	room._mark_special_used()
	_emit_bus_inventory_changed()
	return {"ok": true, "item_name": picked.display_name}


## 时空裂隙：传送到本层一个已探索房间（重置该房间，可再刷掉落）。
func _event_rift(config: Dictionary) -> Dictionary:
	var gr = room._game_root()
	if gr == null:
		return {"ok": false, "reason": "状态不可用"}
	# 已探索房列表
	var states = gr.get("room_state")
	var explored: Array = []
	if states is Dictionary:
		for i in states:
			if states[i].get("visited", false):
				explored.append(int(i))
	var cur: int = int(gr.get("current_room_index"))
	var gm_rng = room._game_manager()
	var pick_rng: RandomNumberGenerator = gm_rng.rng if gm_rng != null and gm_rng.get("rng") != null else null
	var r: Dictionary = room._special_service.rift_pick_target(explored, cur, pick_rng)
	if not r.get("ok", false):
		return r
	var target := int(r.get("target_index", -1))
	# 重置目标房的清空状态 → 可再刷一次掉落
	if states is Dictionary and states.has(target):
		states[target]["cleared"] = false
	room._special_used = true
	room._mark_special_used()
	# 延迟一帧再传送：此刻还在交互面板里，立即切房会让 UI 悬空。
	#
	# **延迟期间房间可能已经变了**（玩家/测试在这两帧内切了房）。
	# 那时再执行就是从非预期位置把玩家拽走——实测表现为测试的特殊房遍历
	# 断言「切房后停在目标房」偶发失败（期望 N 实际 = 裂隙传送目标）。
	# 故把「发起传送时的房间索引」带过去，落地时校验。
	gr.call_deferred("_deferred_rift_transition", target, cur)
	return {"ok": true, "target_index": target}


## 时空裂隙的延迟传送落地：仅在**发起房间仍是当前房间**时执行。
## 这不是加闸而是补正确性——延迟回调本就该校验前置条件。
func _deferred_rift_transition(target_idx: int, from_idx: int) -> void:
	var gr = room._game_root()
	if gr == null:
		return
	var cur: int = int(gr.get("current_room_index"))
	if cur != from_idx:
		# 延迟期间房间已变，本次传送作废（奖励已发，不再把玩家拽走）
		return
	gr.call("_transition_to_room", target_idx)


## 属性键 → 中文名（提示文案用）
func _stat_label(key: String) -> String:
	match key:
		"atk": return "攻击力"
		"def": return "防御"
		"spd": return "移动速度"
	return key


## 发射背包变更信号（事件改动了装备时用）
func _emit_bus_inventory_changed() -> void:
	var bus = room._event_bus()
	if bus:
		bus.inventory_changed.emit()
		bus.stats_changed.emit()

## 获取特殊房配置。
func _room_interaction() -> Dictionary:
	if room.room_data is Dictionary:
		return room.room_data.get("interaction", {})
	return room.room_data.interaction


# ============================================================
# 特殊房 UI 接口（面板只展示与选择，业务校验全在这里）
# ============================================================

## 公开访问器：跨对象不要调下划线方法（player 需要据此决定是否让位给拾取）
func is_special_room() -> bool:
	return room._is_special_room()


## 供 UI 读取的只读上下文
## {ok, kind, config, gold, potions, capacity, used, event_type}
func get_special_context() -> Dictionary:
	if not room._is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	var gm = room._game_manager()
	var inv = gm.consumable_inventory if gm else null
	var config: Dictionary = _room_interaction()
	return {
		"ok": true,
		"kind": room._room_type(),
		"config": config,
		"gold": int(gm.gold) if gm else 0,
		"potions": inv.count(inv.HEALTH_POTION_ID) if inv else 0,
		"capacity": inv.capacity if inv else 0,
		"used": room._special_used,
		"event_type": str(config.get("event_type", "memory_shard")),
		"stock": get_shop_stock() if room._room_type() == "shop" else [],
	}


## 商店：购买一瓶生命药水（UI 专用，可重复购买；不置 room._special_used）
## 返回服务层原样结果 {ok, gold?, quantity?, reason?}
func purchase_health_potion() -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var inv = gm.consumable_inventory
	if inv == null:
		return {"ok": false, "reason": "消耗品背包不可用"}
	var config: Dictionary = _room_interaction()
	var price := int(config.get("price", 25))
	var heal := float(config.get("heal", 80.0))

	# state 必须从真实背包播种，否则容量检查永远看不到已装数量
	var state := {
		"gold": int(gm.gold),
		"potions": inv.count(inv.HEALTH_POTION_ID),
		"capacity": inv.capacity,
	}
	var result: Dictionary = room._special_service.buy_health_potion(state, price, heal)
	if not result.get("ok", false):
		return result

	# 服务层已扣费，这里入包；入包失败必须回滚，绝不吞钱
	var added: Dictionary = inv.add_health_potion(1)
	if not added.get("ok", false):
		return {"ok": false, "reason": added.get("reason", "消耗品背包已满")}

	gm.gold = int(result.get("gold", gm.gold))
	_emit_gold_changed()
	return result


## 商店：属性灌注（策划 4.3.2「金币终极黑洞」）。
## 无限购，价格随次数递增（300 起、每次 +50）；
## 每次随机 +1~3 攻击 或 +3~8 生命（本局永久）。
## 返回 {ok, stat, amount, cost, gold}。
func purchase_infusion() -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null or gm.attributes == null:
		return {"ok": false, "reason": "状态不可用"}
	var cost := SpecialRoomService.infuse_cost(gm.infused_count)
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}
	var roll := SpecialRoomService.roll_infusion(gm.rng)
	var stat_key := str(roll.get("stat", "atk"))
	var amount := int(roll.get("amount", 0))
	# 灌注用固定源名累加（多次灌注叠加），故不 remove 旧值
	var stat_id: int = gm.attributes.STAT_BY_NAME.get(stat_key, 0)
	gm.attributes.add_modifier("infusion", stat_id, float(amount), 0.0)
	gm.gold -= cost
	gm.infused_count += 1
	_emit_gold_changed()
	var bus = room._event_bus()
	if bus:
		bus.stats_changed.emit()
	return {"ok": true, "stat": stat_key, "amount": amount, "cost": cost,
		"gold": int(gm.gold)}


## 商店：购买融合折扣券（策划 4.3.2，300 金 → 下次融合费用减半）。
func purchase_fusion_coupon() -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	if gm.has_fusion_coupon:
		return {"ok": false, "reason": "已持有折扣券"}
	var price := SpecialRoomService.FUSION_COUPON_PRICE
	if int(gm.gold) < price:
		return {"ok": false, "reason": "金币不足（需要 %d）" % price}
	gm.gold -= price
	gm.has_fusion_coupon = true
	_emit_gold_changed()
	return {"ok": true, "cost": price, "gold": int(gm.gold)}


## 商店：购买升级券（策划 4.3.2，500/800/1200 三级）。
func purchase_shop_upgrade() -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var r := SpecialRoomService.shop_upgrade(gm.shop_level)
	if not r.get("ok", false):
		return r
	var cost := int(r.get("cost", 0))
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}
	gm.gold -= cost
	gm.shop_level = int(r.get("level", gm.shop_level + 1))
	_emit_gold_changed()
	# 升级改变可售稀有度（2 级解锁紫装）与价格（3 级 9 折），货架必须重摆。
	# 没有这行的话：升级前摆的是蓝装货架，升到 2 级后仍显示蓝装，
	# 玩家会以为升级券没生效。
	_invalidate_shop_stock()
	return {"ok": true, "level": gm.shop_level, "cost": cost, "gold": int(gm.gold)}


## 商店：附魔（策划 4.3.2，低级 800 / 中级 2,000 / 高级 5,000；单件限 3 次）。
## 把一条通用词条（名词分册第 5 章）**附加到指定装备**上。
##
## 与 purchase_infusion 的区别：灌注给玩家加固定属性、与装备无关；
## 附魔把词条挂在装备实例上，卸下/丢弃时词条一起走。
##
## slot 指定目标槽位；不传则挑**已穿戴**里附魔次数最少的一件
## （避免连续附魔都堆在同一件上白撞 3 次上限）。
func purchase_enchant(tier: String = "mid", slot: int = -1) -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "状态不可用"}
	var em = gm.equipment_manager

	var target: EquipmentInstance = null
	if slot >= 0:
		target = em.get_equipped().get(slot)
	else:
		for s in em.get_equipped().values():
			if s == null:
				continue
			if not SpecialRoomService.can_enchant(s.enchant_stacks):
				continue
			if target == null or s.enchant_stacks < target.enchant_stacks:
				target = s
	if target == null:
		return {"ok": false, "reason": "没有可附魔的已穿戴装备（需先穿戴，且未达 3 次上限）"}

	var r: Dictionary = em.enchant(target, tier)
	if not r.get("ok", false):
		return r
	_emit_gold_changed()
	var bus = room._event_bus()
	if bus:
		bus.stats_changed.emit()
		bus.message.emit("附魔成功：%s → %s" % [target.display_name(), str(r.get("text", ""))])
	return {"ok": true, "tier": tier, "cost": int(r.get("cost", 0)),
		"text": str(r.get("text", "")), "item": target.display_name(),
		"gold": int(gm.gold)}


# ============================================================
# 商店：出售装备（策划 总册 5.1 / 4.3.2）
#
# 货架是**按房间 + 按层缓存**的：随机结果若每次重建都重掷，
# 关闭面板再打开就会换一批货（同一层商店前后看到的不是同一家店）。
# 缓存键取「层数 + 商店等级」——升级券会改变可售稀有度与折扣价，
# 故升级后必须失效重摆，见 _invalidate_shop_stock()。
# ============================================================



## 当前货架（首次访问时按本层与商店等级生成）
## 返回 [{id, slot, rarity, price, name, affix_text, sold}, ...]
func get_shop_stock() -> Array:
	var gm = room._game_manager()
	if gm == null:
		return []
	var floor_num := int(gm.run_info.get("floor", 1))
	var key := "%d:%d" % [floor_num, int(gm.shop_level)]
	if room._shop_stock == null or room._shop_stock_key != key:
		# 用派生独立流，不借 gm.rng——理由见 SpecialRoomService.shop_stock_rng
		var seed_val := int(gm.run_info.get("seed", 0))
		var stock_rng := SpecialRoomService.shop_stock_rng(seed_val, floor_num, int(gm.shop_level))
		room._shop_stock = SpecialRoomService.roll_shop_stock(floor_num, int(gm.shop_level), stock_rng)
		room._shop_stock_key = key
		# sold 标记存在 room_state 里（控制器实例随房间重建而新建，
		# 存成员变量的话回访商店会「已售出的装备复活」，可无限购买）
		var sold := _shop_sold_ids()
		for row in room._shop_stock:
			row["sold"] = sold.has(str(row.get("id", "")))
	return room._shop_stock


## 让货架失效（下次 get_shop_stock 重掷）
func _invalidate_shop_stock() -> void:
	room._shop_stock = null
	room._shop_stock_key = ""


## 本店已售出的装备 id 集合（落在 room_state 的数组里）
func _shop_sold_ids() -> Array:
	var gr = room._game_root()
	if gr == null:
		return []
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return []
	var idx: int = int(gr.get("current_room_index"))
	if not states.has(idx):
		return []
	return states[idx].get("shop_sold", [])


## 记一件装备已售出（落盘，供回访时恢复）
func _mark_shop_sold(item_id: String) -> void:
	var gr = room._game_root()
	if gr == null:
		return
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return
	var idx: int = int(gr.get("current_room_index"))
	if not states.has(idx):
		return
	var sold: Array = states[idx].get("shop_sold", [])
	if not sold.has(item_id):
		sold.append(item_id)
	states[idx]["shop_sold"] = sold


## 商店：购买货架上第 index 件装备。
##
## 返回 {ok, name, rarity, price, gold} 或 {ok:false, reason}。
##
## **先扣钱还是先入包**：服务层的 buy_shop_item 负责校验与扣钱，但装备实例
## 在本函数里创建。若创建失败（模板缺失）而钱已扣，玩家就白花了——
## 故这里**先建实例、再扣钱**，扣钱后入包失败则原路退款。
## 与 purchase_health_potion 的「服务层先扣、入包失败回滚」是同一套思路，
## 只是顺序反过来：那边实例（药水）不需要构造，这边需要。
func purchase_equipment(index: int) -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "状态不可用"}
	var stock := get_shop_stock()
	if index < 0 or index >= stock.size():
		return {"ok": false, "reason": "货架上没有这一件"}
	var row: Dictionary = stock[index]
	if bool(row.get("sold", false)):
		return {"ok": false, "reason": "这件已经卖出去了"}
	var price := int(row.get("price", 0))
	var item_id := str(row.get("id", ""))

	var template: EquipmentTemplate = EquipmentDB.get_template(StringName(item_id))
	if template == null:
		return {"ok": false, "reason": "装备模板缺失（%s）" % item_id}

	var state := {"gold": int(gm.gold), "purchased": false}
	var result: Dictionary = room._special_service.buy_shop_item(state, price)
	if not result.get("ok", false):
		return result

	var inst := EquipmentInstance.create(template)
	var em = gm.equipment_manager
	if not em.add_item(inst):
		return {"ok": false, "reason": "背包已满（%d 格）" % em.get_capacity()}

	gm.gold = int(result.get("gold", gm.gold))
	_mark_shop_sold(item_id)
	row["sold"] = true
	_emit_gold_changed()
	var bus = room._event_bus()
	if bus:
		bus.inventory_changed.emit()
	return {"ok": true, "name": str(row.get("name", "")), "rarity": int(row.get("rarity", 0)),
		"price": price, "gold": int(gm.gold)}


## 商店：贷款（策划 4.3.2，借 2000 还 4000，结算时扣）。
func purchase_loan() -> Dictionary:
	if room._room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	gm.gold += SpecialRoomService.LOAN_AMOUNT
	gm.loan_debt += SpecialRoomService.LOAN_REPAY
	_emit_gold_changed()
	return {"ok": true, "amount": SpecialRoomService.LOAN_AMOUNT,
		"debt": gm.loan_debt, "gold": int(gm.gold)}


## 事件：记忆碎片——直接发放（无选择）
## 返回 {ok, reward?, reason?}
func claim_memory_shard() -> Dictionary:
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var config: Dictionary = _room_interaction()
	var reward := int(config.get("reward", 100))
	var claimed := {"value": room._special_used}
	var result: Dictionary = room._special_service.claim_event_reward({}, reward, claimed)
	if not result.get("ok", false):
		return result
	gm.gold += int(result.get("reward", reward))
	room._special_used = true
	room._mark_special_used()
	_emit_gold_changed()
	var bus = room._event_bus()
	if bus:
		bus.stats_changed.emit()
	return result


## 事件：赌徒的挑战——第一阶段，付费开箱
## 扣费并洗出 3 个箱子；返回值**不含奖励内容**（防 UI 提前泄漏答案）
## 返回 {ok, phase, cost, boxes: int, gold} / {ok:false, reason}
func start_gambler_challenge() -> Dictionary:
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	if room._special_used:
		return {"ok": false, "reason": "已结算"}
	var config: Dictionary = _room_interaction()
	var cost := int(config.get("cost", 100))
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足", "gold": int(gm.gold)}
	gm.gold -= cost
	room._gambler_boxes = room._special_service.shuffle_gambler_boxes(
		config.get("boxes", []), gm.rng if gm else null
	)
	_emit_gold_changed()
	return {
		"ok": true, "phase": "choose", "cost": cost,
		"boxes": room._gambler_boxes.size(), "gold": int(gm.gold),
	}


## 事件：赌徒的挑战——第二阶段，结算所选箱子
## 返回 {ok, outcome: "empty"|"gold"|"equipment", amount?, item_name?, reason?}
func resolve_gambler_choice(index: int) -> Dictionary:
	if room._gambler_boxes.is_empty():
		return {"ok": false, "reason": "尚未开始挑战"}
	var gm = room._game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var claimed := {"value": room._special_used}
	var result: Dictionary = room._special_service.resolve_gambler_box(room._gambler_boxes, index, claimed)
	if not result.get("ok", false):
		return result

	room._special_used = true
	room._mark_special_used()
	var bus = room._event_bus()

	match str(result.get("outcome", "empty")):
		"gold":
			gm.gold += int(result.get("amount", 0))
			_emit_gold_changed()
			if bus:
				bus.stats_changed.emit()
		"equipment":
			var granted: Dictionary = _grant_random_equipment()
			if not granted.get("ok", false):
				# 背包装不下：退还开箱费，不让玩家白花钱
				var cost := int(_room_interaction().get("cost", 100))
				gm.gold += cost
				_emit_gold_changed()
				return {"ok": false, "reason": granted.get("reason", "装备背包已满")}
			result["item_name"] = granted.get("item_name", "")
	return result


## 随机发一件白装进装备背包（赌徒奖励用）
## 不走 LootSystem——它只生成地面掉落物，而这里是直接入包
func _grant_random_equipment() -> Dictionary:
	var gm = room._game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备背包不可用"}
	var pool: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if pool.is_empty():
		return {"ok": false, "reason": "无可用装备"}
	var tpl = pool[gm.rng.randi_range(0, pool.size() - 1)]
	var item = EquipmentInstance.create(tpl)
	if not gm.equipment_manager.add_item(item):
		return {"ok": false, "reason": "装备背包已满"}
	var bus = room._event_bus()
	if bus:
		bus.inventory_changed.emit()
		bus.item_picked_up.emit(str(item.instance_id), item.display_name())
	return {"ok": true, "item_name": item.display_name()}


## 发金币变更信号（商店/事件结算后刷新 HUD）
func _emit_gold_changed() -> void:
	var gm = room._game_manager()
	var bus = room._event_bus()
	if bus and gm:
		bus.gold_changed.emit(int(gm.gold))

