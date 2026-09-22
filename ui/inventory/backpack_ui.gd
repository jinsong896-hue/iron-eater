class_name BackpackUI
extends CanvasLayer
## 背包主界面 —— 双页签（装备 / 强化·融合）
##
## ## 为什么是双页签而不是全都堆在一屏
## 上一版把「装备槽 + 详情 + 属性 + 操作按钮 + 吞噬汇总 + 背包网格」全塞进
## 左右分栏。720p 窗口装不下：按钮被挤出可视区、内容溢出到屏幕外，
## 玩家报告「强化/融合按钮点了没反应」——实际是**根本看不到按钮**。
## 现在按用途分成两页，每页只留该做的事：
##
##   装备页  左=装备槽（可拖入） / 中=背包网格（可多选） / 右=选中详情+角色属性
##   强化页  左=主装备 + 融合材料 / 中=材料候选 / 右=词条预览
##
## ## 三个交互
##  拖拽      背包格拖到装备槽 → 直接穿戴（暗黑式）。用 Godot 的
##            Control._get_drag_data/_drop_data 实现。
##  多选      Ctrl+左键切换选中；批量吞噬/融合一次处理多件。
##  右键      保留原有菜单（单件操作）。

const ITEM_SCENE := preload("res://ui/inventory/backpack_item.tscn")
const DEFAULT_CAPACITY := 40
const COLUMNS := 8
const MODAL_GROUP := "modal_ui"

## 装备槽的 index 基准（与背包格 0..capacity-1 区分）
const SLOT_INDEX_BASE := 1000

enum Page { EQUIP, CRAFT }
enum Filter { ALL, WEAPON, ARMOR, ACCESSORY }

const SLOT_ORDER := [
	EquipmentDefs.Slot.HEAD, EquipmentDefs.Slot.CHEST, EquipmentDefs.Slot.SHOULDERS,
	EquipmentDefs.Slot.HANDS, EquipmentDefs.Slot.LEGS, EquipmentDefs.Slot.FEET,
	EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Slot.ACCESSORY_2,
	EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Slot.WEAPON_2,
]

var _grids: Array[BackpackItem] = []
var _slot_grids: Dictionary = {}          # slot_id -> BackpackItem
var _menu: BackpackMenu
var _page: int = Page.EQUIP
var _selected: EquipmentInstance = null   # 详情面板当前选中
var _fusion_source: EquipmentInstance = null  # 融合主装备
var _filter: int = Filter.ALL
## 批量选中集合（instance -> true）。用实例做键而不是格子下标——
## 拖拽/排序会改下标，实例身份才稳定。
var _multi: Dictionary = {}

# —— 装备页 ——
@onready var _gold_label: Label = $Root/Panel/Margin/VBox/Header/GoldLabel
@onready var _hint: Label = $Root/Panel/Margin/VBox/Hint
@onready var _slot_grid: GridContainer = $Root/Panel/Margin/VBox/Pages/EquipPage/Left/SlotPanel/SlotMargin/SlotGrid
@onready var _stats: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Left/StatPanel/StatMargin/Stats
@onready var _detail_name: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Right/DetailMargin/DetailScroll/DetailVBox/DetailName
@onready var _detail_meta: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Right/DetailMargin/DetailScroll/DetailVBox/DetailMeta
@onready var _detail_affix: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Right/DetailMargin/DetailScroll/DetailVBox/DetailAffix
@onready var _filter_label: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/FilterLabel
@onready var _btn_equip: Button = $Root/Panel/Margin/VBox/Pages/EquipPage/Left/Actions/BtnEquip
@onready var _btn_devour: Button = $Root/Panel/Margin/VBox/Pages/EquipPage/Left/Actions/BtnDevour
@onready var _btn_drop: Button = $Root/Panel/Margin/VBox/Pages/EquipPage/Left/Actions/BtnDrop
@onready var _multi_label: Label = $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/MultiLabel
@onready var _equip_page: Control = $Root/Panel/Margin/VBox/Pages/EquipPage
@onready var _craft_page: Control = $Root/Panel/Margin/VBox/Pages/CraftPage

