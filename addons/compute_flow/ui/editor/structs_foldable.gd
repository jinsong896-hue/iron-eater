@tool
extends FoldableContainer

signal on_delete(delete:bool)

@onready var box_container: BoxContainer = $BoxContainer
const STRUCK_EDIT = preload("uid://caoxj2as6gtxb")

var delete_mode:=false
var black_board:ComputeFlowBlackBoard

func _ready() -> void:
	var add_button = Button.new()
	add_button.flat = true
	add_button.icon = preload("uid://civ2j4tdn64qy")
	add_button.custom_minimum_size = Vector2(60,0)
	add_button.tooltip_text = "add new struct"
	add_title_bar_control(add_button)
	add_button.pressed.connect(_on_add_button_pressed)
	
	var remove_button = Button.new()
	remove_button.flat = true
	remove_button.toggle_mode = true
	remove_button.icon = preload("uid://cxdl0usvwx0c7")
	remove_button.custom_minimum_size = Vector2(60,0)
	remove_button.tooltip_text = "delete mode\n"
	add_title_bar_control(remove_button)
	remove_button.toggled.connect(_on_remove_button_toggled)

## 点击添加按钮
func _on_add_button_pressed():
	var stuck_editor =  STRUCK_EDIT.instantiate()
	box_container.add_child(stuck_editor)
	stuck_editor.owner = get_tree().current_scene
	stuck_editor.black_board = black_board
	
	black_board.structs.append(stuck_editor.struct)

## 点击删除按钮
func _on_remove_button_toggled(toggled):
	if toggled:
		delete_mode = true
		on_delete.emit(delete_mode)
	else :
		delete_mode = false
		on_delete.emit(delete_mode)

func sync_structs():
	for i:Node in box_container.get_children():
		i.queue_free()
	for i in black_board.structs:
		var stuck_editor:StructEditor = preload("uid://caoxj2as6gtxb").instantiate()
		box_container.add_child(stuck_editor)
		stuck_editor.owner = get_tree().current_scene
		stuck_editor.black_board = black_board
		stuck_editor.updata_struct(i)
