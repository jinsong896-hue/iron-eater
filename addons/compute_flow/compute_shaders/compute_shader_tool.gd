class_name ComputeFlowTool 
## compute_shader_tool 
## 计算着色器工具集

const TYPE_SIZES := {
	TYPE_INT: 4, TYPE_FLOAT: 4, TYPE_BOOL: 4,
	TYPE_VECTOR2: 8, TYPE_VECTOR2I: 8,
	TYPE_VECTOR3: 16, TYPE_VECTOR3I: 16,
	TYPE_VECTOR4: 16, TYPE_VECTOR4I: 16,
	TYPE_COLOR: 16, TYPE_RECT2: 16, TYPE_RECT2I: 16,
	TYPE_TRANSFORM2D: 48, TYPE_TRANSFORM3D: 64,
	TYPE_BASIS: 48, TYPE_AABB: 32, TYPE_PROJECTION: 64,
	TYPE_STRING: -1,  # 动态大小
}

## 数据类型转换
static func get_type(value: Variant) -> int:
	match typeof(value):
		TYPE_VECTOR3:
			return TYPE_VECTOR4      
		TYPE_VECTOR3I:
			return TYPE_VECTOR4I    
		TYPE_COLOR:
			return TYPE_VECTOR4     
		TYPE_RECT2:
			return TYPE_VECTOR4  
		TYPE_RECT2I:
			return TYPE_VECTOR4I  
		TYPE_PLANE:
			return TYPE_VECTOR4   
			
		# ========== 矩阵系列：直接转换为标准列向量大小 ==========
		TYPE_BASIS:
			return TYPE_BASIS      
		TYPE_TRANSFORM3D:
			return TYPE_TRANSFORM3D  # 保持原本，对应 mat4 (共 64 字节)
		TYPE_PROJECTION:
			return TYPE_PROJECTION   # 保持原本，对应 mat4 (共 64 字节)

		# ========== 基础标量与 2D 向量：直接输出原本类型 ==========
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, \
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR4, TYPE_VECTOR4I:
			return typeof(value)     # 基础 4 字节和 8 字节类型，不需要额外对齐转换

		# ========== 安全防御 ==========
		_:
			push_warning("未处理的类型转换: ", typeof(value))
			return typeof(value)

#  <==============================方法1 将字段转换成字典==============================>
## 从编辑器文本生成数据字典
## field:编辑器数据文本  auto_alignment: 是否自动排序[br]
## 返回:[数据字典,字段索引列表,类型列表]
## 返回 data: Dictionary;  field_list: Array; type_index: Dictionary 
static func field_to_data(fields: String, auto_alignment: bool = true) -> Array:
	var data: Dictionary = {}
	var field_list: Array = []
	var type_index: Dictionary = {}
	
	fields = fields.replace("：", ":")
	var lines = fields.strip_edges().split("\n")
	
	for line in lines:
		var trimmed_line = line.strip_edges()
		# 移除行内注释
		var comment_index = trimmed_line.find("//")
		if comment_index >= 0:
			trimmed_line = trimmed_line.left(comment_index).strip_edges()
		
		if trimmed_line.is_empty():
			continue
		
		if trimmed_line.ends_with(";"):
			trimmed_line = trimmed_line.left(trimmed_line.length() - 1)
		
		var space_index = trimmed_line.find(" ")
		if space_index == -1:
			continue
		
		var type_str = trimmed_line.substr(0, space_index).strip_edges()
		var rest_str = trimmed_line.substr(space_index + 1).strip_edges()
		
		var var_name: String
		var value_str: String
		
		var equal_index = rest_str.find("=")
		if equal_index != -1:
			var_name = rest_str.substr(0, equal_index).strip_edges()
			value_str = rest_str.substr(equal_index + 1).strip_edges()
		else:
			var_name = rest_str.strip_edges()
			# 根据类型设置默认值
			match type_str:
				"float": value_str = "0.0"
				"int": value_str = "0"
				"bool": value_str = "false"
				"vec2": value_str = "0,0"
				"vec3": value_str = "0,0,0"
				"vec4": value_str = "0,0,0,0"
				"mat2": value_str = "1,0,0,1"
				"mat3": value_str = "1,0,0,0,1,0,0,0,1"
				"mat4": value_str = "1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1"
				"ivec2": value_str = "0,0"
				"ivec3": value_str = "0,0,0"
				"ivec4": value_str = "0,0,0,0"
				"uvec2": value_str = "0,0"
				"uvec3": value_str = "0,0,0"
				"uvec4": value_str = "0,0,0,0"
				"bvec2": value_str = "false,false"
				"bvec3": value_str = "false,false,false"
				"bvec4": value_str = "false,false,false,false"
				_:
					value_str = ""
		
		if var_name.is_empty():
			continue
		
		# 根据类型和值字符串解析
		data[var_name] = _parse_value_with_type(value_str, type_str)
	
	if auto_alignment:
		data = _exchange_members(data)
	
	for key in data.keys():
		type_index[key] = typeof(data[key])
		field_list.append(key)
	
	return [data, field_list, type_index]

