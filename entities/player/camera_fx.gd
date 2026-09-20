class_name PlayerCameraFx
extends Node
## 玩家的屏幕震动组件 —— 战斗反馈的**投递方**，不自己写相机。
##
## ## 为什么偏移加在**相机节点**上而不是 rig
##
## `CameraRig._process` 每帧把 rig 的 position lerp 向玩家。直接改
## `rig.position` 会被跟随逻辑对抗——先被拉走一半、再往回补，
## 表现为**大幅斜向抖动**（而不是短促的震）。相机是 rig 的子节点，
## 改它的**局部** position 不影响跟随逻辑。这一条是踩坑换来的，别改回去。
##
## ## 与 CameraRig.shake 的关系：**投递，不竞争**
##
## 项目里原本有两条并存的震动路径，各写各的相机位置、互不知晓：
##   · 本组件（player 直写相机局部位置）—— 命中/落地斩等战斗反馈
##   · `CameraRig.shake()` —— 由 `EventBus.screen_shake` 驱动（爆炸）
## 两条 tween 写同一个属性、写的是绝对值，后启动的会**直接覆盖**先启动的
## ——表现为"爆炸震屏被吃掉"或震幅随机。
##
## 现已收敛：`CameraRig` 是**唯一的执行者**，持有一份震动状态、逐帧写位置；
## 本组件只负责**把战斗反馈的请求投递过去**。
## 冲突策略（取强者）见 `CameraRig.shake()` 的注释。

## 玩家节点（构造时注入；本组件只用它找兄弟 CameraRig）
var player: Node3D = null

## 战斗反馈震动的默认时长（秒）。
##
## **与原实现一致**：原实现是"加一次偏移 + 0.2 秒线性归零"，
## 故时长取 0.2 保持手感不变。CameraRig 的包络是"前 35% 升到峰值、
## 之后衰减"，与原"瞬间偏移再归零"的起手略有差别（更平滑），
## 但峰值与总时长相同。
const SHAKE_DURATION := 0.2


## 装配：注入玩家节点
func setup(owner_player: Node3D) -> void:
	player = owner_player


## 屏幕震动：把一次震动请求投递给 CameraRig。
##
## strength 是水平面上的峰值偏移（米）。找不到 CameraRig 时静默返回
## （测试场景可能没有相机架，不该因此报错）。
func shake(strength: float) -> void:
	var rig: Node = _camera_rig()
	if rig == null:
		return
	rig.call("shake", strength, SHAKE_DURATION)


## 取兄弟节点 CameraRig（没有则 null）
func _camera_rig() -> Node:
	if player == null:
		return null
	return player.get_node_or_null("../CameraRig")
