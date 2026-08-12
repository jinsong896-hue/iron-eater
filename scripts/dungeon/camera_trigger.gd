class_name CameraTrigger
extends Area2D
## 房间/走廊相机切换触发器：玩家进入后把房间边界交给 RoomCamera

signal player_entered(room_rect: Rect2)

var room_rect := Rect2()


func setup(rect: Rect2) -> void:
	room_rect = rect
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = rect.size
	shape.shape = rect_shape
	shape.position = rect.size / 2.0
	add_child(shape)
	position = rect.position
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(room_rect)
