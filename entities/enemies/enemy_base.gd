class_name EnemyBase
extends CharacterBody3D
## 敌人基类 —— HD-2D 重构版
## 3D 敌人通用基类，包含状态机、AI 追踪、战斗、死亡

# 基础属性
@export var max_hp: float = 100.0
@export var atk: float = 10.0
@export var defense: float = 5.0
@export var move_speed: float = 2.0
@export var attack_range: float = 2.0
@export var detect_range: float = 10.0
@export var attack_interval: float = 1.0

# AI 行为
enum AIBehavior {
	MELEE_CHASE,
	RANGED_KITE,
	PATROL,
	STATIONARY,
}

@export var behavior := AIBehavior.MELEE_CHASE

# 状态
enum EnemyState {
	IDLE,
	DETECT,
	CHASE,
	ATTACK,
	RECOVER,
	DEAD,
}

## 死亡信号（RoomController 计数、LootSystem 掉落都监听它）
signal died(world_position: Vector3)

@export var loot_table: String = ""  ## 掉落表 ID（空 = 默认白装池）
@export var gold_min := 3
@export var gold_max := 12

var _current_state := EnemyState.IDLE
var _hp: float
var _attack_timer := 0.0
var _player  # Player（动态类型：避免 --script 测试模式下 class_name 编译依赖）


func _ready() -> void:
	add_to_group("enemies")
	_hp = max_hp
	_find_player()
	_create_visual()


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]


## 创建临时视觉模型
func _create_visual() -> void:
	var model := MeshInstance3D.new()
	model.name = "Model"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	model.mesh = capsule
	model.position = Vector3(0, 0.9, 0)
	var mat := StandardMaterial3D.new()
	match behavior:
		AIBehavior.MELEE_CHASE:
			mat.albedo_color = Color(0.8, 0.2, 0.2)  # 红色近战
		AIBehavior.RANGED_KITE:
			mat.albedo_color = Color(0.2, 0.2, 0.8)  # 蓝色远程
		_:
			mat.albedo_color = Color(0.5, 0.3, 0.7)  # 紫色特殊
	model.material_override = mat
	add_child(model)


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	if _player == null:
		_find_player()
		if _player == null:
			return

	match _current_state:
		EnemyState.IDLE:
			_state_idle()
		EnemyState.CHASE:
			_state_chase(delta)
		EnemyState.ATTACK:
			_state_attack()
		EnemyState.RECOVER:
			_state_recover(delta)
		EnemyState.DEAD:
			pass


func _state_idle() -> void:
	var dist: float = global_position.distance_to(_player.global_position)
	if dist <= detect_range:
		_current_state = EnemyState.CHASE


func _state_chase(delta: float) -> void:
	var dist: float = global_position.distance_to(_player.global_position)

	# 进入攻击范围
	if dist <= attack_range:
		_current_state = EnemyState.ATTACK
		return

	# 超出侦测范围
	if dist > detect_range:
		_current_state = EnemyState.IDLE
		return

	# 追踪玩家
	var direction: Vector3 = (_player.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * move_speed
	move_and_slide()

	# 朝向玩家
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)


func _state_attack() -> void:
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > attack_range:
		_current_state = EnemyState.CHASE
		return

	if _attack_timer > 0.0:
		return

	_attack_timer = attack_interval
	_perform_attack()


func _state_recover(delta: float) -> void:
	_current_state = EnemyState.CHASE


func _perform_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	var player_def := 0.0
	var gm = _game_manager()
	if gm:
		player_def = gm.stat_value("def")
	var result = DamagePipeline.physical(atk, 1.0, 0.0, player_def)
	_player.take_damage(result.damage)
	var bus = _event_bus()
	if bus:
		bus.damage_dealt.emit(self, _player, result.damage, "physical", false)


func take_damage(amount: float, _is_crit: bool = false) -> void:
	_hp = maxf(_hp - amount, 0.0)
	var gm = _game_manager()
	if gm:
		gm.total_damage += amount

	if _hp <= 0.0:
		die()


func die() -> void:
	_current_state = EnemyState.DEAD
	var gm = _game_manager()
	if gm:
		gm.kills += 1
	var bus = _event_bus()
	if bus:
		bus.enemy_died.emit(self, global_position, [])
	died.emit(global_position)

	# 掉落（挂在房间节点下，随房间销毁）
	if gm:
		var loot := LootSystem.new()
		var parent := get_parent()
		if parent:
			loot.generate_loot(self, global_position, parent)

	set_physics_process(false)
	hide()
	# 延迟销毁
	await get_tree().create_timer(0.5).timeout
	queue_free()


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var node := get_node_or_null("/root/GameManager")
	return node


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var node := get_node_or_null("/root/EventBus")
	return node