# —— 强化页 ——
@onready var _craft_main_name: Label = $Root/Panel/Margin/VBox/Pages/CraftPage/Main/MainMargin/V/Name
@onready var _craft_main_info: Label = $Root/Panel/Margin/VBox/Pages/CraftPage/Main/MainMargin/V/Info
@onready var _craft_mat_name: Label = $Root/Panel/Margin/VBox/Pages/CraftPage/Mat/MatMargin/V/Name
@onready var _craft_hint: Label = $Root/Panel/Margin/VBox/Pages/CraftPage/Hint
@onready var _btn_enhance: Button = $Root/Panel/Margin/VBox/Pages/CraftPage/Actions/BtnEnhance
@onready var _btn_fuse: Button = $Root/Panel/Margin/VBox/Pages/CraftPage/Actions/BtnFuse
@onready var _btn_craft_pick: Button = $Root/Panel/Margin/VBox/Pages/CraftPage/Actions/BtnPick
@onready var _tab_equip: Button = $Root/Panel/Margin/VBox/Tabs/TabEquip
@onready var _tab_craft: Button = $Root/Panel/Margin/VBox/Tabs/TabCraft


func _ready() -> void:
	_menu = $Menu
	_build_bag_grid()
	_build_slot_grid()
	var bus = _event_bus()
	if bus:
		bus.inventory_changed.connect(_refresh)
		bus.equipment_changed.connect(func(_s, _i): _refresh())
		bus.gold_changed.connect(func(_g): _refresh())
	_switch_page(Page.EQUIP)


## 构建背包格子网格
func _build_bag_grid() -> void:
	var grid := $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Scroll/Grid
	grid.columns = COLUMNS
	for i in range(_capacity()):
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = i
		n.swap_requested.connect(_on_swap_requested)
		n.menu_requested.connect(_on_menu_requested)
		n.item_clicked.connect(_on_item_clicked)
		_grids.push_back(n)
		grid.add_child(n)


## 构建装备槽（10 格）。每格也是 BackpackItem，index 用 SLOT_INDEX_BASE 区间
func _build_slot_grid() -> void:
	for slot_id in SLOT_ORDER:
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = SLOT_INDEX_BASE + int(slot_id)
		n.menu_requested.connect(_on_slot_menu_requested)
		n.item_clicked.connect(_on_slot_clicked)
		# 暗黑式拖拽：背包物品拖到槽位即穿戴
		n.equip_drop_requested.connect(_on_equip_drop)
		_slot_grids[int(slot_id)] = n
		_slot_grid.add_child(n)


## 拖到装备槽 → 直接穿到该槽位（暗黑式）
func _on_equip_drop(inst: EquipmentInstance, slot_id: int) -> void:
	if inst == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	em.equip(slot_id, inst)
	_notify({"ok": true}, "已装备到 %s：%s" % [
		EquipmentDefs.slot_name(slot_id), inst.display_name()])
	_selected = inst
	_refresh()


func _capacity() -> int:
	var gm: Node = _game_manager()
	if gm != null and gm.equipment_manager != null:
		if gm.equipment_manager.has_method("get_capacity"):
			return int(gm.equipment_manager.call("get_capacity"))
	return DEFAULT_CAPACITY


# ============================================================
# 页签
# ============================================================

func _switch_page(page: int) -> void:
	_page = page
	_equip_page.visible = page == Page.EQUIP
	_craft_page.visible = page == Page.CRAFT
	_tab_equip.button_pressed = page == Page.EQUIP
	_tab_craft.button_pressed = page == Page.CRAFT
	_hint.text = ("左键选中 · Ctrl+左键多选 · 拖到左侧装备槽穿戴 · 右键操作"
		if page == Page.EQUIP else
		"左键选主装备 → 右键同类装备作为材料（武器吃武器，其余可互吃）")
	_refresh()


func _on_tab_equip() -> void:
	_switch_page(Page.EQUIP)


func _on_tab_craft() -> void:
	_switch_page(Page.CRAFT)


# ============================================================
# 刷新
# ============================================================

