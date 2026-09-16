class_name BackpackUI
extends CanvasLayer
## 背包主界面 —— 左右分栏常驻版
##
## 布局（用户要求：免去频繁切页）：
##   左侧 = 装备栏 + 角色属性 + 选中详情 + 操作按钮 + 吞噬累积
##   右侧 = 背包网格 + 分类筛选（全部/武器/护甲/饰品）
##
## 旧版是四个页签（装备/背包/强化/吞噬）来回切——操作一件装备要跳好几次页。
## 现在所有功能同屏常驻：选中任意物品（背包格或装备槽）→ 左侧直接操作。
##
## 数据源：GameManager.equipment_manager 的 EquipmentInstance 列表。
## ESC 开关，EventBus.inventory_changed 驱动刷新。

const ITEM_SCENE := preload("res://ui/inventory/backpack_item.tscn")
## 背包格子数。**以逻辑层为准**（EquipmentManager.MAX_INVENTORY_SIZE），
## 此常量只是 GameManager 未就绪时的兜底——两者不一致会让玩家
## 「看到空格却放不进去」。
const DEFAULT_CAPACITY := 40
const COLUMNS := 8
## 模态面板组：打开时入组，暂停菜单据此让位（避免 Esc 叠加）
const MODAL_GROUP := "modal_ui"

## 装备槽的 index 基准：背包格用 0..capacity-1，装备槽用 1000+slot_id。
## 两者共用 BackpackItem 控件，靠 index 区间区分来源
## （见 _on_item_clicked / _on_menu_requested 的分支）。
const SLOT_INDEX_BASE := 1000

## 背包分类筛选
enum Filter { ALL, WEAPON, ARMOR, ACCESSORY }

## 装备槽顺序（界面从左到右、从上到下）
const SLOT_ORDER := [
	EquipmentDefs.Slot.HEAD, EquipmentDefs.Slot.CHEST, EquipmentDefs.Slot.SHOULDERS,
	EquipmentDefs.Slot.HANDS, EquipmentDefs.Slot.LEGS, EquipmentDefs.Slot.FEET,
	EquipmentDefs.Slot.ACCESSORY_1, EquipmentDefs.Slot.ACCESSORY_2,
	EquipmentDefs.Slot.WEAPON_1, EquipmentDefs.Slot.WEAPON_2,
]

var _grids: Array[BackpackItem] = []
var _slot_grids: Dictionary = {}          # slot_id -> BackpackItem
var _menu: BackpackMenu
var _selected: EquipmentInstance = null   # 详情面板当前选中
var _fusion_source: EquipmentInstance = null  # 融合流程：已选主装备待选材料
var _filter: int = Filter.ALL

@onready var _gold_label: Label = $SafeZone/Panel/Margin/VBox/Header/GoldLabel
@onready var _hint: Label = $SafeZone/Panel/Margin/VBox/Hint
@onready var _slot_grid: GridContainer = $SafeZone/Panel/Margin/VBox/Content/Left/SlotPanel/SlotMargin/SlotGrid
@onready var _detail_name: Label = $SafeZone/Panel/Margin/VBox/Content/Left/Detail/DetailMargin/DetailScroll/DetailVBox/DetailName
@onready var _detail_meta: Label = $SafeZone/Panel/Margin/VBox/Content/Left/Detail/DetailMargin/DetailScroll/DetailVBox/DetailMeta
@onready var _detail_affix: Label = $SafeZone/Panel/Margin/VBox/Content/Left/Detail/DetailMargin/DetailScroll/DetailVBox/DetailAffix
@onready var _devour_summary: Label = $SafeZone/Panel/Margin/VBox/Content/Left/DevourSummary
@onready var _stats: Label = $SafeZone/Panel/Margin/VBox/Content/Left/StatPanel/StatMargin/Stats
@onready var _filter_label: Label = $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters/FilterLabel
@onready var _btn_equip: Button = $SafeZone/Panel/Margin/VBox/Content/Left/Actions/BtnEquip
@onready var _btn_enhance: Button = $SafeZone/Panel/Margin/VBox/Content/Left/Actions/BtnEnhance
@onready var _btn_fuse: Button = $SafeZone/Panel/Margin/VBox/Content/Left/Actions/BtnFuse
@onready var _btn_devour: Button = $SafeZone/Panel/Margin/VBox/Content/Left/Actions/BtnDevour


