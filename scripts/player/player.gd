class_name Player
extends CharacterBody2D
## 玩家原型：俯视角移动 + 鼠标朝向普攻（扇形判定，伤害走 DamagePipeline）

@export var move_speed_factor := 2.4
@export var base_attack_interval := 0.6

var _attack_timer := 0.0

const CLASS_COLORS := {
	"warrior": Color(0.45, 0.65, 1.0),
	"mage": Color(0.75, 0.5, 1.0),
	"hunter": Color(0.45, 0.9, 0.5),
	"judge": Color(1.0, 0.7, 0.35),
	"monk": Color(0.95, 0.45, 0.4),
}


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
		AudioManager.play("hit")


func take_damage(amount: float) -> void:
	GameState.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount)
	AudioManager.play("hit")
	if GameState.attributes.hp <= 0.0:
		die()


func die() -> void:
	if not is_inside_tree() or not visible:
		return
	AudioManager.play("death")
	var result := GameState.finish_run("defeated")
	EventBus.run_finished.emit(result)
	set_physics_process(false)
	visible = false


func _draw() -> void:
	# 占位视觉：身体圆 + 朝向线
	var color: Color = CLASS_COLORS.get(str(GameState.run_info.get("character", "warrior")), CLASS_COLORS["warrior"])
	draw_circle(Vector2.ZERO, 16.0, color)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, color.lightened(0.35), 2.0)
	var dir := (get_global_mouse_position() - global_position).normalized()
	draw_line(Vector2.ZERO, dir * 30.0, Color(0.95, 0.95, 0.9), 3.0)
