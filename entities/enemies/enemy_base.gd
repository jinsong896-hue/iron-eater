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
	WINDUP,   # 攻击前摇（可被受击打断）
	ATTACK,
	RECOVER,
	STAGGERED,  # 受击硬直（AI 暂停，velocity 走击退摩擦）
	DASH,   # 突进冲刺中
	DEAD,
}

## 死亡信号（RoomController 计数、LootSystem 掉落都监听它）
signal died(world_position: Vector3)

@export var loot_table: String = ""  ## 掉落表 ID（空 = 默认白装池）
@export var is_elite := false        ## 精英标记：掉落概率走 ELITE_DROP_CHANCE
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

# —— 怪物机制（分册第 4/5 章；本轮实现「自爆/分裂/召唤」三种）——
var death_explode := false    ## 死亡自爆（带前摇，期间被打死则提前引爆）
var explode_damage := 40.0    ## 自爆伤害
var explode_radius := 3.0     ## 自爆范围（米）
var death_split := false      ## 死亡分裂为小型同类
var split_count := 2          ## 分裂数量
var summon_spec: Dictionary = {}   ## 召唤配置 {id,count,chance}
var affixes: Array = []       ## 词缀 id 列表（数值型已作用到属性，其余待后续系统）
var _explode_timer := 0.0     ## 自爆前摇倒计时（>0 表示正在蓄爆）
var _exploding := false
var _dash_timer := 0.0        ## 突进持续时间
var _dash_dir := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var _current_state := EnemyState.IDLE
var _hp: float
var _attack_timer := 0.0
var _player  # Player（动态类型：避免 --script 测试模式下 class_name 编译依赖）
var _visual_color := Color(0.8, 0.2, 0.2)
var _model: MeshInstance3D = null          # 模型引用（受击闪红/血条用）
var _flash_timer := 0.0                    # 受击闪红剩余时间

# 头顶血条（受伤后显示）
var _hp_bar: Node3D = null
var _hp_bar_fill: MeshInstance3D = null
var _hp_bar_bg: MeshInstance3D = null

## 受击闪红时长（秒）
const HIT_FLASH_DURATION := 0.18
## 血条尺寸（米）与挂高（乘体型缩放）
const BAR_WIDTH := 1.1
const BAR_HEIGHT := 0.14

# 前摇与硬直
var _windup_timer := 0.0        # 前摇剩余
var _stagger_timer := 0.0       # 硬直剩余
var _knockback_velocity := Vector3.ZERO  # 硬直期间击退速度（摩擦衰减）


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
	# 金币按血量档位（血厚值钱：飞行/闪避怪低、高血怪高）
	var hp := float(m.get("hp", 100))
	gold_min = int(maxi(3, hp / 25.0))
	gold_max = gold_min + 8
	if bool(m.get("is_boss", false)):
		gold_min = 50
		gold_max = 120

	var special: Dictionary = m.get("special", {})
	death_poison = special.get("death_poison", false)
	kite_range = special.get("kite_range", 5.0)
	dash_range = special.get("dash_range", 0.0)
	# 死亡自爆（矿道自爆者）：范围伤害 + 前摇（前摇期间被打死则提前引爆）
	death_explode = special.get("death_explode", false)
	explode_damage = float(special.get("explode_damage", 40.0))
	explode_radius = float(special.get("explode_radius", 3.0))
	# 死亡分裂（水孢行者 / 混沌幼蛛）：分裂成 N 只小型同类
	death_split = special.get("death_split", false)
	split_count = int(special.get("split_count", 2))
	# 召唤小怪（僵尸各阶段）
	summon_spec = special.get("summon", {})
	# 词缀（分册第 7 章）：非数值型词缀已登记在 affixes，此处只记录供后续系统消费
	affixes = m.get("affixes", [])

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
	_model = model
	_visual_color = mat.albedo_color  # 记录本色，闪红后还原用
	_create_health_bar()


## 敌人头顶血条（billboard 四边形，纯脚本图元，无贴图依赖）
## 受伤后才显示；满血时隐藏，避免满屏血条
func _create_health_bar() -> void:
	_hp_bar = Node3D.new()
	_hp_bar.name = "HealthBar"
	_hp_bar.position = Vector3(0, 2.15 * body_scale, 0)

	# 底：深色背景 + 细黑边
	_hp_bar_bg = _make_bar_quad(Vector3(BAR_WIDTH, BAR_HEIGHT, 0), Color(0.05, 0.05, 0.07, 0.9))
	# 填充：红色（受击反馈里也用这个色系）
	_hp_bar_fill = _make_bar_quad(Vector3(BAR_WIDTH, BAR_HEIGHT, 0), Color(0.85, 0.2, 0.2, 1.0))
	# 填充略微前移，避免与底 z-fighting
	_hp_bar_fill.position.z = 0.01

	_hp_bar.add_child(_hp_bar_bg)
	_hp_bar.add_child(_hp_bar_fill)
	add_child(_hp_bar)
	_hp_bar.visible = false
	_update_health_bar()


