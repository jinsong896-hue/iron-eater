class_name DummyEnemy
extends Node2D
## 木桩敌人：受击掉血、死亡掉落、2 秒后复活（原型用）

@export var max_hp := 120.0
@export var defense := 10.0

var hp := 120.0

@onready var hp_label: Label = $HPLabel
@onready var respawn_timer: Timer = $RespawnTimer


func _ready() -> void:
	add_to_group("enemies")
	z_index = 10
	hp = max_hp
	respawn_timer.timeout.connect(_on_respawn)
	_update_label()
	queue_redraw()


func take_damage(amount: float, crit: bool) -> void:
	hp = maxf(hp - amount, 0.0)
	GameState.total_damage += amount
	EventBus.player_damage_dealt.emit(amount, crit)
	_update_label()
	if hp <= 0.0:
		die()


func die() -> void:
	remove_from_group("enemies")
	GameState.kills += 1
	GameState.drop_item(global_position)
	EventBus.enemy_died.emit()
	EventBus.message.emit("木桩被击杀！掉落装备")
	visible = false
	respawn_timer.start()


func _on_respawn() -> void:
	hp = max_hp
	visible = true
	add_to_group("enemies")
	_update_label()


func _update_label() -> void:
	hp_label.text = "HP %d / %d" % [int(ceil(hp)), int(max_hp)]


func _draw() -> void:
	# 占位视觉：靶心
	draw_circle(Vector2.ZERO, 24.0, Color(0.65, 0.25, 0.25))
	draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.95, 0.6, 0.6), 2.0)
	draw_circle(Vector2.ZERO, 8.0, Color(0.95, 0.95, 0.9))
