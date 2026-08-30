@icon("uid://v2fnd7dcxvhy")
@tool
extends ComputeFlowBase
class_name ComputeFlow
## 计算着色器根节点，用于自定义计算着色器
## 使用流程：[br]
## 1. 新建一个.glsl 的计算着色器文件（可以为空），添加到 black_board.glsl_file  [br]
## 2. 设置全局线程总数[br]
## 3. 添加set ， 根据情况添加push_constant [br]
## 4. 在set节点添加自定义uniform [br]
## 5. 点击按钮生成着色器 [br]
## ！！！！[br]
## 着色器默认整数使用uint型

## 黑板数据
@export var black_board :ComputeFlowBlackBoard:
	set(v):
		if v!= black_board:
			black_board = v
			update_configuration_warnings()

## 设置uniform
@export var restart := false:
	set(value):
		restart = value
		if Engine.is_editor_hint():
			await get_tree().create_timer(1).timeout
			restart = false
			return
		if restart:
			print("重启计算着色器: ",name)
			_restart()

## 暂停运行
@export var debug := false:
	set(v):
		debug = v
		if black_board:
			if black_board.push_constant:
				black_board.push_constant.debug = v 

@export var stop := false:
	set(v):
		if v!= stop:
			stop = v
			update_configuration_warnings()


## 工作组
var work_group : Vector3i
## 管线
var pipeline: RID
## set集合
var sets:=[]
## 计算着色器准备就绪
var is_ready:=false
## 是否存在重名uniform
var has_dup_uniforms:=false 

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await update_binding()

#<==============================公有方法==============================>##

## <公有方法>设置工作组
func set_work_group(x: int = black_board.global_size.x, y: int = black_board.global_size.y, z: int = black_board.global_size.z):
	print("%s 设置工作组" % name ,black_board.global_size)
	work_group.x = ceil(x / float(black_board.local_size.x))
	work_group.y = ceil(y / float(black_board.local_size.y))
	work_group.z = ceil(z / float(black_board.local_size.z))

## <公有方法>更新绑定shader，当绑定对象更新时，调用此方法
func update_binding():
	set_work_group()
	shader_rid = _get_shader_from_inc()
	pipeline = rd.compute_pipeline_create(shader_rid)
	# 创建set
	sets.clear()
	for uniform_set in get_children():
		if uniform_set is ComputeSet:
			uniform_set.shader_rid = shader_rid
			await uniform_set.get_set()
			sets.append(uniform_set)
			if !uniform_set.rid:
				printerr("无效set：",uniform_set)
	is_ready = true
	print(self.name," ready")

## <公有方法>更新计算着色器
func run() -> void:
	if !is_ready or stop:
		return
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)

	for set_id in sets.size():
		var compute_set:ComputeSet = sets[set_id]
		## 如果是双缓冲set
		rd.compute_list_bind_uniform_set(compute_list, compute_set.rid,set_id)
	if black_board.push_constant:
		var aligned_data := black_board.push_constant.get_byte_array()
		if debug:
			print("push_constant:\n %s\n" %[black_board.push_constant.get_parsed_data()])
		rd.compute_list_set_push_constant(compute_list, aligned_data, aligned_data.size())

	rd.compute_list_dispatch(compute_list, work_group.x, work_group.y, work_group.z)
	rd.compute_list_end()
	## 如果是双缓冲set 交换
	for set_id in sets.size():
		var compute_set:ComputeSet = sets[set_id]
		if compute_set is DoubleBufferingSet:
			compute_set.swap_set()
	# 发射运行信号
	black_board.compute_run.emit()

## <公有方法>更新push_constant(单个值)
func set_push_constant(name: String, value: Variant) -> void:
	if black_board.push_constant:
		black_board.push_constant.set_value(name,value)

## <公有方法>更新push_constant(按字典更新,可以不是全部参数,性能和 set_push_constant 没有差别)
func set_push_constants(values: Dictionary) -> void:
	if black_board.push_constant:
		black_board.push_constant.set_values(values)

