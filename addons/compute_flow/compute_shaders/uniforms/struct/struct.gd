@tool
extends Resource
class_name Struct
## 结构体数据

## 结构体名称
@export var struct_name:="struct":
	set(value):
		if value == "":
			printerr("结构体名称不能为空")
		struct_name = value
		resource_name=value
## 描述 
@export var description: String = ""

# ==================== 导出变量 ==================== ##
## key : value 或 key = value[br]
## 使用换行进行分割，字段之间不要加逗号[br]
## 整型和浮点型会根据小数点自动识别[br]
## -------------------------------[br]
## 矢量描述  mouse:0.0,0.0 [br]
## 生成配置模板时会自动重新排序，不要手动修改[br]
## -------------------------------[br]
## 不支持: [br]
## - 字符串、数组、字典、对象、通用容器（Array、Dictionary）[br]
## - 资源、信号、RID
@export_multiline var fields := ""
## 自动对齐[br]
## 自动调整字段顺序，减少数据填充[br]
## 在需要完全自定义优化的情况下关闭
@export var auto_alignment = true
## 在编辑器中配置 data 数据[br]
## 该字典应该只在初始化时配置，在运行过程中禁止修改字典结构
@export var data: Dictionary = {}
@export var data_list:=[]
@export_storage var type_index:={}

func _init() -> void:
	fields = "vec2 resolution = vec2(1920, 1080)
vec2 inv_resolution = vec2(0.00052,0.000926)
float delta_time= 0.016666
float scale= 1.0"

# ==================== 公共接口 ==================== #
## 根据data生成GLSL结构体定义
func generate_struct() -> String:
	if data.is_empty():
		return ""
	
	var lines := PackedStringArray()
	lines.append("struct %s { //%s" % [struct_name,description])
	
	for member_name in data_list:
		var value = data[member_name]
		var type_name = ComputeFlowTool.get_type_name(value)
		lines.append("\t%s %s;" % [type_name, member_name])
	
	lines.append("};")
	return "\n".join(lines)
# ==================== 编辑器工具 ==================== ##
## 解析文本并应用到配置
func add_field_to_data() -> void:
	var datas:=  ComputeFlowTool.field_to_data(fields,auto_alignment)
	data = datas[0]
	data_list= datas[1]
	take_over_path(self.resource_path)
