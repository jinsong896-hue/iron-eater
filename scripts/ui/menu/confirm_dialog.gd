class_name ConfirmDialog
extends Control
## 统一确认弹窗：《开始页面相关.md》——删除存档/覆盖旧局/放弃探索/退出均复用

signal confirmed
signal cancelled

var _on_confirm: Callable
var _dim: ColorRect
var _title_label: Label
var _body_label: Label
var _confirm_btn: Button


func _ready() -> void:
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_body_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 40)
	cancel.pressed.connect(_on_cancel_pressed)
	buttons.add_child(cancel)

	_confirm_btn = Button.new()
	_confirm_btn.custom_minimum_size = Vector2(140, 40)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_btn)


func show_confirm(title: String, body: String, confirm_text: String, on_confirm: Callable, danger := false) -> void:
	_title_label.text = title
	_body_label.text = body
	_confirm_btn.text = confirm_text
	_confirm_btn.modulate = Color(1, 0.35, 0.3) if danger else Color.WHITE
	_on_confirm = on_confirm
	visible = true


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_confirm_pressed() -> void:
	visible = false
	confirmed.emit()
	if _on_confirm.is_valid():
		_on_confirm.call()
