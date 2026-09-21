extends Node3D
## GameRoot —— 游戏场景根节点，HD-2D 重构版
## 管理地下城生成、房间加载、房间切换
## 替代 Autoload DungeonManager，避免 class_name 编译依赖

const ROOM_DATA_DIR := "res://data/rooms/"
const ROOM_SIZE := 30.0
## 穿门进房后，玩家落在入口门内侧多远处（避开触发器的体积，防止立刻回触发）
const DOOR_ENTRY_OFFSET := 2.0

# 房间模板
var room_templates: Dictionary = {}
# 地下城数据
var dungeon_graph: Array[Dictionary] = []
var dungeon_connections: Array[Array] = []
var dungeon_start_index := 0
var current_room_index := 0
var _is_transitioning := false   # 切房重入保护（见 _transition_to_room）
## 切房后的全局防抖窗口（秒）：期间忽略所有门信号，杜绝连锁切房。
## 只覆盖「落点踩门」那一两帧——设大了会误伤正常玩法（玩家快速连续穿门
## 会被拦掉，表现为门"没反应"）。0.15s ≈ 9 帧，足够覆盖落点抖动。
const TRANSITION_COOLDOWN := 0.15
var _last_transition_time := -999.0
var dungeon_generated := false
var current_room_node: Node3D = null
var room_state: Dictionary = {}
## 本层地牢种子。用于「房间模板在生成期就定好」——同一房间无论重建多少次
## 都拿到同一个模板（见 _pick_template）。
var dungeon_seed := 0
## 整层机制容器（跨房间存活；如第 6 层毒气层数）。
## 每层重建一次，见 _rebuild_floor_mechanic。
var floor_mechanic: FloorMechanic = null

# 子节点。
#
# 用**按名递归查找**而不是 `$World`：3D 世界被挪进了 SubViewport 子树
# （见 main.tscn 与 rendering/effects/pixel_renderer.gd 的说明），
# 绝对路径会随包裹层数变化。节点仍是 GameRoot 的后代，只是多隔了几层。
@onready var world: Node3D = _find_scene_node("World")
@onready var camera_rig: Node3D = _find_scene_node("CameraRig")
@onready var player: Node3D = _find_scene_node("Player")

## 环境管理器（楼层雾色/环境光）。在 `_ready()` 里经 `_setup_environment()` 装配。
var environment_manager: WorldEnvironmentManager = null
## 房间工厂（模板挑选 / 房间构建 / 拓扑门 / 生成点与道具）。
## 在 `_ready()` 里经 `_setup_factory()` 装配。
var factory: RoomFactory = null
## 预建调度器（逐帧/一次性建房间，消切房卡顿）。
## 在 `_ready()` 里经 `_setup_factory()` 装配。
var preloader: PreloadScheduler = null
## 切房服务（门触发/防抖/重入保护/落点协调）。
## 在 `_ready()` 里经 `_setup_factory()` 装配。
var transition_svc: RoomTransitionService = null


## 在本场景内按名递归查找节点。
##
## 不用唯一名 `%World`：那要求 .tscn 里给节点打 `unique_name_in_owner = true`，
## 而这些节点是从 main.tscn 实例化来的，标记一漏就是运行期空引用。
## 也不用 `$World`：3D 世界现在隔着 SubViewportContainer/SubViewport 两层。
## 递归查找对两者都免疫，代价只是启动时一次树遍历。
func _find_scene_node(node_name: String) -> Node3D:
	var found := find_child(node_name, true, false)
	return found as Node3D


## 注册表现层工厂（供逻辑层按 key 取，见 core/spawn_registry.gd）。
##
## 集中注册而不是各自 `_ready` 自注册：当前只有 1 个工厂，
## 集中在这里一眼能看全"哪些被接上了"。注册项变多再考虑自注册。
##
## **必须在任何房间生成之前跑**——`SpawnDirector` 在刷 Boss 时会取
## `boss_mechanics`，取不到会 push_warning 且 Boss 少一整套机制。
func _register_spawn_factories() -> void:
	SpawnRegistry.register("boss_mechanics", func(target, boss_def):
		return BossMechanics.attach(target, boss_def))


