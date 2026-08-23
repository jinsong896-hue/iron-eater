@tool
extends Control
## IronEater Studio 主面板 —— 六标签页

var _editor_interface: EditorInterface = null


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	var tabs: TabContainer = $Tabs
	if tabs == null:
		print("[IronStudio] ERROR: Tabs not found")
		return
	_safe_call(tabs, "角色", "setup", [editor_interface])
	_safe_call(tabs, "装备", "setup", [editor_interface])
	_safe_call(tabs, "技能", "setup", [editor_interface])
	_safe_call(tabs, "怪物", "setup", [editor_interface])
	_safe_call(tabs, "数值", "setup", [editor_interface])
	_safe_call(tabs, "资源", "setup", [editor_interface])
	_safe_call(tabs, "Buff", "setup", [editor_interface])


func _safe_call(tabs: TabContainer, tab_name: String, method: String, args: Array) -> void:
	var node := tabs.get_node_or_null(tab_name)
	if node == null:
		print("[IronStudio] WARNING: tab '%s' not found" % tab_name)
		return
	if node.has_method(method):
		node.callv(method, args)
