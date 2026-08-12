class_name EquipmentScreen
extends Control
## 装备管理界面：装备 / 背包 / 强化（含融合）/ 吞噬 四页
## 交互：左键查看 + 完整对比；右键功能条（装备/查看/吞噬/强化/锁定/丢弃）

const RARITY_COLORS := {
	0: "#FFFFFF", 1: "#7BC96F", 2: "#5B8DEF", 3: "#B06CE8", 4: "#F09A3E", 5: "#E5484D",
}

const TAG_FILTERS := ["单手", "双手", "近战", "远程", "长杆", "物理", "法术", "其他", "轻甲", "中甲", "重甲"]

var current_tab := 0          # 0 装备 1 背包 2 强化 3 吞噬
var source_mode := 0          # 0 背包 1 已装备 2 全部拥有
var enhance_subtab := 0       # 0 强化 1 融合
var selected_id := ""
var fuse_main_id := ""
var fuse_material_id := ""
var devour_selected := {}
var filter_slot := -1
var filter_tag := ""
var filter_search := ""
var sort_mode := 0            # 0 最近 1 名称 2 部位 3 强化 4 融合

var gold_label: Label
var tab_buttons: Array[Button] = []
var page_containers: Array[Control] = []
var detail_rt: RichTextLabel
var _context_item_id := ""
var _context_slot := -1


func _ready() -> void:
	theme = UITheme.get_theme()
	add_to_group("equipment_screen")
	visible = false
	_build_layout()
	EventBus.gold_changed.connect(func(_x = null): _refresh_gold())
	EventBus.inventory_changed.connect(refresh_all)
	EventBus.stats_changed.connect(refresh_all)
	EventBus.layer_changed.connect(func(_a, _b): refresh_all())
	refresh_all()


func refresh_all() -> void:
	if not is_inside_tree():
		return
	_refresh_gold()
	for i in page_containers.size():
		page_containers[i].visible = i == current_tab
		_rebuild_page(i)
	_update_tab_style()


# ---------------------------------------------------------------------------
# 布局
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	gold_label = Label.new()
	gold_label.position = Vector2(880, 10)
	gold_label.add_theme_font_size_override("font_size", 20)
	add_child(gold_label)

	var title := Label.new()
	title.text = "装备管理"
	title.position = Vector2(24, 10)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.position = Vector2(1120, 10)
	close_btn.pressed.connect(func(): visible = false)
	add_child(close_btn)

	for i in 4:
		var tab := Button.new()
		tab.text = ["装备", "背包", "强化", "吞噬"][i]
		tab.position = Vector2(24 + i * 100, 48)
		tab.custom_minimum_size = Vector2(90, 34)
		tab.pressed.connect(func(t = i): _switch_tab(t))
		tab_buttons.append(tab)
		add_child(tab)

	for i in 4:
		var page := Control.new()
		page.position = Vector2(16, 92)
		page.size = Vector2(1250, 600)
		page_containers.append(page)
		add_child(page)


func _switch_tab(tab: int) -> void:
	current_tab = tab
	refresh_all()


func _update_tab_style() -> void:
	for i in tab_buttons.size():
		tab_buttons[i].modulate = Color(1, 1, 1, 1) if i == current_tab else Color(0.6, 0.6, 0.6, 1)


func _refresh_gold() -> void:
	gold_label.text = "金币：%d" % GameState.gold


# ---------------------------------------------------------------------------
# 页面重建
# ---------------------------------------------------------------------------

func _rebuild_page(index: int) -> void:
	var page := page_containers[index]
	for child in page.get_children():
		child.queue_free()
	match index:
		0: _build_equipment_page(page)
		1: _build_backpack_page(page)
		2: _build_enhance_page(page)
		3: _build_devour_page(page)


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _make_item_button(parent: Control, item: EquipmentInstance, on_left: Callable, on_right: Callable) -> void:
	var btn := Button.new()
	var color: String = RARITY_COLORS.get(item.rarity, "#FFFFFF")
	btn.text = "[color=%s]%s[/color] 融合%d [%s] 强化+%d" % [
		color, item.display_name(), item.fusion_count, item.fusion_tier(), item.enhancement_level]
	if item.is_locked:
		btn.text += " 🔒"
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(300, 34)
	btn.pressed.connect(func(): on_left.call(item.instance_id))
	btn.gui_input.connect(_on_item_gui_input.bind(item.instance_id, on_right))
	parent.add_child(btn)


