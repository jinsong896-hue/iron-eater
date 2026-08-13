class_name MinimapView
extends Control
## 右上角预览小地图：《地图相关.md》——固定方向、当前房间高亮、相连房间显示、已探索房间保留

var dungeon: DungeonGenerator

const ROOM_BASE_SIZE := Vector2(22.0, 22.0)
const ROOM_GAP := 8.0
const LINE_COLOR := Color(0.85, 0.85, 0.85, 0.85)
const CURRENT_COLOR := Color(1.0, 0.82, 0.25)
const EXPLORED_COLOR := Color(0.72, 0.72, 0.72, 0.9)
const CONNECTED_COLOR := Color(0.4, 0.75, 0.95, 0.9)
const DARK_COLOR := Color(0.2, 0.2, 0.22, 0.85)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dungeon = get_tree().get_first_node_in_group("dungeon_manager").get_node("DungeonGenerator") as DungeonGenerator
	if dungeon:
		dungeon.minimap_updated.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if dungeon == null:
		return
	var current := dungeon.current_room_coord
	var all_coords: Array = []
	for r in dungeon.rooms:
		all_coords.append(r.room_coord)
	if all_coords.is_empty():
		return
	var draw_coords: Array = []
	for coord in all_coords:
		if _should_draw(coord, current):
			draw_coords.append(coord)
	if draw_coords.is_empty():
		draw_coords.append(current)
	var scale := _auto_scale(draw_coords)
	var center := size * 0.5
	# 先画连接线
	for coord in draw_coords:
		var pos := _minimap_pos(coord, current, center, scale)
		for neighbor in dungeon.room_connections.get(coord, []):
			if not draw_coords.has(neighbor):
				continue
			var npos := _minimap_pos(neighbor, current, center, scale)
			draw_line(pos, npos, LINE_COLOR, 4.0)
	# 再画房间
	for coord in draw_coords:
		var data: RoomData = dungeon.get_room_data(coord)
		if data == null:
			continue
		var pos := _minimap_pos(coord, current, center, scale)
		var rect_size := ROOM_BASE_SIZE * Vector2(data.rect.size) * 0.6
		rect_size = rect_size.clamp(Vector2(16, 16), Vector2(44, 44))
		var rect := Rect2(pos - rect_size * 0.5, rect_size)
		var color := _room_color(coord, current)
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0.08, 0.08, 0.08, 0.9), false, 2.0)
		if coord == current:
			draw_rect(rect.grow(2.0), Color(1.0, 1.0, 1.0, 0.9), false, 1.0)


func _should_draw(coord: Vector2i, current: Vector2i) -> bool:
	if dungeon.is_room_explored(coord):
		return true
	if dungeon.room_connections.get(current, []).has(coord):
		return true
	return false


func _room_color(coord: Vector2i, current: Vector2i) -> Color:
	if coord == current:
		return CURRENT_COLOR
	if dungeon.is_room_explored(coord):
		return EXPLORED_COLOR
	return CONNECTED_COLOR


func _minimap_pos(coord: Vector2i, current: Vector2i, center: Vector2, scale: float) -> Vector2:
	var delta := Vector2(coord - current)
	return center + delta * (ROOM_BASE_SIZE.x + ROOM_GAP) * scale


func _auto_scale(coords: Array) -> float:
	var min_c := Vector2i(1 << 30, 1 << 30)
	var max_c := Vector2i(-(1 << 30), -(1 << 30))
	for coord in coords:
		var c: Vector2i = coord
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var span := Vector2(max_c - min_c)
	var step := ROOM_BASE_SIZE.x + ROOM_GAP
	var needed := Vector2(span.x * step + ROOM_BASE_SIZE.x, span.y * step + ROOM_BASE_SIZE.y)
	var avail := size - Vector2(20, 20)
	var scale_x := 1.0
	var scale_y := 1.0
	if needed.x > avail.x and needed.x > 0:
		scale_x = avail.x / needed.x
	if needed.y > avail.y and needed.y > 0:
		scale_y = avail.y / needed.y
	return minf(scale_x, scale_y)
