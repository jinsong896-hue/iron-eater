@icon("uid://b53q0shhy3bym")
@tool
extends ComputeSet
class_name DoubleBufferingSet

## 双缓冲set
## 可以交换两个子缓冲区节点(image buffer | storage buffer) [br]
## 只支持两个缓冲区节点,且会在每帧自动交换两个buffer[br]

@export var current_buffer :ComputeUniform
@export var next_buffer :ComputeUniform

var set_a :RID 
var set_b :RID 
var use_set_a:= true

signal uniform_change()

func _ready() -> void:
	if Engine.is_editor_hint():
		return

func get_set()-> RID:
	await current_buffer.get_rd_uniform()
	await next_buffer.get_rd_uniform()
	
	var uniforms_a:=[]
	var uniforms_b:=[]

	uniforms_a.append(current_buffer.rd_uniform)
	uniforms_a.append(next_buffer.rd_uniform)
	
	var next_buffer_b=duplicate_rd_uniform(next_buffer.rd_uniform,0)
	var current_buffer_b= duplicate_rd_uniform(current_buffer.rd_uniform,1)
	
	uniforms_b.append(next_buffer_b)
	uniforms_b.append(current_buffer_b)
	
	set_a = rd.uniform_set_create(uniforms_a, shader_rid, set_id)
	set_b = rd.uniform_set_create(uniforms_b, shader_rid, set_id)
	swap_set()
	return rid

## 交换AB set 
func swap_set():
	
	if use_set_a:
		rid = set_a
	else:
		rid = set_b

	use_set_a =!use_set_a
	uniform_change.emit()


## 编辑器警告
func _get_configuration_warnings() -> PackedStringArray:
	var warnings:PackedStringArray = []
	
	for child in get_children():
		if child is not ComputeUniform:
			warnings.append("DoubleBufferingSet子节点必须为Compute_Uniform")

	return warnings

func duplicate_rd_uniform(original: RDUniform,binding:int) -> RDUniform:
	var copy = RDUniform.new()
	copy.uniform_type = original.uniform_type
	copy.binding = binding
	
	for rid in original.get_ids():
		copy.add_id(rid)
	return copy
