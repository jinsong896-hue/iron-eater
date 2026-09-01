class_name RoomController
extends Node3D
## 房间控制器 —— HD-2D 重构版
## 管理房间生命周期：激活 → 战斗 → 清空 → 离开
## 以撒式房间锁门机制：进房锁门 → 刷怪 → 全灭开门
## Boss 房：击杀 Boss 后生成下一层传送门

var room_data = null   # RoomData（JSON Dictionary）

# 房间状态
var is_cleared := false
var is_active := false
var enemies_alive := 0
var is_boss_room := false
var _spawn_points: Array[Marker3D] = []
var _boss_spawn: Marker3D = null
var _doors: Array[Node3D] = []
var _living_enemies: Array[EnemyBase] = []
var _boss: EnemyBase = null
var _portal: Area3D = null


func _ready() -> void:
	_collect_nodes()


## 收集生成点（房间根下的 SpawnPoints 容器）与门节点（Doors 容器）
func _collect_nodes() -> void:
	var room_root := get_parent()
	if room_root == null:
		return

	var spawns_node := room_root.get_node_or_null("SpawnPoints")
	if spawns_node:
		for child in spawns_node.get_children():
			if child is Marker3D:
				var m := child as Marker3D
				if m.is_in_group("boss_spawn"):
					_boss_spawn = m
				else:
					_spawn_points.append(m)

	# 门在房间根下的 Doors 容器内（Door_* 命名）
	var doors_node := room_root.get_node_or_null("Doors")
	if doors_node:
		for child in doors_node.get_children():
			if child.name.begins_with("Door_"):
				_doors.append(child)

	is_boss_room = _boss_spawn != null or _room_type() == "boss"


## 激活房间（玩家进入）
func activate() -> void:
	if is_active:
		return

	is_active = true
	var bus = _event_bus()
	if bus:
		bus.room_entered.emit(_room_id())

	if is_cleared:
		_open_doors()
		if is_boss_room:
			_show_portal()
		return

	if is_boss_room:
		_spawn_boss()
	else:
		_spawn_enemies()

	if enemies_alive == 0:
		_on_cleared()
		return

	_lock_doors()


## 敌人死亡回调
func on_enemy_died(_world_position: Vector3) -> void:
	enemies_alive = maxf(enemies_alive - 1, 0)
	if enemies_alive <= 0:
		_on_cleared()


## 房间清空
func _on_cleared() -> void:
	if is_cleared:
		return
	is_cleared = true
	_open_doors()
	if is_boss_room and _boss != null:
		var gm = _game_manager()
		if gm:
			gm.boss_kills += 1
		_show_portal()
	var bus = _event_bus()
	if bus:
		bus.room_cleared.emit(_room_id())


## 离开房间
func deactivate() -> void:
	is_active = false
	var bus = _event_bus()
	if bus:
		bus.room_exited.emit(_room_id())


## 生成敌人（70% 概率/点；怪物从 MonsterDB 第一层池按房间类型选）
func _spawn_enemies() -> void:
	if _spawn_points.is_empty():
		return

	var difficulty_mult := _difficulty_mult()
	var gm = _game_manager()
	var rng := RandomNumberGenerator.new()
	if gm and gm.rng:
		rng.seed = gm.rng.randi()
	MonsterDB.init_layer1()

	for point in _spawn_points:
		if randf() < 0.7:
			var m: Dictionary
			# 生成点带 monster_id meta 时用指定怪，否则按房间类型加权随机
			var custom_id := str(point.get_meta("monster_id", ""))
			if not custom_id.is_empty():
				m = MonsterDB.get_monster(custom_id)
			elif _room_type() == "elite":
				m = MonsterDB.random_elite(rng)
			else:
				m = MonsterDB.random_monster(rng)
			var enemy := _spawn_enemy_at(point, difficulty_mult, m)
			if enemy:
				enemies_alive += 1
				_living_enemies.append(enemy)


## 在生成点创建敌人（应用 MonsterDB 配置 + 难度缩放）
func _spawn_enemy_at(point: Marker3D, difficulty_mult: float, m: Dictionary = {}) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position
	if not m.is_empty():
		enemy.apply_monster_config(m)
		# 难度缩放（在怪物基准数值之上）
		enemy.max_hp *= difficulty_mult
		enemy.atk *= difficulty_mult
	else:
		enemy.max_hp = 100.0 * difficulty_mult
		enemy.atk = 10.0 * difficulty_mult
		enemy.move_speed = 2.0
	enemy.died.connect(on_enemy_died)
	add_child(enemy)
	return enemy


