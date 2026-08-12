class_name MainMenuController
extends Control
## 主菜单状态机：《开始页面相关.md》——主菜单/存档选择/存档主页/新游戏配置/升级/设置

enum MenuState { MAIN, SAVE_SELECT, PROFILE, NEW_GAME, UPGRADE, SETTINGS }

const GAMEPLAY_SCENE := "res://scenes/main.tscn"
const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
const SlotCardScene := preload("res://scenes/ui/save_slot_card.tscn")

var state := MenuState.MAIN
var previous_state := MenuState.MAIN
var active_slot := 0

var panels := {}
var save_cards: Array = []
var confirm_dialog: ConfirmDialog
var transition: SceneTransition

# NewGamePanel 控件
var character_buttons: Array = []
var mode_buttons: Array = []
var difficulty_buttons: Array = []
var class_desc: Label
var new_game_reason: Label
var new_game_start_btn: Button

# ProfilePanel 控件
var profile_title: Label
var profile_info: Label
var continue_btn: Button
var continue_reason: Label


func _ready() -> void:
	theme = UITheme.get_theme()
	_build_background()
	_build_main_panel()
	_build_save_select_panel()
	_build_profile_panel()
	_build_new_game_panel()
	_build_upgrade_panel()
	_build_settings_panel()
	_build_dialog_and_transition()
	_show_state(MenuState.MAIN)


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.texture = UITheme.get_menu_background()
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var title := Label.new()
	title.text = "噬 铁 者"
	title.add_theme_font_size_override("font_size", 64)
	title.modulate = Color(0.85, 0.55, 0.35)
	title.position = Vector2(70, 80)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	add_child(title)
	var version := Label.new()
	version.text = "V0.1.0"
	version.position = Vector2(1130, 690)
	version.modulate = Color(0.6, 0.6, 0.6)
	add_child(version)


