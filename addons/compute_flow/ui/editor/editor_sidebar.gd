@tool
extends Control

#region 节点引用
## 按钮容器
@onready var button_container: BoxContainer = %ButtonContainer

@onready var set_buttons: FlowContainer = %SetButtons
@onready var double_buffering_buttons: FlowContainer = %DoubleBufferingButtons
@onready var uniform_buttons: FlowContainer = %UniformButtons


## 黑板容器
@onready var black_board_foldable: FoldableContainer = %BlackBoard
@onready var shader_name: Button = %shader_name
@onready var black_board_name: Button = %BlackBoardName

## 数据编辑器
@onready var global_x: SpinBox = %global_x
@onready var global_y: SpinBox = %global_y
@onready var global_z: SpinBox = %global_z

@onready var local_x: SpinBox = %local_x
@onready var local_y: SpinBox = %local_y
@onready var local_z: SpinBox = %local_z

@onready var macro_edit: CodeEdit = %MacroEdit
@onready var push_constant_edit: CodeEdit = %PushConstantEdit
@onready var structs_foldable: FoldableContainer = %StructsFoldable

## 警告标签
@onready var worring_label: Label = %WorringLabel
#endregion

## 当前选中的节点
var current_node:Node = null
var compute_shader:ComputeFlow = null
## 黑板数据
var black_board:ComputeFlowBlackBoard = null

## glsl 文件路径
var file_path:String
# 编辑器
@onready var new_black_board: BoxContainer = %NewBlackBoard
@onready var black_board_edit: BoxContainer = %BlackBoardEdit


@onready var scene_root = EditorInterface.get_edited_scene_root()
@onready var urm:EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()

signal switch_position()

func _ready() -> void:
	urm.clear_history(urm.get_object_history_id(scene_root))

#region 插件初始,切换当前节点
func update_for_node(node:Node) -> void:
	get_child(0).show()
	worring_label.hide()
	
	current_node = node
	compute_shader = find_compute_flow(node)
		
	if !compute_shader:
		if current_node is ComputeSet:
			_show_worring("The node must be a child node of ComputeFlow\n该节点必须为ComputeFlow的子节点")
		else:
			_show_worring("The node must be a child node of ComputeSet\n该节点必须为ComputeSet的子节点")
		return
		
	if compute_shader.black_board == null:
		_show_worring("Please create and save blackboard\n请先创建黑板数据")
		get_child(0).show()
		new_black_board.show()
		black_board_edit.hide()
		return
	else:
		black_board = compute_shader.black_board
		black_board_edit.show()
		new_black_board.hide()

	if current_node is ComputeFlow:
		compute_shader = node
		black_board = compute_shader.black_board
		_show_button(0)
	elif current_node is ComputeSet:
		if current_node is DoubleBufferingSet:
			_show_button(1)
		else :
			_show_button(2)
	elif current_node is ComputeUniform:
		_show_button(3)
		
	_blackboard_sync(compute_shader)
	
	update_ui_from_blackboard()

func find_compute_flow(node: Node) -> ComputeFlow:
	if node == null:
		return null
	if node is ComputeFlow:
		return node
	return find_compute_flow(node.get_parent())
	
# 显示按钮
func _show_button(type: int) -> void:
	for child in button_container.get_children():
		child.hide()
	match type:
		0: 
			set_buttons.show()
		1:
			double_buffering_buttons.show()
			
		2:  # ComputeSet
			uniform_buttons.show()
		_:
			pass
# 展示警告
func _show_worring(worring:String):
	get_child(0).hide()
	worring_label.show()
	worring_label.text = worring

#endregion

#region 添加子节点
func _add_new_node(new_node:Node,new_name) -> void:
	if not urm or not current_node:
		return
	
	urm.create_action("Add Node")
	
	var target_parent = current_node
	
	# Do操作
	urm.add_do_method(target_parent, "add_child", new_node)
	urm.add_do_property(new_node, "name", new_name)
	urm.add_do_property(new_node, "owner", get_tree().edited_scene_root)
	
	# Undo操作
	urm.add_undo_method(target_parent, "remove_child", new_node)
	
	urm.commit_action()


func _on_compute_set_pressed() -> void:
	var new_node = ComputeSet.new()
	_add_new_node(new_node,"ComputeSet")

func _on_double_buffering_set_pressed() -> void:
	var new_node = DoubleBufferingSet.new()
	_add_new_node(new_node,"DoubleBufferingSet")

func _on_image_buffer_pressed() -> void:
	var new_node = ImageUniform.new()
	_add_new_node(new_node,"Image")

func _on_sampler_2d_pressed() -> void:
	var new_node = Sampler2DUniform.new()
	_add_new_node(new_node,"Sampler2D")

func _on_uniform_buffer_pressed() -> void:
	var new_node = UniformBuffer.new()
	_add_new_node(new_node,"UniformBuffer")

func _on_storage_buffer_pressed() -> void:
	var new_node = StorageBuffer.new()
	_add_new_node(new_node,"Storage")


func _on_audio_buffer_pressed() -> void:
	var new_node = AudioBuffer.new()
	_add_new_node(new_node,"AudioBuffer")