func _on_item_gui_input(event: InputEvent, item_id: String, on_right: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		on_right.call(item_id, event.global_position)


func _show_context_menu(item_id: String, at: Vector2, include_equip: bool, equipped_slot: int) -> void:
	_context_item_id = item_id
	_context_slot = equipped_slot
	var item := GameState.equipment_manager.find_item(item_id)
	if item == null:
		return
	var menu := PopupMenu.new()
	menu.position = at
	if include_equip:
		menu.add_item("装备" if equipped_slot < 0 else "卸下", 1)
	menu.add_item("查看", 2)
	menu.add_item("吞噬", 3)
	menu.add_item("强化", 4)
	menu.add_item("解锁" if item.is_locked else "锁定", 5)
	menu.add_item("丢弃", 6)
	menu.id_pressed.connect(_on_context_action.bind(item_id, equipped_slot))
	add_child(menu)
	menu.popup()


func _on_context_action(id: int, item_id: String, equipped_slot: int) -> void:
	var item := GameState.equipment_manager.find_item(item_id)
	if item == null:
		return
	match id:
		1:
			if equipped_slot >= 0:
				GameState.unequip_slot(equipped_slot)
			else:
				GameState.equip_item(item_id)
		2:
			selected_id = item_id
			refresh_all()
		3:
			if item.is_locked or equipped_slot >= 0:
				EventBus.message.emit("锁定或已装备的装备不能吞噬")
			else:
				GameState.devour_ids([item_id])
		4:
			_switch_to_enhance(item_id)
		5:
			item.is_locked = not item.is_locked
			EventBus.inventory_changed.emit()
		6:
			if item.is_locked or equipped_slot >= 0:
				EventBus.message.emit("锁定或已装备的装备不能丢弃")
			else:
				GameState.equipment_manager.remove_item(item)
				EventBus.inventory_changed.emit()


func _switch_to_enhance(item_id: String) -> void:
	selected_id = item_id
	fuse_main_id = item_id
	current_tab = 2
	refresh_all()


# ---------------------------------------------------------------------------
# 1. 装备页
# ---------------------------------------------------------------------------

func _build_equipment_page(page: Control) -> void:
	var slots_label := Label.new()
	slots_label.text = "10 个装备槽位（双手武器占用武器1+2，属性只计一次）"
	slots_label.position = Vector2(0, 0)
	page.add_child(slots_label)

	var slot_names := EquipmentDefs.SLOT_NAMES
	var slot_buttons: Array[Button] = []
	for i in slot_names.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(250, 44)
		var x := (i % 2) * 280
		var y := 36 + (i / 2) * 52
		btn.position = Vector2(x, y)
		var slot: int = EquipmentDefs.SlotId.values()[i]
		var item := GameState.equipment_manager.loadout.get_item(slot)
		if item != null:
			btn.text = "%s：%s" % [slot_names[i], item.display_name()]
			btn.modulate = _rarity_color(item.rarity)
		else:
			btn.text = "%s：空" % slot_names[i]
			btn.modulate = Color(0.6, 0.6, 0.6)
		btn.pressed.connect(func(s = slot): _on_slot_clicked(s))
		btn.gui_input.connect(_on_slot_gui_input.bind(slot))
		page.add_child(btn)
		slot_buttons.append(btn)

	detail_rt = RichTextLabel.new()
	detail_rt.bbcode_enabled = true
	detail_rt.position = Vector2(590, 0)
	detail_rt.size = Vector2(640, 580)
	detail_rt.fit_content = true
	page.add_child(detail_rt)
	if selected_id != "":
		_show_detail()


func _on_slot_gui_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var item := GameState.equipment_manager.loadout.get_item(slot)
		if item:
			_show_context_menu(item.instance_id, event.global_position, true, slot)


func _on_slot_clicked(slot: int) -> void:
	var item := GameState.equipment_manager.loadout.get_item(slot)
	if item:
		selected_id = item.instance_id
		refresh_all()


# ---------------------------------------------------------------------------
# 2. 背包页
# ---------------------------------------------------------------------------

func _build_backpack_page(page: Control) -> void:
	var search := LineEdit.new()
	search.placeholder_text = "搜索名称"
	search.position = Vector2(0, 0)
	search.size = Vector2(180, 32)
	search.text = filter_search
	search.text_changed.connect(func(t): filter_search = t; refresh_all())
	page.add_child(search)

	var slot_opt := OptionButton.new()
	slot_opt.position = Vector2(200, 0)
	slot_opt.size = Vector2(120, 32)
	slot_opt.add_item("全部部位", -1)
	for i in EquipmentDefs.SLOT_CATEGORY_NAMES.size():
		slot_opt.add_item(EquipmentDefs.SLOT_CATEGORY_NAMES[i], i)
	slot_opt.select(filter_slot + 1)
	slot_opt.item_selected.connect(func(idx): filter_slot = idx - 1; refresh_all())
	page.add_child(slot_opt)

	var tag_opt := OptionButton.new()
	tag_opt.position = Vector2(330, 0)
	tag_opt.size = Vector2(120, 32)
	tag_opt.add_item("全部标签", -1)
	for t_idx in TAG_FILTERS.size():
		tag_opt.add_item(TAG_FILTERS[t_idx], t_idx)
	tag_opt.select(maxi(TAG_FILTERS.find(filter_tag) + 1, 0))
	tag_opt.item_selected.connect(func(idx): filter_tag = tag_opt.get_item_text(idx) if idx > 0 else ""; refresh_all())
	page.add_child(tag_opt)

	var sort_opt := OptionButton.new()
	sort_opt.position = Vector2(460, 0)
	sort_opt.size = Vector2(130, 32)
	sort_opt.add_item("最近获得", 0)
	sort_opt.add_item("名称", 1)
	sort_opt.add_item("部位", 2)
	sort_opt.add_item("强化等级", 3)
	sort_opt.add_item("融合次数", 4)
	sort_opt.select(sort_mode)
	sort_opt.item_selected.connect(func(idx): sort_mode = idx; refresh_all())
	page.add_child(sort_opt)

	var chips := Label.new()
	chips.position = Vector2(610, 2)
	chips.text = "当前筛选：" + _filter_desc()
	chips.add_theme_font_size_override("font_size", 13)
	page.add_child(chips)

	var clear_btn := Button.new()
	clear_btn.text = "清除筛选"
	clear_btn.position = Vector2(1000, 0)
	clear_btn.pressed.connect(func(): filter_search = ""; filter_slot = -1; filter_tag = ""; refresh_all())
	page.add_child(clear_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(0, 44)
	grid.size = Vector2(620, 520)
	page.add_child(grid)

	var items := _filtered_and_sorted()
	for item in items:
		_make_item_button(grid, item,
			func(id): selected_id = id; refresh_all(),
			func(id, at): _show_context_menu(id, at, true, -1))

	detail_rt = RichTextLabel.new()
	detail_rt.bbcode_enabled = true
	detail_rt.position = Vector2(640, 44)
	detail_rt.size = Vector2(600, 520)
	detail_rt.fit_content = true
	page.add_child(detail_rt)
	if selected_id != "":
		_show_detail()


func _filter_desc() -> String:
	var parts: Array = []
	if filter_search != "":
		parts.append("搜索:" + filter_search)
	if filter_slot >= 0:
		parts.append(EquipmentDefs.SLOT_CATEGORY_NAMES[filter_slot])
	if filter_tag != "":
		parts.append(filter_tag)
	return "、".join(PackedStringArray(parts)) if not parts.is_empty() else "无"


func _filtered_and_sorted() -> Array:
	var items: Array = GameState.equipment_manager.inventory.duplicate()
	if filter_search != "":
		items = items.filter(func(item): return item.display_name().contains(filter_search))
	if filter_slot >= 0:
		items = items.filter(func(item): return item.get_template().slot_category == filter_slot)
	if filter_tag != "":
		items = items.filter(func(item): return filter_tag in item.get_template().all_tags())
	match sort_mode:
		1: items.sort_custom(func(a, b): return a.display_name() < b.display_name())
		2: items.sort_custom(func(a, b): return a.get_template().slot_category < b.get_template().slot_category)
		3: items.sort_custom(func(a, b): return a.enhancement_level > b.enhancement_level)
		4: items.sort_custom(func(a, b): return a.fusion_count > b.fusion_count)
		_:
			items.sort_custom(func(a, b): return a.created_at_usec > b.created_at_usec)
	return items


# ---------------------------------------------------------------------------
# 详情 + 对比
# ---------------------------------------------------------------------------

func _item_lines(item: EquipmentInstance) -> Array:
	var t: EquipmentTemplate = item.get_template()
	var lines: Array = []
	if t == null:
		return ["模板缺失"]
	lines.append("[b]%s[/b]（%s·%s）" % [item.display_name(), item.rarity_name(), t.slot_name()])
	lines.append("标签：" + "、".join(PackedStringArray(t.all_tags())))
	if t.category == EquipmentDefs.Category.WEAPON:
		lines.append("武器类型：%s" % EquipmentDefs.WEAPON_TYPE_NAMES[t.weapon_type])
	lines.append("强化等级：+%d" % item.enhancement_level)
	lines.append("基础词条：%s（强化后 %.2f）" % [t.base_affix.describe(), item.base_affix_value()])
	lines.append("吞噬词条：%s" % t.devour_affix.describe())
	lines.append("融合词条（作为材料贡献）：%s" % t.fusion_affix.describe())
	lines.append("融合次数：%d　品质：%s" % [item.fusion_count, item.fusion_tier()])
	if item.gained_fusion_affixes.is_empty():
		lines.append("已获得融合词条：无")
	else:
		var affix_lines: PackedStringArray = []
		for a in item.gained_fusion_affixes:
			affix_lines.append("%s ×%d" % [a.describe(), a.stack_count])
		lines.append("已获得融合词条：" + "、".join(affix_lines))
	if item.is_locked:
		lines.append("[color=#E5484D]已锁定[/color]")
	return lines


func _show_detail() -> void:
	var item := GameState.equipment_manager.find_item(selected_id)
	if item == null:
		return
	var lines := _item_lines(item)
	var equipped_items := _equipped_same_slot(item)
	if not equipped_items.is_empty():
		lines.append("\n[b]—— 与已装备对比 ——[/b]")
		for e in equipped_items:
			lines.append("\n[b]候选 → 已装备：%s[/b]" % e.display_name())
			lines.append_array(_compare_lines(item, e))
	detail_rt.text = "\n".join(PackedStringArray(lines))


func _equipped_same_slot(item: EquipmentInstance) -> Array:
	var t: EquipmentTemplate = item.get_template()
	var result: Array = []
	if t == null:
		return result
	for slot in EquipmentDefs.SlotId.values():
		var e := GameState.equipment_manager.loadout.get_item(slot)
		if e != null and e != item and e.get_template() != null \
				and e.get_template().slot_category == t.slot_category:
			result.append(e)
	return result


func _compare_lines(candidate: EquipmentInstance, equipped: EquipmentInstance) -> Array:
	var ct: EquipmentTemplate = candidate.get_template()
	var et: EquipmentTemplate = equipped.get_template()
	var lines: Array = []
	lines.append(_diff_row("基础词条", ct.base_affix, et.base_affix, candidate.base_affix_value(), equipped.base_affix_value()))
	lines.append(_diff_row("吞噬词条", ct.devour_affix, et.devour_affix))
	lines.append(_diff_row("融合词条", ct.fusion_affix, et.fusion_affix))
	var cd: PackedStringArray = []
	var ed: PackedStringArray = []
	for a in candidate.gained_fusion_affixes:
		cd.append(a.describe())
	for a in equipped.gained_fusion_affixes:
		ed.append(a.describe())
	var c_aff := "、".join(cd) if not cd.is_empty() else "无"
	var e_aff := "、".join(ed) if not ed.is_empty() else "无"
	lines.append(_value_diff("融合次数", candidate.fusion_count, equipped.fusion_count))
	lines.append(_value_diff("强化等级", candidate.enhancement_level, equipped.enhancement_level))
	lines.append("已获得融合词条：%s　→　%s" % [c_aff, e_aff])
	return lines


func _diff_row(title: String, c: AffixData, e: AffixData, c_val: float = 0.0, e_val: float = 0.0) -> String:
	var c_desc := c.describe() if c != null else "无"
	var e_desc := e.describe() if e != null else "无"
	var marker := "＝"
	if c != null and e != null:
		if c.stat == e.stat and c.operation == e.operation:
			marker = _num_marker(c_val if c_val != 0.0 else c.value, e_val if e_val != 0.0 else e.value)
		else:
			marker = "◆"
	return "%s：%s　%s　%s" % [title, c_desc, marker, e_desc]


func _value_diff(title: String, c: float, e: float) -> String:
	return "%s：%d　%s　%d" % [title, int(c), _num_marker(c, e), int(e)]


func _num_marker(c: float, e: float) -> String:
	if absf(c - e) < 0.001:
		return "＝"
	return "▲" if c > e else "▼"


func _rarity_color(rarity: int) -> Color:
	var map := {
		0: Color.WHITE, 1: Color(0.48, 0.79, 0.44), 2: Color(0.36, 0.55, 0.94),
		3: Color(0.69, 0.42, 0.91), 4: Color(0.94, 0.60, 0.24), 5: Color(0.90, 0.28, 0.30),
	}
	return map.get(rarity, Color.WHITE)


# ---------------------------------------------------------------------------
# 3. 强化页（强化 / 融合）
# ---------------------------------------------------------------------------

func _build_enhance_page(page: Control) -> void:
	var subtabs := Button.new()
	subtabs.text = "强化" if enhance_subtab == 0 else "融合"
	subtabs.position = Vector2(0, 0)
	subtabs.pressed.connect(func(): enhance_subtab = 1 - enhance_subtab; refresh_all())
	page.add_child(subtabs)

	var sub_hint := Label.new()
	sub_hint.position = Vector2(90, 4)
	sub_hint.text = "切换：强化 / 融合"
	sub_hint.modulate = Color(0.6, 0.6, 0.6)
	page.add_child(sub_hint)

	if enhance_subtab == 0:
		_build_enhance_tab(page)
	else:
		_build_fusion_tab(page)


func _source_buttons(page: Control) -> void:
	var names := ["背包", "已装备", "全部拥有"]
	for i in 3:
		var btn := Button.new()
		btn.text = names[i]
		btn.position = Vector2(0, 36 + i * 40)
		btn.custom_minimum_size = Vector2(110, 32)
		btn.modulate = Color(1, 1, 1, 1) if i == source_mode else Color(0.6, 0.6, 0.6)
		btn.pressed.connect(func(m = i): source_mode = m; refresh_all())
		page.add_child(btn)


func _source_items() -> Array:
	match source_mode:
		1: return GameState.equipment_manager.loadout.equipped_items()
		2: return GameState.equipment_manager.all_items()
		_: return GameState.equipment_manager.inventory


func _build_enhance_tab(page: Control) -> void:
	_source_buttons(page)
	var list := VBoxContainer.new()
	list.position = Vector2(130, 36)
	list.size = Vector2(340, 480)
	page.add_child(list)
	for item in _source_items():
		_make_item_button(list, item,
			func(id): selected_id = id; refresh_all(),
			func(id, at): _show_context_menu(id, at, true, _equipped_slot_of(id)))

	var panel := RichTextLabel.new()
	panel.bbcode_enabled = true
	panel.position = Vector2(500, 36)
	panel.size = Vector2(430, 380)
	panel.fit_content = true
	page.add_child(panel)

	var target := GameState.equipment_manager.find_item(selected_id)
	if target == null:
		panel.text = "请在左侧选择要强化的装备"
		return
	var t: EquipmentTemplate = target.get_template()
	var base: float = t.base_affix.value
	var before: float = EnhancementRules.enhanced_value(base, target.enhancement_level)
	var after: float = EnhancementRules.enhanced_value(base, target.enhancement_level + 1)
	var cost := EnhancementRules.cost(target.enhancement_level)
	panel.text = "\n".join(PackedStringArray([
		"[b]%s[/b]（强化 +%d）" % [target.display_name(), target.enhancement_level],
		"强化只提升基础词条，固定 +5%/级，无失败",
		"",
		"基础词条（强化前）：%s" % EquipmentDefs.format_modifier(t.base_affix.stat, t.base_affix.operation, before),
		"基础词条（强化后）：%s　▲ +%.2f" % [EquipmentDefs.format_modifier(t.base_affix.stat, t.base_affix.operation, after), after - before],
		"",
		"所需金币：%d" % cost,
		"当前金币：%d → 强化后：%d" % [GameState.gold, GameState.gold - cost],
	]))

	var reason := Label.new()
	reason.position = Vector2(500, 430)
	reason.size = Vector2(430, 40)
	page.add_child(reason)

	var btn := Button.new()
	btn.text = "强化"
	btn.position = Vector2(500, 470)
	btn.custom_minimum_size = Vector2(160, 40)
	btn.pressed.connect(func():
		var result := GameState.enhance_item(target.instance_id)
		if result.ok:
			EventBus.message.emit("强化成功：%s → +%d" % [target.display_name(), result.level_after])
		else:
			reason.text = "无法强化：%s" % result.reason)
	page.add_child(btn)


func _build_fusion_tab(page: Control) -> void:
	# 材料只能来自背包
	var list := VBoxContainer.new()
	list.position = Vector2(130, 36)
	list.size = Vector2(340, 480)
	page.add_child(list)
	var material_pool: Array = GameState.equipment_manager.inventory
	for item in material_pool:
		_make_item_button(list, item,
			func(id): _on_fusion_list_clicked(id),
			func(id, at): _show_context_menu(id, at, true, -1))

	var hint := Label.new()
	hint.text = "先点左侧“主装备”/“材料”槽，再点列表装备放入；材料仅来自背包"
	hint.position = Vector2(500, 36)
	hint.size = Vector2(500, 30)
	page.add_child(hint)

	var main_slot := Button.new()
	main_slot.position = Vector2(500, 72)
	main_slot.custom_minimum_size = Vector2(220, 42)
	page.add_child(main_slot)
	var mat_slot := Button.new()
	mat_slot.position = Vector2(740, 72)
	mat_slot.custom_minimum_size = Vector2(220, 42)
	page.add_child(mat_slot)

	var main_item := GameState.equipment_manager.find_item(fuse_main_id)
	var mat_item := GameState.equipment_manager.find_item(fuse_material_id)
	main_slot.text = "主装备：%s" % (main_item.display_name() if main_item else "（点击选择）")
	mat_slot.text = "材料：%s" % (mat_item.display_name() if mat_item else "（点击选择）")
	main_slot.pressed.connect(func(): _fusion_assign_target = 0; refresh_all())
	mat_slot.pressed.connect(func(): _fusion_assign_target = 1; refresh_all())

	var preview := RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.position = Vector2(500, 130)
	preview.size = Vector2(720, 300)
	preview.fit_content = true
	page.add_child(preview)

	var reason := Label.new()
	reason.position = Vector2(500, 440)
	reason.size = Vector2(500, 40)
	page.add_child(reason)

	var fuse_btn := Button.new()
	fuse_btn.text = "融合"
	fuse_btn.position = Vector2(500, 480)
	fuse_btn.custom_minimum_size = Vector2(160, 40)
	page.add_child(fuse_btn)

	if main_item and mat_item:
		var validation := FusionRules.validate(main_item, mat_item, GameState.gold, true, _is_in_bag(mat_item))
		if validation.status != FusionRules.FuseStatus.OK:
			reason.text = "无法融合：%s" % validation.reason
			fuse_btn.disabled = true
		else:
			reason.text = "融合费用：%d　当前金币：%d → %d　材料将永久消失" % [
				validation.cost, GameState.gold, GameState.gold - validation.cost]
			fuse_btn.pressed.connect(func():
				var result := GameState.fuse_ids(main_item.instance_id, mat_item.instance_id)
				if result.ok:
					fuse_material_id = ""
					EventBus.message.emit("融合完成：%s → %s" % [main_item.display_name(), main_item.fusion_tier()])
				else:
					reason.text = "融合失败：%s" % result.reason)
		var lines := _item_lines(main_item)
		lines.append("")
		lines.append("[b]融合后（预览）[/b]")
		lines.append("融合次数：%d → %d" % [main_item.fusion_count, main_item.fusion_count + 1])
		if mat_item.get_template().id == main_item.get_template().id and not main_item.gained_fusion_affixes.is_empty():
			lines.append("同名升级：随机已有融合词条 ×+1")
		else:
			lines.append("获得融合词条：%s" % mat_item.get_template().fusion_affix.describe())
		preview.text = "\n".join(PackedStringArray(lines))


var _fusion_assign_target := 0


func _on_fusion_list_clicked(id: String) -> void:
	if _fusion_assign_target == 0:
		fuse_main_id = id
	else:
		fuse_material_id = id
	refresh_all()


func _is_in_bag(item: EquipmentInstance) -> bool:
	return GameState.equipment_manager.inventory.has(item)


func _equipped_slot_of(instance_id: String) -> int:
	for slot in EquipmentDefs.SlotId.values():
		var item := GameState.equipment_manager.loadout.get_item(slot)
		if item != null and item.instance_id == instance_id:
			return slot
	return -1


# ---------------------------------------------------------------------------
# 4. 吞噬页（多选 + 当前→本次→最终）
# ---------------------------------------------------------------------------

func _build_devour_page(page: Control) -> void:
	var tools := Label.new()
	tools.text = "吞噬确定成功，不会失败；已装备 / 锁定装备不会出现在列表"
	tools.position = Vector2(0, 0)
	page.add_child(tools)

	var select_all := Button.new()
	select_all.text = "全选当前筛选"
	select_all.position = Vector2(0, 30)
	select_all.pressed.connect(_on_select_all)
	page.add_child(select_all)

	var invert := Button.new()
	invert.text = "反选"
	invert.position = Vector2(140, 30)
	invert.pressed.connect(_on_invert_selection)
	page.add_child(invert)

	var clear := Button.new()
	clear.text = "清空选择"
	clear.position = Vector2(200, 30)
	clear.pressed.connect(_on_clear_selection)
	page.add_child(clear)

	var list := VBoxContainer.new()
	list.position = Vector2(0, 70)
	list.size = Vector2(460, 420)
	page.add_child(list)
	for item in GameState.equipment_manager.inventory:
		if item.is_locked:
			continue
		var cb := CheckButton.new()
		cb.text = "%s（%s）融合%d 强化+%d" % [item.display_name(), item.rarity_name(), item.fusion_count, item.enhancement_level]
		cb.button_pressed = devour_selected.get(item.instance_id, false)
		cb.toggled.connect(func(on, id = item.instance_id): devour_selected[id] = on)
		list.add_child(cb)

	var summary := RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.position = Vector2(480, 70)
	summary.size = Vector2(520, 300)
	summary.fit_content = true
	page.add_child(summary)

	var chosen: Array = []
	for item in GameState.equipment_manager.inventory:
		if devour_selected.get(item.instance_id, false):
			chosen.append(item)
	summary.text = _devour_summary(chosen)

	var devour_btn := Button.new()
	devour_btn.text = "吞噬所选装备（%d 件）" % chosen.size()
	devour_btn.position = Vector2(480, 390)
	devour_btn.custom_minimum_size = Vector2(220, 42)
	devour_btn.disabled = chosen.is_empty()
	devour_btn.pressed.connect(_on_devour_selected)
	page.add_child(devour_btn)


func _on_select_all() -> void:
	for item in _filtered_and_sorted():
		devour_selected[item.instance_id] = true
	refresh_all()


func _on_invert_selection() -> void:
	for item in _filtered_and_sorted():
		devour_selected[item.instance_id] = not devour_selected.get(item.instance_id, false)
	refresh_all()


func _on_clear_selection() -> void:
	devour_selected.clear()
	refresh_all()


func _on_devour_selected() -> void:
	var ids: Array = []
	for item in GameState.equipment_manager.inventory:
		if devour_selected.get(item.instance_id, false):
			ids.append(item.instance_id)
	var result := GameState.devour_ids(ids)
	devour_selected.clear()
	EventBus.message.emit("吞噬完成：%d 件装备" % result.count)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()


func _devour_summary(chosen: Array) -> String:
	var this_totals := {}
	for item in chosen:
		var t: EquipmentTemplate = item.get_template()
		if t == null or t.devour_affix == null:
			continue
		var a: AffixData = t.devour_affix
		if not this_totals.has(a.stat):
			this_totals[a.stat] = {"flat": 0.0, "percent": 0.0}
		if a.operation == EquipmentDefs.ModifierOperation.ADD_PERCENT:
			this_totals[a.stat]["percent"] += a.value
		else:
			this_totals[a.stat]["flat"] += a.value
	var lines: Array = ["已选择 %d 件装备\n" % chosen.size()]
	for stat in this_totals:
		var cur_flat: float = GameState.equipment_manager.devour_totals.get(stat, {}).get("flat", 0.0)
		var cur_percent: float = GameState.equipment_manager.devour_totals.get(stat, {}).get("percent", 0.0)
		var th_flat: float = this_totals[stat]["flat"]
		var th_percent: float = this_totals[stat]["percent"]
		var label := EquipmentDefs.stat_label(stat)
		lines.append("%s：当前 +%.2f → 本次 +%.2f → 之后 +%.2f" % [label, cur_flat, th_flat, cur_flat + th_flat])
		if th_percent != 0.0:
			lines.append("%s%%：当前 +%.2f%% → 本次 +%.2f%% → 之后 +%.2f%%" % [label, cur_percent * 100.0, th_percent * 100.0, (cur_percent + th_percent) * 100.0])
	if lines.size() == 1:
		lines.append("本次没有可吞噬的收益")
	return "\n".join(PackedStringArray(lines))
