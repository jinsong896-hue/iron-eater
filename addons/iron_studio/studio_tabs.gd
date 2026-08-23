@tool
extends Control
## IronEater Studio 主面板 —— 四标签页

var _editor_interface: EditorInterface = null

@onready var _tabs: TabContainer = $Tabs


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_tabs.get_node("Character").setup(editor_interface)
	_tabs.get_node("Equipment").setup(editor_interface)
	_tabs.get_node("Monster")._ready()
