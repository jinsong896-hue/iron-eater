class_name BackpackUI
extends CanvasLayer
## 背包主界面（四页：装备/背包/强化·融合/吞噬）
## 对接 GameManager.equipment_manager 的 EquipmentInstance 列表
## ESC 开关，EventBus.inventory_changed 驱动刷新
## 左键查看详情，右键功能菜单（穿戴/强化/融合/吞噬/锁定/丢弃/卸下）

const ITEM_SCENE := preload("res://ui/inventory/backpack_item.tscn")
const CAPACITY := 40  # 背包容量（8列 × 5行）
const COLUMNS := 8
## 模态面板组：打开时入组，暂停菜单据此让位（避免 Esc 叠加）
const MODAL_GROUP := "modal_ui"

enum Page { EQUIP, BAG, ENHANCE, DEVOUR }

var _grids: Array[BackpackItem] = []
var _menu: BackpackMenu
var _page: int = Page.BAG
var _selected: EquipmentInstance = null   # 详情面板当前选中
var _fusion_source: EquipmentInstance = null  # 融合流程：已选主装备待选材料

@onready var _tab_equip: Button = $SafeZone/Panel/Margin/VBox/Tabs/TabEquip
@onready var _tab_bag: Button = $SafeZone/Panel/Margin/VBox/Tabs/TabBag
@onready var _tab_enhance: Button = $SafeZone/Panel/Margin/VBox/Tabs/TabEnhance
@onready var _tab_devour: Button = $SafeZone/Panel/Margin/VBox/Tabs/TabDevour
@onready var _gold_label: Label = $SafeZone/Panel/Margin/VBox/Tabs/GoldLabel
@onready var _slot_panel: Panel = $SafeZone/Panel/Margin/VBox/Content/Left/SlotPanel
@onready var _detail_name: Label = $SafeZone/Panel/Margin/VBox/Content/Detail/DetailMargin/DetailVBox/DetailName
@onready var _detail_meta: Label = $SafeZone/Panel/Margin/VBox/Content/Detail/DetailMargin/DetailVBox/DetailMeta
@onready var _detail_affix: Label = $SafeZone/Panel/Margin/VBox/Content/Detail/DetailMargin/DetailVBox/DetailAffix
@onready var _hint: Label = $SafeZone/Panel/Margin/VBox/Hint


func _ready() -> void:
	_menu = $Menu
	_build_grid()
	var bus = _event_bus()
	if bus:
		bus.inventory_changed.connect(_refresh)
		bus.equipment_changed.connect(func(_s, _i): _refresh())
		bus.gold_changed.connect(func(_g): _refresh())
		_refresh()


## 构建背包格子网格
func _build_grid() -> void:
	var grid := $SafeZone/Panel/Margin/VBox/Content/Left/Scroll/Grid
	grid.columns = COLUMNS
	for i in range(CAPACITY):
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = i
		n.swap_requested.connect(_on_swap_requested)
		n.menu_requested.connect(_on_menu_requested)
		n.item_clicked.connect(_on_item_clicked)
		_grids.push_back(n)
		grid.add_child(n)


# ============================================================
# 页签切换
# ============================================================

## 切到装备页（10 槽位总览）
func _on_tab_equip_pressed() -> void:
	_switch_page(Page.EQUIP)


## 切到背包页
func _on_tab_bag_pressed() -> void:
	_switch_page(Page.BAG)


## 切到强化·融合页
func _on_tab_enhance_pressed() -> void:
	_switch_page(Page.ENHANCE)


## 切到吞噬页
func _on_tab_devour_pressed() -> void:
	_switch_page(Page.DEVOUR)


## 统一切页（更新页签按钮状态与提示文案）
func _switch_page(page: int) -> void:
	_page = page
	_fusion_source = null
	_tab_equip.button_pressed = page == Page.EQUIP
	_tab_bag.button_pressed = page == Page.BAG
	_tab_enhance.button_pressed = page == Page.ENHANCE
	_tab_devour.button_pressed = page == Page.DEVOUR
	match page:
		Page.EQUIP:
			_hint.text = "装备总览：右键槽位可卸下装备 · ESC 关闭"
		Page.BAG:
			_hint.text = "左键查看详情 · 右键操作 · 拖拽排序 · ESC 关闭"
		Page.ENHANCE:
			_hint.text = "强化：右键装备直接强化 · 融合：先左键选主装备，再右键同部位材料"
		Page.DEVOUR:
			_hint.text = "吞噬：右键装备吞噬获得本局永久成长 · ESC 关闭"
	_refresh()


## 从装备管理器刷新全部显示
func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_gold()
	match _page:
		Page.EQUIP:
			_refresh_equip_page()
		_:
			_refresh_bag_page()
	_refresh_detail()


