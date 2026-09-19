extends Node
## 测试替身：模拟 GameRoot 的房间状态存储
##
## RoomController 通过 duck-typing 找带 room_state 属性的节点
## （见 RoomController._find_game_root），故测试里用这个最小替身，
## 让 _mark_special_used / _special_was_used 的落盘与读回路径可被验证。

var room_state: Dictionary = {}
var current_room_index := 0


## 预置若干房间状态槽（与 GameRoot 生成地牢时的结构一致）
func seed_rooms(count: int) -> void:
	room_state.clear()
	for i in count:
		room_state[i] = {"cleared": false, "visited": false, "shop_sold": []}
