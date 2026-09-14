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
var _special_service
var _special_used := false
var _gambler_boxes: Array = []   # 赌徒挑战：已洗牌的 3 个箱子（开箱后填）


func _ready() -> void:
	_special_service = load("res://gameplay/dungeon/special_room_service.gd").new()
	_collect_nodes()


## 收集生成点（房间根下的 SpawnPoints 容器）与门节点（Doors 容器）
## 只有真正的敌人标记才算刷怪点。
## 修复：原先「非 boss_spawn 就当作刷怪点」会把 player_spawn / chest_spawn /
## shop_npc / heal_shrine 一并收进来 —— 起始房于是刷出一只怪（刷在玩家脚下），
## 宝箱房/特殊房也会多刷怪。白名单收口，其余标记一律忽略。
const ENEMY_SPAWN_GROUPS := ["enemy_spawn", "elite_spawn"]


func _collect_nodes() -> void:
	var room_root := get_parent()
	if room_root == null:
		return

	var spawns_node := room_root.get_node_or_null("SpawnPoints")
	if spawns_node:
		for child in spawns_node.get_children():
			if not (child is Marker3D):
				continue
			var m := child as Marker3D
			if m.is_in_group("boss_spawn"):
				_boss_spawn = m
			elif _is_enemy_spawn(m):
				_spawn_points.append(m)

	# 门在房间根下的 Doors 容器内（Door_* 命名）
	var doors_node := room_root.get_node_or_null("Doors")
	if doors_node:
		for child in doors_node.get_children():
			if child.name.begins_with("Door_"):
				_doors.append(child)

	is_boss_room = _boss_spawn != null or _room_type() == "boss"


## 该标记是否为敌人刷怪点（白名单，避免把出生点/宝箱/交互物当成怪）
func _is_enemy_spawn(marker: Marker3D) -> bool:
	for g in ENEMY_SPAWN_GROUPS:
		if marker.is_in_group(g):
			return true
	return false


## 激活房间（玩家进入）
func activate() -> void:
	if is_active:
		return

	is_active = true
	add_to_group("current_room_controller")
	var bus = _event_bus()
	if bus:
		bus.room_entered.emit(_room_id())

	# 回访已清空的房间：读回清空状态（房间节点每次进入都重建，控制器实例是新的）
	if not is_cleared and _room_was_cleared():
		is_cleared = true

	# 同理读回特殊房结算状态，否则回访会重复发奖
	if not _special_used and _special_was_used():
		_special_used = true

	if is_cleared:
		_open_doors()
		if is_boss_room:
			_show_portal()
		return

	# 特殊房不锁门：玩家可自由进出，奖励在玩家主动交互时结算
	if _is_special_room():
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


## 登记运行时生成的敌人（召唤物 / 死亡分裂的子体）
## 必须登记，否则这些敌人不计入存活数：玩家清完原始怪后房间会提前判定清空，
## 残留的召唤物/分裂体仍在攻击玩家，但门已开、房间已"通关"。
## 注意顺序：敌人 die() 时会先触发召唤/分裂，再发 died 信号，
## 故这里的 +1 早于父体的 -1，计数不会掉到 0 而误判清空。
func register_summoned_enemy(enemy) -> void:
	if enemy == null:
		return
	enemies_alive += 1
	if enemy is EnemyBase:
		_living_enemies.append(enemy)
		enemy.died.connect(on_enemy_died)
		is_cleared = false    # 有活敌人时取消清空标记（防止边界情况误判）


# ============================================================
# 调试接口（实机测试模式用；面板/控制台调用）
# ============================================================

## 在指定位置生成 N 只指定怪。
##
## 不能直接调 _spawn_enemy_at：那个私有方法**缺一个关键副作用**——
## activate() 是在 _spawn_enemies() **之后**才 _lock_doors() 的。
## 往已清空/特殊房刷怪时不重新锁门，玩家能直接走出去，清空判定也会错。
## 故这里 spawn → register → 锁门 一步到位。
## 返回 {ok, name?, spawned?, error?}
func debug_spawn(monster_id: String, count: int, at: Vector3) -> Dictionary:
	var m: Dictionary = MonsterDB.get_monster(monster_id)
	if m.is_empty():
		# 拼错时给近似候选（MonsterDB 没有 all_ids，从 all_monsters 提取）
		var ids: Array = []
		for mm in MonsterDB.all_monsters():
			ids.append(str(mm.get("id", "")))
		var near := DebugParser.suggest(monster_id, ids)
		var hint := ("  最接近：%s" % ", ".join(near)) if not near.is_empty() else ""
		return {"ok": false, "error": "未知怪物 id：%s%s（用 list monsters 查看全部）"
			% [monster_id, hint]}
	var spawned := 0
	for i in count:
		# 复用私有方法需要一个 Marker3D；造一个临时的，绕开它的定位逻辑
		var mk := Marker3D.new()
		mk.position = at + Vector3(cos(TAU * i / count), 0.0, sin(TAU * i / count)) * 1.5
		var enemy := _spawn_enemy_at(mk, 1.0, m)
		mk.free()
		if enemy != null:
			register_summoned_enemy(enemy)
			spawned += 1
	if spawned > 0:
		_lock_doors()          # 关键副作用：补上正常刷怪流程里的锁门
	return {"ok": true, "name": str(m.get("name", monster_id)), "spawned": spawned}


