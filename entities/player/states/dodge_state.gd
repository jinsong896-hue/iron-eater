extends PlayerState
## 翻滚状态 —— 0.2s 高速位移 + 无敌帧，不可打断
##
## 搬移自 player.gd 的 _physics_process 翻滚分支。
## 注：原实现在位移结束的当帧会 fall-through 继续执行移动逻辑；
## 状态机下结束帧只发转移信号，移动从下一帧开始（差 1 物理帧 ≈16ms，
## 无测试覆盖，接受该差异以免引入同帧重入的复杂度）。

## 翻滚方向（enter 时由 MoveState 通过 data 传入）
var _direction := Vector3.ZERO


func enter(_previous: String, data: Dictionary = {}) -> void:
	var p := player
	_direction = data.get("direction", p._facing)
	p.velocity = _direction * p.dodge_speed
	p._is_dodging = true
	p.dodge_timer = p.dodge_duration
	p._dodge_cooldown_timer = p.dodge_cooldown
	EventBus.player_moved.emit(p.global_position, _direction)


func exit() -> void:
	player._is_dodging = false


func physics_update(delta: float) -> void:
	var p := player
	p.dodge_timer -= delta
	if p.dodge_timer <= 0.0:
		finished.emit("MoveState", {})
		return
	p.move_and_slide()
