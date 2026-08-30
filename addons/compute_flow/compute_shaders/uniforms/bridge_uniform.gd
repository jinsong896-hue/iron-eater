@icon("uid://bw8f3nk17fpcg")
@tool
extends ComputeUniform
class_name BridgeUniform 
## 桥接不同着色器的uniform数据[br]
@export var uniform :ComputeUniform

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	uniform.rd_change.connect(on_uniform_rd_change)
	
## <==============================公有方法==============================>##

func on_uniform_rd_change():
	get_rd_uniform()
	print("%s改变，源uniform：%s 发生变化"%[uniform_name,uniform.uniform_name])

func _set_uniform()-> RID:
	rid = uniform.rid
	return rid
	
##  绑定到RDuniform
func get_rd_uniform() -> RDUniform:
	#await uniform.rd_change
	_set_uniform()
	rd_uniform = uniform.rd_uniform
	return rd_uniform

##  获取当前uniform在glsl的语句
func get_declaration(set:int)->String:
	if !uniform:
		return ""
	uniform = uniform.duplicate()
	uniform.description = description
	uniform.uniform_name = uniform_name
	var declaration = uniform.get_declaration(set)
	uniform.queue_free()
	return declaration 
