class_name PlayerFx
extends Node
## 玩家的视觉反馈组件 —— 受击闪红 + 挥砍扇形特效池。
##
## ## 为什么独立成组件
##
## 这两块（闪红、挥砍特效）是**纯表现**：只读玩家状态（朝向/位置/模型节点），
## 不参与任何战斗判定。把它们从 `player.gd` 里拿出来，是为了让
## "改视觉"与"改战斗"不再互相牵连——改扇形颜色不该翻 2000 行的战斗文件。
##
## ## 闪红
##
## 受击时把模型材质染红，前 40% 全红、剩余时间线性退回本色。
## **材质是卡通着色器（ShaderMaterial）**，改色必须走 `ToonMaterial.set_color`——
## 早期写成 `as StandardMaterial3D` 会静默拿到 null，表现为"扣了血却没有视觉反馈"。
##
## ## 挥砍扇形
##
## 三层缓存，为的是**连打时不产生 GC 尖峰**：
##   1. 材质按颜色缓存（渐隐改 alpha，故每种颜色必须独立实例）
##   2. 网格按 (reach, half_angle) 缓存（形状只由这两者决定）
##   3. 节点用池复用（避免每次 add_child/queue_free）
##
## 渐隐走 tween 调制**材质的 albedo_color.a**（不是节点 modulate）——
## 调完必须复位 alpha，否则下一个复用到该颜色的节点会直接隐形。
## 见 `_spawn_slash_visual` 里的复位那行。

## 受击闪红时长（秒）
const HIT_FLASH_DURATION := 0.18

## 闪红颜色（与本色按时间插值）
const FLASH_COLOR := Color(1.0, 0.15, 0.15)

## 玩家本体（构造时注入；本组件只读它的位置/朝向）
var player: Node3D = null

## 模型节点（player.tscn 的 Model）。闪红就改它的材质。
var _model: MeshInstance3D = null
## 闪红剩余时间
var _flash_timer := 0.0
## 模型本色（闪红结束后恢复用）
var _base_color := Color.WHITE

# 挥砍特效：材质/网格静态缓存 + 节点池
static var _slash_mat_cache := {}
static var _slash_mesh_cache := {}
var _slash_pool: Array[MeshInstance3D] = []
var _slash_free: Array[MeshInstance3D] = []


## 装配：注入玩家、接管模型节点。
##
## 模型节点的材质在这里**换成本项目的卡通材质**（原模型带的是内置材质），
## 这是闪红可控的前提——故这段必须在组件里，不能留在 player 侧。
func setup(owner_player: Node3D) -> void:
	player = owner_player
	_model = player.get_node_or_null("Model") as MeshInstance3D
	if _model == null:
		return
	var src := _model.get_active_material(0) as StandardMaterial3D
	if src != null:
		_base_color = src.albedo_color
	else:
		_base_color = Color.WHITE
	_model.material_override = ToonMaterial.create(_base_color)