## 装配房间工厂。**必须在 _register_templates / generate_dungeon 之前**——
## 模板注册与房间构建都转发到它。
func _setup_factory() -> void:
	factory = RoomFactory.new()
	factory.name = "RoomFactory"
	add_child(factory)
	factory.setup(self)
	preloader = PreloadScheduler.new()
	preloader.name = "PreloadScheduler"
	add_child(preloader)
	preloader.setup(self)
	transition_svc = RoomTransitionService.new()
	transition_svc.name = "RoomTransitionService"
	add_child(transition_svc)
	transition_svc.setup(self)


# ============================================================
# 房间工厂转发（实现已拆到 RoomFactory）
# ============================================================
#
# 以下全部是**内部实现**（实测零外部引用），保留薄转发只为：
# ① GameRoot 自己的 generate_dungeon / load_current_room / preload 仍按原名调用
# ② 测试与调试按名直呼时不必改


## 注册房间模板（转发）
func _register_templates() -> void:
	factory.register_templates()


## 构建房间节点（不入树；转发）
func _build_room(idx: int) -> Node3D:
	return factory.build_room(idx)


# ============================================================
# 切房服务转发（实现已拆到 RoomTransitionService）
# ============================================================
#
# 这一族外部引用最多（测试大量按名直呼），故**全部保留同名转发**。
# 实现与四道防线的说明见 gameplay/dungeon/room_transition_service.gd。


## 门触发（转发；EventBus.door_opened 的订阅方）
func _on_door_entered(direction: String, _door_id: String) -> void:
	transition_svc.on_door_entered(direction, _door_id)


## 按方向找邻接房（转发）
func _find_room_in_direction(direction: String) -> int:
	return transition_svc.find_room_in_direction(direction)


## 切到目标房（转发）
func _transition_to_room(target_idx: int, enter_direction: String = "") -> void:
	transition_svc.transition_to_room(target_idx, enter_direction)


## 把本房所有门临时标为「已触发」（转发）
func _suppress_all_doors() -> void:
	transition_svc.suppress_all_doors()


## 解除门抑制（转发）
func _release_suppressed_doors() -> void:
	transition_svc.release_suppressed_doors()


## 本房所有门触发器（转发）
func _room_door_triggers() -> Array:
	return transition_svc.room_door_triggers()


## 让门短暂失效（转发）
func _disarm_entry_door(enter_direction: String) -> void:
	transition_svc.disarm_entry_door(enter_direction)


## 玩家是否压在门触发器上（转发）
func _player_touches_door(trig: Node) -> bool:
	return transition_svc.player_touches_door(trig)


## 激活当前房间控制器（转发）
func _activate_current_room() -> void:
	transition_svc.activate_current_room()


func _ready() -> void:
	# 小地图数据源（HUD MinimapView 自动拉取）
	add_to_group("game_root")
	# 新一局开始，作废上一局的 GameRef 缓存（防跨局持有旧节点）
	GameRef.invalidate()
	_register_spawn_factories()
	_setup_factory()
	# 接线自检：把"有发无收"的信号点名打到输出。
	# **只在 debug 构建跑**（导出后的 release 不做无谓的字符串拼接）。
	# 不改任何行为、不报错、不影响门禁判据——只是让静默失效可见。
	if OS.is_debug_build():
		WiredCheck.audit_event_bus()
	# 直跑场景兜底：未经主菜单 start_new_run 时初始化局内数据
	if GameManager.attributes == null:
		GameManager.start_new_run(GameManager.run_info.duplicate())
	_register_templates()
	_setup_environment()
	EventBus.door_opened.connect(_on_door_entered)
	# 延迟生成地下城
	call_deferred("_init_dungeon")


func _init_dungeon() -> void:
	# 进入场景的第一段过渡：盖住整屏 → 生成 → 等满最低时长 → 淡出。
	# 时长锚定策划预算（总册 11.8：单房间加载 < 1 秒）。
	# **初始房不放进度条**——玩家在这个阶段看到的是过渡遮罩，
	# 遮罩淡出后立刻播入场动作（见 _play_entrance_after_load）。
	if _cinematics_enabled():
		await _begin_transition()
	# generate_dungeon 内部已按当前层取房间数与范围，并同步加载起始房、放置玩家
	generate_dungeon(randi())
	if _cinematics_enabled():
		await _finish_transition()
		_play_entrance_after_load()


