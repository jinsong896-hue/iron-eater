class_name Player
extends CharacterBody2D
## 玩家原型：俯视角移动 + 鼠标朝向普攻（扇形判定，伤害走 DamagePipeline）

@export var move_speed_factor := 2.4
@export var base_attack_interval := 0.6

var _attack_timer := 0.0


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * GameState.stat_value("spd") * move_speed_factor
	move_and_slide()
	if Input.is_action_just_pressed("attack"):
		try_attack()
	queue_redraw()


func try_attack() -> void:
	if _attack_timer > 0.0:
		return
	var aspd := GameState.stat_value("aspd")
	_attack_timer = base_attack_interval / maxf(aspd, 0.1)
	var atk := GameState.stat_value("atk")
	var attack_range := GameState.stat_value("rng")
	var crt := GameState.stat_value("crt")
	var crd := GameState.stat_value("crd")
	var face_dir := (get_global_mouse_position() - global_position).normalized()
	var hit_any := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy2d := enemy as Node2D
		if enemy2d == null or not enemy2d.has_method("take_damage"):
			continue
		var to_enemy: Vector2 = enemy2d.global_position - global_position
		if to_enemy.length() > attack_range:
			continue
		if to_enemy.normalized().dot(face_dir) < 0.3:
			continue
		var crit := randf() < crt
		var target_def: float = enemy2d.get("defense")
		var result := DamagePipeline.physical(atk, 1.0, 0.0, target_def)
		var total := DamagePipeline.with_crit(result.damage, crit, crd)
		enemy2d.call("take_damage", total, crit)
		hit_any = true
	if hit_any:
		EventBus.message.emit("攻击命中（ATK %.0f）" % atk)


func _draw() -> void:
	# 占位视觉：身体圆 + 朝向线
	draw_circle(Vector2.ZERO, 16.0, Color(0.35, 0.6, 0.95))
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(0.9, 0.95, 1.0), 2.0)
	var dir := (get_global_mouse_position() - global_position).normalized()
	draw_line(Vector2.ZERO, dir * 30.0, Color(0.95, 0.95, 0.9), 3.0)
