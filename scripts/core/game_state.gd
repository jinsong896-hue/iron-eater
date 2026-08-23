extends Node
## 局内状态（原型）：属性、金币、装备管理、掉落
## 装备逻辑统一由 EquipmentManager 承担；角色属性由 AttributeSystem + Modifier 汇总

const AttributeSystemScript := preload("res://scripts/core/attribute_system.gd")
const EquipmentManagerScript := preload("res://scripts/equipment/equipment_manager.gd")
const ItemPickupScene := preload("res://scenes/equipment/item_pickup.tscn")

var attributes: AttributeSystem
var equipment_manager: EquipmentManager
## 战斗/装备层随机数：按 run_info.seed 初始化，保证同一种子可复现本局（地牢生成另用 DungeonGenerator 自己的 rng）
var rng := RandomNumberGenerator.new()
var gold := 0
var kills := 0
var total_damage := 0.0
var devoured_count := 0
var fusion_count := 0
var elite_kills := 0
var boss_kills := 0
var run_info := {"character": "warrior", "mode": "dungeon", "difficulty": "normal", "floor": 1, "seed": 0}
var _run_start_ms := 0


func _ready() -> void:
	reset_run()


func reset_run() -> void:
	attributes = AttributeSystemScript.new()
	equipment_manager = EquipmentManagerScript.new()
	equipment_manager.rng = rng
	rng.seed = int(run_info.get("seed", 0))
	gold = 1000
	kills = 0
	total_damage = 0.0
	devoured_count = 0
	fusion_count = 0
	elite_kills = 0
	boss_kills = 0
	_run_start_ms = Time.get_ticks_msec()
	# 从编辑器数据加载角色属性
	_apply_editor_character()
	# 开局送 3 件白装用于体验吞噬/融合
	var starter_pool: Array = EquipmentDB.all_templates()
	for i in 3:
		var t: EquipmentTemplate = starter_pool[rng.randi() % starter_pool.size()]
		equipment_manager.add_item(EquipmentInstance.create(t))
	_refresh_attributes()
	EventBus.stats_changed.emit()
	EventBus.inventory_changed.emit()
	EventBus.gold_changed.emit()
	EventBus.message.emit("新的一局开始：吞噬或融合，把木桩打爆！")


## 从 IronEater Creator 编辑器数据加载角色属性
func _apply_editor_character() -> void:
	var char_id := str(run_info.get("character", "warrior"))
	var creator := IronEaterCreator.new()
	var char_data := creator.load_character(char_id)
	if char_data == null or char_data.base_stats == null:
		return
	var stats := char_data.base_stats
	attributes.add_modifier("editor_char", AttributeSystem.STAT_BY_NAME.get("hp", 0), stats.hp, 0.0)
	attributes.add_modifier("editor_char", AttributeSystem.STAT_BY_NAME.get("atk", 0), stats.atk, 0.0)
	attributes.add_modifier("editor_char", AttributeSystem.STAT_BY_NAME.get("def", 0), stats.defense, 0.0)
	attributes.add_modifier("editor_char", AttributeSystem.STAT_BY_NAME.get("spd", 0), stats.spd, 0.0)
	EventBus.message.emit("加载角色: %s" % char_data.char_name)


## 主菜单开始/继续游戏时调用：写入本局配置并重置单局
func apply_run_info(info: Dictionary) -> void:
	run_info = info.duplicate()
	reset_run()


## 本局结束（死亡/通关/放弃）：生成结算数据并写入当前存档
func finish_run(reason: String) -> Dictionary:
	var play_seconds := float(Time.get_ticks_msec() - _run_start_ms) / 1000.0
	var floor := int(run_info.get("floor", 1))
	var result := {
		"reason": reason,
		"floor": floor,
		"kills": kills,
		"elite_kills": elite_kills,
		"boss_kills": boss_kills,
		"gold": gold,
		"play_time": play_seconds,
		"fragments": kills + floor * 2,
		"devoured": devoured_count,
		"fusions": fusion_count,
		"character": run_info.get("character", "warrior"),
		"difficulty": run_info.get("difficulty", "normal"),
		"total_damage": total_damage,
		# 通关时写入已通关层数，供 SaveManager 更新 highest_cleared_floor
		"cleared_floor": floor if reason == "cleared" else 0,
	}
	if SaveManager.active_slot > 0:
		SaveManager.finish_run(result)
	EventBus.run_finished.emit(result)
	return result


func stat_value(stat_name: String) -> float:
	var stat = AttributeSystem.STAT_BY_NAME.get(stat_name)
	if stat == null:
		return 0.0
	return attributes.get_value(stat)


