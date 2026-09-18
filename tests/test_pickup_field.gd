extends Node
## 掉落物规模化优化 —— 行为回归
##
## 覆盖 `PickupField` 的三个优化点（见该类注释）：
##   ① 动画集中驱动（掉落物自身不再跑 _process）
##   ② 空间分桶查找（拾取不再全场景遍历）
##   ③ 上限淘汰（防止无限堆积拖垮帧率）
##
## **为什么要测**：这三个都是"性能优化"，但它们同时改变了行为契约
##（谁的 _process 在跑、怎么找最近的、超量时会发生什么）。
## 不测的话，任何一条失效都只会表现为"帧率慢慢变差"或"掉落物莫名消失"，
## 极难定位。
##
## 运行：godot --headless --path . res://tests/test_pickup_field.tscn

var failed := 0


func _ready() -> void:
	await get_tree().process_frame
	_test_registration()
	_test_spatial_query()
	_test_cap_eviction()
	_test_anim_driven_by_field()

	if failed == 0:
		print("ALL PICKUP FIELD TESTS PASSED")
		get_tree().quit(0)
	else:
		print("PICKUP FIELD TESTS FAILED: %d" % failed)
		get_tree().quit(1)


## 登记后应被管理器接管（进桶、有 base_y meta）
func _test_registration() -> void:
	var field := PickupField.new()
	add_child(field)
	var p := _make_pickup(Vector3(1, 0.5, 1))
	field.register(p)
	_check(field.count() == 1, "登记后计数为 1")
	_check(p.has_meta("base_y"), "登记时记录了基准高度（供动画用）")
	# 节点销毁后应自动移出（tree_exiting 回调）
	p.queue_free()
	await get_tree().process_frame
	_check(field.count() == 0, "节点销毁后自动移出管理")
	field.queue_free()


## 空间查询：只返回半径内的，且取最近的
func _test_spatial_query() -> void:
	var field := PickupField.new()
	add_child(field)
	# 三个点：近(1,0)、中(3,0)、远(20,0)
	var near := _make_pickup(Vector3(1, 0.5, 0))
	var mid := _make_pickup(Vector3(3, 0.5, 0))
	var far := _make_pickup(Vector3(20, 0.5, 0))
	field.register(near)
	field.register(mid)
	field.register(far)

	var got = field.nearest(Vector3.ZERO, 5.0)
	_check(got == near, "半径 5 内返回最近的那个")
	var got2 = field.nearest(Vector3.ZERO, 2.0)
	_check(got2 == near, "半径 2 内仍返回近的那个（mid 在 3 米外）")
	var got3 = field.nearest(Vector3.ZERO, 0.5)
	_check(got3 == null, "半径 0.5 内没有掉落物时返回 null")
	# 远处查：应该拿到 far
	var got4 = field.nearest(Vector3(19, 0.5, 0), 3.0)
	_check(got4 == far, "在远处查询能命中远处那件")
	field.queue_free()


## 上限淘汰：超过 MAX_PICKUPS 时淘汰最旧的
func _test_cap_eviction() -> void:
	var field := PickupField.new()
	add_child(field)
	var made: Array[Node3D] = []
	# 多造 5 件
	var total := PickupField.MAX_PICKUPS + 5
	for i in total:
		var p := _make_pickup(Vector3(float(i) * 0.1, 0.5, 0.0))
		field.register(p)
		made.append(p)
	_check(field.count() == PickupField.MAX_PICKUPS,
		"超出上限后计数被钳制在 %d（实际 %d）" % [PickupField.MAX_PICKUPS, field.count()])
	# 最旧的那 5 件应已被标记释放
	var freed := 0
	for i in 5:
		if not is_instance_valid(made[i]) or made[i].is_queued_for_deletion():
			freed += 1
	_check(freed == 5, "最旧的 5 件被淘汰（实际 %d）" % freed)
	# 最新的那件仍在
	var newest: Node3D = made[made.size() - 1]
	_check(is_instance_valid(newest) and not newest.is_queued_for_deletion(),
		"最新的掉落物保留")
	field.queue_free()


## 动画由 PickupField 驱动：掉落物自身不该有 _process
func _test_anim_driven_by_field() -> void:
	var field := PickupField.new()
	add_child(field)
	var p := _make_pickup(Vector3(0, 0.5, 0))
	field.register(p)
	# 掉落物脚本不该定义 _process——动画集中在管理器里
	var scr: GDScript = p.get_script()
	var has_process := false
	for m in scr.get_script_method_list():
		if str(m.get("name", "")) == "_process":
			has_process = true
	_check(not has_process,
		"掉落物脚本不含 _process（动画由 PickupField 集中驱动）")
	# 管理器推进一帧后，掉落物的姿态应被改写
	var before_y: float = p.position.y
	var before_rot: float = p.rotation.y
	field._process(0.5)
	_check(p.rotation.y != before_rot or p.position.y != before_y,
		"PickupField._process 驱动了掉落物姿态")
	field.queue_free()


## 造一个掉落物节点（与 LootSystem 生成的结构一致）
func _make_pickup(pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	p.add_to_group("pickups")
	p.set_script(load("res://gameplay/loot/pickup_item.gd"))
	add_child(p)
	return p


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  [OK] %s" % name)
	else:
		failed += 1
		print("  [FAIL] %s" % name)
