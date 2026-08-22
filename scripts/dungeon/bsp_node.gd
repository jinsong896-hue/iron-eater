class_name BSPNode
extends RefCounted
## BSP（二叉空间分割）节点：《关卡设计分册》2.3/2.4

var rect: Rect2i
var left: BSPNode
var right: BSPNode
var room: Rect2i = Rect2i()


func _init(area: Rect2i) -> void:
	rect = area


func is_leaf() -> bool:
	return left == null and right == null


## 按较长边切割；min_size 为叶子最小尺寸。rng 由生成器传入，保证种子可复现
func split(min_size: int, rng: RandomNumberGenerator) -> bool:
	if not is_leaf():
		return false
	var split_horizontal := false
	if rect.size.x > rect.size.y:
		split_horizontal = false
	elif rect.size.y > rect.size.x:
		split_horizontal = true
	else:
		split_horizontal = rng.randf() > 0.5

	if split_horizontal:
		var max_split := rect.size.y - min_size
		if max_split <= min_size:
			return false
		var y := rng.randi_range(min_size, max_split)
		left = BSPNode.new(Rect2i(rect.position, Vector2i(rect.size.x, y)))
		right = BSPNode.new(Rect2i(rect.position + Vector2i(0, y), Vector2i(rect.size.x, rect.size.y - y)))
	else:
		var max_split := rect.size.x - min_size
		if max_split <= min_size:
			return false
		var x := rng.randi_range(min_size, max_split)
		left = BSPNode.new(Rect2i(rect.position, Vector2i(x, rect.size.y)))
		right = BSPNode.new(Rect2i(rect.position + Vector2i(x, 0), Vector2i(rect.size.x - x, rect.size.y)))
	return true
