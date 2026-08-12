class_name RoomBaseCarve
extends RefCounted
## 门洞开凿辅助：按 {side, center}（瓦片坐标）在墙上开 3 格宽通道

const TILE_SOURCE_ID := 0


static func carve_opening(room, opening: Dictionary) -> void:
	var side: String = opening.get("side", "north")
	var center: float = opening.get("center", 0.0)
	var half := 1
	match side:
		"north":
			for x in range(int(round(center)) - half, int(round(center)) + half + 1):
				for y in range(room.wall_thickness):
					room.erase_cell(room.walls, Vector2i(x, y))
		"south":
			for x in range(int(round(center)) - half, int(round(center)) + half + 1):
				for y in range(room.room_height - room.wall_thickness, room.room_height):
					room.erase_cell(room.walls, Vector2i(x, y))
		"west":
			for y in range(int(round(center)) - half, int(round(center)) + half + 1):
				for x in range(room.wall_thickness):
					room.erase_cell(room.walls, Vector2i(x, y))
		"east":
			for y in range(int(round(center)) - half, int(round(center)) + half + 1):
				for x in range(room.room_width - room.wall_thickness, room.room_width):
					room.erase_cell(room.walls, Vector2i(x, y))
