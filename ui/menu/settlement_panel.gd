extends CanvasLayer
## 结算页面 —— HD-2D 重构版
## 死亡/通关/放弃探索后的本局统计

@onready var title_label: Label = $CenterContainer/VBox/Title
@onready var floor_label: Label = $CenterContainer/VBox/FloorLabel
@onready var stats_container: VBoxContainer = $CenterContainer/VBox/StatsContainer
@onready var continue_btn: Button = $CenterContainer/VBox/ContinueBtn


## 结算面板需在暂停下仍可交互
func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	if continue_btn:
		continue_btn.pressed.connect(_on_continue)
	# 监听本局结束（死亡/通关/放弃）显示结算
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.run_finished.connect(show_result)


## 显示结算数据
func show_result(result: Dictionary) -> void:
	var reason: String = result.get("reason", "")

	match reason:
		"defeated":
			title_label.text = "探 索 终 止"
		"cleared":
			title_label.text = "深 渊 已 平 息"
		"abandoned":
			title_label.text = "探 索 结 束"
		_:
			title_label.text = "探 索 结 束"

	floor_label.text = "抵达 第 %d 层" % result.get("floor", 1)

	# 清空旧统计
	for child in stats_container.get_children():
		child.queue_free()

	# 添加统计项
	_add_stat("游戏时间", _format_time(result.get("play_seconds", 0.0)))
	_add_stat("击杀敌人", "%d" % result.get("kills", 0))
	_add_stat("精英击杀", "%d" % result.get("elite_kills", 0))
	_add_stat("Boss 击杀", "%d" % result.get("boss_kills", 0))
	_add_stat("获得金币", "%d" % result.get("gold", 0))
	_add_stat("吞噬装备", "%d" % result.get("devoured", 0))
	_add_stat("融合次数", "%d" % result.get("fusions", 0))

	visible = true
	get_tree().paused = true


func _add_stat(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(lbl)

	var sep := Label.new()
	sep.text = "    "
	row.add_child(sep)

	var val := Label.new()
	val.text = value
	val.custom_minimum_size = Vector2(100, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	val.add_theme_color_override("font_color", Color(0.72, 0.59, 0.38, 1))
	row.add_child(val)

	stats_container.add_child(row)


func _format_time(seconds: float) -> String:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	return "%02d:%02d" % [m, s]


func _on_continue() -> void:
	visible = false
	get_tree().paused = false
	var sm := get_node_or_null("/root/SceneManager")
	if sm and sm.has_method("go_to_main_menu"):
		sm.go_to_main_menu()