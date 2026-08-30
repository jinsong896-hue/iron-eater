extends Node
## 设置管理器 —— HD-2D 重构版
## 管理游戏设置（音效/画面/控制），持久化到 user://settings.cfg

const SETTINGS_PATH := "user://settings.cfg"

# 默认设置
var _settings := {
	"master_volume": 1.0,
	"bgm_volume": 0.8,
	"sfx_volume": 1.0,
	"fullscreen": false,
	"vsync": true,
	"msaa": 2,
	"resolution_scale": 1.0,
	"language": "zh",
	"show_damage_numbers": true,
	"camera_shake": true,
}


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		_save_settings()
		return

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) == OK:
		var data: Dictionary = json.data
		for key in _settings:
			if data.has(key):
				_settings[key] = data[key]

	_apply_settings()


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_settings, "\t"))
	file.close()


func get_setting(key: String):
	return _settings.get(key, null)


func set_setting(key: String, value) -> void:
	if not _settings.has(key):
		return
	_settings[key] = value
	_save_settings()
	_apply_setting(key, value)


func _apply_settings() -> void:
	for key in _settings:
		_apply_setting(key, _settings[key])


func _apply_setting(key: String, value) -> void:
	match key:
		"master_volume":
			var bus_idx := AudioServer.get_bus_index("Master")
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		"bgm_volume":
			var bus_idx := AudioServer.get_bus_index("BGM")
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		"sfx_volume":
			var bus_idx := AudioServer.get_bus_index("SFX")
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
		"fullscreen":
			if value:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			if value:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"msaa":
			RenderingServer.viewport_set_msaa_3d(get_viewport().get_viewport_rid(), value as int)