## 每帧推进闪红衰减（由 player 的 _physics_process 转发）
func tick(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	_update_flash()


## 触发一次受击闪红
func flash() -> void:
	_flash_timer = HIT_FLASH_DURATION
	_update_flash()


## 闪红剩余时间（供 HUD / 测试判断反馈是否在跑）
func flash_timer() -> float:
	return _flash_timer


## 模型节点（闪红作用的那个 MeshInstance3D）
func model() -> MeshInstance3D:
	return _model


## 受击闪红：前 40% 全红，剩余时间线性退回本色
func _update_flash() -> void:
	if _model == null or _model.material_override == null:
		return
	# 卡通材质是 ShaderMaterial，改色走 ToonMaterial 的 set_color
	# （原先 as StandardMaterial3D 的写法在这里会静默拿到 null）
	var mat := _model.material_override as ShaderMaterial
	if mat == null:
		return
	if _flash_timer <= 0.0:
		ToonMaterial.set_color(mat, _base_color)
		return
	var t := _flash_timer / HIT_FLASH_DURATION
	var blend := clampf(t / 0.4, 0.0, 1.0)
	ToonMaterial.set_color(mat, FLASH_COLOR.lerp(_base_color, 1.0 - blend))


## 播放一次扇形挥砍特效。
##
## reach/half_angle 决定扇形形状与大小；color 决定配色
##（终结技金黄 / 冲撞橙红 / 落地斩冰蓝 / 普攻淡黄，见各调用点）。
func spawn_slash(reach: float, half_angle: float,
		color: Color = Color(1, 1, 0.85, 0.5)) -> void:
	var node := _acquire_slash_node()
	node.mesh = _get_slash_mesh(reach, half_angle)
	# 每种颜色一个独立缓存的材质实例（渐隐会改它的 alpha，故不能与其他颜色共用）
	var mat := _get_slash_material(color)
	# 复用前复位（上次渐隐把 alpha 调成 0、阈值调到 1，不复位则本次直接隐形）
	mat.albedo_color = color
	mat.alpha_scissor_threshold = clampf(1.0 - color.a, 0.05, 0.95)
	node.material_override = mat
	node.visible = true

	var facing: Vector3 = player.get("_facing")
	var rot_y := atan2(facing.x, facing.z)
	node.position = player.global_position + Vector3(0, 1.0, 0)
	node.rotation.y = rot_y

	# 渐隐：调该颜色专属材质的 alpha，结束后归还池。
	#
	# **必须同步调 alpha_scissor_threshold**：材质用的是 HASH（抖动透明，
	# 见 material_library.create_translucent_material 的说明），
	# 它靠**固定阈值**决定每个像素露不露，光改 alpha 不会让画面变淡。
	# 阈值 = 1 - alpha，alpha 降到 0 时阈值升到 1 → 全部裁掉 = 完全消失。
	var tween := player.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_property(mat, "alpha_scissor_threshold", 1.0, 0.12)
	tween.chain().tween_callback(func(): _release_slash_node(node))


## 取一个挥砍节点（池空则新建）
func _acquire_slash_node() -> MeshInstance3D:
	var node: MeshInstance3D
	if _slash_free.is_empty():
		node = MeshInstance3D.new()
		node.name = "SlashVisual"
		_slash_pool.append(node)
		player.get_parent().add_child(node)
	else:
		node = _slash_free.pop_back()
		node.visible = true
	return node


## 归还挥砍节点（隐藏而非销毁，供下次复用）
func _release_slash_node(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false
	if not _slash_free.has(node):
		_slash_free.append(node)


## 材质按颜色缓存（r/g/b 作键；alpha 由渐隐 tween 控制，故键里不含 a）
static func _get_slash_material(color: Color) -> StandardMaterial3D:
	var key := "%.3f_%.3f_%.3f" % [color.r, color.g, color.b]
	if _slash_mat_cache.has(key):
		return _slash_mat_cache[key]
	var mat := MaterialLibrary.create_translucent_material(color, 1.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slash_mat_cache[key] = mat
	return mat


## 扇形网格按 (reach, half_angle) 缓存（形状只由这两个参数决定）
static func _get_slash_mesh(reach: float, half_angle: float) -> ArrayMesh:
	var key := "%.2f_%.3f" % [reach, half_angle]
	if _slash_mesh_cache.has(key):
		return _slash_mesh_cache[key]

	var steps := 12
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(steps):
		var a0 := -half_angle + (2.0 * half_angle * i / steps)
		var a1 := -half_angle + (2.0 * half_angle * (i + 1) / steps)
		var base := verts.size()
		verts.push_back(Vector3.ZERO)
		verts.push_back(Vector3(sin(a1) * reach, 0.0, cos(a1) * reach))
		verts.push_back(Vector3(sin(a0) * reach, 0.0, cos(a0) * reach))
		indices.push_back(base + 0)
		indices.push_back(base + 1)
		indices.push_back(base + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_slash_mesh_cache[key] = mesh
	return mesh
