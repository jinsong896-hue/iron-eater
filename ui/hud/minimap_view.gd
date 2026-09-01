class_name MinimapView
extends Control
## 右上角小地图 —— 拓扑图绘制（依据 ai/地图相关.md 方案）
## 已探索房间亮灰 / 当前房间金色 / 相邻房间半亮蓝 / 连接线
## 固定方向：上北下南左西右东；只画当前房间周围 ±radius 格

@export var room_size: Vector2 = Vector2(22, 22)
@export var room_gap: float = 8.0

@export var explored_color := Color(0.75, 0.75, 0.75, 0.9)
@export var current_color := Color(1.0, 0.85, 0.2, 1.0)
@export var adjacent_color := Color(0.45, 0.85, 1.0, 0.75)
@export var line_color := Color(0.9, 0.9, 0.9, 0.8)
@export var bg_color := Color(0.08, 0.08, 0.12, 0.85)
@export var border_color := Color(0.3, 0.3, 0.35, 1.0)

## 绘制半径（当前房间周围格数）
@export var visible_radius := 4

# 数据（由 HUD/GameRoot 注入或自动拉取）
var dungeon_graph: Array = []        # [{id, position: Vector2i, type}]
var connections: Array = []          # [[idx_a, idx_b], ...]
var explored_rooms: Dictionary = {}  # position(Vector2i) -> true
var current_position := Vector2i.ZERO

var _game_root: Node = null


func _ready() -> void:
	# 从场景树找 GameRoot（自动接线）
	_bind_game_root()
	queue_redraw()


func _bind_game_root() -> void:
	if _game_root != null:
		return
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("game_root"):
		_game_root = node
		break
	if _game_root == null:
		# 兜底：从当前场景找
		var current := tree.current_scene
		if current and current.has_method("next_floor"):
			_game_root = current
		elif current:
			_game_root = current.get_node_or_null("MainScene")
	if _game_root:
		_refresh_from_game_root()


## 从 GameRoot 拉取地牢数据（每次房间切换/进入时调）
func _refresh_from_game_root() -> void:
	if _game_root == null:
		return
	dungeon_graph = _game_root.get("dungeon_graph")
	connections = _game_root.get("dungeon_connections")
	var room_state: Dictionary = _game_root.get("room_state")
	var cur_idx: int = _game_root.get("current_room_index")
	# 已探索 = visited 的房间坐标
	explored_rooms.clear()
	for i in range(dungeon_graph.size()):
		if room_state.has(i) and room_state[i].get("visited", false):
			explored_rooms[dungeon_graph[i]["position"]] = true
	# 当前房间坐标
	if cur_idx >= 0 and cur_idx < dungeon_graph.size():
		current_position = dungeon_graph[cur_idx]["position"]
	queue_redraw()


## 通知刷新（EventBus.room_entered 后由 HUD 调，或外部直接调）
func notify_room_changed() -> void:
	_bind_game_root()
	_refresh_from_game_root()


func _draw() -> void:
	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 1.5)

	if dungeon_graph.is_empty():
		return

	var center := size * 0.5

	# 1) 连接线（先画，房间盖在上面）
	for conn in connections:
		if conn.size() < 2:
			continue
		var a: Vector2i = dungeon_graph[conn[0]]["position"]
		var b: Vector2i = dungeon_graph[conn[1]]["position"]
		if not _should_draw(a) and not _should_draw(b):
			continue
		# 两端都可见才画（或一端在当前视野）
		if not _in_radius(a) and not _in_radius(b):
			continue
		var pa := _coord_to_screen(a, center)
		var pb := _coord_to_screen(b, center)
		draw_line(pa, pb, line_color, 3.0)

	# 2) 房间块
	for room in dungeon_graph:
		var pos: Vector2i = room["position"]
		if not _should_draw(pos):
			continue
		var rect := Rect2(_coord_to_screen(pos, center) - room_size * 0.5, room_size)
		var color := _room_color(pos, str(room.get("type", "normal")))
		draw_rect(rect, color)
		# Boss 房画红边
		if str(room.get("type", "")) == "boss":
			draw_rect(rect, Color(0.9, 0.25, 0.25, 0.95), false, 2.0)
		# 宝箱房画金点
		if str(room.get("type", "")) == "treasure":
			draw_circle(rect.get_center(), 3.0, Color(0.95, 0.8, 0.3))

	# 3) 当前房间玩家标记（白点）
	var cur_center := _coord_to_screen(current_position, center)
	draw_circle(cur_center, 3.5, Color.WHITE)


## 房间颜色：当前金 / 相邻蓝半亮 / 已探索灰 / 未探索暗
func _room_color(pos: Vector2i, _room_type: String) -> Color:
	if pos == current_position:
		return current_color
	if explored_rooms.has(pos):
		return explored_color
	if _is_adjacent_to_current(pos):
		return adjacent_color
	return Color(0.3, 0.3, 0.32, 0.6)


## 是否与当前房间相邻（曼哈顿距离 1 且有连接）
func _is_adjacent_to_current(pos: Vector2i) -> bool:
	var d := pos - current_position
	if abs(d.x) + abs(d.y) != 1:
		return false
	# 检查连接表里是否有这条边
	for conn in connections:
		if conn.size() < 2:
			continue
		var pa: Vector2i = dungeon_graph[conn[0]]["position"]
		var pb: Vector2i = dungeon_graph[conn[1]]["position"]
		if (pa == current_position and pb == pos) or (pb == current_position and pa == pos):
			return true
	return false


## 房间是否画（已探索/相邻/在半径内已见过的）
func _should_draw(pos: Vector2i) -> bool:
	if pos == current_position:
		return true
	if explored_rooms.has(pos):
		return _in_radius(pos)
	if _is_adjacent_to_current(pos):
		return true
	return false


## 是否在当前房间 visible_radius 格内
func _in_radius(pos: Vector2i) -> bool:
	var d := pos - current_position
	return abs(d.x) <= visible_radius and abs(d.y) <= visible_radius


## 逻辑坐标 → 屏幕坐标（固定方向：x 东右 / y 南下，中心=当前房间）
func _coord_to_screen(pos: Vector2i, center: Vector2) -> Vector2:
	var d: Vector2i = pos - current_position
	var cell := room_size.y + room_gap
	return center + Vector2(float(d.x) * cell, float(d.y) * cell)
