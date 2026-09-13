extends PlayerState
## 奔跑攻击状态 —— 0.18s 冲撞位移
##
## 搬移自 player.gd 的 _physics_process 冲撞分支。
## 伤害判定是单帧的，在 enter() 里通过 player._start_sprint_attack() 一次性结算；
## 本状态只负责位移推进。结束帧差 1 物理帧同 DodgeState。

func enter(_previous: String, _data: Dictionary = {}) -> void:
	# 一次性：判定参数、结算矩形伤害、置冲撞计时器（同步）
	player._start_sprint_attack()
	# 连段机拒绝（attack_in_progress）时计时器不会置位，立即让回默认状态
	if player._sprint_attack_timer <= 0.0:
		finished.emit("MoveState", {})


func physics_update(_delta: float) -> void:
	var p := player
	if p._sprint_attack_timer <= 0.0:
		finished.emit("MoveState", {})
		return
	p.velocity = p._sprint_attack_dir * p.sprint_speed
	p.move_and_slide()
