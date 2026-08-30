@tool
class_name PushConstant
extends Resource
## 计算着色器的 push_constant 数据管理器
## 自动处理内存对齐、序列化和GLSL代码生成


# ==================== 导出变量 ==================== ##

## push_constant 成员名,可以为空
@export var member_name:=""

## key : value 使用换行进行分割，不要加逗号[br]
## 整型和浮点型会根据小数点识别[br]
## -------------------------------[br]
## 矢量描述  mouse:0.0,0.0 [br]
## 生成配置模板时会重新排序[br]
## -------------------------------[br]
## 不支持: [br]
## - 字符串、数组、字典、对象、通用容器（Array、Dictionary）[br]
## - 资源、信号、RID
@export_multiline var fields := "time:1.0 
frame_index: 1
mouse:0.0,0.0,0.0,0.0
intensity: 1.0
scale: 1.0
seed: 12345"

## 自动对齐[br]
## 自动调整字段顺序，减少数据填充[br]
## 在需要完全自定义优化的情况下关闭
@export var auto_alignment = true
## 在编辑器中配置 data 数据
@export var data: Dictionary = {}
@export var data_list:=[]
@export_storage var type_index:={}
## debug 模式,会打印更多信息
var debug:= false
# ==================== 运行时数据 ==================== ##

## 字段索引，用于快速查找
var _field_index: Dictionary = {}

## 字节化的 push_constant 数据
var buffer_byte := PackedByteArray()

## 总数据大小
var data_size := 0

# ==================== 公共接口 ==================== ##
## 更新单个字段的值
func set_value(key: String, value: Variant) -> void:
	if data_size == 0:
		# 从字典构建字节索引
		var template = ComputeFlowTool.generate_field_index(data,data_list,0)
		_field_index = template[0]
		data_size = template[1]

		buffer_byte.resize( data_size)
		print(_field_index,"\n",data_size )
		if data_size>128:
			printerr("%s 数据超出push constant 上限:%s"%[resource_name , data_size])
			return
		set_values()
		return
	# 直接更新字节数组
	var value_bytes = ComputeFlowTool.get_value_bytes(value)
	var idx = _field_index.get(key,0)
	# 写入字节
	for i in range(value_bytes.size()):
		if idx + i < buffer_byte.size():
			buffer_byte[idx + i] = value_bytes[i]
			
	if debug:
		if not key in data:
			push_error("PushConstant: 字段 '%s' 不存在" % key)
			return
		# 验证类型
		var expected_type = ComputeFlowTool.get_type(data[key])
		var actual_type = ComputeFlowTool.get_type(value)
		if expected_type != actual_type:
			push_error("PushConstant: 字段 '%s' 类型错误" % key)
			return

## 批量更新多个字段
func set_values(updates: Dictionary = {}) -> void:
	if updates == {}:
		for key in data_list:
			set_value(key, data[key])
	for key in updates:
		set_value(key, updates[key])

## 获取序列化的字节数据
func get_byte_array() -> PackedByteArray:
	if data_size ==0:
		set_values()
	return buffer_byte

## 根据当前配置生成GLSL push_constant结构
func get_declaration() -> String:
	var lines = PackedStringArray()
	lines.append("layout(push_constant) uniform PushConstants {")
	for member_name in data_list:
		var value = data[member_name]
		var type_name = ComputeFlowTool.get_type_name(value)
		lines.append("    %s %s;" % [type_name, member_name])

	lines.append("};")
	return "\n".join(lines)

func get_parsed_data() -> Dictionary:
	return ComputeFlowTool.parse_value_bytes(buffer_byte,type_index,data_list)


# ==================== 编辑器工具 ==================== ##
## 解析文本并应用到配置
func add_field_to_data() -> void:
	var datas:=  ComputeFlowTool.field_to_data(fields,auto_alignment)
	data = datas[0]
	data_list= datas[1]
	type_index = datas[2]
	take_over_path(self.resource_path)
