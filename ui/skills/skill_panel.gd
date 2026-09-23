class_name SkillPanel
extends CanvasLayer
## 技能管理页 —— 配置最多 6 个已装备技能。
##
## ## 为什么需要这个页面
##
## 技能**池**来自职业/形态（规格里每形态 0~3 个），而槽位有 6 个。
## 没有管理页时，玩家只能用当前形态自带的那几个，且切形态会打乱配置。
## 有了它，玩家可以把**任意已解锁形态**的技能混搭进 6 个槽
##（`ClassDefs.find_skill` 是全局检索，不限形态）。
##
## ## 布局
##
##   左：6 个技能槽（点击选中，显示已装技能名）
##   右：可选技能池（按职业分组列出全部技能，点击装到当前选中槽）
##
## ## 业务规则在哪
##
## **槽位规则全在 `SkillLoadout`**（唯一/越界/上限），本页只做展示与转发——
## 与 special_room_ui 同一约定：面板不复制业务规则，否则两边会漂移。
##
## 开关：`open()` 设 paused + 登记 modal_ui 组；`close()` 反之。

const GROUP_MODAL := "modal_ui"
const GROUP_SELF := "skill_panel"

const COLOR_BG := Color(0.035, 0.039, 0.043, 0.98)
const COLOR_PANEL := Color(0.071, 0.078, 0.086, 0.8)
const COLOR_TEXT := Color(0.914, 0.898, 0.863)
const COLOR_DIM := Color(0.545, 0.545, 0.529)
const COLOR_GOLD := Color(0.71, 0.592, 0.384)

## 当前选中的槽位（右侧点击技能时装到这里）
var _selected_slot := 0

var _slot_buttons: Array[Button] = []
var _pool_buttons: Array[Button] = []
var _hint: Label = null
var _root: Control = null


func _ready() -> void:
	# **必须 ALWAYS**：open() 会把 get_tree().paused 设成 true，
	# 不设 ALWAYS 时本面板自己也被暂停 → **收不到任何输入、关不掉**
	#（实机症状："页面打开后不能正常关闭，功能不能正常使用"）。
	# 与 pause_menu / settings_panel 同一处理。
	process_mode = PROCESS_MODE_ALWAYS
	add_to_group(GROUP_SELF)
	visible = false
	_build_layout()


## 打开面板
func open() -> void:
	_refresh()
	add_to_group(GROUP_MODAL)
	visible = true
	get_tree().paused = true


## 关闭面板
func close() -> void:
	remove_from_group(GROUP_MODAL)
	visible = false
	get_tree().paused = false


## 是否有模态面板打开（供 pause_menu 判断，与 special_room_ui 同接口）
static func is_modal_active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(GROUP_MODAL):
		if n is CanvasLayer and (n as CanvasLayer).visible:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


## 取技能槽（GameManager 持有）
func _loadout():
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return null
	return gm.get("skill_loadout")


# ============================================================
# 布局
# ============================================================

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var title := Label.new()
	title.text = "技能配置（最多 6 个）"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.position = Vector2(60, 30)
	_root.add_child(title)

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", COLOR_DIM)
	_hint.position = Vector2(60, 68)
	_root.add_child(_hint)

	# 左：6 个槽
	var left := VBoxContainer.new()
	left.position = Vector2(60, 110)
	left.add_theme_constant_override("separation", 8)
	_root.add_child(left)
	for i in SkillLoadout.SLOT_COUNT:
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_slot_pressed.bind(i))
		left.add_child(b)
		_slot_buttons.append(b)

	# 右：技能池
	var right := VBoxContainer.new()
	right.position = Vector2(420, 110)
	right.add_theme_constant_override("separation", 4)
	_root.add_child(right)

	var pool_title := Label.new()
	pool_title.text = "可选技能（点击装到选中槽）"
	pool_title.add_theme_color_override("font_color", COLOR_TEXT)
	right.add_child(pool_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 480)
	right.add_child(scroll)
	var pool := VBoxContainer.new()
	pool.name = "Pool"
	pool.add_theme_constant_override("separation", 2)
	scroll.add_child(pool)
	_build_pool(pool)

	var close_btn := Button.new()
	close_btn.text = "关闭（Tab / Esc）"
	close_btn.position = Vector2(60, 470)
	close_btn.pressed.connect(close)
	_root.add_child(close_btn)


