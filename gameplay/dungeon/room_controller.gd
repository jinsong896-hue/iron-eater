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
## 商店货架缓存（惰性构建，`_shop_stock_key` 是它的失效键）
var _shop_stock = null
var _shop_stock_key := ""
## 特殊房业务组件（商店/泉水/事件/赌徒）。在 `_ready()` 里经 `_setup_shop()` 装配。
var shop: ShopController = null
## Boss 生成组件。在 `_ready()` 里经 `_setup_spawner()` 装配。
var spawner: SpawnDirector = null
## 刷怪编排组件（生成点收集 / 敌人与群体单位分流）。
## 在 `_ready()` 里经 `_setup_spawner()` 装配——与 Boss 组件同批。
var room_spawner: RoomSpawner = null
## 群体模拟管理器（只在有 swarm 怪的房间创建，见 _crowd()）
var _crowd_mgr: CrowdManager = null
## 投射物模拟管理器（与群体管理器同生命周期）
var _proj_mgr: ProjectileManager = null
## 特效池（惰性创建，见 effect_field()）
var _effect_field: EffectField = null
## 本房墙体是否已喂给模拟核（每房只喂一次）
var _walls_fed := false
## 测试/调试开关：强制所有符合条件的基础怪走群体模拟。
## 生产环境恒为 false（路由由 MonsterDB 的 swarm 标记决定）。
static var CROWD_FORCE_SWARM := false


func _ready() -> void:
	_special_service = load("res://gameplay/dungeon/special_room_service.gd").new()
	_setup_shop()
	_setup_spawner()
	room_spawner.collect_nodes()


## 装配生成组件（Boss 生成族 + 刷怪编排）。
##
## 两个组件同批装配：Boss 分支与普通刷怪分支在 `activate()` 里二选一，
## 拆成两个字段只是为了各自内聚，装配时机没有差别。
func _setup_spawner() -> void:
	spawner = SpawnDirector.new()
	spawner.name = "SpawnDirector"
	add_child(spawner)
	spawner.setup(self)
	room_spawner = RoomSpawner.new()
	room_spawner.name = "RoomSpawner"
	add_child(room_spawner)
	room_spawner.setup(self)


## 装配特殊房业务组件。**必须在 _collect_nodes 之前**——本类的公开 API
## （interact_special / purchase_* / get_shop_stock 等）都转发到它。
func _setup_shop() -> void:
	shop = ShopController.new()
	shop.name = "ShopController"
	add_child(shop)
	shop.setup(self)


# ============================================================
# 刷怪编排转发（实现已拆到 RoomSpawner）
# ============================================================
#
# **字段留在本类**（_spawn_points / _living_enemies / _crowd_mgr / _walls_fed）：
# 清场（debug_clear_enemies）、死亡计数（on_enemy_died）、清空判定（_on_cleared）
# 都要读它们，故组件按 room.xxx 访问。
#
# 以下转发保留公开名——测试与 SpawnDirector 直接按名调用。


## 收集生成点与门节点（转发）
func _collect_nodes() -> void:
	room_spawner.collect_nodes()


## 刷怪（转发）
func _spawn_enemies() -> void:
	room_spawner.spawn_enemies()


## 该怪是否走群体模拟（转发）
func _should_use_crowd(m: Dictionary, is_elite_room: bool) -> bool:
	return room_spawner.should_use_crowd(m, is_elite_room)


## 在指定生成点创建群体单位（转发）
func _spawn_crowd_at(point: Marker3D, m: Dictionary, difficulty_mult: float) -> bool:
	return room_spawner.spawn_crowd_at(point, m, difficulty_mult)


## 在指定生成点创建节点式敌人（转发）
func _spawn_enemy_at(point: Marker3D, difficulty_mult: float, m: Dictionary = {}) -> EnemyBase:
	return room_spawner.spawn_enemy_at(point, difficulty_mult, m)


## 当前层数（转发；SpawnDirector 也经本方法取）
func _current_layer() -> int:
	return room_spawner.current_layer()


