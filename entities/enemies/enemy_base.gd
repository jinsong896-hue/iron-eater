class_name EnemyBase
extends CharacterBody3D
## 敌人基类 —— HD-2D 重构版
## 3D 敌人通用基类：状态机、AI 追踪/风筝/哨兵/突进、远程弹射、闪避、死亡毒雾
## 数据来源：MonsterDB（怪物设计分册第一层 10 种）

# 基础属性
@export var max_hp: float = 100.0
@export var atk: float = 10.0
@export var defense: float = 5.0
@export var move_speed: float = 2.0
@export var attack_range: float = 2.0
@export var detect_range: float = 12.0
@export var attack_interval: float = 1.0

# AI 行为
enum AIBehavior {
	MELEE_CHASE,   # 近战追击（含缓慢/快速，速度由 move_speed 区分）
	RANGED_KITE,   # 远程风筝（被近身后退）
	SENTRY,        # 固定炮台（不移动，远射程）
	RUSHER,        # 突进（远距冲刺接敌）
	PATROL,
	STATIONARY,    # 旧占位（木桩），等同 SENTRY 但不攻击
}

@export var behavior := AIBehavior.MELEE_CHASE

# 状态
enum EnemyState {
	IDLE,
	DETECT,
	CHASE,
	ATTACK,
	RECOVER,
	DASH,   # 突进冲刺中
	DEAD,
}

## 死亡信号（RoomController 计数、LootSystem 掉落都监听它）
signal died(world_position: Vector3)

@export var loot_table: String = ""  ## 掉落表 ID（空 = 默认白装池）
@export var gold_min := 3
@export var gold_max := 12

# 第一层扩展属性（MonsterDB 应用）
var monster_id := ""          ## 怪物 ID（显示名查询用）
var monster_name := ""        ## 显示名
var dodge_pct := 0.0          ## 闪避率（0~1）
var is_ranged := false        ## 远程怪（攻击走弹射）
var kite_range := 5.0         ## 风筝后退触发距离
var dash_range := 0.0         ## 突进触发距离（0=不突进）
var death_poison := false     ## 死亡释放毒雾
var body_scale := 1.0         ## 体型缩放
var _dash_timer := 0.0        ## 突进持续时间
var _dash_dir := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var _current_state := EnemyState.IDLE
var _hp: float
var _attack_timer := 0.0
var _player  # Player（动态类型：避免 --script 测试模式下 class_name 编译依赖）
var _visual_color := Color(0.8, 0.2, 0.2)


func _ready() -> void:
	add_to_group("enemies")
	_hp = max_hp
	rng.randomize()
	_find_player()
	_create_visual()


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]


## 从 MonsterDB 字典应用配置（刷怪用）
func apply_monster_config(m: Dictionary) -> void:
	if m.is_empty():
		return
	monster_id = str(m.get("id", ""))
	monster_name = str(m.get("name", ""))
	max_hp = float(m.get("hp", 100))
	atk = float(m.get("atk", 10))
	defense = float(m.get("defense", 5))
	# 移速：玩家基准 4.0 m/s × 百分比
	move_speed = 4.0 * float(m.get("speed_pct", 50)) / 100.0
	attack_interval = float(m.get("attack_interval", 3.0))
	dodge_pct = float(m.get("dodge_pct", 0.0))
	body_scale = float(m.get("scale", 1.0))

	var special: Dictionary = m.get("special", {})
	death_poison = special.get("death_poison", false)
	kite_range = special.get("kite_range", 5.0)
	dash_range = special.get("dash_range", 0.0)

	# AI 类型映射
	match str(m.get("ai", "melee")):
		"kite":
			behavior = AIBehavior.RANGED_KITE
			is_ranged = true
			attack_range = float(m.get("attack_range", 8.0))
		"sentry":
			behavior = AIBehavior.SENTRY
			is_ranged = true
			attack_range = float(m.get("attack_range", 15.0))
			detect_range = float(m.get("attack_range", 15.0))
		"rusher":
			behavior = AIBehavior.RUSHER
		"flyer_melee":
			behavior = AIBehavior.MELEE_CHASE  # 飞行近战＝追击（飞行视觉后续做）
		"flyer_ranged":
			behavior = AIBehavior.RANGED_KITE
			is_ranged = true
			attack_range = float(m.get("attack_range", 10.0))
		_:
			behavior = AIBehavior.MELEE_CHASE


## 创建临时视觉模型（按 AI 类型配色，体型缩放）
func _create_visual() -> void:
	var model := MeshInstance3D.new()
	model.name = "Model"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4 * body_scale
	capsule.height = 1.8 * body_scale
	model.mesh = capsule
	model.position = Vector3(0, 0.9 * body_scale, 0)
	var mat := StandardMaterial3D.new()
	match behavior:
		AIBehavior.MELEE_CHASE:
			mat.albedo_color = Color(0.8, 0.2, 0.2)  # 红色近战
		AIBehavior.RANGED_KITE:
			mat.albedo_color = Color(0.2, 0.2, 0.8)  # 蓝色远程
		AIBehavior.SENTRY:
			mat.albedo_color = Color(0.2, 0.6, 0.6)  # 青色哨兵
		AIBehavior.RUSHER:
			mat.albedo_color = Color(0.85, 0.5, 0.1)  # 橙色突进
		_:
			mat.albedo_color = Color(0.5, 0.3, 0.7)  # 紫色特殊
	mat.emission_enabled = death_poison  # 毒怪发光提示
	if death_poison:
		mat.emission = Color(0.2, 0.8, 0.2)
		mat.emission_energy_multiplier = 0.4
	model.material_override = mat
	add_child(model)


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	# 突进推进
	if _current_state == EnemyState.DASH:
		_update_dash(delta)
		return

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
	if _player == null:
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist <= detect_range:
		_current_state = EnemyState.CHASE


