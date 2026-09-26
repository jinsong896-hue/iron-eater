class_name ModelPreview
extends SubViewportContainer
## 3D 模型预览组件 —— 编辑器面板与游戏内界面共用
##
## ## 为什么抽成组件
##
## 两个界面（`addons/iron_studio/panels/art_browser_dock.gd` 与
## `ui/art/art_browser.gd`）都要「加载一个模型、转着看」。
## 各写一份必然分叉——调好一边的视距/光照，另一边还是老样子。
##
## ## 用法
##
## ```gdscript
## var preview := ModelPreview.new()
## add_child(preview)
## preview.show_model("res://assets/castle-kit/Models/GLB format/wall.glb")
## ```
##
## ## 关键实现点
##
## **1. `SubViewport` 必须自己持有 `World3D`**（`own_world_3d = true`）。
## 否则预览的模型会渲染进主场景的世界，在编辑器里表现为
## 「模型出现在关卡里」；在游戏内则更糟——预览的模型会被游戏逻辑看到。
##
## **2. 相机按模型 AABB 自动取景**。castle-kit 的模型尺寸不一
##（`flag-pennant` 高 0.87、`wall` 高 1.31），写死视距会让小的看不清、
## 大的出画。故每次换模型都按包围盒重新摆相机。
##
## **3. 光照用两盏**：一盏方向光（主光，给立体感）+ 环境光。
## 单盏方向光会让背光面全黑，看不出模型形状。

## 预览用的背景色（深灰，让浅色模型也能看清轮廓）
const BG_COLOR := Color(0.13, 0.14, 0.16)

## 相机初始俯角（度）。略微俯视比平视更能看清立体形状。
const CAMERA_PITCH_DEG := 20.0

## 相机与模型的距离系数（相对包围盒半径）
const CAMERA_DIST_FACTOR := 2.6

## 滚轮缩放范围
const ZOOM_MIN := 0.4
const ZOOM_MAX := 3.0

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _pivot: Node3D = null          ## 模型挂在这个节点下，便于整体旋转
var _current_model: Node3D = null

var _yaw := 0.0                    ## 水平旋转（鼠标左右拖）
var _pitch := 0.0                  ## 垂直旋转（鼠标上下拖）
var _zoom := 1.0                   ## 缩放系数
var _dragging := false
var _base_dist := 3.0              ## 按包围盒算出的基准视距


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(240, 240)
	# 预览不该拦截游戏输入（游戏内界面打开时除外，见 set_process_input）
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	# **必须独立世界**：否则模型渲染进主场景，编辑器里会污染关卡
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.size = Vector2i(480, 480)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# 环境：给一点环境光，避免背光面全黑
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 0.55
	env.environment = e
	_viewport.add_child(env)

	# 主光：方向光，斜上方打
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 1.1
	_viewport.add_child(light)

	# 补光：从相反方向补一盏，让暗面有细节
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.45
	_viewport.add_child(fill)

	# 旋转枢轴：模型挂这里，相机绕它转
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_viewport.add_child(_pivot)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_viewport.add_child(_camera)

	_update_camera()


## 显示一个模型（传空串 = 清空预览）
##
## **用 `load()` 的结果判成败**——项目已知陷阱：`.import` 损坏的资源
## `ResourceLoader.exists()` 返回 true 但 `load()` 返回 null。
func show_model(path: String) -> bool:
	_clear_model()
	if path.is_empty():
		return false
	var ps = load(path)
	if not (ps is PackedScene):
		return false
	var inst = (ps as PackedScene).instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	_current_model = inst as Node3D
	_pivot.add_child(_current_model)
	_frame_camera()
	return true


## 清空预览
func clear() -> void:
	_clear_model()
	_update_camera()


func _clear_model() -> void:
	if _current_model != null and is_instance_valid(_current_model):
		_current_model.queue_free()
	_current_model = null


## 按模型包围盒自动取景
##
## 换模型后必须重算——castle-kit 的模型高矮差 1.5 倍以上，
## 固定视距会让小模型看不清、大模型出画。
func _frame_camera() -> void:
	if _current_model == null:
		_base_dist = 3.0
		_update_camera()
		return
	var aabb := _model_aabb(_current_model)
	var radius: float = maxf(aabb.size.length() * 0.5, 0.3)
	_base_dist = radius * CAMERA_DIST_FACTOR
	# 把模型移到包围盒中心在原点——否则偏心的模型会转出画面
	_pivot.position = -aabb.get_center()
	_zoom = 1.0
	_yaw = 0.0
	_pitch = deg_to_rad(CAMERA_PITCH_DEG)
	_update_camera()


## 算模型的世界空间包围盒（递归合并所有 MeshInstance3D）
func _model_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			# 用全局变换把局部 AABB 转到世界空间
			var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				out = bb
				first = false
			else:
				out = out.merge(bb)
		for c in cur.get_children():
			stack.append(c)
	if first:
		out = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return out


func _update_camera() -> void:
	if _camera == null:
		return
	# **未入树时不能调 `look_at`**——它会报
	# 「Node not inside tree. Use look_at_from_position() instead.」
	# 并让调用方（界面构建）中断。
	#
	# `_init` 里 `_build()` 会走到这里，而那时节点还没入树。
	# 入树后 `_ready` 会再调一次，届时才真正定位。
	if not is_inside_tree():
		return
	var dist := _base_dist * _zoom
	var dir := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	)
	_camera.position = dir * dist
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _ready() -> void:
	# 入树后补一次相机定位（`_init` 里那次被跳过了）
	_update_camera()


# ============================================================
# 交互：拖拽旋转 / 滚轮缩放
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		# 俯仰夹在 ±80°，避免翻过头导致相机倒转
		_pitch = clampf(_pitch + mm.relative.y * 0.01,
			deg_to_rad(-80.0), deg_to_rad(80.0))
		_update_camera()
		accept_event()


## 复位视角（界面的「重置」按钮用）
func reset_view() -> void:
	_yaw = 0.0
	_pitch = deg_to_rad(CAMERA_PITCH_DEG)
	_zoom = 1.0
	_update_camera()
