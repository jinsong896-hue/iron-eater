class_name MassTextRenderer
extends CanvasLayer
## 海量文本渲染器 —— 每字形一个实例，单 draw call
##
## ## 目标
## 同时渲染**几千个文本**（伤害数字、状态提示、拾取信息…），
## 且 CPU 每帧开销接近零。
##
## ## 为什么不用 Label
## Label 每个是独立 Control 节点：几千个 Label = 几千次节点布局 + 几次
## 独立的 draw call。数量一上来必然掉帧。
##
## ## 为什么不用旧的 TextAtlas 方案
## 旧方案（rendering/shaders/TextAtlas.gdshader）为了支持任意长度字符串，
## 用了 string_tex + cum_tex + 片元内二分查找 + advance 测量 —— 四层间接，
## 任何一环错都不出字，而且 headless 读不到像素无法定位。
## 它的历史正是"逐环节静态检查全部正确，实机就是不出字"。
##
## ## 本方案：把复杂度从 GPU 挪到 CPU
##   · **每个字形 = 一个实例**（不是一个字符串一个实例）
##   · 图集格号 / 出生时间 / 横向偏移 / 字号缩放，全部 CPU 预计算好
##     塞进 INSTANCE_CUSTOM
##   · 着色器只做：按 AGE 上浮、按 UV 采样、按 AGE 淡出
##
## 代价是实例数 = 文本数 × 平均字数（2000 条 × 4 字 ≈ 8000 实例），
## 但 MultiMesh 单 draw call 扛得住，且**实例之间无依赖**——
## 不会出现"某处索引算错导致整片不出字"。
##
## ## 关键：CPU 每帧零写入
## 生成时写一次实例数据，之后**每帧不碰任何实例**：
## 上浮与淡出完全由着色器按 TIME - spawn_time 计算。
## 过期实例由着色器 discard，槽位靠环形缓冲复用，无需 CPU 回收。
## 这才是"几千个文本"能跑起来的原因。

## 实例总容量。按"2000 条文本 × 平均 4 字"估算，留一倍余量。
const CAPACITY := 16384

## 图集参数
const ATLAS_CELL := 64          ## 单格边长（像素）
const ATLAS_COLS := 16          ## 列数
const ATLAS_ROWS := 16          ## 行数
const BAKE_FONT_SIZE := 48      ## 烘焙字号（所有字号由它缩放得到）

## 文本存活时长（秒）
const LIFETIME := 1.0
## 上浮速度（像素/秒）
const RISE_SPEED := 60.0

## 需要烘焙的字符集 —— 覆盖伤害数字/缩写/状态提示的全部字形
const GLYPH_SET := "0123456789KMB.!+-%x/×·：: "

## 飘字颜色（按 kind）
const KIND_COLORS := {
	"normal": Color(1.0, 1.0, 1.0, 1.0),
	"crit": Color(1.0, 0.35, 0.1, 1.0),
	"player": Color(1.0, 0.25, 0.25, 1.0),
	"aoe": Color(0.75, 0.35, 1.0, 1.0),
	"heal": Color(0.35, 1.0, 0.45, 1.0),
	"armor": Color(1.0, 0.85, 0.3, 1.0),
	"true": Color(1.0, 0.5, 0.9, 1.0),
}

## 各 kind 的字号（像素，屏幕空间）
const KIND_SIZES := {
	"normal": 32, "crit": 40, "player": 32, "aoe": 32,
	"heal": 32, "armor": 28, "true": 30,
}

var _mm: MultiMesh = null
var _mmi: MultiMeshInstance2D = null
var _atlas_tex: ImageTexture = null
var _glyph_cell := {}      # 字符 → 图集格号
var _glyph_adv := {}       # 字符 → 横向步进（格分数）
var _ready_done := false

## 环形槽位分配器
var _next_slot := 0
## 累计生成次数（测试用）
var _spawn_count := 0
## 累计写入的实例数（测试用）。
## **不能用 get_instance_custom_data 读回**：headless 的 dummy 渲染器下
## MultiMesh 实例数据读回不可信（实测写入了却读回全 0）。
var _instances_written := 0
## 当前活跃文本数（估算，测试用）
var _live := 0

var _camera: Camera3D = null
## 着色器材质（每帧要写 now_time）
var _mat: ShaderMaterial = null


func _ready() -> void:
	layer = 10
	add_to_group("damage_renderer")
	add_to_group("mass_text")
	_camera = _find_camera()
	_setup_multimesh()
	# 烘焙是异步的（要等 SubViewport 渲染）
	await _bake_atlas()
	_ready_done = true
	# 订阅伤害事件（与旧 Label 渲染器同一接口，便于切换）
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("damage_popup"):
		bus.damage_popup.connect(_on_damage_popup)


