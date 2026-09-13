extends PlayerState
## 跳跃攻击状态 —— 后跳 → 俯冲(无敌帧) → 落地 AOE
##
## 搬移自 player.gd 的 _update_jump_attack()。
## 伤害判定（落地 AOE）在阶段推进到 LAND 时同步结算；
## _jump_phase / _jump_phase_timer 仍留在 Player 上（测试直接读取）。

func enter(_previous: String, _data: Dictionary = {}) -> void:
	# 一次性：置三阶段初值与攻击冷却（同步置位，测试依赖）
	player._start_jump_attack()
	if player._jump_phase == Player.JumpPhase.NONE:
		# 连段机拒绝时未进入跳跃，立即让回默认状态
		finished.emit("MoveState", {})


func physics_update(delta: float) -> void:
	var p := player
	p._jump_phase_timer -= delta
	match p._jump_phase:
		Player.JumpPhase.BACKHOP:
			# 后跳：向面向反方向
			p.velocity = -p._jump_attack_dir * (
				GameBalance.JUMP_ATTACK[2] / GameBalance.JUMP_ATTACK_PHASES[0]
			)
			p.move_and_slide()
			if p._jump_phase_timer <= 0.0:
				p._jump_phase = Player.JumpPhase.DIVE
				p._jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[1]
		Player.JumpPhase.DIVE:
			# 俯冲：向前高速位移（无敌帧）
			p.velocity = p._jump_attack_dir * (
				GameBalance.JUMP_ATTACK[3] / GameBalance.JUMP_ATTACK_PHASES[1]
			)
			p.move_and_slide()
			if p._jump_phase_timer <= 0.0:
				p._jump_phase = Player.JumpPhase.LAND
				p._jump_phase_timer = GameBalance.JUMP_ATTACK_PHASES[2]
				p._perform_jump_landing()
		Player.JumpPhase.LAND:
			p.velocity = Vector3.ZERO
			if p._jump_phase_timer <= 0.0:
				p._jump_phase = Player.JumpPhase.NONE
				if p._combo:
					p._combo.end_attack()
				finished.emit("MoveState", {})
		_:
			# 已归零（外部重置）：让回默认状态
			finished.emit("MoveState", {})
