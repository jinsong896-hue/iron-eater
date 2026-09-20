extends Control
## 主菜单控制器 —— HD-2D 重构版
## 完整菜单状态机：主菜单 → 存档选择 → 存档主页 → 新游戏配置 → 升级 → 设置
## ESC 统一返回上一级

enum MenuState {
	MAIN,           # 主菜单
	SAVE_SELECT,    # 存档选择
	PROFILE,        # 存档主页
	NEW_GAME,       # 新游戏配置
	UPGRADE,        # 局外升级
	SETTINGS,       # 设置
}

var current_state: MenuState = MenuState.MAIN
var previous_state: MenuState = MenuState.MAIN
var current_save_slot := 0

# 主菜单
@onready var main_panel: Control = $MainPanel
@onready var btn_start: Button = $MainPanel/VBox/BtnStart
@onready var btn_settings: Button = $MainPanel/VBox/BtnSettings
@onready var btn_quit: Button = $MainPanel/VBox/BtnQuit
@onready var version_label: Label = $MainPanel/VersionLabel
@onready var recent_label: Label = $MainPanel/RecentLabel

# 存档选择
@onready var save_panel: Control = $SaveSelectPanel
@onready var save_title: Label = $SaveSelectPanel/Title
@onready var save_container: VBoxContainer = $SaveSelectPanel/ScrollContainer/SaveList

# 存档主页
@onready var profile_panel: Control = $ProfilePanel
@onready var profile_title: Label = $ProfilePanel/Title
@onready var btn_new_game: Button = $ProfilePanel/VBox/BtnNewGame
@onready var btn_continue: Button = $ProfilePanel/VBox/BtnContinue
@onready var btn_upgrade: Button = $ProfilePanel/VBox/BtnUpgrade
@onready var btn_back_save: Button = $ProfilePanel/VBox/BtnBackSave
@onready var continue_hint: Label = $ProfilePanel/VBox/BtnContinue/Hint

# 新游戏配置
@onready var new_game_panel: Control = $NewGamePanel
@onready var char_select: ItemList = $NewGamePanel/VBox/CharSelect
@onready var form_select: ItemList = $NewGamePanel/VBox/FormSelect
@onready var mode_select: ItemList = $NewGamePanel/VBox/ModeSelect
@onready var difficulty_select: ItemList = $NewGamePanel/VBox/DifficultySelect
## 当前选中的形态槽位（开局写入 run_info，整局固定）
var selected_form := 0
@onready var btn_start_game: Button = $NewGamePanel/VBox/BtnStartGame
@onready var char_desc: Label = $NewGamePanel/VBox/CharDesc

# 升级页
@onready var upgrade_panel: Control = $UpgradePanel
@onready var upgrade_placeholder: Label = $UpgradePanel/Placeholder

# 设置页
@onready var settings_panel: Control = $SettingsPanel

# 确认弹窗
@onready var confirm_dialog: AcceptDialog = $ConfirmDialog

# 选中的配置
var selected_character := "warrior"
var selected_mode := "dungeon"
var selected_difficulty := "normal"


func _ready() -> void:
	# 暂停态下也要能交互。
	#
	# 结算页 `settlement_panel._on_continue()` 是先 `paused = false` 再切场景的，
	# 所以常规「死亡 → 结算 → 回主菜单」不会带着暂停进来。但**不能依赖这条**：
	# 只要有任何一条路径在 paused 仍为 true 时切到主菜单（新加的入口、异常
	# 中断、将来把结算改成延迟切场景），本菜单就会整体冻结——按钮不响应，
	# ESC 也不响应（`_unhandled_input` 同样不跑），表现为「主页面 UI 点不动」。
	#
	# 另外三个菜单（pause / settlement / settings）都设了 ALWAYS，只有本菜单
	# 漏了。对齐即可，不改变任何现有行为。
	process_mode = PROCESS_MODE_ALWAYS
	_setup_main_menu()
	_setup_save_select()
	_setup_profile()
	_setup_new_game()
	_setup_upgrade()
	_setup_settings()
	# 全部子页面建完之后再统一接按钮音：上面几个 _setup_* 会动态建按钮
	#（存档卡的进入/删除/新建、升级页），提前接会漏掉它们。
	AudioManager.connect_buttons(self)
	_switch_state(MenuState.MAIN)


# ============================================================
# 状态切换
# ============================================================

