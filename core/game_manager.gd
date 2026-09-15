extends Node
## 游戏状态管理器 —— HD-2D 重构版
## 管理游戏全局状态机：MENU → TOWN → DUNGEON → BOSS → DEAD
## 同时管理角色属性、装备、金币等局内状态
## 注意：使用 untyped 变量避免编译期循环依赖

enum GamePhase {
	MENU,       # 主菜单
	TOWN,       # 城镇（未实现，预留）
	DUNGEON,    # 地下城探索中
	BOSS,       # Boss 战
	DEAD,       # 死亡结算
}

var current_state: GamePhase = GamePhase.MENU
var previous_state: GamePhase = GamePhase.MENU

# 局内运行时数据（untyped 避免编译期依赖）
var attributes   # AttributeSystem
var equipment_manager   # EquipmentManager
var consumable_inventory   # ConsumableInventory
var rng := RandomNumberGenerator.new()
var gold := 0
var kills := 0
var total_damage := 0.0
var devoured_count := 0
var fusion_count := 0
var elite_kills := 0
var boss_kills := 0

## 本局钥匙碎片数（集齐 8 片解锁隐藏第 9 层，策划书 1.3）。
## 掉落由 LootSystem 在 Boss 死亡时按层概率产出（见 FloorDefs.boss_fragment_chance）。
var run_key_fragments := 0

## 局外累积的钥匙碎片（跨局保留，写入存档 meta）。
## 策划书 6.「钥匙碎片：局内数据持有，集齐 8 片触发隐藏层入口；结算时写入局外记录」。
var meta_key_fragments := 0

# 本局配置
var run_info := {
	"character": "warrior",
	"mode": "dungeon",
	"difficulty": "normal",
	"floor": 1,
	"seed": 0,
}

var _run_start_ms := 0


func _ready() -> void:
	rng.set_seed(int(run_info.get("seed", 0)))
	_run_start_ms = Time.get_ticks_msec()


## 切换游戏状态
func set_state(new_state: GamePhase) -> void:
	previous_state = current_state
	current_state = new_state
	match new_state:
		GamePhase.MENU:
			_on_enter_menu()
		GamePhase.DUNGEON:
			_on_enter_dungeon()
		GamePhase.BOSS:
			_on_enter_boss()
		GamePhase.DEAD:
			_on_enter_dead()


## 开始新的一局
func start_new_run(info: Dictionary) -> void:
	run_info = info.duplicate()
	rng.set_seed(int(run_info.get("seed", 0)))
	_reset_run()
	EventBus.game_started.emit()
	set_state(GamePhase.DUNGEON)


## 重置局内状态
func _reset_run() -> void:
	EquipmentDB.init_equipment_db()
	attributes = load("res://data/attributes/attribute_system.gd").new()
	equipment_manager = load("res://gameplay/inventory/equipment_manager.gd").new()
	equipment_manager.rng = rng
	consumable_inventory = load("res://data/consumables/consumable_inventory.gd").new()
	gold = 0
	kills = 0
	total_damage = 0.0
	devoured_count = 0
	fusion_count = 0
	elite_kills = 0
	boss_kills = 0
	run_key_fragments = 0
	_run_start_ms = Time.get_ticks_msec()


## 获得一片钥匙碎片（Boss 掉落调用）。
## 局内计数；同时累积到局外（跨局保留，死亡不掉——策划书未规定丢失规则，
## 保守起见按「累积保留」实现，待策划明确后再调整）。
## 返回当前本局碎片总数。
func add_key_fragment(from_floor: int = 0) -> int:
	run_key_fragments += 1
	meta_key_fragments += 1
	EventBus.key_fragment_gained.emit(run_key_fragments, from_floor)
	return run_key_fragments


## 本局是否已集齐解锁隐藏层所需的钥匙碎片
func has_all_key_fragments() -> bool:
	return run_key_fragments >= FloorDefs.KEY_FRAGMENTS_REQUIRED


## 局外累积碎片写入/读出（存档用）
func set_meta_key_fragments(count: int) -> void:
	meta_key_fragments = maxi(count, 0)


func get_meta_key_fragments() -> int:
	return meta_key_fragments


## 本局结束
func finish_run(reason: String) -> Dictionary:
	var play_seconds := float(Time.get_ticks_msec() - _run_start_ms) / 1000.0
	var result := {
		"reason": reason,
		"floor": int(run_info.get("floor", 1)),
		"kills": kills,
		"elite_kills": elite_kills,
		"boss_kills": boss_kills,
		"gold": gold,
		"total_damage": total_damage,
		"devoured": devoured_count,
		"fusions": fusion_count,
		"play_seconds": play_seconds,
	}
	EventBus.run_finished.emit(result)
	# 本局结束 → 作废存档的「进行中」标记（策划 5.3：死亡后不可读档）。
	# 不置 false 的话主菜单的「继续游戏」仍然可点，玩家能读档复活，
	# 与「每一战都是决赛、无原地复活」的设计相悖。
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		if sm.has_method("save"):
			sm.call("save", int(sm.get("current_slot")))   # 先落盘最终数据
		if sm.has_method("set_active_run"):
			sm.call("set_active_run", false)
	set_state(GamePhase.DEAD)
	return result


## 便捷访问：获取属性值
func stat_value(stat_name: String) -> float:
	if attributes == null:
		return 0.0
	return attributes.get_value(attributes.STAT_BY_NAME.get(stat_name, 0))


## 融合攻击加成
func fusion_attack_bonus() -> float:
	if equipment_manager == null:
		return 0.0
	return equipment_manager.fusion_attack_bonus()


## 吞噬物品
func devour_item(item) -> Dictionary:  # item: EquipmentInstance
	if equipment_manager == null:
		return {"ok": false, "reason": "装备管理器未初始化"}
	var result: Dictionary = equipment_manager.devour(item)
	if result.get("ok", false):
		devoured_count += 1
		EventBus.stats_changed.emit()
	return result


func _on_enter_menu() -> void:
	pass


func _on_enter_dungeon() -> void:
	# 地下城生成由 GameRoot 场景负责
	pass


func _on_enter_boss() -> void:
	pass


func _on_enter_dead() -> void:
	pass