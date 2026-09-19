class_name ToonMaterial
extends RefCounted
## 卡通材质工厂 —— 全项目唯一的 toon 材质构造入口
##
## 为什么不挂在 MeshInstance3D 的材质槽上、而是运行时构造：
## 项目里几乎全部网格都是**脚本现建**的（地板/墙/敌人/道具都是
## `MeshInstance3D.new()`），没有 `.tscn` 可以挂材质资源，只能在建的时候给。
## 调用点集中在渲染层，不散落到各业务模块。
##
## **换到 ShaderMaterial 后，原先那批
## `material_override as StandardMaterial3D` 的写法全部会拿到 null 并静默失效**
## （as 失败不报错，只返回 null，后面 `if mat == null: return` 一挡就没了）。
## 受击闪红、前摇白光、毒怪绿光、隐身半透明四处都踩在这个坑上，
## 已统一改走本文件的 API。以后给这些物件加视觉反馈，也要走这里。

const TOON_SHADER_PATH := "res://rendering/shaders/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://rendering/shaders/model_outline.gdshader"

## 着色器只加载一次（首次用到时惰性加载）
static var _toon_shader: Shader = null
static var _outline_shader: Shader = null


## 惰性取 toon 着色器。用 load 而非 preload：preload 会让本文件在解析期
## 依赖着色器资源，无头模式下着色器未导入时会连带整个类解析失败。
static func _shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = load(TOON_SHADER_PATH) as Shader
	return _toon_shader


## 惰性取描边着色器
static func _outline() -> Shader:
	if _outline_shader == null:
		_outline_shader = load(OUTLINE_SHADER_PATH) as Shader
	return _outline_shader


## 造一支 toon 材质。
##
## color          —— 本色（原先 StandardMaterial3D.albedo_color 的位置）
## texture        —— 图集贴图，null 表示纯色
## texture_tint   —— 贴图在**时**用于替代 color 的染色系数。图集贴图是
##                   「亮底色 × 染色」的工作方式，直接拿主题色当 albedo_color
##                   乘上去会把亮度拉飞（floor_builder 里那段注释讲的就是这个），
##                   故两者分开传，由调用方先用 AtlasDefs.tint_for 算好
## emission       —— 自发光色，energy 为 0 时等于没有
## outline        —— 是否挂反壳描边
## outline_width  —— 描边视空间外扩量
static func create(color: Color = Color.WHITE, texture: Texture2D = null,
		texture_tint: Color = Color.WHITE, emission: Color = Color.BLACK,
		emission_energy: float = 0.0, outline: bool = true,
		outline_width: float = 0.012) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader()
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("use_albedo_texture", texture != null)
	if texture != null:
		mat.set_shader_parameter("albedo_texture", texture)
		mat.set_shader_parameter("albedo", texture_tint)
	mat.set_shader_parameter("emission_color", emission)
	mat.set_shader_parameter("emission_energy", emission_energy)
	if outline:
		mat.next_pass = create_outline(outline_width)
	return mat


## 只造描边 pass（一般不用单独调，create 里已经挂上）
static func create_outline(width: float = 0.012) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _outline()
	mat.set_shader_parameter("grow_amount", width)
	mat.set_shader_parameter("outline_color", Color.BLACK)
	return mat


# ============================================================
# 运行时改参（替代原先直接改 StandardMaterial3D 属性的写法）
# ============================================================

## 改本色。受击闪红、闪红复原都走这里
static func set_color(mat: ShaderMaterial, color: Color) -> void:
	if mat != null:
		mat.set_shader_parameter("albedo", color)


## 改自发光。energy <= 0 视为关闭
static func set_emission(mat: ShaderMaterial, color: Color, energy: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("emission_color", color)
	mat.set_shader_parameter("emission_energy", maxf(energy, 0.0))


## 取本色。闪红逻辑需要「先读出来再插值回去」
static func get_color(mat: ShaderMaterial) -> Color:
	if mat == null:
		return Color.WHITE
	return mat.get_shader_parameter("albedo")


## 模型半透明。
##
## **不能改材质里的 alpha**：toon.gdshader 写的是不透明 ALPHA，一旦在着色器
## 里写 ALPHA 就会让整支材质掉进透明队列（不写深度缓冲）——既拖慢场景几何，
## 又会让屏幕空间描边读到的深度缓冲缺这一块，边缘检测在隐身怪周围失效。
## 改走 `GeometryInstance3D.transparency`：Godot 对不透明材质做 alpha 混合，
## 且**保持写入深度**，两条通道都不受影响。
static func set_model_transparency(mesh: MeshInstance3D, alpha: float) -> void:
	if mesh != null:
		mesh.transparency = clampf(1.0 - alpha, 0.0, 1.0)


## 读模型当前的透明混合量（0 = 完全不透明）
static func get_model_transparency(mesh: MeshInstance3D) -> float:
	if mesh == null:
		return 0.0
	return mesh.transparency