func _switch_state(new_state: MenuState) -> void:
	previous_state = current_state
	current_state = new_state

	# 隐藏所有面板
	main_panel.visible = false
	save_panel.visible = false
	profile_panel.visible = false
	new_game_panel.visible = false
	upgrade_panel.visible = false
	settings_panel.visible = false

	match new_state:
		MenuState.MAIN:
			main_panel.visible = true
			_refresh_main_menu()
		MenuState.SAVE_SELECT:
			save_panel.visible = true
			_refresh_save_list()
		MenuState.PROFILE:
			profile_panel.visible = true
			_refresh_profile()
		MenuState.NEW_GAME:
			new_game_panel.visible = true
			_refresh_new_game()
			if btn_start_game:
				btn_start_game.grab_focus()
		MenuState.UPGRADE:
			upgrade_panel.visible = true
		MenuState.SETTINGS:
			settings_panel.visible = true


func _go_back() -> void:
	match current_state:
		MenuState.MAIN:
			pass  # 主菜单不返回
		MenuState.SAVE_SELECT:
			_switch_state(MenuState.MAIN)
		MenuState.PROFILE:
			_switch_state(MenuState.SAVE_SELECT)
		MenuState.NEW_GAME:
			_switch_state(MenuState.PROFILE)
		MenuState.UPGRADE:
			_switch_state(MenuState.PROFILE)
		MenuState.SETTINGS:
			_switch_state(previous_state)


# ============================================================
# 主菜单
# ============================================================

func _setup_main_menu() -> void:
	if btn_start:
		btn_start.pressed.connect(_on_start_pressed)
	if btn_settings:
		btn_settings.pressed.connect(_on_settings_pressed)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit_pressed)
	if version_label:
		version_label.text = "V0.1.0 HD-2D"


func _refresh_main_menu() -> void:
	# 显示最近存档信息
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("list_slots"):
		var list: Array = sm.list_slots()
		for slot in list:
			if slot.get("exists", false):
				if recent_label:
					recent_label.text = "最近存档：存档 %d\n%s" % [slot["slot"] + 1, slot.get("time", "")]
				return
	if recent_label:
		recent_label.text = ""


func _on_start_pressed() -> void:
	_switch_state(MenuState.SAVE_SELECT)


func _on_settings_pressed() -> void:
	_switch_state(MenuState.SETTINGS)


func _on_quit_pressed() -> void:
	get_tree().quit()


# ============================================================
# 存档选择
# ============================================================

func _setup_save_select() -> void:
	pass


func _refresh_save_list() -> void:
	# 清空列表
	for child in save_container.get_children():
		child.queue_free()

	var sm := get_node_or_null("/root/SaveManager")
	if sm == null or not sm.has_method("list_slots"):
		return

	var slots: Array = sm.list_slots()
	for slot_info in slots:
		var card := _create_save_card(slot_info)
		save_container.add_child(card)


func _create_save_card(slot_info: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 120)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var slot_num: int = slot_info.get("slot", 0)
	var exists: bool = slot_info.get("exists", false)

	var title := Label.new()
	if exists:
		title.text = "存档 %02d" % (slot_num + 1)
	else:
		title.text = "存档 %02d — 空" % (slot_num + 1)
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	if exists:
		var info := Label.new()
		info.text = "角色: %s\n最高层数: %d\n游戏时间: %s" % [
			slot_info.get("name", "未知"),
			slot_info.get("floor", 0),
			slot_info.get("time", "")
		]
		info.add_theme_font_size_override("font_size", 14)
		vbox.add_child(info)

		var btn_row := HBoxContainer.new()
		var enter_btn := Button.new()
		enter_btn.text = "进入"
		enter_btn.pressed.connect(_on_enter_save.bind(slot_num))
		btn_row.add_child(enter_btn)

		var delete_btn := Button.new()
		delete_btn.text = "删除"
		delete_btn.pressed.connect(_on_delete_save.bind(slot_num))
		btn_row.add_child(delete_btn)
		vbox.add_child(btn_row)
	else:
		var create_btn := Button.new()
		create_btn.text = "＋ 创建存档"
		create_btn.pressed.connect(_on_create_save.bind(slot_num))
		vbox.add_child(create_btn)

	return card


func _on_create_save(slot: int) -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("save"):
		sm.save(slot)
		_refresh_save_list()


func _on_enter_save(slot: int) -> void:
	current_save_slot = slot
	_switch_state(MenuState.PROFILE)


func _on_delete_save(slot: int) -> void:
	_show_confirm(
		"删除存档？",
		"存档 %02d 将被永久删除，此操作不可撤销。" % (slot + 1),
		"删除",
		func():
			var sm := get_node_or_null("/root/SaveManager")
			if sm and sm.has_method("delete"):
				sm.delete(slot)
				_refresh_save_list()
	)


