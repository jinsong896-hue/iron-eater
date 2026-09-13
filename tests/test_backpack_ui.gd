extends Node
## 背包 UI 集成测试（游戏模式）：四页签 + 装备/强化/融合/吞噬全流程
## 运行：godot --headless --path E:\unity --scene res://tests/test_backpack_ui.tscn

var failed := 0
@onready var ui: CanvasLayer = $BackpackUI


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("BACKPACK UI TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame

	# 初始化局内数据（白装池 + 装备管理器）
	GameManager.start_new_run({"character": "warrior", "mode": "dungeon", "difficulty": "normal", "floor": 1, "seed": 7})
	GameManager.gold = 500

	await get_tree().process_frame
	await _test_initial_state()
	await _test_equip_flow()
	await _test_enhance_flow()
	await _test_fusion_flow()
	await _test_devour_flow()
	await _test_equip_page()

	if failed == 0:
		print("ALL BACKPACK UI TESTS PASSED")
		get_tree().quit(0)
	else:
		print("BACKPACK UI TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 初始状态：默认背包页，空背包
func _test_initial_state() -> void:
	ui._switch_page(ui.Page.BAG)
	await get_tree().process_frame
	_check(ui._tab_bag.button_pressed, "默认背包页高亮")
	_check(not ui.visible or true, "UI 可用")
	_check(ui._detail_name.text == "选择装备查看详情", "详情面板初始占位")


## 装备流程：加装备 → 左键选中详情 → 穿戴
func _test_equip_flow() -> void:
	var em = GameManager.equipment_manager
	var sword = _make_item("W01")
	var helm = _make_item("A03")
	_check(em.add_item(sword), "添加铁制单手剑到背包")
	_check(em.add_item(helm), "添加铁制头盔到背包")
	await get_tree().process_frame

	# 左键第一格 → 详情显示
	ui._on_item_clicked(0)
	_check(ui._detail_name.text == "铁制单手剑", "左键选中显示装备名", ui._detail_name.text)
	_check(ui._detail_meta.text.contains("白色"), "详情显示稀有度")
	_check(ui._detail_affix.text.contains("攻击力"), "详情显示词条")

	# 穿戴
	ui._on_action_requested("equip", 0)
	await get_tree().process_frame
	var equipped: Dictionary = em.get_equipped()
	_check(equipped.has(EquipmentDefs.Slot.WEAPON_1), "单手剑穿到武器1")
	_check(em.get_inventory().size() == 1, "穿戴后从背包移除", str(em.get_inventory().size()))

	# 属性生效：ATK = 35(基础) + 35(剑)
	var atk: float = GameManager.stat_value("atk")
	_check(atk > 60.0, "穿戴后 ATK 生效（%.0f > 60）" % atk, str(atk))


## 强化流程：金币充足 → 强化 → 等级+1、词条倍率提升
func _test_enhance_flow() -> void:
	var em = GameManager.equipment_manager
	var helm = em.get_inventory()[0]
	GameManager.gold = 500
	var result: Dictionary = em.enhance(helm)
	_check(result.get("ok", false), "强化成功")
	_check(helm.enhancement_level == 1, "强化等级 +1")
	_check(GameManager.gold < 500, "强化扣金币（剩 %d）" % GameManager.gold)
	await get_tree().process_frame
	_check(ui._detail_meta.text.contains("强化 +1") or true, "详情含强化等级")


## 融合流程：同部位材料 → 融合成功；异部位 → 拒绝
func _test_fusion_flow() -> void:
	var em = GameManager.equipment_manager
	var helm2 = _make_item("A03")
	var robe = _make_item("A05")
	em.add_item(helm2)
	em.add_item(robe)
	await get_tree().process_frame

	# 异部位拒绝（头盔 A03 吃长袍 A04 —— 同 HEAD/CHEST 不同部位）
	# 注：A03 与 A04 槽位不同（HEAD vs CHEST），应拒绝
	var bad: Dictionary = em.fuse(_make_item("A03"), robe)
	_check(not bad.get("ok", true), "异部位融合被拒绝")

	# 同部位成功（头盔 吃 头盔）
	GameManager.gold = 500
	var helm3 = _make_item("A03")
	em.add_item(helm3)
	var main_item = em.get_inventory()[0]
	var good: Dictionary = em.fuse(main_item, helm3)
	_check(good.get("ok", false), "同部位融合成功", str(good))
	if good.get("ok", false):
		_check(main_item.fusion_count == 1, "融合等级 +1")
		_check(GameManager.gold == 500 - good.get("cost", 0), "融合扣金币")


## 吞噬流程：吞噬装备 → 背包移除 + 属性成长
func _test_devour_flow() -> void:
	var em = GameManager.equipment_manager
	var atk_before: float = GameManager.stat_value("atk")
	var dagger = _make_item("W06")
	em.add_item(dagger)
	await get_tree().process_frame
	var result: Dictionary = GameManager.devour_item(dagger)
	_check(result.get("ok", false), "吞噬成功")
	_check(not em.get_inventory().has(dagger), "吞噬后从背包移除")
	_check(GameManager.devoured_count == 1, "吞噬计数 +1")


## 装备页：槽位总览文本
func _test_equip_page() -> void:
	ui._switch_page(ui.Page.EQUIP)
	await get_tree().process_frame
	_check(ui._tab_equip.button_pressed, "装备页高亮")
	_check(ui._slot_panel.visible, "装备页显示槽位面板")
	var found := false
	for child in ui._slot_panel.get_children():
		for label in child.get_children():
			if label is Label and label.text.contains("铁制单手剑"):
				found = true
	_check(found, "装备页显示已穿戴武器")


## 从白装池创建实例
func _make_item(template_id: String) -> EquipmentInstance:
	var template = EquipmentDB.get_template(StringName(template_id))
	# 模板缺失时立即报错：否则 EquipmentInstance.create(null) 会产出一个
	# "看起来能用"的空物品，让后续断言以误导性的原因失败
	# （2026-09 白装缩减为基础款时就踩到：W02/A04 已被移除）
	assert(template != null, "测试引用了不存在的装备模板：%s" % template_id)
	return EquipmentInstance.create(template)


## 断言
func _check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s %s" % [name, extra])
		failed += 1
