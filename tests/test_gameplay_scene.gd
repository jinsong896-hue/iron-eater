extends Node
## 成品流程集成测试（游戏模式运行）：玩家血量/死亡、难度缩放、Boss 门控与通关流程
## 运行：godot --headless --path E:\unity --scene res://tests/test_gameplay_scene.tscn

const PlayerScene := preload("res://scenes/player.tscn")
const ChaserScene := preload("res://scenes/dungeon/chaser_enemy.tscn")
const ManagerScript := preload("res://scripts/dungeon/dungeon_manager.gd")
const GeneratorScript := preload("res://scripts/dungeon/dungeon_generator.gd")

var failed := 0
var run_result := {}


func _ready() -> void:
	EventBus.run_finished.connect(func(result): run_result = result)
	await get_tree().process_frame
	await _test_player_hp_and_death()
	await _test_difficulty_scaling()
	await _test_boss_gating()
	if failed == 0:
		print("ALL GAMEPLAY TESTS PASSED")
		get_tree().quit(0)
	else:
		print("GAMEPLAY TESTS FAILED: %d" % failed)
		get_tree().quit(1)


func _test_player_hp_and_death() -> void:
	var player = PlayerScene.instantiate()
	get_tree().root.add_child(player)
	await get_tree().process_frame
	GameState.reset_run()
	var before := GameState.attributes.hp
	player.take_damage(10.0)
	_check(absf(GameState.attributes.hp - (before - 10.0)) < 0.01, "玩家受击扣血")
	GameState.attributes.hp = 5.0
	run_result = {}
	player.take_damage(50.0)
	await get_tree().process_frame
	_check(not run_result.is_empty() and run_result.get("reason", "") == "defeated", "玩家死亡触发结算")
	player.queue_free()
	await get_tree().process_frame


func _test_difficulty_scaling() -> void:
	GameState.run_info["difficulty"] = "hard"
	var chaser = ChaserScene.instantiate()
	get_tree().root.add_child(chaser)
	await get_tree().process_frame
	_check(absf(chaser.max_hp - 80.0 * 1.3) < 0.01, "困难难度敌人生命 ×1.3")
	_check(absf(chaser.contact_damage - 12.0 * 1.3) < 0.01, "困难难度敌人伤害 ×1.3")
	chaser.queue_free()
	GameState.run_info["difficulty"] = "normal"
	await get_tree().process_frame


func _test_boss_gating() -> void:
	GameState.run_info["floor"] = 1
	GameState.run_info["seed"] = 0
	var gen = GeneratorScript.new()
	gen.name = "DungeonGenerator"
	var mgr = ManagerScript.new()
	mgr.add_child(gen)
	get_tree().root.add_child(mgr)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(mgr.current_layer == 1, "初始层为第 1 层")
	_check(not mgr.boss_cleared, "初始未击败 Boss")
	mgr.next_layer()
	_check(mgr.current_layer == 1, "未击败 Boss 时禁止进入下一层")
	gen.template_room_cleared.emit(RoomData.RoomType.BOSS)
	await get_tree().process_frame
	_check(mgr.boss_cleared, "击败 Boss 后解锁下一层")
	mgr.next_layer()
	_check(mgr.current_layer == 2, "击败 Boss 后可进入第 2 层")
	_check(int(GameState.run_info.get("floor", 1)) == 2, "楼层写入本局信息")
	mgr.queue_free()
	await get_tree().process_frame


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
