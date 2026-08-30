extends CanvasLayer
## 暂停菜单 —— HD-2D 重构版
## 继续 / 设置 / 返回主菜单 / 放弃探索 / 退出至桌面
## 返回主菜单 ≠ 放弃本局（返回主菜单保留续玩，放弃探索才终止本局）

@onready var btn_resume: Button = $RightPanel/BtnResume
@onready var btn_settings: Button = $RightPanel/BtnSettings
@onready var btn_main_menu: Button = $RightPanel/BtnMainMenu
@onready var btn_abandon: Button = $RightPanel/BtnAbandon
@onready var btn_quit: Button = $RightPanel/BtnQuit


func _ready() -> void:
	# 关键：暂停时仍然处理输入
	process_mode = PROCESS_MODE_ALWAYS

	if btn_resume:
		btn_resume.pressed.connect(_on_resume)
	if btn_settings:
		btn_settings.pressed.connect(_on_settings)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_main_menu)
	if btn_abandon:
		btn_abandon.pressed.connect(_on_abandon)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if visible:
			_on_resume()
		else:
			visible = true
			get_tree().paused = true
		get_viewport().set_input_as_handled()


func _on_resume() -> void:
	visible = false
	get_tree().paused = false


func _on_settings() -> void:
	EventBus.message.emit("设置面板")


func _on_main_menu() -> void:
	get_tree().paused = false
	var sm := get_node_or_null("/root/SceneManager")
	if sm:
		sm.go_to_main_menu()


func _on_abandon() -> void:
	get_tree().paused = false
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("finish_run"):
		gm.finish_run("abandoned")
	var sm := get_node_or_null("/root/SceneManager")
	if sm:
		sm.go_to_main_menu()


func _on_quit() -> void:
	get_tree().quit()