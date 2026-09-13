extends PlayerState
## 死亡状态 —— 不做任何每帧推进
##
## 死亡的实质处理（音效 / 结算 / 停物理 / 隐藏）由 Player.die() 负责——
## 那里会被 GameManager.finish_run 触发暂停，本状态只需保证
## 死亡后不再有任何每帧行为（原实现靠 set_physics_process(false) 达成）。

func enter(_previous: String, _data: Dictionary = {}) -> void:
	player.velocity = Vector3.ZERO


func physics_update(_delta: float) -> void:
	pass
