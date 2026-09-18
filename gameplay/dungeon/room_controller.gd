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
## Boss 击杀是否已计数。防止 _on_cleared 因「Boss 死后又刷新敌人」重复执行时
## 把 boss_kills 累加多次（见 _on_boss_died 注释）
var _boss_kill_counted := false
var _portal: Area3D = null
var _special_service
var _special_used := false
var _gambler_boxes: Array = []   # 赌徒挑战：已洗牌的 3 个箱子（开箱后填）
## 群体模拟管理器（只在有 swarm 怪的房间创建，见 _crowd()）
var _crowd_mgr: CrowdManager = null
## 特效池（惰性创建，见 effect_field()）
var _effect_field: EffectField = null
## 本房墙体是否已喂给模拟核（每房只喂一次）
var _walls_fed := false
## 测试/调试开关：强制所有符合条件的基础怪走群体模拟。
## 生产环境恒为 false（路由由 MonsterDB 的 swarm 标记决定）。
static var CROWD_FORCE_SWARM := false


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
		# 策划 5.3：「进入 Boss 房时自动存档（仅记录本局进度，死亡后不可读档）」。
		# 这是本作唯一的存档时机——此前只在"开局那一刻"写一次存档，
		# 玩家玩到第 5 层捡满装备，存档里还是开局状态。
		_autosave_before_boss()
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
	else:
		# **锁门不变量**：还有敌人活着 → 门必须是锁的。
		# 原先门只在 activate() 里锁一次，这里是唯一的「开门」反向操作，
		# 于是任何绕过 activate() 的补刷路径（召唤/分裂/调试刷怪）都会留下
		# 「房间里有怪、门却开着」的窗口——玩家清完原始怪前一脚踏出去，
		# 门就再也不关了。锁门是幂等的（DoorTrigger.lock 只在缺阻挡体时新建），
		# 每死一只补锁一次成本可忽略，换来的是不变量恒成立。
		_lock_doors()


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
		# 与 on_enemy_died 互补的另一半不变量：只要有怪在场上，门就该锁着。
		# 正常战斗流程里门本来就锁着（lock 幂等，重复调用不会叠加阻挡体），
		# 但「已清空的房间被重新召唤出敌人」这条路径原先只重置了清空标记、
		# 没补锁，门会一直敞着——玩家清完场再被召唤物缠住时就走出去了。
		_lock_doors()


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
	# 临时 Marker 必须**先挂进树**再用：_spawn_enemy_at 读的是
	# `point.global_position`，节点不在树里时 Godot 直接报
	# "!is_inside_tree()" 并返回原点——于是 debug_spawn 会把敌人
	# 全部刷在世界原点，而不是调用方指定的位置。
	var mk_holder := Marker3D.new()
	mk_holder.position = at
	add_child(mk_holder)
	for i in count:
		# 复用私有方法需要一个 Marker3D；造一个临时的，绕开它的定位逻辑
		var mk := Marker3D.new()
		mk.position = Vector3(cos(TAU * i / count), 0.0, sin(TAU * i / count)) * 1.5
		mk_holder.add_child(mk)
		var enemy := _spawn_enemy_at(mk, 1.0, m)
		if enemy != null:
			register_summoned_enemy(enemy)
			spawned += 1
	mk_holder.queue_free()
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
		# boss_kills 已在 _on_boss_died 结算（那里只记一次），此处只开门
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


## 泉水清空硫磺毒气（策划 6.7 的三种减层方式之一）。
## 毒气层数住在整层的 FloorMechanic 上，不在本房间控制器里。
func _clear_gas_if_any() -> void:
	var fm = _floor_mechanic()
	if fm != null:
		fm.call("clear_gas")


## 暂停/恢复毒气累积（策划 6.7：Boss 战期间暂停）
func _set_gas_paused(paused: bool) -> void:
	var fm = _floor_mechanic()
	if fm != null:
		fm.set("gas_paused", paused)