## 激活房间（玩家进入）
func activate() -> void:
	if is_active:
		return

	is_active = true
	add_to_group("current_room_controller")
	# 投射物管理器：与房间同生命周期（切房随房间销毁，残留子弹不会打到新房间）
	_ensure_projectile_mgr()
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
##
## 与 `debug_kill_all_enemies()` 的区别：本函数**不产死亡事件**（不走掉落、
## 不计击杀），只是把场地清干净并强制结算；后者走完整死亡路径。
## 两者都必须覆盖群体单位——只清节点侧的话，模拟核里的单位会继续攻击玩家。
func debug_clear_enemies() -> void:
	for e in _living_enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	_living_enemies.clear()
	if _crowd_mgr != null and is_instance_valid(_crowd_mgr):
		_crowd_mgr.kill_all_units()
	enemies_alive = 0
	_on_cleared()


## 运行时存活实体清单（读 _living_enemies，不遍历场景树）
##
## **注意：这里只有节点式敌人。** 群体单位（CrowdSim）住在模拟核的 SoA
## 数组里、不是场景节点，不在本清单内——需要连它们一起处理时用
## `debug_kill_all_enemies()`，别自己遍历本清单去"清场"。
func debug_living_enemies() -> Array:
	var out: Array = []
	for e in _living_enemies:
		if is_instance_valid(e):
			out.append(e)
	return out


## 清空本房所有存活敌人（节点式 + 群体），走正常死亡路径。
## 返回被清掉的总数。
##
## 存在的理由：`enemies_alive` 把两类敌人算在一起，而它们的死亡入口完全不同
##（节点侧 `EnemyBase.die()` / 群体侧 `crowd_died` 信号）。任何"清场"的调用方
## 只处理一半，就会让 `enemies_alive` 归不了零 → 房间永不清空 → 门永不开。
## 调试命令与测试都走这里，保证与产品路径同一套清空逻辑。
func debug_kill_all_enemies() -> int:
	var n := 0
	for e in _living_enemies.duplicate():
		if is_instance_valid(e):
			e.set("dodge_pct", 0.0)      # 清闪避，保证击杀确定性
			e.take_damage(999999.0)
			n += 1
	if _crowd_mgr != null and is_instance_valid(_crowd_mgr):
		n += _crowd_mgr.kill_all_units()
	return n


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


## GameRoot 引用。查找逻辑统一在 `GameRef.game_root()`（跨层引用的唯一入口）。
func _game_root():
	return GameRef.game_root()


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


## 惰性创建投射物管理器。
##
## **不能搭在 _crowd() 里**：那条路径只在"本房有 swarm 怪"时才走，
## 而投射物与 swarm 无关——没有 swarm 怪的房间照样要能发射投射物。
## 故由 activate() 无条件调用。
func _ensure_projectile_mgr() -> void:
	if _proj_mgr != null and is_instance_valid(_proj_mgr):
		return
	_proj_mgr = ProjectileManager.new()
	_proj_mgr.name = "ProjectileManager"
	add_child(_proj_mgr)


## 群体单位攻击玩家 → 走**正常的受击链路**结算。
##
## 模拟核只报"打了多少"，护甲/减伤/无敌帧/护盾全由 player.take_damage 处理。
## 若在核里直接扣血，玩家堆防御就对群体单位无效——那种不一致极难察觉。
##
## `attacker_id` 用来把攻击者节点补上：`player.take_damage` 的 `from`
## 参与「伤害反弹」词条（分册第 5 章，限定近战来源），传 null 就等于
## 该词条对 swarm 怪永久失效。群体单位不是节点，故拿 `CrowdUnitHost`
## 当代理——它有 `take_damage`，能把反伤原样转回 `damage_unit`。
func _on_crowd_attacked(_pos: Vector3, damage: float, attacker_id: int = -1) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("take_damage"):
		return
	var from: Node3D = null
	if _crowd_mgr != null and is_instance_valid(_crowd_mgr) and attacker_id >= 0:
		# `host_of` 会顺带建宿主（近战命中时本就建过，这里通常直接命中缓存）。
		# 取不到就退化为 null——反弹失效好过整条受击链路报错。
		var host = _crowd_mgr.call("host_of", attacker_id)
		if host is Node3D and is_instance_valid(host):
			from = host
	p.call("take_damage", damage, from)


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