## 根据类型和值字符串解析
static func _parse_value_with_type(value_str: String, type_str: String):
	if value_str.is_empty():
		# 如果没有值，根据类型返回默认值
		return _get_default_value_by_type(type_str)
	
	# 1. 清理 GLSL 特有的构造前缀和后缀
	if "(" in value_str and ")" in value_str:
		var start = value_str.find("(")
		var end = value_str.rfind(")")
		value_str = value_str.substr(start + 1, end - start - 1)
	
	# 移除 float 后缀 'f' (如 1.0f -> 1.0)
	value_str = value_str.replace("f", "").strip_edges()
	var lower = value_str.to_lower()
	
	if lower == "true": return true
	if lower == "false": return false
	if lower == "null": return null
	
	# 2. 根据类型解析
	match type_str:
		"float":
			return value_str.to_float() if value_str.is_valid_float() else 0.0
		
		"int":
			return value_str.to_int() if value_str.is_valid_int() else 0
		
		"bool":
			return lower == "true"
		
		"vec2":
			var parts = value_str.split(",")
			if parts.size() >= 2:
				return Vector2(
					parts[0].to_float() if parts[0].is_valid_float() else 0.0,
					parts[1].to_float() if parts[1].is_valid_float() else 0.0
				)
			return Vector2.ZERO
		
		"vec3":
			var parts = value_str.split(",")
			if parts.size() >= 3:
				return Vector3(
					parts[0].to_float() if parts[0].is_valid_float() else 0.0,
					parts[1].to_float() if parts[1].is_valid_float() else 0.0,
					parts[2].to_float() if parts[2].is_valid_float() else 0.0
				)
			return Vector3.ZERO
		
		"vec4":
			var parts = value_str.split(",")
			if parts.size() >= 4:
				return Vector4(
					parts[0].to_float() if parts[0].is_valid_float() else 0.0,
					parts[1].to_float() if parts[1].is_valid_float() else 0.0,
					parts[2].to_float() if parts[2].is_valid_float() else 0.0,
					parts[3].to_float() if parts[3].is_valid_float() else 0.0
				)
			return Vector4.ZERO
		
		"mat2":
			var parts = value_str.split(",")
			var nums = []
			for part in parts:
				if part.is_valid_float():
					nums.append(part.to_float())
			# 2x2 矩阵，返回数组
			return nums
		
		"mat3":
			var parts = value_str.split(",")
			var nums = []
			for part in parts:
				if part.is_valid_float():
					nums.append(part.to_float())
			# 3x3 矩阵，返回 Transform2D
			if nums.size() >= 9:
				return Transform2D(
					Vector2(nums[0], nums[1]),
					Vector2(nums[3], nums[4]),
					Vector2(nums[6], nums[7])
				)
			return Transform2D()
		
		"mat4":
			var parts = value_str.split(",")
			var nums = []
			for part in parts:
				if part.is_valid_float():
					nums.append(part.to_float())
			# 4x4 矩阵，返回 Transform3D
			if nums.size() >= 16:
				return Transform3D(
					Vector3(nums[0], nums[1], nums[2]),
					Vector3(nums[4], nums[5], nums[6]),
					Vector3(nums[8], nums[9], nums[10]),
					Vector3(nums[12], nums[13], nums[14])
				)
			return Transform3D()
		
		"ivec2", "uvec2":
			var parts = value_str.split(",")
			if parts.size() >= 2:
				return Vector2i(
					parts[0].to_int() if parts[0].is_valid_int() else 0,
					parts[1].to_int() if parts[1].is_valid_int() else 0
				)
			return Vector2i.ZERO
		
		"ivec3", "uvec3":
			var parts = value_str.split(",")
			if parts.size() >= 3:
				return Vector3i(
					parts[0].to_int() if parts[0].is_valid_int() else 0,
					parts[1].to_int() if parts[1].is_valid_int() else 0,
					parts[2].to_int() if parts[2].is_valid_int() else 0
				)
			return Vector3i.ZERO
		
		"ivec4", "uvec4":
			var parts = value_str.split(",")
			if parts.size() >= 4:
				return Vector4i(
					parts[0].to_int() if parts[0].is_valid_int() else 0,
					parts[1].to_int() if parts[1].is_valid_int() else 0,
					parts[2].to_int() if parts[2].is_valid_int() else 0,
					parts[3].to_int() if parts[3].is_valid_int() else 0
				)
			return Vector4i.ZERO
		
		"bvec2", "bvec3", "bvec4":
			var parts = value_str.split(",")
			var bools = []
			for part in parts:
				bools.append(part.strip_edges().to_lower() == "true")
			return bools
	
	# 3. 默认数值解析
	if value_str.is_valid_int(): 
		return value_str.to_int()
	if value_str.is_valid_float(): 
		return value_str.to_float()
	
	return value_str

