class_name PlayerCameraFx
extends Node
## 玩家的屏幕震动组件。
##
## ## 为什么偏移加在**相机节点**上而不是 rig
##
## `CameraRig._process` 每帧把 rig 的 position lerp 向玩家。直接改
## `rig.position` 会被跟随逻辑对抗——先被拉走一半、tween 又往回补，
## 0.2 秒内来回震荡，俯视投影下表现为**大幅斜向抖动**（而不是短促的震）。
##
## 相机是 rig 的子节点，改它的**局部** position 不影响跟随逻辑，
## 震完 tween 归零即可。这一条是踩坑换来的，别改回去。
##
## ## 与 CameraRig.shake 的关系（**待用户决策**）
##
## 项目里目前有两条并存的震动路径：
##   · 本组件（player 直写相机局部位置）—— 近战命中/受击等战斗反馈
##   · `rendering/camera/camera_rig.gd` 的 `shake()` —— 由 EventBus.screen_shake 驱动
## 两者互不知晓，同时触发会叠加。**是否合并留给用户拍板**——
## 合并属于行为变化，超出"零行为重构"的范围，故本次只做位置搬迁。

## 玩家节点（构造时注入；本组件只用它找兄弟 CameraRig 与创建 tween）
var player: Node3D = null

## 震动随机源。独立实例（不用全局 randi）以便将来做可复现的测试。
var _rng := RandomNumberGenerator.new()


## 装配：注入玩家节点
func setup(owner_player: Node3D) -> void:
	player = owner_player


## 屏幕震动：给 rig 下的 Camera3D 一个短促位置脉冲，指数衰减回零。
##
## strength 是水平面上的最大随机偏移（米）。
func shake(strength: float) -> void:
	if player == null:
		return
	var rig := player.get_node_or_null("../CameraRig")
	if rig == null:
		return
	var cam := rig.get_node_or_null("Camera3D") as Node3D
	if cam == null:
		return
	var offset := Vector3(
		_rng.randf_range(-strength, strength),
		0.0,
		_rng.randf_range(-strength, strength)
	)
	cam.position += offset
	var tween := player.create_tween()
	tween.tween_property(cam, "position", Vector3.ZERO, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