func play_time_seconds() -> float:
	return float(Time.get_ticks_msec() - _run_start_ms) / 1000.0


## 已装备武器融合成长带来的攻击加成（《武器设计分册》融合攻击成长，0/5/10/15/20/25 节点）
func fusion_attack_bonus() -> float:
	var best := 0.0
	for item in equipment_manager.loadout.equipped_items():
		var t: EquipmentTemplate = item.get_template()
		if t != null and t.category == EquipmentDefs.Category.WEAPON:
			best = maxf(best, item.fusion_bonus())
	return best


## 把装备栏 + 吞噬累计写入角色属性（来源可追踪，随时可重算）
func _refresh_attributes() -> void:
	attributes.remove_modifiers("equip")
	attributes.remove_modifiers("fusion")
	attributes.remove_modifiers("devour")
	# 已装备：基础词条（含强化）+ 已获得融合词条
	for item in equipment_manager.loadout.equipped_items():
		var t: EquipmentTemplate = item.get_template()
		if t == null:
			continue
		if t.base_affix != null:
			var value: float = t.base_affix.value * item.enhancement_mult()
			_add_affix_to_attributes("equip", item.instance_id, t.base_affix.stat, t.base_affix.operation, value)
		for a in item.gained_fusion_affixes:
			_add_affix_to_attributes("fusion", item.instance_id, a.stat, a.operation, a.effective_value())
	# 吞噬累计（本局永久）
	for stat in equipment_manager.devour_totals:
		var stat_id = AttributeSystem.STAT_BY_NAME.get(stat)
		if stat_id == null:
			continue
		attributes.add_modifier("devour", stat_id, equipment_manager.devour_totals[stat]["flat"], equipment_manager.devour_totals[stat]["percent"])


func _add_affix_to_attributes(source: String, source_id: String, stat_name: String, operation: int, value: float) -> void:
	var stat_id = AttributeSystem.STAT_BY_NAME.get(stat_name)
	if stat_id == null:
		return
	var source_key := "%s_%s" % [source, source_id]
	if operation == EquipmentDefs.ModifierOperation.ADD_PERCENT:
		attributes.add_modifier(source_key, stat_id, 0.0, value)
	else:
		attributes.add_modifier(source_key, stat_id, value, 0.0)


func drop_item(at: Vector2) -> void:
	var item := equipment_manager.create_loot()
	if item == null:
		return
	_spawn_pickup(at, item)


func spawn_item() -> void:
	var item := equipment_manager.create_loot()
	if item == null:
		return
	equipment_manager.add_item(item)
	EventBus.inventory_changed.emit()
	EventBus.message.emit("获得装备：%s（%s）" % [item.display_name(), item.rarity_name()])


func give_gold(amount: int) -> void:
	gold += amount
	EventBus.gold_changed.emit()


func _spawn_pickup(at: Vector2, item: EquipmentInstance) -> void:
	var pickup = ItemPickupScene.instantiate()
	pickup.item = item
	pickup.position = at
	get_tree().current_scene.add_child(pickup)


## 装备管理操作统一入口：执行后刷新属性/UI
func equip_item(instance_id: String, target_slot: int = -1) -> Dictionary:
	var result := equipment_manager.equip(instance_id, target_slot)
	if result.ok:
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
	return result


func unequip_slot(slot: int) -> Dictionary:
	var result := equipment_manager.unequip(slot)
	if result.ok:
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
	return result


func devour_ids(ids: Array) -> Dictionary:
	var result := equipment_manager.devour_many(ids)
	if result.ok:
		devoured_count += result.get("count", 0)
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
	return result


## 直接吞噬一件掉落物实例（demo2：E 键吞噬，本局永久成长）
func devour_item(item: EquipmentInstance) -> Dictionary:
	if item == null:
		return {"ok": false, "reason": "无效掉落物"}
	var result := equipment_manager.devour_instance(item)
	if result.ok:
		devoured_count += result.get("count", 0)
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
	return result


func fuse_ids(main_id: String, material_id: String) -> Dictionary:
	var result := equipment_manager.fuse(main_id, material_id, gold)
	if result.ok:
		gold -= result.cost
		fusion_count += 1
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
		EventBus.gold_changed.emit()
	return result


func enhance_item(instance_id: String) -> Dictionary:
	var result := equipment_manager.enhance(instance_id, gold)
	if result.ok:
		gold -= result.cost
		_refresh_attributes()
		EventBus.stats_changed.emit()
		EventBus.inventory_changed.emit()
		EventBus.gold_changed.emit()
	return result
