class_name SaveSlotCard
extends Control
## 存档卡槽：《开始页面相关.md》——空槽创建 / 已有档进入与删除

signal slot_selected(slot: int)
signal slot_delete_requested(slot: int)

@export var slot := 1

var _title: Label
var _info: Label
var _status: Label
var _create_btn: Button


func _ready() -> void:
	theme = UITheme.get_theme()
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(320, 205)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(_info)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_create_btn = Button.new()
	_create_btn.text = "＋ 创建存档"
	_create_btn.custom_minimum_size = Vector2(200, 36)
	_create_btn.pressed.connect(func(): slot_selected.emit(slot))
	box.add_child(_create_btn)
	var enter := Button.new()
	enter.text = "进入"
	enter.custom_minimum_size = Vector2(120, 36)
	enter.pressed.connect(func(): slot_selected.emit(slot))
	buttons.add_child(enter)
	var delete_btn := Button.new()
	delete_btn.text = "删除"
	delete_btn.custom_minimum_size = Vector2(90, 36)
	delete_btn.pressed.connect(func(): slot_delete_requested.emit(slot))
	buttons.add_child(delete_btn)
	buttons.visible = false
	set_meta("buttons", buttons)


func setup(data: Dictionary, exists: bool) -> void:
	_title.text = "存档 %02d" % slot
	var buttons: HBoxContainer = get_meta("buttons")
	if not exists:
		_info.text = "＋ 创建存档\n\n点击进入后创建新档案"
		_status.text = ""
		buttons.visible = false
		_create_btn.visible = true
		_show_as_empty(true)
		return
	_create_btn.visible = false
	_show_as_empty(false)
	buttons.visible = true
	var prog: Dictionary = data.get("progression", {})
	var run: Dictionary = data.get("current_run", {})
	var char_name := "—"
	var cls := GameCatalog.class_info(str(run.get("character", "warrior")))
	if not run.get("active", false):
		cls = GameCatalog.class_info("warrior")
	char_name = "%s · %s" % [cls.get("name", "?"), cls.get("title", "?")]
	_status.text = "● 存在未完成的探索" if run.get("active", false) else "● 无进行中的探索"
	_status.modulate = Color(1.0, 0.85, 0.5) if run.get("active", false) else Color(0.6, 0.6, 0.6)
	var meta: Dictionary = data.get("_meta", {})
	var load_status: String = meta.get("load_status", "normal")
	if load_status == "bak_recovered":
		_status.text += "\n（已从备份恢复）"
		_status.modulate = Color(1.0, 0.8, 0.3)
	elif load_status == "migrated":
		_status.text += "\n（旧版本存档已迁移）"
	var last_play: String = str(data.get("last_play_time", "")).split("T")[0]
	_info.text = "%s\n游戏时间：%.0f 分钟\n最高抵达：第 %d 层\n最后游玩：%s" % [
		char_name, data.get("total_play_time", 0.0) / 60.0, prog.get("highest_floor", 0), last_play]


func _show_as_empty(is_empty: bool) -> void:
	modulate = Color(0.55, 0.55, 0.58) if is_empty else Color.WHITE
