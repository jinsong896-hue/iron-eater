extends Node
## 特殊房 UI 集成测试：商店/泉水/事件 三大流程 + 输入锁 + 拾取回归
## 运行：godot --headless --path E:\unity --scene res://tests/test_special_room_ui.tscn

var failed := 0
var _gold_signals := 0

@onready var ui: CanvasLayer = $SpecialRoomUI


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("SPECIAL ROOM UI TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame

	GameManager.start_new_run({"character": "warrior", "mode": "dungeon", "difficulty": "normal", "floor": 1, "seed": 7})
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.gold_changed.connect(func(_g): _gold_signals += 1)

	await get_tree().process_frame
	await _test_shop()
	await _test_shop_equipment()
	await _test_heal()
	await _test_memory_shard()
	await _test_gambler()
	await _test_reentry_no_duplicate()
	await _test_panel_choices()
	await _test_modal_lock()
	await _test_pickup_not_blocked()

	if failed == 0:
		print("ALL SPECIAL ROOM UI TESTS PASSED")
		get_tree().quit(0)
	else:
		print("SPECIAL ROOM UI TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 构造一个特殊房控制器（不进场景树，直接测业务）
func _make_controller(kind: String, interaction: Dictionary):
	var RC = load("res://gameplay/dungeon/room_controller.gd")
	var ctrl = RC.new()
	ctrl.name = "RoomController"
	ctrl.set("room_data", {
		"room_id": "test_" + kind,
		"room_type": kind,
		"interaction": interaction,
	})
	add_child(ctrl)
	ctrl._special_service = load("res://gameplay/dungeon/special_room_service.gd").new()
	return ctrl


## ---------- 商店装备货架：买入 / 售罄 / 落盘 / 满包不吞钱 ----------
## 策划 总册 5.1「商店也出售装备」。这组测的是控制器侧的真实成交路径
## （服务层的定价与货架生成由 test_framework 的 ShopConsumption 覆盖）。
func _test_shop_equipment() -> void:
	var fake := $FakeGameRoot
	fake.seed_rooms(3)
	fake.current_room_index = 1

	var ctrl = _make_controller("shop", {"price": 25, "heal": 80})
	GameManager.gold = 99999
	# get_inventory() 返回副本，清它无效——直接清内部数组重置背包
	var inv: Array = GameManager.equipment_manager._inventory
	inv.clear()

	var stock: Array = ctrl.get_shop_stock()
	_check(stock.size() > 0, "商店摆出货架")
	var first: Dictionary = stock[0]
	var price := int(first.get("price", 0))
	var gold_before: int = GameManager.gold

	var r1: Dictionary = ctrl.purchase_equipment(0)
	_check(r1.get("ok", false), "购买第 1 件装备成功", [r1])
	_check(GameManager.gold == gold_before - price, "按标价扣款",
		["期望 %d 实际 %d" % [gold_before - price, GameManager.gold]])
	_check(inv.size() == 1, "装备已入背包", ["%d 件" % inv.size()])
	if inv.size() > 0:
		_check(inv[0].template_id == StringName(str(first.get("id", ""))),
			"入包的正是货架上那一件", [str(inv[0].template_id)])

	# 售罄：同一件不可再买（这是「无限回购」的直接回归）
	var r2: Dictionary = ctrl.purchase_equipment(0)
	_check(not r2.get("ok", false), "已售出的装备不可重复购买", [r2])
	_check(GameManager.gold == gold_before - price, "重复购买被拒且未扣款")
	_check(ctrl.get_shop_stock()[0].get("sold", false), "售罄标记写回货架（UI 会显示已售出）")

	# 落盘：控制器实例重建后仍是售罄（不落盘则回访可无限买）
	var c2 = _make_controller("shop", {"price": 25, "heal": 80})
	_check(c2.get_shop_stock()[0].get("sold", false),
		"新实例从 room_state 读回售罄状态（不复活）")
	var r3: Dictionary = c2.purchase_equipment(0)
	_check(not r3.get("ok", false), "回访时同一件仍不可买")
	c2.queue_free()

	# 满包不吞钱：塞满背包后购买必须被拒且金币不变。
	# 用 _inventory 直接塞——add_item 自身会在满 40 件时拒绝。
	for _i in 45:
		GameManager.equipment_manager._inventory.append(EquipmentInstance.new())
	var gold_full: int = GameManager.gold
	var r4: Dictionary = ctrl.purchase_equipment(1)
	_check(not r4.get("ok", false), "背包满时购买被拒", [r4])
	_check(GameManager.gold == gold_full, "被拒后金币未变（不吞钱）",
		["期望 %d 实际 %d" % [gold_full, GameManager.gold]])

	inv.clear()
	ctrl.queue_free()


## ---------- 商店：可重复购买 + 满包不吞钱（B3 回归） ----------
func _test_shop() -> void:
	var ctrl = _make_controller("shop", {"price": 25, "heal": 80})
	GameManager.gold = 500
	GameManager.consumable_inventory.quantities.clear()
	_gold_signals = 0

	var ctx: Dictionary = ctrl.get_special_context()
	_check(ctx.get("ok", false), "商店上下文可用")
	_check(ctx.get("potions") == 0 and ctx.get("capacity") == 3, "初始 0/3",
		["%s/%s" % [ctx.get("potions"), ctx.get("capacity")]])

	# 买一次：975？不，500-25=475
	var r1: Dictionary = ctrl.purchase_health_potion()
	_check(r1.get("ok", false), "购买 1 瓶成功")
	_check(GameManager.gold == 475, "金币 500→475", [GameManager.gold])
	_check(GameManager.consumable_inventory.count("health_potion") == 1, "背包 1 瓶")
	_check(_gold_signals > 0, "购买发出 gold_changed（HUD 可刷新）")

	# 再买两次到满
	ctrl.purchase_health_potion()
	ctrl.purchase_health_potion()
	_check(GameManager.consumable_inventory.count("health_potion") == 3, "买满 3 瓶")
	var gold_before: int = GameManager.gold

	# 第 4 次：背包满 → 拒绝且金币不变（B3 核心回归）
	var r4: Dictionary = ctrl.purchase_health_potion()
	_check(not r4.get("ok", false), "背包满时第 4 次购买被拒")
	_check(GameManager.gold == gold_before, "被拒后金币未变（不吞钱）",
		["期望 %d 实际 %d" % [gold_before, GameManager.gold]])

	# 金币不足
	GameManager.consumable_inventory.quantities.clear()
	GameManager.gold = 10
	var r5: Dictionary = ctrl.purchase_health_potion()
	_check(not r5.get("ok", false), "金币不足时购买被拒")
	_check(GameManager.gold == 10, "金币不足时未扣款")

	ctrl.queue_free()


## ---------- 泉水：治疗量 + 满血不消耗 + 回访不重复（B2/B5 回归） ----------
func _test_heal() -> void:
	var ctrl = _make_controller("heal", {"amount": 9999})
	GameManager.attributes.hp = GameManager.attributes.max_hp
	GameManager.attributes.take_damage(120.0)

	var r: Dictionary = ctrl.interact_special()
	_check(r.get("ok", false), "泉水交互成功")
	_check(abs(float(r.get("healed", 0.0)) - 120.0) < 0.01, "治疗量 = 实际缺失的 120",
		[str(r.get("healed"))])
	_check(GameManager.attributes.hp == GameManager.attributes.max_hp, "治疗后满血")

	# 满血时不应消耗这次机会
	var ctrl2 = _make_controller("heal", {"amount": 9999})
	var r2: Dictionary = ctrl2.interact_special()
	_check(r2.get("healed", -1) == 0.0, "满血时治疗量为 0")
	_check(str(r2.get("reason", "")) == "生命值已满", "满血给出明确原因",
		[str(r2.get("reason"))])

	ctrl.queue_free()
	ctrl2.queue_free()


## ---------- 事件：记忆碎片（自动获得） ----------
func _test_memory_shard() -> void:
	var ctrl = _make_controller("event", {"event_type": "memory_shard", "reward": 100})
	GameManager.gold = 0
	_gold_signals = 0

	var ctx: Dictionary = ctrl.get_special_context()
	_check(str(ctx.get("event_type", "")) == "memory_shard", "识别为记忆碎片")

	var r: Dictionary = ctrl.claim_memory_shard()
	_check(r.get("ok", false), "记忆碎片领取成功")
	_check(GameManager.gold == 100, "获得 100 金币", [GameManager.gold])
	_check(_gold_signals > 0, "发出 gold_changed")

	# 二次领取被拒
	var r2: Dictionary = ctrl.claim_memory_shard()
	_check(not r2.get("ok", false), "重复领取被拒")
	_check(GameManager.gold == 100, "重复领取不发放")

	ctrl.queue_free()


## ---------- 事件：赌徒的挑战（付费 3 选 1） ----------
func _test_gambler() -> void:
	var ctrl = _make_controller("event", {
		"event_type": "gambler", "cost": 100,
		"boxes": [{"kind": "empty"}, {"kind": "gold", "amount": 200}, {"kind": "equipment"}],
	})
	GameManager.gold = 50
	GameManager.consumable_inventory.quantities.clear()
	GameManager.equipment_manager.get_inventory().clear()

	# 金币不足
	var r0: Dictionary = ctrl.start_gambler_challenge()
	_check(not r0.get("ok", false), "金币不足时无法开箱")
	_check(GameManager.gold == 50, "失败未扣款")

	# 够钱开箱
	GameManager.gold = 500
	var r1: Dictionary = ctrl.start_gambler_challenge()
	_check(r1.get("ok", false), "开箱成功")
	_check(GameManager.gold == 400, "扣费 100（500→400）", [GameManager.gold])
	_check(r1.get("boxes") == 3, "开出 3 只箱子")
	_check(not r1.has("outcome") and not r1.has("amount"), "开箱返回值不泄漏奖励内容")

	# 遍历三种奖励，逐一验证（洗牌随机，故三种全查）
	var outcomes := {}
	var gold_before: int = GameManager.gold
	for i in 3:
		var c2 = _make_controller("event", {
			"event_type": "gambler", "cost": 100,
			"boxes": [{"kind": "empty"}, {"kind": "gold", "amount": 200}, {"kind": "equipment"}],
		})
		GameManager.gold = 500
		c2.start_gambler_challenge()
		var rr: Dictionary = c2.resolve_gambler_choice(i)
		if rr.get("ok", false):
			outcomes[str(rr.get("outcome", ""))] = true
		c2.queue_free()
	_check(outcomes.size() == 3, "3 只箱子覆盖 empty/gold/equipment 三种结果",
		[str(outcomes.keys())])

	# 二次结算被拒
	var r3: Dictionary = ctrl.resolve_gambler_choice(0)
	_check(r3.get("ok", false), "首次结算成功")
	var r4: Dictionary = ctrl.resolve_gambler_choice(1)
	_check(not r4.get("ok", false), "二次结算被拒")
	ctrl.queue_free()


## ---------- 输入锁：面板打开时 Esc 不应叠加暂停菜单 ----------
func _test_modal_lock() -> void:
	var ctrl = _make_controller("shop", {"price": 25, "heal": 80})
	GameManager.gold = 500
	GameManager.consumable_inventory.quantities.clear()

	var ctx: Dictionary = ctrl.get_special_context()
	ui.open(ctx, ctrl)
	await get_tree().process_frame

	_check(ui.visible, "面板已打开")
	_check(get_tree().paused, "打开时游戏暂停")
	_check(not get_tree().get_nodes_in_group("modal_ui").is_empty(), "已登记 modal_ui 组")
	_check(SpecialRoomUI.is_modal_active(), "is_modal_active() 为真")

	ui.close()
	await get_tree().process_frame
	_check(not ui.visible, "面板已关闭")
	_check(not get_tree().paused, "关闭时恢复运行")
	_check(not SpecialRoomUI.is_modal_active(), "关闭后不再模态")

	ctrl.queue_free()


## ---------- B2 回归：回访特殊房不重复发奖 ----------
## 房间节点每次进入都重建、控制器是新实例，不落盘的话记忆碎片可无限刷金币
func _test_reentry_no_duplicate() -> void:
	var fake := $FakeGameRoot
	fake.seed_rooms(3)
	fake.current_room_index = 1

	# 第一次进入：领取
	var c1 = _make_controller("event", {"event_type": "memory_shard", "reward": 100})
	c1.set("_special_used", c1._special_was_used())
	GameManager.gold = 0
	var r1: Dictionary = c1.claim_memory_shard()
	_check(r1.get("ok", false), "首次领取成功")
	_check(GameManager.gold == 100, "首次获得 100 金币")
	_check(c1._special_was_used(), "领取状态已落盘到 room_state")
	c1.queue_free()

	# 模拟离开后重建房间（新控制器实例，同 index）
	var c2 = _make_controller("event", {"event_type": "memory_shard", "reward": 100})
	c2.set("_special_used", c2._special_was_used())
	_check(c2.get("_special_used"), "新实例从 room_state 读回已用状态（不重置）")

	GameManager.gold = 100
	var r2: Dictionary = c2.claim_memory_shard()
	_check(not r2.get("ok", false), "回访时重复领取被拒")
	_check(GameManager.gold == 100, "回访不重复发放金币（不再无限刷）",
		["期望 100 实际 %d" % GameManager.gold])
	c2.queue_free()


## ---------- UI 层：面板选项随状态变化 ----------
func _test_panel_choices() -> void:
	var ctrl = _make_controller("shop", {"price": 25, "heal": 80})
	GameManager.gold = 500
	GameManager.consumable_inventory.quantities.clear()

	ui.open(ctrl.get_special_context(), ctrl)
	await get_tree().process_frame
	var ids: Array = ui.choice_ids()
	_check(ids.has("buy_potion") and ids.has("leave"), "商店列出购买与离开", [str(ids)])
	_check(ui.status_text().contains("0/3"), "状态行显示 0/3", [ui.status_text()])
	# 装备货架（策划 总册 5.1）：每件一个 buy_equip_N 条目
	var equip_ids := ids.filter(func(x): return str(x).begins_with("buy_equip_"))
	_check(equip_ids.size() == ctrl.get_shop_stock().size(),
		"货架件数与控制器一致（%d 件）" % ctrl.get_shop_stock().size(), [str(ids)])
	ui.close()

	# 泉水：已用过时只剩离开
	var heal = _make_controller("heal", {"amount": 9999})
	heal.set("_special_used", true)
	ui.open(heal.get_special_context(), heal)
	await get_tree().process_frame
	var hids: Array = ui.choice_ids()
	_check(not hids.has("heal"), "泉水已用过时不再提供饮用选项", [str(hids)])
	_check(hids.has("leave"), "泉水已用过时仍可离开")
	ui.close()

	# 记忆碎片：已领过时只剩离开
	var mem = _make_controller("event", {"event_type": "memory_shard", "reward": 100})
	mem.set("_special_used", true)
	ui.open(mem.get_special_context(), mem)
	await get_tree().process_frame
	var mids: Array = ui.choice_ids()
	_check(not mids.has("claim"), "记忆碎片已领过时不再提供领取选项", [str(mids)])
	ui.close()

	ctrl.queue_free()
	heal.queue_free()
	mem.queue_free()


## ---------- B1 回归：普通房不应挡住拾取 ----------
func _test_pickup_not_blocked() -> void:
	var ctrl = _make_controller("normal", {})
	var special: bool = ctrl.is_special_room()
	_check(not special, "普通房 is_special_room() 为假（拾取可执行）")
	ctrl.queue_free()


func _check(c: bool, name: String, detail: Array = []) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
		for d in detail:
			print("    %s" % d)
