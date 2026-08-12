class_name DungeonManager
extends Node
## 层管理器：当前层配置、重新生成、下一层（对应《关卡设计分册》1.2）

const LAYER_CONFIGS := [
	preload("res://data/dungeon/layers/layer01.tres"),
	preload("res://data/dungeon/layers/layer02.tres"),
	preload("res://data/dungeon/layers/layer03.tres"),
	preload("res://data/dungeon/layers/layer04.tres"),
	preload("res://data/dungeon/layers/layer05.tres"),
	preload("res://data/dungeon/layers/layer06.tres"),
	preload("res://data/dungeon/layers/layer07.tres"),
	preload("res://data/dungeon/layers/layer08.tres"),
	preload("res://data/dungeon/layers/layer09.tres"),
]

var current_layer := 1
var generator: DungeonGenerator


func _ready() -> void:
	add_to_group("dungeon_manager")
	generator = $DungeonGenerator
	regenerate()


func regenerate() -> void:
	var cfg: ChapterConfig = LAYER_CONFIGS[current_layer - 1]
	generator.generate(cfg, -1, true)
	_place_player()
	EventBus.layer_changed.emit(current_layer, cfg.chapter_name)


func next_layer() -> void:
	current_layer = mini(current_layer + 1, LAYER_CONFIGS.size())
	regenerate()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dungeon_regenerate"):
		regenerate()
	elif event.is_action_pressed("dungeon_next_layer"):
		next_layer()


func _place_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	player.global_position = generator.start_usable_rect().get_center()
	var camera := player.get_node_or_null("Camera2D") as RoomCamera
	if camera:
		camera.switch_to_room(generator.start_usable_rect())
