class_name Player
extends CharacterBody2D
## 玩家原型：俯视角移动 + 方向键朝向与普攻（无鼠标攻击）

@export var move_speed_factor := 2.4
@export var base_attack_interval := 0.6

## 每点“射程”属性折算的像素距离（基础射程 1.5 → 约 96px，即 1.5 格）
const ATTACK_REACH := 64.0

var _attack_timer := 0.0
var _facing := Vector2.DOWN

const CLASS_COLORS := {
	"warrior": Color(0.45, 0.65, 1.0),
	"mage": Color(0.75, 0.5, 1.0),
	"hunter": Color(0.45, 0.9, 0.5),
	"judge": Color(1.0, 0.7, 0.35),
	"monk": Color(0.95, 0.45, 0.4),
}


func _ready() -> void:
	add_to_group("player")
	z_index = 10


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * GameState.stat_value("spd") * move_speed_factor
	move_and_slide()
	# 方向键：切换朝向并攻击
	if Input.is_action_just_pressed("attack_up"):
		_facing = Vector2.UP
		try_attack()
	elif Input.is_action_just_pressed("attack_down"):
		_facing = Vector2.DOWN
		try_attack()
	elif Input.is_action_just_pressed("attack_left"):
		_facing = Vector2.LEFT
		try_attack()
	elif Input.is_action_just_pressed("attack_right"):
		_facing = Vector2.RIGHT
		try_attack()
	queue_redraw()


func try_attack() -> void:
	if _attack_timer > 0.0:
		return
	var aspd := GameState.stat_value("aspd")
	_attack_timer = base_attack_interval / maxf(aspd, 0.1)
	var atk := GameState.stat_value("atk")
	# 射程是无单位属性，需按瓦片像素换算后才能与敌人做距离比较
	var attack_range := ATTACK_REACH * maxf(GameState.stat_value("rng"), 0.1)
	var crt := GameState.stat_value("crt")
	var crd := GameState.stat_value("crd")
	var fusion_bonus := GameState.fusion_attack_bonus()
	var face_dir: Vector2 = _facing.normalized()
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
		var crit := GameState.rng.randf() < crt
		var target_def: float = enemy2d.get("defense")
		var result := DamagePipeline.physical(atk, 1.0, fusion_bonus, target_def)
		var total := DamagePipeline.with_crit(result.damage, crit, crd)
		enemy2d.call("take_damage", total, crit)
		EventBus.damage_popup.emit(enemy2d.global_position, total, "crit" if crit else "normal")
		hit_any = true
	if hit_any:
		EventBus.message.emit("攻击命中（ATK %.0f）" % atk)
		AudioManager.play("hit")


func take_damage(amount: float) -> void:
	GameState.attributes.take_damage(amount)
	EventBus.player_hit.emit(amount)
	EventBus.damage_popup.emit(global_position, amount, "player")
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		var screen := get_tree().get_first_node_in_group("equipment_screen") as Control
		if screen:
			screen.visible = not screen.visible
			get_viewport().set_input_as_handled()
	# 鼠标左键普攻：面向鼠标并攻击（demo2：LMB attack）
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_facing = (get_global_mouse_position() - global_position).normalized()
		if _facing.length_squared() < 0.001:
			_facing = Vector2.DOWN
		try_attack()
		get_viewport().set_input_as_handled()
	# E 吞噬最近掉落物（demo2：E devour，本局永久成长）
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		devour_nearby()
		get_viewport().set_input_as_handled()


## 吞噬离玩家最近的掉落物，触发其吞噬词条（本局永久成长）
func devour_nearby() -> void:
	var nearest: ItemPickup = null
	var nearest_d := INF
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node) or not (node is ItemPickup):
			continue
		var d := (node as Node2D).global_position.distance_to(global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = node
	if nearest == null:
		EventBus.message.emit("附近没有可吞噬的掉落物")
		return
	var item: EquipmentInstance = nearest.item
	var display := item.display_name() if item != null else "掉落物"
	var result := GameState.devour_item(item)
	if result.ok:
		nearest.queue_free()
		EventBus.message.emit("吞噬 %s：本局永久成长生效！" % display)
		AudioManager.play("pickup")
	else:
		EventBus.message.emit("%s 无法吞噬" % display)


## 施放演示技能（demo2 核心：Q 火焰斩范围伤害），对敌人造成真实伤害
func cast_skill(skill_id: String) -> Dictionary:
	var data := GameBalance.skill_by_id(skill_id)
	if data.is_empty():
		return {"ok": false, "reason": "未知技能"}
	var atk := GameState.stat_value("atk")
	var mult: float = data.get("mult", 1.0)
	var range_px: float = data.get("range", 150.0)
	var kind: String = data.get("kind", "aoe")
	var hit := 0
	if kind == "single":
		# 单体：锁定范围内最近敌人
		var target := _nearest_enemy(range_px)
		if target != null:
			hit += _skill_hit(target, atk, mult)
	else:
		# 范围：命中范围内所有敌人
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(enemy) and enemy is Node2D:
				if (enemy as Node2D).global_position.distance_to(global_position) <= range_px:
					hit += _skill_hit(enemy as Node2D, atk, mult)
	if hit > 0:
		EventBus.message.emit("%s 命中 %d 个敌人！" % [data.get("name", ""), hit])
		AudioManager.play("hit")
	else:
		EventBus.message.emit("%s 未命中任何敌人" % data.get("name", ""))
	return {"ok": true, "hits": hit}


func _nearest_enemy(range_px: float) -> Node2D:
	var best: Node2D = null
	var best_d := range_px
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var d := (enemy as Node2D).global_position.distance_to(global_position)
		if d <= best_d:
			best_d = d
			best = enemy
	return best


## 对单个敌人结算技能伤害（走伤害管线 + 飘字），返回命中数
func _skill_hit(enemy: Node2D, atk: float, mult: float) -> int:
	if enemy == null or not enemy.has_method("take_damage"):
		return 0
	var target_def: float = enemy.get("defense")
	var result := DamagePipeline.physical(atk, mult, 0.0, target_def)
	enemy.call("take_damage", result.damage, false)
	EventBus.damage_popup.emit(enemy.global_position, result.damage, "normal")
	return 1


func _draw() -> void:
	# 占位视觉：身体圆 + 朝向线
	var color: Color = CLASS_COLORS.get(str(GameState.run_info.get("character", "warrior")), CLASS_COLORS["warrior"])
	draw_circle(Vector2.ZERO, 16.0, color)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, color.lightened(0.35), 2.0)
	draw_line(Vector2.ZERO, _facing * 30.0, Color(0.95, 0.95, 0.9), 3.0)
