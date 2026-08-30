@icon("uid://bekv483kwsupx")
@tool
extends StorageBuffer
class_name MutilMeshBuffer

enum MODE{MultiMesh2D,MultiMesh3D}

@export_tool_button("add_struct","RDShaderFile") var add_struct = _add_struct

@export var mode: MODE = MODE.MultiMesh2D
	
@export_custom(PROPERTY_HINT_NODE_TYPE, "MultiMeshInstance2D,MultiMeshInstance3D")
var multimesh_instance:Node:
	set(v):
		multimesh_instance = null
		if mode == MODE.MultiMesh2D:
			if v is MultiMeshInstance2D:
				multimesh_instance = v
			else:
				printerr("当前为2D模式")
				multimesh_instance = null
		else:
			if v is MultiMeshInstance3D:
				multimesh_instance = v
			else:
				printerr("当前为3D模式")
				multimesh_instance = null
var mm_rid:RID

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if not multimesh_instance or not multimesh_instance.multimesh:
		push_error("请先绑定有效的 MultiMeshInstance节点！")
		return
	await rd_change
	var mm: MultiMesh = multimesh_instance.multimesh
	if mm.instance_count == 0:
		mm.instance_count = element_count
	mm_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm.get_rid())
	
	black_board.compute_run.connect(copy_buffer_to_multimesh)
	black_board.compute_restart.connect(rebind_mmi)

func rebind_mmi():
	var mm: MultiMesh = multimesh_instance.multimesh
	var global_size = black_board.global_size
	element_count = global_size.x * global_size.y * global_size.z
	mm.instance_count = 0
	mm.instance_count = element_count
	mm_rid = RenderingServer.multimesh_get_buffer_rd_rid(mm.get_rid())

func copy_buffer_to_multimesh():
	rd.buffer_copy(
		rid,
		mm_rid,
		0,
		0,
		data_size
	)

func _add_struct():
	var mmi_struct:= Struct.new()
	mmi_struct.auto_alignment = false
	match mode:
		0:
			mmi_struct.fields = "vec4 row_1;\nvec4 row_2;\nvec4 color;\nvec4 custom_data;"
			mmi_struct.struct_name = "MutilMesh2D"
		1:
			mmi_struct.fields = "vec4 row_1;\nvec4 row_2;\nvec4 row_3;\nvec4 color;\nvec4 custom_data;"
			mmi_struct.struct_name = "MutilMesh3D"
	if black_board:
		black_board.structs.append(mmi_struct)
		black_board.is_dirty = true
		black_board.changed.emit()
		
	struct = mmi_struct.struct_name
	
	member_name = "mutil_mesh"