## 生成 Boss（鼠王·巨型变异老鼠精英版，难度缩放 + 必掉装备）
func _spawn_boss() -> void:
	if _boss_spawn == null:
		return
	var mult := _difficulty_mult()
	MonsterDB.init_layer1()
	_boss = EnemyBase.new()
	_boss.position = _boss_spawn.global_position
	_boss.apply_monster_config(MonsterDB.boss_monster())
	_boss.max_hp *= mult
	_boss.atk *= mult
	_boss.attack_range = 2.6
	_boss.gold_min = 50
	_boss.gold_max = 120
	# Boss 必掉装备：掉落表指向随机白装由 LootSystem 处理，这里用必掉标记
	_boss.set_meta("boss_loot", true)
	_boss.died.connect(_on_boss_died)
	add_child(_boss)
	enemies_alive += 1
	_living_enemies.append(_boss)


## Boss 死亡：必掉两件装备 + 房间清空
func _on_boss_died(world_position: Vector3) -> void:
	enemies_alive = maxf(enemies_alive - 1, 0)
	if enemies_alive <= 0:
		_on_cleared()


## 难度倍率
func _difficulty_mult() -> float:
	var gm = _game_manager()
	if gm == null:
		return 1.0
	match str(gm.run_info.get("difficulty", "normal")):
		"easy":
			return 0.8
		"hard":
			return 1.35
	return 1.0


## 生成下一层传送门（Boss 房清空后出现，触碰进入下一层）
func _show_portal() -> void:
	if _portal != null and is_instance_valid(_portal):
		_portal.visible = true
		return

	var room_root := get_parent()
	if room_root == null:
		return

	# 传送门放在 Boss 出生点
	var pos: Vector3 = _boss_spawn.global_position if _boss_spawn else Vector3.ZERO
	_portal = Area3D.new()
	_portal.name = "NextFloorPortal"
	_portal.position = pos + Vector3(0, 1.0, 0)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 2.0
	col.shape = shape
	_portal.add_child(col)

	# 视觉：发光圆柱
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 2.0
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	_portal.add_child(mesh)

	_portal.body_entered.connect(_on_portal_entered)
	room_root.add_child(_portal)

	var bus = _event_bus()
	if bus:
		bus.message.emit("Boss 已击败！进入传送门前往下一层")


## 触碰传送门 → 进入下一层
func _on_portal_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var gm = _game_manager()
	if gm:
		gm.run_info["floor"] = int(gm.run_info.get("floor", 1)) + 1
		# 层间全恢复（满状态进新层）
		if GameBalance.FLOOR_TRANSITION_FULL_HEAL and gm.attributes:
			gm.attributes.hp = gm.attributes.max_hp
		if int(gm.run_info["floor"]) > 9:
			gm.finish_run("cleared")
			return
		var bus0 = _event_bus()
		if bus0:
			bus0.stats_changed.emit()
	# 通知 GameRoot 重建地牢（下一层）
	var room_root := get_parent()
	var game_root := room_root.get_parent() if room_root else null
	if game_root and game_root.has_method("next_floor"):
		game_root.call("next_floor")


## 房间类型（兼容 Dictionary 与 RoomData）
func _room_type() -> String:
	if room_data == null:
		return ""
	if room_data is Dictionary:
		return str(room_data.get("room_type", room_data.get("type", "")))
	return str(room_data.room_type)


## 锁定所有门（设置阻挡体）
func _lock_doors() -> void:
	for door in _doors:
		_look_for_trigger(door, "lock")
	var bus = _event_bus()
	if bus:
		bus.door_locked.emit("")


## 打开所有门
func _open_doors() -> void:
	for door in _doors:
		_look_for_trigger(door, "unlock")


## 在门节点中查找触发器并调用方法
func _look_for_trigger(door: Node, method_name: String) -> void:
	if door.has_method(method_name):
		door.call(method_name)
		return
	for child in door.get_children():
		if child.has_method(method_name):
			child.call(method_name)
			return


## 房间 ID（兼容 Dictionary 与 RoomData 两种来源）
func _room_id() -> String:
	if room_data == null:
		return ""
	if room_data is Dictionary:
		return str(room_data.get("room_id", room_data.get("id", "")))
	return str(room_data.room_id)


## 获取 GameManager autoload（--script 测试模式下不存在，返回 null）
func _game_manager():
	return get_node_or_null("/root/GameManager")


## 获取 EventBus autoload（--script 测试模式下不存在，返回 null）
func _event_bus():
	return get_node_or_null("/root/EventBus")
