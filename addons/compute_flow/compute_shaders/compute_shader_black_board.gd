@tool
extends Resource
class_name ComputeFlowBlackBoard
## 计算着色器黑板资源
## 用来添加 宏|结构体

## 计算着色器开始运行
signal compute_run()
signal compute_restart()

var is_dirty:= false

## 着色器文件
@export_file("*.glsl","*.gdshaderinc") var glsl_file : String = "":
	set(value):
		glsl_file = value
		emit_changed()
## 计算着色器描述，会添加到glsl注释
@export var description: String = ""

## 全局线程总数，比如图片512 * 512 线程总数为 Vector3i(512,512,1)
@export var global_size: Vector3i = Vector3i(1920,1080, 1):
	set(value):
		global_size = Vector3i(max(value.x,1),
			max(value.y,1),
			max(value.z,1))
		emit_changed()

## 工作组线程数 ！最大工作组线程数通常是 1024
@export var local_size: Vector3i = Vector3i(8, 8, 1):
	set(value):
		# 限制在1-64范围内
		local_size = Vector3i(clampi(value.x, 1,128),
			clampi(value.y, 1,128),
			clampi(value.z, 1,128))
		emit_changed()

## 宏
@export_multiline() var macro :="#define PI 3.141592653589793\n#define SMOOTHSTEP(x) (x*x*(3.0-2.0*x))":
	set(value):
		macro = value
		emit_changed()

## PushConstants 用于传递少量、频繁变化的数据（通常小于 128-256 字节）
@export var push_constant:PushConstant:
	set(value):
		push_constant = value
		emit_changed()

## 结构体
@export var structs:Array[Struct]:
	set(value):
		structs = value
		emit_changed()

func _init() -> void:
	changed.connect(_scan)


func _scan():
	if Engine.is_editor_hint():
		if resource_path:
			ResourceSaver.save(self)
			print_rich("[color=#888888]黑板数据更新[/color]")
			
