class_name ChaserEnemy
extends CharacterBody2D
## 追踪敌人：NavigationAgent2D 寻路追击玩家
## 寻路网格由 DungeonGenerator 在生成后烘焙（NavigationServer2D）

@export var max_hp := 80.0
@export var defense := 5.0
@export var speed := 140.0

var hp := 80.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
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
		GameState.drop_item(global_position)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 18.0, Color(0.80, 0.30, 0.22))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(1.0, 0.75, 0.65), 2.0)