func _on_bridge_uniform_pressed() -> void:
	var new_node = BridgeUniform.new()
	_add_new_node(new_node,"BridgeUniform")

func _on_multi_mesh_buffer_pressed() -> void:
	var new_node = MutilMeshBuffer.new()
	_add_new_node(new_node,"MutilMeshBuffer")

#endregion

#region 选择 生成 glsl文件预设
func _on_shader_name_pressed() -> void:
	if file_path == "":
		_show_glsl_selection_dialog()
	else:
		_open_glsl_file_location()

# 显示GLSL文件选择弹窗
func _show_glsl_selection_dialog() -> void:
	var file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_ANY
	file_dialog.filters = PackedStringArray(["*.glsl"])
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "选择GLSL文件或文件夹"
	
	file_dialog.file_selected.connect(func(selected_path: String):
		# 如果选择的是GLSL文件
		if selected_path.get_extension() == "glsl":
			file_path = selected_path
			shader_name.text = file_path.get_file().get_basename()
			
			# 加载已有的GLSL文件
			if ResourceLoader.exists(file_path):
				var glsl_resource = ResourceLoader.load(file_path)
				if glsl_resource:
					black_board.glsl_file = file_path
				
		file_dialog.queue_free()
	)
	
	file_dialog.dir_selected.connect(func(selected_dir: String):
		_create_custom_glsl_file(selected_dir)
		file_dialog.queue_free()
	)
	
	file_dialog.canceled.connect(func():
		file_dialog.queue_free()
	)
	
	get_parent().add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.8)

# 打开文件所在文件夹
func _open_glsl_file_location() -> void:
	var dir_dialog = EditorFileDialog.new()
	dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dir_dialog.filters = PackedStringArray(["*.glsl"])
	dir_dialog.current_path = file_path
	dir_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dir_dialog.title = "Open_GLSL_file"
	
	dir_dialog.file_selected.connect(func(selected_path: String):
		# 可以更新文件路径
		if selected_path != file_path:
			file_path = selected_path
			shader_name.text = file_path.get_file().get_basename()
			
			# 重新加载GLSL文件
			if ResourceLoader.exists(file_path):
				var glsl_resource = ResourceLoader.load(file_path)
				if glsl_resource:
					black_board.glsl_file = file_path
		
		dir_dialog.queue_free()
	)
	
	dir_dialog.canceled.connect(func():
		dir_dialog.queue_free()
	)
	
	get_parent().add_child(dir_dialog)
	dir_dialog.popup_centered_ratio(0.8)

# 新建shader
func _on_new_shader_pressed() -> void:
	var save_dialog = EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.glsl"])
	save_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	save_dialog.title = "创建新的 GLSL 文件"
	save_dialog.current_file = "new_compute_shader.glsl"
	
	save_dialog.file_selected.connect(func(selected_path: String):
		_create_custom_glsl_file(selected_path)
		save_dialog.queue_free()
	)
	
	save_dialog.canceled.connect(func():
		save_dialog.queue_free()
	)
	
	get_parent().add_child(save_dialog)
	save_dialog.popup_centered_ratio(0.8)

# 写入和激活新文件
func _create_custom_glsl_file(new_file_path: String) -> void:
	if new_file_path.get_extension() != "glsl":
		new_file_path += ".glsl"
		
	# 创建 GLSL 源码文件
	var file = FileAccess.open(new_file_path, FileAccess.WRITE)
	if file:
		file.close()
		
		file_path = new_file_path
		shader_name.text = new_file_path.get_file().get_basename()

		await get_tree().create_timer(0.1).timeout
		EditorInterface.get_resource_filesystem().scan()
	else:
		print("创建文件失败: ", new_file_path)
#endregion

#region 黑板数据编辑

func _on_black_board_name_pressed() -> void:
	if file_path == "":
		_show_black_board_selection_dialog()
	else:
		_open_black_board_location()

# 显示黑板文件选择弹窗
func _show_black_board_selection_dialog() -> void:
	var file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_ANY
	file_dialog.filters = PackedStringArray(["*.tres"])
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.title = "选择黑板文件"
	
	file_dialog.file_selected.connect(func(selected_path: String):
		if selected_path.get_extension() == "tres":
			black_board_name.text = file_path.get_file().get_basename()
			
			# 加载已有的GLSL文件
			if ResourceLoader.exists(selected_path):
				black_board = ResourceLoader.load(selected_path)
				compute_shader.black_board = black_board
				update_for_node(compute_shader)
				
		file_dialog.queue_free()
	)
	
	file_dialog.dir_selected.connect(func(selected_dir: String):
		_create_custom_glsl_file(selected_dir)
		file_dialog.queue_free()
	)
	
	file_dialog.canceled.connect(func():
		file_dialog.queue_free()
	)
	
	get_parent().add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.8)

