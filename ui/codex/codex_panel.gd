extends Control
## 图鉴 —— 查看全部装备与敌人。
##
## ## 数据源（**只读展示，不改任何游戏状态**）
##
##   · 装备：`EquipmentDB.all_templates()`（542 件：白装克隆 + 策划筛选池）
##   · 敌人：`MonsterDB.all_monsters()`（基础怪各阶段 + 独特怪 + 第 9 层）
##
## ## 与其它面板的约定一致
##
## 本页只做**展示**，不复制任何业务规则（与 special_room_ui / skill_panel 同一约定）。
## 列表内容全部从数据层现取，数据层改了这里自动跟随——
## 不写死任何条目，否则加一件装备就要来改一次 UI。
##
## ## 布局
##
##   顶部：页签（装备 / 敌人）
##   左：列表（可滚动）
##   右：详情（选中项的完整信息）

const COLOR_BG := Color(0.035, 0.039, 0.043, 0.98)
const COLOR_PANEL := Color(0.071, 0.078, 0.086, 0.8)
const COLOR_TEXT := Color(0.914, 0.898, 0.863)
const COLOR_DIM := Color(0.545, 0.545, 0.529)
const COLOR_GOLD := Color(0.71, 0.592, 0.384)

enum Tab { EQUIPMENT, MONSTER }

var _tab := Tab.EQUIPMENT
var _root: Control = null
var _list_box: VBoxContainer = null
var _detail: RichTextLabel = null
var _tab_equip: Button = null
var _tab_monster: Button = null
var _count_label: Label = null
## 当前展示的条目（选中项在列表里的下标）
var _entries: Array = []


func _ready() -> void:
	# **必须 ALWAYS**：打开时会把 get_tree().paused 设成 true，
	# 不设 ALWAYS 时本面板自己也被暂停 → 收不到输入、关不掉
	#（与 skill_panel / settings_panel 同一处理）。
	process_mode = PROCESS_MODE_ALWAYS
	add_to_group("codex_panel")
	visible = false
	_build_layout()


## 打开面板
func open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true


## 关闭面板
func close() -> void:
	visible = false
	get_tree().paused = false


## 是否处于打开态（供主菜单判断）
func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("toggle_inventory"):
		close()
		get_viewport().set_input_as_handled()


# ============================================================
# 布局
# ============================================================

func _build_layout() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# —— 顶栏：标题 + 页签 + 计数 ——
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)

	var title := Label.new()
	title.text = "图 鉴"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	top.add_child(title)

	_tab_equip = Button.new()
	_tab_equip.text = "装备"
	_tab_equip.toggle_mode = true
	_tab_equip.pressed.connect(func(): _switch_tab(Tab.EQUIPMENT))
	top.add_child(_tab_equip)

	_tab_monster = Button.new()
	_tab_monster.text = "敌人"
	_tab_monster.toggle_mode = true
	_tab_monster.pressed.connect(func(): _switch_tab(Tab.MONSTER))
	top.add_child(_tab_monster)

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", COLOR_DIM)
	top.add_child(_count_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var btn_close := Button.new()
	btn_close.text = "关闭 (Esc)"
	btn_close.pressed.connect(close)
	top.add_child(btn_close)

	# —— 主体：左列表 + 右详情 ——
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	col.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_list_box)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)

	var dm := MarginContainer.new()
	dm.add_theme_constant_override("margin_left", 16)
	dm.add_theme_constant_override("margin_right", 16)
	dm.add_theme_constant_override("margin_top", 12)
	dm.add_theme_constant_override("margin_bottom", 12)
	detail_panel.add_child(dm)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.add_theme_color_override("default_color", COLOR_TEXT)
	dm.add_child(_detail)


# ============================================================
# 页签切换
# ============================================================

func _switch_tab(t: int) -> void:
	_tab = t
	_tab_equip.button_pressed = t == Tab.EQUIPMENT
	_tab_monster.button_pressed = t == Tab.MONSTER
	_refresh()


func _refresh() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		c.queue_free()
	_entries.clear()
	_detail.text = "← 从左侧选择一项查看详情"

	if _tab == Tab.EQUIPMENT:
		_build_equipment_list()
	else:
		_build_monster_list()