func _ready() -> void:
	_menu = $Menu
	_build_bag_grid()
	_build_slot_grid()
	var bus = _event_bus()
	if bus:
		bus.inventory_changed.connect(_refresh)
		bus.equipment_changed.connect(func(_s, _i): _refresh())
		bus.gold_changed.connect(func(_g): _refresh())
		_refresh()


## 构建背包格子网格
func _build_bag_grid() -> void:
	var grid := $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Scroll/Grid
	grid.columns = COLUMNS
	for i in range(_capacity()):
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = i
		n.swap_requested.connect(_on_swap_requested)
		n.menu_requested.connect(_on_menu_requested)
		n.item_clicked.connect(_on_item_clicked)
		_grids.push_back(n)
		grid.add_child(n)


## 构建装备槽（10 格，常驻左栏）。每格也是一个 BackpackItem，
## index 用 SLOT_INDEX_BASE 区间，便于统一处理点击/右键。
func _build_slot_grid() -> void:
	for slot_id in SLOT_ORDER:
		var n := ITEM_SCENE.instantiate() as BackpackItem
		n.index = SLOT_INDEX_BASE + int(slot_id)
		n.menu_requested.connect(_on_slot_menu_requested)
		n.item_clicked.connect(_on_slot_clicked)
		_slot_grids[int(slot_id)] = n
		_slot_grid.add_child(n)


## 背包格子数：从逻辑层取（单一真相源），取不到时用常量兜底。
func _capacity() -> int:
	var gm := _game_manager()
	if gm != null and gm.equipment_manager != null:
		if gm.equipment_manager.has_method("get_capacity"):
			return int(gm.equipment_manager.call("get_capacity"))
	return DEFAULT_CAPACITY


# ============================================================
# 刷新
# ============================================================

## 从装备管理器刷新全部显示
func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_gold()
	_refresh_slots()
	_refresh_bag()
	_refresh_detail()
	_refresh_role_stats()
	_refresh_devour_summary()
	_refresh_action_buttons()


## 刷新金币显示
func _refresh_gold() -> void:
	var gm = _game_manager()
	_gold_label.text = "金币 %d" % (gm.gold if gm else 0)


## 刷新装备栏（已穿戴的 10 个槽）
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


## 刷新背包格（含分类筛选）
func _refresh_bag() -> void:
	var em = _equipment_manager()
	var inventory: Array = em.get_inventory() if em else []
	var shown := 0
	var total := inventory.size()
	for i in range(_grids.size()):
		if i < inventory.size():
			var inst: EquipmentInstance = inventory[i]
			if _matches_filter(inst):
				_grids[i].item = inst
				shown += 1
			else:
				# 被筛掉的格子**保留原物品的索引语义**：
				# 这里只是不显示，拖拽仍按真实索引工作
				_grids[i].clear()
		else:
			_grids[i].clear()
	_filter_label.text = "%d/%d" % [shown, _capacity()]


## 该物品是否通过当前分类筛选
func _matches_filter(inst: EquipmentInstance) -> bool:
	if _filter == Filter.ALL:
		return true
	var t := inst.get_template()
	if t == null:
		return false
	match _filter:
		Filter.WEAPON:
			return t.category == EquipmentDefs.Category.WEAPON
		Filter.ARMOR:
			return t.category == EquipmentDefs.Category.ARMOR
		Filter.ACCESSORY:
			return t.category == EquipmentDefs.Category.ACCESSORY
	return true


## 详情面板：选中装备的词条
## （角色属性已拆到独立的「角色属性」常驻面板，不再混在这里——
##   放在滚动区里会被长词条挤出视野，而用户明确要求它能随时看到）
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
	# 附魔附加的通用词条（名词分册第 5 章）
	if not _selected.extra_affixes.is_empty():
		lines.append("")
		lines.append("[附魔词条]")
		for a in _selected.extra_affixes:
			if a != null:
				lines.append("  " + a.description())
	if _fusion_source != null and _fusion_source != _selected:
		lines.append("")
		lines.append("→ 再次点「融合」将作为材料")
	_detail_affix.text = "\n".join(lines)


## 角色当前面板属性（常驻显示，不随选中变化）。
## 用户要求「装备页面要给出角色属性数值」——放在独立面板而非详情滚动区。
func _refresh_role_stats() -> void:
	if _stats == null:
		return
	_stats.text = _role_stats_text()


