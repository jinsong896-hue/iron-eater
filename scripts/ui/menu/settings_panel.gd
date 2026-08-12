class_name SettingsPanel
extends Control
## 设置面板：《开始页面相关.md》——显示/音频/游戏（主菜单与暂停菜单共用）

signal back_pressed

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _vsync_opt: CheckButton
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _shake_opt: CheckButton


func _ready() -> void:
	_build_ui()
	_refresh_from_settings()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	box.add_child(_row_label("显示"))
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("窗口模式", 0)
	_mode_opt.add_item("全屏", 1)
	_mode_opt.add_item("无边框窗口", 2)
	box.add_child(_mode_opt)
	_res_opt = OptionButton.new()
	for r in ["1280x720", "1600x900", "1920x1080"]:
		_res_opt.add_item(r)
	box.add_child(_res_opt)
	_vsync_opt = CheckButton.new()
	_vsync_opt.text = "垂直同步"
	box.add_child(_vsync_opt)

	box.add_child(_row_label("音频"))
	_master_slider = _slider_row(box, "主音量")
	_music_slider = _slider_row(box, "音乐音量")
	_sfx_slider = _slider_row(box, "音效音量")

	box.add_child(_row_label("游戏"))
	_shake_opt = CheckButton.new()
	_shake_opt.text = "屏幕震动"
	box.add_child(_shake_opt)

	var reset := Button.new()
	reset.text = "恢复默认"
	reset.custom_minimum_size = Vector2(160, 38)
	reset.pressed.connect(func():
		SettingsManager.reset_defaults()
		_refresh_from_settings())
	box.add_child(reset)

	var back := Button.new()
	back.text = "保存并返回（ESC）"
	back.custom_minimum_size = Vector2(160, 38)
	back.pressed.connect(_on_back)
	box.add_child(back)


func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(1.0, 0.85, 0.5)
	return l


func _slider_row(parent: VBoxContainer, label: String) -> HSlider:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(220, 0)
	h.add_child(slider)
	parent.add_child(h)
	return slider


func _refresh_from_settings() -> void:
	var disp: Dictionary = SettingsManager.settings["display"]
	match disp.get("window_mode", "windowed"):
		"fullscreen": _mode_opt.select(1)
		"borderless": _mode_opt.select(2)
		_: _mode_opt.select(0)
	var res := str(disp.get("resolution", "1280x720"))
	for i in _res_opt.item_count:
		if _res_opt.get_item_text(i) == res:
			_res_opt.select(i)
	_vsync_opt.button_pressed = disp.get("vsync", true)
	var audio: Dictionary = SettingsManager.settings["audio"]
	_master_slider.value = audio.get("master", 0.8)
	_music_slider.value = audio.get("music", 0.8)
	_sfx_slider.value = audio.get("sfx", 0.9)
	_shake_opt.button_pressed = SettingsManager.settings["game"].get("screen_shake", true)


func _collect() -> void:
	SettingsManager.set_value("display", "window_mode", ["windowed", "fullscreen", "borderless"][_mode_opt.selected])
	SettingsManager.set_value("display", "resolution", _res_opt.get_item_text(_res_opt.selected))
	SettingsManager.set_value("display", "vsync", _vsync_opt.button_pressed)
	SettingsManager.set_value("audio", "master", _master_slider.value)
	SettingsManager.set_value("audio", "music", _music_slider.value)
	SettingsManager.set_value("audio", "sfx", _sfx_slider.value)
	SettingsManager.set_value("game", "screen_shake", _shake_opt.button_pressed)
	SettingsManager.save_settings()


func _on_back() -> void:
	_collect()
	back_pressed.emit()