func _menu_panel(panel_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.position = Vector2(850, 90)
	panel.custom_minimum_size = Vector2(390, 570)
	panels[panel_name] = panel
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(330, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_main_panel() -> void:
	var box_main := _menu_panel("MainPanel")
	box_main.add_theme_constant_override("separation", 22)
	var opts := [
		["开始游戏", func(): _show_state(MenuState.SAVE_SELECT)],
		["设置", func(): _enter_settings()],
		["退出游戏", func(): confirm_dialog.show_confirm("退出游戏", "确定要退出《噬铁者》吗？", "退出", func(): get_tree().quit(), true)],
	]
	for opt in opts:
		var btn := _menu_button(opt[0])
		btn.pressed.connect(opt[1])
		box_main.add_child(btn)


func _build_save_select_panel() -> void:
	var box := _menu_panel("SaveSelectPanel")
	box.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "选择存档"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var card = SlotCardScene.instantiate()
		card.slot = slot
		card.slot_selected.connect(_on_slot_selected)
		card.slot_delete_requested.connect(_on_slot_delete_requested)
		box.add_child(card)
		save_cards.append(card)
	var back := _menu_button("返回（ESC）")
	back.pressed.connect(func(): _show_state(MenuState.MAIN))
	box.add_child(back)


func _build_profile_panel() -> void:
	var box := _menu_panel("ProfilePanel")
	box.add_theme_constant_override("separation", 14)
	profile_title = Label.new()
	profile_title.add_theme_font_size_override("font_size", 28)
	box.add_child(profile_title)
	profile_info = Label.new()
	profile_info.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(profile_info)

	var start_btn := _menu_button("开始游戏")
	start_btn.pressed.connect(func(): _open_new_game())
	box.add_child(start_btn)

	continue_btn = _menu_button("继续游戏")
	continue_btn.pressed.connect(_on_continue_game)
	box.add_child(continue_btn)
	continue_reason = Label.new()
	continue_reason.modulate = Color(0.7, 0.7, 0.7)
	continue_reason.add_theme_font_size_override("font_size", 13)
	box.add_child(continue_reason)

	var upgrade := _menu_button("升级")
	upgrade.pressed.connect(func(): _show_state(MenuState.UPGRADE))
	box.add_child(upgrade)

	var back := _menu_button("退出当前存档")
	back.pressed.connect(func(): _show_state(MenuState.SAVE_SELECT))
	box.add_child(back)


func _build_new_game_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "NewGamePanel"
	panel.position = Vector2(850, 90)
	panel.custom_minimum_size = Vector2(390, 570)
	panel.custom_maximum_size = Vector2(390, 570)
	panels["NewGamePanel"] = panel
	add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(330, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "开始新的探索"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	# 左右分栏：左侧＝模式选择，右侧＝难度选择
	var middle := HBoxContainer.new()
	middle.name = "ModeDifficultyRow"
	middle.add_theme_constant_override("separation", 16)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(middle)

	var mode_col := VBoxContainer.new()
	mode_col.name = "ModeColumn"
	mode_col.add_theme_constant_override("separation", 8)
	mode_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_col.custom_maximum_size = Vector2(157, 9999)
	middle.add_child(mode_col)
	mode_col.add_child(_section_label("模式"))
	for m in GameCatalog.MODES:
		var btn := _menu_button(m.name)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = m.locked
		btn.pressed.connect(func(md = m): _select_mode(md))
		mode_col.add_child(btn)
		mode_buttons.append(btn)

	var diff_col := VBoxContainer.new()
	diff_col.name = "DifficultyColumn"
	diff_col.add_theme_constant_override("separation", 8)
	diff_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_col.custom_maximum_size = Vector2(157, 9999)
	middle.add_child(diff_col)
	diff_col.add_child(_section_label("难度"))
	for d in GameCatalog.DIFFICULTIES:
		var btn := _menu_button(d.name)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(dd = d): _select_difficulty(dd))
		diff_col.add_child(btn)
		difficulty_buttons.append(btn)

	# 底部一栏：角色选择（五个职业横向排布）
	var char_label := _section_label("角色")
	char_label.name = "CharacterSectionLabel"
	box.add_child(char_label)
	var char_row := HBoxContainer.new()
	char_row.name = "CharacterRow"
	char_row.add_theme_constant_override("separation", 8)
	char_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_row.custom_maximum_size = Vector2(330, 9999)
	box.add_child(char_row)
	for cls in GameCatalog.CLASSES:
		var btn := Button.new()
		btn.text = cls.name
		btn.custom_minimum_size = Vector2(56, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		var btn_tex := load("res://assets/ui-pack/PNG/Blue/Default/button_round_depth_gradient.png") as Texture2D
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			var sb := StyleBoxTexture.new()
			sb.texture = btn_tex
			sb.texture_margin_left = 18.0
			sb.texture_margin_right = 18.0
			sb.texture_margin_top = 10.0
			sb.texture_margin_bottom = 12.0
			sb.content_margin_left = 4.0
			sb.content_margin_right = 4.0
			sb.content_margin_top = 8.0
			sb.content_margin_bottom = 8.0
			match style_name:
				"hover":
					sb.modulate_color = Color(1.25, 1.25, 1.25)
				"pressed":
					sb.modulate_color = Color(0.75, 0.75, 0.8)
					sb.content_margin_top = 10.0
					sb.content_margin_bottom = 6.0
				"disabled":
					sb.modulate_color = Color(0.5, 0.5, 0.55)
			btn.add_theme_stylebox_override(style_name, sb)
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.pressed.connect(func(c = cls): _select_class(c))
		char_row.add_child(btn)
		character_buttons.append(btn)

	class_desc = Label.new()
	class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	class_desc.custom_minimum_size = Vector2(0, 54)
	class_desc.modulate = Color(0.8, 0.8, 0.8)
	class_desc.add_theme_font_size_override("font_size", 14)
	box.add_child(class_desc)

	new_game_reason = Label.new()
	new_game_reason.modulate = Color(0.9, 0.6, 0.5)
	new_game_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_game_reason.add_theme_font_size_override("font_size", 13)
	box.add_child(new_game_reason)

	var action_row := HBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.add_theme_constant_override("separation", 12)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(action_row)

	new_game_start_btn = _menu_button("开始游戏")
	new_game_start_btn.custom_minimum_size = Vector2(0, 44)
	new_game_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game_start_btn.pressed.connect(_on_new_game_start)
	action_row.add_child(new_game_start_btn)

	var back := _menu_button("返回（ESC）")
	back.custom_minimum_size = Vector2(0, 44)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): _show_state(MenuState.PROFILE))
	action_row.add_child(back)


func _build_upgrade_panel() -> void:
	var box := _menu_panel("UpgradePanel")
	box.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = "升级（局外养成）"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var wip := Label.new()
	wip.text = "开发中\n\n天赋树 / 形态解锁 / 局外锻造将在后续版本开放。"
	wip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(wip)
	var back := _menu_button("返回（ESC）")
	back.pressed.connect(func(): _show_state(MenuState.PROFILE))
	box.add_child(back)


func _build_settings_panel() -> void:
	var panel: Control = SettingsPanelScene.instantiate()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	add_child(panel)
	panels["SettingsPanel"] = panel


func _build_dialog_and_transition() -> void:
	confirm_dialog = load("res://scripts/ui/menu/confirm_dialog.gd").new()
	confirm_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(confirm_dialog)
	transition = load("res://scripts/ui/menu/scene_transition.gd").new()
	add_child(transition)


func _menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 44)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func(): AudioManager.play_ui())
	return btn


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.modulate = Color(1.0, 0.85, 0.5)
	return l