#<==============================runtime==============================>#
## 根据代码返回着色器实例
func _get_shader_from_inc() -> RID:
	# 1. 以文本形式读取文件内容
	var file = FileAccess.open(black_board.glsl_file, FileAccess.READ)
	if not file:
		return RID()
	
	var file_path: String = ResourceLoader.load(black_board.glsl_file).resource_path
	var shader_spirv:RDShaderSPIRV
	var shader_code = file.get_as_text()
	file.close()
	var shader_source = RDShaderSource.new()
	# 去掉中文 确保驱动程序不会因为 UTF-8 字节报错
	var regex = RegEx.new()
	regex.compile("[^\\x00-\\x7F]+")
	shader_code = regex.sub(shader_code, "", true)
	if file_path.get_extension() == "gdshaderinc":
	# 去掉开头
		regex.compile("#\\[\\w+\\]")
		shader_code = regex.sub(shader_code, "", true)
		# 3. 使用 RDShaderSource 代替 RDShaderFile
		shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL

		# 如果是计算着色器，赋值给 source_compute
		shader_source.source_compute = shader_code
		shader_spirv = rd.shader_compile_spirv_from_source(shader_source)
		
	elif file_path.get_extension() == "glsl" :
		var shader_file := load(black_board.glsl_file)
		shader_spirv = shader_file.get_spirv()
		
	# 4. 编译并获取着色器 RID
	if shader_spirv.compile_error_compute:
		printerr("着色器编译错误 :\n ",shader_spirv.compile_error_compute)

	# 检查编译错误
	return rd.shader_create_from_spirv(shader_spirv)

func _restart():
	_get_shader_from_inc()
	
	update_binding()
	if black_board.push_constant:
		black_board.push_constant.set_values()
	run()
	black_board.compute_restart.emit()

# <==============================编辑器工具==============================>
## 打开外部编辑器，编辑glsl文件
func edit_shader() -> void:
	if black_board.glsl_file == "" or not FileAccess.file_exists(black_board.glsl_file):
		printerr("未选择着色器文件或文件不存在: ", black_board.glsl_file)
		return

	# 获取用户配置的外部编辑器路径
	var settings := EditorInterface.get_editor_settings()
	var editor_path := settings.get_setting("text_editor/external/exec_path") as String

	if editor_path.is_empty():
		printerr("未配置外部编辑器路径，在 'text_editor/external/exec_path'处配置")
		return

	var file_path: String = ResourceLoader.load(black_board.glsl_file).resource_path
	file_path = ProjectSettings.globalize_path(file_path)
	
	# 创建进程
	var process_id := -1
	var args: PackedStringArray = []
	
	match OS.get_name():
		"macOS":
			# macOS 特殊处理：使用 open 命令
			args = ["-a", editor_path, file_path]
			process_id = OS.create_process("open", args, false)
		"Windows", "Linux", "FreeBSD", "NetBSD", "OpenBSD":
			# 其他系统：直接传递编辑器路径
			args = [file_path]
			process_id = OS.create_process(editor_path, args, false)
		_:
			printerr("不支持的操作系统: ", OS.get_name())
			return

	if process_id == -1:
		printerr("无法启动外部编辑器进程: ", editor_path)
		return
	
	print("已在外部编辑器中打开: ", file_path.get_file())