## 技能池：**只列当前职业**的技能。
##
## 用户明确要求："技能管理页面会有角色还没有的其他角色的技能"是问题。
## 跨职业学技能既不符合职业设计，也让页面被无关内容淹没。
## 职业从玩家当前 run_info 读（与 skill_facade.setup_class 同源）。
func _build_pool(pool: VBoxContainer) -> void:
	var cid := _current_class_id()
	var head := Label.new()
	head.text = "— %s —" % str(ClassDefs.CLASSES.get(cid, {}).get("name", cid))
	head.add_theme_color_override("font_color", COLOR_DIM)
	pool.add_child(head)
	# 该职业所有形态的技能去重（同 id 可能出现在多个形态）
	var seen := {}
	for slot in range(ClassDefs.FORM_SLOTS):
		for sk in ClassDefs.skills_of(cid, slot):
			var sid := str(sk.get("id", ""))
			if sid.is_empty() or seen.has(sid):
				continue
			seen[sid] = true
			var b := Button.new()
			b.text = "%s（%s）" % [str(sk.get("name", sid)), str(sk.get("kind", ""))]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_on_pool_pressed.bind(sid))
			pool.add_child(b)
			_pool_buttons.append(b)

	# **装备技能分栏**（装备参考2：装备自带的主动技能）。
	# 与职业技能分开列：它们的来源不同（装备 vs 职业），
	# 玩家需要一眼看出「这个技能是靠哪件装备才有的」。
	var eq_skills: Array = EquipmentSkills.available_for(_equipment_manager())
	if eq_skills.is_empty():
		return
	var head2 := Label.new()
	head2.text = "— 装备技能 —"
	head2.add_theme_color_override("font_color", COLOR_GOLD)
	pool.add_child(head2)
	for sk in eq_skills:
		var sid2 := str(sk.get("id", ""))
		if sid2.is_empty() or seen.has(sid2):
			continue
		seen[sid2] = true
		var b2 := Button.new()
		b2.text = "%s（%s）" % [str(sk.get("name", sid2)), str(sk.get("source_equip", ""))]
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.pressed.connect(_on_pool_pressed.bind(sid2))
		pool.add_child(b2)
		_pool_buttons.append(b2)


## 取装备管理器（装备技能的来源）
func _equipment_manager():
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return null
	return gm.get("equipment_manager")


## 当前职业 id（取不到时回退战士，与 player 的兜底一致）
func _current_class_id() -> String:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return "warrior"
	var ri: Dictionary = gm.get("run_info") if gm.get("run_info") != null else {}
	var cid := str(ri.get("character", "warrior"))
	return cid if not cid.is_empty() else "warrior"


# ============================================================
# 交互
# ============================================================

func _on_slot_pressed(slot: int) -> void:
	_selected_slot = slot
	# 左键点空槽只是选中；右键/再点已装槽则卸下
	var lo = _loadout()
	if lo == null:
		return
	if not str(lo.ids()[slot]).is_empty():
		lo.unequip(slot)
	_refresh()


func _on_pool_pressed(skill_id: String) -> void:
	var lo = _loadout()
	if lo == null:
		return
	var r: Dictionary = lo.equip(skill_id, _selected_slot)
	if not bool(r.get("ok", false)):
		_hint.text = str(r.get("reason", "装备失败"))
		return
	_refresh()


## 刷新槽位与提示文本
func _refresh() -> void:
	var lo = _loadout()
	if lo == null:
		_hint.text = "技能槽未初始化"
		return
	var ids: Array = lo.ids()
	for i in _slot_buttons.size():
		var sid := str(ids[i])
		var label := "空"
		if not sid.is_empty():
			var found := ClassDefs.find_skill(sid)
			var sk: Dictionary = found.get("skill", {})
			label = str(sk.get("name", sid))
		var mark := "▶ " if i == _selected_slot else "   "
		_slot_buttons[i].text = "%s%d. %s" % [mark, i + 1, label]
	_hint.text = "已装备 %d / %d　（点槽位选中；再点已装槽位可卸下）" % [
		lo.equipped_count(), SkillLoadout.SLOT_COUNT]
