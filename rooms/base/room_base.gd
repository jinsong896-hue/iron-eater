class_name RoomBase
extends Node2D
## 统一房间基类：《房间生成.md》
## 职责：玩家进入检测 → 锁门 → 刷怪 → 清怪 → 开门完成；门锁定/解锁；出口请求

signal room_entered(room: RoomBase)
signal encounter_started(room: RoomBase)
signal room_cleared(room: RoomBase)
signal exit_requested(room: RoomBase, door: RoomDoor)

enum RoomType { START, NORMAL, ELITE, SPECIAL, BOSS }

const TILE_SOURCE_ID := 0
const WORLD_TILE := 64

@export var room_id := "ROOM_000"
@export var room_type: RoomType = RoomType.NORMAL
@export var starts_cleared := false
@export var lock_doors_during_combat := true

var ground: TileMapLayer
var grass: TileMapLayer
var walls: TileMapLayer
var enemy_container: Node2D
var spawn_points: Node2D
var doors_root: Node2D
var player_detector: Area2D
var player_spawn: Marker2D

var has_player_entered := false
var encounter_active := false
var cleared := false
var active_enemy_ids := {}


func _ready() -> void:
	_ensure_structure()
	_connect_player_detector()
	_connect_doors()
	if starts_cleared or room_type == RoomType.START:
		cleared = true
		_set_all_doors_locked(false)
	else:
		cleared = false
		_set_all_doors_locked(false)


## 自动补齐场景结构（支持代码构建与 .tscn 两种方式）
func _ensure_structure() -> void:
	var ts := TilesetFactory.get_tileset()
	for layer_name in ["Ground", "Grass", "Walls"]:
		var layer := get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			layer = TileMapLayer.new()
			layer.name = layer_name
			add_child(layer)
		layer.tile_set = ts
		layer.scale = Vector2.ONE * 4.0
		match layer_name:
			"Ground": ground = layer
			"Grass": grass = layer
			"Walls": walls = layer
	for node_name in ["Decorations", "EnemyContainer", "SpawnPoints", "Doors"]:
		var node := get_node_or_null(node_name) as Node2D
		if node == null:
			node = Node2D.new()
			node.name = node_name
			add_child(node)
		match node_name:
			"EnemyContainer": enemy_container = node
			"SpawnPoints": spawn_points = node
			"Doors": doors_root = node
	if player_detector == null:
		player_detector = get_node_or_null("PlayerDetector") as Area2D
	if player_detector == null:
		player_detector = Area2D.new()
		player_detector.name = "PlayerDetector"
		player_detector.collision_layer = 0
		player_detector.collision_mask = 1
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(2000, 1200)
		shape.shape = box
		player_detector.add_child(shape)
		add_child(player_detector)
	if player_spawn == null:
		player_spawn = get_node_or_null("PlayerSpawn") as Marker2D
	if player_spawn == null:
		player_spawn = Marker2D.new()
		player_spawn.name = "PlayerSpawn"
		add_child(player_spawn)


func _connect_player_detector() -> void:
	if player_detector == null:
		return
	if not player_detector.body_entered.is_connected(_on_player_detector_body_entered):
		player_detector.body_entered.connect(_on_player_detector_body_entered)


func _on_player_detector_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if has_player_entered:
		return
	has_player_entered = true
	room_entered.emit(self)
	if cleared:
		return
	start_encounter()


func start_encounter() -> void:
	if encounter_active or cleared:
		return
	encounter_active = true
	if lock_doors_during_combat:
		_set_all_doors_locked(true)
	encounter_started.emit(self)
	_spawn_room_enemies()
	_register_existing_enemies()
	if active_enemy_ids.is_empty():
		call_deferred("finish_room")


## 子类覆盖：刷怪
func _spawn_room_enemies() -> void:
	pass


func register_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	var enemy_id := enemy.get_instance_id()
	if active_enemy_ids.has(enemy_id):
		return
	active_enemy_ids[enemy_id] = true
	if not enemy.tree_exited.is_connected(_on_enemy_tree_exited.bind(enemy_id)):
		enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy_id), CONNECT_ONE_SHOT)


func _register_existing_enemies() -> void:
	if enemy_container == null:
		return
	for enemy in enemy_container.get_children():
		register_enemy(enemy)


func _on_enemy_tree_exited(enemy_id: int) -> void:
	active_enemy_ids.erase(enemy_id)
	if encounter_active and active_enemy_ids.is_empty():
		call_deferred("finish_room")


func finish_room() -> void:
	if cleared:
		return
	cleared = true
	encounter_active = false
	_set_all_doors_locked(false)
	room_cleared.emit(self)
	_on_room_cleared()


func _on_room_cleared() -> void:
	pass


func _connect_doors() -> void:
	if doors_root == null:
		return
	for node in doors_root.get_children():
		if node is RoomDoor:
			var door := node as RoomDoor
			if not door.used.is_connected(_on_door_used):
				door.used.connect(_on_door_used)


func _set_all_doors_locked(value: bool) -> void:
	if doors_root == null:
		return
	var changed := false
	for node in doors_root.get_children():
		if node is RoomDoor:
			var door := node as RoomDoor
			if door.locked != value:
				door.set_locked(value)
				changed = true
	if changed:
		_play_door_sound(value)


func _play_door_sound(locked: bool) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play"):
		audio.call("play", "door_close" if locked else "door_open")


func _on_door_used(door: RoomDoor) -> void:
	if not cleared:
		return
	exit_requested.emit(self, door)


func get_player_spawn_position() -> Vector2:
	if player_spawn:
		return player_spawn.global_position
	return global_position


func set_cell(layer: TileMapLayer, cell: Vector2i, atlas_coords: Vector2i) -> void:
	layer.set_cell(cell, TILE_SOURCE_ID, atlas_coords)


func erase_cell(layer: TileMapLayer, cell: Vector2i) -> void:
	layer.erase_cell(cell)
