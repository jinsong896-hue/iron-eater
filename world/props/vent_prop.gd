class_name VentProp
extends DestroyableProp
## 通风口 —— 第 3 层「古老墓穴」
##
## 策划：「毒气区域（持续掉血，**可破坏通风口消除**）」。
## 每个毒气区旁生成一个通风口，打掉它即清除对应毒气区。
##
## `zone_index` 把通风口与它负责的毒气区绑起来——FloorEnvironment
## 在 `destroyed` 信号里据此清掉那一个区域。

## 负责的毒气区在场地里的下标
var zone_index := -1


func _init() -> void:
	prop_kind = "vent"
	max_hp = 60.0
	hp = 60.0


func collision_size() -> Vector3:
	return Vector3(0.8, 1.6, 0.8)


func _build_visual() -> void:
	# 铁栅栏状出风口：底座 + 竖条 + 顶部暗绿毒气提示
	_add_box(Vector3(0, 0.15, 0), Vector3(0.9, 0.3, 0.9), Color(0.35, 0.33, 0.30), 0.0)
	for i in 3:
		var x := (float(i) - 1.0) * 0.22
		_add_box(Vector3(x, 0.85, 0), Vector3(0.10, 1.0, 0.10),
			Color(0.45, 0.42, 0.38), 0.0)
	_add_box(Vector3(0, 1.4, 0), Vector3(0.75, 0.12, 0.75),
		Color(0.30, 0.28, 0.26), 0.0)
	# 冒出的毒气：暗绿微光球（提示"这里在放毒"）
	_add_sphere(Vector3(0, 1.75, 0), 0.22, Color(0.35, 0.75, 0.30), 0.8)
	_add_light(Color(0.40, 0.85, 0.35), 1.0)
