extends CanvasLayer
class_name DamageTextRenderer
## 伤害飘字渲染器 —— Label 实现
##
## 历史：本节点曾用 MultiMeshInstance2D + 字形图集着色器（MassiveText 方案）
## 渲染飘字，但那条链路在实机上始终不出字。逐环节静态检查过：
## 信号订阅、图集烘焙（数字 0-9 已采样）、着色器参数绑定、uniform 名字、
## 实例缓冲写入、着色器 len/instance_color 解码、纹理布局与索引公式、
## QuadMesh 尺寸 —— 全部正确，而 headless（dummy 渲染器）无法验证渲染结果，
## 因此无法定位到具体是哪一步在实机上失效。
##
## 伤害数字每秒只有个位数，根本不需要「单 draw call 渲染海量文本」这套优化。
## 改用最朴素的 Label：一定能渲染，性能代价可忽略。
##
## 注意：本节点删除了 MultiMesh/图集相关字段（_mm/_mmi/_shader_mat/
## _bake_result/_pack_result/_initialized）。依赖这些字段的测试已同步更新。

const FLOAT_SPEED := 60.0   # 屏幕上浮速度（像素/秒）
const LIFETIME := 1.0       # 存活时长（秒）
const MAX_LABELS := 64      # 同时存在的飘字上限

# 颜色配置（按 kind）
const KIND_COLORS := {
	"normal": Color(1.0, 1.0, 1.0, 1.0),
	"crit": Color(1.0, 0.3, 0.1, 1.0),
	"player": Color(1.0, 0.2, 0.2, 1.0),
	"aoe": Color(0.7, 0.3, 1.0, 1.0),
	"heal": Color(0.3, 1.0, 0.4, 1.0),
	"armor": Color(1.0, 0.85, 0.3, 1.0),   # 霸体减伤
}
const KIND_SIZES := {
	"normal": 32,
	"crit": 40,
	"player": 32,
	"aoe": 32,
	"heal": 32,
	"armor": 28,
}

var _camera: Camera3D = null
var _active: Array[Dictionary] = []   # 活跃飘字记录（测试读取）
var _pool: Array[Label] = []          # Label 池（与 _active 同序复用）
var _count := 0                       # 累计产生次数（测试读取）


func _ready() -> void:
	layer = 10
	add_to_group("damage_renderer")
	_camera = _find_camera()
	# 订阅伤害事件
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("damage_popup"):
		bus.damage_popup.connect(_on_damage_popup)


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


## spawn：在 3D 世界位置产生伤害数字（投影到屏幕一次，之后纯 2D 飘动）
func spawn(world_pos: Vector3, amount: float, kind: String) -> void:
	var screen_pos := _world_to_screen(world_pos)
	var text := _format_text(amount, kind)
	var size_px := int(KIND_SIZES.get(kind, 32))

	_active.append({
		"pos": screen_pos,
		"vel": Vector2(randf_range(-20.0, 20.0), -FLOAT_SPEED),
		"elapsed": 0.0,
		"lifetime": LIFETIME,
		"str": text,
		"kind": kind,
		"size": size_px,
	})
	_count += 1

	# 超出上限时丢弃最早的
	while _active.size() > MAX_LABELS:
		_active.remove_at(0)

	_sync_labels()


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var i := 0
	while i < _active.size():
		var entry: Dictionary = _active[i]
		entry.elapsed += delta
		entry.pos += entry.vel * delta
		if entry.elapsed >= entry.lifetime:
			_active.remove_at(i)
		else:
			i += 1
	_sync_labels()


## 把 _active 同步到 Label 池（复用节点，不每帧新建）
func _sync_labels() -> void:
	# 按需扩容
	while _pool.size() < _active.size():
		var lb := Label.new()
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lb)
		_pool.append(lb)

	for i in _pool.size():
		var lb: Label = _pool[i]
		if i >= _active.size():
			lb.visible = false
			continue
		var entry: Dictionary = _active[i]
		var alpha: float = 1.0 - (float(entry.elapsed) / float(entry.lifetime))
		lb.text = str(entry.str)
		lb.add_theme_font_size_override("font_size", int(entry.size))
		lb.add_theme_color_override("font_color", KIND_COLORS.get(entry.kind, Color.WHITE))
		# 水平居中到飘字位置（用文本实际宽度的一半回退）
		var half_w: float = lb.get_minimum_size().x * 0.5
		lb.position = Vector2(entry.pos.x - half_w, entry.pos.y)
		lb.modulate = Color(1, 1, 1, clampf(alpha, 0.0, 1.0))
		lb.visible = true


## 3D 世界位置 → 屏幕坐标
func _world_to_screen(world_pos: Vector3) -> Vector2:
	if _camera == null:
		_camera = _find_camera()
	if _camera == null:
		return get_viewport().get_visible_rect().size * 0.5
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


## 找场景里的 Camera3D
func _find_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("camera")
	if nodes.size() > 0:
		return nodes[0] as Camera3D
	# 回退：全局搜一个
	var found := tree.get_nodes_in_group("player")
	for n in found:
		var cam := (n as Node).get_viewport().get_camera_3d() if n is Node else null
		if cam:
			return cam
	return get_viewport().get_camera_3d()