## 取整层的 FloorMechanic（不存在时返回 null——非第 6 层就没有毒气机制）
func _floor_mechanic():
	var gr = _game_root()
	if gr == null:
		return null
	var fm = gr.get("floor_mechanic")
	if fm != null and is_instance_valid(fm):
		return fm
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


## 引擎真正消费的机制键（见 EnemyBase._apply_mechanic）。
##
## **不能用"special 非空"当判据**：MonsterDB._special_for 的默认分支返回
## `{"mechanic": mech}`——那是给未来引擎实现用的**登记键**，不是已实现行为。
## 于是每只怪都有非空 special，一刀切会把所有怪都拒掉（实测踩到）。
## 只有下面这些键代表"这只怪真的有行为机制"，必须留在 EnemyBase 节点上。
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
## **测试/调试开关** `CROWD_FORCE_SWARM`：置 true 时所有符合条件的
## 基础怪都走群体模拟，不必逐个给 MonsterDB 条目加 swarm 标记。
## 这让路由本身可被测试覆盖——否则"默认没有怪带 swarm"意味着
## 这条路径永远测不到，等于没有防线。
func _should_use_crowd(m: Dictionary, is_elite_room: bool) -> bool:
	if is_elite_room or bool(m.get("is_elite", false)):
		return false
	if not (CROWD_FORCE_SWARM or bool(m.get("swarm", false))):
		return false
	# 带已实现机制的怪不搬（机制还没进模拟核）
	if _has_enemy_mechanic(m):
		return false
	if _crowd() == null:
		return false
	return true


## 该怪是否带引擎已实现的机制（→ 必须留在 EnemyBase 节点上）
func _has_enemy_mechanic(m: Dictionary) -> bool:
	var sp: Dictionary = m.get("special", {})
	for key in ENEMY_MECHANIC_KEYS:
		if sp.has(key):
			return true
	return false


## 本房的特效池（惰性创建，全房共用一个）。
##
## 挂在房间节点下随房间销毁——特效本就是房间的临时产物。
## 全房共用而不是每个敌人一个：池化的意义就是"少数节点反复复用"，
## 每个实体各建一个池等于没池化。
func effect_field() -> EffectField:
	if _effect_field != null and is_instance_valid(_effect_field):
		return _effect_field
	_effect_field = EffectField.new()
	_effect_field.name = "EffectField"
	add_child(_effect_field)
	return _effect_field


## 惰性创建群体管理器（只在本房真的有 swarm 怪时才建）
func _crowd() -> CrowdManager:
	if _crowd_mgr != null and is_instance_valid(_crowd_mgr):
		return _crowd_mgr
	# 至少一条后端可用才建（真扩展或 GDScript 降级）。
	# 探测走加载器而不是 ClassDB.class_exists("CrowdSimFallback")——
	# fallback 是 class_name 脚本，不是注册到 ClassDB 的原生类。
	if CrowdSimLoader.create() == null:
		return null
	_crowd_mgr = CrowdManager.new()
	_crowd_mgr.name = "CrowdManager"
	add_child(_crowd_mgr)
	_crowd_mgr.crowd_died.connect(_on_crowd_died)
	_crowd_mgr.crowd_attacked.connect(_on_crowd_attacked)
	return _crowd_mgr