func _refresh() -> void:
	if not is_inside_tree():
		return
	var gm: Node = _game_manager()
	_gold_label.text = "金币 %d" % (gm.gold if gm else 0)
	_refresh_slots()
	_refresh_bag()
	_refresh_detail()
	_refresh_role_stats()
	_refresh_action_buttons()
	_refresh_craft_page()


func _refresh_slots() -> void:
	var em = _equipment_manager()
	var equipped: Dictionary = em.get_equipped() if em else {}
	for slot_id in _slot_grids:
		var node: BackpackItem = _slot_grids[slot_id]
		var inst: EquipmentInstance = equipped.get(slot_id)
		node.set_slot_label(EquipmentDefs.slot_name(slot_id))
		if inst != null:
			node.item = inst
		else:
			node.clear()


func _refresh_bag() -> void:
	var em = _equipment_manager()
	var inventory: Array = em.get_inventory() if em else []
	var shown := 0
	for i in range(_grids.size()):
		if i < inventory.size():
			var inst: EquipmentInstance = inventory[i]
			if _matches_filter(inst):
				_grids[i].item = inst
				shown += 1
			else:
				_grids[i].clear()
		else:
			_grids[i].clear()
	_filter_label.text = "%d/%d" % [shown, _capacity()]
	# 清理已不在背包的选中项
	for inst in _multi.keys():
		if not inventory.has(inst):
			_multi.erase(inst)
	_update_multi_label()


func _update_multi_label() -> void:
	if _multi.is_empty():
		_multi_label.text = ""
	else:
		_multi_label.text = "已选 %d 件" % _multi.size()


func _matches_filter(inst: EquipmentInstance) -> bool:
	if _filter == Filter.ALL:
		return true
	var t := inst.get_template()
	if t == null:
		return false
	match _filter:
		Filter.WEAPON: return t.category == EquipmentDefs.Category.WEAPON
		Filter.ARMOR: return t.category == EquipmentDefs.Category.ARMOR
		Filter.ACCESSORY: return t.category == EquipmentDefs.Category.ACCESSORY
	return true


func _refresh_detail() -> void:
	if _selected == null or not _selected.get_template():
		_detail_name.text = "选择装备查看详情"
		_detail_meta.text = ""
		_detail_affix.text = "点背包格或装备槽查看"
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
	if _selected.enchant_stacks > 0:
		meta_parts.append("附魔 %d/%d" % [
			_selected.enchant_stacks, SpecialRoomService.ENCHANT_MAX_STACKS])
	_detail_meta.text = " · ".join(meta_parts)

	var lines := [
		"[基础词条·穿戴]", _affix_text(t.base_affix, _selected.enhancement_level),
		"",
		"[吞噬词条·本局永久]", _affix_text(t.devour_affix, 0),
		"",
		"[融合词条·作材料贡献]", _affix_text(t.fusion_affix, 0),
	]
	if not _selected.extra_affixes.is_empty():
		lines.append("")
		lines.append("[附魔词条]")
		for a in _selected.extra_affixes:
			if a != null:
				lines.append("  " + a.description())
	_detail_affix.text = "\n".join(lines)


func _refresh_role_stats() -> void:
	if _stats != null:
		_stats.text = _role_stats_text()


func _role_stats_text() -> String:
	var gm: Node = _game_manager()
	if gm == null or gm.attributes == null:
		return "（属性不可用）"
	var parts: Array[String] = []
	for key in ["atk", "def", "hp", "ap", "crt", "crd", "aspd", "spd", "cdr", "rng"]:
		var stat_id: int = int(AttributeSystem.STAT_BY_NAME.get(key, -1))
		if stat_id < 0:
			continue
		var v: float = float(gm.call("stat_value", key))
		var name_s: String = str(AttributeSystem.STAT_NAMES.get(stat_id, key))
		if key in ["crt", "crd", "cdr"]:
			parts.append("%s %.1f%%" % [name_s, v * 100.0])
		elif key == "spd":
			parts.append("%s %.2f" % [name_s, v / 100.0])
		else:
			parts.append("%s %.0f" % [name_s, v])
	var rows: Array[String] = []
	var i := 0
	while i < parts.size():
		rows.append("  ".join(parts.slice(i, mini(i + 3, parts.size()))))
		i += 3
	return "\n".join(rows)


