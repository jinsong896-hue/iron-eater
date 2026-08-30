@tool
extends EditorPlugin

## 侧边栏实例
var _sidebar: Control
var _sidebar_3d: Control

## 侧边栏场景
const _sidebar_scene: PackedScene = preload("uid://dklawglii2m5m")

## 当前选中的节点
var _current_selected_node: Node
## 数据缓存文件夹
var data_path:="res://addons/compute_shader/data/black_board_data/"
## 侧边栏是否启用
var sidebar_enabled := true :
	set(value):
		sidebar_enabled = value
		_update_sidebar_visibility()

## 工具栏按钮
var _toolbar_button_2d: Button
var _toolbar_button_3d: Button

func _enter_tree():
	# 创建侧边栏
	_sidebar = _sidebar_scene.instantiate()
	_sidebar_3d = _sidebar_scene.instantiate()
	_hide_sidebar()
	# 将侧边栏添加到编辑器右侧，支持2D和3D编辑器
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_SIDE_RIGHT, _sidebar)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, _sidebar_3d)
	# 连接选择变化信号
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	# 添加工具栏按钮
	_add_toolbar_button()
	
func _exit_tree():
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button_2d)
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button_3d)
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_SIDE_RIGHT, _sidebar)
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, _sidebar_3d)

	_toolbar_button_2d.queue_free()
	_toolbar_button_3d.queue_free()
	_sidebar.queue_free()
	_sidebar_3d.queue_free()


## 添加工具栏按钮
func _add_toolbar_button() -> void:
	_toolbar_button_2d = Button.new()
	_toolbar_button_2d.icon = preload("uid://v2fnd7dcxvhy")
	_toolbar_button_2d.add_theme_constant_override("icon_max_width",24)
	_toolbar_button_2d.tooltip_text = "show compute_shader editor"
	_toolbar_button_2d.toggle_mode = true
	_toolbar_button_2d.button_pressed = sidebar_enabled
	_toolbar_button_2d.toggled.connect(_on_toolbar_button_2d_toggled)
	
	# 添加到画布编辑器菜单栏
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button_2d)
	
	_toolbar_button_3d = Button.new()
	_toolbar_button_3d.icon = preload("uid://v2fnd7dcxvhy")
	_toolbar_button_3d.add_theme_constant_override("icon_max_width",24)
	_toolbar_button_3d.tooltip_text = "show compute_shader editor"
	_toolbar_button_3d.toggle_mode = true
	_toolbar_button_3d.button_pressed = sidebar_enabled
	_toolbar_button_3d.toggled.connect(_on_toolbar_button_3d_toggled)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar_button_3d)
	
## 工具栏按钮切换回调
func _on_toolbar_button_2d_toggled(toggled_on: bool) -> void:
	sidebar_enabled = toggled_on
	if _toolbar_button_3d.button_pressed != toggled_on:
		_toolbar_button_3d.button_pressed = toggled_on
	
func _on_toolbar_button_3d_toggled(toggled_on: bool) -> void:
	sidebar_enabled = toggled_on
	if _toolbar_button_2d.button_pressed != toggled_on:
		_toolbar_button_2d.button_pressed = toggled_on
		
## 更新侧边栏可见性
func _update_sidebar_visibility() -> void:
	
	if !sidebar_enabled:
		_hide_sidebar()
		
	elif _current_selected_node and _is_supported_node_type(_current_selected_node):
		_show_sidebar_for_node(_current_selected_node)
	else:
		_hide_sidebar()

## 选择变化回调
func _on_selection_changed() -> void:
	var selection = EditorInterface.get_selection().get_selected_nodes()
	
	if selection.size() == 1:
		var selected_node = selection[0]
		# 检查节点类型是否支持
		if _is_supported_node_type(selected_node):
			_current_selected_node = selected_node
			_toolbar_button_2d.show()
			_toolbar_button_3d.show()

		else:
			_current_selected_node = null
			_toolbar_button_2d.hide()
			_toolbar_button_3d.hide()
	else:
		_current_selected_node = null
		_toolbar_button_2d.hide()
		_toolbar_button_3d.hide()
	# 更新侧边栏可见性
	_update_sidebar_visibility()

## 显示侧边栏并更新内容
func _show_sidebar_for_node(node: Node) -> void:
	_show_sidebar()
	
	_sidebar.update_for_node(node)
	_sidebar_3d.update_for_node(node)
	
## 显示侧边栏
func _show_sidebar() -> void:
	_sidebar.show()
	_sidebar_3d.show()

## 隐藏侧边栏
func _hide_sidebar() -> void:
	_sidebar.hide()
	_sidebar_3d.hide()
	
## 检查节点类型是否支持
func _is_supported_node_type(node: Node) -> bool:
	return node is ComputeFlowBase
