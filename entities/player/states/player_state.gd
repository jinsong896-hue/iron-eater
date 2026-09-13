class_name PlayerState
extends State
## 玩家状态基类 —— 持有 Player 引用，提供跨状态共享的动作
##
## 分工对齐 GameDev.tv 课件：Player 存数据与共享动作，State 存行为。
## 状态通过 player.xxx 读写玩家的数据与方法。
##
## 注意：Player 上的 _start_sprint_attack / _start_jump_attack 等
## 仍是同步置位的公开入口（测试直接调用），状态只在 enter() 里调它们，
## 自己负责每帧推进。

var player: Player = null


## 状态机在注册后调用，注入归属的玩家
func setup(p_player: Player) -> void:
	player = p_player


## 读取当前移动输入方向（无输入返回零向量）
func move_input() -> Vector3:
	return InputManager.get_move_direction_3d()
