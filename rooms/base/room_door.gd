class_name RoomDoor
extends Node2D
## 房间门：《房间生成.md》—— 检测门（Area2D）与实体门（StaticBody2D）分离

enum Direction { NORTH, EAST, SOUTH, WEST }

signal used(door: RoomDoor)

@export var direction: Direction = Direction.NORTH
@export var target_room_id := ""
@export var target_spawn_id := "DEFAULT"
var target_room_data: RoomData = null

var locked := false


func _ready() -> void:
	_ensure_children()
	var trigger: Area2D = get_node_or_null("Trigger")
	if trigger:
		if not trigger.body_entered.is_connected(_on_body_entered):
			trigger.body_entered.connect(_on_body_entered)
	set_locked(locked)


func _ensure_children() -> void:
	if get_node_or_null("DoorVisual") == null:
		var visual := Polygon2D.new()
		visual.name = "DoorVisual"
		var horizontal := direction == Direction.NORTH or direction == Direction.SOUTH
		var size := Vector2(192, 128) if horizontal else Vector2(128, 192)
		visual.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y),
		])
		visual.color = Color(0.45, 0.4, 0.35)
		visual.position = -size / 2.0
		add_child(visual)
	if get_node_or_null("Blocker") == null:
		var blocker := StaticBody2D.new()
		blocker.name = "Blocker"
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(192, 128) if direction == Direction.NORTH or direction == Direction.SOUTH else Vector2(128, 192)
		shape.shape = box
		blocker.add_child(shape)
		add_child(blocker)
	if get_node_or_null("Trigger") == null:
		var trigger := Area2D.new()
		trigger.name = "Trigger"
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(192, 96) if direction == Direction.NORTH or direction == Direction.SOUTH else Vector2(96, 192)
		shape.shape = box
		trigger.add_child(shape)
		add_child(trigger)


func set_locked(value: bool) -> void:
	locked = value
	var blocker := get_node_or_null("Blocker")
	if blocker:
		blocker.set_deferred("collision_layer", 1 if locked else 0)
		blocker.set_deferred("collision_mask", 1 if locked else 0)
	var visual: CanvasItem = get_node_or_null("DoorVisual")
	if visual:
		visual.modulate.a = 1.0 if locked else 0.3


func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body.is_in_group("player"):
		used.emit(self)
