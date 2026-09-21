class_name RoomFactory
extends Node
## 房间工厂 —— 模板挑选、房间节点构建、拓扑门重算、生成点与道具摆放。
##
## ## 为什么整体搬
##
## 这一族 13 个函数**互相调用、零外部引用**（实测：除 GameRoot 自身外
## 全项目无人调用），是内聚的独立簇。搬走后 GameRoot 只剩"何时建、建完挂哪"。
##
## ## 与 PreloadScheduler 的关系
##
## `_build_room` **不入树**——调用方负责挂载（见 `attach_to_world`）。
## 预建调度器把未入树的房间存进 `_room_cache`，切房时取出直接挂上。
##
## ## 字段归属
##
## `dungeon_graph` / `dungeon_seed` / `current_room_index` / `world` /
## `_building_room_index` 留在 GameRoot（生成、切房、预建共用），
## 组件按 `root.xxx` 访问。
##
## `_json_cache` 是 static（全项目共享的 JSON 解析缓存，省读盘），
## 组件自带同名 static 副本——**两处缓存不互通但无害**（同一文件解析两遍，
## 各存各的）。若要合并，把缓存抽成独立类即可，属后续优化。

## 宿主 GameRoot（构造时注入）
var root: Node = null

## JSON 解析缓存（static：跨房间、跨层复用，省重复读盘）
static var _json_cache := {}


## 装配：注入宿主 GameRoot
func setup(owner_root: Node) -> void:
	root = owner_root


func register_templates() -> void:
	root.room_templates = {"start": [], "normal": [], "elite": [], "treasure": [], "boss": [], "shop": [], "heal": [], "event": [], "hidden": [], "reward_hall": []}
	var dir := DirAccess.open(root.ROOM_DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".json") and not dir.current_is_dir():
			var rtype := self.read_json_field(root.ROOM_DATA_DIR + fn, "room_type")
			if not rtype.is_empty():
				if not root.room_templates.has(rtype):
					root.room_templates[rtype] = []
				root.room_templates[rtype].append(root.ROOM_DATA_DIR + fn)
		fn = dir.get_next()
	dir.list_dir_end()


