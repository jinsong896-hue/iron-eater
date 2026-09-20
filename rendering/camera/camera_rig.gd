class_name CameraRig
extends Node3D
## 相机架 —— HD-2D 重构版
## 完全俯视视角，以玩家为中心，不旋转

@export var target: Node3D
@export var follow_speed: float = 8.0
@export var camera_height := 20.0
@export var camera_fov := 30.0

@onready var camera: Camera3D = $Camera3D

## 当前震动 tween（重复震动时先掐掉，避免两条 tween 互相拉扯）
var _shake_tween: Tween = null


func _ready() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	# 伤害飘字要把世界坐标投影成屏幕坐标（见 damage_text_renderer._find_camera）。
	# 它优先按 "camera" 组找——不登记的话会回退到 `get_viewport().get_camera_3d()`，
	# 而 UI 层的 get_viewport() 是**根视口**，根视口里根本没有 Camera3D
	# （3D 世界已被挪进 SubViewport），于是飘字全部堆在屏幕中心。
	camera.add_to_group("camera")
	_setup_camera()
	_connect_screen_shake()
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


## 屏幕震动：给相机一个短促位置脉冲，衰减回零。
##
## **偏移必须加在 Camera3D 上、而不是 rig 本身**：rig 的 position 每帧由
## `_process` lerp 向玩家，直接改 rig.position 会被跟随逻辑对抗
##（先被拉走一半、tween 又往回补 → 俯视投影下是大幅斜向抖动）。
## 相机是 rig 的子节点，改它的局部位置不影响跟随。
##
## **基准是零，不是 camera_height**：`_setup_camera` 已把相机局部位置设为
## Vector3.ZERO（俯视靠 rotation 实现），故偏移围绕零。
## 旧实现的 `_shake_offset` 写的是 `camera_height ± y`（20 上下），
## 一旦被调用相机会瞬间弹到 20 米高再掉回来——本函数此前从未被接线，
## 所以这个 bug 一直没暴露。
func shake(intensity: float, duration: float) -> void:
	if camera == null:
		return
	# 掐掉上一次未播完的震动，否则两次震动会互相拉扯
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var peak := Vector3(
		randf_range(-intensity, intensity), 0.0, randf_range(-intensity, intensity))
	_shake_tween = create_tween()
	_shake_tween.tween_property(camera, "position", peak, duration * 0.35)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(camera, "position", Vector3.ZERO, duration * 0.65)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 接上 `EventBus.screen_shake`。
##
## 此前**零订阅者**：投射物命中（`projectile_manager.gd:298`）与引信爆炸
##（`projectile.gd:342`）都在 emit，但没人接，`shake()` 也无人调用——
## 表现为"爆炸没有任何画面反馈"，且不报错。
## EventBus 走运行时获取（`--script` 测试模式下不存在）。
func _connect_screen_shake() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var bus = tree.root.get_node_or_null("EventBus")
	if bus and not bus.screen_shake.is_connected(shake):
		bus.screen_shake.connect(shake)