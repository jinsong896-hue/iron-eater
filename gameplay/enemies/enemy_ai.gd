class_name EnemyAI
extends RefCounted
## 敌人 AI 状态机 —— HD-2D 重构版
## 基于状态机的敌人行为控制
## 状态：Idle → Detect → Chase → Attack → Recover → Dead

enum AIState {
	IDLE,
	DETECT,
	CHASE,
	ATTACK,
	RECOVER,
	DEAD,
}

var _state := AIState.IDLE
var _enemy: EnemyBase
var _player: Player


func _init(enemy: EnemyBase) -> void:
	_enemy = enemy


## 每帧更新
func update(delta: float) -> void:
	_find_player()
	match _state:
		AIState.IDLE:
			_update_idle()
		AIState.CHASE:
			_update_chase(delta)
		AIState.ATTACK:
			_update_attack()
		AIState.RECOVER:
			_update_recover(delta)


func _find_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := _enemy.get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Player


func _update_idle() -> void:
	if _player == null:
		return
	var dist: float = _enemy.global_position.distance_to(_player.global_position)
	if dist <= _enemy.detect_range:
		_state = AIState.CHASE


func _update_chase(_delta: float) -> void:
	if _player == null:
		_state = AIState.IDLE
		return

	var dist: float = _enemy.global_position.distance_to(_player.global_position)
	if dist <= _enemy.attack_range:
		_state = AIState.ATTACK
		return
	if dist > _enemy.detect_range:
		_state = AIState.IDLE
		return


func _update_attack() -> void:
	if _player == null:
		_state = AIState.IDLE
		return


func _update_recover(_delta: float) -> void:
	_state = AIState.CHASE


func get_state() -> AIState:
	return _state


func set_state(new_state: AIState) -> void:
	_state = new_state