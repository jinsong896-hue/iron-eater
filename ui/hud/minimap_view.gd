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

## 全层预览：按 M 在「±radius 迷雾窗口」与「整层拓扑」之间切换
## 全层模式下房间会自动缩小以塞进面板；未探索房间仍不显示类型（保留探索感）
var full_floor_mode := false

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


## 全层预览切换键（M）。玩家只消费自己的动作，M 会传到这里
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_M:
			full_floor_mode = not full_floor_mode
			queue_redraw()
			get_viewport().set_input_as_handled()


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
	# 全层模式下以整层包围盒中心为原点，否则当前房偏在一侧时整层会画偏出框
	var origin := center
	if full_floor_mode:
		origin = _coord_to_screen(_floor_center(), center, _cell_size_for_view())
	# 全层模式下按房间跨度自动缩放，保证整层塞得进面板
	var cell := _cell_size_for_view()
	var half := _room_half_size()

	# 1) 连接线（先画，房间盖在上面）
	for conn in connections:
		if conn.size() < 2:
			continue
		var a: Vector2i = dungeon_graph[conn[0]]["position"]
		var b: Vector2i = dungeon_graph[conn[1]]["position"]
		if not _should_draw(a) and not _should_draw(b):
			continue
		var pa := _coord_to_screen(a, origin, cell)
		var pb := _coord_to_screen(b, origin, cell)
		draw_line(pa, pb, line_color, 3.0 if not full_floor_mode else 2.0)

	# 2) 房间块
	for room in dungeon_graph:
		var pos: Vector2i = room["position"]
		if not _should_draw(pos):
			continue
		var rtype := str(room.get("type", "normal"))
		var rect := Rect2(_coord_to_screen(pos, origin, cell) - half, half * 2.0)
		draw_rect(rect, _room_color(pos, rtype))

		# 类型标记：仅已探索/当前/相邻的房间显示（未探索不泄漏情报）
		if _type_visible(pos):
			_draw_type_marker(rect, rtype)

	# 3) 当前房间玩家标记（白点）
	var cur_center := _coord_to_screen(current_position, origin, cell)
	draw_circle(cur_center, 3.5, Color.WHITE)


## 各房型的标记色（未列为默认，不画标记）
const TYPE_MARKER_COLORS := {
	"shop": Color(0.95, 0.8, 0.3),      # 商店：钱币金
	"heal": Color(0.4, 0.9, 1.0),       # 泉水：青
	"event": Color(0.8, 0.5, 0.95),     # 事件：紫
	"treasure": Color(1.0, 0.85, 0.25), # 宝箱：金
	"boss": Color(0.9, 0.25, 0.25),     # Boss：红
}

## 标注用单字（画在方块中心，一眼区分房型）
const TYPE_MARKER_GLYPHS := {
	"shop": "商",
	"heal": "泉",
	"event": "?",
	"treasure": "宝",
	"boss": "王",
}


## 画房型标记：有色的描边 + 中心单字（避免只靠颜色区分，色盲友好）
func _draw_type_marker(rect: Rect2, rtype: String) -> void:
	if not TYPE_MARKER_COLORS.has(rtype):
		return
	var col: Color = TYPE_MARKER_COLORS[rtype]
	# Boss 用较粗的双层描边强调
	draw_rect(rect, col, false, 3.0 if rtype == "boss" else 2.0)

	# 单字：仅在方块够大时画（全层缩小时会互相压字）
	if rect.size.x < 14.0:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var glyph: String = TYPE_MARKER_GLYPHS.get(rtype, "")
	if glyph.is_empty():
		return
	var fs := int(rect.size.x * 0.6)
	var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := rect.get_center() - Vector2(ts.x * 0.5, -ts.y * 0.35)
	draw_string(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 该位置是否显示房型标记（已探索 / 当前 / 相邻）
func _type_visible(pos: Vector2i) -> bool:
	return pos == current_position or explored_rooms.has(pos) or _is_adjacent_to_current(pos)


## 当前视图的格子间距（全层模式按跨度压缩）
func _cell_size_for_view() -> float:
	var base := room_size.y + room_gap
	if not full_floor_mode:
		return base
	var span := _floor_span()
	var max_cells := float(maxi(span.x, span.y))
	if max_cells <= 0.0:
		return base
	# 面板尺寸减去边距后均分，且不超过 base（小地图不需要放大）
	var usable := minf(size.x, size.y) - room_size.y - 8.0
	var fit := usable / max_cells
	return clampf(minf(fit, base), 6.0, base)


## 房间半边长（全层模式随格子收缩）
func _room_half_size() -> Vector2:
	if not full_floor_mode:
		return room_size * 0.5
	var cell := _cell_size_for_view()
	var s := clampf(cell * 0.72, 3.0, room_size.x)
	return Vector2(s, s) * 0.5


## 整层包围盒的中心坐标（全层模式的绘制原点）
func _floor_center() -> Vector2i:
	if dungeon_graph.is_empty():
		return current_position
	var minp := Vector2i(9999, 9999)
	var maxp := Vector2i(-9999, -9999)
	for room in dungeon_graph:
		var p: Vector2i = room["position"]
		minp.x = mini(minp.x, p.x)
		minp.y = mini(minp.y, p.y)
		maxp.x = maxi(maxp.x, p.x)
		maxp.y = maxi(maxp.y, p.y)
	return Vector2i((minp.x + maxp.x) / 2, (minp.y + maxp.y) / 2)


## 整层在 x / y 上的格子跨度
func _floor_span() -> Vector2i:
	if dungeon_graph.is_empty():
		return Vector2i.ONE
	var minp := Vector2i(9999, 9999)
	var maxp := Vector2i(-9999, -9999)
	for room in dungeon_graph:
		var p: Vector2i = room["position"]
		minp.x = mini(minp.x, p.x)
		minp.y = mini(minp.y, p.y)
		maxp.x = maxi(maxp.x, p.x)
		maxp.y = maxi(maxp.y, p.y)
	return Vector2i(maxp.x - minp.x + 1, maxp.y - minp.y + 1)


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


## 房间是否画（已探索/相邻/当前；全层模式下忽略半径）
func _should_draw(pos: Vector2i) -> bool:
	if pos == current_position:
		return true
	if full_floor_mode:
		# 全层：已探索 + 相邻（未探索的不画，保留探索感）
		return explored_rooms.has(pos) or _is_adjacent_to_current(pos)
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
## cell 由调用方按视图模式给定（全层模式会压缩间距）
func _coord_to_screen(pos: Vector2i, center: Vector2, cell: float) -> Vector2:
	var d: Vector2i = pos - current_position
	return center + Vector2(float(d.x) * cell, float(d.y) * cell)
