class_name RoomController
extends Node3D
## 房间控制器 —— HD-2D 重构版
## 管理房间生命周期：激活 → 战斗 → 清空 → 离开
## 以撒式房间锁门机制：进房锁门 → 刷怪 → 全灭开门

var room_data = null   # RoomData（JSON Dictionary）

# 房间状态
var is_cleared := false
var is_active := false
var enemies_alive := 0
var _spawn_points: Array[Marker3D] = []
var _doors: Array[Node3D] = []
var _living_enemies: Array[EnemyBase] = []


func _ready() -> void:
	_collect_nodes()


## 收集生成点（房间根下的 SpawnPoints 容器）与门节点（兄弟节点）
func _collect_nodes() -> void:
	var room_root := get_parent()
	if room_root == null:
		return

	var spawns_node := room_root.get_node_or_null("SpawnPoints")
	if spawns_node:
		for child in spawns_node.get_children():
			if child is Marker3D:
				_spawn_points.append(child as Marker3D)

	# 门是房间根下的直接子节点（Door_* 命名）
	for sibling in room_root.get_children():
		if sibling.name.begins_with("Door_"):
			_doors.append(sibling)


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
		return

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
	var bus = _event_bus()
	if bus:
		bus.room_cleared.emit(_room_id())


## 离开房间
func deactivate() -> void:
	is_active = false
	var bus = _event_bus()
	if bus:
		bus.room_exited.emit(_room_id())


## 生成敌人（70% 概率/点，难度缩放取 GameManager 配置）
func _spawn_enemies() -> void:
	if _spawn_points.is_empty():
		return

	var difficulty_mult := 1.0
	var gm = _game_manager()
	if gm:
		match str(gm.run_info.get("difficulty", "normal")):
			"easy":
				difficulty_mult = 0.8
			"hard":
				difficulty_mult = 1.35

	for point in _spawn_points:
		if randf() < 0.7:
			var enemy := _spawn_enemy_at(point, difficulty_mult)
			if enemy:
				enemies_alive += 1
				_living_enemies.append(enemy)


## 在生成点创建敌人
func _spawn_enemy_at(point: Marker3D, difficulty_mult: float) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position
	enemy.max_hp = 100.0 * difficulty_mult
	enemy.atk = 10.0 * difficulty_mult
	enemy.move_speed = 2.0
	enemy.died.connect(on_enemy_died)
	add_child(enemy)
	return enemy


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