## 每帧把当前时间写进着色器。
##
## **不能用着色器内置的 `TIME`**：它与 GDScript 的 Time.get_ticks_msec()
## 不是同一个时钟（实测同时刻相差数秒），混用会让 age 变负数、
## 片元全部 discard —— 正是"数据全对却不出字"的成因。
## 每帧写一个 uniform（不是每实例）成本可忽略。
func _process(_delta: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("now_time", Time.get_ticks_msec() / 1000.0)


## 配置 MultiMesh：固定容量，实例数据只在生成时写
func _setup_multimesh() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.use_colors = true     # 每实例 tint（飘字颜色）
	_mm.instance_count = CAPACITY
	var q := QuadMesh.new()
	q.size = Vector2(ATLAS_CELL, ATLAS_CELL)
	_mm.mesh = q
	# 初始全部缩放置 0 → 不显示（着色器会 discard 未初始化的实例）
	for i in CAPACITY:
		_mm.set_instance_custom_data(i, Color(-1, 0, 0, 0))

	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "MassText"
	_mmi.multimesh = _mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://rendering/shaders/mass_text.gdshader")
	mat.set_shader_parameter("atlas_grid", Vector2(ATLAS_COLS, ATLAS_ROWS))
	mat.set_shader_parameter("lifetime", LIFETIME)
	mat.set_shader_parameter("rise_speed", RISE_SPEED)
	mat.set_shader_parameter("fade_start", 0.65)
	_mmi.material = mat
	_mat = mat
	add_child(_mmi)


## 烘焙字形图集：**一次性把所有字形排进同一个 SubViewport**，
## 然后整块 blit —— 而不是逐字形渲染 N 次（旧实现每个字形等 2 帧）。
func _bake_atlas() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(ATLAS_CELL * ATLAS_COLS, ATLAS_CELL * ATLAS_ROWS)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var font := ThemeDB.fallback_font
	var idx := 0
	for i in GLYPH_SET.length():
		var ch := GLYPH_SET.substr(i, 1)
		if _glyph_cell.has(ch):
			continue
		var col := idx % ATLAS_COLS
		var row := idx / ATLAS_COLS
		if row >= ATLAS_ROWS:
			break
		_glyph_cell[ch] = idx
		var lb := Label.new()
		lb.text = ch
		lb.add_theme_font_override("font", font)
		lb.add_theme_font_size_override("font_size", BAKE_FONT_SIZE)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.size = Vector2(ATLAS_CELL, ATLAS_CELL)
		lb.position = Vector2(col * ATLAS_CELL, row * ATLAS_CELL)
		vp.add_child(lb)
		idx += 1

	await get_tree().process_frame
	await get_tree().process_frame
	var img := vp.get_texture().get_image() if vp.get_texture() != null else null
	if img == null:
		# **无 GPU 环境（headless / dummy 渲染器）拿不到 SubViewport 纹理**。
		# 此处必须早退而不是继续——否则 create_from_image(null) 与
		# get_pixel 会连锁报错，把整个场景拖挂。
		# 所有字形退回等宽步进（排版略松，但不影响正确性）。
		for ch in _glyph_cell:
			_glyph_adv[ch] = 0.62
		vp.queue_free()
		return
	_atlas_tex = ImageTexture.create_from_image(img)
	if _mmi != null:
		_mmi.material.set_shader_parameter("atlas", _atlas_tex)
	# 测每个字形的横向步进（用于排版）：从图集格子里扫墨迹宽度
	_measure_advances(img)
	vp.queue_free()


## 从已烘焙的图集里量每个字形的墨迹宽度 → 横向步进。
## 不做这步的话所有字按等宽排，数字串会显得松散。
func _measure_advances(img: Image) -> void:
	for ch in _glyph_cell:
		var gi: int = _glyph_cell[ch]
		var col := gi % ATLAS_COLS
		var row := gi / ATLAS_COLS
		var min_x := ATLAS_CELL
		var max_x := -1
		for y in ATLAS_CELL:
			for x in ATLAS_CELL:
				var px := img.get_pixel(col * ATLAS_CELL + x, row * ATLAS_CELL + y)
				if px.a > 0.1:
					if x < min_x:
						min_x = x
					if x > max_x:
						max_x = x
		if max_x < min_x:
			# 空白字形（空格）：给一个固定的窄步进
			_glyph_adv[ch] = 0.35
		else:
			_glyph_adv[ch] = float(max_x - min_x + 1) / float(ATLAS_CELL)


## EventBus.damage_popup → 飘字（与旧 Label 渲染器同一入口）
func _on_damage_popup(world_position: Vector3, amount: float, kind: String) -> void:
	if kind == "dodge":
		return
	if not _damage_numbers_enabled():
		return
	spawn(world_position, _format_text(amount, kind), kind)


func _damage_numbers_enabled() -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return true
	return bool(sm.get_setting("show_damage_numbers"))


## 在 3D 世界位置生成一段飘字。返回占用的实例数（0 = 未生成）。
##
## 世界坐标只在**生成时投影一次**——之后纯屏幕空间上浮，
## 与相机移动解耦（飘字不该跟着场景漂）。
func spawn(world_pos: Vector3, text: String, kind: String = "normal",
		color_override: Variant = null) -> int:
	if not _ready_done or text.is_empty():
		return 0
	var screen := _world_to_screen(world_pos)
	var size_px: float = float(KIND_SIZES.get(kind, 32))
	var scale: float = size_px / float(BAKE_FONT_SIZE)
	var color: Color = KIND_COLORS.get(kind, Color.WHITE) if color_override == null \
		else color_override

	# 排版：先算总宽，好让整串水平居中于落点
	var advs: Array[float] = []
	var total_w := 0.0
	for i in text.length():
		var ch := text.substr(i, 1)
		var a: float = float(_glyph_adv.get(ch, 0.5))
		advs.append(a)
		total_w += a
	var step_px: float = float(ATLAS_CELL) * scale
	var cursor: float = -total_w * step_px * 0.5
	var now := Time.get_ticks_msec() / 1000.0

	var used := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if not _glyph_cell.has(ch):
			# 未烘焙的字符：跳过（不占槽位），避免渲染出错误字形
			cursor += advs[i] * step_px
			continue
		var slot := _next_slot
		_next_slot = (_next_slot + 1) % CAPACITY
		# 实例变换只做平移（锚点）；缩放/偏移/上浮全在着色器里算，
		# 避免二者互相干扰（缩放会影响偏移量的语义）。
		_mm.set_instance_transform_2d(slot, Transform2D(0.0, screen))
		_mm.set_instance_custom_data(slot, Color(
			float(_glyph_cell[ch]),   # x = 图集格号
			now,                       # y = 出生时间
			cursor + advs[i] * step_px * 0.5,   # z = 该字形的横向偏移
			scale                      # w = 字号缩放
		))
		# 每个实例的 tint 走 instance color
		_mm.set_instance_color(slot, color)
		cursor += advs[i] * step_px
		used += 1
	_spawn_count += 1
	_live += used
	_instances_written += used
	return used


## 3D 世界位置 → 屏幕坐标
##
## **必须做视口缩放换算**：3D 世界跑在 `SubViewport`（640×360，像素化管线），
## 相机也在那个视口里，故 `unproject_position` 返回的是 **640×360 坐标系**；
## 而本渲染器挂在**根视口**（1280×720）的 CanvasLayer 上。
## 直接拿相机坐标当绘制位置会让伤害数字**整体缩到左上角一半处**
##（实机症状：数字不在敌人身上弹出）。
##
## 换算 = 本视口尺寸 / 相机视口尺寸（本例 1280/640 = 2）。
func _world_to_screen(world_pos: Vector3) -> Vector2:
	if _camera == null or not is_instance_valid(_camera):
		_camera = _find_camera()
	if _camera == null:
		return get_viewport().get_visible_rect().size * 0.5
	var p := _camera.unproject_position(world_pos)
	var cam_vp := _camera.get_viewport()
	if cam_vp == null:
		return p
	var from_size := cam_vp.get_visible_rect().size
	var to_size := get_viewport().get_visible_rect().size
	if from_size.x <= 0.0 or from_size.y <= 0.0:
		return p
	return Vector2(p.x * to_size.x / from_size.x, p.y * to_size.y / from_size.y)


## 伤害数字格式化（与旧 Label 渲染器同口径，保证切换前后显示一致）
func _format_text(amount: float, kind: String) -> String:
	var s := ""
	var abs_amount: float = abs(amount)
	if abs_amount >= 1000000.0:
		s = "%.1fM" % (amount / 1000000.0)
	elif abs_amount >= 1000.0:
		s = "%.1fK" % (amount / 1000.0)
	else:
		s = "%.0f" % amount
	if kind == "crit":
		s += "!"
	return s


func _find_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("camera")
	if nodes.size() > 0:
		return nodes[0] as Camera3D
	return get_viewport().get_camera_3d()


# ============================================================
# 测试 / 调试接口
# ============================================================

## 已烘焙的字符数
func glyph_count() -> int:
	return _glyph_cell.size()


## 累计生成的文本条数
func spawn_count() -> int:
	return _spawn_count


## 累计写入的实例数（每个字形算一个实例）
func instances_written() -> int:
	return _instances_written


## 图集纹理（测试用：可断言非空、有墨迹）
func atlas_texture() -> ImageTexture:
	return _atlas_tex


## MultiMesh（测试用：可断言实例数、读取实例数据）
func multimesh() -> MultiMesh:
	return _mm