## 群体单位攻击玩家 → 走**正常的受击链路**结算。
##
## 模拟核只报"打了多少"，护甲/减伤/无敌帧/护盾全由 player.take_damage 处理。
## 若在核里直接扣血，玩家堆防御就对群体单位无效——那种不一致极难察觉。
func _on_crowd_attacked(_pos: Vector3, damage: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("take_damage"):
		p.call("take_damage", damage, null)


## 群体死亡：同步计数 + 掉落 + 特效。
## 掉落走与节点式敌人**同一个 LootSystem 接口**，只是数据来源不同
##（节点侧在 EnemyBase.die() 里发，这里由死亡事件驱动）。
func _on_crowd_died(pos: Vector3, _is_elite: bool) -> void:
	enemies_alive = maxf(enemies_alive - 1, 0)
	# 死亡特效：群体单位此前**完全没有表现**，打死了毫无反馈。
	# 用轻量的 swarm_death 预设（粒子数少）——同时几百个死亡时，
	# 每个都放 20 颗粒子会瞬间把 GPU 粒子预算吃满。
	effect_field().play("swarm_death", pos, Color(0.85, 0.35, 0.30))
	var loot := LootSystem.new()
	var parent := get_parent()
	if parent != null:
		loot.generate_loot({}, pos, parent)
	if enemies_alive <= 0:
		_on_cleared()


## 在指定生成点创建群体单位。返回是否成功。
func _spawn_crowd_at(point: Marker3D, m: Dictionary, difficulty_mult: float) -> bool:
	var mgr := _crowd()
	if mgr == null:
		return false
	# **把本房墙体喂给模拟核**——否则群体单位没有墙的碰撞，
	# 会被斥力一路挤出房间，玩家清不掉也追不上（实机症状：
	# "敌人过多时被挤到边界外，游戏无法继续"）。
	# 每房都要重设：切房后障碍全变了。
	_feed_walls_to_crowd(mgr)
	var hp := float(m.get("hp", 100.0)) * difficulty_mult
	var speed := 4.0 * float(m.get("speed_pct", 50)) / 100.0
	var pos := point.global_position
	var id := mgr.spawn_unit(pos, hp, speed, 0.35, 1.0, m)
	if id < 0:
		return false
	enemies_alive += 1
	return true


## 把本房墙体转成 AABB 喂给群体模拟核。
##
## 障碍格式：每 4 个 float 一组 = min_x, min_z, max_x, max_z（世界坐标）。
## 房间 JSON 的墙是格子坐标 + 方向，每格 1 米（CELL_SIZE=1.0），
## 故直接把格子边界当 AABB 用，不做缩放换算。
##
## 房间外墙若在 JSON 里没写全（部分模板只记了内墙），再补一圈房间边界，
## 保证单位跑不出房间——这是"被挤出边界"的最后一道防线。
func _feed_walls_to_crowd(mgr) -> void:
	if mgr == null or _walls_fed:
		return
	_walls_fed = true
	var out := PackedFloat32Array()
	var d = room_data
	if d == null:
		return
	# room_data 可能是原始 JSON 字典（game_root 传的是 jd），
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
			# **swarm 分流**（海量单位优化）：MonsterDB 条目带 swarm:true 的
			# 基础怪走 CrowdSim（C++ 模拟 + MultiMesh 渲染），其余（精英/
			# 带机制怪/Boss）仍走 EnemyBase 节点。
			#
			# 默认没有任何怪带这个标记——路由能力就位但不改变现有行为，
			# 真正启用是"给选定基础怪加 swarm 标记"这一数据决定。
			# 这是刻意的分批迁移：第一版只搬"移动+碰撞+渲染"，
			# 机制/词缀行为留给后续批次。
			if _should_use_crowd(m, is_elite_room) and _spawn_crowd_at(point, m, difficulty_mult):
				continue
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


## 生成 Boss（按层从 BossDB 抽取——每层 7 个轮换，不同局不同）。
##
## 原先所有层都刷同一个「鼠王」，9 层打下来 Boss 完全相同。
## 现在：Boss 个体（名字/机制/相对强度）来自 BossDB，
## 层难度（boss_hp 基准）来自 FloorDefs，两者相乘。
## 第 8 层固定破坏神化身、第 9 层三连战由 BossDB 的 pool 直接决定。
func _spawn_boss() -> void:
	# 策划 6.7：Boss 战期间**暂停**硫磺毒气累积。
	# 挂在这里而不是"进 Boss 房时"——只有真的刷出 Boss 才算 Boss 战，
	# 空 Boss 房（异常数据）不该白暂停。
	_set_gas_paused(true)
	if _boss_spawn == null:
		return
	var mult := _difficulty_mult()
	var layer := _current_layer()
	MonsterDB.init()

	# **读生成阶段预抽的 Boss**，不在这里现抽。
	# 原因：Boss 决定房间模板尺寸（策划 7 章），而房间是预建的——
	# 必须先生成阶段定下来。这里现抽的话会出现「房间按 A 的尺寸建、
	# 却刷出 B」的错配，且同一种子两次进入可能刷不同 Boss。
	var boss_def := _preassigned_boss()

	_boss = EnemyBase.new()
	_boss.position = _boss_spawn.global_position
	if boss_def.is_empty():
		# 兜底：房间数据缺 boss_def（旧存档 / 手工构造的图）时现场抽一个
		var rng := RandomNumberGenerator.new()
		var gm_rng = _game_manager()
		if gm_rng != null and gm_rng.get("rng") != null:
			rng.seed = gm_rng.rng.randi()
		else:
			rng.randomize()
		boss_def = BossDB.random_for_floor(layer, rng)
	if boss_def.is_empty():
		_boss.apply_monster_config(MonsterDB.boss_monster())
	else:
		var cfg := BossDB.to_monster_config(boss_def, layer, FloorDefs.boss_hp(layer))
		_boss.apply_monster_config(cfg)
		# 装配 Boss 通用机制（阶段/护盾/场地/召唤）
		var bm_script = load("res://entities/enemies/boss_mechanics.gd")
		if bm_script != null:
			_boss.boss_mech = bm_script.attach(_boss, boss_def)
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
	# **Boss 击杀计数在 Boss 死时结算，不放 _on_cleared**：
	# _on_cleared 可能因「Boss 死后分裂/召唤出新的敌人」而再次执行
	# （register_summoned_enemy 会把 is_cleared 重置，见其注释），
	# 挂在里面会让 boss_kills 重复累加（实测同一只 Boss 计了 2 次）。
	if not _boss_kill_counted:
		_boss_kill_counted = true
		var gm_k = _game_manager()
		if gm_k:
			gm_k.boss_kills += 1
	# 通知 HUD 隐藏顶部 Boss 血条栏
	var bus_b = _event_bus()
	if bus_b:
		bus_b.boss_state_changed.emit(true)
	_show_portal()
	if enemies_alive <= 0:
		_on_cleared()


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
	var gr = _game_root()
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
	var layer_factor: float = FloorDefs.monster_mult(_current_layer())
	var gm = _game_manager()
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


## 触碰传送门 → 进入下一层。
##
## **隐藏层门槛**（策划书 1.3）：第 9 层需集齐 8 片钥匙碎片才能进入。
## 未集齐时**拦下传送**（提示 + 不切层），玩家留在本层可继续探索，
## 但传送门已开、可反复尝试——策划原文「进入后不可回头」指的是进去之后，
## 不是「凑不齐就死局」。
func _on_portal_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	var gm = _game_manager()
	if gm:
		var cur: int = int(gm.run_info.get("floor", 1))
		var next_floor: int = cur + 1

		# 隐藏层门槛：进入第 9 层需集齐碎片
		if next_floor >= FloorDefs.MAX_FLOOR and not gm.has_all_key_fragments():
			var bus_deny = _event_bus()
			if bus_deny:
				bus_deny.message.emit("混沌裂隙需要 %d 片钥匙碎片（当前 %d 片）" % [
					FloorDefs.KEY_FRAGMENTS_REQUIRED, int(gm.run_key_fragments)])
			return

		gm.run_info["floor"] = next_floor
		# 层间全恢复（满状态进新层）
		if GameBalance.FLOOR_TRANSITION_FULL_HEAL and gm.attributes:
			gm.attributes.hp = gm.attributes.max_hp
		# 同时清空词条与元素叠层——「满状态」必须包含这一项。
		# 毒蚀按策划「层数永不衰减、持续至目标死亡」，跨层不清的话
		# 玩家会带着上层的毒层数与三层毒负面（侵蚀/衰弱/虚弱）进新层，
		# 表现为「debuff 永远挂着、只有再吃一次才刷新」（实测报告）。
		if GameBalance.FLOOR_TRANSITION_FULL_HEAL:
			_clear_player_buffs()
		# 超出层数上限即通关（第 9 层打完结算）
		if next_floor > FloorDefs.MAX_FLOOR:
			gm.finish_run("cleared")
			return
		var bus0 = _event_bus()
		if bus0:
			bus0.stats_changed.emit()
	# 通知 GameRoot 重建地牢（下一层）。
	# **必须用 _game_root() 而不是 get_parent().get_parent()**：
	# 房间节点挂在 GameRoot/World 下，父节点是 World 而非 GameRoot，
	# 原先这样取得的是 World → has_method("next_floor") 恒 false
	# → 传送门只涨层数、地牢从不重建（玩家原地不动，以为传送没打通）。
	var game_root: Node = _game_root()
	if game_root != null and game_root.has_method("next_floor"):
		game_root.call("next_floor")


## 清空玩家身上的全部词条与元素叠层（换层"满状态"用）。
## 取不到玩家或 buffs 时静默跳过。
func _clear_player_buffs() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var pb = p.get("buffs")
		if pb != null and pb.has_method("clear"):
			pb.call("clear")
			return


## 房间类型（兼容 Dictionary 与 RoomData）
func _room_type() -> String:
	if room_data == null:
		return ""
	if room_data is Dictionary:
		return str(room_data.get("room_type", room_data.get("type", "")))
	return str(room_data.room_type)


## 判断是否为商店、泉水或事件特殊房。
## 是否为「不刷怪、不锁门」的功能房间。
## 商店/泉水/事件是特殊房（有交互物），奖励大厅（第 9 层）也是——
## 它满屋宝箱、没有敌人，玩家进来就是搜刮，锁门毫无意义。
func _is_special_room() -> bool:
	return _room_type() in ["shop", "heal", "event", "reward_hall"]

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
			# 泉水清空硫磺毒气（策划 6.7：减层方式之一是「泉水清空」）。
			# 挂在结算成功之后——没喝到水不该白清层。
			if result.get("ok", false):
				_clear_gas_if_any()
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
			# 事件按 event_type 分派到各自的规则（策划 总册 5.2 共 9 种）。
			# 未识别的类型退回「直接领奖」的旧行为，保证老模板仍可用。
			result = _handle_event(str(config_event.get("event_type", "memory_shard")), config_event)
	if result.get("ok", false):
		_special_used = true
		_mark_special_used()
	return result


## 事件房分派（对应策划 总册 5.2 的事件池）。
## 返回统一格式 {ok, reason?, ...}，具体字段按事件类型不同。
## selected_index 供锻造炉/祭坛指定背包里的装备（旧路径不传时取 -1）。
func _handle_event(event_type: String, config: Dictionary,
		selected_index: int = -1) -> Dictionary:
	match event_type:
		"plague":
			return _event_plague(config)
		"forge":
			return _event_forge(config, selected_index)
		"altar":
			return _event_altar(config, selected_index)
		"rift":
			return _event_rift(config)
		_:
			# 记忆碎片等「自动获得」型：直接结算奖励
			return _special_service.claim_event_reward(config, int(config.get("reward", 12)))


## 事件交互的公开入口（UI 用）。
## **不走 interact_special()**：那个是「按 E 直接结算」的旧路径，
## 无法传 selected_index——而锻造炉/祭坛必须先指定一件装备。
## 返回统一格式；成功后自动置 _special_used 并落盘。
func interact_event(selected_index: int = -1) -> Dictionary:
	if not _is_special_room():
		return {"ok": false, "reason": "该房间不可交互"}
	if _special_used:
		return {"ok": false, "already_used": true, "reason": "这里已经探索过了"}
	var config: Dictionary = _room_interaction()
	var result: Dictionary = _handle_event(
		str(config.get("event_type", "memory_shard")), config, selected_index)
	if result.get("ok", false):
		_special_used = true
		_mark_special_used()
	return result


## 瘟疫之泉：回满生命 + 随机一项属性 -10%（本局）。
func _event_plague(config: Dictionary) -> Dictionary:
	var gm = _game_manager()
	if gm == null or gm.attributes == null:
		return {"ok": false, "reason": "状态不可用"}
	var claimed := {"value": _special_used}
	var r: Dictionary = _special_service.use_plague_spring(gm.attributes, claimed, gm.rng)
	if not r.get("ok", false):
		return r
	# 施加永久减益（本局）——用独立源名，避免与装备/吞噬的 modifier 混淆
	var stat_key := str(r.get("cursed_stat", "atk"))
	var stat_id: int = gm.attributes.STAT_BY_NAME.get(stat_key, 0)
	gm.attributes.add_modifier("plague_curse", stat_id, 0.0, float(r.get("cursed_pct", -0.10)))
	_special_used = true
	_mark_special_used()
	var bus = _event_bus()
	if bus:
		bus.stats_changed.emit()
		bus.message.emit("瘟疫之泉：生命已恢复，但 %s 永久降低 10%%" % _stat_label(stat_key))
	return {"ok": true, "healed": r.get("healed", 0.0), "cursed_stat": stat_key}


## 锻造炉：免费把 1 件装备的稀有度 +1（策划：白→绿→蓝…）。
## 需要玩家指定装备——由 UI 传入 selected_index（背包下标）。
func _event_forge(config: Dictionary, selected_index: int = -1) -> Dictionary:
	var gm = _game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备系统不可用"}
	var inv: Array = gm.equipment_manager.get_inventory()
	var idx := selected_index
	if idx < 0 or idx >= inv.size():
		return {"ok": false, "reason": "请先选择要锻造的装备"}
	var inst = inv[idx]
	if inst.rarity >= EquipmentDefs.Rarity.BLUE:
		return {"ok": false, "reason": "锻造炉最高只能把装备提升到蓝装"}
	var r: Dictionary = _special_service.forge_upgrade(inst.rarity, EquipmentDefs.Rarity.BLUE)
	if not r.get("ok", false):
		return r
	inst.rarity = int(r.get("new_rarity", inst.rarity))
	_special_used = true
	_mark_special_used()
	_emit_bus_inventory_changed()
	return {"ok": true, "new_rarity": inst.rarity}


## 古代祭坛：献祭一件装备 → 同部位高 1 稀有度的随机装备（上限紫）。
func _event_altar(config: Dictionary, selected_index: int = -1) -> Dictionary:
	var gm = _game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "装备系统不可用"}
	var inv: Array = gm.equipment_manager.get_inventory()
	var idx := selected_index
	if idx < 0 or idx >= inv.size():
		return {"ok": false, "reason": "请先选择要献祭的装备"}
	var inst = inv[idx]
	var tpl = inst.get_template()
	if tpl == null:
		return {"ok": false, "reason": "装备数据异常"}
	var r: Dictionary = _special_service.altar_sacrifice(
		inst.rarity, int(tpl.slot), EquipmentDefs.Rarity.PURPLE)
	if not r.get("ok", false):
		return r
	# 抽同部位、目标稀有度的随机装备
	var pool: Array = EquipmentDB.get_templates_by_rarity(int(r.get("want_rarity", 1)))
	var matched: Array = []
	for t in pool:
		if int(t.slot) == int(tpl.slot):
			matched.append(t)
	if matched.is_empty():
		return {"ok": false, "reason": "没有可献祭换取的装备"}
	var picked = matched[gm.rng.randi_range(0, matched.size() - 1)]
	# 移除献祭品、加入新装备
	gm.equipment_manager.remove_item(inst)
	gm.equipment_manager.add_item(EquipmentInstance.create(picked))
	_special_used = true
	_mark_special_used()
	_emit_bus_inventory_changed()
	return {"ok": true, "item_name": picked.display_name}


