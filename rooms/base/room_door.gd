class_name RoomDoor
extends Node2D
## 动态门：关闭→开启动画→可通过
## 精灵图：door_<方向>_spritesheet.png，帧0=关闭 帧1-3=开启动画

enum Direction { NORTH, EAST, SOUTH, WEST }

signal used(door: RoomDoor)
signal opened(door: RoomDoor)

@export var direction: Direction = Direction.NORTH
@export var door_sprite_path: String = ""  ## 门精灵图目录
var target_room_data: RoomData = null
var locked := false:
	set(v):
		locked = v
		if v:
			_close()
		else:
			_open()

var _anim: AnimatedSprite2D
var _anim_finished := false


func _ready() -> void:
	_ensure_children()
	var trigger: Area2D = get_node_or_null("Trigger")
	if trigger:
		if not trigger.body_entered.is_connected(_on_body_entered):
			trigger.body_entered.connect(_on_body_entered)
	if locked:
		_close()
	else:
		_open()


func _ensure_children() -> void:
	_anim = get_node_or_null("DoorAnim") as AnimatedSprite2D
	if _anim == null:
		_anim = AnimatedSprite2D.new()
		_anim.name = "DoorAnim"
		_anim.centered = true
		_anim.sprite_frames = SpriteFrames.new()
		_anim.sprite_frames.add_animation("closed")
		_anim.sprite_frames.add_animation("opening")
		_anim.sprite_frames.set_animation_loop("opening", false)
		_anim.animation_finished.connect(_on_anim_finished)
		add_child(_anim)
		_load_sprites()
	# 碰撞
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


func _load_sprites() -> void:
	var dir_name := ""
	match direction:
		Direction.NORTH: dir_name = "north"
		Direction.SOUTH: dir_name = "south"
		Direction.EAST: dir_name = "east"
		Direction.WEST: dir_name = "west"
	var base := door_sprite_path + "/door_" + dir_name if not door_sprite_path.is_empty() else ""
	# 加载关闭帧
	if not base.is_empty() and ResourceLoader.exists(base + "_closed.png"):
		_add_texture("closed", load(base + "_closed.png"))
	else:
		_add_fallback("closed", Color(0.35, 0.3, 0.25))
	# 加载开启动画帧
	var loaded := false
	if not base.is_empty():
		for i in range(3):
			var path := base + "_open_%d.png" % i
			if ResourceLoader.exists(path):
				_add_texture("opening", load(path))
				loaded = true
	if not loaded:
		_add_fallback("opening", Color(0.45, 0.4, 0.35))
		_add_fallback("opening", Color(0.5, 0.45, 0.4))
		_add_fallback("opening", Color(0.55, 0.5, 0.45))


func _add_texture(anim: String, tex: Texture2D) -> void:
	_anim.sprite_frames.add_frame(anim, tex)


func _add_fallback(anim: String, col: Color) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(col)
	_add_texture(anim, ImageTexture.create_from_image(img))


func _close() -> void:
	_anim_finished = false
	_anim.play("closed")
	_set_blocker(true)


func _open() -> void:
	if _anim_finished:
		return
	_anim.play("opening")
	_anim_finished = true


func _on_anim_finished() -> void:
	if _anim.animation == "opening":
		_set_blocker(false)
		opened.emit(self)


func _set_blocker(active: bool) -> void:
	var blocker := get_node_or_null("Blocker")
	if blocker:
		blocker.set_deferred("collision_layer", 1 if active else 0)
		blocker.set_deferred("collision_mask", 1 if active else 0)


func set_locked(value: bool) -> void:
	locked = value


func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body.is_in_group("player"):
		used.emit(self)