func _show_state(next: MenuState) -> void:
	state = next
	for panel_name in panels:
		var panel: Control = panels[panel_name]
		panel.visible = panel_name == _state_panel_name(next)
	if next == MenuState.SAVE_SELECT:
		_refresh_save_cards()
	elif next == MenuState.PROFILE:
		_refresh_profile()
	elif next == MenuState.NEW_GAME:
		_init_new_game_panel()


func _state_panel_name(s: MenuState) -> String:
	match s:
		MenuState.MAIN: return "MainPanel"
		MenuState.SAVE_SELECT: return "SaveSelectPanel"
		MenuState.PROFILE: return "ProfilePanel"
		MenuState.NEW_GAME: return "NewGamePanel"
		MenuState.UPGRADE: return "UpgradePanel"
		MenuState.SETTINGS: return "SettingsPanel"
	return "MainPanel"


func _enter_settings() -> void:
	previous_state = state
	_show_state(MenuState.SETTINGS)


func _refresh_save_cards() -> void:
	for card in save_cards:
		var slot: int = card.slot
		card.setup(SaveManager.load_save(slot), SaveManager.has_save(slot))


func _on_slot_selected(slot: int) -> void:
	active_slot = slot
	if not SaveManager.has_save(slot):
		SaveManager.create_save(slot)
	SaveManager.enter_save(slot)
	_show_state(MenuState.PROFILE)


func _on_slot_delete_requested(slot: int) -> void:
	confirm_dialog.show_confirm("删除存档？", "该操作将永久删除：角色成长、职业解锁、升级内容、剧情进度。\n此操作无法撤销。", "删除", func():
		SaveManager.delete_save(slot)
		_refresh_save_cards(), true)


func _refresh_profile() -> void:
	var save := SaveManager.active_save
	profile_title.text = "存档 %02d" % active_slot
	var run: Dictionary = save.get("current_run", {})
	var cls := GameCatalog.class_info(str(run.get("character", "warrior")))
	profile_info.text = "%s · %s\n最高抵达：第 %d 层　记忆残渣：%d" % [
		cls.name, cls.title, save.get("progression", {}).get("highest_floor", 0),
		save.get("currencies", {}).get("memory_fragments", 0)]
	var has_run: bool = run.get("active", false)
	continue_btn.disabled = not has_run
	continue_reason.text = "当前没有进行中的探索" if not has_run else "第 %d 层 · %s" % [
		run.get("floor", 1), GameCatalog.mode_info(str(run.get("mode", "dungeon"))).name]


func _on_continue_game() -> void:
	var run: Dictionary = SaveManager.active_save.get("current_run", {})
	if not run.get("active", false):
		return
	var info := {
		"character": run.get("character", "warrior"),
		"mode": run.get("mode", "dungeon"),
		"difficulty": run.get("difficulty", "normal"),
		"floor": run.get("floor", 1),
		"seed": run.get("seed", 0),
	}
	GameState.apply_run_info(info)
	transition.transition_to(GAMEPLAY_SCENE)


