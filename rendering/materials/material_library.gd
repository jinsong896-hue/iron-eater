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


## 切换主题
static func set_theme(theme: String) -> void:
	_current_theme = theme


## 获取当前主题
static func get_theme() -> String:
	return _current_theme