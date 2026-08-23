@tool
extends Control
## IronEater Studio 主面板 —— 五标签页

var _editor_interface: EditorInterface = null
@onready var _tabs: TabContainer = $Tabs


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_tabs.get_node("角色").setup(editor_interface)
	_tabs.get_node("装备").setup(editor_interface)
	_tabs.get_node("怪物")._ready()
	_tabs.get_node("数值")._ready()
