extends Node
## 死亡结算流程集成测试：玩家死亡 → run_finished → 结算面板显示 → 继续回主菜单
## 运行：godot --headless --path E:\unity --scene res://tests/test_death_flow.tscn

var failed := 0


func _ready() -> void:
	var guard := Timer.new()
	guard.wait_time = 30.0
	guard.timeout.connect(func():
		print("DEATH FLOW TESTS FAILED: 超时")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var game_root := get_tree().current_scene.get_node_or_null("MainScene") as Node
	var ui: CanvasLayer = game_root.get_node("UI") if game_root else null
	if ui == null:
		print("  [FAIL] UI 层不存在")
		_finish()
		return

	var settlement: CanvasLayer = ui.get_node_or_null("SettlementPanel")
	_check(settlement != null, "结算面板存在")
	if settlement == null:
		_finish()
		return

	_check(not settlement.visible, "结算面板初始隐藏")

	# 玩家死亡 → finish_run → run_finished → 结算显示
	var player: Node = game_root.get_node_or_null("Player")
	_check(player != null, "玩家存在")
	if player:
		player.take_damage(999999.0)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(settlement.visible, "死亡后结算面板显示")
		_check(settlement.title_label.text == "探 索 终 止", "标题为死亡文案",
			settlement.title_label.text)
		_check(get_tree().paused, "结算时游戏暂停")

		# 先出结果再切场景（切场景会释放本测试节点）
		_finish()
		settlement._on_continue()


## 结束判定
func _finish() -> void:
	if failed == 0:
		print("ALL DEATH FLOW TESTS PASSED")
		get_tree().quit(0)
	else:
		print("DEATH FLOW TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 断言
func _check(cond: bool, name: String, extra: String = "") -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s %s" % [name, extra])
		failed += 1
