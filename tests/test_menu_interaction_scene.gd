extends Node
## 主菜单交互集成测试（游戏模式）：验证面板可见性与按钮点击真实生效
## 运行：godot --headless --path E:\unity --scene res://tests/test_menu_interaction_scene.tscn
## 注意：脚本错误会使函数中止但不计 failed —— 断言失败必须显式 _check，不要依赖属性访问报错

## 私有成员访问一律经 `TestProbe`（重构搬方法时只改 probe，本文件零改动）
var probe := TestProbe.new()

var failed := 0
@onready var menu: Control = $MainMenu


func _ready() -> void:
	# 清空全部槽位（旧档残留的 has_active_run 会干扰断言）
	for slot in 3:
		SaveManager.delete(slot)
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("MENU INTERACTION TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()
	await get_tree().process_frame
	await _test_initial_state()
	await _test_open_save_select_and_back()
	await _test_settings_and_back()
	await _test_create_save_enter_profile()
	await _test_new_game_panel()
	for slot in 3:
		SaveManager.delete(slot)
	if failed == 0:
		print("ALL MENU INTERACTION TESTS PASSED")
		get_tree().quit(0)
	else:
		print("MENU INTERACTION TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 初始状态：主菜单可见，其他面板隐藏
func _test_initial_state() -> void:
	_check(menu.main_panel.visible, "主菜单面板初始可见")
	_check(not menu.save_panel.visible, "存档面板初始隐藏")
	_check(not menu.new_game_panel.visible, "新游戏面板初始隐藏")
	_check(not menu.settings_panel.visible, "设置面板初始隐藏")


## 主菜单 → 存档选择 → 返回
func _test_open_save_select_and_back() -> void:
	menu.btn_start.pressed.emit()
	await get_tree().process_frame
	_check(menu.save_panel.visible, "点击『开始游戏』进入存档选择")
	_check(not menu.main_panel.visible, "主菜单面板隐藏")
	probe.menu_go_back(menu)
	await get_tree().process_frame
	_check(menu.main_panel.visible, "返回后主菜单可见")


## 主菜单 → 设置 → 返回
func _test_settings_and_back() -> void:
	menu.btn_settings.pressed.emit()
	await get_tree().process_frame
	_check(menu.settings_panel.visible, "设置面板可见")
	probe.menu_go_back(menu)
	await get_tree().process_frame
	_check(menu.main_panel.visible, "ESC 从设置返回主菜单")


## 空档创建存档 → 刷新出『进入』按钮 → 进入存档主页
func _test_create_save_enter_profile() -> void:
	menu.btn_start.pressed.emit()
	await get_tree().process_frame
	_check(menu.save_panel.visible, "进入存档选择")

	# 空存档卡：显示『＋ 创建存档』按钮
	var create_btn := _find_button(menu.save_panel, "创建存档")
	_check(create_btn != null, "空存档卡有『创建存档』按钮")
	if create_btn:
		create_btn.pressed.emit()
		await get_tree().process_frame
	# queue_free 是延迟的，多等一帧让旧卡清空
	await get_tree().process_frame

	_check(SaveManager.load_slot(menu.current_save_slot).get("ok", false), "存档已写入磁盘")
	var enter_btn := _find_button(menu.save_panel, "进入")
	_check(enter_btn != null, "创建后存档卡显示『进入』按钮")
	if enter_btn:
		enter_btn.pressed.emit()
		await get_tree().process_frame
	_check(menu.profile_panel.visible, "点击『进入』后进入存档主页")
	_check(menu.btn_continue != null and menu.btn_continue.disabled, "无进行中探索时『继续游戏』置灰")


## 存档主页 → 新游戏配置 → 返回
func _test_new_game_panel() -> void:
	menu.btn_new_game.pressed.emit()
	await get_tree().process_frame
	_check(menu.new_game_panel.visible, "从存档主页进入新游戏配置")
	_check(menu.char_select.item_count == 5, "新游戏配置显示五职业")
	_check(menu.btn_start_game != null, "存在开始游戏按钮")
	probe.menu_go_back(menu)
	await get_tree().process_frame
	_check(menu.profile_panel.visible, "返回回到存档主页")


## 按文本查找按钮（递归）
func _find_button(root: Node, text_part: String) -> Button:
	for child in root.find_children("", "Button", true, false):
		var b := child as Button
		if b and b.text.contains(text_part):
			return b
	return null


## 断言
func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