## 操作按钮可用性。**多选时优先对多选生效**（批量吞噬/丢弃）。
func _refresh_action_buttons() -> void:
	var has_sel := _selected != null
	var has_multi := not _multi.is_empty()
	_btn_equip.disabled = not has_sel
	_btn_devour.disabled = not (has_sel or has_multi)
	_btn_drop.disabled = not (has_sel or has_multi)
	if has_multi:
		_btn_devour.text = "吞噬(%d)" % _multi.size()
		_btn_drop.text = "丢弃(%d)" % _multi.size()
	else:
		_btn_devour.text = "吞噬"
		_btn_drop.text = "丢弃"
	# 已穿戴时「穿戴」变「卸下」
	if has_sel:
		var em = _equipment_manager()
		var worn: bool = em != null and em.get_equipped().values().has(_selected)
		_btn_equip.text = "卸下" if worn else "穿戴"
	else:
		_btn_equip.text = "穿戴"


func _affix_text(affix: AffixData, enhance_level: int) -> String:
	if affix == null:
		return "（无）"
	if affix.is_trigger():
		return affix.description()
	var value := affix.value
	if enhance_level > 0:
		value *= (1.0 + enhance_level * 0.05)
	var stat_name: String = AttributeSystem.STAT_NAMES.get(affix.stat, "属性")
	if affix.operation == AffixData.Operation.PERCENT:
		return "%s %+.1f%%" % [stat_name, value * 100.0]
	return "%s %+.1f" % [stat_name, value]


# ============================================================
# 强化页
# ============================================================

func _refresh_craft_page() -> void:
	if _craft_main_name == null:
		return
	if _fusion_source == null:
		_craft_main_name.text = "（未选主装备）"
		_craft_main_info.text = "在左侧背包选一件装备，点「选为材料/主装备」"
		_craft_hint.text = ""
	else:
		var t := _fusion_source.get_template()
		_craft_main_name.text = _fusion_source.display_name()
		_craft_main_name.add_theme_color_override("font_color",
			t.rarity_color() if t else Color.WHITE)
		_craft_main_info.text = "强化 +%d · 融合 %d（%s）" % [
			_fusion_source.enhancement_level, _fusion_source.fusion_count,
			_fusion_source.fusion_tier()]
		var cost := FusionRules.fusion_cost(_fusion_source, _fusion_source)
		var em := _equipment_manager()
		var e_cost: int = em.enhancement_cost(_fusion_source) if em != null else 0
		_craft_hint.text = "强化费用 %d 金 · 融合费用约 %d 金（武器吃武器，其余可互吃）" % [e_cost, cost]
	_btn_enhance.disabled = _fusion_source == null
	_btn_fuse.disabled = _fusion_source == null
	_btn_craft_pick.disabled = _selected == null
	if _selected != null:
		_btn_craft_pick.text = ("已选：%s" % _selected.display_name()) \
			if _fusion_source == _selected else "把当前选中设为主装备"


# ============================================================
# 选择
# ============================================================

func _on_item_clicked(idx: int) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		_selected = null
		_refresh_detail(); _refresh_action_buttons(); _refresh_craft_page()
		return
	# Ctrl 按住 → 切换多选（批量操作）
	if Input.is_key_pressed(KEY_CTRL):
		_toggle_multi(_grids[idx].item)
		_grids[idx].set_multi_selected(_multi.has(_grids[idx].item))
		return
	_selected = _grids[idx].item
	_refresh_detail(); _refresh_action_buttons(); _refresh_craft_page()


func _on_slot_clicked(idx: int) -> void:
	var slot_id := idx - SLOT_INDEX_BASE
	var node: BackpackItem = _slot_grids.get(slot_id)
	if node == null or not node.has_item():
		_selected = null
	else:
		_selected = node.item
	_refresh_detail(); _refresh_action_buttons(); _refresh_craft_page()


