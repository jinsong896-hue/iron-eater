class_name DamageTextRenderer
extends CanvasLayer
## 伤害飘字渲染器 —— MassiveText 方案（单 draw call 海量文本）
## 纯 2D 屏幕空间：spawn 时 3D 世界坐标投影到屏幕一次，之后纯 2D 飘动+淡出
## 用 MultiMeshInstance2D + TextAtlas shader 渲染所有飘字

const MAX_INSTANCES := 64
const MAX_STRING_LEN := 8  # 伤害数字最多 8 位（含小数点/感叹号）
const FLOAT_SPEED := 80.0  # 屏幕像素/秒
const LIFETIME := 1.0

# 颜色配置（按 kind）
const KIND_COLORS := {
	"normal": Color(1.0, 1.0, 1.0, 1.0),
	"crit": Color(1.0, 0.3, 0.1, 1.0),
	"player": Color(1.0, 0.2, 0.2, 1.0),
	"aoe": Color(0.7, 0.3, 1.0, 1.0),
	"heal": Color(0.3, 1.0, 0.4, 1.0),
}
const KIND_SIZES := {
	"normal": 32,
	"crit": 40,
	"player": 32,
	"aoe": 32,
	"heal": 32,
}

var _mmi: MultiMeshInstance2D
var _mm: MultiMesh
var _shader_mat: ShaderMaterial
var _bake_result: Dictionary
var _pack_result: Dictionary
# 活跃飘字条目，每项含 pos/vel/elapsed/lifetime/str/kind/size
var _active: Array = []
var _strings_dirty := true  # 需要重新打包 string_tex
var _camera: Camera3D
var _font: Font
var _initialized := false


func _ready() -> void:
	layer = 10
	add_to_group("damage_renderer")
	# 默认字体（CanvasLayer 不是 Control，不能调用 get_theme_default_font）
	_font = ThemeDB.fallback_font
	# 订阅伤害事件：此前全链路无人监听 damage_popup，数字永远不显示
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("damage_popup"):
		bus.damage_popup.connect(_on_damage_popup)
	# 相机从父节点或场景找
	await _init_async()


## EventBus.damage_popup → 飘字。
## 受设置开关控制（设置面板可关）；"dodge" 是闪避提示，不算伤害数字，不显示。
func _on_damage_popup(world_position: Vector3, amount: float, kind: String) -> void:
	if kind == "dodge":
		return
	if not _damage_numbers_enabled():
		return
	spawn(world_position, amount, kind)


## 伤害数字是否开启（设置缺失时默认开）
func _damage_numbers_enabled() -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return true
	return bool(sm.get_setting("show_damage_numbers"))


## 异步初始化：烘焙图集 + 配 shader + 建 MultiMesh
func _init_async() -> void:
	# 找场景里的 Camera3D
	_camera = _find_camera()
	if _camera == null:
		push_warning("[DamageTextRenderer] 未找到 Camera3D，spawn 时无法投影")
		return

	# 烘焙图集（所有可能用到的字符）
	var samples := _generate_samples()
	var baker := GlyphAtlasBaker.new()
	add_child(baker)
	_bake_result = await baker.bake(samples, _font, 32)
	baker.queue_free()

	if _bake_result.is_empty():
		push_error("[DamageTextRenderer] 烘焙失败")
		return

	# 打包空字符串纹理（spawn 时再按需重新打包）
	_repack_strings([])

	# 建 MultiMesh + shader 材质
	_mmi = MultiMeshInstance2D.new()
	_mmi.name = "DamageTextMMI"
	add_child(_mmi)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.use_colors = true
	_mm.mesh = QuadMesh.new()
	_mm.instance_count = MAX_INSTANCES
	_mmi.multimesh = _mm

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load("res://rendering/shaders/TextAtlas.gdshader")
	_mmi.material = _shader_mat
	_apply_shader_params()
	_initialized = true


## spawn：在 3D 世界位置产生伤害数字
func spawn(world_pos: Vector3, amount: float, kind: String = "normal") -> void:
	if not _initialized:
		return
	var screen_pos := _world_to_screen(world_pos)
	if screen_pos == Vector2.ZERO and _camera:
		# 投影失败（相机看不到）仍用屏幕中心兜底
		screen_pos = get_viewport().get_visible_rect().size / 2.0

	var text := _format_text(amount, kind)
	var size := int(KIND_SIZES.get(kind, 32))
	_active.append({
		"pos": screen_pos,
		"vel": Vector2(randf_range(-20.0, 20.0), -FLOAT_SPEED),
		"elapsed": 0.0,
		"lifetime": LIFETIME,
		"str": text,
		"kind": kind,
		"size": size,
	})
	# 标记需要重新打包字符串
	_strings_dirty = true


