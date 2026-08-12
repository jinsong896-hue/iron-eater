extends SceneTree
## 开始页面系统逻辑测试：职业目录、三存档（含备份恢复）、设置持久化

const SaveManagerScript := preload("res://scripts/core/save_manager.gd")
const SettingsManagerScript := preload("res://scripts/core/settings_manager.gd")

var failed := 0


func _init() -> void:
	_test_catalog()
	_test_save_manager()
	_test_settings_manager()
	if failed == 0:
		print("ALL MENU TESTS PASSED")
		quit(0)
	else:
		print("MENU TESTS FAILED: %d" % failed)
		quit(1)


func _test_catalog() -> void:
	_check(GameCatalog.CLASSES.size() == 5, "五职业目录")
	_check(GameCatalog.class_info("monk").name == "武僧", "武僧数据")
	_check(GameCatalog.mode_info("story").locked, "剧情模式锁定")
	_check(GameCatalog.difficulty_info("hard").mult > 1.0, "困难难度倍率")


func _test_save_manager() -> void:
	var sm = SaveManagerScript.new()
	var slot := 3
	sm.delete_save(slot)
	_check(not sm.has_save(slot), "初始无存档")
	var data := sm.create_save(slot)
	_check(sm.has_save(slot), "创建存档")
	_check(data.get("save_version", 0) == SaveManager.SAVE_VERSION, "存档版本号")
	data["progression"]["highest_floor"] = 6
	data["currencies"]["memory_fragments"] = 42
	sm.write_save(slot, data)
	var loaded := sm.load_save(slot)
	_check(loaded.get("progression", {}).get("highest_floor", 0) == 6, "读写回环")
	_check(loaded.get("currencies", {}).get("memory_fragments", 0) == 42, "局外货币保存")
	_check(int(loaded.get("save_revision", 0)) >= 2, "版本修订递增")
	# 备份恢复：破坏主档后应回退 .bak
	var main_path := sm.slot_path(slot)
	var f := FileAccess.open(main_path, FileAccess.WRITE)
	f.store_string("{broken json")
	f.close()
	var recovered := sm.load_save(slot)
	_check(recovered.get("save_version", -1) == SaveManager.SAVE_VERSION and not recovered.is_empty(), "主档损坏回退备份")
	sm.delete_save(slot)
	_check(not sm.has_save(slot), "删除存档")


func _test_settings_manager() -> void:
	var mgr = SettingsManagerScript.new()
	mgr.settings = {
		"display": {"window_mode": "windowed", "resolution": "1280x720", "vsync": true},
		"audio": {"master": 0.8, "music": 0.8, "sfx": 0.9},
		"control": {"mouse_sens": 1.0, "gamepad_sens": 1.0, "vibration": true},
		"game": {"damage_numbers": true, "screen_shake": true},
	}
	mgr.set_value("audio", "music", 0.35)
	mgr.set_value("display", "window_mode", "fullscreen")
	mgr.save_settings()
	var mgr2 = SettingsManagerScript.new()
	mgr2.load_settings()
	_check(absf(float(mgr2.get_value("audio", "music", 0.0)) - 0.35) < 0.001, "设置持久化（音乐音量）")
	_check(mgr2.get_value("display", "window_mode", "") == "fullscreen", "设置持久化（窗口模式）")
	mgr2.reset_defaults()
	_check(mgr2.get_value("audio", "music", 0.0) == 0.8, "恢复默认")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		print("  [FAIL] %s" % name)
		failed += 1
