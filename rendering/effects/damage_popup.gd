class_name DamagePopup
extends Node3D
## 伤害飘字 —— HD-2D 重构版
## 在 3D 空间中显示伤害数字，面向相机

@export var text := ""
@export var color := Color.WHITE
@export var lifetime := 1.0
@export var float_speed := 2.0
@export var font_size := 32

var _elapsed := 0.0
var _label: Label3D


func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = font_size
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.outline_size = 2
	_label.outline_modulate = Color.BLACK
	add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	position.y += float_speed * delta

	# 淡出
	var alpha: float = 1.0 - (_elapsed / lifetime)
	_label.modulate.a = alpha

	if _elapsed >= lifetime:
		queue_free()


## 创建伤害飘字
static func create(parent: Node3D, world_pos: Vector3, amount: float, kind: String) -> DamagePopup:
	var popup := DamagePopup.new()
	popup.position = world_pos + Vector3(0.0, 1.5, 0.0)
	popup.text = "%.0f" % amount

	match kind:
		"crit":
			popup.color = Color(1.0, 0.3, 0.1)
			popup.font_size = 40
		"player":
			popup.color = Color(1.0, 0.2, 0.2)
		"aoe":
			popup.color = Color(0.7, 0.3, 1.0)
		"armor":  # 终结技霸体期受击（金色）
			popup.color = Color(1.0, 0.85, 0.3)
		_:
			popup.color = Color.WHITE

	parent.add_child(popup)
	return popup