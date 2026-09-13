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

@onready var chk_auto_pickup: CheckButton = get_node_or_null("VBox/Pages/GamePage/ChkAutoPickup")


func _ready() -> void:
	_setup_tabs()
	_setup_game_toggles()
	_switch_tab(Tab.DISPLAY)


## 游戏页的可交互开关（此前该页全是静态标签，改不了任何东西）
func _setup_game_toggles() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if chk_auto_pickup:
		if sm:
			chk_auto_pickup.button_pressed = bool(sm.get_setting("auto_pickup"))
		chk_auto_pickup.toggled.connect(_on_auto_pickup_toggled)


func _on_auto_pickup_toggled(pressed: bool) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		sm.set_setting("auto_pickup", pressed)


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