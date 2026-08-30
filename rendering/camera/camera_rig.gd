class_name CameraRig
extends Node3D
## 相机架 —— HD-2D 重构版
## 完全俯视视角，以玩家为中心，不旋转

@export var target: Node3D
@export var follow_speed: float = 8.0
@export var camera_height := 20.0
@export var camera_fov := 30.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	_setup_camera()
	call_deferred("_find_player")


func _find_player() -> void:
	if target != null:
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0] as Node3D


func _process(delta: float) -> void:
	if target == null:
		return

	# 完全俯视：相机在玩家正上方
	var desired := target.global_position
	desired.y += camera_height

	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, weight)


func _setup_camera() -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = camera_fov
	camera.position = Vector3(0, 0, 0)
	# 完全俯视：相机向下看
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true


func set_target(new_target: Node3D) -> void:
	target = new_target


func shake(intensity: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_method(_shake_offset, Vector3.ZERO, Vector3(intensity, intensity, 0), duration / 2.0)
	tween.tween_method(_shake_offset, Vector3(intensity, intensity, 0), Vector3.ZERO, duration / 2.0)


func _shake_offset(offset: Vector3) -> void:
	camera.position = Vector3(
		randf_range(-offset.x, offset.x),
		camera_height + randf_range(-offset.y, offset.y),
		randf_range(-offset.z, offset.z),
	)