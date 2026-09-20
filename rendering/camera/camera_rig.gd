class_name CameraRig
extends Node3D
## 相机架 —— HD-2D 重构版
## 完全俯视视角，以玩家为中心，不旋转

@export var target: Node3D
@export var follow_speed: float = 8.0
@export var camera_height := 20.0
@export var camera_fov := 30.0

@onready var camera: Camera3D = $Camera3D

## 震动剩余时长（秒）。**两条震动路径共用的唯一状态**，见 shake()。
var _shake_left := 0.0
## 本次震动的强度（米）与总时长，用于计算衰减包络
var _shake_intensity := 0.0
var _shake_duration := 0.0
## 本次震动的随机方向。**整段保持不变**——每帧重掷会让相机抖成噪声而不是"震一下"。
var _shake_dir := Vector3.ZERO


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
	# 震动**先于**跟随处理，且不受 target 缺失影响：
	# 否则开局 target 未就绪时震屏会被整段吞掉。
	_apply_shake(delta)
	if target == null:
		return

	# 完全俯视：相机在玩家正上方
	var desired := target.global_position
	desired.y += camera_height

	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, weight)


## 每帧应用震动偏移。
##
## **逐帧写，不用 tween** —— 这是"两条路径互相感知"的关键。
## 项目里有两条震动来源：本类的 `shake()`（由 `EventBus.screen_shake` 驱动，
## 爆炸用）与 `PlayerCameraFx`（战斗反馈：命中/落地斩）。两者写的是
## **同一个** `camera.position`。各自开 tween 时，tween 写的是**绝对值**，
## 后启动的会把先启动的直接覆盖——表现为"爆炸震屏被吃掉"或震幅随机。
##
## 收敛到"单一状态 + 每帧写"后：谁在震、震多强、还剩多久只有一份真相，
## 两条路径只是**往同一个入口投递请求**（见 shake 的取强者策略）。
##
## ## 包络：立即峰值 + 线性衰减（**保留实际在跑的手感**）
##
## `PlayerCameraFx` 原实现是「`cam.position += offset` 立即偏移，
## 再 0.2 秒 tween 归零」——**这是目前唯一在生产里真正跑过的震动**。
## 本类原先那套「前 35% 升到峰值」的 tween 因零订阅者从未执行过。
## 故统一时采用**前者**的包络，玩家感受到的震感不变。
func _apply_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	if _shake_left <= 0.0:
		camera.position = Vector3.ZERO   # 精确归零（不能留浮点残差）
		return
	# 线性衰减：起手即峰值，与原 tween 的 EASE_OUT 近似（差值在 0.2 秒内不可感）
	var amp := _shake_intensity * (_shake_left / _shake_duration)
	camera.position = _shake_dir * amp


func _setup_camera() -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = camera_fov
	camera.position = Vector3(0, 0, 0)
	# 完全俯视：相机向下看
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true


func set_target(new_target: Node3D) -> void:
	target = new_target


## 屏幕震动：请求一次震动，持续 `duration` 秒、峰值偏移 `intensity` 米。
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
##
## ## 并发策略：取强者
##
## 本类是**唯一的震动执行者**（`PlayerCameraFx` 也投递到这里，见其实现）。
## 新请求与正在播放的震动比较时：
##   · 峰值更高 → 替换（大招的震感不该被小命中盖掉）
##   · 峰值更低 → 忽略（小命中不该打断大招的震动）
## 这样两条路径同时触发时**不会互相覆盖**，而是保留更强的那个。
func shake(intensity: float, duration: float) -> void:
	if camera == null:
		return
	# 正在震动且新请求更弱 → 忽略（不打断更强的那个）
	if _shake_left > 0.0 and intensity <= _shake_intensity:
		return
	_shake_intensity = intensity
	_shake_duration = maxf(duration, 0.0001)
	_shake_left = _shake_duration
	_shake_dir = Vector3(
		randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if _shake_dir.length_squared() < 0.0001:
		_shake_dir = Vector3.RIGHT
	_shake_dir = _shake_dir.normalized()


## 当前是否正在震动（供测试与调试观察）
func is_shaking() -> bool:
	return _shake_left > 0.0


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