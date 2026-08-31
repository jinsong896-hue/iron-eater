extends Area3D
## 门触发器 —— HD-2D 重构版
## 挂在 Door 场景的 DoorTrigger 节点上
## 锁门时生成物理阻挡，开门时移除

var direction := ""
var is_locked := false
var is_open := true

var _blocker: StaticBody3D = null


## 锁门：禁用触发 + 生成物理阻挡
func lock() -> void:
	is_locked = true
	is_open = false
	if _blocker == null:
		_blocker = StaticBody3D.new()
		_blocker.name = "DoorBlocker"
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0, 3.0, 0.6)
		col.shape = shape
		_blocker.add_child(col)
		get_parent().add_child(_blocker)


## 开门：恢复触发 + 移除物理阻挡
func unlock() -> void:
	is_locked = false
	is_open = true
	if _blocker != null:
		_blocker.queue_free()
		_blocker = null


func _on_body_entered(body: Node3D) -> void:
	if is_locked or not is_open:
		return
	if body.is_in_group("player"):
		# EventBus 运行时获取（--script 测试模式下不存在）
		var tree := Engine.get_main_loop() as SceneTree
		var bus = tree.root.get_node_or_null("EventBus") if tree and tree.root else null
		if bus:
			bus.door_opened.emit(direction, direction)