## 演出（过渡遮罩 + 入场动作）是否启用。
## **headless 下跳过**：测试/CI 跑的是无头模式，没有画面，
## 而这些演出会锁输入、且最少占 2 秒，会让所有场景测试被迫等待。
## 有窗口的真实游玩不受影响。
##
## 注意：判定必须用 DisplayServer.get_name()，
## **`OS.has_feature("headless")` 在 --headless 下返回 false**（实测），
## earlier 用它做闸门等于没关。
func _cinematics_enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## 取过渡屏（挂在 SceneManager autoload 下，跨场景存活）
func _loading_screen():
	var sm := get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("loading"):
		return sm.call("loading")
	return null


## 盖上过渡遮罩
func _begin_transition() -> void:
	var ls = _loading_screen()
	if ls == null:
		return
	await ls.begin(_load_budget(), "噬 铁 者", "正在进入地下城…")


## 等满最低时长后淡出
func _finish_transition() -> void:
	var ls = _loading_screen()
	if ls == null:
		return
	await ls.finish()


func _load_budget() -> float:
	var sm := get_node_or_null("/root/SceneManager")
	if sm != null:
		return float(sm.get("LOAD_BUDGET_SECONDS"))
	return 1.0


## 遮罩淡出后播主角入场动作。
## 玩家的入场动画做好后，把 duration 改成动画长度即可（EntranceState 里换视觉）。
func _play_entrance_after_load() -> void:
	if player == null:
		return
	if player.has_method("play_entrance"):
		player.call("play_entrance")


## 进入下一层：清空当前层 → 重生成地牢 → 回初始房
func next_floor() -> void:
	# 清空旧房间
	if current_room_node:
		current_room_node.queue_free()
		current_room_node = null
	room_state.clear()

	# 层数由调用方写入 run_info（传送门 / 调试跳层），此处只读用于显示与事件
	var gm := get_node_or_null("/root/GameManager")
	var floor_num := 1
	if gm:
		floor_num = int(gm.run_info.get("floor", 1))
	var seed_value := randi()
	if gm and gm.rng:
		seed_value = gm.rng.randi()

	# 整层机制容器：跨房间存活的那一半（如第 6 层毒气层数）。
	# **必须在生成地牢之前重建**——房间预建时 FloorEnvironment 会读它的参数。
	_rebuild_floor_mechanic(floor_num)

	# generate_dungeon 内部按**当前层**取房间数与可用范围（FloorDefs），
	# 并同步加载起始房、放置玩家、激活控制器
	generate_dungeon(seed_value)

	if gm:
		gm.set_state(GameManager.GamePhase.DUNGEON)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.floor_changed.emit(floor_num)
		bus.message.emit("进入第 %d 层" % floor_num)

	# 层间切换是玩家**可感知**的卡顿点：`generate_dungeon` 只同步建了起始房，
	# 其余房间靠 `_process` 每帧 1 间补——而 1 间 ≈ 7ms，占掉一帧预算的四成
	# （见 PRELOAD_PER_FRAME 注释），玩家会在新层里持续抖好几秒。
	#
	# 切层瞬间本来就有整屏传送特效盖着，正是该把预建一次做完的时机。
	# 放在最后调：`floor_changed` 的监听方（HUD/小地图）此时已拿到新层数据，
	# 预建不会看到半更新的状态。
	preload_all()


# ============================================================
# 模板注册
# ============================================================

## 重建整层机制容器。切层时调用；同层内**不重建**（层数是跨房间状态）。
func _rebuild_floor_mechanic(floor_num: int) -> void:
	if floor_mechanic != null and is_instance_valid(floor_mechanic):
		floor_mechanic.queue_free()
	floor_mechanic = FloorMechanic.new()
	floor_mechanic.name = "FloorMechanic"
	add_child(floor_mechanic)
	floor_mechanic.setup(floor_num)


