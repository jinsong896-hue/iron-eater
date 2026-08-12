class_name SettingsPanel
extends Control
## 设置面板：《页面相关2.md》页面06——左侧分类 + 右侧设置项；主菜单与暂停菜单共用

signal back_pressed

var _mode_opt: OptionButton
var _res_opt: OptionButton
var _vsync_opt: CheckButton
var _fps_opt: OptionButton
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _shake_opt: CheckButton
var _reduce_motion_opt: CheckButton
var _content: VBoxContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	_build_ui()
	_refresh_from_settings()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 34)
	panel.add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 36)
	margin.add_child(root)

	# 左侧分类
	var cats := VBoxContainer.new()
	cats.custom_minimum_size = Vector2(150, 0)
	cats.add_theme_constant_override("separation", 10)
	root.add_child(cats)
	var cat_title := Label.new()
	cat_title.text = "设置"
	cat_title.add_theme_font_size_override("font_size", 28)
	cats.add_child(cat_title)
	var cat_defs := [["显示", _build_display], ["音频", _build_audio], ["游戏", _build_game]]
	for def in cat_defs:
		var btn := Button.new()
		btn.text = def[0]
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(def[1])
		cats.add_child(btn)

	# 右侧设置内容
	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content_panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	content_panel.add_child(_content)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	root.add_child(actions)
	var reset := Button.new()
	reset.text = "恢复默认"
	reset.custom_minimum_size = Vector2(130, 40)
	reset.pressed.connect(func():
		SettingsManager.reset_defaults()
		_refresh_from_settings()
		ToastManager.notify("设置已恢复默认"))
	actions.add_child(reset)
	var back := Button.new()
	back.text = "保存并返回（ESC）"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(_on_back)
	actions.add_child(back)
	_build_display()


func _build_display() -> void:
	_clear_content()
	_content.add_child(_row_label("显示"))
	_mode_opt = _make_option(["窗口模式", "全屏", "无边框窗口"])
	_content.add_child(_row_item("显示模式", _mode_opt))
	_res_opt = _make_option(["1280x720", "1600x900", "1920x1080"])
	_content.add_child(_row_item("分辨率", _res_opt))
	_vsync_opt = CheckButton.new()
	_vsync_opt.text = "垂直同步"
	_content.add_child(_row_item("垂直同步", _vsync_opt))
	_fps_opt = _make_option(["不限", "30", "60", "120", "144"])
	_content.add_child(_row_item("FPS 上限", _fps_opt))
	_refresh_display()


func _build_audio() -> void:
	_clear_content()
	_content.add_child(_row_label("音频"))
	_master_slider = _slider_row("主音量")
	_music_slider = _slider_row("音乐音量")
	_sfx_slider = _slider_row("音效音量")
	_refresh_audio()


func _build_game() -> void:
	_clear_content()
	_content.add_child(_row_label("游戏"))
	_shake_opt = CheckButton.new()
	_shake_opt.text = "屏幕震动"
	_content.add_child(_row_item("屏幕震动", _shake_opt))
	_reduce_motion_opt = CheckButton.new()
	_reduce_motion_opt.text = "减少动态效果"
	_content.add_child(_row_item("减少动态效果", _reduce_motion_opt))
	_refresh_game()


func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()


func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.modulate = Color(1.0, 0.85, 0.5)
	return l


func _row_item(label: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	h.add_child(control)
	return h


func _make_option(items: Array) -> OptionButton:
	var opt := OptionButton.new()
	for item in items:
		opt.add_item(item)
	opt.custom_minimum_size = Vector2(200, 0)
	return opt


func _slider_row(label: String) -> HSlider:
	var h := _row_item(label, HSlider.new())
	var slider := h.get_child(1) as HSlider
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(220, 0)
	return slider


func _refresh_from_settings() -> void:
	_refresh_display()
	_refresh_audio()
	_refresh_game()


func _refresh_display() -> void:
	if _mode_opt == null:
		return
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
	var fps := str(disp.get("max_fps", 0))
	for i in _fps_opt.item_count:
		if _fps_opt.get_item_text(i) == fps:
			_fps_opt.select(i)


func _refresh_audio() -> void:
	if _master_slider == null:
		return
	var audio: Dictionary = SettingsManager.settings["audio"]
	_master_slider.value = audio.get("master", 0.8)
	_music_slider.value = audio.get("music", 0.8)
	_sfx_slider.value = audio.get("sfx", 0.9)


func _refresh_game() -> void:
	if _shake_opt == null:
		return
	_shake_opt.button_pressed = SettingsManager.settings["game"].get("screen_shake", true)
	_reduce_motion_opt.button_pressed = SettingsManager.settings["game"].get("reduce_motion", false)


func _collect() -> void:
	SettingsManager.set_value("display", "window_mode", ["windowed", "fullscreen", "borderless"][_mode_opt.selected])
	SettingsManager.set_value("display", "resolution", _res_opt.get_item_text(_res_opt.selected))
	SettingsManager.set_value("display", "vsync", _vsync_opt.button_pressed)
	var fps := _fps_opt.get_item_text(_fps_opt.selected)
	SettingsManager.set_value("display", "max_fps", int(fps) if fps.is_valid_int() else 0)
	SettingsManager.set_value("audio", "master", _master_slider.value)
	SettingsManager.set_value("audio", "music", _music_slider.value)
	SettingsManager.set_value("audio", "sfx", _sfx_slider.value)
	SettingsManager.set_value("game", "screen_shake", _shake_opt.button_pressed)
	SettingsManager.set_value("game", "reduce_motion", _reduce_motion_opt.button_pressed)
	SettingsManager.save_settings()


func _on_back() -> void:
	_collect()
	ToastManager.notify("设置已保存")
	back_pressed.emit()
