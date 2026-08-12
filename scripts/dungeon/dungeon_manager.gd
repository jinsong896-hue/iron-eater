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
var _continue_seed := 0
var boss_cleared := false
var boss_cleared_count := 0


func _ready() -> void:
	add_to_group("dungeon_manager")
	generator = $DungeonGenerator
	current_layer = clampi(int(GameState.run_info.get("floor", 1)), 1, LAYER_CONFIGS.size())
	_continue_seed = int(GameState.run_info.get("seed", 0))
	generator.template_room_cleared.connect(_on_template_room_cleared)
	regenerate()


func regenerate(force_random := false) -> void:
	boss_cleared = false
	boss_cleared_count = 0
	EventBus.boss_state_changed.emit(false)
	var cfg: ChapterConfig = LAYER_CONFIGS[current_layer - 1]
	var seed := -1
	if not force_random and _continue_seed != 0:
		seed = _continue_seed
		_continue_seed = 0
	generator.generate(cfg, seed, true)
	_place_player()
	EventBus.layer_changed.emit(current_layer, cfg.chapter_name)


func next_layer() -> void:
	if current_layer >= LAYER_CONFIGS.size():
		return
	if not boss_cleared:
		EventBus.message.emit("需要先击败本层 Boss 才能进入下一层")
		return
	current_layer = mini(current_layer + 1, LAYER_CONFIGS.size())
	GameState.run_info["floor"] = current_layer
	SaveManager.update_run_floor(current_layer)
	regenerate()


func _on_template_room_cleared(room_type: int) -> void:
	if room_type != RoomBase.RoomType.BOSS:
		return
	if current_layer == 9:
		boss_cleared_count += 1
		EventBus.message.emit("混沌守卫被击败（%d/3）" % boss_cleared_count)
		if boss_cleared_count >= 3:
			_on_victory()
		return
	boss_cleared = true
	EventBus.boss_state_changed.emit(true)
	EventBus.message.emit("本层 Boss 已击败！按 N 或点击按钮进入下一层")


func _on_victory() -> void:
	EventBus.message.emit("第 9 层全部 Boss 已被击败——通关！")
	GameState.finish_run("cleared")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dungeon_regenerate"):
		regenerate(true)
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
