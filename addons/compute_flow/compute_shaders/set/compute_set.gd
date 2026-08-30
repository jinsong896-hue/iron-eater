@icon("uid://dcafrg0ni7wdo")
@tool
extends ComputeFlowBase
class_name ComputeSet
## 添加计算着色器set集

@export_storage var set_id:int
## 描述
@export var description: String = ""
## 黑板数据
var black_board :ComputeFlowBlackBoard

## 获取set rid
func get_set()-> RID:
	_set_create()
	return rid

func _set_create()-> RID:
	var uniforms:=[]
	for uniform in get_children():
		if uniform is ComputeUniform :
			await uniform.get_rd_uniform()
			if !uniform.rid:
				printerr("%s 错误"%uniform.name)
			uniforms.append(uniform.rd_uniform)
	rid = rd.uniform_set_create(uniforms, shader_rid, set_id)
	return rid

## 检查是否符合glsl要求
func _is_valid_glsl_identifier(identifier: String) -> bool:
	if identifier.is_empty():
		return false

	# 检查首字符是否为数字
	if identifier[0].is_valid_int():
		return false

	# 检查是否只包含允许的字符
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	var result = regex.search(identifier)

	return result != null

## 编辑器警告
func _get_configuration_warnings() -> PackedStringArray:
	var warnings:PackedStringArray = []

	for child in get_children():
		if child is not ComputeUniform:
			warnings.append("计算着色器子节点必须为Compute_Uniform")

	return warnings