# ============================================================
# 装备列表
# ============================================================

func _build_equipment_list() -> void:
	var EDB = load("res://data/equipment/equipment_db.gd")
	var ED = load("res://data/equipment/equipment_defs.gd")
	EDB.init_equipment_db()
	var all: Array = EDB.all_templates()
	# 按稀有度排序（高稀有度在前），同级按名字
	all.sort_custom(func(a, b):
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return str(a.display_name) < str(b.display_name))
	_entries = all
	_count_label.text = "共 %d 件" % all.size()
	for t in all:
		var b := Button.new()
		var rc: Color = ED.RARITY_COLORS.get(t.rarity, Color.WHITE)
		b.text = "%s  %s" % [ED.rarity_name(t.rarity), str(t.display_name)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", rc)
		b.pressed.connect(_show_equipment.bind(t))
		_list_box.add_child(b)
	# 默认展示第一件
	if not all.is_empty():
		_show_equipment(all[0])


func _show_equipment(t) -> void:
	if t == null:
		return
	var EDB = load("res://data/equipment/equipment_db.gd")
	var ED = load("res://data/equipment/equipment_defs.gd")
	var rc: Color = ED.RARITY_COLORS.get(t.rarity, Color.WHITE)
	var lines: Array = []
	lines.append("[font_size=24][color=#%s]%s[/color][/font_size]" % [
		rc.to_html(false), str(t.display_name)])
	lines.append("[color=#8b8b87]%s · %s[/color]" % [
		ED.rarity_name(t.rarity), ED.slot_name(int(t.slot))])
	if not str(t.weapon_type).is_empty():
		lines.append("武器类型：%s" % str(t.weapon_type))
	if t.tags.size() > 0:
		lines.append("标签：%s" % ", ".join(t.tags))
	lines.append("")
	lines.append("[color=#b5a37f]【基础属性】[/color]")
	lines.append(_affix_line(t.base_affix, true))
	lines.append("[color=#b5a37f]【自有词条】[/color]")
	lines.append(_affix_line(t.own_affix, false))
	lines.append("[color=#b5a37f]【吞噬词条】[/color]")
	lines.append(_affix_line(t.devour_affix, false))
	lines.append("[color=#b5a37f]【融合词条】[/color]")
	lines.append(_affix_line(t.fusion_affix, false))
	# 装备技能（若有）
	var ES = load("res://data/equipment/equipment_skills.gd")
	var sk: Dictionary = ES.skill_of_equipment(str(t.display_name), int(t.rarity))
	if not sk.is_empty():
		lines.append("")
		lines.append("[color=#b5a37f]【装备技能】[/color]")
		lines.append("%s（%s，冷却 %.0f 秒）" % [
			str(sk.get("name", "")), str(sk.get("kind", "")), float(sk.get("cooldown", 0.0))])
		lines.append("[color=#8b8b87]%s[/color]" % str(sk.get("desc", "")))
	lines.append("")
	lines.append("[color=#6f6f6b]掉落时随机生成 1~4 条随机词条（无法升级/转移）[/color]")
	_detail.text = "\n".join(lines)


## 词条 → 可读文本。base=true 时按「基础属性」口径（固定值也显示）。
func _affix_line(a, is_base: bool) -> String:
	if a == null:
		return "[color=#6f6f6b]—[/color]"
	var AS = load("res://data/attributes/attribute_system.gd")
	var name: String = ""
	if int(a.stat) >= 100:
		# 扩展修饰量（吸血/反伤/格挡…）
		var EDB = load("res://data/equipment/equipment_db.gd")
		var key: String = EDB.special_out_key(int(a.stat))
		name = _special_name(key)
	else:
		name = str(AS.STAT_NAMES.get(int(a.stat), "属性%d" % int(a.stat)))
	var val: String = ""
	if a.operation == 1:   # AffixData.Operation.PERCENT
		val = "%.0f%%" % (float(a.value) * 100.0)
	else:
		val = "%.1f" % float(a.value)
	# 触发条件后缀
	var trig := int(a.trigger) if "trigger" in a else 0
	var suffix: String = ""
	if trig > 0:
		var AD = load("res://data/equipment/affix_data.gd")
		suffix = "  [color=#8b8b87]（%s触发[/color]" % str(AD.TRIGGER_NAMES.get(trig, ""))
		if float(a.duration) > 0.0:
			suffix += "[color=#8b8b87]，持续 %.0f 秒[/color]" % float(a.duration)
		if int(a.stack_max) > 0:
			suffix += "[color=#8b8b87]，最多 %d 层[/color]" % int(a.stack_max)
		suffix += "[color=#8b8b87]）[/color]"
	return "%s +%s%s" % [name, val, suffix]


## 扩展修饰量 key → 中文名
func _special_name(key: String) -> String:
	var m := {
		"life_steal": "生命偷取", "knockback_pct": "击退距离",
		"debuff_dur_pct": "负面时长", "elem_pen_pct": "元素穿透",
		"reflect_pct": "伤害反弹", "execute_bonus": "处决线",
		"elem_resist_pct": "元素抗性", "gold_gain_pct": "金币获取",
		"sell_price_pct": "出售价格", "key_drop_pct": "钥匙碎片掉落",
		"block_pct": "格挡率", "dodge_pct": "闪避率",
		"ctrl_resist_pct": "受控时长减免", "cd_refresh_pct": "击杀刷新冷却",
		"drop_rate_pct": "装备掉落率", "pickup_range_pct": "拾取范围",
		"summon_dmg_pct": "召唤物伤害", "elem_dmg_pct": "元素伤害",
		"true_dmg_pct": "真实伤害", "exp_gain_pct": "经验获取",
		"summon_limit": "召唤物上限",
	}
	return str(m.get(key, key))


# ============================================================
# 敌人列表
# ============================================================

func _build_monster_list() -> void:
	var MDB = load("res://data/monsters/monster_db.gd")
	MDB.init()
	var all: Array = MDB.all_monsters()
	all.sort_custom(func(a, b):
		return str(a.get("name", "")) < str(b.get("name", "")))
	_entries = all
	_count_label.text = "共 %d 种" % all.size()
	for m in all:
		var b := Button.new()
		b.text = str(m.get("name", str(m.get("id", "?"))))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_monster.bind(m))
		_list_box.add_child(b)
	if not all.is_empty():
		_show_monster(all[0])


