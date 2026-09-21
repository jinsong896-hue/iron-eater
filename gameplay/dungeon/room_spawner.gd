class_name RoomSpawner
extends Node
## 刷怪编排 —— 生成点收集 / 敌人与群体单位分流 / 墙体喂给模拟核。
##
## ## 与 SpawnDirector 的分工
##
## · **本组件（RoomSpawner）**：普通房的刷怪编排——收集生成点、按层取怪、
##   词缀分配、swarm 分流（节点式 vs 群体模拟）
## · **SpawnDirector**：Boss 生成族（`_spawn_boss` / `_on_boss_died` /
##   `_autosave_before_boss` / `_preassigned_boss` / `_difficulty_mult`）
##
## 两者拆开而不是合成一个：Boss 分支有独立的存档时机与击杀结算，
## 与普通刷怪没有共享状态。
##
## ## 字段归属
##
## 刷怪字段（`_spawn_points` / `_boss_spawn` / `_living_enemies` /
## `_crowd_mgr` / `_walls_fed`）**留在 RoomController**——它们被清场
##（`debug_clear_enemies`）、死亡计数（`on_enemy_died`）、
## 清空判定（`_on_cleared`）共用。故本组件按 `room.xxx` 访问。
##
## ## 隐式宿主引用（搬迁时的重点）
##
## 组件化后 `add_child` / `connect` / `get_parent` **不再等于宿主**：
##   · `add_child(enemy)` → `room.add_child(enemy)`（敌人须挂在房间下，
##     否则 `die()` 里 `get_parent()` 拿到的掉落挂载点是错的）
##   · `died.connect(on_enemy_died)` → `room.on_enemy_died`（否则回调
##     连到组件自己）
## 这两类不报错，只在运行时以奇怪的方式失败——阶段 3 踩过（见 PROGRESS §二十二）。

## 宿主 RoomController（构造时注入）
var room: Node = null


## 装配：注入宿主房间控制器
func setup(owner_room: Node) -> void:
	room = owner_room

const ENEMY_SPAWN_GROUPS := ["enemy_spawn", "elite_spawn"]


func collect_nodes() -> void:
	var room_root := room.get_parent()
	if room_root == null:
		return

	var spawns_node := room_root.get_node_or_null("SpawnPoints")
	if spawns_node:
		for child in spawns_node.get_children():
			if not (child is Marker3D):
				continue
			var m := child as Marker3D
			if m.is_in_group("boss_spawn"):
				room._boss_spawn = m
			elif self.is_enemy_spawn(m):
				room._spawn_points.append(m)

	# 门在房间根下的 Doors 容器内（Door_* 命名）
	var doors_node := room_root.get_node_or_null("Doors")
	if doors_node:
		for child in doors_node.get_children():
			if child.name.begins_with("Door_"):
				room._doors.append(child)

	room.is_boss_room = room._boss_spawn != null or room._room_type() == "boss"


## 该标记是否为敌人刷怪点（白名单，避免把出生点/宝箱/交互物当成怪）
func is_enemy_spawn(marker: Marker3D) -> bool:
	for g in ENEMY_SPAWN_GROUPS:
		if marker.is_in_group(g):
			return true
	return false

const ENEMY_MECHANIC_KEYS := [
	"death_poison", "death_explode", "death_split", "summon",
	"stealth_always", "ambush", "slow_target_pct", "haste_self_pct",
	"healcut_on_hit", "knockback_on_hit", "aura_spec", "shield_spec",
	"pulse_slow", "enrage_below_pct", "teleport_spec", "ranged_spec",
]


## 该怪是否走群体模拟（而非 EnemyBase 节点）。
##
## 判据刻意保守——**只有明确标了 swarm 的基础怪**才走：
##   · 精英一律走节点（词缀行为、视觉差异、掉落规则都在节点侧）
##   · Boss 一律走节点（阶段机制）
##   · 带**已实现机制**的怪走节点（自爆/分裂/召唤/隐身等在 EnemyBase 里）
## 这样"搬走"的永远是行为最简单的近战追击型基础怪。
##
## **测试/调试开关** `room.CROWD_FORCE_SWARM`：置 true 时所有符合条件的
## 基础怪都走群体模拟，不必逐个给 MonsterDB 条目加 swarm 标记。
## 这让路由本身可被测试覆盖——否则"默认没有怪带 swarm"意味着
## 这条路径永远测不到，等于没有防线。
func should_use_crowd(m: Dictionary, is_elite_room: bool) -> bool:
	if is_elite_room or bool(m.get("is_elite", false)):
		return false
	if not (room.CROWD_FORCE_SWARM or bool(m.get("swarm", false))):
		return false
	# 带已实现机制的怪不搬（机制还没进模拟核）
	if self.has_enemy_mechanic(m):
		return false
	if room._crowd() == null:
		return false
	return true


## 该怪是否带引擎已实现的机制（→ 必须留在 EnemyBase 节点上）
func has_enemy_mechanic(m: Dictionary) -> bool:
	var sp: Dictionary = m.get("special", {})
	for key in ENEMY_MECHANIC_KEYS:
		if sp.has(key):
			return true
	return false