## 生成一个 billboard 四边形（始终面向相机）
func _make_bar_quad(quad_size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(quad_size.x, quad_size.y)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true  # 不被墙体遮挡
	mi.material_override = mat
	return mi


## 按当前血量刷新血条长度（从左向右收缩）与可见性
func _update_health_bar() -> void:
	if _hp_bar == null or _hp_bar_fill == null:
		return
	var maxv: float = maxf(max_hp, 0.001)
	var ratio := clampf(_hp / maxv, 0.0, 1.0)
	_hp_bar.visible = _hp < max_hp - 0.001 and _hp > 0.0
	_hp_bar_fill.scale.x = maxf(ratio, 0.001)
	# 左对齐：中心左移半个被"吃掉"的长度
	_hp_bar_fill.position.x = -BAR_WIDTH * (1.0 - ratio) * 0.5


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	# 受击闪红衰减（每帧都要走，包括硬直/死亡前）
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_update_flash()

	# 突进推进
	if _current_state == EnemyState.DASH:
		_update_dash(delta)
		return

	# 自爆前摇倒计时（蓄爆完成后引爆）
	if _exploding:
		_explode_timer -= delta
		if _explode_timer <= 0.0:
			_do_explode()
			if is_instance_valid(self):
				die()
			return
		return

	# 受击硬直：AI 暂停，走击退摩擦位移
	if _current_state == EnemyState.STAGGERED:
		_update_stagger(delta)
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
		EnemyState.WINDUP:
			_state_windup(delta)
		EnemyState.ATTACK:
			_state_attack()
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

	# 自爆怪：进入前摇不普攻，蓄爆后自爆（分册 5.1，1.5 秒可被打断）
	if death_explode:
		_attack_timer = attack_interval
		_start_explode_windup()
		return

	# 进入攻击前摇（高伤害怪前摇更长，可被打断）
	_attack_timer = attack_interval
	_windup_timer = _windup_duration()
	_current_state = EnemyState.WINDUP
	_set_windup_visual(true)


## 前摇时长：普通 0.5s；高伤害（≥35 攻）加长到 1.0s（分册约束）
func _windup_duration() -> float:
	if atk >= 35.0:
		return 1.0
	return 0.5


## 前摇推进：结束才结算伤害；目标脱离范围则取消
func _state_windup(delta: float) -> void:
	if _player == null:
		_cancel_windup()
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > attack_range * 1.4:
		_cancel_windup()
		return
	_windup_timer -= delta
	if _windup_timer <= 0.0:
		_set_windup_visual(false)
		_current_state = EnemyState.ATTACK
		_perform_attack()
		_current_state = EnemyState.CHASE


## 取消前摇（目标脱离/被打断）
func _cancel_windup() -> void:
	_set_windup_visual(false)
	_current_state = EnemyState.CHASE


## 前摇视觉：模型发白光预警
func _set_windup_visual(active: bool) -> void:
	var model := get_node_or_null("Model") as MeshInstance3D
	if model == null:
		return
	var mat := model.material_override as StandardMaterial3D
	if mat == null:
		return
	if active:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.95, 0.5)
		mat.emission_energy_multiplier = 0.8
	elif not death_poison:
		mat.emission_enabled = false
	else:
		mat.emission = Color(0.2, 0.8, 0.2)
		mat.emission_energy_multiplier = 0.4


## 受击硬直推进：AI 暂停，击退速度摩擦衰减
func _update_stagger(delta: float) -> void:
	_stagger_timer -= delta
	velocity = _knockback_velocity
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 12.0 * delta)
	move_and_slide()
	if _stagger_timer <= 0.0:
		_knockback_velocity = Vector3.ZERO
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


func take_damage(amount: float, _is_crit: bool = false, knockback: Vector3 = Vector3.ZERO) -> void:
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
		return

	# 受击硬直：打断前摇/攻击，进入 STAGGERED（击退为向量速度）
	_knockback_velocity = knockback
	_stagger_timer = 0.3
	if _current_state == EnemyState.WINDUP:
		_set_windup_visual(false)
		_attack_timer = maxf(_attack_timer, 0.4)  # 打断后惩罚：短冷却
	# 自爆前摇可被打断：受击即提前引爆（分册 5.1「可被攻击提前引爆」）
	if _exploding and _explode_timer > 0.0:
		_do_explode()
		return
	_current_state = EnemyState.STAGGERED
	_flash_hit()
	_update_health_bar()