## 根据类型获取默认值
static func _get_default_value_by_type(type_str: String) :
	match type_str:
		"float": return 0.0
		"int": return 0
		"bool": return false
		"vec2": return Vector2.ZERO
		"vec3": return Vector3.ZERO
		"vec4": return Vector4.ZERO
		"mat2": return [1.0, 0.0, 0.0, 1.0]
		"mat3": return Transform2D()
		"mat4": return Transform3D()
		"ivec2", "uvec2": return Vector2i.ZERO
		"ivec3", "uvec3": return Vector3i.ZERO
		"ivec4", "uvec4": return Vector4i.ZERO
		"bvec2": return [false, false]
		"bvec3": return [false, false, false]
		"bvec4": return [false, false, false, false]
		_: return null

## 调整字段顺序
static func _exchange_members(data: Dictionary) -> Dictionary:
	# 排序：先按大小，再按类型，最后按名称
	var sorted_keys = data.keys()
	sorted_keys.sort_custom(func(a, b):
		var val_a = data[a]
		var val_b = data[b]
		var type_a = typeof(val_a)
		var type_b = typeof(val_b)
		
		var size_a = TYPE_SIZES.get(type_a, 4)
		var size_b = TYPE_SIZES.get(type_b, 4)
		
		# 1. 按大小降序
		if size_a != size_b:
			return size_a > size_b
		
		# 2. 大小相同按类型
		if type_a != type_b:
			return type_a > type_b
		
		# 3. 类型相同按名称
		return a > b
	)
	
	var ordered_data = {}
	for key in sorted_keys:
		ordered_data[key] = data[key]
	
	return ordered_data

#  <==============================方法2 获取对应的GLSL类型名==============================>
## 获取对应的GLSL类型名
static func get_type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_INT:
			return "uint"
		TYPE_FLOAT:
			return "float"
		TYPE_BOOL:
			return "bool"
		TYPE_VECTOR2:
			return "vec2"
		TYPE_VECTOR3:
			return "vec3"
		TYPE_VECTOR4:
			return "vec4"
		TYPE_COLOR:
			return "vec4"
		TYPE_BASIS:
			return "mat3"
		TYPE_TRANSFORM3D:
			return "mat4"
		TYPE_TRANSFORM2D:
			return "mat3"
		TYPE_QUATERNION:
			return "vec4"
		TYPE_VECTOR2I:
			return "ivec2"
		TYPE_VECTOR3I:
			return "ivec3"
		TYPE_VECTOR4I:
			return "ivec4"
		TYPE_RECT2:
			return "vec4"  # Rect2可表示为(x,y,width,height)
		TYPE_RECT2I:
			return "ivec4" # Rect2i
		TYPE_PLANE:
			return "vec4"  # 平面(normal.x, normal.y, normal.z, d)
		TYPE_AABB:
			return "vec6"  # 需特殊处理，实际上是vec3[2]
		_:
			printerr("不支持的数据类型")
			return str(value)

#  <==============================方法3 生成字段索引==============================>
## 从data字典生成 [0]字段索引字典 [1]数据总长度 [2]数据类型字典[br] 
## layout: 0=push_constant ,1= std140, 2=storage_buffer/std430
## 字段索引字典 {field字段名(string):offset偏移位数(int)}[br]
static func generate_field_index(field_data: Dictionary,data_list:Array, layout :int) -> Array:
	var data = field_data.duplicate()
	var field_index = {}
	var current_offset = 0
	for field in data_list:
		var value = data[field]
		var alignment = _get_type_alignments(value)
		
		# 对齐当前偏移
		if current_offset % alignment != 0:
			var padding = alignment - (current_offset % alignment)
			current_offset += padding
		
		field_index[field] = current_offset
		
		var value_type = typeof(value)
		var size = TYPE_SIZES.get(value_type, 4)
		current_offset += size