# ============================================================
# 存档主页
# ============================================================

func _setup_profile() -> void:
	if btn_new_game:
		btn_new_game.pressed.connect(_on_new_game_pressed)
	if btn_continue:
		btn_continue.pressed.connect(_on_continue_pressed)
	if btn_upgrade:
		btn_upgrade.pressed.connect(_on_upgrade_pressed)
	if btn_back_save:
		btn_back_save.pressed.connect(func(): _switch_state(MenuState.SAVE_SELECT))


func _refresh_profile() -> void:
	if profile_title:
		profile_title.text = "存档 %02d" % (current_save_slot + 1)

	# 检查是否有进行中的游戏
	var sm := get_node_or_null("/root/SaveManager")
	var has_active_run := false
	var floor_num := 1
	if sm and sm.has_method("load_slot"):
		var result: Dictionary = sm.load_slot(current_save_slot)
		if result.get("ok", false):
			var data: Dictionary = result.get("data", {})
			has_active_run = data.get("has_active_run", false)
			floor_num = data.get("floor", 1)

	if btn_continue:
		btn_continue.disabled = not has_active_run
		if continue_hint:
			if has_active_run:
				continue_hint.text = "第 %d 层 · 地下沼泽" % floor_num
			else:
				continue_hint.text = "当前没有进行中的探索"
			continue_hint.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3) if not has_active_run else Color(0.7, 0.65, 0.5))


func _on_new_game_pressed() -> void:
	# 检查是否有未结束的游戏
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("load"):
		var result: Dictionary = sm.load_slot(current_save_slot)
		if result.get("ok", false):
			var data: Dictionary = result.get("data", {})
			if data.get("has_active_run", false):
				_show_confirm(
					"开始新的游戏？",
					"当前仍存在尚未结束的探索。\n开始新游戏将结束上一局游戏，\n上一局的局内装备、金币与成长将被清除。",
					"结束上一局并开始",
					func(): _switch_state(MenuState.NEW_GAME)
				)
				return
	_switch_state(MenuState.NEW_GAME)


func _on_continue_pressed() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var result: Dictionary = sm.load_slot(current_save_slot)
	if result.get("ok", false):
		var data: Dictionary = result.get("data", {})
		# **用 restore_run 而非 start_new_run**：后者是全新开局，
		# 会把存档里的金币/击杀/装备/吞噬全部清零——玩家读档后发现
		# 自己光着身子、金币归零，而存档文件本身看起来完全正常
		# （写进去了，只是从来没人读）。
		if sm.has_method("restore_run"):
			sm.call("restore_run", data)
		else:
			# 兜底：老版本 SaveManager 没有 restore_run 时的降级路径
			var gm := get_node_or_null("/root/GameManager")
			if gm and gm.has_method("start_new_run"):
				gm.start_new_run({
					"character": data.get("character", "warrior"),
					"mode": data.get("mode", "dungeon"),
					"difficulty": data.get("difficulty", "normal"),
					"floor": data.get("floor", 1),
					"seed": data.get("seed", 0),
				})
		var sm2 := get_node_or_null("/root/SceneManager")
		if sm2 and sm2.has_method("change_scene"):
			sm2.change_scene("res://scenes/main.tscn")


func _on_upgrade_pressed() -> void:
	_switch_state(MenuState.UPGRADE)


# ============================================================
# 新游戏配置
# ============================================================

func _setup_new_game() -> void:
	# 职业选择（第一级）。职业名从 ClassDefs 取，避免与数据表两处硬编码打架。
	if char_select:
		for cid in CLASS_ORDER:
			char_select.add_item(ClassDefs.class_name_of(cid))
		char_select.select(0)
		char_select.item_selected.connect(_on_char_selected)

	# 形态选择（第二级）。策划口径：形态是"衍生职业"，开局二选一即定，
	# 整局不再变化——所以做成选人界面的一级，而不是局内可切换的按钮。
	#
	# **不做解锁门禁**（用户明确要求全部直接可选）。ClassDefs.UNLOCK_FLOOR
	# 保留为设计意图记录，但不在这里拦。
	if form_select:
		form_select.item_selected.connect(_on_form_selected)

	# 模式选择
	if mode_select:
		mode_select.add_item("地牢模式")
		mode_select.add_item("剧情模式 (开发中)")
		mode_select.set_item_disabled(1, true)
		mode_select.select(0)

	# 难度选择
	if difficulty_select:
		difficulty_select.add_item("简单")
		difficulty_select.add_item("普通")
		difficulty_select.add_item("困难")
		difficulty_select.select(1)

	if btn_start_game:
		btn_start_game.pressed.connect(_on_start_game_pressed)


