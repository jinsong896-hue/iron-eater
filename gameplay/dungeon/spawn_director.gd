class_name SpawnDirector
extends Node
## Boss 生成与难度系数 —— 房间刷怪编排的 Boss 分支。
##
## ## 范围说明（**只搬了 Boss 族**）
##
## `room_controller.gd` 的刷怪逻辑被群体接线（`_crowd()` / `_on_crowd_*` /
## `_spawn_crowd_at`）夹成几段，不是连续块。本组件先搬**最内聚、最独立**
## 的一段：Boss 生成族（`_spawn_boss` / `_on_boss_died` /
## `_autosave_before_boss` / `_preassigned_boss` / `_difficulty_mult`，124 行）。
##
## 其余刷怪部分（`_collect_nodes` / `_spawn_enemies` / `_spawn_enemy_at` /
## `_spawn_crowd_at`）与房间生命周期（`activate` / `debug_*` / `_living_enemies`）
## 耦合更紧，**未搬**——它们的字段（`_living_enemies` / `_crowd_mgr` /
## `_boss`）被清场、调试、死亡计数共用，硬拆会制造多份真相。
##
## ## 字段归属
##
## Boss 字段（`_boss` / `_boss_spawn` / `_boss_kill_counted`）留在 RoomController：
## `_on_cleared`（清空判定）与 `_show_portal`（传送门）都要读 `_boss`。
## 故本组件按 `room.xxx` 访问。

## 宿主 RoomController（构造时注入）
var room = null


## 装配：注入宿主房间控制器
func setup(owner_room) -> void:
	room = owner_room

func _spawn_boss() -> void:
	# 策划 6.7：Boss 战期间**暂停**硫磺毒气累积。
	# 挂在这里而不是"进 Boss 房时"——只有真的刷出 Boss 才算 Boss 战，
	# 空 Boss 房（异常数据）不该白暂停。
	room._set_gas_paused(true)
	if room._boss_spawn == null:
		return
	var mult := _difficulty_mult()
	var layer: int = room._current_layer()
	MonsterDB.init()

	# **读生成阶段预抽的 Boss**，不在这里现抽。
	# 原因：Boss 决定房间模板尺寸（策划 7 章），而房间是预建的——
	# 必须先生成阶段定下来。这里现抽的话会出现「房间按 A 的尺寸建、
	# 却刷出 B」的错配，且同一种子两次进入可能刷不同 Boss。
	var boss_def := _preassigned_boss()

	room._boss = EnemyBase.new()
	room._boss.position = room._boss_spawn.global_position
	if boss_def.is_empty():
		# 兜底：房间数据缺 boss_def（旧存档 / 手工构造的图）时现场抽一个
		var rng := RandomNumberGenerator.new()
		var gm_rng = room._game_manager()
		if gm_rng != null and gm_rng.get("rng") != null:
			rng.seed = gm_rng.rng.randi()
		else:
			rng.randomize()
		boss_def = BossDB.random_for_floor(layer, rng)
	if boss_def.is_empty():
		room._boss.apply_monster_config(MonsterDB.boss_monster())
	else:
		var cfg := BossDB.to_monster_config(boss_def, layer, FloorDefs.boss_hp(layer))
		room._boss.apply_monster_config(cfg)
		# 装配 Boss 通用机制（阶段/护盾/场地/召唤）
		var bm_script = load("res://entities/enemies/boss_mechanics.gd")
		if bm_script != null:
			room._boss.boss_mech = bm_script.attach(room._boss, boss_def)
	room._boss.max_hp *= mult
	room._boss.atk *= mult
	room._boss.attack_range = 2.6
	room._boss.gold_min = 50
	room._boss.gold_max = 120
	# Boss 必掉装备：掉落表指向随机白装由 LootSystem 处理，这里用必掉标记
	room._boss.set_meta("boss_loot", true)
	room._boss.died.connect(_on_boss_died)
	# **必须挂在 room 下而非本组件**：Boss 的 die() 用 get_parent() 找掉落
	# 的挂载点（掉落随房间销毁），挂到组件下会让掉落挂错父节点。
	room.add_child(room._boss)
	# 通知 HUD 显示顶部 Boss 血条栏
	var bus_boss = room._event_bus()
	if bus_boss:
		var bname: String = str(room._boss.get("monster_name"))
		if bname.is_empty():
			bname = "BOSS"
		bus_boss.boss_engaged.emit(bname, room._boss.max_hp)
	room.enemies_alive += 1
	room._living_enemies.append(room._boss)


## Boss 死亡：必掉两件装备 + 房间清空
func _on_boss_died(world_position: Vector3) -> void:
	room.enemies_alive = maxf(room.enemies_alive - 1, 0)
	# **Boss 击杀计数在 Boss 死时结算，不放 _on_cleared**：
	# _on_cleared 可能因「Boss 死后分裂/召唤出新的敌人」而再次执行
	# （register_summoned_enemy 会把 is_cleared 重置，见其注释），
	# 挂在里面会让 boss_kills 重复累加（实测同一只 Boss 计了 2 次）。
	if not room._boss_kill_counted:
		room._boss_kill_counted = true
		var gm_k = room._game_manager()
		if gm_k:
			gm_k.boss_kills += 1
	# 通知 HUD 隐藏顶部 Boss 血条栏
	var bus_b = room._event_bus()
	if bus_b:
		bus_b.boss_state_changed.emit(true)
	room._show_portal()
	if room.enemies_alive <= 0:
		room._on_cleared()


## 进入 Boss 房前自动存档（策划 5.3）。取不到存档系统时静默跳过（测试/无头环境）。
func _autosave_before_boss() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sm := tree.root.get_node_or_null("SaveManager")
	if sm == null or not sm.has_method("save"):
		return
	sm.call("save", int(sm.get("current_slot")))


## 读生成阶段预抽的 Boss 定义（房间数据里的 boss_def）。
## 取不到时返回空字典，由调用方兜底。
func _preassigned_boss() -> Dictionary:
	var gr = room._game_root()
	if gr == null:
		return {}
	var graph = gr.get("dungeon_graph")
	var idx: int = int(gr.get("current_room_index"))
	if graph == null or idx < 0 or idx >= graph.size():
		return {}
	return graph[idx].get("boss_def", {})


## 难度倍率 = 玩家难度选择 × 层因子。
##
## **层因子是必须的**：怪物池虽然按 `PHASE_OF_LAYER` 换阶段（1~2 层阶段一、
## 3~4 层阶段二…），但同阶段内 2 层共用一个池，若不给层因子，
## 第 2 层与第 1 层强度完全相同、第 4 层与第 3 层相同——
## 策划书 5.3 的「前慢后快」曲线就断了。
## 层因子来自 FloorDefs（1.0 → 3.30，第 9 层最高）。
func _difficulty_mult() -> float:
	var layer_factor: float = FloorDefs.monster_mult(room._current_layer())
	var gm = room._game_manager()
	if gm == null:
		return layer_factor
	# 玩家难度选择与层因子**相乘**：easy/hard 是全局手感，层是进度曲线
	match str(gm.run_info.get("difficulty", "normal")):
		"easy":
			return layer_factor * 0.8
		"hard":
			return layer_factor * 1.35
	return layer_factor


## 生成下一层传送门（Boss 房清空后出现，触碰进入下一层）
