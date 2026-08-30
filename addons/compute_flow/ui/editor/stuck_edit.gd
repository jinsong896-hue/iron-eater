@tool
extends BoxContainer
class_name StructEditor

var struct:Struct
var black_board:ComputeFlowBlackBoard

@onready var structs_name: LineEdit = %StructsName
@onready var delete_button: Button = %DeleteButton
@onready var stuck_edit: TextEdit = %StuckEdit
@onready var auto_alignment_button: CheckButton = %auto_alignment

const GLSL_EDITOR = preload("uid://c5wupgq8n1kt")

func _ready() -> void:
	# 新建结构体
	struct = Struct.new()
	updata_struct(struct)
	
	var structs_foldable = get_parent().get_parent()
	_on_delete_mode(structs_foldable.delete_mode)
	structs_foldable.on_delete.connect(_on_delete_mode)

func _on_delete_mode(delete_mode:bool):
	if delete_mode:
		delete_button.show()
	else :
		delete_button.hide()

## 删除struct
func _on_delete_button_pressed() -> void:
	if black_board.structs.has(struct):
		print("remove struct")
		black_board.structs.erase(struct)
	self.queue_free()

func _on_text_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton :
		if event.button_index ==1 and event.double_click:
			var editor = GLSL_EDITOR.instantiate()
			add_child(editor)
			editor.owner = get_tree().current_scene
			editor.updata_editor(stuck_edit)

## 同步结构体数据到UI 
func updata_struct(_struct:Struct):
	struct = _struct
	structs_name.text = struct.struct_name
	stuck_edit.text = struct.fields
	auto_alignment_button.button_pressed = struct.auto_alignment

func _on_stuck_edit_text_changed() -> void:
	struct.fields = stuck_edit.text

func _on_structs_name_text_changed(new_text: String) -> void:
	struct.struct_name = structs_name.text

## 是否开启自动排序
func _on_auto_alignment_toggled(toggled_on: bool) -> void:
	struct.auto_alignment = toggled_on
