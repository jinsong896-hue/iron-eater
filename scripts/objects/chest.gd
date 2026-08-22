class_name DungeonChest
extends StaticBody2D
## 宝箱：玩家靠近并按交互键（或自动触发）后打开，随机掉落装备或金币

signal opened(chest: DungeonChest)

enum State { CLOSED, OPENED }

@export var loot_gold_min := 10
@export var loot_gold_max := 50

var state: State = State.CLOSED
var _interactable := true


func _ready() -> void:
	add_to_group("interactable")


## 与宝箱交互：仅在关闭状态下可打开一次
func interact(_who: Node = null) -> void:
	if state == State.OPENED:
		return
	state = State.OPENED
	_open()


## 返回宝箱是否已被打开（用于外部查询）
func is_opened() -> bool:
	return state == State.OPENED


func _open() -> void:
	# 视觉占位：切换 modulate 颜色模拟打开
	modulate = Color(1.0, 0.9, 0.6)
	var gold := randi_range(loot_gold_min, loot_gold_max)
	var gs := get_node_or_null("/root/GameState")
	if gs:
		if gs.has_method("give_gold"):
			gs.call("give_gold", gold)
		if gs.has_method("drop_item"):
			gs.call("drop_item", global_position)
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_method("emit_signal"):
		bus.call("emit_signal", "message", "发现宝箱：获得 %d 金币与一件装备" % gold)
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play"):
		audio.call("play", "pickup")
	opened.emit(self)