func _open_new_game() -> void:
	# 有未结束探索时先确认
	var run: Dictionary = SaveManager.active_save.get("current_run", {})
	if run.get("active", false):
		confirm_dialog.show_confirm("开始新的游戏？", "当前仍存在尚未结束的探索。\n开始新游戏将结束上一局游戏，上一局的局内装备、金币与成长将被清除。", "结束上一局并开始", func():
			_show_state(MenuState.NEW_GAME))
	else:
		_show_state(MenuState.NEW_GAME)


func _init_new_game_panel() -> void:
	var run: Dictionary = SaveManager.active_save.get("current_run", {})
	var char_id := str(run.get("character", "warrior")) if run.get("active", false) else "warrior"
	var mode_id := str(run.get("mode", "dungeon")) if run.get("active", false) else "dungeon"
	var diff_id := str(run.get("difficulty", "normal")) if run.get("active", false) else "normal"
	_select_class(GameCatalog.class_info(char_id))
	_select_mode(GameCatalog.mode_info(mode_id))
	_select_difficulty(GameCatalog.difficulty_info(diff_id))
	new_game_reason.text = ""


func _select_class(cls: Dictionary) -> void:
	for i in character_buttons.size():
		character_buttons[i].modulate = Color(1, 1, 1, 1) if i == GameCatalog.CLASSES.find(cls) else Color(0.6, 0.6, 0.6)
	class_desc.text = "%s · %s（%s）\n%s" % [cls.name, cls.title, cls.resource, cls.desc]


func _select_mode(mode: Dictionary) -> void:
	for i in mode_buttons.size():
		mode_buttons[i].modulate = Color(1, 1, 1, 1) if i == GameCatalog.MODES.find(mode) else Color(0.6, 0.6, 0.6)


func _select_difficulty(diff: Dictionary) -> void:
	for i in difficulty_buttons.size():
		difficulty_buttons[i].modulate = Color(1, 1, 1, 1) if i == GameCatalog.DIFFICULTIES.find(diff) else Color(0.6, 0.6, 0.6)
	new_game_reason.text = diff.desc


func _selected_class_id() -> String:
	for i in character_buttons.size():
		if character_buttons[i].modulate.a > 0.99 and character_buttons[i].modulate.r > 0.99:
			return GameCatalog.CLASSES[i].id
	return "warrior"


func _selected_mode_id() -> String:
	for i in mode_buttons.size():
		if mode_buttons[i].modulate.a > 0.99 and mode_buttons[i].modulate.r > 0.99:
			return GameCatalog.MODES[i].id
	return "dungeon"


func _selected_difficulty_id() -> String:
	for i in difficulty_buttons.size():
		if difficulty_buttons[i].modulate.a > 0.99 and difficulty_buttons[i].modulate.r > 0.99:
			return GameCatalog.DIFFICULTIES[i].id
	return "normal"


func _on_new_game_start() -> void:
	var config := {
		"character": _selected_class_id(),
		"mode": _selected_mode_id(),
		"difficulty": _selected_difficulty_id(),
		"floor": 1,
		"seed": randi(),
	}
	var info: Dictionary = config.duplicate()
	SaveManager.start_run(config)
	GameState.apply_run_info(info)
	transition.transition_to(GAMEPLAY_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if confirm_dialog.visible or transition._transitioning:
			return
		_go_back()
		get_viewport().set_input_as_handled()


func _go_back() -> void:
	match state:
		MenuState.SAVE_SELECT: _show_state(MenuState.MAIN)
		MenuState.PROFILE: _show_state(MenuState.SAVE_SELECT)
		MenuState.NEW_GAME: _show_state(MenuState.PROFILE)
		MenuState.UPGRADE: _show_state(MenuState.PROFILE)
		MenuState.SETTINGS:
			var target := previous_state if previous_state != MenuState.SETTINGS else MenuState.MAIN
			_show_state(target)
		_:
			pass