## 当前血量比例（0~1）；HUD 的 Boss 血条栏靠它刷新，无需触碰私有字段
func hp_ratio() -> float:
	return clampf(_hp / maxf(max_hp, 0.001), 0.0, 1.0)


## 是否存活
func is_alive() -> bool:
	return _hp > 0.0 and _current_state != EnemyState.DEAD


## 受击闪红：模型短暂染红再还原（给出明确的打击反馈）
func _flash_hit() -> void:
	if _model == null:
		return
	_flash_timer = HIT_FLASH_DURATION
	_update_flash()


## 按剩余时间推进闪红（前段全红，后段渐隐）
func _update_flash() -> void:
	if _model == null or _model.material_override == null:
		return
	var mat := _model.material_override as StandardMaterial3D
	if mat == null:
		return
	if _flash_timer <= 0.0:
		mat.albedo_color = _visual_color
		return
	# 前 40% 全红，剩余时间线性退回本色
	var t := _flash_timer / HIT_FLASH_DURATION
	var blend := clampf(t / 0.4, 0.0, 1.0)
	mat.albedo_color = Color(1.0, 0.15, 0.15).lerp(_visual_color, 1.0 - blend)


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

	# 死亡自爆（矿道自爆者 / 熔炉小鬼）
	if death_explode:
		_do_explode()

	# 死亡分裂（水孢行者 / 混沌幼蛛）
	if death_split:
		_spawn_splits()

	# 召唤小怪（僵尸各阶段）：死亡时按概率召唤
	if not summon_spec.is_empty():
		_try_summon()

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


# ============================================================
# 怪物机制（分册第 4/5 章，本轮实现自爆/分裂/召唤三种）
# ============================================================

## 死亡自爆：对范围内玩家结算伤害 + 视觉爆发
func _do_explode() -> void:
	if _explode_timer < 0.0:
		return
	_explode_timer = -1.0   # 标记已引爆，避免重复
	_exploding = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if not (p is Node3D):
			continue
		if (p as Node3D).global_position.distance_to(global_position) <= explode_radius:
			if p.has_method("take_damage"):
				p.call("take_damage", explode_damage)
	# 视觉：橙色扩张球
	var vis := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = explode_radius * 0.5
	sphere.height = explode_radius
	vis.mesh = sphere
	vis.position = Vector3(0, 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vis.material_override = mat
	add_child(vis)


## 进入自爆前摇（分册：前摇 1.5 秒，期间被打死或受击则提前引爆）
func _start_explode_windup() -> void:
	_exploding = true
	_explode_timer = 1.5


## 死亡分裂：生成 N 只小型同类（血量/攻击减半）
func _spawn_splits() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for _i in split_count:
		var child := EnemyBase.new()
		# 沿圆周散开，避免叠在同一点
		var ang := TAU * float(_i) / float(maxi(split_count, 1))
		child.position = position + Vector3(cos(ang), 0.0, sin(ang)) * 1.2
		var cfg := {
			"id": monster_id,
			"name": monster_name,
			"hp": maxf(max_hp * 0.5, 1.0),
			"atk": atk * 0.5,
			"defense": defense,
			"speed_pct": 60.0,
			"attack_interval": attack_interval,
			"attack_range": attack_range,
			"dodge_pct": dodge_pct,
			"scale": body_scale * 0.6,
			"special": {},          # 子体不再分裂，避免无限增殖
			"ai": "melee" if behavior == AIBehavior.MELEE_CHASE else "kite",
		}
		child.apply_monster_config(cfg)
		child.is_elite = false
		parent.add_child(child)


## 召唤小怪（僵尸各阶段：按概率召唤 1~N 只）
func _try_summon() -> void:
	if summon_spec.is_empty():
		return
	var chance := float(summon_spec.get("chance", 1.0))
	if randf() > chance:
		return
	var parent := get_parent()
	if parent == null:
		return
	var count := int(summon_spec.get("count", 1))
	for _i in count:
		var m := MonsterDB.get_monster(str(summon_spec.get("id", "")))
		if m.is_empty():
			continue
		var minion := EnemyBase.new()
		var ang := randf() * TAU
		minion.position = position + Vector3(cos(ang), 0.0, sin(ang)) * 1.5
		minion.apply_monster_config(m)
		minion.is_elite = false
		parent.add_child(minion)
		# 先挂到房间树再登记，保证控制器能找到
		_register_summon(minion)


## 找到房间控制器登记召唤物（保持 enemies_alive 正确）
func _register_summon(minion: Node) -> void:
	var room := get_parent()
	while room != null and not room.has_method("register_summoned_enemy"):
		room = room.get_parent()
	if room != null:
		room.call("register_summoned_enemy", minion)


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