# 根据layout对齐总大小
	match layout:
		0,1:  
			var alignment = 16
			if current_offset % alignment != 0:
				current_offset += alignment - (current_offset % alignment)
		2:  
			var alignment = _get_type_alignments(field_data.get(data_list[0]))
			if current_offset % alignment != 0:
				current_offset += alignment - (current_offset % alignment)
	return [field_index, current_offset]

## 辅助方法：获取数据的对齐要求
static func _get_type_alignments(value) -> int:
	var value_type = typeof(value)
	match value_type:
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return 4
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return 8
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return 16
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR, TYPE_RECT2, TYPE_RECT2I:
			return 16
		TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_BASIS, TYPE_AABB, TYPE_PROJECTION:
			return 16
		_:
			# 未知类型，默认为4字节对齐
			printerr("未知类型:", value_type)
			return 4
#  <==============================方法4 原始数据与字节数据转换==============================>
## 获取任意值的原始字节数据
static func get_value_bytes(value: Variant) -> PackedByteArray:
	var value_type = typeof(value)
	
	
	match value_type:
		TYPE_INT:
			return PackedInt32Array([value]).to_byte_array()  # 4字节
		TYPE_FLOAT:
			return PackedFloat32Array([value]).to_byte_array()  # 4字节
		TYPE_BOOL:
			var bool_value = 1 if value else 0
			return PackedInt32Array([bool_value]).to_byte_array()  # 4字节
		TYPE_VECTOR2:
			var vec = value as Vector2
			return PackedFloat32Array([vec.x, vec.y]).to_byte_array()  # 8字节
		TYPE_VECTOR2I:
			var vec = value as Vector2i
			return PackedInt32Array([vec.x, vec.y]).to_byte_array()  # 8字节
		TYPE_VECTOR3:
			var vec = value as Vector3
			return PackedFloat32Array([vec.x, vec.y, vec.z]).to_byte_array()  # 12字节
		TYPE_VECTOR3I:
			var vec = value as Vector3i
			return PackedInt32Array([vec.x, vec.y, vec.z]).to_byte_array()  # 12字节
		TYPE_RECT2I:
			var vec = value
			return PackedInt32Array([vec.position.x, vec.position.y, vec.size.x, vec.size.y]).to_byte_array()
		TYPE_RECT2:
			var vec = value
			return PackedFloat32Array([vec.position.x, vec.position.y, vec.size.x, vec.size.y]).to_byte_array()
			
		TYPE_VECTOR4I:
			var vec = value
			return PackedInt32Array([vec.x, vec.y, vec.z, vec.w]).to_byte_array()  
		TYPE_VECTOR4:
			var vec = value
			return PackedFloat32Array([vec.x, vec.y, vec.z, vec.w]).to_byte_array()  
		TYPE_COLOR:
			var color = value as Color
			return PackedFloat32Array([color.r, color.g, color.b, color.a]).to_byte_array()  
		TYPE_TRANSFORM3D:
			var transform = value as Transform3D
			var basis = transform.basis
			var origin = transform.origin
			# Transform3D 的逻辑数据是 48 字节
			return PackedFloat32Array([
				basis.x.x, basis.x.y, basis.x.z, 0.0,
				basis.y.x, basis.y.y, basis.y.z, 0.0,
				basis.z.x, basis.z.y, basis.z.z, 0.0,
				origin.x, origin.y, origin.z, 1.0
			]).to_byte_array()  # 64字节
		_:
			push_error("不支持的字段类型: ", value_type)
			return PackedByteArray()