## 生成glsl预设
func build_glsl_source() -> void:
	## glsl 模板
	var GLSL_header = "#[compute]\n#version 450\n"
	var work_group_decl = "layout(local_size_x = {x}, local_size_y = {y}, local_size_z = {z}) in;"
	work_group_decl = work_group_decl.format({
		"x": black_board.local_size.x,
		"y": black_board.local_size.y,
		"z": black_board.local_size.z
	})
	# 生成 black_board.push_constant 声明
	var push_constant_declarations = _generate_push_constant()
	# 添加 uniform 声明
	var structs_declarations = _generate_structs()
	# 生成 uniform 声明
	var uniform_declarations = _generate_uniforms()
	# 3. 组合完整的 GLSL
	var glsl_code = (GLSL_header+ "\n" 
	 + black_board.macro + "\n" 
	 + "//" + black_board.description + "\n" 
	 + work_group_decl + "\n"
	 + push_constant_declarations + "\n"
	 + structs_declarations + "\n"
	 + uniform_declarations
	)
	# 读取现有文件内容
	var file_content = ""
	if FileAccess.file_exists(black_board.glsl_file):
		var read_file = FileAccess.open(black_board.glsl_file, FileAccess.READ)
		if read_file:
			file_content = read_file.get_as_text()
			read_file.close()
	
	# 查找分隔符位置
	var separator_index = file_content.find(SEPARATOR)

	if separator_index != -1:
		# 找到分隔符，保留分隔符之后的内容
		var after_separator = file_content.substr(separator_index)
		# 组合代码：生成的代码 + 原分隔符之后的内容
		file_content = glsl_code +"\n" + after_separator
	else:
		# 没有找到分隔符
		var main_index = file_content.find("void main()")
		# 组合 GLSL 代码
		var generated_code = glsl_code
		# 找到main函数 获取main函数后的内容
		if main_index != -1:
			var brace_index = file_content.find("{", main_index)
			var end_brace_index = file_content.rfind("}")
			var after_main_decl = file_content.substr(main_index, brace_index - main_index + 1)
			var after_main_body = ""

			if end_brace_index > brace_index:
				after_main_body = file_content.substr(brace_index + 1, end_brace_index - brace_index - 1)

			file_content = generated_code + "\n" + SEPARATOR  + "\n" + after_main_decl
			file_content += after_main_body
			file_content += "}"
		else:
			# 组合 GLSL 代码
			file_content = (glsl_code + "\n"
				+ DEPENDENCIES_SLOT + "\n" 
				+ SEPARATOR  + "\n" 
				+  "//** 使用compute_shader插件时 不要修改或者删除分隔符 也不要修改分隔符上方的内容 **//\n\n"
				)
			# 添加main函数
			file_content += "void main() {\n"
			file_content += "	// 在这里添加计算着色器代码\n"
			file_content += "}"
	# 写入文件
	var file = FileAccess.open(black_board.glsl_file, FileAccess.WRITE)
	if file:
		file.store_string(file_content)
		file.close()
		print("GLSL code written to: " + black_board.glsl_file)
	else:
		printerr("Failed to write to file: " + black_board.glsl_file)

## 生成push_constant
func _generate_push_constant()->String:
	if black_board.push_constant and black_board.push_constant.fields != "":
		return black_board.push_constant.get_declaration()
	return ""

## 生成结构体
func _generate_structs()->String:
	var declarations :=""
	for i:Struct in black_board.structs:
		i.add_field_to_data()
		declarations += i.generate_struct() +"\n"
	return declarations

## 生成uniform
func _generate_uniforms():
	has_dup_uniforms =false
	var uniform_names:=[]
	var uniforms:={}
	for compute_set in get_children():
		if compute_set is not ComputeSet:
			printerr("%s 节点不是ComputeSet")
		else:
			uniforms[compute_set]=[]
			# 添加uniform
			for uniform:ComputeUniform in compute_set.get_children():
				uniforms[compute_set].append(uniform)
				if uniform_names.has(uniform.uniform_name):
					has_dup_uniforms = true
				else:
					uniform_names.append(uniform.uniform_name)
	update_configuration_warnings()
	# uniform 字段
	var declarations :=""
	# 遍历所有 set
	for i in uniforms.keys().size():
		var compute_set:ComputeSet = uniforms.keys().get(i)
		
		compute_set.set_id = i
		# 添加注释
		declarations += "\n//set %s %s\n" % [str(i),compute_set.description]
		# 遍历当前 set 中的所有 uniform
		for j in uniforms.get(compute_set).size():
			var uniform:ComputeUniform = uniforms.get(compute_set).get(j)
			uniform.binding = j
			declarations += uniform.get_declaration(i)
	return declarations

## 配置警告
func _get_configuration_warnings() -> PackedStringArray:
	var warnings:PackedStringArray = []
	# 检查子节点类型
	for child in get_children():
		if not child is ComputeSet:
			warnings.append("计算着色器子节点必须为ComputeSet")
			break

	if !black_board :
		warnings.append("未添加和保存黑板数据")
		return warnings
	if black_board.local_size.x* black_board.local_size.y* black_board.local_size.z> 1024:
		warnings.append("工作组最大线程数超出范围限制")
	if has_dup_uniforms:
		warnings.append("存在重名uniform变量")
	if stop:
		warnings.append("计算着色器暂停")
	return warnings 

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
	for set in sets:
		for uniform in set.get_children():
			if uniform.rid.is_valid():
				rd.free_rid(uniform.rid)
	print("清除该着色器的所有 RID")
