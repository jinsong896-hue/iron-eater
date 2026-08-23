@tool
extends Control
## IronEater Studio 主面板 —— 标签页切换各编辑器

var _editor_interface: EditorInterface = null

@onready var _tabs: TabContainer = $Tabs
@onready var _char_dock: Control = $Tabs/Character
@onready var _equip_dock: Control = $Tabs/Equipment
@onready var _monster_dock: Control = $Tabs/Monster


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_char_dock.setup(editor_interface)
	_equip_dock.setup(editor_interface)
	_monster_dock._ready()
