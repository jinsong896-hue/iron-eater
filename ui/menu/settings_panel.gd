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


func _ready() -> void:
	_setup_tabs()
	_switch_tab(Tab.DISPLAY)


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