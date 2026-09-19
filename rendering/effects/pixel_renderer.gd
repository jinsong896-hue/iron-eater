extends Node3D
## 3D 像素化渲染器 —— HD-2D
##
## 颗粒感**不来自着色器**，而来自分辨率：3D 世界按 1/pixel_scale 渲染到
## SubViewport，再以最近邻放大回窗口；UI 走另一条路（main.tscn 的 CanvasLayer），
## 全程原生分辨率。这正是 `ai/hd2d.md` 第二十六节推荐的管线，
## 也是 `房间参考/着色器/` 三个 MIT 参考项目里两个的共同做法。
##
## 为什么不用全屏 pixel shader（`floor(SCREEN_UV * n)`）：它会把 UI、文字、
## 景深、辉光、粒子一起糊掉，见 `ai/hd2d.md` 第二十五节。
##
## 场景结构（挂载点在 main.tscn）：
##
##   GameRoot
##     ViewportContainer   ← 铺满窗口，最近邻放大（stretch_shrink = pixel_scale）
##       SubViewport       ← 3D 世界在这里，尺寸 = 容器尺寸 / pixel_scale
##         World / Player / Lights / WorldEnvironment
##         CameraRig
##           Camera3D
##             PixelRenderer ← 本节点，描边 quad
##     UI (CanvasLayer)    ← HUD/背包/菜单，原生分辨率，不受像素化影响
##
## 因而 `GameRoot` 的 `$World` / `$Player` / `$CameraRig` 语义不变——
## 它们仍在 GameRoot 名下，只是被挪进了 SubViewport 子树
## （GameRoot 内部改用唯一名 `%World` 等引用，见 scenes/game_root.gd）。

const SHADER_PATH := "res://rendering/shaders/pixel_post_process.gdshader"

## 低分辨率除数：2 → 半分辨率，3 → 三分之一。整数倍放大才不会出现
## 非整像素抖动；这也是参考项目用 `stretch_shrink` 而非任意缩放的原因。
@export var pixel_scale := 2:
	set(v):
		pixel_scale = maxi(1, v)
		var c := _find_container(_viewport) if _viewport != null else null
		if c != null:
			c.stretch_shrink = pixel_scale
		_sync_viewport_size()

@export var enabled := true:
	set(v):
		enabled = v
		if _quad != null:
			_quad.visible = v

@export var light_intensity := 1.25    # 重打光时的强度（use_lighting 为真时生效）
@export var line_alpha := 0.7          # 描边透明度
@export var line_highlight := 0.2      # 法线边提亮量
@export var line_shadow := 0.55        # 深度边压暗量
## 默认 false：保留场景自身的 WorldEnvironment 光照/雾/辉光，只在边上做明暗调制。
## 置 true 会按法线缓冲重新打光，画面变成参考项目那种平面着色。
@export var use_lighting := false

var _quad: MeshInstance3D
var _material: ShaderMaterial
var _viewport: SubViewport


func _ready() -> void:
	_viewport = _find_parent_viewport()
	if _viewport == null:
		push_error("PixelRenderer: 未找到所属的 SubViewport，3D 像素化未启用")
		return

	# 最近邻放大：这是像素颗粒感的来源。线性过滤会把颗粒抹平成糊图。
	# 设在整个 SubViewport 上（不是找那个 Container）——测试场景把 main.tscn
	# 嵌在中间节点下，父链形状不固定，但「最近的祖先 SubViewport」永远成立。
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

	# 放大后由窗口分辨率补回细节，故 3D 侧关掉 MSAA 与 TAA——
	# 二者都在低分辨率缓冲上做亚像素平滑，会把颗粒感抹掉（`ai/hd2d.md` 第二十七条同源理由）
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_taa = false
	# 3D 侧不吃输入；键鼠事件由 UI 层与 InputManager 处理。
	#
	# **`gui_disable_input` 必须保持 false**（实测验证，勿改回 true）：
	# 置 true 会让本视口**完全不接收转发事件**，视口内的节点收不到任何
	# `_unhandled_input`。玩家（`Player`）就在这个 SubViewport 里，而交互键 E
	# 只在 `Player._unhandled_input` 里处理——置 true 后按 E 毫无反应
	#（移动/攻击走 `Input.is_action_pressed()` 轮询，与视口无关，故只有交互键会死）。
	# 「不让 3D 视口吃掉给 UI 的输入」靠 `handle_input_locally = false` 就够了：
	# 那表示本视口不消费事件，事件会继续往上层视口传递。
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = false

	# 尺寸由 SubViewportContainer 反推（见 _sync_viewport_size），不再手写死值
	_viewport.size_changed.connect(_sync_viewport_size)

	_sync_viewport_size()

	_setup_post_process()


## 向上找到最近的那个 SubViewport——本节点所在的 3D 视口。
func _find_parent_viewport() -> SubViewport:
	var n := get_parent()
	while n != null:
		if n is SubViewport:
			return n as SubViewport
		n = n.get_parent()
	return null


func _setup_post_process() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "PostProcessQuad"

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	# **必须开**：着色器把 POSITION 直接写成 NDC 常量，模型矩阵不参与，
	# quad 的朝向与绕序无从确定；不翻转时背面剔除会把整个 quad 剔掉，
	# 表现为「开不开 enabled 画面都一样」。
	# 参考项目 3DPixelArt_Tutorial/demo.tscn 的 QuadMesh 同样设了 flip_faces。
	quad_mesh.flip_faces = true
	_quad.mesh = quad_mesh
	# 只用于屏幕空间采样，不该产生阴影（否则它会把自己投到场景里）
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := load(SHADER_PATH)
	if shader == null:
		push_error("PixelRenderer: 着色器加载失败 %s" % SHADER_PATH)
		return

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("lightIntensity", light_intensity)
	_material.set_shader_parameter("lineAlpha", line_alpha)
	_material.set_shader_parameter("lineHighlight", line_highlight)
	_material.set_shader_parameter("lineShadow", line_shadow)
	_material.set_shader_parameter("useLighting", use_lighting)

	_quad.material_override = _material
	add_child(_quad)

	# 贴着相机放，确保它排在最前（顶点着色器会忽略这个位置，仅用于排序）
	_quad.position = Vector3(0, 0, -1.0)
	_quad.visible = enabled


## 按承载视口的容器实际尺寸重算低分辨率尺寸。
##
## **不能用窗口尺寸**：3D 世界只占容器那一块，而窗口尺寸是整块屏幕；
## 按窗口算会在分屏/嵌套场景里把画面放大两次。
## 测试场景就是这种情况——它们把 main.tscn 实例化进一个占半屏的容器，
## 按窗口算会让 SubViewport 尺寸偏大，画面被压扁。
func _sync_viewport_size() -> void:
	if _viewport == null:
		return
	var c := _find_container(_viewport)
	if c == null:
		return
	var s := c.size
	if s.x < 1.0 or s.y < 1.0:
		return
	_viewport.size = Vector2i(
		maxi(1, int(s.x) / pixel_scale),
		maxi(1, int(s.y) / pixel_scale)
	)


## 找到承载该视口的 SubViewportContainer（视口自己不记录这件事，只能反查兄弟）
func _find_container(vp: SubViewport) -> SubViewportContainer:
	var parent := vp.get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child is SubViewportContainer and (child as SubViewportContainer).get_child_count() > 0 \
				and (child as SubViewportContainer).get_child(0) == vp:
			return child as SubViewportContainer
	return null


func _notification(what: int) -> void:
	# 窗口尺寸变化时容器会先动；容器的 resized 会经视口尺寸变化传导回来
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_sync_viewport_size()
