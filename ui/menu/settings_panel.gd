extends Control
## 设置面板 —— HD-2D 重构版
## 四分类：显示 / 音频 / 控制 / 游戏
## 可独立使用，也可嵌入主菜单

@onready var tab_display: Button = get_node_or_null("VBox/TabBar/BtnDisplay")
@onready var tab_audio: Button = get_node_or_null("VBox/TabBar/BtnAudio")
@onready var tab_control: Button = get_node_or_null("VBox/TabBar/BtnControl")
@onready var tab_game: Button = get_node_or_null("VBox/TabBar/BtnGame")

@onready var display_page: Control = get_node_or_null("VBox/Pages/DisplayPage")
@onready var audio_page: Control = get_node_or_null("VBox/Pages/AudioPage")
@onready var control_page: Control = get_node_or_null("VBox/Pages/ControlPage")
@onready var game_page: Control = get_node_or_null("VBox/Pages/GamePage")

enum Tab { DISPLAY, AUDIO, CONTROL, GAME }
var current_tab: Tab = Tab.DISPLAY

## 游戏内打开时为 true：接管暂停与模态，关闭时还原
var _in_game := false

@onready var chk_auto_pickup: CheckButton = get_node_or_null("VBox/Pages/GamePage/ChkAutoPickup")
@onready var chk_damage_numbers: CheckButton = get_node_or_null("VBox/Pages/GamePage/ChkDamageNumbers")


func _ready() -> void:
	# 游戏内打开时游戏是暂停的，面板必须仍能接收输入
	process_mode = PROCESS_MODE_ALWAYS
	if not is_in_group("settings_panel"):
		add_to_group("settings_panel")
	_setup_tabs()
	_setup_game_toggles()
	AudioManager.connect_buttons(self)
	_switch_tab(Tab.DISPLAY)


## 打开面板。in_game=true 接管暂停与模态（供暂停菜单调用）
func open(in_game: bool = false) -> void:
	_in_game = in_game
	visible = true
	if _in_game:
		add_to_group("modal_ui")
		get_tree().paused = true


## 关闭面板（游戏内则恢复运行并交还暂停菜单）
func close() -> void:
	visible = false
	if not _in_game:
		return
	remove_from_group("modal_ui")
	get_tree().paused = false
	_in_game = false
	# 交还给暂停菜单，避免玩家回到游戏后找不到菜单
	var pm := get_tree().get_first_node_in_group("pause_menu")
	if pm and "visible" in pm:
		pm.visible = true


func _unhandled_input(event: InputEvent) -> void:
	# 只在游戏内接管 Esc；主菜单里的 Esc 由 main_menu.gd 统一处理（回上级页）
	if not visible or not _in_game:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


## 游戏页的可交互开关（此前该页全是静态标签，改不了任何东西）
func _setup_game_toggles() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if chk_auto_pickup:
		if sm:
			chk_auto_pickup.button_pressed = bool(sm.get_setting("auto_pickup"))
		chk_auto_pickup.toggled.connect(_on_auto_pickup_toggled)
	if chk_damage_numbers:
		if sm:
			chk_damage_numbers.button_pressed = bool(sm.get_setting("show_damage_numbers"))
		chk_damage_numbers.toggled.connect(_on_damage_numbers_toggled)


func _on_auto_pickup_toggled(pressed: bool) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		sm.set_setting("auto_pickup", pressed)


func _on_damage_numbers_toggled(pressed: bool) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		sm.set_setting("show_damage_numbers", pressed)


func _setup_tabs() -> void:
	if tab_display:
		tab_display.pressed.connect(_switch_tab.bind(Tab.DISPLAY))
	if tab_audio:
		tab_audio.pressed.connect(_switch_tab.bind(Tab.AUDIO))
	if tab_control:
		tab_control.pressed.connect(_switch_tab.bind(Tab.CONTROL))
	if tab_game:
		tab_game.pressed.connect(_switch_tab.bind(Tab.GAME))


func _switch_tab(tab: Tab) -> void:
	current_tab = tab
	if display_page:
		display_page.visible = tab == Tab.DISPLAY
	if audio_page:
		audio_page.visible = tab == Tab.AUDIO
	if control_page:
		control_page.visible = tab == Tab.CONTROL
	if game_page:
		game_page.visible = tab == Tab.GAME