func _state_chase(delta: float) -> void:
	if _player == null:
		return
	var dist: float = global_position.distance_to(_player.global_position)

	# 突进触发：距离在 [attack_range, dash_range] 外且冷却好 → 冲刺
	if behavior == AIBehavior.RUSHER and dash_range > 0.0:
		if dist > attack_range + 1.0 and dist < dash_range + 4.0 and _attack_timer <= 0.0:
			_start_dash()
			return

	# 进入攻击范围
	if dist <= attack_range:
		_current_state = EnemyState.ATTACK
		return

	# 超出侦测范围
	if dist > detect_range:
		_current_state = EnemyState.IDLE
		return

	# 风筝：远程怪被近身（< kite_range）→ 后退
	if behavior == AIBehavior.RANGED_KITE and dist < kite_range:
		var away: Vector3 = (global_position - _player.global_position)
		away.y = 0.0
		if away.length_squared() > 0.001:
			velocity = away.normalized() * move_speed
			move_and_slide()
		return

	# 哨兵：不移动
	if behavior == AIBehavior.SENTRY:
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
	if _player == null:
		return
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


## 开始突进冲刺
func _start_dash() -> void:
	if _player == null:
		return
	_dash_dir = (_player.global_position - global_position)
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()
	_current_state = EnemyState.DASH
	_dash_timer = 0.35
	_attack_timer = attack_interval  # 冲完进入攻击冷却


## 突进推进
func _update_dash(delta: float) -> void:
	_dash_timer -= delta
	velocity = _dash_dir * move_speed * 2.2
	move_and_slide()
	if _dash_timer <= 0.0:
		_current_state = EnemyState.CHASE


func _perform_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if is_ranged:
		_fire_projectile()
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


## 远程弹射（直线飞行的能量球）
func _fire_projectile() -> void:
	if _player == null:
		return
	var dir: Vector3 = (_player.global_position - global_position).normalized()
	var proj := Node3D.new()
	proj.position = global_position + Vector3(0, 1.2, 0) + dir * 0.6
	proj.add_to_group("enemy_projectiles")

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.6, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mesh.material_override = mat
	proj.add_child(mesh)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	area.add_child(col)
	proj.add_child(area)

	area.body_entered.connect(_on_projectile_hit.bind(proj, atk))

	var speed := 8.0
	var life := attack_range / speed + 0.5
	get_parent().add_child(proj)

	# 弹射推进（await 逐帧移动）
	_fly_projectile(proj, dir, speed, life)


## 弹射逐帧飞行
func _fly_projectile(proj: Node3D, dir: Vector3, speed: float, life: float) -> void:
	var t := 0.0
	while t < life and is_instance_valid(proj):
		var step := get_physics_process_delta_time()
		proj.position += dir * speed * step
		t += step
		await get_tree().physics_frame
	if is_instance_valid(proj):
		proj.queue_free()


## 弹射命中玩家
func _on_projectile_hit(body: Node3D, proj: Node3D, damage: float) -> void:
	if not body.is_in_group("player"):
		return
	if not is_instance_valid(proj):
		return
	var player_def := 0.0
	var gm = _game_manager()
	if gm:
		player_def = gm.stat_value("def")
	var result = DamagePipeline.physical(damage, 1.0, 0.0, player_def)
	body.call("take_damage", result.damage)
	proj.queue_free()


func take_damage(amount: float, _is_crit: bool = false) -> void:
	# 闪避判定（迷雾幽灵 30%）
	if dodge_pct > 0.0 and rng.randf() < dodge_pct:
		var bus0 = _event_bus()
		if bus0:
			bus0.damage_popup.emit(global_position, 0.0, "dodge")
		return
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

	# 死亡毒雾（毒瘴僵尸）：2 米每秒 10 伤持续 3 秒
	if death_poison:
		_spawn_death_poison()

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


## 死亡毒雾（2 米，每秒 10 伤，持续 3 秒）
func _spawn_death_poison() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var zone := Area3D.new()
	zone.position = global_position
	zone.add_to_group("poison_zones")

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 2.0
	col.shape = shape
	zone.add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.0
	cyl.height = 2.0
	mesh.mesh = cyl
	mesh.position.y = 0.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 0.2, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	zone.add_child(mesh)

	parent.add_child(zone)

	# 每秒 10 伤 × 3 秒
	var ticks := 3
	for i in range(ticks):
		await get_tree().create_timer(1.0).timeout
		if zone == null or not is_instance_valid(zone):
			return
		for body in zone.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				body.call("take_damage", 10.0)
	zone.queue_free()


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	var node := get_node_or_null("/root/GameManager")
	return node


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	var node := get_node_or_null("/root/EventBus")
	return node
