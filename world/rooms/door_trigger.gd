extends Area3D
## 门触发器 —— HD-2D 重构版
## 挂在 Door 场景的 DoorTrigger 节点上
## 锁门时生成物理阻挡，开门时移除

var direction := ""
var is_locked := false
var is_open := true

var _blocker: StaticBody3D = null
## 重入保护：一次触发只切一次房。
## 原实现每次 body_entered 都发信号，若玩家正好被放在门触发器上（或站在门上
## 来回蹭），会连续触发切房 → 房间被反复销毁重建 → 卡死。
var _triggered := false
## 短暂失效：玩家刚穿过本门进入房间，落点就在门旁；若门立刻可用会被再次
## 触发（表现：进一格却穿两房）。
## 必须「时间窗口 + 离开检测」双条件：只靠离开检测不够——落点在门外侧、
## 不与触发区重叠时，第一帧 _process 就会恢复，奔跑时一帧位移大，
## 玩家能冲过这个窗口再次踩门。
var _disarmed := false
var _disarm_timer := 0.0
## 失效最短时长（秒）。奔跑 8m/s、帧 1/60s 时单帧位移约 0.13m，
## 0.25s 内有充足帧数让玩家走离门口。
const DISARM_MIN_TIME := 0.25


func _ready() -> void:
	set_process(false)


## 让本门失效，直到「过了最短时间」且「玩家已离开触发区」
func disarm_until_clear() -> void:
	_disarmed = true
	_disarm_timer = DISARM_MIN_TIME
	_triggered = false   # 允许以后正常使用
	set_process(true)


func _process(delta: float) -> void:
	if not _disarmed:
		set_process(false)
		return
	# 条件 1：最短时间未到 → 继续失效
	if _disarm_timer > 0.0:
		_disarm_timer -= delta
		return
	# 条件 2：玩家仍在触发区内 → 继续失效
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return
	_disarmed = false
	set_process(false)


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
	if _triggered:
		return
	if _disarmed:
		return
	if is_locked or not is_open:
		return
	if body.is_in_group("player"):
		_triggered = true
		# EventBus 运行时获取（--script 测试模式下不存在）
		var tree := Engine.get_main_loop() as SceneTree
		var bus = tree.root.get_node_or_null("EventBus") if tree and tree.root else null
		if bus:
			bus.door_opened.emit(direction, direction)


## 重置触发标记（房间重新激活时用；本房门被再次使用）
func reset_trigger() -> void:
	_triggered = false
