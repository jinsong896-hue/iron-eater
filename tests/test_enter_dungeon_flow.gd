extends Node
## 回归测试：主菜单 → 新游戏配置 → 开始游戏 → 成功进入地牢初始房间
## 运行：godot --headless --path E:\unity --scene res://tests/test_enter_dungeon_flow.tscn

@onready var menu: Control = $MainMenu

var failed := 0


func _ready() -> void:
	SaveManager.delete_save(1)
	# 场景切换后本节点会被释放；结果由 TestFlowMonitor（autoload）在 --flow-test 时判定
	var guard := get_tree().create_timer(20.0)
	guard.timeout.connect(func():
		print("ENTER DUNGEON FLOW TESTS FAILED: 超时（未进入地牢）")
		get_tree().quit(1))
	await get_tree().process_frame
	SaveManager.create_save(1)
	SaveManager.enter_save(1)
	menu._open_new_game()
	await get_tree().process_frame
	print("  [%s] 从存档主页进入新游戏配置" % ("OK" if menu.panels["NewGamePanel"].visible else "FAIL"))
	menu.new_game_start_btn.pressed.emit()
	print("点击开始游戏，等待场景切换…")
