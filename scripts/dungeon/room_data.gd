class_name RoomData
extends RefCounted
## 逻辑房间数据：布局矩形（格）、类型、门方向
## 对应《关卡设计分册》2.1 母网格 / 3.1 房间类型分配

enum RoomType {
	START,    # 初始房（安全区）
	NORMAL,   # 普通怪物房
	ELITE,    # 精英怪物房
	BOSS,     # Boss 房
	SHOP,     # 商店房
	CHEST,    # 宝箱房
	HEAL,     # 泉水房
	EVENT,    # 事件房
	HIDDEN,   # 隐藏房
	CORRIDOR, # 走廊（连接房间）
}

const TYPE_NAMES := {
	RoomType.START: "初始房", RoomType.NORMAL: "战斗房", RoomType.ELITE: "精英房",
	RoomType.BOSS: "Boss房", RoomType.SHOP: "商店", RoomType.CHEST: "宝箱",
	RoomType.HEAL: "泉水", RoomType.EVENT: "事件", RoomType.HIDDEN: "隐藏房",
	RoomType.CORRIDOR: "走廊",
}

var rect: Rect2i            # 布局格矩形（整数格坐标）
var type: int = RoomType.NORMAL
var doors: Array[Vector2i] = []   # 相对方向（格单位），用于逻辑连通
var door_cells: Array[Vector2i] = []  # 与走廊相接的格坐标（自动开洞）


func _init(r: Rect2i = Rect2i()) -> void:
	rect = r


func center_cell() -> Vector2i:
	return rect.get_center()


func center_world(cell_size: Vector2) -> Vector2:
	return (Vector2(center_cell()) + Vector2(0.5, 0.5)) * cell_size


func distance_cells_to(other: RoomData) -> int:
	return (center_cell() - other.center_cell()).length() as int


func type_name() -> String:
	return TYPE_NAMES.get(type, "未知")