func _show_monster(m) -> void:
	if m == null:
		return
	var lines: Array = []
	lines.append("[font_size=24][color=#e6e5dc]%s[/color][/font_size]" % str(m.get("name", "?")))
	lines.append("[color=#8b8b87]%s[/color]" % str(m.get("id", "")))
	lines.append("")
	lines.append("[color=#b5a37f]【基础数值】[/color]")
	lines.append("生命值　　%.0f" % float(m.get("hp", 0)))
	lines.append("攻击力　　%.0f" % float(m.get("atk", 0)))
	lines.append("防御力　　%.0f" % float(m.get("defense", 0)))
	lines.append("移动速度　%.0f%%" % float(m.get("speed_pct", 0)))
	lines.append("攻击间隔　%.1f 秒" % float(m.get("attack_interval", 0)))
	lines.append("攻击距离　%.1f" % float(m.get("attack_range", 0)))
	var dodge := float(m.get("dodge_pct", 0.0))
	if dodge > 0.0:
		lines.append("闪避率　　%.0f%%" % (dodge * 100.0))
	lines.append("")
	lines.append("[color=#b5a37f]【行为】[/color]")
	lines.append("AI 类型：%s" % str(m.get("ai", "—")))
	# 机制（special）
	var sp = m.get("special", {})
	if sp is Dictionary and not sp.is_empty():
		lines.append("")
		lines.append("[color=#b5a37f]【专属机制】[/color]")
		for k in sp:
			lines.append("· %s：%s" % [str(k), str(sp[k])])
	# 词缀
	var af = m.get("affixes", [])
	if af is Array and not af.is_empty():
		lines.append("")
		lines.append("[color=#b5a37f]【词缀】[/color]")
		lines.append(", ".join(af))
	_detail.text = "\n".join(lines)