## 清空当前房间的所有敌人（立刻结算清空，供调试跳过战斗）
func debug_clear_enemies() -> void:
	for e in _living_enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	_living_enemies.clear()
	enemies_alive = 0
	_on_cleared()


## 运行时存活实体清单（读 _living_enemies，不遍历场景树）
func debug_living_enemies() -> Array:
	var out: Array = []
	for e in _living_enemies:
		if is_instance_valid(e):
			out.append(e)
	return out


## 房间清空（标记状态并落盘到 GameRoot.room_state，供回访时恢复）
func _on_cleared() -> void:
	if is_cleared:
		return
	is_cleared = true
	_mark_room_cleared()
	_open_doors()
	if is_boss_room and _boss != null:
		var gm = _game_manager()
		if gm:
			gm.boss_kills += 1
		_show_portal()
	var bus = _event_bus()
	if bus:
		bus.room_cleared.emit(_room_id())


## 把清空状态写回 GameRoot.room_state
## 房间节点每次进入都会重建（GameRoot._transition_to_room 销毁旧节点），
## 不落盘的话回访已清房间会重新刷怪/锁门，Boss 房甚至会重现传送门
func _mark_room_cleared() -> void:
	var gr = _game_root()
	if gr == null:
		return
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return
	var idx: int = int(gr.get("current_room_index"))
	if states.has(idx):
		states[idx]["cleared"] = true


## 从 GameRoot.room_state 读回本房历史清空状态
func _room_was_cleared() -> bool:
	var gr = _game_root()
	if gr == null:
		return false
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return false
	var idx: int = int(gr.get("current_room_index"))
	if not states.has(idx):
		return false
	return bool(states[idx].get("cleared", false))


## 把特殊房结算状态写回 GameRoot.room_state
## 与 _mark_room_cleared 同理：控制器实例随房间重建而新建，
## 不落盘的话回访特殊房会重复发奖（记忆碎片可无限刷金币）
func _mark_special_used() -> void:
	_set_room_state_flag("special_used", true)


## 从 GameRoot.room_state 读回本房特殊房结算状态
func _special_was_used() -> bool:
	return _get_room_state_flag("special_used")


## 写一个房间状态标记到位（读不到 GameRoot 时静默跳过）
func _set_room_state_flag(key: String, value: bool) -> void:
	var gr = _game_root()
	if gr == null:
		return
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return
	var idx: int = int(gr.get("current_room_index"))
	if states.has(idx):
		states[idx][key] = value


## 读一个房间状态标记（缺省 false）
func _get_room_state_flag(key: String) -> bool:
	var gr = _game_root()
	if gr == null:
		return false
	var states = gr.get("room_state")
	if states == null or not (states is Dictionary):
		return false
	var idx: int = int(gr.get("current_room_index"))
	if not states.has(idx):
		return false
	return bool(states[idx].get(key, false))


## GameRoot 引用（运行时获取，--script 测试模式兼容）
## 优先按节点名找；测试场景把 main.tscn 嵌在别的父节点下，故回退到脚本属性探测
func _game_root():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var by_name := tree.root.get_node_or_null("GameRoot")
	if by_name != null:
		return by_name
	var scene := tree.current_scene
	if scene != null:
		var found: Node = _find_game_root(scene)
		if found != null:
			return found
	return null


## 递归查找带 room_state 属性的节点（GameRoot 特征）
func _find_game_root(node: Node) -> Node:
	if node.get("room_state") != null:
		return node
	for child in node.get_children():
		var hit: Node = _find_game_root(child)
		if hit != null:
			return hit
	return null


