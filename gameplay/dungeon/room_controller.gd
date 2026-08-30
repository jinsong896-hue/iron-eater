class_name RoomController
extends Node3D
## 房间控制器 —— HD-2D 重构版
## 管理房间生命周期：激活 → 战斗 → 清空 → 离开
## 以撒式房间锁门机制

var room_data = null   # RoomData

# 房间状态
var is_cleared := false
var is_active := false
var enemies_alive := 0
var _spawn_points: Array[Marker3D] = []
var _doors: Array[Node3D] = []


func _ready() -> void:
	_collect_nodes()


func _collect_nodes() -> void:
	for child in get_children():
		if child.is_in_group("enemy_spawn"):
			_spawn_points.append(child as Marker3D)
	# 门在 Door 兄弟节点中
	for sibling in get_parent().get_children():
		if sibling.get_node_or_null("DoorTrigger") != null:
			_doors.append(sibling)


## 激活房间（玩家进入）
func activate() -> void:
	if is_active:
		return

	is_active = true
	EventBus.room_entered.emit(room_data.get("room_id", "") if room_data else "")

	if is_cleared:
		_open_doors()
		return

	_spawn_enemies()

	if enemies_alive == 0:
		_on_cleared()
		return

	_lock_doors()


## 敌人死亡回调
func on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		_on_cleared()


## 房间清空
func _on_cleared() -> void:
	is_cleared = true
	_open_doors()
	EventBus.room_cleared.emit(room_data.get("room_id", "") if room_data else "")


## 离开房间
func deactivate() -> void:
	is_active = false
	EventBus.room_exited.emit(room_data.get("room_id", "") if room_data else "")


## 生成敌人
func _spawn_enemies() -> void:
	if _spawn_points.is_empty():
		return

	for point in _spawn_points:
		if randf() < 0.7:
			_spawn_enemy_at(point)
			enemies_alive += 1


## 在生成点创建敌人
func _spawn_enemy_at(point: Marker3D) -> void:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position
	enemy.max_hp = 100.0
	enemy.atk = 10.0
	enemy.move_speed = 2.0
	enemy.tree_exiting.connect(on_enemy_died)
	add_child(enemy)


## 锁定所有门
func _lock_doors() -> void:
	for door in _doors:
		_look_for_trigger(door, "lock")
	EventBus.door_locked.emit("")


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