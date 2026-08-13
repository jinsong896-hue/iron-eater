class_name DungeonRoom
extends Node2D
## 物理房间节点：地板、2 瓦片墙（含门洞）、类型标识
## 瓦片规格：《关卡设计分册》二、房间尺寸与瓦片数量

const CELL := Vector2(1280.0, 768.0)
const WALL_PX := 128.0
const DOOR_HALF_WIDTH := 96.0

enum Side { TOP, BOTTOM, LEFT, RIGHT }

const TYPE_COLORS := {
	RoomData.RoomType.START: Color(0.30, 0.60, 0.42),
	RoomData.RoomType.NORMAL: Color(0.80, 0.82, 0.86),
	RoomData.RoomType.ELITE: Color(1.00, 0.68, 0.25),
	RoomData.RoomType.BOSS: Color(0.95, 0.32, 0.28),
	RoomData.RoomType.SHOP: Color(1.00, 0.85, 0.35),
	RoomData.RoomType.CHEST: Color(0.45, 0.62, 0.95),
	RoomData.RoomType.HEAL: Color(0.35, 0.85, 0.85),
	RoomData.RoomType.EVENT: Color(0.75, 0.48, 0.92),
	RoomData.RoomType.HIDDEN: Color(0.90, 0.55, 0.90),
}

var data: RoomData
var config: ChapterConfig
signal room_entered(room: Node2D)


func set_room_data(room_data: RoomData) -> void:
	data = room_data


func get_room_data() -> RoomData:
	return data


func initialize(room_data: RoomData, cfg: ChapterConfig, _usable_world: Rect2) -> void:
	data = room_data
	config = cfg
	_build_floor()
	_build_walls()
	_build_label()
	_build_player_detector()


func _build_player_detector() -> void:
	var detector := Area2D.new()
	detector.name = "PlayerDetector"
	detector.collision_layer = 0
	detector.collision_mask = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(data.rect.size) * CELL
	shape.shape = box
	shape.position = box.size * 0.5
	detector.add_child(shape)
	detector.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			room_entered.emit(self))
	add_child(detector)


func _build_floor() -> void:
	var world := Rect2(Vector2.ZERO, Vector2(data.rect.size) * CELL)
	var usable := world.grow(-WALL_PX)
	var floor := Polygon2D.new()
	floor.name = "Floor"
	floor.polygon = PackedVector2Array([
		usable.position, usable.position + Vector2(usable.size.x, 0),
		usable.end, usable.position + Vector2(0, usable.size.y),
	])
	floor.color = config.floor_color
	add_child(floor)
	# 特殊房间：地面描边提示
	if data.type != RoomData.RoomType.NORMAL and TYPE_COLORS.has(data.type):
		var frame := Polygon2D.new()
		frame.polygon = PackedVector2Array([
			usable.position, usable.position + Vector2(usable.size.x, 0),
			usable.end, usable.position + Vector2(0, usable.size.y),
		])
		frame.color = TYPE_COLORS[data.type] * Color(1, 1, 1, 0.18)
		add_child(frame)


func _build_walls() -> void:
	var world := Rect2(Vector2.ZERO, Vector2(data.rect.size) * CELL)
	var w := world.size.x
	var h := world.size.y
	var top_open := _openings(Side.TOP, w, h)
	var bottom_open := _openings(Side.BOTTOM, w, h)
	var left_open := _openings(Side.LEFT, w, h)
	var right_open := _openings(Side.RIGHT, w, h)

	_add_wall_segments(Rect2(0, 0, w, WALL_PX), top_open, true)
	_add_wall_segments(Rect2(0, h - WALL_PX, w, WALL_PX), bottom_open, true)
	_add_wall_segments(Rect2(0, 0, WALL_PX, h), left_open, false)
	_add_wall_segments(Rect2(w - WALL_PX, 0, WALL_PX, h), right_open, false)

	# 门洞视觉（浅色门槛）
	for op in top_open + bottom_open + left_open + right_open:
		var door := Polygon2D.new()
		door.polygon = PackedVector2Array([
			op.position, op.position + Vector2(op.size.x, 0),
			op.end, op.position + Vector2(0, op.size.y),
		])
		door.color = config.floor_color.lightened(0.35)
		add_child(door)


func _openings(side: int, w: float, h: float) -> Array:
	var list: Array = []
	for cell in data.door_cells:
		var center := Vector2.ZERO
		var matched := false
		match side:
			Side.TOP:
				if cell.y == data.rect.position.y - 1:
					center = Vector2((cell.x + 0.5) * CELL.x, 0.0)
					matched = true
			Side.BOTTOM:
				if cell.y == data.rect.end.y:
					center = Vector2((cell.x + 0.5) * CELL.x, h)
					matched = true
			Side.LEFT:
				if cell.x == data.rect.position.x - 1:
					center = Vector2(0.0, (cell.y + 0.5) * CELL.y)
					matched = true
			Side.RIGHT:
				if cell.x == data.rect.end.x:
					center = Vector2(w, (cell.y + 0.5) * CELL.y)
					matched = true
		if matched:
			if side == Side.TOP or side == Side.BOTTOM:
				list.append(Rect2(center.x - DOOR_HALF_WIDTH, 0.0, DOOR_HALF_WIDTH * 2.0, WALL_PX))
			else:
				list.append(Rect2(0.0, center.y - DOOR_HALF_WIDTH, WALL_PX, DOOR_HALF_WIDTH * 2.0))
	return list


func _add_wall_segments(span: Rect2, openings: Array, horizontal: bool) -> void:
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(a: Rect2, b: Rect2) -> bool:
		var va: float = a.position.x if horizontal else a.position.y
		var vb: float = b.position.x if horizontal else b.position.y
		return va < vb
	)
	var cursor := span.position.x if horizontal else span.position.y
	for op in cuts:
		var op_start: float = op.position.x if horizontal else op.position.y
		var op_end: float = op.end.x if horizontal else op.end.y
		if op_start > cursor:
			if horizontal:
				_add_wall_segment(Rect2(cursor, span.position.y, op_start - cursor, span.size.y))
			else:
				_add_wall_segment(Rect2(span.position.x, cursor, span.size.x, op_start - cursor))
		cursor = maxf(cursor, op_end)
	var span_end := span.end.x if horizontal else span.end.y
	if cursor < span_end:
		if horizontal:
			_add_wall_segment(Rect2(cursor, span.position.y, span_end - cursor, span.size.y))
		else:
			_add_wall_segment(Rect2(span.position.x, cursor, span.size.x, span_end - cursor))


func _add_wall_segment(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.end, rect.position + Vector2(0, rect.size.y),
	])
	poly.color = config.wall_color
	body.add_child(poly)
	add_child(body)


func _build_label() -> void:
	var label := Label.new()
	label.name = "TypeLabel"
	label.text = data.type_name()
	label.position = Vector2(WALL_PX + 16, WALL_PX + 4)
	label.add_theme_font_size_override("font_size", 28)
	label.modulate = TYPE_COLORS.get(data.type, Color.WHITE)
	add_child(label)