## 生成 Boss（按层从 BossDB 抽取——每层 7 个轮换，不同局不同）。
##
## 原先所有层都刷同一个「鼠王」，9 层打下来 Boss 完全相同。
## 现在：Boss 个体（名字/机制/相对强度）来自 BossDB，
## 层难度（boss_hp 基准）来自 FloorDefs，两者相乘。
## 第 8 层固定破坏神化身、第 9 层三连战由 BossDB 的 pool 直接决定。
# ============================================================
# Boss 生成族转发（实现已拆到 SpawnDirector）
# ============================================================
#
# **字段留在本类**（_boss / _boss_spawn / _boss_kill_counted）：
# _on_cleared（清空判定）与 _show_portal（传送门）都要读 _boss。
#


## Boss 战前自动存档（转发；策划 5.3 唯一的存档时机）
func _autosave_before_boss() -> void:
	spawner._autosave_before_boss()


## 难度系数（转发；Boss 生成读它）
func _difficulty_mult() -> float:
	return spawner._difficulty_mult()
# 其余刷怪部分（_collect_nodes / _spawn_enemies / _spawn_enemy_at /
# _spawn_crowd_at）与房间生命周期耦合更紧，**未搬**（见组件文件头）。

## Boss 生成（转发）
func _spawn_boss() -> void:
	spawner._spawn_boss()


## Boss 死亡结算（转发）
func _on_boss_died(world_position: Vector3) -> void:
	spawner._on_boss_died(world_position)


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


# ============================================================
# 特殊房业务转发（实现已拆到 ShopController）
# ============================================================
#
# **字段留在本类**（_special_used / _special_service / _gambler_boxes /
# _shop_stock / _shop_stock_key）：`activate()` 要读 `_special_used`
# 决定是否恢复"已探索"状态。房间身份方法（_room_type / _is_special_room）
# 也留下——刷怪与锁门逻辑同样读它们，搬走会制造两份真相。
#
# 公开 API 全部保留转发，UI 与测试零改动。

## 执行特殊房交互（转发）
func interact_special() -> Dictionary:
	return shop.interact_special()


## 事件交互（转发；UI 用它传 selected_index）
func interact_event(selected_index: int = -1) -> Dictionary:
	return shop.interact_event(selected_index)


## 公开访问器（转发）
func is_special_room() -> bool:
	return _is_special_room()


## 供 UI 读取的只读上下文（转发）
func get_special_context() -> Dictionary:
	return shop.get_special_context()


## 购买生命药水（转发）
func purchase_health_potion() -> Dictionary:
	return shop.purchase_health_potion()


## 购买注魔（转发）
func purchase_infusion() -> Dictionary:
	return shop.purchase_infusion()


## 购买融合券（转发）
func purchase_fusion_coupon() -> Dictionary:
	return shop.purchase_fusion_coupon()


## 购买商店升级（转发）
func purchase_shop_upgrade() -> Dictionary:
	return shop.purchase_shop_upgrade()


## 购买附魔（转发）
func purchase_enchant(tier: String = "mid", slot: int = -1) -> Dictionary:
	return shop.purchase_enchant(tier, slot)


## 商店货架（转发）
func get_shop_stock() -> Array:
	return shop.get_shop_stock()


## 购买货架装备（转发）
func purchase_equipment(index: int) -> Dictionary:
	return shop.purchase_equipment(index)


## 贷款（转发）
func purchase_loan() -> Dictionary:
	return shop.purchase_loan()


## 领取记忆碎片（转发）
func claim_memory_shard() -> Dictionary:
	return shop.claim_memory_shard()


## 开始赌徒挑战（转发）
func start_gambler_challenge() -> Dictionary:
	return shop.start_gambler_challenge()


## 赌徒选箱（转发）
func resolve_gambler_choice(index: int) -> Dictionary:
	return shop.resolve_gambler_choice(index)

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
