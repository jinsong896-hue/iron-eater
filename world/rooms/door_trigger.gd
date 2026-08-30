extends Area3D
## 门触发器 —— HD-2D 重构版
## 挂在 Door 场景的 DoorTrigger 节点上

var direction := ""
var is_locked := false
var is_open := true


func lock() -> void:
	is_locked = true
	is_open = false


func unlock() -> void:
	is_locked = false
	is_open = true


func _on_body_entered(body: Node3D) -> void:
	if is_locked or not is_open:
		return
	if body.is_in_group("player"):
		EventBus.door_opened.emit(direction, direction)