## 离开房间
func deactivate() -> void:
	is_active = false
	remove_from_group("current_room_controller")
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
	MonsterDB.init()

	# 本层怪物池（分册 3.1：基础怪按阶段、独特怪只在本层及相邻层、第9层独立池）
	var layer := _current_layer()

	for point in _spawn_points:
		if rng.randf() < 0.7:
			var m: Dictionary
			# 生成点带 monster_id meta 时用指定怪，否则按本层池加权随机
			var custom_id := str(point.get_meta("monster_id", ""))
			var is_elite_room := _room_type() == "elite" or str(point.get_meta("elite", "")) == "true"
			if not custom_id.is_empty():
				m = MonsterDB.get_monster(custom_id)
			elif is_elite_room:
				m = MonsterDB.random_elite_for_layer(layer, rng)
			else:
				m = MonsterDB.random_for_layer(layer, rng)
			if m.is_empty():
				continue
			# 词缀按阶段与是否精英分配（分册第 7 章）
			var phase: int = MonsterDB.PHASE_OF_LAYER.get(clampi(layer, 1, 9), 1)
			var affix_ids := AffixDB.roll(phase, is_elite_room, rng)
			if not affix_ids.is_empty():
				AffixDB.apply(m, affix_ids)
			var enemy := _spawn_enemy_at(point, difficulty_mult, m)
			if enemy:
				enemies_alive += 1
				_living_enemies.append(enemy)


## 当前层数（取不到时按第 1 层）
func _current_layer() -> int:
	var gm = _game_manager()
	if gm == null:
		return 1
	var info = gm.get("run_info")
	if info is Dictionary:
		return int(info.get("floor", 1))
	return 1


## 在生成点创建敌人（应用 MonsterDB 配置 + 难度缩放）
func _spawn_enemy_at(point: Marker3D, difficulty_mult: float, m: Dictionary = {}) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position
	# 精英房刷出的怪标记为精英，掉落走 ELITE_DROP_CHANCE
	if _room_type() == "elite" or str(point.get_meta("elite", "")) == "true":
		enemy.is_elite = true
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
	MonsterDB.init()
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
	# 通知 HUD 显示顶部 Boss 血条栏
	var bus_boss = _event_bus()
	if bus_boss:
		var bname: String = str(_boss.get("monster_name"))
		if bname.is_empty():
			bname = "BOSS"
		bus_boss.boss_engaged.emit(bname, _boss.max_hp)
	enemies_alive += 1
	_living_enemies.append(_boss)


## Boss 死亡：必掉两件装备 + 房间清空
func _on_boss_died(world_position: Vector3) -> void:
	enemies_alive = maxf(enemies_alive - 1, 0)
	# 通知 HUD 隐藏顶部 Boss 血条栏
	var bus_b = _event_bus()
	if bus_b:
		bus_b.boss_state_changed.emit(true)
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


## 判断是否为商店、泉水或事件特殊房。
func _is_special_room() -> bool:
	return _room_type() in ["shop", "heal", "event"]

## 执行特殊房交互（不锁门，可重复进入；奖励只结算一次）
## 返回 {ok, reason?, already_used?}，UI / 输入层据 ok 决定是否提示
func interact_special() -> Dictionary:
	if not _is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	if _special_used:
		return {"ok": false, "already_used": true, "reason": "这里已经探索过了"}
	var result: Dictionary
	match _room_type():
		"heal":
			var gm = _game_manager()
			result = _special_service.use_healing_spring(gm.attributes if gm else null)
		"shop":
			var gm_shop = _game_manager()
			var config: Dictionary = _room_interaction()
			var state := {"gold": gm_shop.gold if gm_shop else 0}
			result = _special_service.buy_health_potion(state, int(config.get("price", 25)), float(config.get("heal", 80.0)))
			if result.get("ok", false) and gm_shop:
				gm_shop.gold = result.gold
				if gm_shop.consumable_inventory:
					gm_shop.consumable_inventory.add_health_potion(1)
		"event":
			var config_event: Dictionary = _room_interaction()
			result = _special_service.claim_event_reward(config_event, int(config_event.get("reward", 12)))
	if result.get("ok", false):
		_special_used = true
		_mark_special_used()
	return result

## 获取特殊房配置。
func _room_interaction() -> Dictionary:
	if room_data is Dictionary:
		return room_data.get("interaction", {})
	return room_data.interaction


# ============================================================
# 特殊房 UI 接口（面板只展示与选择，业务校验全在这里）
# ============================================================

## 公开访问器：跨对象不要调下划线方法（player 需要据此决定是否让位给拾取）
func is_special_room() -> bool:
	return _is_special_room()


## 供 UI 读取的只读上下文
## {ok, kind, config, gold, potions, capacity, used, event_type}
func get_special_context() -> Dictionary:
	if not _is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	var gm = _game_manager()
	var inv = gm.consumable_inventory if gm else null
	var config: Dictionary = _room_interaction()
	return {
		"ok": true,
		"kind": _room_type(),
		"config": config,
		"gold": int(gm.gold) if gm else 0,
		"potions": inv.count(inv.HEALTH_POTION_ID) if inv else 0,
		"capacity": inv.capacity if inv else 0,
		"used": _special_used,
		"event_type": str(config.get("event_type", "memory_shard")),
	}