## 解析字节为原始数据
static func parse_value_bytes(data: PackedByteArray, type_index: Dictionary, data_list: Array) -> Dictionary:
	var result := {}
	
	if data.is_empty() or data_list.is_empty():
		push_error("字节数据或字段列表为空")
		return result
	
	var current_offset := 0
	var data_size := data.size()
	
	for field_name in data_list:
		if current_offset >= data_size:
			push_warning("数据字节流已提前结束，无法解析字段: ", field_name)
			break
			
		var field_type: int = type_index.get(field_name, TYPE_FLOAT)
		
		var size: int = TYPE_SIZES.get(field_type, 4)
		
		match field_type:
			TYPE_BOOL:
				result[field_name] = data.decode_s32(current_offset) != 0
				
			TYPE_INT:
				result[field_name] = data.decode_s32(current_offset)
				
			TYPE_FLOAT:
				result[field_name] = data.decode_float(current_offset)
				
			TYPE_VECTOR2:
				result[field_name] = Vector2(
					data.decode_float(current_offset),
					data.decode_float(current_offset + 4)
				)
				
			TYPE_VECTOR2I:
				result[field_name] = Vector2i(
					data.decode_s32(current_offset),
					data.decode_s32(current_offset + 4)
				)
				
			TYPE_VECTOR3:
				result[field_name] = Vector3(
					data.decode_float(current_offset),
					data.decode_float(current_offset + 4),
					data.decode_float(current_offset + 8)
				)
				
			TYPE_VECTOR3I:
				result[field_name] = Vector3i(
					data.decode_s32(current_offset),
					data.decode_s32(current_offset + 4),
					data.decode_s32(current_offset + 8)
				)
				
			TYPE_VECTOR4:
				result[field_name] = Vector4(
					data.decode_float(current_offset),
					data.decode_float(current_offset + 4),
					data.decode_float(current_offset + 8),
					data.decode_float(current_offset + 12)
				)
				
			TYPE_VECTOR4I:
				result[field_name] = [
					data.decode_s32(current_offset),
					data.decode_s32(current_offset + 4),
					data.decode_s32(current_offset + 8),
					data.decode_s32(current_offset + 12)
				]
				
			TYPE_COLOR:
				result[field_name] = Color(
					data.decode_float(current_offset),
					data.decode_float(current_offset + 4),
					data.decode_float(current_offset + 8),
					data.decode_float(current_offset + 12)
				)
				
			TYPE_RECT2:
				result[field_name] = Rect2(
					data.decode_float(current_offset),
					data.decode_float(current_offset + 4),
					data.decode_float(current_offset + 8),
					data.decode_float(current_offset + 12)
				)
				
			TYPE_RECT2I:
				result[field_name] = Rect2i(
					data.decode_s32(current_offset),
					data.decode_s32(current_offset + 4),
					data.decode_s32(current_offset + 8),
					data.decode_s32(current_offset + 12)
				)
				
			TYPE_TRANSFORM2D:
				var origin = Vector2(data.decode_float(current_offset), data.decode_float(current_offset + 4))
				var x_axis = Vector2(data.decode_float(current_offset + 16), data.decode_float(current_offset + 20))
				var y_axis = Vector2(data.decode_float(current_offset + 32), data.decode_float(current_offset + 36))
				result[field_name] = Transform2D(x_axis, y_axis, origin)

			TYPE_BASIS:
				var rows_or_cols = [
					Vector3(data.decode_float(current_offset), data.decode_float(current_offset + 4), data.decode_float(current_offset + 8)),
					Vector3(data.decode_float(current_offset + 16), data.decode_float(current_offset + 20), data.decode_float(current_offset + 24)),
					Vector3(data.decode_float(current_offset + 32), data.decode_float(current_offset + 36), data.decode_float(current_offset + 40))
				]
				result[field_name] = Basis(rows_or_cols[0], rows_or_cols[1], rows_or_cols[2])

			TYPE_TRANSFORM3D:
				var b_x = Vector3(data.decode_float(current_offset), data.decode_float(current_offset + 4), data.decode_float(current_offset + 8))
				var b_y = Vector3(data.decode_float(current_offset + 16), data.decode_float(current_offset + 20), data.decode_float(current_offset + 24))
				var b_z = Vector3(data.decode_float(current_offset + 32), data.decode_float(current_offset + 36), data.decode_float(current_offset + 40))
				var origin = Vector3(data.decode_float(current_offset + 48), data.decode_float(current_offset + 52), data.decode_float(current_offset + 56))
				result[field_name] = Transform3D(Basis(b_x, b_y, b_z), origin)
				
			TYPE_PROJECTION:
				var c0 = Vector4(data.decode_float(current_offset), data.decode_float(current_offset + 4), data.decode_float(current_offset + 8), data.decode_float(current_offset + 12))
				var c1 = Vector4(data.decode_float(current_offset + 16), data.decode_float(current_offset + 20), data.decode_float(current_offset + 24), data.decode_float(current_offset + 28))
				var c2 = Vector4(data.decode_float(current_offset + 32), data.decode_float(current_offset + 36), data.decode_float(current_offset + 40), data.decode_float(current_offset + 44))
				var c3 = Vector4(data.decode_float(current_offset + 48), data.decode_float(current_offset + 52), data.decode_float(current_offset + 56), data.decode_float(current_offset + 60))
				result[field_name] = Projection(c0, c1, c2, c3)

			_:
				if size > 0:
					result[field_name] = data.slice(current_offset, current_offset + size)
				else:
					push_warning("遇到动态或不支持的基础类型: ", field_type, "，跳过解析")
					result[field_name] = null
		
		current_offset += size if size > 0 else 0
		
	return result