func _process(delta: float) -> void:
	if not _initialized:
		return
	# 更新活跃飘字
	var i := 0
	while i < _active.size():
		var entry: Dictionary = _active[i]
		entry.elapsed += delta
		entry.pos += entry.vel * delta
		if entry.elapsed >= entry.lifetime:
			_active.remove_at(i)
		else:
			i += 1

	# 重新打包字符串（如果有新飘字）
	if _strings_dirty:
		_repack_strings(_active.map(func(e): return e.str))
		_strings_dirty = false

	# 更新 MultiMesh 实例缓冲
	_update_instances()


# ============================================================
# 内部
# ============================================================

## 生成烘焙用的字符样本（0-9 + 小数点 + 感叹号 + 负号）
func _generate_samples() -> Array:
	var samples := []
	for i in 10:
		samples.append(str(i))
	samples.append(".")
	samples.append("!")
	samples.append("-")
	samples.append("+")
	# 大伤害可能需要的单位
	samples.append("K")
	samples.append("M")
	return samples


## 找场景里的 Camera3D
func _find_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("camera")
	if nodes.size() > 0:
		return nodes[0] as Camera3D
	# 兜底：找当前视口相机
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null


## 3D 世界坐标 → 2D 屏幕坐标
func _world_to_screen(world_pos: Vector3) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(world_pos)


## 格式化伤害数字为字符串
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


## 重新打包字符串纹理
func _repack_strings(strings: Array) -> void:
	if _bake_result.is_empty():
		return
	_pack_result = StringTexturePacker.pack(
		strings,
		_bake_result.glyph_to_index,
		_bake_result.advances,
		MAX_STRING_LEN
	)


## 应用 shader 参数
func _apply_shader_params() -> void:
	if _shader_mat == null or _bake_result.is_empty():
		return
	_shader_mat.set_shader_parameter("text_atlas", _bake_result.atlas)
	_shader_mat.set_shader_parameter("atlas_grid", float(_bake_result.grid))
	_shader_mat.set_shader_parameter("atlas_cell_px", float(_bake_result.cell))
	_shader_mat.set_shader_parameter("atlas_size", 4096.0)
	_shader_mat.set_shader_parameter("advance_tex", _bake_result.advance_tex)
	_shader_mat.set_shader_parameter("advance_tex_cols", float(_bake_result.grid))
	# 8 种颜色 tint（前 4 种用 KIND_COLORS，其余白）
	var tints: Array = []
	var kinds := ["normal", "crit", "player", "aoe"]
	for k in kinds:
		tints.append(KIND_COLORS.get(k, Color.WHITE))
	for _i in range(4):
		tints.append(Color.WHITE)
	_shader_mat.set_shader_parameter("text_tints", tints)
	_shader_mat.set_shader_parameter("per_glyph_tint", 0.0)
	_shader_mat.set_shader_parameter("anim_enabled", 0.0)
	_shader_mat.set_shader_parameter("burst_enabled", 0.0)
	_shader_mat.set_shader_parameter("max_string_len", float(MAX_STRING_LEN))


## 更新 MultiMesh 实例缓冲（每帧）
func _update_instances() -> void:
	if _mm == null:
		return
	# 重新打包后更新 string_tex 参数
	if not _pack_result.is_empty():
		_shader_mat.set_shader_parameter("string_tex", _pack_result.string_tex)
		_shader_mat.set_shader_parameter("cum_tex", _pack_result.cum_tex)
		_shader_mat.set_shader_parameter(
			"strings_tex_cols", float(StringTexturePacker.STRING_TEX_WIDTH)
		)
		_shader_mat.set_shader_parameter("string_tex_rows", float(_pack_result.rows))
		_shader_mat.set_shader_parameter("cum_tex_cols", float(StringTexturePacker.STRING_TEX_WIDTH))
		_shader_mat.set_shader_parameter("cum_tex_rows", float(_pack_result.cum_rows))

	# 写每个实例的 transform + color
	var count := mini(_active.size(), MAX_INSTANCES)
	for i in MAX_INSTANCES:
		if i >= count:
			_mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
			_mm.set_instance_color(i, Color(0, 0, 0, 0))  # len=0 → shader discard
			continue
		var entry: Dictionary = _active[i]
		# 颜色：R=字符串长度/255, G=size 相关, B=style 索引, A=alpha
		var str_len: int = entry.str.length()
		var style := _kind_style_index(entry.kind)
		var alpha: float = 1.0 - (entry.elapsed / entry.lifetime)
		var color := Color(
			float(str_len) / 255.0,
			float(entry.size) / 64.0,
			float(style) / 255.0,
			alpha
		)
		_mm.set_instance_color(i, color)
		# transform：位置 + 缩放（用 size 控制大小）
		var scale_factor := float(entry.size) / 32.0
		var t := Transform2D().scaled(Vector2.ONE * scale_factor)
		t.origin = entry.pos
		_mm.set_instance_transform_2d(i, t)


## kind → style 索引（对应 text_tints 数组）
func _kind_style_index(kind: String) -> int:
	var kinds := ["normal", "crit", "player", "aoe"]
	var idx := kinds.find(kind)
	return idx if idx >= 0 else 0
