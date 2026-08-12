class_name ChaserEnemy
extends CharacterBody2D
## 追踪敌人：NavigationAgent2D 寻路追击玩家
## 寻路网格由 DungeonGenerator 在生成后烘焙（NavigationServer2D）

@export var max_hp := 80.0
@export var defense := 5.0
@export var speed := 140.0
@export var contact_damage := 12.0

var hp := 80.0
var _attack_cooldown := 0.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	add_to_group("enemies")
	_apply_difficulty()
	hp = max_hp


func _physics_process(_delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - _delta, 0.0)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	# 接触攻击
	if global_position.distance_to(player.global_position) < 34.0 and _attack_cooldown <= 0.0:
		_attack_cooldown = 1.0
		if player.has_method("take_damage"):
			player.call("take_damage", contact_damage)
	nav_agent.target_position = player.global_position
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
	else:
		var direction := global_position.direction_to(nav_agent.get_next_path_position())
		velocity = direction * speed
	move_and_slide()
	queue_redraw()


func take_damage(amount: float, _crit: bool) -> void:
	hp -= amount
	if hp <= 0.0:
		GameState.kills += 1
		EventBus.enemy_died.emit()
		GameState.drop_item(global_position)
		queue_free()


## 难度影响敌人生命与伤害（简单 0.8 / 普通 1.0 / 困难 1.3）
func _apply_difficulty() -> void:
	var diff_id := str(GameState.run_info.get("difficulty", "normal"))
	var mult: float = GameCatalog.difficulty_info(diff_id).get("mult", 1.0)
	max_hp *= mult
	contact_damage *= mult


func _draw() -> void:
	draw_circle(Vector2.ZERO, 18.0, Color(0.80, 0.30, 0.22))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.65), 2.0)