## 时空裂隙：传送到本层一个已探索房间（重置该房间，可再刷掉落）。
func _event_rift(config: Dictionary) -> Dictionary:
	var gr = _game_root()
	if gr == null:
		return {"ok": false, "reason": "状态不可用"}
	# 已探索房列表
	var states = gr.get("room_state")
	var explored: Array = []
	if states is Dictionary:
		for i in states:
			if states[i].get("visited", false):
				explored.append(int(i))
	var cur: int = int(gr.get("current_room_index"))
	var gm_rng = _game_manager()
	var pick_rng: RandomNumberGenerator = gm_rng.rng if gm_rng != null and gm_rng.get("rng") != null else null
	var r: Dictionary = _special_service.rift_pick_target(explored, cur, pick_rng)
	if not r.get("ok", false):
		return r
	var target := int(r.get("target_index", -1))
	# 重置目标房的清空状态 → 可再刷一次掉落
	if states is Dictionary and states.has(target):
		states[target]["cleared"] = false
	_special_used = true
	_mark_special_used()
	# 延迟一帧再传送：此刻还在交互面板里，立即切房会让 UI 悬空。
	#
	# **延迟期间房间可能已经变了**（玩家/测试在这两帧内切了房）。
	# 那时再执行就是从非预期位置把玩家拽走——实测表现为测试的特殊房遍历
	# 断言「切房后停在目标房」偶发失败（期望 N 实际 = 裂隙传送目标）。
	# 故把「发起传送时的房间索引」带过去，落地时校验。
	gr.call_deferred("_deferred_rift_transition", target, cur)
	return {"ok": true, "target_index": target}