func generate_dungeon(seed_value: int, count: int = -1) -> void:
	var floor_num: int = _current_floor_num()
	# 记下本层种子：房间模板的确定性选择依赖它（见 _pick_template）
	dungeon_seed = seed_value
	# 整层机制容器必须**先于房间生成**存在：房间预建时 FloorEnvironment
	# 会读它的参数（如毒气层数）来决定布置。
	# next_floor 里已重建过一次；这里是首次生成（开局直跑场景）的兜底。
	if floor_mechanic == null or not is_instance_valid(floor_mechanic) \
			or floor_mechanic.floor_num != floor_num:
		_rebuild_floor_mechanic(floor_num)
	# 按层取默认规模：rng 用本次种子，保证同种子同层结果可复现
	var rng := RandomNumberGenerator.new()
	rng.set_seed(seed_value)
	if count <= 0:
		count = FloorDefs.room_count(floor_num, rng)
	elif count < DungeonGenerator.MIN_SAFE_ROOMS:
		# 低于安全下限（起始房+Boss 房+至少一间普通房）会生成失败，
		# 钳到下限而不是让调用方拿到空地牢
		count = DungeonGenerator.MIN_SAFE_ROOMS

	var gen := DungeonGenerator.new()
	gen.rng.set_seed(seed_value)
	gen.min_rooms = count
	gen.max_rooms = count
	# 本层可用范围（策划书 2.1：14×14 → 30×30 逐层扩张）
	gen.range_half = FloorDefs.range_half(floor_num)
	# 层数：第 9 层走特殊的「奖励大厅 + 三连战」房型分配
	gen.floor_num = floor_num
	gen.generate(seed_value)

	dungeon_graph = gen.rooms
	dungeon_connections = gen.connections
	dungeon_start_index = gen.start_room_index
	dungeon_generated = true
	current_room_index = 0
	room_state.clear()
	# 丢弃上一层的预建房间——留着会把旧层房间挂到新层上
	_clear_preload()

	for i in dungeon_graph.size():
		# shop_sold：该房商店已售出的装备 id。商店房回访时要恢复「已售罄」，
		# 不落盘的话回访会重新上架同一件，可无限回购。
		room_state[i] = {"cleared": false, "visited": false, "shop_sold": []}

	# 本层主题环境（雾/环境光）——与房间地板墙配色一起构成该层视觉主题
	_apply_floor_environment(floor_num)

	# 起始房立刻需要（玩家马上就在里面），同步建好入树；
	# 其余房间交给 _process 逐帧预建
	load_current_room()
	_place_player()
	_activate_current_room()
	# 首次生成走 `_init_dungeon`，那里有过渡遮罩盖着，整层一次性建完。
	# 这条路径（测试直调 / 调试跳层）没有遮罩，留给 _process 逐帧补，
	# 免得在无过渡的情况下同步卡住一帧。
	if not _cinematics_enabled():
		return
	preload_all()


## 按当前层应用世界环境主题（雾色/环境光）。
##
## 实现在 `WorldEnvironmentManager`（环境配置的唯一归属处）——
## 本函数只负责把楼层号传过去。
func _apply_floor_environment(floor_num: int) -> void:
	if environment_manager == null:
		return
	environment_manager.apply_floor(floor_num)


## 装配环境管理器并把场景里的 WorldEnvironment 注入进去。
##
## **注入而非让它自己找**：WorldEnvironment 挂在 SubViewport 子树下，
## 而管理器是本节点的子节点——`find_children` 只搜自己的后代，
## 找不到兄弟分支里的节点。**必须在 add_child 之后 setup**。
func _setup_environment() -> void:
	environment_manager = WorldEnvironmentManager.new()
	environment_manager.name = "EnvironmentManager"
	add_child(environment_manager)
	environment_manager.setup(_find_world_environment())


## 取本场景的 WorldEnvironment。
## **递归查找**而非 `$WorldEnvironment`：WorldEnvironment 现在挂在
## SubViewport 子树下（3D 世界整体下移了一层），写死路径会随包裹层数失效。
func _find_world_environment() -> WorldEnvironment:
	for node in find_children("*", "WorldEnvironment", true, false):
		return node as WorldEnvironment
	return null


# ============================================================
# 房间加载
# ============================================================

func get_current_room_data() -> Dictionary:
	if dungeon_graph.is_empty() or current_room_index >= dungeon_graph.size():
		return {}
	return dungeon_graph[current_room_index]