## 读单个字段（注册模板时用）。走同一个缓存，避免每个 JSON 读两遍。
func read_json_field(path: String, field: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	if self._json_cache.has(path):
		return str((self._json_cache[path] as Dictionary).get(field, ""))
	var d := self.read_json_dict(path)
	return str(d.get(field, ""))


# ============================================================
# 地下城生成
# ============================================================

## 生成地牢。
## count <= 0 时按**当前层**取房间数（FloorDefs：12~16 → 20~28 逐层递增，
## 第 9 层固定 5 间）；显式传正数则用它（测试与调试跳层需要固定规模）。


## 构建房间节点（**不入树**）。入树由调用方负责——
## 预加载路径把它挂进缓存，正常路径立刻 root.world.add_child。
func build_room(idx: int) -> Node3D:
	if root.dungeon_graph.is_empty() or idx < 0 or idx >= root.dungeon_graph.size():
		return null
	root._building_room_index = idx

	var data: Dictionary = root.dungeon_graph[idx]
	var room_type: String = data.get("type", "normal")
	# Boss 房按预抽的 boss_size 指定模板尺寸（策划 7 章：不同 Boss 不同战场大小）
	var prefer := ""
	if room_type == "boss":
		var size_key := str(data.get("boss_size", "standard"))
		prefer = str(BossDB.SIZE_TEMPLATE.get(size_key, "room_boss"))
	var template_path := self.pick_template(room_type, prefer)
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
	var jd := self.read_json_dict(template_path)
	if RoomDataClass and not jd.is_empty():
		# 门按地牢拓扑重算，覆盖模板里写死的门（消除哑门与死胡同）
		# 必须传 idx：预建时 root.current_room_index 指向别的房
		self.apply_topology_doors(jd, idx)
		var rd = RoomDataClass.new()
		rd.load_from_dict(jd)
		# 本层主题配色（FloorDefs：9 层各不相同）
		var floor_num: int = root._current_floor_num()
		var floor_col: Color = FloorDefs.color_of(floor_num, "floor")
		var wall_col: Color = FloorDefs.color_of(floor_num, "wall")
		# 本层主题配色 + 主题 id（id 决定用图集里的哪块砖）
		var theme_id: String = FloorDefs.theme_id(floor_num)
		FloorBuilder.build(containers["Floor"], jd, floor_col, Color.TRANSPARENT, theme_id)
		WallBuilder.build(containers["Walls"], jd, wall_col, theme_id)
		DoorBuilder.build(containers["Doors"], jd)
		DecorationBuilder.build(containers["Props"], jd)
		self.build_spawn_markers(containers["SpawnPoints"], jd)

		var controller := RoomController.new()
		controller.name = "RoomController"
		controller.set("room_data", jd)
		room_node.add_child(controller)

		# 本层环境机制（毒气/熔岩/爆炸/传送…）。挂在房间节点下，
		# 随房间销毁；无机制层（第 1 层）返回 null。
		FloorEnvironment.apply(room_node, floor_num, jd)

		# 破墙入口：本房若是隐藏房的锚房间，在共用的墙上放一个可交互裂缝
		self.build_hidden_wall(room_node, idx, jd)

	return room_node


## 构建破墙入口（本房是某个隐藏房的锚房间时）。
## 位置取本房边界中点那条边（与门的落格口径一致）——隐藏房与锚房共用该边。
func build_hidden_wall(room_node: Node3D, anchor_idx: int, jd: Dictionary) -> void:
	var w: float = float(jd.get("width", 20))
	var h: float = float(jd.get("height", 15))
	for i in root.dungeon_graph.size():
		var r: Dictionary = root.dungeon_graph[i]
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


## 读房间 JSON（带缓存）。
## **返回深拷贝**：调用方（_apply_topology_doors）会就地改 doors/walls，
## 直接给缓存引用会被写坏，下一次切同一间房就拿到被污染的数据。
func read_json_dict(path: String) -> Dictionary:
	if self._json_cache.has(path):
		return (self._json_cache[path] as Dictionary).duplicate(true)
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
	self._json_cache[path] = parsed
	return parsed.duplicate(true)


## 按地牢拓扑重算本房的门，写回 jd["doors"]，并让边界墙在门格留洞
## 模板里的门方位是固定的，与随机拓扑对不上就会产生哑门（走上去不切房）
##
## idx 显式传入而非读 root.current_room_index——预加载时房间是**提前**构建的，
## 那时 root.current_room_index 还指向别的房，读它会把门装到错误的房间上。
## 不传（-1）则回退到 root.current_room_index，兼容既有调用。
func apply_topology_doors(jd: Dictionary, idx: int = -1) -> void:
	if root.dungeon_graph.is_empty() or root.dungeon_connections.is_empty():
		return
	if idx < 0:
		idx = root.current_room_index
	if idx < 0 or idx >= root.dungeon_graph.size():
		return

	var start_idx: int = clampi(root.dungeon_start_index, 0, root.dungeon_graph.size() - 1)
	var parents: Array = DoorsByTopology.bfs_parents(root.dungeon_graph, root.dungeon_connections, start_idx)
	var back_idx: int = start_idx
	if idx < parents.size() and int(parents[idx]) >= 0:
		back_idx = int(parents[idx])

	var w: int = int(jd.get("width", 20))
	var h: int = int(jd.get("height", 15))
	var doors: Array = DoorsByTopology.build_doors(
		root.dungeon_graph, root.dungeon_connections, idx,
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


func pick_template(room_type: String, prefer_id: String = "") -> String:
	var templates: Array = root.room_templates.get(room_type, [])
	# 指定模板（Boss 房用）：按 id 精确匹配 data/rooms/<prefer_id>.json
	if not prefer_id.is_empty():
		var want := "res://data/rooms/%s.json" % prefer_id
		if templates.has(want):
			return want
		# 指定模板不在本房型的池里时**不回退到随机**——宁可让调用方拿到空、
		# 走 _create_fallback_room，也不要静默换成尺寸不符的模板
	if templates.is_empty():
		for key in root.room_templates:
			var arr: Array = root.room_templates[key]
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
	var h := hash("%d:%d:%s" % [root.dungeon_seed, root._building_room_index, room_type])
	return templates[abs(h) % templates.size()]


func build_spawn_markers(parent: Node3D, data) -> void:
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
			self.spawn_chest(marker.position, parent)
		# 特殊房交互物：商店 NPC / 治疗泉水 / 事件祭坛
		elif etype in ["shop_npc", "heal_shrine", "event_shrine"]:
			self.spawn_special_prop(marker.position, etype, parent)


## 在标记位置生成特殊房交互物（按实体类型决定外观）
func spawn_special_prop(pos: Vector3, entity_type: String, parent: Node3D) -> void:
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
func spawn_chest(pos: Vector3, parent: Node3D) -> void:
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
	var rtype := self.building_room_type()
	if rtype == "hidden" or rtype == "reward_hall":
		chest.set("is_hidden_reward", true)
		chest.set("gold_min", 300)
		chest.set("gold_max", 800)
	parent.add_child(chest)


## 当前正在构建的房间是否为隐藏房（_build_room 里按 idx 判断）
func current_room_is_hidden() -> bool:
	return self.building_room_type() == "hidden"


## 当前正在构建的房间类型（预建时 root.current_room_index 指向别的房，必须按 idx 查）
func building_room_type() -> String:
	var idx: int = root._building_room_index
	if idx < 0 or idx >= root.dungeon_graph.size():
		return ""
	return str(root.dungeon_graph[idx].get("type", ""))


func create_fallback_room() -> Node3D:
	var room_node := Node3D.new()
	room_node.name = "Room_Fallback"
	root.world.add_child(room_node)
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