## 时空裂隙的延迟传送落地：仅在**发起房间仍是当前房间**时执行。
## 这不是加闸而是补正确性——延迟回调本就该校验前置条件。
func _deferred_rift_transition(target_idx: int, from_idx: int) -> void:
	var gr = _game_root()
	if gr == null:
		return
	var cur: int = int(gr.get("current_room_index"))
	if cur != from_idx:
		# 延迟期间房间已变，本次传送作废（奖励已发，不再把玩家拽走）
		return
	gr.call("_transition_to_room", target_idx)


## 属性键 → 中文名（提示文案用）
func _stat_label(key: String) -> String:
	match key:
		"atk": return "攻击力"
		"def": return "防御"
		"spd": return "移动速度"
	return key


## 发射背包变更信号（事件改动了装备时用）
func _emit_bus_inventory_changed() -> void:
	var bus = _event_bus()
	if bus:
		bus.inventory_changed.emit()
		bus.stats_changed.emit()

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


## 商店：属性灌注（策划 4.3.2「金币终极黑洞」）。
## 无限购，价格随次数递增（300 起、每次 +50）；
## 每次随机 +1~3 攻击 或 +3~8 生命（本局永久）。
## 返回 {ok, stat, amount, cost, gold}。
func purchase_infusion() -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null or gm.attributes == null:
		return {"ok": false, "reason": "状态不可用"}
	var cost := SpecialRoomService.infuse_cost(gm.infused_count)
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}
	var roll := SpecialRoomService.roll_infusion(gm.rng)
	var stat_key := str(roll.get("stat", "atk"))
	var amount := int(roll.get("amount", 0))
	# 灌注用固定源名累加（多次灌注叠加），故不 remove 旧值
	var stat_id: int = gm.attributes.STAT_BY_NAME.get(stat_key, 0)
	gm.attributes.add_modifier("infusion", stat_id, float(amount), 0.0)
	gm.gold -= cost
	gm.infused_count += 1
	_emit_gold_changed()
	var bus = _event_bus()
	if bus:
		bus.stats_changed.emit()
	return {"ok": true, "stat": stat_key, "amount": amount, "cost": cost,
		"gold": int(gm.gold)}


