class_name RoomDecorator
extends RefCounted
## 房间装饰器：根据房间类型/布局在房间内随机放置火炬、宝箱、石柱等装饰对象

const TorchScene := preload("res://scenes/objects/torch.tscn")
const ChestScene := preload("res://scenes/objects/chest.tscn")

var rng := RandomNumberGenerator.new()


## 在房间 Objects 节点下生成装饰；room 为 RoomBase 子类
func decorate(room: Node2D) -> void:
	if room == null:
		return
	var objects := room.get_node_or_null("Objects") as Node2D
	if objects == null:
		return
	var w: int = room.get("room_width") if room.get("room_width") != null else 20
	var h: int = room.get("room_height") if room.get("room_height") != null else 12
	var wall := 2
	# 根据房间类型决定装饰密度
	var room_type: int = room.get("room_type") if room.get("room_type") != null else RoomBase.RoomType.NORMAL
	_place_torches(room_type, objects, w, h, wall)
	_place_chests(room_type, objects, w, h, wall)


func _place_torches(room_type: int, objects: Node2D, w: int, h: int, wall: int) -> void:
	var count := 2
	match room_type:
		RoomBase.RoomType.BOSS:
			count = 4
		RoomBase.RoomType.ELITE:
			count = 3
		RoomBase.RoomType.START:
			count = 2
		_:
			count = 2
	for i in count:
		var torch := TorchScene.instantiate() as Torch
		if torch == null:
			continue
		var margin := wall + 1
		var cell_x := margin + (i * (w - margin * 2)) / maxi(count - 1, 1)
		var cell_y := wall + 1 if i % 2 == 0 else h - wall - 2
		torch.position = Vector2((cell_x + 0.5) * 64.0, (cell_y + 0.5) * 64.0)
		objects.add_child(torch)


func _place_chests(room_type: int, objects: Node2D, w: int, h: int, wall: int) -> void:
	var chance := 0.0
	match room_type:
		RoomBase.RoomType.ELITE:
			chance = 0.5
		RoomBase.RoomType.BOSS:
			chance = 1.0
		RoomBase.RoomType.SPECIAL:
			chance = 1.0
		_:
			chance = 0.2
	if rng.randf() > chance:
		return
	var chest := ChestScene.instantiate() as DungeonChest
	if chest == null:
		return
	var cx := w / 2
	var cy := h / 2
	chest.position = Vector2((cx + 0.5) * 64.0, (cy + 0.5) * 64.0)
	objects.add_child(chest)
