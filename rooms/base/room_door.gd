class_name RoomDoor
extends Node2D
## 房间门：支持4方向精灵图 + 前后左右朝向
## 精灵图命名：door_north.png / door_south.png / door_east.png / door_west.png

enum Direction { NORTH, EAST, SOUTH, WEST }

signal used(door: RoomDoor)

@export var direction: Direction = Direction.NORTH
@export var door_sprite_path: String = ""  ## 门精灵图目录路径
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
	# 门精灵
	if get_node_or_null("DoorSprite") == null:
		var sprite := Sprite2D.new()
		sprite.name = "DoorSprite"
		sprite.centered = true
		_load_door_sprite(sprite)
		add_child(sprite)
	# 碰撞体
	if get_node_or_null("Blocker") == null:
		var blocker := StaticBody2D.new()
		blocker.name = "Blocker"
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(192, 128) if direction == Direction.NORTH or direction == Direction.SOUTH else Vector2(128, 192)
		shape.shape = box
		blocker.add_child(shape)
		add_child(blocker)
	# 触发器
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


func _load_door_sprite(sprite: Sprite2D) -> void:
	var dir_name := ""
	match direction:
		Direction.NORTH: dir_name = "north"
		Direction.SOUTH: dir_name = "south"
		Direction.EAST: dir_name = "east"
		Direction.WEST: dir_name = "west"
	var path := door_sprite_path + "/door_" + dir_name + ".png" if not door_sprite_path.is_empty() else ""
	if not path.is_empty() and ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	else:
		# 回退到色块占位
		sprite.texture = null
		_draw_fallback(sprite)


func _draw_fallback(sprite: Sprite2D) -> void:
	sprite.queue_redraw()
	var rect := ColorRect.new()
	rect.name = "FallbackColor"
	rect.color = Color(0.45, 0.4, 0.35)
	rect.size = Vector2(192, 128) if direction == Direction.NORTH or direction == Direction.SOUTH else Vector2(128, 192)
	rect.position = -rect.size / 2.0
	sprite.add_child(rect)


func set_locked(value: bool) -> void:
	locked = value
	var blocker := get_node_or_null("Blocker")
	if blocker:
		blocker.set_deferred("collision_layer", 1 if locked else 0)
		blocker.set_deferred("collision_mask", 1 if locked else 0)
	var sprite: Sprite2D = get_node_or_null("DoorSprite")
	if sprite:
		sprite.modulate.a = 1.0 if locked else 0.3


func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body.is_in_group("player"):
		used.emit(self)
