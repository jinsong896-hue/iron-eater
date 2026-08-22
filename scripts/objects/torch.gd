class_name Torch
extends PointLight2D
## 火炬：周期性闪烁的点光源，可挂在房间墙壁或场景中提供氛围照明

@export var base_energy := 2.5
@export var flicker_intensity := 0.3
@export var flicker_speed := 8.0

var _time := 0.0


func _ready() -> void:
	energy = base_energy


func _process(delta: float) -> void:
	_time += delta
	var noise := sin(_time * flicker_speed) + sin(_time * flicker_speed * 2.3) * 0.3
	energy = base_energy + noise * flicker_intensity