func _toggle_multi(inst: EquipmentInstance) -> void:
	if _multi.has(inst):
		_multi.erase(inst)
	else:
		_multi[inst] = true
	_update_multi_label()
	_refresh_action_buttons()


## 清空多选（操作完成后调）
func _clear_multi() -> void:
	for inst in _multi.keys():
		for g in _grids:
			if g.item == inst:
				g.set_multi_selected(false)
	_multi.clear()
	_update_multi_label()
	_refresh_action_buttons()


# ============================================================
# 拖拽 / 交换
# ============================================================

func _on_swap_requested(from: int, to: int) -> void:
	var em = _equipment_manager()
	if em:
		em.swap_items(from, to)


# ============================================================
# 右键菜单
# ============================================================

func _on_menu_requested(idx: int, screen_pos: Vector2) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	_selected = item
	_refresh_detail(); _refresh_action_buttons(); _refresh_craft_page()
	_menu.show_actions(screen_pos, idx, ["equip", "enhance", "devour", "lock", "drop"])
	_menu.set_lock_state(item.is_locked)


func _on_slot_menu_requested(idx: int, screen_pos: Vector2) -> void:
	var slot_id := idx - SLOT_INDEX_BASE
	var node: BackpackItem = _slot_grids.get(slot_id)
	if node == null or not node.has_item():
		return
	_selected = node.item
	_refresh_detail(); _refresh_action_buttons()
	_menu.show_actions(screen_pos, idx, ["unequip", "enhance", "lock"])
	_menu.set_lock_state(node.item.is_locked)


func _on_action_requested(action: String, idx: int) -> void:
	if idx >= SLOT_INDEX_BASE:
		_on_slot_action(action)
		return
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	var em = _equipment_manager()
	if em == null:
		return
	var result: Dictionary
	match action:
		"equip":      _try_equip(item)
		"unequip":    _unequip(item)
		"enhance":    result = em.enhance(item); _notify(result, "强化 +%d" % item.enhancement_level)
		"devour":     result = _devour(item)
		"lock":       item.is_locked = not item.is_locked; _refresh()
		"drop":
			if item.is_locked:
				_notify({"ok": false, "reason": "已锁定，无法丢弃"}, "")
			else:
				em.remove_item(item); _selected = null
	_refresh()


func _on_slot_action(action: String) -> void:
	if _selected == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	match action:
		"unequip": _unequip(_selected)
		"enhance":
			var r: Dictionary = em.enhance(_selected)
			_notify(r, "强化 +%d" % _selected.enhancement_level)
		"lock": _selected.is_locked = not _selected.is_locked; _refresh()


func _unequip(item: EquipmentInstance) -> void:
	var em = _equipment_manager()
	if em == null:
		return
	if em.unequip_item(item):
		_notify({"ok": true}, "已卸下：%s" % item.display_name())
	else:
		_notify({"ok": false, "reason": "背包已满，无法卸下"}, "")


# ============================================================
# 左栏操作按钮
# ============================================================

func _on_btn_equip() -> void:
	if _selected == null:
		return
	var em = _equipment_manager()
	if em != null and em.get_equipped().values().has(_selected):
		_unequip(_selected)
	else:
		_try_equip(_selected)
	_refresh()


## 吞噬：多选优先（批量），否则单件
func _on_btn_devour() -> void:
	var em = _equipment_manager()
	if em == null:
		return
	var targets: Array = []
	if not _multi.is_empty():
		targets = _multi.keys()
	elif _selected != null:
		targets = [_selected]
	if targets.is_empty():
		return
	var ok := 0
	for inst in targets:
		var r: Dictionary = _devour(inst)
		if r.get("ok", false):
			ok += 1
	_clear_multi()
	_selected = null
	_notify({"ok": true}, "吞噬 %d/%d 件" % [ok, targets.size()])
	_refresh()


## 丢弃：多选优先
func _on_btn_drop() -> void:
	var em = _equipment_manager()
	if em == null:
		return
	var targets: Array = []
	if not _multi.is_empty():
		targets = _multi.keys()
	elif _selected != null:
		targets = [_selected]
	if targets.is_empty():
		return
	var n := 0
	for inst in targets:
		if not inst.is_locked:
			em.remove_item(inst)
			n += 1
	_clear_multi()
	_selected = null
	_notify({"ok": true}, "丢弃 %d 件" % n)
	_refresh()


