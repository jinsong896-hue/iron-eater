class_name SettlementPanel
extends Control
## 本局结算页：《开始页面相关.md》——死亡/通关/放弃后显示本局数据

signal closed

var _title: Label
var _body: Label


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
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_body)
	var ok := Button.new()
	ok.text = "确认"
	ok.custom_minimum_size = Vector2(160, 40)
	ok.pressed.connect(func(): visible = false; closed.emit())
	box.add_child(ok)


func show_result(result: Dictionary) -> void:
	var reason_names := {"defeated": "探索失败", "cleared": "通关", "abandoned": "已放弃探索"}
	_title.text = reason_names.get(result.get("reason", ""), "探索结束")
	_body.text = "抵达层数：第 %d 层\n击杀：%d　金币：%d\n本局时长：%.0f 秒\n\n记忆残渣 +%d" % [
		result.get("floor", 1), result.get("kills", 0), result.get("gold", 0),
		result.get("play_time", 0.0), result.get("fragments", 0)]
	visible = true