## 商店：购买融合折扣券（策划 4.3.2，300 金 → 下次融合费用减半）。
func purchase_fusion_coupon() -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	if gm.has_fusion_coupon:
		return {"ok": false, "reason": "已持有折扣券"}
	var price := SpecialRoomService.FUSION_COUPON_PRICE
	if int(gm.gold) < price:
		return {"ok": false, "reason": "金币不足（需要 %d）" % price}
	gm.gold -= price
	gm.has_fusion_coupon = true
	_emit_gold_changed()
	return {"ok": true, "cost": price, "gold": int(gm.gold)}


## 商店：购买升级券（策划 4.3.2，500/800/1200 三级）。
func purchase_shop_upgrade() -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	var r := SpecialRoomService.shop_upgrade(gm.shop_level)
	if not r.get("ok", false):
		return r
	var cost := int(r.get("cost", 0))
	if int(gm.gold) < cost:
		return {"ok": false, "reason": "金币不足（需要 %d）" % cost}
	gm.gold -= cost
	gm.shop_level = int(r.get("level", gm.shop_level + 1))
	_emit_gold_changed()
	return {"ok": true, "level": gm.shop_level, "cost": cost, "gold": int(gm.gold)}


## 商店：附魔（策划 4.3.2，低级 800 / 中级 2,000 / 高级 5,000；单件限 3 次）。
## 把一条通用词条（名词分册第 5 章）**附加到指定装备**上。
##
## 与 purchase_infusion 的区别：灌注给玩家加固定属性、与装备无关；
## 附魔把词条挂在装备实例上，卸下/丢弃时词条一起走。
##
## slot 指定目标槽位；不传则挑**已穿戴**里附魔次数最少的一件
## （避免连续附魔都堆在同一件上白撞 3 次上限）。
func purchase_enchant(tier: String = "mid", slot: int = -1) -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null or gm.equipment_manager == null:
		return {"ok": false, "reason": "状态不可用"}
	var em = gm.equipment_manager

	var target: EquipmentInstance = null
	if slot >= 0:
		target = em.get_equipped().get(slot)
	else:
		for s in em.get_equipped().values():
			if s == null:
				continue
			if not SpecialRoomService.can_enchant(s.enchant_stacks):
				continue
			if target == null or s.enchant_stacks < target.enchant_stacks:
				target = s
	if target == null:
		return {"ok": false, "reason": "没有可附魔的已穿戴装备（需先穿戴，且未达 3 次上限）"}

	var r: Dictionary = em.enchant(target, tier)
	if not r.get("ok", false):
		return r
	_emit_gold_changed()
	var bus = _event_bus()
	if bus:
		bus.stats_changed.emit()
		bus.message.emit("附魔成功：%s → %s" % [target.display_name(), str(r.get("text", ""))])
	return {"ok": true, "tier": tier, "cost": int(r.get("cost", 0)),
		"text": str(r.get("text", "")), "item": target.display_name(),
		"gold": int(gm.gold)}


## 商店：贷款（策划 4.3.2，借 2000 还 4000，结算时扣）。
func purchase_loan() -> Dictionary:
	if _room_type() != "shop":
		return {"ok": false, "reason": "此处不出售"}
	var gm = _game_manager()
	if gm == null:
		return {"ok": false, "reason": "状态不可用"}
	gm.gold += SpecialRoomService.LOAN_AMOUNT
	gm.loan_debt += SpecialRoomService.LOAN_REPAY
	_emit_gold_changed()
	return {"ok": true, "amount": SpecialRoomService.LOAN_AMOUNT,
		"debt": gm.loan_debt, "gold": int(gm.gold)}


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