## 角色当前面板属性文本（供详情面板与常驻面板复用）
func _role_stats_text() -> String:
	var gm = _game_manager()
	if gm == null or gm.attributes == null:
		return "（属性不可用）"
	var parts: Array[String] = []
	for key in ["atk", "def", "hp", "ap", "crt", "crd", "aspd", "spd", "cdr", "rng"]:
		var stat_id: int = int(AttributeSystem.STAT_BY_NAME.get(key, -1))
		if stat_id < 0:
			continue
		var v: float = float(gm.stat_value(key))
		var name_s: String = str(AttributeSystem.STAT_NAMES.get(stat_id, key))
		# 暴击/暴伤/冷却缩减是比例量，按百分比显示更直观
		if key in ["crt", "crd", "cdr"]:
			parts.append("%s %.1f%%" % [name_s, v * 100.0])
		elif key == "spd":
			parts.append("%s %.2f" % [name_s, v / 100.0])
		else:
			parts.append("%s %.0f" % [name_s, v])
	# 每行 3 项，避免长行溢出面板
	var rows: Array[String] = []
	var i := 0
	while i < parts.size():
		rows.append("  ".join(parts.slice(i, mini(i + 3, parts.size()))))
		i += 3
	return "\n".join(rows)


## 吞噬累积效果汇总（用户要求）
func _refresh_devour_summary() -> void:
	var gm = _game_manager()
	if gm == null:
		_devour_summary.text = "尚无吞噬"
		return
	var em = _equipment_manager()
	var mods: Dictionary = {}
	if em != null and em.has_method("devour_modifiers"):
		mods = em.call("devour_modifiers")
	if mods.is_empty():
		_devour_summary.text = "尚无吞噬（右键物品 → 吞噬，获得本局永久成长）"
		return
	# 按 stat 聚合
	var agg := {}
	for inst_id in mods:
		var m: Dictionary = mods[inst_id]
		var st: int = int(m.get("stat", 0))
		agg[st] = float(agg.get(st, 0.0)) + float(m.get("flat", 0.0)) \
			+ float(m.get("percent", 0.0))
	var lines: Array[String] = []
	for st in agg:
		var name_s: String = str(AttributeSystem.STAT_NAMES.get(st, "属性"))
		lines.append("%s +%.1f" % [name_s, float(agg[st])])
	_devour_summary.text = "已吞噬 %d 件\n%s" % [mods.size(), "  ".join(lines)]


## 操作按钮可用性：无选中时禁用，避免误点
func _refresh_action_buttons() -> void:
	var has_sel := _selected != null
	var t := _selected.get_template() if has_sel else null
	_btn_equip.disabled = not has_sel
	_btn_enhance.disabled = not has_sel
	_btn_fuse.disabled = not has_sel
	_btn_devour.disabled = not has_sel
	# 已穿戴的装备，"穿戴"按钮改叫"卸下"更贴切
	if has_sel:
		var em = _equipment_manager()
		var worn: bool = em != null and em.get_equipped().values().has(_selected)
		_btn_equip.text = "卸下" if worn else "穿戴"
	else:
		_btn_equip.text = "穿戴"


## 词条文本（含强化倍率显示）
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
# 分类筛选
# ============================================================

func _on_filter_all() -> void:
	_set_filter(Filter.ALL, $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters/FilterAll)

func _on_filter_weapon() -> void:
	_set_filter(Filter.WEAPON, $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters/FilterWeapon)

func _on_filter_armor() -> void:
	_set_filter(Filter.ARMOR, $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters/FilterArmor)

func _on_filter_accessory() -> void:
	_set_filter(Filter.ACCESSORY, $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters/FilterAccessory)


## 切换筛选并同步按钮的按下态（互斥）
func _set_filter(f: int, btn: Button) -> void:
	_filter = f
	var filters := $SafeZone/Panel/Margin/VBox/Content/BagPanel/BagMargin/BagVBox/Filters
	for c in filters.get_children():
		if c is Button:
			(c as Button).button_pressed = (c == btn)
	_refresh_bag()


# ============================================================
# 交互
# ============================================================

## 背包格左键：更新详情
func _on_item_clicked(idx: int) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		_selected = null
		_refresh_detail()
		_refresh_action_buttons()
		return
	_selected = _grids[idx].item
	_refresh_detail()
	_refresh_action_buttons()