func load_current_room() -> Node3D:
	var idx := current_room_index
	var room_node: Node3D = null

	# 命中预建缓存 → 只需挂载。实测：构建 3.12ms + 入树 0.14ms，
	# 预建把玩家可感知的那段压到 ~1/35（真实 GPU 上材质首次编译更贵，收益更大）
	if _room_cache.has(idx):
		room_node = _room_cache[idx]
		_room_cache.erase(idx)
	else:
		room_node = _build_room(idx)

	if room_node == null:
		return factory.create_fallback_room()

	room_node.name = "Room_%d" % idx
	world.add_child(room_node)
	room_node.position = Vector3.ZERO
	if room_state.has(idx):
		room_state[idx]["visited"] = true
	current_room_node = room_node
	return room_node


# ============================================================
# 房间预加载
# ============================================================

## 房间节点缓存：索引 → 已构建但未入树的房间。
## 与 _json_cache 的区别：那个缓存的是 JSON 解析结果（省读盘），
## 这个缓存的是**建好的网格节点**（省建模，是切房卡顿的大头）。
##
## **留在 GameRoot**：`load_current_room()` 要读它取出已建好的房间直接挂载
##（这是预建收益的兑现点）。调度器按 `root._room_cache` 访问。
var _room_cache: Dictionary = {}
var _preload_cursor := 0
## 预建统计（调度器读写；留在 GameRoot 是因为 `preload_stats()` 的对外契约
## 由本类转发，且测试按 `gr.preload_stats()` 断言）
var _preload_built := 0
var _preload_usec := 0
## 正在构建的房间索引。**不能用 current_room_index 代替**——
## 预加载时房间是提前建的，那时 current_room_index 指向别的房
## （与 _apply_topology_doors 的 idx 参数同一个原因）。
var _building_room_index := -1


func _process(_delta: float) -> void:
	preloader.preload_step()


# ============================================================
# 预建调度转发（实现已拆到 PreloadScheduler）
# ============================================================


## 一次性预建整层（转发；给开场动画/切层传送特效期间用）
func preload_all() -> int:
	return preloader.preload_all()


## 丢弃预建缓存（转发；重建地牢时必须调用，否则会挂上上一层的房间）
func _clear_preload() -> void:
	preloader.clear_preload()


## 整层生成是否在策划预算内（转发）
func preload_budget_check() -> Dictionary:
	return preloader.preload_budget_check()


## 预加载统计（转发；供调试面板/测试断言）
func preload_stats() -> Dictionary:
	return preloader.preload_stats()


## 整层预建是否完成（转发）
func preload_done() -> bool:
	return preloader.preload_done()

func _current_floor_num() -> int:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return 1
	var info = gm.get("run_info")
	if info is Dictionary:
		return int(info.get("floor", 1))
	return 1




# ============================================================
# 调试接口（实机测试模式）
# ============================================================

## 跳到本层指定房间（序号）。_transition_to_room 是私有的，对外开一个口子。
func debug_goto_room(idx: int) -> void:
	if idx < 0 or idx >= dungeon_graph.size():
		return
	_transition_to_room(idx, "")


## 跳到指定层。注意 **next_floor() 自己不写层数**——层数只由
## RoomController._on_portal_entered 写，故调用方必须先设 run_info["floor"]。
## 上限 1..9 在 DebugManager 的命令层钳制（next_floor 里没有这个检查）。
func debug_goto_floor(floor_num: int) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		var info = gm.get("run_info")
		if info is Dictionary:
			info["floor"] = floor_num
	next_floor()


