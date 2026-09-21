extends Node
## 设置面板测试：打开/关闭/暂停接管/模态/自动拾取开关持久化
## 运行：godot --headless --path E:\unity --scene res://tests/test_settings_panel.tscn

## 私有成员访问一律经 `TestProbe`（重构搬方法时只改 probe，本文件零改动）
var probe := TestProbe.new()

var failed := 0

@onready var panel: Control = $SettingsPanel
@onready var pause_menu: CanvasLayer = $PauseMenu


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("SETTINGS PANEL TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame

	await _test_group_registration()
	await _test_in_game_open_close()
	await _test_auto_pickup_toggle()
	await _test_tabs()
	await _test_pause_menu_settings_button()

	if failed == 0:
		print("ALL SETTINGS PANEL TESTS PASSED")
		get_tree().quit(0)
	else:
		print("SETTINGS PANEL TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 面板与暂停菜单都应在组里（跨场景查找靠它）
func _test_group_registration() -> void:
	_check(panel.is_in_group("settings_panel"), "设置面板登记 settings_panel 组")
	_check(pause_menu.is_in_group("pause_menu"), "暂停菜单登记 pause_menu 组")
	_check(panel.process_mode == Node.PROCESS_MODE_ALWAYS,
		"设置面板暂停时仍可交互")


## 游戏内打开：接管暂停 + 模态；关闭：还原 + 交还暂停菜单
func _test_in_game_open_close() -> void:
	pause_menu.visible = true
	panel.open(true)
	await get_tree().process_frame

	_check(panel.visible, "打开后面板可见")
	_check(get_tree().paused, "打开后游戏暂停")
	_check(panel.is_in_group("modal_ui"), "打开后登记 modal_ui（Esc 不会叠加暂停菜单）")

	panel.close()
	await get_tree().process_frame
	_check(not panel.visible, "关闭后面板隐藏")
	_check(not get_tree().paused, "关闭后恢复运行")
	_check(not panel.is_in_group("modal_ui"), "关闭后退出 modal_ui")
	_check(pause_menu.visible, "关闭后交还暂停菜单")


## 自动拾取开关：勾选后写入 SettingsManager
func _test_auto_pickup_toggle() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		_check(false, "SettingsManager 可用")
		return
	var chk: CheckButton = panel.get_node_or_null("VBox/Pages/GamePage/ChkAutoPickup")
	_check(chk != null, "游戏页存在自动拾取复选框")
	if chk == null:
		return

	sm.set_setting("auto_pickup", false)
	chk.button_pressed = true
	chk.toggled.emit(true)
	await get_tree().process_frame
	_check(bool(sm.get_setting("auto_pickup")), "勾选后设置写入（自动拾取=开）")

	chk.button_pressed = false
	chk.toggled.emit(false)
	await get_tree().process_frame
	_check(not bool(sm.get_setting("auto_pickup")), "取消勾选后设置写入（自动拾取=关）")


## 页签切换：同一时刻只有一个页面可见
func _test_tabs() -> void:
	var pages := ["DisplayPage", "AudioPage", "ControlPage", "GamePage"]
	var btns := ["BtnDisplay", "BtnAudio", "BtnControl", "BtnGame"]
	for i in btns.size():
		var btn: Button = panel.get_node_or_null("VBox/TabBar/%s" % btns[i])
		if btn == null:
			_check(false, "存在页签按钮 %s" % btns[i])
			continue
		btn.pressed.emit()
		await get_tree().process_frame
		var visible_count := 0
		for p in pages:
			var node: Control = panel.get_node_or_null("VBox/Pages/%s" % p)
			if node and node.visible:
				visible_count += 1
		_check(visible_count == 1, "切到「%s」后恰好 1 页可见（实际 %d）" % [btns[i], visible_count])


## 暂停菜单的「设置」按钮应真的打开面板，而不是只发一条消息
func _test_pause_menu_settings_button() -> void:
	pause_menu.visible = true
	panel.visible = false
	probe.pause_menu_on_settings(pause_menu)
	await get_tree().process_frame
	_check(panel.visible, "暂停菜单「设置」打开面板")
	_check(not pause_menu.visible, "面板打开时暂停菜单让位")
	_check(get_tree().paused, "面板打开时游戏保持暂停")
	panel.close()
	await get_tree().process_frame


func _check(c: bool, name: String) -> void:
	if c:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
