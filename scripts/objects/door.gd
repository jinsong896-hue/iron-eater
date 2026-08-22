class_name DoorInteract
extends StaticBody2D
## 可交互门：继承 demo 中“远古之门”的概念，提供 open/close 与一次性开启功能

signal opened(door: DoorInteract)

enum State { CLOSED, OPENED }

@export var one_shot := true
@export var auto_open := false

var state: State = State.CLOSED


func _ready() -> void:
	add_to_group("interactable")


## 与门交互：打开（一次性门打开后不可再关闭）
func interact(_who: Node = null) -> void:
	if state == State.OPENED:
		return
	state = State.OPENED
	_open()


## 直接打开门，供触发器/代码调用
func open() -> void:
	if state == State.OPENED:
		return
	state = State.OPENED
	_open()


func _open() -> void:
	modulate = Color(0.7, 0.7, 0.7, 0.5)
	AudioManager.play("door_open")
	opened.emit(self)