# —— 强化页按钮 ——

func _on_btn_pick() -> void:
	if _selected == null:
		return
	_fusion_source = _selected
	_notify({"ok": true}, "已选为主装备：%s" % _selected.display_name())
	_refresh_craft_page()


func _on_btn_enhance() -> void:
	if _fusion_source == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	var r: Dictionary = em.enhance(_fusion_source)
	_notify(r, "强化 +%d（花费 %d）" % [_fusion_source.enhancement_level, r.get("cost", 0)])
	_refresh()


func _on_btn_fuse() -> void:
	"""融合：主装备吃材料。材料来自多选（批量）或当前选中。"""
	if _fusion_source == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	var mats: Array = []
	if not _multi.is_empty():
		mats = _multi.keys()
	elif _selected != null and _selected != _fusion_source:
		mats = [_selected]
	if mats.is_empty():
		_notify({"ok": false, "reason": "请先选材料（Ctrl+左键多选）"}, "")
		return
	var ok := 0
	var fail_reason := ""
	for m in mats:
		if m == _fusion_source:
			continue
		var r: Dictionary = em.fuse(_fusion_source, m)
		if r.get("ok", false):
			ok += 1
		elif fail_reason.is_empty():
			fail_reason = str(r.get("reason", ""))
	_clear_multi()
	if ok > 0:
		_notify({"ok": true}, "融合 %d 件材料（当前融合数 %d）" % [ok, _fusion_source.fusion_count])
	else:
		_notify({"ok": false, "reason": fail_reason if fail_reason else "融合失败"}, "")
	_refresh()


# —— 筛选 ——

func _on_filter_all() -> void:
	_set_filter(Filter.ALL, $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/FilterAll)

func _on_filter_weapon() -> void:
	_set_filter(Filter.WEAPON, $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/FilterWeapon)

func _on_filter_armor() -> void:
	_set_filter(Filter.ARMOR, $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/FilterArmor)

func _on_filter_accessory() -> void:
	_set_filter(Filter.ACCESSORY, $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters/FilterAccessory)


func _set_filter(f: int, btn: Button) -> void:
	_filter = f
	var filters := $Root/Panel/Margin/VBox/Pages/EquipPage/Mid/Filters
	for c in filters.get_children():
		if c is Button:
			(c as Button).button_pressed = (c == btn)
	_refresh_bag()


# —— 穿戴/吞噬 ——

func _try_equip(item: EquipmentInstance) -> void:
	var template := item.get_template()
	if template == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	var slot := template.slot
	var defs := EquipmentDefs
	if slot in [defs.Slot.ACCESSORY_1, defs.Slot.WEAPON_1]:
		var equipped: Dictionary = em.get_equipped()
		if equipped.has(slot) and not equipped.has(slot + 1):
			slot = slot + 1
	em.equip(slot, item)
	_notify({"ok": true}, "已装备：%s" % item.display_name())


func _devour(item: EquipmentInstance) -> Dictionary:
	var gm: Node = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "GameManager 不可用"}
	return gm.call("devour_item", item)


func _notify(result: Dictionary, ok_text: String) -> void:
	var bus = _event_bus()
	if bus == null:
		return
	if result.get("ok", false):
		bus.message.emit(ok_text)
	else:
		bus.message.emit(result.get("reason", "操作失败"))


# ============================================================
# 开关
# ============================================================

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


func _open() -> void:
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_in_group(MODAL_GROUP):
		add_to_group(MODAL_GROUP)
	_fusion_source = null
	_clear_multi()
	_refresh()


func _close() -> void:
	_menu.hide()
	visible = false
	remove_from_group(MODAL_GROUP)
	get_tree().paused = false


# ============================================================
# autoload 访问
# ============================================================

func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


func _event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


func _equipment_manager() -> RefCounted:
	var gm: Node = _game_manager()
	return gm.equipment_manager if gm else null
