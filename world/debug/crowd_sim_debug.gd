extends Node3D
## CrowdSim 调试场景 —— 海量单位渲染与模拟验证
##
## **这个场景是实机验证用的，不进游戏链路**。它验证两件事：
##   ① 模拟核在真实帧循环里的耗时（headless 已测 0.52ms@2000，这里复核）
##   ② MultiMesh 直写渲染是否正常（headless 测不了，必须开窗口看）
##
## 用法：F5 运行本场景 → WASD 移动方块 → 看左上角 FPS 与单位数。
## 滑条可实时改生成数量（验证 500 / 1000 / 2000 各档表现）。
##
## 渲染路径与正式接入一致：`get_render_buffer()` 拿 12 float/实例的
## 变换矩阵，直接喂 `multimesh_set_buffer`——**不建节点、不逐个 set_transform**，
## 这是万级单位能跑起来的唯一原因。

## 单位上限（与 C++ 侧 CAP 一致）
const CAP := 2048
## 单个单位的视觉尺寸（米）
const UNIT_SIZE := 0.7
## 玩家方块的移动速度
const MOVE_SPEED := 12.0

@onready var mmi: MultiMeshInstance3D = $Swarm
@onready var info: Label = $UI/Panel/VBox/Info
@onready var slider: HSlider = $UI/Panel/VBox/CountSlider
@onready var count_label: Label = $UI/Panel/VBox/CountLabel

## CrowdSim 实例。
## **代码里创建而不是放进 .tscn**：场景文件里写 `type="CrowdSim"` 要求
## 解析 .tscn 时扩展类已注册，而编辑器导入阶段未必满足（实测会退化成
## 普通 Node，于是所有 call() 都报 "Nonexistent function"）。
## 运行时用 ClassDB.instantiate 最稳，也不依赖编辑器缓存。
var crowd: Node = null

var _player := Vector3(0.0, 0.0, 0.0)
var _spawned := 0
var _fps_accum := 0.0
var _fps_frames := 0
var _fps := 0.0
var _step_ms := 0.0


func _ready() -> void:
	if not ClassDB.class_exists("CrowdSim"):
		info.text = "CrowdSim 扩展未加载——请先编译：\n" \
			+ "cd extensions/crowd_sim\n" \
			+ "python -m SCons platform=windows target=template_debug arch=x86_64"
		return

	_setup_multimesh()
	_setup_room()
	crowd = ClassDB.instantiate("CrowdSim")
	crowd.name = "CrowdSim"
	add_child(crowd)
	crowd.call("setup", CAP, 2.0)
	crowd.call("set_obstacles", _room_walls())

	slider.min_value = 100
	slider.max_value = CAP
	slider.step = 100
	slider.value = 1000
	slider.value_changed.connect(_on_count_changed)
	_respawn(int(slider.value))


## 配置 MultiMesh：固定实例数 = 容量，未存活的实例靠"缩放写 0"隐藏。
##
## **不按存活数动态改 instance_count**：改一次会重建 GPU 侧缓冲，
## 反而比"多画几个零尺寸实例"慢。C++ 侧 get_render_buffer 已把
## 未存活实例的缩放写成 0，GPU 会直接剔除。
func _setup_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = CAP

	var quad := QuadMesh.new()
	quad.size = Vector2(UNIT_SIZE, UNIT_SIZE)
	mm.mesh = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.85, 0.25, 0.25)
	# 双面可见：俯视角下从背面看也要能看见
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat

	mmi.multimesh = mm


## 房间地面与边界（视觉参考，也用来对照障碍碰撞）
func _setup_room() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.16, 0.18)
	ground.material_override = gm
	add_child(ground)

	# 一堵竖墙：验证"单位撞墙不穿透"的视觉效果
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 2.0, 24.0)
	wall.mesh = box
	wall.position = Vector3(8.0, 1.0, 0.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.42, 0.38)
	wall.material_override = wm
	add_child(wall)

	# 玩家方块（跟随目标）
	var pv := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(1.0, 1.0, 1.0)
	pv.mesh = pb
	pv.position = Vector3(0.0, 0.5, 0.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.7, 1.0)
	pv.material_override = pm
	add_child(pv)
	pv.name = "PlayerMarker"

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 34.0, 22.0)
	cam.rotation_degrees = Vector3(-57.0, 0.0, 0.0)
	cam.fov = 60.0
	add_child(cam)


## 障碍盒（与上面那堵墙一致）：min_x, min_z, max_x, max_z
func _room_walls() -> PackedFloat32Array:
	return PackedFloat32Array([7.75, -12.0, 8.25, 12.0])


## 重新生成 N 个单位
##
## **只生成在墙的近侧**（x < 7.0）：墙是 x=7.75~8.25，若把生成范围铺到
## x>8.25，那些单位是"刷在墙右边"而不是"穿过墙"，视觉上会误判成穿墙。
## 现在的布局是"一群怪从左侧涌向右侧的玩家，必须绕过或挤在墙前"。
func _respawn(n: int) -> void:
	# 清空：把已生成的都 despawn
	for id in _spawned:
		crowd.call("despawn", id)
	_spawned = 0
	n = clampi(n, 1, CAP)
	# 铺在墙近侧：x ∈ [-24, 7.0]，z ∈ [-16, 16]
	var cols := 28
	var col_step := 31.0 / float(cols)
	var rows_max := int(ceil(float(n) / float(cols)))
	var row_step := 32.0 / float(maxi(rows_max, 1))
	for i in n:
		var cx := i % cols
		var cz := i / cols
		var x := -24.0 + float(cx) * col_step
		var z := -16.0 + float(cz) * row_step
		var id := int(crowd.call("spawn", x, z, 100.0, 3.5, 0.35, 1.0))
		if id < 0:
			break
		_spawned += 1
	count_label.text = "生成 %d 个（滑条调整）" % _spawned


func _on_count_changed(v: float) -> void:
	_respawn(int(v))


func _physics_process(delta: float) -> void:
	if not ClassDB.class_exists("CrowdSim"):
		return
	_move_player(delta)
	var t0 := Time.get_ticks_usec()
	crowd.call("step", delta, _player.x, _player.z)
	_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _process(delta: float) -> void:
	if not ClassDB.class_exists("CrowdSim"):
		return
	# **渲染读的是 step 刚完成的那份缓冲**（C++ 侧 step 末尾已 swap）。
	# 直接整块上传，不逐个 set_instance_transform。
	var buf: PackedFloat32Array = crowd.call("get_render_buffer")
	mmi.multimesh.set_buffer(buf)
	mmi.position = Vector3.ZERO

	var marker := get_node_or_null("PlayerMarker") as Node3D
	if marker != null:
		marker.position = Vector3(_player.x, 0.5, _player.z)

	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 0.5:
		_fps = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
	info.text = "FPS %.0f   单位 %d   模拟 %.2f ms   渲染 %.0f 个实例" % [
		_fps, int(crowd.call("get_active_count")), _step_ms, CAP]


func _move_player(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if dir.length_squared() > 0.0:
		_player += dir.normalized() * MOVE_SPEED * delta
		_player.x = clampf(_player.x, -22.0, 22.0)
		_player.z = clampf(_player.z, -18.0, 18.0)
