class_name CoverProp
extends DestroyableProp
## 掩体 —— 第 8 层「地狱王座」
##
## 策划：「全屏间歇性火焰风暴（**需躲掩体**）」。
## 风暴来袭时，站在掩体保护范围内的玩家不受伤。
##
## **不可摧毁**：掩体是"解法"而不是"资源"——如果能被打掉，
## 玩家在风暴前把掩体打没了就变成无解局面。故 `indestructible = true`。
## 受击仍有反馈（闪红），让玩家知道打不动而不是"没打到"。

## 保护半径（玩家中心距掩体中心小于它即算被遮挡）
const COVER_RADIUS := 1.8


func _init() -> void:
	prop_kind = "cover"
	indestructible = true
	max_hp = 9999.0
	hp = 9999.0


func collision_size() -> Vector3:
	return Vector3(1.2, 1.2, 1.2)


## 某点是否被本掩体保护
func covers(point: Vector3) -> bool:
	return global_position.distance_to(point) <= COVER_RADIUS


func _build_visual() -> void:
	# 破碎神像残块：厚石墩 + 斜置石板（挡在身前的感觉）
	_add_box(Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 1.2), Color(0.30, 0.24, 0.22), 0.0)
	var slab := _add_box(Vector3(0, 0.95, 0), Vector3(1.3, 0.9, 0.35),
		Color(0.38, 0.30, 0.27), 0.0)
	slab.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	# 血红色微光：与第 8 层主题一致，也提示"这是关键物件"
	_add_light(Color(1.0, 0.35, 0.30), 0.8)
