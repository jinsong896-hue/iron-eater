class_name PauseMenu
extends CanvasLayer
## 游戏内暂停菜单：《开始页面相关.md》——真暂停；继续/设置/返回主菜单/放弃探索/退出桌面

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SettingsPanelScene := preload("res://scenes/ui/settings_panel.tscn")
const SettlementPanelScene := preload("res://scenes/ui/settlement_panel.tscn")
const ConfirmDialogScript := preload("res://scripts/ui/menu/confirm_dialog.gd")
const TransitionScript := preload("res://scripts/ui/menu/scene_transition.gd")

var paused := false
var _panel: Control
var _settings: Control
var _settlement: SettlementPanel
var _confirm: ConfirmDialog
var _transition: SceneTransition


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	_build_ui()
	EventBus.run_finished.connect(_on_run_finished)


func _build_ui() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(dim)
	var menu := PanelContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.custom_minimum_size = Vector2(360, 0)
	_panel.add_child(menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	menu.add_child(box)
	var title := Label.new()
	title.text = "暂停"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var actions := [
		["继续游戏", func(): toggle_pause()],
		["设置", func(): _settings.visible = true],
		["返回主菜单", _on_return_menu],
		["放弃探索", _on_abandon],
		["退出桌面", _on_quit_desktop],
	]
	for action in actions:
		var btn := Button.new()
		btn.text = action[0]
		btn.custom_minimum_size = Vector2(300, 42)
		btn.add_theme_font_size_override("font_size", 19)
		btn.pressed.connect(action[1])
		box.add_child(btn)
	_panel.visible = false

	_settings = SettingsPanelScene.instantiate()
	_settings.visible = false
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.back_pressed.connect(func(): _settings.visible = false)
	add_child(_settings)

	_settlement = SettlementPanelScene.instantiate()
	add_child(_settlement)
	_settlement.closed.connect(func():
		get_tree().paused = false
		paused = false
		_transition.transition_to(MAIN_MENU_SCENE))

	_confirm = ConfirmDialogScript.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)

	_transition = TransitionScript.new()
	add_child(_transition)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			return
		if _settings.visible:
			_settings.visible = false
			return
		if _panel.visible or not paused:
			toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	_panel.visible = paused
	if paused:
		EventBus.message.emit("游戏已暂停（ESC 继续）")


func _on_return_menu() -> void:
	_confirm.show_confirm("返回主菜单？", "当前探索会被保留，可从存档主页的『继续游戏』恢复。", "返回主菜单", func():
		SaveManager.save_active()
		get_tree().paused = false
		paused = false
		_transition.transition_to(MAIN_MENU_SCENE))


func _on_abandon() -> void:
	_confirm.show_confirm("放弃本次探索？", "本局进度、局内装备、金币与成长将被结算并清除，此操作无法撤销。", "放弃探索", func():
		GameState.finish_run("abandoned"), true)


func _on_quit_desktop() -> void:
	_confirm.show_confirm("退出游戏？", "退出前会保存当前可保存的数据。", "退出至桌面", func():
		SaveManager.save_active()
		get_tree().paused = false
		get_tree().quit(), true)


func _on_run_finished(result: Dictionary) -> void:
	if get_tree().paused:
		get_tree().paused = false
		paused = false
	_panel.visible = false
	_settlement.show_result(result)