## 在指定生成点创建群体单位。返回是否成功。
func spawn_crowd_at(point: Marker3D, m: Dictionary, difficulty_mult: float) -> bool:
	var mgr: Node = room._crowd()
	if mgr == null:
		return false
	# **把本房墙体喂给模拟核**——否则群体单位没有墙的碰撞，
	# 会被斥力一路挤出房间，玩家清不掉也追不上（实机症状：
	# "敌人过多时被挤到边界外，游戏无法继续"）。
	# 每房都要重设：切房后障碍全变了。
	self.feed_walls_to_crowd(mgr)
	var hp := float(m.get("hp", 100.0)) * difficulty_mult
	var speed := 4.0 * float(m.get("speed_pct", 50)) / 100.0
	var pos := point.global_position
	var id: int = mgr.spawn_unit(pos, hp, speed, 0.35, 1.0, m)
	if id < 0:
		return false
	room.enemies_alive += 1
	return true


## 把本房墙体转成 AABB 喂给群体模拟核。
##
## 障碍格式：每 4 个 float 一组 = min_x, min_z, max_x, max_z（世界坐标）。
## 房间 JSON 的墙是格子坐标 + 方向，每格 1 米（CELL_SIZE=1.0），
## 故直接把格子边界当 AABB 用，不做缩放换算。
##
## 房间外墙若在 JSON 里没写全（部分模板只记了内墙），再补一圈房间边界，
## 保证单位跑不出房间——这是"被挤出边界"的最后一道防线。
func feed_walls_to_crowd(mgr) -> void:
	if mgr == null or room._walls_fed:
		return
	room._walls_fed = true
	var out := PackedFloat32Array()
	var d = room.room_data
	if d == null:
		return
	# room.room_data 可能是原始 JSON 字典（game_root 传的是 jd），
	# 也可能是 RoomData 对象（编辑器/测试路径）。两种都要支持。
	var width := 0.0
	var height := 0.0
	var walls: Array = []
	if d is Dictionary:
		width = float((d as Dictionary).get("width", 0))
		height = float((d as Dictionary).get("height", 0))
		walls = (d as Dictionary).get("walls", [])
	else:
		width = float(d.get("width"))
		height = float(d.get("height"))
		var w = d.get("walls")
		if w is Array:
			walls = w
	for w in walls:
		var wx := float(w.get("x", 0))
		var wy := float(w.get("y", 0))
		# 墙占 1 格；向外扩 0.1 留厚度，避免高速单位在单帧内穿过
		out.append(wx - 0.1)
		out.append(wy - 0.1)
		out.append(wx + 1.1)
		out.append(wy + 1.1)
	if width > 0.0 and height > 0.0:
		# 房间四边各补一条厚墙：JSON 若漏记外墙，这是最后一道防线，
		# 保证单位不会跑出房间（"被挤到边界外"的直接兜底）。
		var t := 0.5
		out.append(-t); out.append(-t); out.append(width + t); out.append(0.0)
		out.append(-t); out.append(height); out.append(width + t); out.append(height + t)
		out.append(-t); out.append(-t); out.append(0.0); out.append(height + t)
		out.append(width); out.append(-t); out.append(width + t); out.append(height + t)
	mgr.set_obstacles(out)


## 生成敌人（70% 概率/点；怪物从 MonsterDB 第一层池按房间类型选）
func spawn_enemies() -> void:
	if room._spawn_points.is_empty():
		return

	var difficulty_mult: float = room._difficulty_mult()
	var gm = room._game_manager()
	var rng := RandomNumberGenerator.new()
	if gm and gm.rng:
		rng.seed = gm.rng.randi()
	MonsterDB.init()

	# 本层怪物池（分册 3.1：基础怪按阶段、独特怪只在本层及相邻层、第9层独立池）
	var layer := self.current_layer()

	for point in room._spawn_points:
		if rng.randf() < 0.7:
			var m: Dictionary
			# 生成点带 monster_id meta 时用指定怪，否则按本层池加权随机
			var custom_id := str(point.get_meta("monster_id", ""))
			var is_elite_room: bool = room._room_type() == "elite" or str(point.get_meta("elite", "")) == "true"
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
			# **swarm 分流**（海量单位优化）：MonsterDB 条目带 swarm:true 的
			# 基础怪走 CrowdSim（C++ 模拟 + MultiMesh 渲染），其余（精英/
			# 带机制怪/Boss）仍走 EnemyBase 节点。
			#
			# 默认没有任何怪带这个标记——路由能力就位但不改变现有行为，
			# 真正启用是"给选定基础怪加 swarm 标记"这一数据决定。
			# 这是刻意的分批迁移：第一版只搬"移动+碰撞+渲染"，
			# 机制/词缀行为留给后续批次。
			if self.should_use_crowd(m, is_elite_room) and self.spawn_crowd_at(point, m, difficulty_mult):
				continue
			var enemy := self.spawn_enemy_at(point, difficulty_mult, m)
			if enemy:
				room.enemies_alive += 1
				room._living_enemies.append(enemy)


## 当前层数（取不到时按第 1 层）
func current_layer() -> int:
	var gm = room._game_manager()
	if gm == null:
		return 1
	var info = gm.get("run_info")
	if info is Dictionary:
		return int(info.get("floor", 1))
	return 1


## 在生成点创建敌人（应用 MonsterDB 配置 + 难度缩放）
func spawn_enemy_at(point: Marker3D, difficulty_mult: float, m: Dictionary = {}) -> EnemyBase:
	var enemy := EnemyBase.new()
	enemy.position = point.global_position
	# 精英房刷出的怪标记为精英，掉落走 ELITE_DROP_CHANCE
	if room._room_type() == "elite" or str(point.get_meta("elite", "")) == "true":
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
	enemy.died.connect(room.on_enemy_died)
	room.add_child(enemy)
	return enemy
