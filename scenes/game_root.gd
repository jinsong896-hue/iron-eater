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

# 子节点
@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig
@onready var player: Node3D = $Player


func _ready() -> void:
	# 小地图数据源（HUD MinimapView 自动拉取）
	add_to_group("game_root")
	# 直跑场景兜底：未经主菜单 start_new_run 时初始化局内数据
	if GameManager.attributes == null:
		GameManager.start_new_run(GameManager.run_info.duplicate())
	_register_templates()
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



func _register_templates() -> void:
	room_templates = {"start": [], "normal": [], "elite": [], "treasure": [], "boss": [], "shop": [], "heal": [], "event": [], "hidden": [], "reward_hall": []}
	var dir := DirAccess.open(ROOM_DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json") and not dir.current_is_dir():
			var rtype := _read_json_field(ROOM_DATA_DIR + fn, "room_type")
			if not rtype.is_empty():
				if not room_templates.has(rtype):
					room_templates[rtype] = []
				room_templates[rtype].append(ROOM_DATA_DIR + fn)
		fn = dir.get_next()
	dir.list_dir_end()


## 读单个字段（注册模板时用）。走同一个缓存，避免每个 JSON 读两遍。
func _read_json_field(path: String, field: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	if _json_cache.has(path):
		return str((_json_cache[path] as Dictionary).get(field, ""))
	var d := _read_json_dict(path)
	return str(d.get(field, ""))


# ============================================================
# 地下城生成
# ============================================================

## 生成地牢。
## count <= 0 时按**当前层**取房间数（FloorDefs：12~16 → 20~28 逐层递增，
## 第 9 层固定 5 间）；显式传正数则用它（测试与调试跳层需要固定规模）。
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
		room_state[i] = {"cleared": false, "visited": false}

	# 本层主题环境（雾/环境光）——与房间地板墙配色一起构成该层视觉主题
	_apply_floor_environment(floor_num)

	# 起始房立刻需要（玩家马上就在里面），同步建好入树；
	# 其余房间交给 _process 逐帧预建
	load_current_room()
	_place_player()
	_activate_current_room()


## 按当前层应用世界环境主题（雾色/环境光）。取不到 WorldEnvironment 时静默跳过。
func _apply_floor_environment(floor_num: int) -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.fog_light_color = FloorDefs.color_of(floor_num, "fog")
	env.ambient_light_color = FloorDefs.color_of(floor_num, "ambient")
	# 环境光强度随主题明度走：偏暗的层（虚空/裂隙）压暗，明亮层（熔炉/王座）提亮
	var amb := FloorDefs.color_of(floor_num, "ambient")
	var lum := (amb.r + amb.g + amb.b) / 3.0
	env.ambient_light_energy = clampf(0.4 + lum * 1.6, 0.3, 0.9)


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
		return _create_fallback_room()

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
var _room_cache: Dictionary = {}
var _preload_cursor := 0
## 一次性预建整层（**给开场动画/加载画面用**）。
## 逐帧 1 间 ≈ 7ms，放在游戏进行中会占掉一帧预算的四成、造成微顿；
## 开场动画期间没有别的事在做，一次建完最划算。
## 返回本次新建的房间数。
func preload_all() -> int:
	if not dungeon_generated:
		return 0
	var built := 0
	while _preload_cursor < dungeon_graph.size():
		var i := _preload_cursor
		_preload_cursor += 1
		if i == current_room_index or _room_cache.has(i):
			continue
		var t0 := Time.get_ticks_usec()
		var node := _build_room(i)
		_preload_usec += Time.get_ticks_usec() - t0
		if node != null:
			_room_cache[i] = node
			_preload_built += 1
			built += 1
	return built


## 每帧预建房间数。1 间 ≈ 7ms；分散到帧里仍有微顿，
## 故只在**开场动画尚未覆盖**或缓存已空时才有意义——
## 正常情况下由 preload_all() 在动画期间一次建完，这里兜底补齐。
const PRELOAD_PER_FRAME := 1
var _preload_built := 0
var _preload_usec := 0


## 增量预加载：每帧建少量房间，直到整层建完。
## 首次由开场动画盖住（玩家看不到），之后在游玩过程中逐步补完。
func _process(_delta: float) -> void:
	_preload_step()


## 整层生成是否在策划预算内（总册 11.8：单房间加载 < 1 秒）
## 返回 {ok, seconds, budget}
func preload_budget_check() -> Dictionary:
	var budget := 1.0
	var sm := get_node_or_null("/root/SceneManager")
	if sm != null:
		budget = float(sm.get("LOAD_BUDGET_SECONDS"))
	var secs := float(_preload_usec) / 1000000.0
	return {"ok": secs <= budget, "seconds": secs, "budget": budget}


func _preload_step() -> void:
	if not dungeon_generated or _preload_cursor >= dungeon_graph.size():
		return
	for _n in PRELOAD_PER_FRAME:
		if _preload_cursor >= dungeon_graph.size():
			return
		var i := _preload_cursor
		_preload_cursor += 1
		if i == current_room_index or _room_cache.has(i):
			continue
		var t0 := Time.get_ticks_usec()
		var node := _build_room(i)
		_preload_usec += Time.get_ticks_usec() - t0
		if node != null:
			_room_cache[i] = node
			_preload_built += 1


## 丢弃预建缓存（重建地牢时必须调用，否则会挂上上一层的房间）
func _clear_preload() -> void:
	for k in _room_cache:
		var n = _room_cache[k]
		if n != null and is_instance_valid(n):
			n.free()      # 未入树，free 即可
	_room_cache.clear()
	_preload_cursor = 0
	_preload_built = 0
	_preload_usec = 0


## 正在构建的房间索引。**不能用 current_room_index 代替**——
## 预加载时房间是提前建的，那时 current_room_index 指向别的房
## （与 _apply_topology_doors 的 idx 参数同一个原因）。
var _building_room_index := -1


## 构建房间节点（**不入树**）。入树由调用方负责——
## 预加载路径把它挂进缓存，正常路径立刻 world.add_child。
func _build_room(idx: int) -> Node3D:
	if dungeon_graph.is_empty() or idx < 0 or idx >= dungeon_graph.size():
		return null
	_building_room_index = idx

	var data: Dictionary = dungeon_graph[idx]
	var room_type: String = data.get("type", "normal")
	# Boss 房按预抽的 boss_size 指定模板尺寸（策划 7 章：不同 Boss 不同战场大小）
	var prefer := ""
	if room_type == "boss":
		var size_key := str(data.get("boss_size", "standard"))
		prefer = str(BossDB.SIZE_TEMPLATE.get(size_key, "room_boss"))
	var template_path := _pick_template(room_type, prefer)
	if template_path.is_empty():
		return null

	var room_node := Node3D.new()
	var containers := {}
	for name in ["Floor", "Walls", "Doors", "Props", "SpawnPoints"]:
		var c := Node3D.new()
		c.name = name
		room_node.add_child(c)
		containers[name] = c

	var RoomDataClass = load("res://data/rooms/room_data.gd")
	var jd := _read_json_dict(template_path)
	if RoomDataClass and not jd.is_empty():
		# 门按地牢拓扑重算，覆盖模板里写死的门（消除哑门与死胡同）
		# 必须传 idx：预建时 current_room_index 指向别的房
		_apply_topology_doors(jd, idx)
		var rd = RoomDataClass.new()
		rd.load_from_dict(jd)
		# 本层主题配色（FloorDefs：9 层各不相同）
		var floor_num: int = _current_floor_num()
		var floor_col: Color = FloorDefs.color_of(floor_num, "floor")
		var wall_col: Color = FloorDefs.color_of(floor_num, "wall")
		# 本层主题配色 + 主题 id（id 决定用图集里的哪块砖）
		var theme_id: String = FloorDefs.theme_id(floor_num)
		FloorBuilder.build(containers["Floor"], jd, floor_col, Color.TRANSPARENT, theme_id)
		WallBuilder.build(containers["Walls"], jd, wall_col, theme_id)
		DoorBuilder.build(containers["Doors"], jd)
		DecorationBuilder.build(containers["Props"], jd)
		_build_spawn_markers(containers["SpawnPoints"], jd)

		var controller := RoomController.new()
		controller.name = "RoomController"
		controller.set("room_data", jd)
		room_node.add_child(controller)

		# 本层环境机制（毒气/熔岩/爆炸/传送…）。挂在房间节点下，
		# 随房间销毁；无机制层（第 1 层）返回 null。
		FloorEnvironment.apply(room_node, floor_num, jd)

		# 破墙入口：本房若是隐藏房的锚房间，在共用的墙上放一个可交互裂缝
		_build_hidden_wall(room_node, idx, jd)

	return room_node


## 构建破墙入口（本房是某个隐藏房的锚房间时）。
## 位置取本房边界中点那条边（与门的落格口径一致）——隐藏房与锚房共用该边。
func _build_hidden_wall(room_node: Node3D, anchor_idx: int, jd: Dictionary) -> void:
	var w: float = float(jd.get("width", 20))
	var h: float = float(jd.get("height", 15))
	for i in dungeon_graph.size():
		var r: Dictionary = dungeon_graph[i]
		if str(r.get("type", "")) != "hidden":
			continue
		if int(r.get("anchor_index", -1)) != anchor_idx:
			continue
		var dir := str(r.get("anchor_dir", ""))
		# 锚房间朝隐藏房那侧的边界中点（与 DoorsByTopology.cell_for 同口径）
		var pos := Vector3.ZERO
		match dir:
			"north": pos = Vector3(w * 0.5, 1.5, -0.5)
			"south": pos = Vector3(w * 0.5, 1.5, h - 0.5)
			"west":  pos = Vector3(-0.5, 1.5, h * 0.5)
			"east":  pos = Vector3(w - 0.5, 1.5, h * 0.5)
		if dir.is_empty():
			continue
		var hw_script = load("res://world/rooms/hidden_wall.gd")
		if hw_script == null:
			continue
		hw_script.create(room_node, pos, i, dir)


## 当前层数（取不到时按第 1 层）。层数是主题/难度/规模的共同输入，
## 统一在这里兜底，避免散落的 `run_info.get("floor", 1)` 各写各的。
func _current_floor_num() -> int:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return 1
	var info = gm.get("run_info")
	if info is Dictionary:
		return int(info.get("floor", 1))
	return 1


## 预加载统计（供调试面板/测试断言）
func preload_stats() -> Dictionary:
	return {
		"total": dungeon_graph.size(),
		"built": _preload_built,
		"cached": _room_cache.size(),
		"cursor": _preload_cursor,
		"avg_ms": (float(_preload_usec) / float(maxi(_preload_built, 1))) / 1000.0,
	}


## 整层预建是否完成
func preload_done() -> bool:
	return dungeon_generated and _preload_cursor >= dungeon_graph.size()


## 房间 JSON 缓存：路径 → 解析后的字典。
## 原先每次切房都重新读盘 + JSON.parse（实测单次 0.97ms，占切房耗时的可观比例），
## 而房间模板在运行期不会变，读一次就够。
static var _json_cache := {}


## 读房间 JSON（带缓存）。
## **返回深拷贝**：调用方（_apply_topology_doors）会就地改 doors/walls，
## 直接给缓存引用会被写坏，下一次切同一间房就拿到被污染的数据。
func _read_json_dict(path: String) -> Dictionary:
	if _json_cache.has(path):
		return (_json_cache[path] as Dictionary).duplicate(true)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(t) != OK:
		return {}
	var parsed: Dictionary = j.data
	_json_cache[path] = parsed
	return parsed.duplicate(true)


## 按地牢拓扑重算本房的门，写回 jd["doors"]，并让边界墙在门格留洞
## 模板里的门方位是固定的，与随机拓扑对不上就会产生哑门（走上去不切房）
##
## idx 显式传入而非读 current_room_index——预加载时房间是**提前**构建的，
## 那时 current_room_index 还指向别的房，读它会把门装到错误的房间上。
## 不传（-1）则回退到 current_room_index，兼容既有调用。
func _apply_topology_doors(jd: Dictionary, idx: int = -1) -> void:
	if dungeon_graph.is_empty() or dungeon_connections.is_empty():
		return
	if idx < 0:
		idx = current_room_index
	if idx < 0 or idx >= dungeon_graph.size():
		return

	var start_idx: int = clampi(dungeon_start_index, 0, dungeon_graph.size() - 1)
	var parents: Array = DoorsByTopology.bfs_parents(dungeon_graph, dungeon_connections, start_idx)
	var back_idx: int = start_idx
	if idx < parents.size() and int(parents[idx]) >= 0:
		back_idx = int(parents[idx])

	var w: int = int(jd.get("width", 20))
	var h: int = int(jd.get("height", 15))
	var doors: Array = DoorsByTopology.build_doors(
		dungeon_graph, dungeon_connections, idx,
		start_idx, back_idx, w, h
	)
	if doors.is_empty():
		return
	# 模板里的旧门位置：若重算后那里不再是门，必须**把墙补回来**。
	# 否则模板里为旧门留的洞会变成「没有门的缺口」，玩家从那儿直接走出房间。
	var stale_door_keys := {}
	for d in jd.get("doors", []):
		stale_door_keys["%d_%d_%s" % [
			int(d.get("x", 0)), int(d.get("y", 0)), str(d.get("direction", ""))]] = true

	jd["doors"] = doors

	# 墙在门格留洞。
	#
	# **必须留两格**：门宽 DOOR_WIDTH=2.0，而墙段是 1 格宽（CELL_SIZE=1.0）。
	# 只删门格那一格 → 洞宽 1.0，而玩家胶囊直径也是 1.0 → **零间隙**，
	# 位置稍偏就卡在墙段上、推不进门触发区（表现为「走到门口过不去」）。
	# 门沿门面方向跨格，故洞要在该方向多留一格。
	# 角落格的反向墙要保留，故只删「与门同方位」的墙。
	var door_keys := {}
	for d in doors:
		var dx := int(d["x"])
		var dy := int(d["y"])
		var dir := str(d["direction"])
		door_keys["%d_%d_%s" % [dx, dy, dir]] = true
		# 沿门面方向扩一格：north/south 门面沿 x，west/east 沿 y
		if dir == "north" or dir == "south":
			door_keys["%d_%d_%s" % [dx + 1, dy, dir]] = true
		else:
			door_keys["%d_%d_%s" % [dx, dy + 1, dir]] = true

	var walls: Array = []
	for wall in jd.get("walls", []):
		var wdk := "%d_%d_%s" % [
			int(wall.get("x", 0)), int(wall.get("y", 0)), str(wall.get("direction", ""))
		]
		if door_keys.has(wdk):
			continue
		walls.append(wall)

	# 补回「旧门位置但已不是门」的墙（含其扩格），除非它现在是门
	for old_key in stale_door_keys:
		if door_keys.has(old_key):
			continue
		var parts: PackedStringArray = str(old_key).split("_")
		if parts.size() != 3:
			continue
		var ox := int(parts[0])
		var oy := int(parts[1])
		var odir := str(parts[2])
		# 该位置现在是否已被别的门占用
		if door_keys.has("%d_%d_%s" % [ox, oy, odir]):
			continue
		walls.append({"x": ox, "y": oy, "direction": odir, "type": "normal_wall"})
		if odir == "north" or odir == "south":
			if not door_keys.has("%d_%d_%s" % [ox + 1, oy, odir]):
				walls.append({"x": ox + 1, "y": oy, "direction": odir, "type": "normal_wall"})
		else:
			if not door_keys.has("%d_%d_%s" % [ox, oy + 1, odir]):
				walls.append({"x": ox, "y": oy + 1, "direction": odir, "type": "normal_wall"})

	jd["walls"] = walls


func _pick_template(room_type: String, prefer_id: String = "") -> String:
	var templates: Array = room_templates.get(room_type, [])
	# 指定模板（Boss 房用）：按 id 精确匹配 data/rooms/<prefer_id>.json
	if not prefer_id.is_empty():
		var want := "res://data/rooms/%s.json" % prefer_id
		if templates.has(want):
			return want
		# 指定模板不在本房型的池里时**不回退到随机**——宁可让调用方拿到空、
		# 走 _create_fallback_room，也不要静默换成尺寸不符的模板
	if templates.is_empty():
		for key in room_templates:
			var arr: Array = room_templates[key]
			if not arr.is_empty():
				return arr[0]
		return ""
	# **确定性选择**：用「地牢种子 + 房间下标」派生，而不是全局 randi()。
	#
	# 原先用 `randi()` 是「已进过的房间会不停变换」的根因：房间节点每次
	# 进入都重建（见 _transition_to_room），重建时又抽一次模板——同一个房间
	# 第二次进去可能换成长宽不同的另一套模板，布局全变。
	# 策划口径是「房间布局在开局就该定好」，故改为由种子派生：
	# 同种子 + 同房间 → 永远同一个模板。
	var h := hash("%d:%d:%s" % [dungeon_seed, _building_room_index, room_type])
	return templates[abs(h) % templates.size()]


func _build_spawn_markers(parent: Node3D, data) -> void:
	var entities = data.get("entities", [])
	for entity in entities:
		var etype := str(entity.get("type", ""))
		var gn := ""
		match etype:
			"player_spawn": gn = "player_spawn"
			"enemy_spawn":  gn = "enemy_spawn"
			"elite_spawn":  gn = "elite_spawn"
			"boss_spawn":   gn = "boss_spawn"
			"chest_spawn":  gn = "chest_spawn"
			"shop_npc":     gn = "shop_npc"
			"heal_shrine":  gn = "heal_shrine"
			"event_shrine": gn = "event_shrine"
		if gn.is_empty():
			continue
		var marker := Marker3D.new()
		marker.position = Vector3(float(entity.get("x", 0)), 0.0, float(entity.get("y", 0)))
		marker.add_to_group(gn)
		parent.add_child(marker)
		# 宝箱：chest_spawn 处实例化宝箱实体（可交互掉落）
		if etype == "chest_spawn":
			_spawn_chest(marker.position, parent)
		# 特殊房交互物：商店 NPC / 治疗泉水 / 事件祭坛
		elif etype in ["shop_npc", "heal_shrine", "event_shrine"]:
			_spawn_special_prop(marker.position, etype, parent)


## 在标记位置生成特殊房交互物（按实体类型决定外观）
func _spawn_special_prop(pos: Vector3, entity_type: String, parent: Node3D) -> void:
	var kinds := {"shop_npc": "shop", "heal_shrine": "heal", "event_shrine": "event"}
	var kind: String = kinds.get(entity_type, "")
	if kind.is_empty():
		return
	var script_res := load("res://world/props/special_prop.gd")
	if script_res == null:
		return
	var prop := Node3D.new()
	prop.name = "SpecialProp_%s" % kind
	prop.set_script(script_res)
	prop.set("prop_kind", kind)
	prop.position = pos
	parent.add_child(prop)


## 在标记位置生成宝箱实体
func _spawn_chest(pos: Vector3, parent: Node3D) -> void:
	var chest_scene := "res://scenes/props/chest.tscn"
	if not ResourceLoader.exists(chest_scene):
		return
	var scene := ResourceLoader.load(chest_scene, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return
	var chest := scene.instantiate()
	chest.position = pos
	# 高价值宝箱：隐藏房（策划 3.2）与第 9 层奖励大厅（策划 6.10「奖励狂欢」）
	# 同档——金币 300~800 + 必掉高稀有度装备。
	var rtype := _building_room_type()
	if rtype == "hidden" or rtype == "reward_hall":
		chest.set("is_hidden_reward", true)
		chest.set("gold_min", 300)
		chest.set("gold_max", 800)
	parent.add_child(chest)


## 当前正在构建的房间是否为隐藏房（_build_room 里按 idx 判断）
func _current_room_is_hidden() -> bool:
	return _building_room_type() == "hidden"


## 当前正在构建的房间类型（预建时 current_room_index 指向别的房，必须按 idx 查）
func _building_room_type() -> String:
	var idx := _building_room_index
	if idx < 0 or idx >= dungeon_graph.size():
		return ""
	return str(dungeon_graph[idx].get("type", ""))


func _create_fallback_room() -> Node3D:
	var room_node := Node3D.new()
	room_node.name = "Room_Fallback"
	world.add_child(room_node)
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor.mesh = plane
	room_node.add_child(floor)
	return room_node


# ============================================================
# 房间切换
# ============================================================

func _on_door_entered(direction: String, _door_id: String) -> void:
	if not dungeon_generated:
		return
	# 全局防抖：刚切完房的一小段时间内忽略所有门信号。
	# 落点靠近门、或奔跑时一帧位移大，都可能在同一帧/紧邻帧再次踩门；
	# 旧房间的门要到帧末才销毁，也在此时仍可被触发 → 「进一格穿两房」。
	# 单靠入口门自身的失效不够，这里再加一道与门无关的总闸。
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_time < TRANSITION_COOLDOWN:
		return
	var target_idx := _find_room_in_direction(direction)
	if target_idx < 0:
		return
	# 只在「门触发的切房」时启动防抖；程序性切房（下一层、测试直调）不启动，
	# 否则会误伤正常玩法与测试里的连续切房
	_last_transition_time = now
	_transition_to_room(target_idx, direction)


func _find_room_in_direction(direction: String) -> int:
	var data := get_current_room_data()
	if data.is_empty():
		return -1
	var current_pos: Vector2i = data.get("position", Vector2i.ZERO)
	var dir_vec := Vector2i.ZERO
	match direction:
		"north": dir_vec = Vector2i(0, -1)
		"south": dir_vec = Vector2i(0, 1)
		"west":  dir_vec = Vector2i(-1, 0)
		"east":  dir_vec = Vector2i(1, 0)
	var target_pos := current_pos + dir_vec
	for i in dungeon_graph.size():
		var pos: Vector2i = dungeon_graph[i].get("position", Vector2i.ZERO)
		if pos == target_pos:
			return i
	return -1


func _transition_to_room(target_idx: int, enter_direction: String = "") -> void:
	if target_idx == current_room_index:
		return
	# 重入保护：一次触发只切一次房。
	# 旧房间的门在本帧内仍然活着（queue_free 要到帧末），落点又靠近门，
	# 没有这道闸门时同一帧可能被第二扇门再触发一次 → 「进一格却穿两房」。
	if _is_transitioning:
		return
	_is_transitioning = true

	# 离开当前房间
	if current_room_node:
		var ctrl := current_room_node.get_node_or_null("RoomController")
		if ctrl and ctrl is RoomController:
			(ctrl as RoomController).deactivate()

	# 销毁旧房间
	if current_room_node:
		current_room_node.queue_free()
		current_room_node = null

	# 更新索引
	current_room_index = target_idx

	# 加载新房间
	load_current_room()
	_activate_current_room()
	# 顺序关键：**先把门标记为已触发，再放玩家**。
	# Godot 在 Area3D 进树时会对「已与其重叠的 body」派发 body_entered。
	# 若先放玩家、出生点又恰在某扇门的触发区内，信号会在我们能禁用之前就发出去
	# → 切房连锁（实测：期望房10 实际房8，玩家落在 (11,0,2) 的出生点、并不在门旁）。
	# _is_transitioning 只挡同一次调用的重入，跨调用无效，挡不住这个。
	_suppress_all_doors()
	_place_player(enter_direction)
	_release_suppressed_doors()
	# 再按落点收尾：只禁玩家真正压着的那扇（保留回头路）
	_disarm_entry_door(enter_direction)

	_is_transitioning = false


## 把本房所有门临时标为「已触发」，挡住 Area3D 进树时对重叠 body 的派发。
## 必须配合 _release_suppressed_doors()：否则门会一直哑掉，正常穿门失灵。
func _suppress_all_doors() -> void:
	for trig in _room_door_triggers():
		trig.set("_triggered", true)


## 解除抑制，但**保留玩家当前压着的那扇**（否则会被重叠派发再次触发）
func _release_suppressed_doors() -> void:
	for trig in _room_door_triggers():
		if not _player_touches_door(trig):
			if trig.has_method("reset_trigger"):
				trig.call("reset_trigger")


## 本房所有门触发器
func _room_door_triggers() -> Array:
	var out: Array = []
	if current_room_node == null:
		return out
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return out
	for door in doors_node.get_children():
		if not str(door.name).begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig != null:
			out.append(trig)
	return out

	_is_transitioning = false


## 让门短暂失效，避免玩家落点踩门导致连锁切房。
##
## 两种落点都会踩门，必须都覆盖：
##  ① 穿门切房：落点在本房入口门内侧（DOOR_ENTRY_OFFSET=2.0，不重叠），
##     但为稳妥仍把入口那扇禁用。
##  ② **无方向切房**（开局 / 传送门 / 直接调用）：走 player_spawn 分支，
##     而绝大多数模板的 player_spawn 距南门只有 1 格——门在**格边缘**
##     （world z = 格子 +0.5），触发器 Z 跨度 ±0.75，于是出生点实际**落在
##     触发器内**（重叠约 0.25m）。若本房恰有南邻，门立刻触发 → 连传两格。
##     （只有有南邻时才会连，故表现为偶发）
##
## 判定用**几何**而非 get_overlapping_bodies()：刚设置完 player 位置的
## 那一帧，Area3D 的重叠列表还没更新（要等物理帧），用重叠检测会漏判。
func _disarm_entry_door(enter_direction: String) -> void:
	if current_room_node == null:
		return
	var doors_node := current_room_node.get_node_or_null("Doors")
	if doors_node == null:
		return

	var entry_dir := "" if enter_direction.is_empty() else _opposite_dir(enter_direction)
	for door in doors_node.get_children():
		if not str(door.name).begins_with("Door_"):
			continue
		var trig = door.get_node_or_null("DoorTrigger")
		if trig == null or not trig.has_method("disarm_until_clear"):
			continue
		# 禁用条件：玩家正压在门上（任何情况都要），或有方向时的入口那扇。
		# 注意**不要**在无方向时无差别禁用全部门——那会挡掉紧随其后的合法切房。
		var touching: bool = _player_touches_door(trig)
		var is_entry: bool = entry_dir != "" and str(trig.get("direction")) == entry_dir
		if not touching and not is_entry:
			continue
		trig.call("disarm_until_clear")


## 玩家是否压在某个门触发器上（在触发器局部空间做盒判定，自动兼容门朝向）
## 触发器尺寸 2×3×1.5（半长 1.0 / 1.5 / 0.75），放宽容差。
## 玩家是否压在某个门触发器上（在触发器局部空间做盒判定，自动兼容门朝向）。
##
## **容差必须 ≥ 物理重叠包络**，否则会漏判：
##   物理包络 = 触发盒半长 + 玩家胶囊半径 = x ±(1.0+0.5) / z ±(0.75+0.5)
##            = x ±1.5 / z ±1.25
## 原先取的是 x±1.3 / z±1.05（比物理窄 0.2 米），留下的**缝隙带**会导致：
## 落点物理上压着门（Area3D 会派发 body_entered）、几何上却判"没碰"
## → _release_suppressed_doors 把这扇门 reset 释放 → 下一物理帧
## 幽灵派发穿透 → 连锁切房（表现为 room_flow 偶发「期望房 N 实际房 M」）。
## 这与 door_trigger 里的几何复核是同一个包络口径，两处必须一致。
const DOOR_TOUCH_HALF_X := 1.5
const DOOR_TOUCH_HALF_Z := 1.25


func _player_touches_door(trig: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not (trig is Node3D):
		return false
	var t := trig as Node3D
	var local: Vector3 = t.global_transform.affine_inverse() * player.global_position
	return absf(local.x) <= DOOR_TOUCH_HALF_X and absf(local.z) <= DOOR_TOUCH_HALF_Z


func _activate_current_room() -> void:
	if current_room_node == null:
		return
	var ctrl := current_room_node.get_node_or_null("RoomController")
	if ctrl and ctrl is RoomController:
		(ctrl as RoomController).activate()


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