func _refresh_new_game() -> void:
	if char_select and char_select.item_count > 0:
		char_select.select(0)
	_on_char_selected(0)


## 职业列表顺序（与 CharSelect 的项顺序一一对应）
const CLASS_ORDER := ["warrior", "mage", "hunter", "judge", "monk"]


## 选职业 → 重建形态列表 + 刷新描述
func _on_char_selected(index: int) -> void:
	if index < 0 or index >= CLASS_ORDER.size():
		return
	selected_character = CLASS_ORDER[index]
	selected_form = 0
	if form_select:
		form_select.clear()
		var forms: Array = ClassDefs.get_class_def(selected_character).get("forms", [])
		for i in forms.size():
			form_select.add_item(str(forms[i].get("name", "形态 %d" % (i + 1))))
		if forms.size() > 0:
			form_select.select(0)
	_refresh_char_desc()


## 选形态 → 刷新描述
func _on_form_selected(index: int) -> void:
	if index < 0:
		return
	selected_form = index
	_refresh_char_desc()


## 描述区：职业定位 + 该形态的专属增益（策划的 gain 原文）
func _refresh_char_desc() -> void:
	if char_desc == null:
		return
	var lines: Array[String] = []
	lines.append("%s — %s" % [
		ClassDefs.class_name_of(selected_character),
		ClassBase.tagline(selected_character)])
	var form := ClassDefs.get_form(selected_character, selected_form)
	if not form.is_empty():
		lines.append("【%s】%s" % [
			str(form.get("name", "")), str(form.get("gain", ""))])
		var sks: Array = form.get("skills", [])
		if sks.is_empty():
			lines.append("技能：无（依靠普攻与形态被动）")
		else:
			var names: Array[String] = []
			for s in sks:
				names.append(str(s.get("name", "")))
			lines.append("技能：" + "、".join(names))
	char_desc.text = "\n".join(lines)


func _on_start_game_pressed() -> void:
	var modes := ["dungeon", "story"]
	var diffs := ["easy", "normal", "hard"]
	selected_mode = modes[mode_select.get_selected_items()[0]] if mode_select.get_selected_items().size() > 0 else "dungeon"
	selected_difficulty = diffs[difficulty_select.get_selected_items()[0]] if difficulty_select.get_selected_items().size() > 0 else "normal"

	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("start_new_run"):
		gm.start_new_run({
			"character": selected_character,
			"form": selected_form,
			"mode": selected_mode,
			"difficulty": selected_difficulty,
			"floor": 1,
			"seed": randi(),
		})

	# 保存到存档
	var sm := get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("save"):
		sm.current_slot = current_save_slot
		sm.save(current_save_slot)

	var sm2 := get_node_or_null("/root/SceneManager")
	if sm2 and sm2.has_method("change_scene"):
		sm2.change_scene("res://scenes/main.tscn")


# ============================================================
# 升级页
# ============================================================

func _setup_upgrade() -> void:
	if upgrade_placeholder:
		upgrade_placeholder.text = "局外养成系统\n\n开发中...\n\n未来将包含：\n· 天赋树\n· 形态解锁\n· 局外锻造\n· 图鉴"


func _setup_settings() -> void:
	# 页签与设置项现在由 settings_panel.gd 自己管理（面板作为独立场景实例化），
	# 主菜单不再重复接线——此前这里连的是内联假壳面板的写死 Label，无实际功能。
	pass


# ============================================================
# 确认弹窗
# ============================================================

func _show_confirm(title: String, body: String, confirm_text: String, on_confirm: Callable) -> void:
	if confirm_dialog == null:
		# 没有绑定弹窗则直接执行
		on_confirm.call()
		return
	confirm_dialog.title = title
	confirm_dialog.dialog_text = body
	confirm_dialog.ok_button_text = confirm_text
	# 断开旧连接
	confirm_dialog.confirmed.disconnect(_on_confirm_action)
	confirm_dialog.confirmed.connect(_on_confirm_action)
	_on_confirm_callback = on_confirm
	confirm_dialog.popup_centered()


var _on_confirm_callback: Callable

func _on_confirm_action() -> void:
	if _on_confirm_callback.is_valid():
		_on_confirm_callback.call()


# ============================================================
# 输入处理
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):  # ESC
		_go_back()
		get_viewport().set_input_as_handled()