# 打开文件所在文件夹
func _open_black_board_location() -> void:
	var dir_dialog = EditorFileDialog.new()
	dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dir_dialog.filters = PackedStringArray(["*.glsl"])
	dir_dialog.current_path = file_path
	dir_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dir_dialog.title = "Open_GLSL_file"
	
	dir_dialog.file_selected.connect(func(selected_path: String):
		# 可以更新文件路径
		if selected_path != file_path:
			file_path = selected_path
			shader_name.text = file_path.get_file().get_basename()
			
			# 重新加载GLSL文件
			if ResourceLoader.exists(file_path):
				var glsl_resource = ResourceLoader.load(file_path)
				if glsl_resource:
					black_board.glsl_file = file_path
		
		dir_dialog.queue_free()
	)
	
	dir_dialog.canceled.connect(func():
		dir_dialog.queue_free()
	)
	
	get_parent().add_child(dir_dialog)
	dir_dialog.popup_centered_ratio(0.8)

func _on_new_black_board_pressed() -> void:
	var save_dialog = EditorFileDialog.new()
	save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.tres"])
	save_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	save_dialog.title = "创建黑板数据"
	save_dialog.current_file = "new_black_board.tres"
	
	save_dialog.file_selected.connect(func(selected_path: String):
		_create_custom_black_board(selected_path)
		save_dialog.queue_free()
	)
	
	save_dialog.canceled.connect(func():
		save_dialog.queue_free()
	)
	
	get_parent().add_child(save_dialog)
	save_dialog.popup_centered_ratio(0.8)

# 写入和激活新文件
func _create_custom_black_board(new_file_path: String) -> void:
	if new_file_path.get_extension() != "tres":
		new_file_path += ".tres"
	
	var new_blackboard = ComputeFlowBlackBoard.new() 
	
	# 保存资源到磁盘
	ResourceSaver.save(new_blackboard, new_file_path)
	print("配套黑板资源创建成功: ", new_file_path)
	
	await get_tree().create_timer(0.1).timeout
	EditorInterface.get_resource_filesystem().scan()
	
	black_board = new_blackboard
	current_node.black_board = new_blackboard
	black_board.changed.connect(update_ui_from_blackboard)
	update_for_node(current_node)

#endregion


func _blackboard_sync(node:Node):
	if !node.get("black_board"):
		return
	if node.black_board != black_board:
		node.black_board = black_board
	for child in node.get_children():
		_blackboard_sync(child)

## 加载黑板数据到UI
func update_ui_from_blackboard() -> void:
	if !black_board.changed.is_connected(update_ui_from_blackboard):
		black_board.changed.connect(update_ui_from_blackboard)
	
	black_board = compute_shader.black_board
	current_node.black_board = compute_shader.black_board

	if black_board.glsl_file != "":
		file_path = ResourceLoader.load(black_board.glsl_file).resource_path
		shader_name.text = file_path.get_file().get_basename()
	else:
		file_path = ""
		shader_name.text = "No GLSL file"
	# 更新全局线程数控件
	global_x.value = black_board.global_size.x
	global_y.value = black_board.global_size.y
	global_z.value = black_board.global_size.z
	# 更新工作组线程数控件
	local_x.value = black_board.local_size.x
	local_y.value = black_board.local_size.y
	local_z.value = black_board.local_size.z
	
	# 更新宏控件
	macro_edit.text = black_board.macro
	
	# 更新push_constant
	if black_board.push_constant :
		push_constant_edit.text = black_board.push_constant.fields
	else:
		push_constant_edit.text = ""
		
	# 更新structs
	structs_foldable.black_board = black_board
	structs_foldable.sync_structs()

func _on_global_x_value_changed(value: float) -> void:
	if black_board.global_size.x != value:
		black_board.global_size.x = int(value)

func _on_global_y_value_changed(value: float) -> void:
	if black_board.global_size.y != value:
		black_board.global_size.y = value

func _on_global_z_value_changed(value: float) -> void:
	if black_board.global_size.z != value:
		black_board.global_size.z = value
		
func _on_local_x_value_changed(value: float) -> void:
	if black_board.black_board.local_size.x != value:
		black_board.black_board.local_size.x = value

func _on_local_y_value_changed(value: float) -> void:
	if black_board.black_board.local_size.y != value:
		black_board.black_board.local_size.y = value
		
func _on_local_z_value_changed(value: float) -> void:
	if black_board.black_board.local_size.z != value:
		black_board.black_board.local_size.z = value

func _on_macro_edit_text_changed() -> void:
	black_board.macro = macro_edit.text

func _on_push_constant_edit_text_changed() -> void:
	if !black_board.push_constant:
		black_board.push_constant= PushConstant.new()
	black_board.push_constant.fields = push_constant_edit.text
	black_board.push_constant.add_field_to_data()

#endregion

## 弹窗编辑
func _on_edit_gui_input(event: InputEvent,text_edit) -> void:
	if event is InputEventMouseButton :
		if event.button_index ==1 and event.double_click:
			const GLSL_EDITOR = preload("uid://c5wupgq8n1kt")
			var editor = GLSL_EDITOR.instantiate()
			add_child(editor)
			editor.owner = get_tree().current_scene
			editor.updata_editor(text_edit)
## 构建shader
func _on_shader_initialization_pressed() -> void:
	compute_shader.build_glsl_source()
## 打开外部编辑器编辑shader
func _on_shader_edit_pressed() -> void:
	compute_shader.edit_shader()
