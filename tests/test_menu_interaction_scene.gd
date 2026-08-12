extends Node
## 主菜单交互集成测试（游戏模式）：验证面板可见性与按钮点击真实生效
## 运行：godot --headless --path E:\unity --scene res://tests/test_menu_interaction_scene.tscn

var failed := 0
@onready var menu: Control = $MainMenu


func _ready() -> void:
	SaveManager.delete_save(1)
	await get_tree().process_frame
	await _test_main_visible()
	await _test_open_save_select_and_back()
	await _test_settings_and_back()
	await _test_create_save_enter_profile()
	await _test_new_game_panel()
	SaveManager.delete_save(1)
	if failed == 0:
		print("ALL MENU INTERACTION TESTS PASSED")
		get_tree().quit(0)
	else:
		print("MENU INTERACTION TESTS FAILED: %d" % failed)
		get_tree().quit(1)


func _test_main_visible() -> void:
	_check(menu.panels["MainPanel"].visible, "主菜单面板可见")
	_check(not menu.panels["SaveSelectPanel"].visible, "存档面板初始隐藏")
	_check(not menu.panels["NewGamePanel"].visible, "新游戏面板初始隐藏")


func _test_open_save_select_and_back() -> void:
	var start := _find_button(menu.panels["MainPanel"], "开始游戏")
	_check(start != null, "找到『开始游戏』按钮")
	if start:
		start.pressed.emit()
		await get_tree().process_frame
	_check(menu.panels["SaveSelectPanel"].visible, "点击开始游戏进入存档选择")
	_check(menu.panels["MainPanel"].visible == false, "主菜单面板隐藏")
	var back := _find_button(menu.panels["SaveSelectPanel"], "返回")
	_check(back != null, "存档页有返回按钮")
	if back:
		back.pressed.emit()
		await get_tree().process_frame
	_check(menu.panels["MainPanel"].visible, "返回后主菜单可见")


func _test_settings_and_back() -> void:
	var settings := _find_button(menu.panels["MainPanel"], "设置")
	if settings:
		settings.pressed.emit()
		await get_tree().process_frame
	_check(menu.panels["SettingsPanel"].visible, "设置面板可见")
	menu._go_back()
	await get_tree().process_frame
	_check(menu.panels["MainPanel"].visible, "ESC 从设置返回主菜单")


func _test_create_save_enter_profile() -> void:
	var start := _find_button(menu.panels["MainPanel"], "开始游戏")
	start.pressed.emit()
	await get_tree().process_frame
	var card = menu.save_cards[0]
	var create_btn := _find_button(card, "创建存档")
	_check(create_btn != null, "空存档卡有『创建存档』按钮")
	if create_btn:
		create_btn.pressed.emit()
		await get_tree().process_frame
	_check(menu.panels["ProfilePanel"].visible, "创建存档后进入存档主页")
	_check(SaveManager.has_save(1), "存档已写入磁盘")
	var continue_btn := _find_button(menu.panels["ProfilePanel"], "继续游戏")
	_check(continue_btn != null and continue_btn.disabled, "无进行中探索时『继续游戏』置灰")


func _test_new_game_panel() -> void:
	var start := _find_button(menu.panels["ProfilePanel"], "开始游戏")
	start.pressed.emit()
	await get_tree().process_frame
	_check(menu.panels["NewGamePanel"].visible, "从存档主页进入新游戏配置")
	_check(menu.character_buttons.size() == 5, "新游戏配置显示五职业")
	_check(menu.new_game_start_btn != null, "存在开始游戏按钮")
	var back := _find_button(menu.panels["NewGamePanel"], "返回")
	back.pressed.emit()
	await get_tree().process_frame
	_check(menu.panels["ProfilePanel"].visible, "ESC/返回回到存档主页")


func _find_button(root: Node, text_part: String) -> Button:
	for child in root.find_children("", "Button", true, false):
		var b := child as Button
		if b and b.text.contains(text_part):
			return b
	return null


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
