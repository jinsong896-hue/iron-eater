extends CanvasLayer
## 暂停菜单 —— HD-2D 重构版
## 继续 / 设置 / 返回主菜单 / 放弃探索 / 退出至桌面
## 返回主菜单 ≠ 放弃本局（返回主菜单保留续玩，放弃探索才终止本局）

@onready var btn_resume: Button = $RightPanel/BtnResume
@onready var btn_settings: Button = $RightPanel/BtnSettings
@onready var btn_skills: Button = $RightPanel/BtnSkills
@onready var btn_main_menu: Button = $RightPanel/BtnMainMenu
@onready var btn_abandon: Button = $RightPanel/BtnAbandon
@onready var btn_quit: Button = $RightPanel/BtnQuit


func _ready() -> void:
	# 关键：暂停时仍然处理输入
	process_mode = PROCESS_MODE_ALWAYS
	# 供设置面板关闭后交还控制（settings_panel.gd 按组查找）
	if not is_in_group("pause_menu"):
		add_to_group("pause_menu")

	if btn_resume:
		btn_resume.pressed.connect(_on_resume)
	if btn_settings:
		btn_settings.pressed.connect(_on_settings)
	if btn_skills:
		btn_skills.pressed.connect(_on_skills)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_main_menu)
	if btn_abandon:
		btn_abandon.pressed.connect(_on_abandon)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit)
	AudioManager.connect_buttons(self)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		# 有更高优先级模态面板（特殊房交互等）时让位——策划要求
		# 「底层菜单不能继续接收输入」，否则 Esc 会把暂停菜单叠在面板上。
		# 本菜单用 _input（早于 _unhandled_input），靠事件顺序抢不过，必须显式判断。
		if _modal_ui_active():
			return
		if visible:
			_on_resume()
		else:
			visible = true
			get_tree().paused = true
		get_viewport().set_input_as_handled()


## 是否有模态面板正在打开（面板通过加入 "modal_ui" 组声明）
func _modal_ui_active() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	return not tree.get_nodes_in_group("modal_ui").is_empty()


func _on_resume() -> void:
	visible = false
	get_tree().paused = false


func _on_settings() -> void:
	# 打开真实设置面板（游戏内模式：接管暂停与模态），暂停菜单暂时让位
	var sp := get_tree().get_first_node_in_group("settings_panel")
	if sp == null or not sp.has_method("open"):
		return
	visible = false
	sp.call("open", true)


## 打开技能配置面板（与设置同模式：接管暂停与模态，暂停菜单让位）
func _on_skills() -> void:
	var sp := get_tree().get_first_node_in_group("skill_panel")
	if sp == null or not sp.has_method("open"):
		return
	visible = false
	sp.call("open")


func _on_main_menu() -> void:
	get_tree().paused = false
	var sm := get_node_or_null("/root/SceneManager")
	if sm:
		sm.go_to_main_menu()


func _on_abandon() -> void:
	visible = false
	get_tree().paused = false
	# 结算面板监听 run_finished 自行显示；由结算页「继续」回主菜单
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.has_method("finish_run"):
		gm.finish_run("abandoned")


func _on_quit() -> void:
	get_tree().quit()