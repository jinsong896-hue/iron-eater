extends Node
## 背包 UI 集成测试（游戏模式）：四页签 + 装备/强化/融合/吞噬全流程
## 运行：godot --headless --path E:\unity --scene res://tests/test_backpack_ui.tscn

## 私有成员访问一律经 `TestProbe`（重构搬方法时只改 probe，本文件零改动）
var probe := TestProbe.new()

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
	await _test_filter()
	await _test_multi_select()
	await _test_button_reachability()

	if failed == 0:
		print("ALL BACKPACK UI TESTS PASSED")
		get_tree().quit(0)
	else:
		print("BACKPACK UI TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 初始状态：左栏装备槽常驻、右栏背包网格、详情占位
func _test_initial_state() -> void:
	await get_tree().process_frame
	_check(probe.ui_detail_name(ui).text == "选择装备查看详情", "详情面板初始占位")
	# 装备槽常驻（左右分栏：左装备右背包，无需切页）
	_check(probe.ui_slot_grid(ui).get_child_count() == 10, "装备槽常驻 10 格")
	_check(probe.ui_grids(ui).size() > 0, "背包网格已构建")


## 装备流程：加装备 → 左键选中详情 → 穿戴
func _test_equip_flow() -> void:
	var em = GameManager.equipment_manager
	var sword = _make_item("W01")
	var helm = _make_item("A03")
	_check(em.add_item(sword), "添加铁制单手剑到背包")
	_check(em.add_item(helm), "添加铁制头盔到背包")
	await get_tree().process_frame

	# 左键第一格 → 详情显示
	probe.ui_on_item_clicked(ui, 0)
	_check(probe.ui_detail_name(ui).text == "铁制单手剑", "左键选中显示装备名", probe.ui_detail_name(ui).text)
	_check(probe.ui_detail_meta(ui).text.contains("白色"), "详情显示稀有度")
	_check(probe.ui_detail_affix(ui).text.contains("攻击力"), "详情显示词条")

	# 穿戴
	probe.ui_on_action_requested(ui, "equip", 0)
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
	# 选中刚强化的头盔并刷详情，确认面板真的把强化等级写进去了。
	# （此前这条是 `... or true` 的恒真断言，面板即使不刷新也照样绿灯。）
	probe.set_ui_selected(ui, helm)
	probe.ui_refresh_detail(ui)
	_check(probe.ui_detail_meta(ui).text.contains("强化 +1"), "详情含强化等级",
		"实际=%s" % probe.ui_detail_meta(ui).text)


## 融合流程（装备参考2 规格口径）：
##   武器 ↔ 武器 可融合；非武器 ↔ 非武器 可融合；**跨类不行**。
##
## 用户 2026-09-22 明确以规格为准，取消了原先「同槽位」的限制——
## 故「头盔吃胸甲」现在是**合法**的（两者都是非武器）。
func _test_fusion_flow() -> void:
	var em = GameManager.equipment_manager
	var helm2 = _make_item("A03")
	var robe = _make_item("A05")
	em.add_item(helm2)
	em.add_item(robe)
	await get_tree().process_frame

	# 跨类拒绝：武器 吃 护甲（A03 头盔是护甲，W01 是武器）
	GameManager.gold = 500
	var bad: Dictionary = em.fuse(_make_item("W01"), robe)
	_check(not bad.get("ok", true), "武器吃护甲被拒绝（跨类）")

	# 同类成功：护甲 吃 护甲（头盔 A03 吃胸甲 A05 —— 不同槽位但都是护甲）
	var helm3 = _make_item("A03")
	em.add_item(helm3)
	var main_item = em.get_inventory()[0]
	var good: Dictionary = em.fuse(main_item, helm3)
	_check(good.get("ok", false), "同大类融合成功（不同槽位也可）", str(good))
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


## 装备槽：已穿戴装备出现在左栏，且可点开详情
func _test_equip_page() -> void:
	await get_tree().process_frame
	# 左栏装备槽显示已穿戴武器（不再需要切页）
	var w1 := int(EquipmentDefs.Slot.WEAPON_1)
	var slot_node: BackpackItem = probe.ui_slot_grids(ui).get(w1)
	_check(slot_node != null and slot_node.has_item(), "装备槽显示已穿戴武器")
	if slot_node != null and slot_node.has_item():
		_check(slot_node.item.display_name() == "铁制单手剑",
			"槽内是铁制单手剑", slot_node.item.display_name())
		# 点装备槽 → 详情（这是"免切页"的关键路径）
		probe.ui_on_slot_clicked(ui, ui.SLOT_INDEX_BASE + w1)
		_check(probe.ui_detail_name(ui).text == "铁制单手剑", "点装备槽可看详情")
		# 角色属性已拆到独立的常驻面板（不随选中变化、不会被词条挤出视野）
		_check(probe.ui_stats(ui).text.contains("攻击力"), "常驻面板显示角色属性",
			probe.ui_stats(ui).text.substr(0, 40))
	# 卸下（走左栏按钮路径）
	probe.ui_on_slot_clicked(ui, ui.SLOT_INDEX_BASE + w1)
	probe.ui_on_btn_equip(ui)   # 已穿戴 → 按钮为"卸下"
	await get_tree().process_frame
	_check(probe.ui_btn_equip(ui).text == "穿戴", "卸下后按钮回到「穿戴」")


## 分类筛选：切到武器后，非武器格被清空
func _test_filter() -> void:
	var em = GameManager.equipment_manager
	# 背包里放一件护甲，确保有可筛掉的目标
	var armor = _make_item("A03")
	em.add_item(armor)
	await get_tree().process_frame

	probe.ui_on_filter_weapon(ui)
	await get_tree().process_frame
	var has_armor := false
	for g in probe.ui_grids(ui):
		if g.has_item():
			var t = g.item.get_template()
			if t != null and t.category != EquipmentDefs.Category.WEAPON:
				has_armor = true
	_check(not has_armor, "武器筛选后不显示非武器")

	probe.ui_on_filter_all(ui)
	await get_tree().process_frame
	var any := false
	for g in probe.ui_grids(ui):
		if g.has_item():
			any = true
	_check(any, "切回全部后有物品显示")


## 批量多选：Ctrl+左键选中多件后可一次性处理
func _test_multi_select() -> void:
	var em = GameManager.equipment_manager
	# 放三件到背包
	for i in 3:
		em.add_item(_make_item("A03"))
	await get_tree().process_frame
	probe.ui_clear_multi(ui)
	# 模拟 Ctrl+左键：直接调 _toggle_multi
	var inv: Array = em.get_inventory()
	for idx in range(mini(3, inv.size())):
		probe.ui_toggle_multi(ui, inv[idx])
	_check(probe.ui_multi(ui).size() == 3, "多选 3 件", str(probe.ui_multi(ui).size()))
	_check(probe.ui_btn_devour(ui).text.contains("3"), "吞噬按钮显示批量数量",
		probe.ui_btn_devour(ui).text)
	# 批量吞噬
	var before: int = em.get_inventory().size()
	probe.ui_on_btn_devour(ui)
	await get_tree().process_frame
	_check(em.get_inventory().size() < before, "批量吞噬后背包减少",
		"%d → %d" % [before, em.get_inventory().size()])
	_check(probe.ui_multi(ui).is_empty(), "操作后多选已清空")


## 按钮可达性 + 点击真实生效（实机问题 1：「强化/融合两个功能都无法使用」）。
##
## 管理器层逻辑早就跑通（`em.enhance`/`em.fuse` 单测覆盖），但玩家点按钮没用——
## 断在 UI 层。故这里不测业务逻辑，只测两件事：
##   ① 两页的每个按钮矩形都落在屏幕内（越界 = 被挤出视野，看得见点不到）
##   ② 走**按钮路径**（_on_btn_pick → _on_btn_enhance/_on_btn_fuse）后，
##      装备实例的强化等级/融合次数确实变化
func _test_button_reachability() -> void:
	ui.visible = true
	await get_tree().process_frame
	var view: Rect2 = ui.get_node("Root").get_global_rect()

	probe.ui_switch_page(ui, ui.Page.EQUIP)
	await get_tree().process_frame
	for n in ["BtnEquip", "BtnDevour", "BtnDrop"]:
		var b: Button = _find_button(probe.ui_equip_page(ui), n)
		_check(b != null, "装备页按钮 %s 存在" % n)
		if b != null:
			_check(b.get_global_rect().intersection(view).get_area() > 1.0,
				"装备页 %s 在屏内 %s" % [n, str(b.get_global_rect())])
	_check(probe.ui_equip_page(ui).visible and not probe.ui_craft_page(ui).visible, "默认显示装备页")

	probe.ui_switch_page(ui, ui.Page.CRAFT)
	await get_tree().process_frame
	_check(probe.ui_craft_page(ui).visible and not probe.ui_equip_page(ui).visible, "可切到强化·融合页")
	for n in ["BtnPick", "BtnEnhance", "BtnFuse"]:
		var b2: Button = _find_button(probe.ui_craft_page(ui), n)
		_check(b2 != null, "强化页按钮 %s 存在" % n)
		if b2 != null:
			_check(b2.get_global_rect().intersection(view).get_area() > 1.0,
				"强化页 %s 在屏内 %s" % [n, str(b2.get_global_rect())])

	# —— 走按钮路径：强化 ——
	var em = GameManager.equipment_manager
	GameManager.gold = 2000
	var a = _make_item("A05")
	var b = _make_item("A05")
	em.add_item(a)
	em.add_item(b)
	await get_tree().process_frame

	probe.set_ui_selected(ui, a)
	probe.ui_on_btn_pick(ui)
	_check(probe.ui_fusion_source(ui) == a, "「设为主装备」按钮生效")
	_check(not probe.ui_btn_enhance(ui).disabled, "选主装备后「强化」按钮解禁")
	var lv: int = a.enhancement_level
	probe.ui_on_btn_enhance(ui)
	_check(a.enhancement_level == lv + 1,
		"点「强化」后等级 %d → %d" % [lv, a.enhancement_level])

	# —— 走按钮路径：融合（主装备吃同类材料）——
	_check(not probe.ui_btn_fuse(ui).disabled, "选主装备后「融合」按钮解禁")
	var fc: int = a.fusion_count
	probe.set_ui_selected(ui, b)
	probe.ui_on_btn_fuse(ui)
	_check(a.fusion_count == fc + 1,
		"点「融合」后融合数 %d → %d" % [fc, a.fusion_count])


## 在子树里按名字找按钮（测试内辅助，不进生产代码）
func _find_button(root: Node, btn_name: String) -> Button:
	for n in root.find_children(btn_name, "Button", true, false):
		return n as Button
	return null


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