## 商店：购买一瓶生命药水（UI 专用，可重复购买；不置 _special_used）
## 返回服务层原样结果 {ok, gold?, quantity?, reason?}
func purchase_health_potion() -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var inv = gm.consumable_inventory
	if inv == null:
		return {"ok": false, "reason": "消耗品背包不可用"}
	var config: Dictionary = _room_interaction()
	var price := int(config.get("price", 25))
	var heal := float(config.get("heal", 80.0))

	# state 必须从真实背包播种，否则容量检查永远看不到已装数量
	var state := {
		"gold": int(gm.gold),
		"potions": inv.count(inv.HEALTH_POTION_ID),
		"capacity": inv.capacity,
	}
	var result: Dictionary = _special_service.buy_health_potion(state, price, heal)
	if not result.get("ok", false):
		return result

	# 服务层已扣费，这里入包；入包失败必须回滚，绝不吞钱
	var added: Dictionary = inv.add_health_potion(1)
	if not added.get("ok", false):
		return {"ok": false, "reason": added.get("reason", "消耗品背包已满")}

	gm.gold = int(result.get("gold", gm.gold))
	_emit_gold_changed()
	return result


## 事件：记忆碎片——直接发放（无选择）
## 返回 {ok, reward?, reason?}
func claim_memory_shard() -> Dictionary:
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var config: Dictionary = _room_interaction()
	var reward := int(config.get("reward", 100))
	var claimed := {"value": _special_used}
	var result: Dictionary = _special_service.claim_event_reward({}, reward, claimed)
	if not result.get("ok", false):
		return result
	gm.gold += int(result.get("reward", reward))
	_special_used = true
	_mark_special_used()
	_emit_gold_changed()
	var bus = _event_bus()
	if bus:
		bus.stats_changed.emit()
	return result


## 事件：赌徒的挑战——第一阶段，付费开箱
## 扣费并洗出 3 个箱子；返回值**不含奖励内容**（防 UI 提前泄漏答案）
## 返回 {ok, phase, cost, boxes: int, gold} / {ok:false, reason}
func start_gambler_challenge() -> Dictionary:
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	if _special_used:
		return {"ok": false, "reason": "已结算"}
	var config: Dictionary = _room_interaction()
	var cost := int(config.get("cost", 100))
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足", "gold": int(gm.gold)}
	gm.gold -= cost
	_gambler_boxes = _special_service.shuffle_gambler_boxes(
		config.get("boxes", []), gm.rng if gm else null
	)
	_emit_gold_changed()
	return {
		"ok": true, "phase": "choose", "cost": cost,
		"boxes": _gambler_boxes.size(), "gold": int(gm.gold),
	}


## 事件：赌徒的挑战——第二阶段，结算所选箱子
## 返回 {ok, outcome: "empty"|"gold"|"equipment", amount?, item_name?, reason?}
func resolve_gambler_choice(index: int) -> Dictionary:
	if _gambler_boxes.is_empty():
		return {"ok": false, "reason": "尚未开始挑战"}
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var claimed := {"value": _special_used}
	var result: Dictionary = _special_service.resolve_gambler_box(_gambler_boxes, index, claimed)
	if not result.get("ok", false):
		return result

	_special_used = true
	_mark_special_used()
	var bus = _event_bus()

	match str(result.get("outcome", "empty")):
		"gold":
			gm.gold += int(result.get("amount", 0))
			_emit_gold_changed()
			if bus:
				bus.stats_changed.emit()
		"equipment":
			var granted := _grant_random_equipment()
			if not granted.get("ok", false):
				# 背包装不下：退还开箱费，不让玩家白花钱
				var cost := int(_room_interaction().get("cost", 100))
				gm.gold += cost
				_emit_gold_changed()
				return {"ok": false, "reason": granted.get("reason", "装备背包已满")}
			result["item_name"] = granted.get("item_name", "")
	return result


## 随机发一件白装进装备背包（赌徒奖励用）
## 不走 LootSystem——它只生成地面掉落物，而这里是直接入包
func _grant_random_equipment() -> Dictionary:
	var gm = _game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备背包不可用"}
	var pool: Array = EquipmentDB.get_templates_by_rarity(EquipmentDefs.Rarity.WHITE)
	if pool.is_empty():
		return {"ok": false, "reason": "无可用装备"}
	var tpl = pool[gm.rng.randi_range(0, pool.size() - 1)]
	var item = EquipmentInstance.create(tpl)
	if not gm.equipment_manager.add_item(item):
		return {"ok": false, "reason": "装备背包已满"}
	var bus = _event_bus()
	if bus:
		bus.inventory_changed.emit()
		bus.item_picked_up.emit(str(item.instance_id), item.display_name())
	return {"ok": true, "item_name": item.display_name()}


## 发金币变更信号（商店/事件结算后刷新 HUD）
func _emit_gold_changed() -> void:
	var gm = _game_manager()
	var bus = _event_bus()
	if bus and gm:
		bus.gold_changed.emit(int(gm.gold))


## 房间清空（设置阻挡体）
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
