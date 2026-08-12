class_name SettlementPanel
extends Control
## 本局结算页：《页面相关2.md》页面09——死亡/通关/放弃统一模板，分阶段呈现

signal closed

var _title: Label
var _highlight: Label
var _stats: Label
var _reward: Label
var _unlock: Label
var _ok_btn: Button


func _ready() -> void:
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_highlight = Label.new()
	_highlight.add_theme_font_size_override("font_size", 21)
	_highlight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_highlight.modulate = Color(0.85, 0.55, 0.35)
	box.add_child(_highlight)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 15)
	_stats.modulate = Color(0.85, 0.85, 0.83)
	box.add_child(_stats)
	_reward = Label.new()
	_reward.add_theme_font_size_override("font_size", 17)
	_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_reward)
	_unlock = Label.new()
	_unlock.add_theme_font_size_override("font_size", 15)
	_unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock.modulate = Color(0.6, 0.9, 0.7)
	box.add_child(_unlock)
	_ok_btn = Button.new()
	_ok_btn.text = "继续"
	_ok_btn.custom_minimum_size = Vector2(160, 42)
	_ok_btn.pressed.connect(func(): visible = false; closed.emit())
	box.add_child(_ok_btn)


func show_result(result: Dictionary) -> void:
	var reason_names := {"defeated": "探 索 终 止", "cleared": "深 渊 已 平 息", "abandoned": "探 索 结 束"}
	_title.text = reason_names.get(result.get("reason", ""), "探 索 结 束")
	var cls := GameCatalog.class_info(str(result.get("character", "warrior")))
	var diff := GameCatalog.difficulty_info(str(result.get("difficulty", "normal")))
	_highlight.text = "抵达 第 %d 层\n%s · %s · %s" % [
		result.get("floor", 1), cls.name, diff.name, cls.title]
	var total_secs := int(result.get("play_time", 0.0))
	_stats.text = "游戏时间  %02d:%02d\n击杀敌人  %d　精英 %d　Boss %d\n获得金币  %d\n吞噬装备  %d　融合次数  %d" % [
		total_secs / 60, total_secs % 60, result.get("kills", 0),
		result.get("elite_kills", 0), result.get("boss_kills", 0),
		result.get("gold", 0), result.get("devoured", 0), result.get("fusions", 0)]
	_reward.text = "记忆残渣 +%d" % result.get("fragments", 0)
	_unlock.text = ""
	if result.get("reason", "") == "cleared":
		_unlock.text = "新的形态已解锁：%s · 进阶Ⅰ" % cls.name
	visible = true
	_ok_btn.grab_focus()
	_play_staged_reveal()


func _play_staged_reveal() -> void:
	for label in [_highlight, _stats, _reward, _unlock]:
		label.modulate.a = 0.0
	var steps := [[_highlight, 0.0], [_stats, 0.5], [_reward, 1.0], [_unlock, 1.6]]
	for step in steps:
		await get_tree().create_timer(step[1]).timeout
		if not is_instance_valid(step[0]):
			return
		var tween := create_tween()
		tween.tween_property(step[0], "modulate:a", 1.0, 0.35)