## 刷新金币显示
func _refresh_gold() -> void:
	var gm = _game_manager()
	_gold_label.text = "金币 %d" % (gm.gold if gm else 0)


## 装备页：槽位总览（文本列表）
func _refresh_equip_page() -> void:
	# 装备页复用 SlotPanel 显示 10 槽位文本；背包格隐藏
	for child in _slot_panel.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	_slot_panel.add_child(box)
	var em = _equipment_manager()
	var equipped: Dictionary = em.get_equipped() if em else {}
	var defs := EquipmentDefs
	for slot in [
		defs.Slot.HEAD, defs.Slot.CHEST, defs.Slot.SHOULDERS, defs.Slot.HANDS,
		defs.Slot.LEGS, defs.Slot.FEET, defs.Slot.ACCESSORY_1, defs.Slot.ACCESSORY_2,
		defs.Slot.WEAPON_1, defs.Slot.WEAPON_2,
	]:
		var label := Label.new()
		var inst: EquipmentInstance = equipped.get(slot)
		if inst:
			label.text = "%s：%s（强化+%d · 融合%d）" % [
				defs.slot_name(slot), inst.display_name(),
				inst.enhancement_level, inst.fusion_count,
			]
			label.add_theme_color_override("font_color",
				_equipped_color(inst))
		else:
			label.text = "%s：——" % defs.slot_name(slot)
			label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
		label.add_theme_font_size_override("font_size", 15)
		box.add_child(label)
	# 隐藏背包格（装备页只看槽位）
	$SafeZone/Panel/Margin/VBox/Content/Left/Scroll.visible = false
	_slot_panel.visible = true


## 背包页：物品格
func _refresh_bag_page() -> void:
	$SafeZone/Panel/Margin/VBox/Content/Left/Scroll.visible = true
	_slot_panel.visible = false

	var inventory: Array = []
	var em = _equipment_manager()
	if em:
		inventory = em.get_inventory()
	for i in range(_grids.size()):
		if i < inventory.size():
			_grids[i].item = inventory[i]
		else:
			_grids[i].clear()


## 详情面板
func _refresh_detail() -> void:
	if _selected == null or not _selected.get_template():
		_detail_name.text = "选择装备查看详情"
		_detail_meta.text = ""
		_detail_affix.text = ""
		return
	var t := _selected.get_template()
	_detail_name.text = t.display_name
	_detail_name.add_theme_color_override("font_color", t.rarity_color())

	var meta_parts := [
		"%s · %s" % [EquipmentDefs.rarity_name(t.rarity), EquipmentDefs.category_name(t.category)],
	]
	if t.weapon_type != "":
		meta_parts.append(t.weapon_type)
	if t.armor_class >= 0:
		meta_parts.append(["轻甲", "中甲", "重甲"][t.armor_class])
	meta_parts.append("强化 +%d" % _selected.enhancement_level)
	meta_parts.append("融合 %d（%s）" % [_selected.fusion_count, _selected.fusion_tier()])
	_detail_meta.text = " · ".join(meta_parts)

	var lines := [
		"[基础词条·穿戴]", _affix_text(t.base_affix, _selected.enhancement_level),
		"",
		"[吞噬词条·本局永久]", _affix_text(t.devour_affix, 0),
		"",
		"[融合词条·作材料贡献]", _affix_text(t.fusion_affix, 0),
	]
	if _fusion_source != null and _fusion_source != _selected:
		lines.append("")
		lines.append("→ 再次右键将作为融合材料")
	_detail_affix.text = "\n".join(lines)


## 词条文本（含强化倍率显示）
func _affix_text(affix: AffixData, enhance_level: int) -> String:
	if affix == null:
		return "（无）"
	var value := affix.value
	if enhance_level > 0:
		value *= (1.0 + enhance_level * 0.05)
	var stat_name: String = AttributeSystem.STAT_NAMES.get(affix.stat, "属性")
	if affix.operation == AffixData.Operation.PERCENT:
		return "%s %+.1f%%" % [stat_name, value * 100.0]
	return "%s %+.1f" % [stat_name, value]


# ============================================================
# 交互
# ============================================================

## 左键选中：更新详情（强化页左键 = 选择融合主装备）
func _on_item_clicked(idx: int) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		_selected = null
		_refresh_detail()
		return
	_selected = _grids[idx].item
	if _page == Page.ENHANCE:
		_fusion_source = _selected
	_refresh_detail()


## 拖拽交换：交换两格物品
func _on_swap_requested(from: int, to: int) -> void:
	var em = _equipment_manager()
	if em:
		em.swap_items(from, to)


