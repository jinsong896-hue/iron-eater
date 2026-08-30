@icon("uid://bw8f3nk17fpcg")
@abstract
@tool
extends ComputeFlowBase
class_name ComputeUniform 
## 计算着色器变量

## 完成设置,rd_uniform 发生变化
signal rd_change() 
@export var debug:= false

## 根据 GLSL 语言规范，标识符必须由字母、数字和下划线组成，且首字符不能是数字
@export var uniform_name: String = "uniform":
	set(value):
		uniform_name = value
		name = uniform_name
		update_configuration_warnings()

## 描述 
@export var description: String = ""
## 变量绑定位
@export_storage var binding:int

## 黑板数据
@export var black_board :ComputeFlowBlackBoard

## 着色器变量
var rd_uniform: RDUniform
## 变量类型
var uniform_type:= RenderingDevice.UNIFORM_TYPE_IMAGE
## glsl语句
var declaration

## 图片格式限定符枚举
enum FormatQualifier {
	RGBA8,     # rgba8 - 8位RGBA
	RG8,       # rg8   - 8位RG
	R8,        # r8    - 8位单通道
	RGBA16F,   # rgba16f - 16位浮点RGBA
	RGBA32F,   # rgba32f - 32位浮点RGBA
	R32F,      # r32f  - 32位浮点单通道
	RG16F,     # rg16f - 16位浮点RG
	RG32F,     # rg32f - 32位浮点RG
	}

##  返回绑定好的 RDuniform
@abstract func get_rd_uniform() -> RDUniform;

##  获取当前 uniform在glsl的语句
@abstract func get_declaration(set:int)->String;

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_rd_uniform()
	print("%s ready"% uniform_name , rid)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings:PackedStringArray = []
	
	if uniform_name=="":
		warnings.append("需要设置uniform变量名")
	
	if !_is_valid_glsl_identifier(uniform_name):
		warnings.append("%s 无效 : " % uniform_name +
		"\n 根据 GLSL 语言规范，标识符必须由字母、数字和下划线组成，且首字符不能是数字")
	return warnings

## 检查命名是否符合glsl要求
func _is_valid_glsl_identifier(identifier: String) -> bool:
	if identifier.is_empty():
		return false
	
	# 长度检查
	if identifier.length() > 1024:
		return false
	
	# 首字符检查
	var first_char = identifier[0]
	if not (
		(first_char >= 'a' and first_char <= 'z') or
		(first_char >= 'A' and first_char <= 'Z') or
		first_char == '_'
	):
		return false
	
	# GLSL保留关键字
	var reserved_keywords = [
		"input","output",
		"attribute", "const", "uniform", "varying", "buffer", "shared",
		"layout", "centroid", "flat", "smooth", "noperspective", "patch", "sample",
		"in", "out", "inout", "highp", "mediump", "lowp", "precision",
		"invariant", "precise", "if", "else", "switch", "case", "default",
		"for", "while", "do", "break", "continue", "return", "discard",
		"struct", "void", "coherent", "volatile", "restrict", "readonly", "writeonly"
	]
	
	if identifier in reserved_keywords:
		return false
	
	# 使用正则表达式进行完整验证
	var regex = RegEx.new()
	# 编译正则表达式并处理可能的错误
	if regex.compile("^[a-zA-Z_][a-zA-Z0-9_]*$") != OK:
		# 如果正则表达式编译失败，回退到基本检查
		printerr("无法编译正则表达式，使用基本验证")
		# 手动检查每个字符
		for i in range(identifier.length()):
			var c = identifier[i]
			if not (
				(c >= 'a' and c <= 'z') or
				(c >= 'A' and c <= 'Z') or
				(c >= '0' and c <= '9') or
				c == '_'
			):
				return false
		return true
	
	var result = regex.search(identifier)
	return result != null
