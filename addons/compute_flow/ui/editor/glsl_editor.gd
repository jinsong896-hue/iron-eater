@tool
extends Window

## 当前节点
var text_node:TextEdit

@onready var glsl_edit: CodeEdit = $GlslEdit

func updata_editor(cur_node:CodeEdit):
	text_node = cur_node
	glsl_edit.placeholder_text = text_node.placeholder_text
	glsl_edit.text = text_node.text
	title = cur_node.name

func _on_close_requested() -> void:
	text_node.text = glsl_edit.text
	self.queue_free()
