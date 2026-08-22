extends Node
## 设置系统：《开始页面相关.md》——显示/音频/控制/游戏；user://settings.cfg 持久化

const SETTINGS_PATH := "user://settings.cfg"

var settings := {
	"display": {"window_mode": "windowed", "resolution": "1280x720", "vsync": true, "max_fps": 0},
	"audio": {"master": 0.8, "music": 0.8, "sfx": 0.9},
	"control": {"mouse_sens": 1.0, "gamepad_sens": 1.0, "vibration": true},
	"game": {"damage_numbers": true, "screen_shake": true, "reduce_motion": false},
}


func _ready() -> void:
	load_settings()
	apply_settings()


func get_value(section: String, key: String, default = null):
	var sec: Dictionary = settings.get(section, {})
	return sec.get(key, default)


func set_value(section: String, key: String, value) -> void:
	if not settings.has(section):
		settings[section] = {}
	settings[section][key] = value


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for section in settings:
		for key in settings[section]:
			if cfg.has_section_key(section, key):
				settings[section][key] = cfg.get_value(section, key)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in settings:
		for key in settings[section]:
			cfg.set_value(section, key, settings[section][key])
	cfg.save(SETTINGS_PATH)
	apply_settings()


func reset_defaults() -> void:
	settings = {
		"display": {"window_mode": "windowed", "resolution": "1280x720", "vsync": true, "max_fps": 0},
		"audio": {"master": 0.8, "music": 0.8, "sfx": 0.9},
		"control": {"mouse_sens": 1.0, "gamepad_sens": 1.0, "vibration": true},
		"game": {"damage_numbers": true, "screen_shake": true, "reduce_motion": false},
	}
	save_settings()


func apply_settings() -> void:
	var disp: Dictionary = settings["display"]
	var mode: String = disp.get("window_mode", "windowed")
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var res := str(disp.get("resolution", "1280x720")).split("x")
	if res.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(res[0]), int(res[1])))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if disp.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
	var fps_cap := int(disp.get("max_fps", 0))
	Engine.max_fps = fps_cap if fps_cap > 0 else 0
	var audio: Dictionary = settings["audio"]
	for bus in ["Master", "Music", "SFX"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(audio.get(bus.to_lower(), 0.8)))