## 装备槽左键：同样更新详情（这才是"不用切页"的关键）
func _on_slot_clicked(idx: int) -> void:
	var slot_id := idx - SLOT_INDEX_BASE
	var node: BackpackItem = _slot_grids.get(slot_id)
	if node == null or not node.has_item():
		_selected = null
	else:
		_selected = node.item
	_refresh_detail()
	_refresh_action_buttons()


## 拖拽交换：交换两格物品
func _on_swap_requested(from: int, to: int) -> void:
	var em = _equipment_manager()
	if em:
		em.swap_items(from, to)


## 背包格右键菜单
func _on_menu_requested(idx: int, screen_pos: Vector2) -> void:
	if idx < 0 or idx >= _grids.size() or not _grids[idx].has_item():
		return
	var item: EquipmentInstance = _grids[idx].item
	_selected = item
	_refresh_detail()
	_refresh_action_buttons()
	_menu.show_actions(screen_pos, idx, ["equip", "enhance", "devour", "lock", "drop"])
	_menu.set_lock_state(item.is_locked)


## 装备槽右键菜单（已穿戴 → 只能卸下/强化/吞噬不可用）
func _on_slot_menu_requested(idx: int, screen_pos: Vector2) -> void:
	var slot_id := idx - SLOT_INDEX_BASE
	var node: BackpackItem = _slot_grids.get(slot_id)
	if node == null or not node.has_item():
		return
	_selected = node.item
	_refresh_detail()
	_refresh_action_buttons()
	_menu.show_actions(screen_pos, idx, ["unequip", "enhance", "lock"])
	_menu.set_lock_state(node.item.is_locked)


## 菜单操作分发
func _on_action_requested(action: String, idx: int) -> void:
	# 装备槽的菜单操作
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
		"equip":
			_try_equip(item)
		"unequip":
			_unequip(item)
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


## 装备槽上的菜单操作（目标是已穿戴的装备）
func _on_slot_action(action: String) -> void:
	if _selected == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	match action:
		"unequip":
			_unequip(_selected)
		"enhance":
			var r: Dictionary = em.enhance(_selected)
			_notify(r, "强化 +%d（花费 %d）" % [
				_selected.enhancement_level, r.get("cost", 0)])
		"lock":
			_selected.is_locked = not _selected.is_locked
			_refresh()


## 卸下已穿戴装备（背包满时会被拒——见 EquipmentManager.unequip 的返回值）
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


func _on_btn_enhance() -> void:
	if _selected == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	var r: Dictionary = em.enhance(_selected)
	_notify(r, "强化 +%d（花费 %d）" % [_selected.enhancement_level, r.get("cost", 0)])
	_refresh()


## 融合按钮：第一次点选主装备，第二次点材料自动融合（省去右键两步流程）
func _on_btn_fuse() -> void:
	if _selected == null:
		return
	var em = _equipment_manager()
	if em == null:
		return
	if _fusion_source == null:
		_fusion_source = _selected
		_notify({"ok": true}, "已选为主装备，再选一件同部位装备点「融合」")
		_refresh_detail()
		return
	if _fusion_source == _selected:
		_fusion_source = null
		_notify({"ok": true}, "已取消融合")
		_refresh_detail()
		return
	var r: Dictionary = em.fuse(_fusion_source, _selected)
	if r.get("ok", false):
		_fusion_source = null
	_notify(r, "融合成功（%s · 花费 %d）" % [r.get("new_tier", ""), r.get("cost", 0)])
	_refresh()


func _on_btn_devour() -> void:
	if _selected == null:
		return
	_devour(_selected)
	_refresh()


func _on_btn_drop() -> void:
	if _selected == null:
		return
	if _selected.is_locked:
		_notify({"ok": false, "reason": "已锁定，无法丢弃"}, "")
		return
	var em = _equipment_manager()
	if em == null:
		return
	em.remove_item(_selected)
	_selected = null
	_refresh()


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


## 打开背包
## 加入 modal_ui 组：暂停菜单用 _input（早于 _unhandled_input），只认这个组。
## 不入组的话，在背包里按 Esc 会被暂停菜单抢先打开（叠在背包上面）。
func _open() -> void:
	get_tree().paused = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_in_group(MODAL_GROUP):
		add_to_group(MODAL_GROUP)
	_fusion_source = null
	_refresh()


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
func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


## 获取 EventBus autoload
func _event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null


## 获取装备管理器
func _equipment_manager() -> RefCounted:
	var gm = _game_manager()
	return gm.equipment_manager if gm else null