## 右键菜单弹出（按当前页定制菜单项）
func _on_menu_requested(idx: int, screen_pos: Vector2) -> void:
	if idx < 0 or idx >= _grids.size():
		return
	if not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	_selected = item
	_refresh_detail()

	match _page:
		Page.EQUIP:
			return  # 装备页无格子交互
		Page.BAG:
			_menu.show_actions(screen_pos, idx, ["equip", "enhance", "devour", "lock", "drop"])
		Page.ENHANCE:
			if _fusion_source == null:
				_menu.show_actions(screen_pos, idx, ["enhance", "fusion_source", "lock", "drop"])
			elif _fusion_source == item:
				_menu.show_actions(screen_pos, idx, ["enhance", "fusion_cancel", "lock", "drop"])
			else:
				_menu.show_actions(screen_pos, idx, ["fusion_material"])
		Page.DEVOUR:
			_menu.show_actions(screen_pos, idx, ["devour", "lock", "drop"])
	_menu.set_lock_state(item.is_locked)


## 菜单操作分发
func _on_action_requested(action: String, idx: int) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	var em = _equipment_manager()
	if em == null:
		return
	var result: Dictionary

	match action:
		"equip":
			_try_equip(item)
		"enhance":
			result = em.enhance(item)
			_notify(result, "强化 +%d（花费 %d）" % [item.enhancement_level, result.get("cost", 0)])
		"devour":
			result = _devour(item)
		"lock":
			item.is_locked = not item.is_locked
			_refresh()
		"drop":
			if item.is_locked:
				_notify({"ok": false, "reason": "已锁定，无法丢弃"}, "")
			else:
				em.remove_item(item)
				_selected = null
		"fusion_source":
			_fusion_source = item
			_notify({"ok": true}, "已选为主装备，请右键同部位材料")
			_refresh_detail()
		"fusion_cancel":
			_fusion_source = null
			_refresh_detail()
		"fusion_material":
			if _fusion_source == null:
				return
			result = em.fuse(_fusion_source, item)
			if result.get("ok", false):
				_fusion_source = null
			_notify(result, "融合成功（%s · 花费 %d）" % [
				result.get("new_tier", ""), result.get("cost", 0)])


## 尝试穿戴（按模板槽位；饰品/单手武器可选二号位）
func _try_equip(item: EquipmentInstance) -> void:
	var template := item.get_template()
	if template == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	var slot := template.slot
	# 饰品/单手武器：一号位被占时穿二号位
	var defs := EquipmentDefs
	if slot in [defs.Slot.ACCESSORY_1, defs.Slot.WEAPON_1]:
		var equipped: Dictionary = em.get_equipped()
		if equipped.has(slot) and not equipped.has(slot + 1):
			slot = slot + 1
	em.equip(slot, item)
	_notify({"ok": true}, "已装备：%s" % item.display_name())


## 吞噬（走 GameManager 计数）
func _devour(item: EquipmentInstance) -> Dictionary:
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "GameManager 不可用"}
	var result: Dictionary = gm.devour_item(item)
	_notify(result, "吞噬成功：%s" % item.display_name())
	if result.get("ok", false):
		_selected = null
	return result


## 操作结果提示
func _notify(result: Dictionary, ok_text: String) -> void:
	var bus = _event_bus()
	if bus == null:
		return
	if result.get("ok", false):
		bus.message.emit(ok_text)
	else:
		bus.message.emit(result.get("reason", "操作失败"))


## 已穿戴装备的显示颜色（稀有度色）
func _equipped_color(inst: EquipmentInstance) -> Color:
	var t := inst.get_template()
	return t.rarity_color() if t else Color.WHITE


# ============================================================
# 开关
# ============================================================

## ESC/Tab 开关
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not visible:
		_open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory") and visible:
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and visible:
		_close()
		get_viewport().set_input_as_handled()


## 打开背包（默认背包页）
## 加入 modal_ui 组：暂停菜单用 _input（早于 _unhandled_input），只认这个组。
## 不入组的话，在背包里按 Esc 会被暂停菜单抢先打开（叠在背包上面）。
func _open() -> void:
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_in_group(MODAL_GROUP):
		add_to_group(MODAL_GROUP)
	_switch_page(Page.BAG)


## 关闭背包
func _close() -> void:
	_menu.hide()
	visible = false
	remove_from_group(MODAL_GROUP)
	get_tree().paused = false


# ============================================================
# autoload 访问
# ============================================================

## 获取 GameManager autoload
func _game_manager():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 获取 EventBus autoload
func _event_bus():
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


## 获取装备管理器
func _equipment_manager():
	var gm = _game_manager()
	return gm.equipment_manager if gm else null
