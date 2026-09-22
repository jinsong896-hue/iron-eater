class_name MaterialLibrary
extends RefCounted
## 材质库 —— HD-2D 重构版
## 统一管理所有材质资源，支持主题切换

static var _materials := {}
static var _current_theme := "crypt"


## 注册材质
static func register(name: String, material: Material) -> void:
	_materials[name] = material


## 获取材质
static func get_material(name: String) -> Material:
	return _materials.get(name, null)


## 获取或创建默认材质
static func get_or_default(name: String, default_color: Color) -> Material:
	if _materials.has(name):
		return _materials[name]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = default_color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	_materials[name] = mat
	return mat


## 创建像素风材质
static func create_pixel_material(texture_path: String, color: Color = Color.WHITE) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC

	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var tex := ResourceLoader.load(texture_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex:
			mat.albedo_texture = tex

	return mat


## 创建发光材质
static func create_emissive_material(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## 创建透明材质（Alpha Scissor）
static func create_alpha_scissor_material(texture_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var tex := ResourceLoader.load(texture_path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if tex:
			mat.albedo_texture = tex

	return mat


## 创建**在像素化管线下可见**的半透明 3D 材质。
##
## ## 为什么不能直接用 `TRANSPARENCY_ALPHA`
##
## 本项目 3D 世界跑在 `SubViewport` + 像素后处理里。实测（同位置同色，
## 只换 transparency 模式）：
##
## | 模式 | 可见 |
## |---|---|
## | `TRANSPARENCY_ALPHA` | **不可见** |
## | `TRANSPARENCY_DISABLED` | 可见（但不透明）|
## | `TRANSPARENCY_ALPHA_SCISSOR` | 可见（硬边，无半透明观感）|
## | `TRANSPARENCY_ALPHA_HASH` | **可见且半透明** ✅ |
##
## 根因未完全定位（后处理只取 `SCREEN_TEXTURE.rgb`、不碰 alpha），
## 但四种模式的实测结果稳定可复现。**HASH（抖动透明）是唯一兼顾
## 「可见 + 半透明」的选项**，且抖动是硬边裁剪，与像素美术天然契合。
##
## 实机症状（修复前）：陷阱区、传送门、隐藏墙裂缝**全部隐形**。
##
## `color.a` 越低 → 抖动阈值越高 → 露出的地面越多（观感越淡）。
static func create_translucent_material(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	mat.alpha_scissor_threshold = clampf(1.0 - color.a, 0.05, 0.95)
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = emission_energy
	return mat


## 切换主题
static func set_theme(theme: String) -> void:
	_current_theme = theme


## 获取当前主题
static func get_theme() -> String:
	return _current_theme