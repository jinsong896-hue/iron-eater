@tool
extends Control
## IronEater Studio 主面板 —— 六标签页

var _editor_interface: EditorInterface = null
@onready var _tabs: TabContainer = $Tabs


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	_safe_call("角色", "setup", [editor_interface])
	_safe_call("装备", "setup", [editor_interface])
	_safe_call("怪物", "_ready", [])
	_safe_call("数值", "_ready", [])
	_safe_call("资源", "_ready", [])


func _safe_call(tab_name: String, method: String, args: Array) -> void:
	var node := _tabs.get_node_or_null(tab_name)
	if node == null:
		return
	if node.has_method(method):
		node.callv(method, args)