## 放置玩家。
## 顺序很重要：穿门切房时**必须**按入口门内侧落点，否则玩家会掉在房间中央
## （甚至落在别的门触发器上）导致反复切房 / 走进不该进的房间。
##
## 原实现先查全局 player_spawn 组，而每个模板都有该标记且旧房间是延迟销毁，
## 于是 spawns[0] 可能取到**上一个房间的残留标记** —— 这就是"随机跳到其他房间
## /传送到地图外"的根因。现改为：按门优先，本房标记只在无方向时用。
func _place_player(enter_direction: String = "") -> void:
	if player == null:
		return

	# 关键：落点前清零速度。
	# 奔跑穿门时玩家带着 7m/s 的惯性被搬到新房间门内侧，若不清零，
	# 一帧就能再次踩上门触发器；门失效保护只有 0.25s，
	# 足够跑出 1.75m —— 小房间里足以冲过整个房间踩到对面门，
	# 表现为「进右边的门却到了右边两格」。
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)

	# 1) 有进入方向（穿门切房）：放在入口门内侧
	if enter_direction != "" and _place_player_at_door(enter_direction):
		return

	# 2) 无方向（开局 / 传送门进新层）：用**本房**的 player_spawn 标记
	var spawn := _current_room_player_spawn()
	if spawn != null:
		player.global_position = spawn.global_position
		return

	# 3) 兜底：房间中心（原先用 Vector3.ZERO，那是房间角落的墙里）
	player.global_position = _room_center_world()


## 取当前房间自己的 player_spawn 标记（限定在本房间节点内，不跨房间）
func _current_room_player_spawn() -> Node3D:
	if current_room_node == null:
		return null
	for child in current_room_node.get_children():
		if child.is_in_group("player_spawn"):
			return child as Node3D
	# 标记可能挂在下级容器里
	for node in current_room_node.find_children("*", "Marker3D", true, false):
		if (node as Node).is_in_group("player_spawn"):
			return node as Node3D
	return null


## 当前房间的世界中心（按模板宽高算，不是硬编码的角落/固定值）
func _room_center_world() -> Vector3:
	var ctrl = current_room_node.get_node_or_null("RoomController") if current_room_node else null
	if ctrl != null:
		var d = ctrl.get("room_data")
		if d is Dictionary:
			return Vector3(float(d.get("width", 20)) * 0.5, 0.0, float(d.get("height", 15)) * 0.5)
	if current_room_node != null:
		# 退化：取所有生成点标记的包围盒中心
		var marks := current_room_node.find_children("*", "Marker3D", true, false)
		if not marks.is_empty():
			var sum := Vector3.ZERO
			for m in marks:
				sum += (m as Node3D).global_position
			return sum / float(marks.size())
	return Vector3.ZERO


## 按进入方向把玩家放在入口门内侧 1.5m
##
## 方向语义易错：从 A 往北走，进入的是 B 的**南门**（B 在 A 北侧），
## 且要在 B 内继续向**北**推进。原实现找的是「同向门」并往反向放，
## 结果玩家被放到房间另一侧（正好落在对面门触发器上 → 再次切房）。
func _place_player_at_door(enter_direction: String) -> bool:
	if current_room_node == null:
		return false
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return false

	# 进入本房所穿的门，方向与行进方向相反
	var entry_door_dir := _opposite_dir(enter_direction)
	# 进门后继续深入的方向就是行进方向
	var inward := _dir_vector(enter_direction)

	for door in doors_node.get_children():
		if not door.name.begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or str(trig.get("direction")) != entry_door_dir:
			continue
		# **y 必须归零**：门是竖立的物体，节点中心在 DOOR_HEIGHT/2（半空），
		# 而 inward 的水平向量 y=0，直接相加会把「门的高度」当成落点高度。
		# 后果：玩家被放到离地 1.5m 的空中 → 下落期间乱飘/踩到别的门 →
		# 切房连锁（实测：同一次运行里 y=0 的切房正常，y=2.0 的那次跑到了别的房）。
		var pos: Vector3 = (door as Node3D).global_position + inward * DOOR_ENTRY_OFFSET
		pos.y = 0.0
		player.global_position = pos
		return true
	return false


## 行进方向 → 该方向上的单位向量（3D，x 东 / z 南）
func _dir_vector(dir: String) -> Vector3:
	match dir:
		"north": return Vector3(0, 0, -1)
		"south": return Vector3(0, 0, 1)
		"west":  return Vector3(-1, 0, 0)
		"east":  return Vector3(1, 0, 0)
	return Vector3.ZERO


## 相反方向
func _opposite_dir(dir: String) -> String:
	match dir:
		"north": return "south"
		"south": return "north"
		"west":  return "east"
		"east":  return "west"
	return ""
