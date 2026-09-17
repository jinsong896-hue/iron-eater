class_name FloorMechanic
extends Node
## 整层机制状态容器 —— 跨房间存活的那一半
##
## **为什么必须拆出来**：`FloorEnvironment` 是**按房间**创建的
##（`game_root._build_room` 里 `FloorEnvironment.apply(...)`，预建时生成、
## 随房间销毁）。但策划的机制里有一部分是**整层持续**的：
## 第 6 层「硫磺毒气」每 35 秒 +1 层、玩家带着层数走过整个楼层，
## 层数不可能住在"某个房间"里。
##
## 故拆成两层职责：
##   · `FloorMechanic`（本类）—— 整层一个，`game_root` 持有，跨房间存活。
##     管跨房间状态（毒气层数）与全局事件订阅。
##   · `FloorEnvironment` —— 每房间一个，管这一间房的场地布置
##    （危害区/通风口/熔炉/掩体），并向本类上报事件。

## 毒气层数变化时发出（供 HUD 显示）。层数 0 表示无该机制。
signal gas_layers_changed(layers: int)

## 第 6 层毒气：每层每秒的真实伤害（策划 6.7：层数 ×1.5）
const GAS_DPS_PER_LAYER := 1.5
## 第 6 层毒气：累积间隔（策划 6.7：每 35 秒 +1 层）
const GAS_INTERVAL := 35.0
## 第 6 层毒气：层数上限（策划 6.7：最高 10 层）
const GAS_MAX_LAYERS := 10

## 当前层号
var floor_num := 1
## 当前毒气层数（仅第 6 层会 > 0）
var gas_layers := 0
## Boss 战期间暂停累积（策划 6.7 明确）
var gas_paused := false

var _gas_timer := 0.0
var _gas_dps_accum := 0.0
## 玩家引用（每帧结算真伤用；懒查找，避免开局时序问题）
var _player: Node = null


func setup(p_floor: int) -> void:
	floor_num = p_floor
	gas_layers = 0
	_gas_timer = 0.0
	_gas_dps_accum = 0.0
	set_process(_has_gas())
	_connect_events()


## 本层是否有毒气机制
func _has_gas() -> bool:
	return floor_num == 6


func _connect_events() -> void:
	var bus: Node = _event_bus()
	if bus == null:
		return
	# 减层挂钩（策划 6.7：击杀精英 -1、开宝箱 -1）
	if bus.has_signal("enemy_died") and not bus.enemy_died.is_connected(_on_enemy_died):
		bus.enemy_died.connect(_on_enemy_died)
	if bus.has_signal("chest_opened") and not bus.chest_opened.is_connected(_on_chest_opened):
		bus.chest_opened.connect(_on_chest_opened)


func _exit_tree() -> void:
	var bus: Node = _event_bus()
	if bus == null:
		return
	if bus.has_signal("enemy_died") and bus.enemy_died.is_connected(_on_enemy_died):
		bus.enemy_died.disconnect(_on_enemy_died)
	if bus.has_signal("chest_opened") and bus.chest_opened.is_connected(_on_chest_opened):
		bus.chest_opened.disconnect(_on_chest_opened)


func _process(delta: float) -> void:
	if not _has_gas():
		return
	# 累积（Boss 战期间暂停——策划 6.7）
	if not gas_paused:
		_gas_timer += delta
		if _gas_timer >= GAS_INTERVAL:
			_gas_timer -= GAS_INTERVAL
			_add_gas(1)
	# 真伤结算：每层每秒 ×1.5，**无视护甲/减伤**（策划明写"真实伤害"）
	if gas_layers > 0:
		_apply_gas_damage(delta)


## 每帧按 层数×1.5 结算真伤。
## 小数累积到 1 点再扣，避免每帧扣 0.025 这种碎数（血条会抖）。
func _apply_gas_damage(delta: float) -> void:
	var p := _find_player()
	if p == null:
		return
	var gm: Node = _game_manager()
	if gm == null or gm.attributes == null or gm.attributes.is_dead():
		return
	_gas_dps_accum += float(gas_layers) * GAS_DPS_PER_LAYER * delta
	var whole := floorf(_gas_dps_accum)
	if whole < 1.0:
		return
	_gas_dps_accum -= whole
	# 走 take_damage 而不是直接扣 attributes.hp：这样受击反馈、
	# 护盾、死亡判定等既有链路全部照常生效。
	# 但**护甲/减伤不参与**——策划要求真实伤害，故传一个专门的来源标记。
	if p.has_method("take_true_damage"):
		p.call("take_true_damage", whole)
	else:
		gm.attributes.take_damage(whole)


## 加层（上限 10）
func _add_gas(n: int) -> void:
	var before := gas_layers
	gas_layers = clampi(gas_layers + n, 0, GAS_MAX_LAYERS)
	if gas_layers != before:
		_announce_gas()


## 减层（精英击杀 / 开宝箱）
func _reduce_gas(n: int) -> void:
	_add_gas(-n)


## 清空（泉水，策划 6.7）
func clear_gas() -> void:
	_add_gas(-gas_layers)


func _announce_gas() -> void:
	gas_layers_changed.emit(gas_layers)
	var bus: Node = _event_bus()
	if bus and gas_layers > 0:
		bus.message.emit("硫磺毒气 %d 层（每秒 %d 伤害）" % [
			gas_layers, int(float(gas_layers) * GAS_DPS_PER_LAYER)])


## 精英击杀 -1（策划 6.7）
func _on_enemy_died(enemy: Node, _pos: Vector3, _loot: Array) -> void:
	if not _has_gas() or gas_layers <= 0:
		return
	# enemy_died 已带 enemy 引用，直接读 is_elite，无需新信号
	if enemy != null and is_instance_valid(enemy) and bool(enemy.get("is_elite")):
		_reduce_gas(1)


## 开宝箱 -1（策划 6.7）
func _on_chest_opened(_gold: int, _pos: Vector3) -> void:
	if _has_gas() and gas_layers > 0:
		_reduce_gas(1)


## 对外查询（HUD / 测试）
func gas_info() -> Dictionary:
	return {
		"layers": gas_layers, "max": GAS_MAX_LAYERS,
		"paused": gas_paused, "interval": GAS_INTERVAL,
		"dps_per_layer": GAS_DPS_PER_LAYER,
	}


func _find_player() -> Node:
	if _player != null and is_instance_valid(_player):
		return _player
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ps := tree.get_nodes_in_group("player")
	if ps.size() > 0:
		_player = ps[0]
	return _player


func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


func _event_bus() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EventBus")
	return null
